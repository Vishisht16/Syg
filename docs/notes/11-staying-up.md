# Chapter 11: Staying Up

An engineer runs a routine command to empty a machine so it can be upgraded. It is
the most ordinary operation in cluster administration: thousands of people do it
every day. The command prints a line saying it is waiting, and then it waits. And
waits. Twenty minutes later it is still waiting, and nothing anywhere is broken:
every service is healthy, every dashboard is green, the machine is idle apart from
one stubborn Pod that refuses to leave. The upgrade is blocked. The whole fleet
rollout behind it is blocked. Nobody can find an error, because there is no error.

This chapter is about that class of failure, and it is where the most expensive
operational mistakes in Kubernetes live. Two of them in particular are worth
learning until they are instinct, because they share a cruel property: both are
caused by a setting that was *added to improve reliability*, and both make things
catastrophically worse in a way that produces no error message at all.

## Two kinds of disruption, and only one you can control

Start with a distinction that governs everything else here. Your Pods get destroyed
for two fundamentally different kinds of reasons.

An **involuntary disruption** is one nobody chose. The physical machine fails. The
kernel panics. The network partitions and the machine drops out of the cluster. Some
hardware, somewhere, dies. These are the failures we usually mean by "failure," and
the honest thing to say about them is that you cannot prevent them; you can only
build software that survives them, which is what replicas and reconciliation are
for.

A **voluntary disruption** is one someone deliberately initiated. An administrator
empties a machine for maintenance. The cluster shrinks itself because traffic is low
and a machine is no longer worth paying for. An operator removes a Pod to make room
for something else. These are *planned* removals, done by people or automation acting
on purpose, and, crucially, they are the ones you can negotiate with.

The reason this distinction is load-bearing: **Kubernetes gives you a mechanism to
constrain voluntary disruptions, and no mechanism at all to constrain involuntary
ones.** A machine that catches fire does not consult your policies. But the process
of deliberately emptying a machine *does*, and that is the entire subject of the next
two sections.

## Draining, and the Eviction API

Emptying a machine has a name: **draining** it. The administrator asks the system to
remove all the Pods from a particular machine so it can be rebooted, upgraded, or
decommissioned. The Pods that are removed will be noticed as missing by their
controllers, which, as Chapter 6 established, will simply create replacements
elsewhere. That is the whole beauty of the design: maintenance becomes routine
because replacement is routine.

But a drain does not just delete Pods. It requests their removal through the
**Eviction API**, a deliberately more polite mechanism than deletion, and the
politeness is the point: an eviction request *can be refused*. Deletion cannot. This
is the hook on which all disruption safety hangs, and it exists so that you can
express a constraint like "you may take my Pods away, but not so many at once that my
service goes dark."

That constraint has an object of its own.

## The PodDisruptionBudget

A **PodDisruptionBudget** (a *budget* for how much disruption you can tolerate) is
a policy attached to a set of Pods, saying how many of them must remain available
while voluntary disruptions are happening. You express it one of two ways: either
`minAvailable`, "at least this many must stay up," or `maxUnavailable`, "at most this
many may be down at once."

The mechanism is exact. When the Eviction API receives a request to remove a Pod, it
consults any budget covering that Pod and asks: if I grant this, will the number of
healthy Pods still satisfy the budget? If yes, the eviction proceeds. If no, **the
eviction is refused**, and the drain command (which is politely retrying, not
failing) waits and asks again, and again, hoping the situation improves.

The documentation gives the canonical example: a Deployment with five replicas and a
budget permitting four available at a time lets the Eviction API remove one Pod at a
time, never two. Drain a machine holding two of those Pods and the first goes
immediately, and the second only after a replacement for the first is up and healthy
elsewhere. That is the system working perfectly: your service never drops below four
live copies, and the maintenance still completes.

Now break it.

## The drain deadlock

Suppose you have three replicas, and someone (reasonably, protectively, wanting the
service to stay strong) writes a budget of `minAvailable: 3`.

Read it as the Eviction API reads it. A request arrives to evict one of the three
Pods. Granting it would leave two available. The budget demands three. **Refused.**
The drain retries. The same arithmetic produces the same refusal. Forever.

There is no state of the world in which this budget can ever be satisfied while
removing a Pod, because it demands that *all* of them stay up. The number of Pods
that may ever be voluntarily evicted is exactly zero. The machine can never be
drained. The upgrade never proceeds. And notice what the system reports: nothing. The
budget is a valid object. The Deployment is a valid object. Every Pod is healthy;
in fact the budget is being *honoured perfectly*, which is precisely the problem. The
drain command sits there saying it is waiting, because it is, and it always will be.

The same trap has a second door: `maxUnavailable: 0`. It reads like a strong
statement of intent ("I don't want any of my Pods unavailable"), and it means
literally "no Pod may ever be voluntarily evicted." Identical deadlock.

And a third, subtler one, which catches people who thought they were being careful by
using percentages. Budgets accept them, and here you have to know which way the
arithmetic breaks. Inside a disruption budget, **both** percentages round *up*: of
`minAvailable`, the documentation says "Kubernetes rounds up to the nearest integer,
so in this case, 4 Pods must be available"; of the other, "when you specify the value
`maxUnavailable` as a percentage, Kubernetes rounds up the number of Pods that may be
disrupted." Rounding up is protective in the first case and permissive in the second,
which is why it is easy to remember it wrongly.

Where does the trap spring, then? On `minAvailable`. Write `minAvailable: 51%` against
a single replica and it rounds up to 1: a requirement that the one and only Pod always
stay available. Deadlock again, arrived at by writing a number that looks like a safety
margin rather than an absolute. This is not a hypothetical: it is how etcd's own
published budget is written, and it is exactly the shape of configuration that reads as
cautious and behaves as fatal.

One warning about a neighbouring field, because it is the reason people get this
backwards. A **Deployment** also has a `maxUnavailable`, in its rolling-update
strategy, and *that* one rounds **down**. Same word, different object, opposite
direction: unrelated mechanisms, one governing how a new version is rolled out and
the other governing what the Eviction API will permit. If you want evidence that
conflating them is easy: this exact error was live in Syg's own checker, rejecting
valid budgets, until a test went looking for it.

Two related things make this worse in practice. First, the number that matters is not
always the replica count you wrote: if an autoscaler is managing the Pod count, the
budget has to be satisfiable against its *lowest* setting, because the autoscaler will
take you there on a quiet night and a drain at 3 a.m. will then deadlock on a
configuration that tested fine at midday. Second, and this catches almost everyone,
a budget on a **single-replica** workload is deadlocked *by construction*. Any budget
demanding availability of a workload that has exactly one copy forbids removing that
copy, and one copy is all there is.

The rule that falls out of all of this is simple, and worth memorising: **a budget
must always leave room for at least one Pod to be evicted.** With three replicas,
`minAvailable` must be at most two. If you cannot afford to lose one, you do not have
a budget problem; you have a replica-count problem.

## Probes: how the system knows a container is healthy

The second family of expensive mistakes lives in the health checks, so let us build
them properly.

The agent on each machine can periodically test each container to decide what to do
with it. These tests are **probes**, and there are three, distinguished not by how
they test but by *what the system does with the answer*:

A **liveness probe** asks: *is this container still working, or is it wedged?* If it
fails repeatedly, the agent **restarts the container**. This is for the situation
where a process is running but has become useless (deadlocked, stuck in a loop,
irrecoverably confused) and the only cure is a restart.

A **readiness probe** asks: *is this container ready to serve requests right now?* If
it fails, the container is **not restarted**; instead the Pod is removed from the
list of addresses that traffic is sent to. Chapter 9 built that list (the
EndpointSlice) and noted that only *ready* Pods appear in it. This is the mechanism
behind that word. When the probe passes again, the Pod is added back.

A **startup probe** exists for programs that take a long time to become usable. While
it is still failing, the other two probes are held off entirely, which prevents a slow
starter from being killed by a liveness probe before it has finished waking up.

Each probe can test by making an HTTP request to a path, by opening a TCP connection,
or by running a command inside the container; and each has timing controls: how long
to wait before the first check, how often to check, how many consecutive failures
count as a real failure.

The distinction that matters most is the one between the first two: **liveness
restarts, readiness only removes traffic.** A failed readiness probe is a way of
saying "don't send me work for a moment." A failed liveness probe is a way of saying
"I am beyond help; kill me and start me over." They are not two flavours of the same
thing. They are two different verbs.

## The restart storm

Which brings us to the second catastrophic mistake, and it is the one this project's
own research found to be both common and completely uncaught by existing tools.

Almost every application framework will happily give you a health endpoint, and the
natural thing (the thing you will find in an enormous amount of real configuration)
is to point *both* probes at it. Same path, same handler, same everything. It looks
tidy. It is symmetric. Why maintain two?

Now suppose that endpoint does what health endpoints so often do: it checks the
service's dependencies. It queries the database to confirm the connection is alive,
because a service that cannot reach its database is arguably not healthy. Reasonable.
Common. Recommended in plenty of blog posts.

The database has a thirty-second blip.

Every replica's health endpoint starts failing simultaneously, not because any
replica is broken, but because they all share a dependency and that dependency
wobbled. The readiness probes fail, and each Pod is pulled out of the traffic list.
That part is *correct behaviour*: there is genuinely nothing useful they can do right
now, and shedding traffic is the right response.

But the liveness probes are pointed at that same endpoint. So they fail too. And the
agent on every machine, doing exactly its job, **restarts every replica of your
service at the same moment.**

Now count the damage. Your entire fleet is cold. Every process must boot, warm its
caches, and re-establish its connection pool, and it must do so *simultaneously with
every other replica*, all of them hammering the database that was already struggling,
which is what caused this. The dependency's thirty-second blip has become a
multi-minute outage of your service, and it was your own health checking that turned
one into the other. Worse, if the dependency is still shaky when the restarts
complete, the liveness probes fail again, and it restarts again: a loop that can
keep a service down long after the original problem has resolved.

You are not the first to find this. The Kubernetes documentation carries a Caution on
exactly this failure shape, and it is worth reading as a description of what you just
watched happen:

> "Liveness probes can be a powerful way to recover from application failures, but they
> should be used with caution. Liveness probes must be configured carefully to ensure
> that they truly indicate unrecoverable application failure, for example a deadlock.
>
> Incorrect implementation of liveness probes can lead to cascading failures. This
> results in restarting of container under high load; failed client requests as your
> application became less scalable; and increased workload on remaining pods due to
> some failed pods."

The same page then says, almost in passing, exactly what to do about a service with
dependencies, and this is the sentence to carry away:

> "When your app has a strict dependency on back-end services, you can implement both a
> liveness and a readiness probe. The liveness probe passes when the app itself is
> healthy, but the readiness probe additionally checks that each required back-end
> service is available."

Which is the two-different-verbs framing, arrived at from the other end. **A liveness
probe should test only whether this process itself is wedged**: something local that
cannot fail for external reasons. **A readiness probe may test dependencies**, because
its consequence, shedding traffic, is the correct response to a dependency being down.

Now the honest qualification, because the same documentation says something that looks
like the opposite: *"A common pattern for liveness probes is to use the same low-cost
HTTP endpoint as for readiness probes, but with a higher `failureThreshold`."* That is
not a contradiction, and reading it carefully is what separates knowing the rule from
understanding it. Sharing an endpoint is not itself the bug. The bug is sharing an
endpoint *that checks dependencies*, which is why the docs qualify it with **low-cost**:
a cheap local check, not a database round-trip. The higher `failureThreshold` is the
second half of the same defence: it makes liveness slower to pull the trigger than
readiness, so a transient wobble sheds traffic well before it starts killing processes.

So the precise statement is this: a shared handler is a *structural* warning sign, not
a proof of a bug. It is worth flagging because it removes your ability to answer the
two questions differently, and the moment someone adds a dependency check to that one
convenient endpoint, which is a normal and well-intentioned thing to do, the restart
storm becomes available to you and nothing anywhere will have changed colour.

If you want the long version of this argument, Colin Breck has written the best
treatment of it: three articles working through how probes intended to improve
availability end up reducing it, including the timeout-and-threshold interactions this
chapter only gestures at. They are linked at the end.

## A third, quieter one: no readiness probe at all

Worth naming because it is so easy: a workload that receives traffic and declares *no*
readiness probe at all. Without it, a Pod is added to the traffic list as soon as its
container starts running, which is generally well before the program inside has
finished starting up and can actually serve anything. The result is a burst of errors
on **every single deploy**, as each new replica receives requests during the seconds
between "process started" and "process ready." Teams live with this for years,
assuming rollouts are just inherently a bit lossy. They are not. That is a missing
readiness probe.

## Where Syg stands

This chapter contains the two mistakes that, in a study of real configurations, are
both common *and* absent from every existing checker, which makes them the core of
what Syg adds.

The first is the disruption budget on a workload that cannot survive it. Syg computes
the budget against the **effective** minimum number of copies (the autoscaler's floor
if one exists, otherwise the declared count) and reports the deadlock at the line you
wrote, with the arithmetic spelled out and the consequence stated in the terms of this
chapter ([`budget-blocks-eviction`](../rules/availability.md#budget-blocks-eviction), and the single-replica case,
[`single-replica-budget`](../rules/availability.md#single-replica-budget), which the study found in half of all the
real configurations it examined). It rounds both percentage forms up, the way a budget
actually behaves, not down, the way a Deployment's rollout does, because that is
where the subtle cases hide.

The second is the shared probe ([`shared-probe-endpoint`](../rules/probes.md#shared-probe-endpoint)). If a
container's liveness and readiness probes resolve to the same handler, Syg says so, as
a warning, and with
the qualification this chapter insisted on. It does not claim the endpoint checks a
dependency; it cannot know that, and it says so rather than pretending. What it
reports is that the two questions have been collapsed into one, which is the
structure a restart storm needs. It also flags a traffic-receiving workload with no
readiness probe at all ([`missing-readiness-probe`](../rules/probes.md#missing-readiness-probe)).

None of these can be caught by validating objects one at a time. All of them are
relationships between fields, which is the case for modelling configuration as a
graph rather than a pile of documents.

## Read the source

- **Disruptions**: voluntary versus involuntary, and the worked example of a budget
  permitting one eviction at a time:
  https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- **Specifying a Disruption Budget**: `minAvailable`, `maxUnavailable`, percentage
  handling, and the healthiness rules:
  https://kubernetes.io/docs/tasks/run-application/configure-pdb/
- **API-initiated eviction**: how the Eviction API differs from deletion, and when it
  refuses: https://kubernetes.io/docs/concepts/scheduling-eviction/api-eviction/
- **Liveness, readiness and startup probes**: the three probe types, the Caution on
  cascading failures quoted above, and the "when should you use…" guidance including
  the strict-dependency prescription:
  https://kubernetes.io/docs/concepts/workloads/pods/probes/
- **Pod lifecycle**: where probes sit in the life of a Pod:
  https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
- **Configure liveness, readiness and startup probes**, the practical guide:
  https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- **Colin Breck, on probes making availability worse**: the long version of this
  chapter's second half, and the source of the timeout/threshold reasoning:
  https://blog.colinbreck.com/kubernetes-liveness-and-readiness-probes-how-to-avoid-shooting-yourself-in-the-foot/
  · https://blog.colinbreck.com/kubernetes-liveness-and-readiness-probes-revisited-how-to-avoid-shooting-yourself-in-the-other-foot/
  · https://blog.colinbreck.com/kubernetes-liveness-and-readiness-probes-looking-for-more-feet/

---

*Your software now runs, survives the loss of a machine, shares resources fairly, and
stays available through deliberate maintenance. What it does not yet have is anything
to work with: the settings that vary between environments, the credentials it needs to
reach a database, an identity of its own, and rules about who is allowed to talk to
it. That is the last layer of the machine.* →
[Configuration, identity, and security](../notes/12-configuration-identity-and-security.md)
