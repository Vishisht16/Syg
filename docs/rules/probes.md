# Health probes

Probes that restart healthy pods, or send traffic to pods that are not ready.

## shared-probe-endpoint

`CHK-PRB-002` · warning · checked offline

A brief downstream outage restarts every replica simultaneously, destroying capacity at the exact moment the system is already degraded.

### What you see

A brief outage of something *downstream* restarts every replica of this service at
once.

The sequence is worth walking, because each step is individually reasonable. A team
writes one health endpoint, `/healthz`, and does the responsible thing: it checks
that the database connection is alive, because a service that cannot reach its
database is not healthy. Both probes are pointed at it. This works for months.

Then the database has a forty-second failover.

Every replica's `/healthz` starts failing simultaneously, because they all depend on
the same database. Readiness failing is *correct*: those pods genuinely cannot serve,
and removing them from the Service is the right response. But liveness is failing
too, and liveness does not mean "cannot serve". It means "this process is broken,
kill it". So the kubelet restarts every replica.

Now the database recovers, and the service does not, because the entire fleet is
restarting at once: cold caches, a thundering herd of new connections against a
database that just came back, and a rollout of pods that all fail their startup at
the same moment. A forty-second dependency blip becomes a multi-minute full outage,
and the logs show the application being killed while it was reporting the truth.

The failure destroys capacity *precisely* when the system is already degraded, which
is the worst possible time for it.

### Why it happens

The two probes cause different actions, and the difference is the whole point.

**Readiness** controls Service membership. A pod failing readiness is removed from
the Endpoints/EndpointSlice for its Services, so no new traffic reaches it. The pod
keeps running, keeps its state, and rejoins when it passes again. Failing readiness
is *recoverable and cheap*.

**Liveness** causes the kubelet to kill the container and restart it, subject to the
pod's restart policy and back-off. Failing liveness is *destructive*: the process is
gone, in-flight requests with it.

The documentation is explicit that liveness is for the case where a process is
wedged (deadlocked, unable to make progress), and that restarting is the only
remedy. A dependency being unavailable is not that case. The process is fine; the
world around it is not, and killing it does not improve the world.

So one endpoint cannot answer both questions correctly, because the questions have
different right answers whenever a dependency is down. The moment the endpoint
checks anything external, it becomes wrong as a liveness signal.

### What Syg catches

A container whose liveness and readiness probes point at the same endpoint.

### Why Syg checks rather than prevents

Because both probes are legitimate, one endpoint per service is legitimate, and the
combination is only *usually* wrong.

There is a case where sharing is harmless: an endpoint that checks nothing but
whether the process can serve a response. If `/healthz` is a static `200 OK`, using
it for both probes is fine: the liveness signal is honest and the readiness signal
is merely weak. Syg cannot see what the endpoint does, so it cannot distinguish that
case from the dangerous one, and it does not pretend to. The diagnostic is a
`warning` and its wording says *if* that endpoint checks a dependency.

That is also why the suggestion is shaped the way it is: it does not say "use two
endpoints", it says give liveness a trivial one and let readiness be the one that
checks dependencies. The asymmetry is the actual lesson.

**Why this is the strongest single case for checking the whole graph.** The
rule is cheap to state and common: 12.5% of the 48 configurations studied had it. But the reason
it is the strongest case is what it demonstrates about *where the information lives*.
Nothing about this container is individually invalid: a schema validator sees two
well-formed probes. The defect exists only in the relationship between two fields
that a per-field validator has no reason to compare, and its consequence is not
local at all: it is a correlated, fleet-wide restart triggered by something in a
different system entirely. That is the shape of failure this project exists to
argue about: valid objects, broken relationship, silence until an incident.

### Kubernetes versions

Verified against the kubernetes.io documentation for configuring liveness, readiness
and startup probes, including its guidance that liveness probes should not depend on
external services and its description of the distinct effect of each probe type
(checked 2026-08). Stable across supported versions.

### What Syg does not claim

Syg compares the probes' *endpoints*, not their behaviour. It cannot know whether
`/healthz` checks a database, and it cannot tell you that two *different* endpoints
are both dependency-checking, which is the same failure with the check evaded.

Probe timing sufficiency (`initialDelaySeconds`, `timeoutSeconds` against real
startup and response latency) is not decidable from source and is documented as
Tier 3; `CHK-PRB-004` covers the structural parts of timing only.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a probe's timing is sufficient (initialDelaySeconds, timeoutSeconds against real startup and response latency) depends on application behaviour under load and is not statically decidable. Syg checks structure and points you at observability.

## liveness-checks-dependency

`CHK-PRB-003` · warning · checked offline

A brief outage of a database or downstream service fails every replica's liveness probe at once, and the kubelet restarts them all: capacity is destroyed while the dependency is already degraded, and the restarts add load as it recovers.

### What you see

The database has a thirty-second blip. Every replica's liveness probe fails
together, and after `failures` attempts the kubelet restarts every container in
the Deployment at once. The service goes from degraded to down. When the
database returns, it is met by every replica reconnecting and warming caches at
the same moment, the thundering herd that makes recovery slower.

### Why it happens

A failed liveness probe makes the kubelet kill and restart the container. That
is the right response to a wedged process: a deadlock, an exhausted event loop.
It cures nothing outside the process. A failed readiness probe only removes the
pod from Service endpoints, the right response to "I cannot serve right now". A
dependency check belongs in readiness, where failing it sheds traffic instead of
destroying capacity.

### What Syg catches

A liveness probe whose HTTP path names something outside the process: a database
(`/health/db`), a cache (`redis`), a broker, or `upstream`, `dependencies`,
`external`. It also catches a readiness-style endpoint (`/ready`, `/readyz`),
which by convention is the one that checks dependencies. For an exec probe, only
the generic words count (`upstream`, `dependencies`, `external`). A database
tool in a command is how a database checks itself: a PostgreSQL that runs
`pg_isready -h 127.0.0.1` as liveness is correct, and must not be reported. So the
exec heuristic is narrowed
for it.

**This is a heuristic, and says so.** It reads the words in the path, not the
handler behind it. A `/health/db` endpoint that checks nothing outside the
process is a misleading name, not a bug, and the warning can be ignored or
turned off in `syg.yaml`.

### Why Syg checks rather than prevents

Syg cannot see what an endpoint does. A probe is a port and a path, and the
handler is application code. The rule can only read names, so it is a warning
over a heuristic. A prevention would need the language to know what a handler
checks, which no manifest states.

### Kubernetes versions

Probe semantics are stable across every supported release. Checked against the
kubernetes.io liveness, readiness and startup probe documentation for 1.32. The
restart behaviour on liveness failure is exercised on a real cluster.

### What Syg does not claim

That the endpoint checks a dependency, or that it does not. That an endpoint
named `/livez` is safe: a liveness handler can call the database under any name.
Whether your dependencies ever fail long enough to trip `failures`. That is
Tier 3.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## slow-start-without-startup-probe

`CHK-PRB-004` · info · checked offline

A fixed initial delay is wrong both ways: a start slower than it gets the container killed in a restart loop, and every start faster than it leaves a wedged process unwatched for the whole delay.

### What you see

A fixed delay is wrong in both directions. When a start takes longer than the
delay, for example a cold cache, a slow volume or a migration, liveness starts
failing before the program can answer. The kubelet restarts it, and the next
start is just as slow: a CrashLoopBackOff that looks like a bug in the program.
When a start is faster, which is most of the time, a process that wedges in
those first seconds goes unwatched for the whole delay, on every restart.

### Why it happens

While a startup probe exists and has not yet succeeded, the kubelet runs neither
liveness nor readiness. It allows the program up to `failures × every` to answer
once, then hands over to liveness at once. `initialDelaySeconds` is a fixed wait
before the first liveness check, the same on every start whatever the program is
doing.

### What Syg catches

A liveness probe with `after` (initialDelaySeconds) of 30 seconds or more, on a
container with no startup probe.

### Why Syg checks rather than prevents

A long delay is not invalid, and Syg does not know how long the program takes to
start: that is a measurement of the running system (Tier 3). Rewriting the probe
into a startup probe would choose a budget for the author. So the rule is
structural advice at info severity, with the startup probe it suggests sized to
cover the delay the author chose.

### Kubernetes versions

Startup probes are GA since Kubernetes 1.20. Checked against the kubernetes.io
probe documentation for 1.32.

### What Syg does not claim

Syg does not know the real start time, so the 30-second threshold is a
judgement, not a measurement. The suggested `failures` count covers the written
delay; it is not a recommendation for the program's actual start.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-startup-probes

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a startup probe's budget, or a liveness delay, is long enough depends on how long the application really takes to start, under real load and on real nodes, and is not statically decidable. Syg checks that slow starts use a startup probe, and points you at observability.

## missing-readiness-probe

`CHK-PRB-005` · warning · checked offline

Every rollout produces a burst of errors: the Service adds each new pod to its endpoints the moment the container starts, before the application can serve.

### What you see

Every rollout produces a burst of errors, and the burst is always blamed on
something else.

Without a readiness probe, a pod becomes Ready the moment its containers are
running, which is when the process has started, not when it can serve. The Service
adds it to the endpoints immediately, and real user traffic arrives while the
application is still loading configuration, warming a cache, establishing its
database pool, or running whatever its framework does before the first request
handler is live.

So each new pod in a rolling update takes a slice of traffic and fails it. The error
rate spikes for a few seconds per pod, the deploy completes, the graph returns to
normal, and the incident is written off as "a blip during the deploy", which it is,
every single time, forever. The cost is paid on every release rather than once.

The same gap makes a rollout unsafe in the other direction: with no readiness signal
the rollout has nothing to wait on, so a broken new version replaces a working one
at full speed instead of stalling on the first unready pod.

### Why it happens

A pod's `Ready` condition determines its membership in the Endpoints and
EndpointSlices of every Service selecting it. `kube-proxy` (or an equivalent
dataplane) programs its rules from those endpoints.

When a container declares no readiness probe, the kubelet reports it Ready as soon
as it is running. There is no default probe and no inference from ports: Kubernetes
has no way to know when your application is prepared to serve, so it assumes
immediately.

A rolling update consults readiness to decide when a new pod counts toward
`maxSurge`/`maxUnavailable`. With every pod Ready on start, those parameters
constrain nothing.

### What Syg catches

A workload that some Service routes to, with no readiness probe on its container.

In a study of 48 real configurations, mostly public Helm charts, 25.0% had this
mistake: a quarter of everything measured.

### Why Syg checks rather than prevents

Because "receives traffic" is not something the language can require a probe for
without also requiring it where it makes no sense.

Plenty of workloads legitimately have no readiness probe: a queue consumer with no
Service, a batch job, a workload whose readiness genuinely is "the process started".
Making the probe mandatory would force a meaningless one into those, and a
meaningless probe is worse than none: it looks like a signal and is not.

**This rule is a graph traversal, and that is the interesting part.** "Receives
traffic" is not a property of the pod spec; you cannot determine it by reading the
Deployment, no matter how carefully. It means *some Service selects this workload*,
which is an edge between two objects that a per-object linter never holds at the
same time. Syg answers it with `workloadFor()` over the derived selector (the same
traversal `CHK-NET-003` uses), so the rule fires exactly on the workloads for which
the question makes sense.

The headless Service governing a StatefulSet is deliberately excluded: it exists to
give pods stable DNS identity, not to load-balance traffic to them, so its presence
is not evidence that anything is routed here.

### Kubernetes versions

Verified against the kubernetes.io documentation for probes and for Service
endpoints, including the statement that a container without a readiness probe is
considered ready once running (checked 2026-08). Stable across supported versions.

### What Syg does not claim

Syg knows a Service selects this workload. It does not know whether that Service
actually receives requests, nor whether your application has any meaningful notion of
"ready" beyond having started.

It also cannot judge a probe that exists but is wrong: a readiness endpoint that
returns 200 before the application can serve satisfies this rule and produces exactly
the symptom above. Probe timing sufficiency is documented as Tier 3, not decidable
from source.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- https://kubernetes.io/docs/concepts/services-networking/service/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

### Where this stops

Whether a readiness endpoint reports readiness *truthfully* (returning 200 only once the application can serve) is a property of your code, not your configuration.

