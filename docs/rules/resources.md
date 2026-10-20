# Resources

Requests and limits that get pods evicted first, throttled, or scheduled where they do not fit.

## missing-requests

`CHK-RES-001` · warning · checked offline

The pod is BestEffort: first to be evicted under node pressure, and not autoscalable on utilization.

### What you see

Under node memory pressure the pod is killed before better-specified neighbours, often during exactly the traffic spike that caused the pressure; and any utilization-based autoscaler attached to it silently never scales.

### Why it happens

A pod's QoS class is derived deterministically from its containers' requests and limits. "A Pod has a QoS class of BestEffort if ... none of the Containers ... have a memory limit or a memory request, and none ... have a CPU limit or a CPU request." Under node pressure, "Kubernetes will first evict BestEffort Pods running on that Node, followed by Burstable and finally Guaranteed Pods." Absent a request there is also no scheduler reservation, so the node can be overcommitted.

### What Syg catches

A container that declares neither a CPU nor a memory request.

### Why Syg checks rather than prevents

Whether to set requests, and to what value, is a genuine capacity-planning decision. Syg cannot pick the value for the user, so it detects the *absence* (and reports the resulting QoS class through CHK-RES-003). Severity is platform-configurable: a platform team may raise it to an error via profile policy.

### Kubernetes versions

Verified against kubernetes.io documentation (v1.36, checked 2026-07); QoS derivation and node-pressure eviction ordering are stable across recent releases.

### What Syg does not claim

Syg does not judge whether a chosen request *value* is appropriate for the workload: that depends on real consumption and is Tier 3 (out of scope). It checks only presence.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/
- https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a request is the right SIZE requires observed utilisation. Syg checks that one exists.

## limit-below-request

`CHK-RES-002` · error · checked offline

The API server rejects the workload, so the deploy fails at apply time rather than here.

### What you see

The API server rejects the workload at apply time with "must be less than or
equal to ... limit". The deploy fails in CI, or worse, mid-way through a
multi-object apply that has already changed some objects. This rule moves the
failure to the line that caused it.

### Why it happens

The scheduler places a container by its request, and the kubelet enforces its
limit. A limit below the request would schedule the container for more than it
may ever use, so pod validation requires `request <= limit` for every resource
that has both.

### What Syg catches

A container whose cpu, memory or extended-resource limit is lower than its
request: `memory 1Gi` with `limits { memory 512Mi }`. Every container is
checked, init containers and sidecars included.

### Why Syg checks rather than prevents

Requests and limits are separate values, each legitimate alone, and a limit may
be any size at or above the request. Making the bad pair unrepresentable would
mean writing limits as a delta over requests, which reads worse for the common
case of a memory limit chosen on its own. So the comparison is checked.

### Kubernetes versions

A validation rule of the core API, unchanged across supported releases, and
verified against the 1.32 API server by dry-run.

### What Syg does not claim

Nothing about whether the values are well chosen: that needs observed usage
(Tier 3). Only that the API server will accept them.

### Further reading

- https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a CPU limit throttles the container enough to make its probes fail depends on node capacity and load. Syg checks that limits are not below requests, and reports the structural risk pattern only.

## qos-class-report

`CHK-RES-003` · info · checked offline

Under node memory pressure the kubelet evicts pods using more memory than they request, BestEffort and Burstable ones, and a disruption budget does not stop it.

### What you see

A node runs short of memory. The kubelet evicts pods to recover it, and a
Burstable workload with a carefully set `minAvailable` loses pods anyway, because
budgets bind voluntary evictions and this one is not voluntary. The team that
wrote the budget concludes that budgets do not work.

### Why it happens

The QoS class is a function of requests and limits:
- **Guaranteed** when every container, init containers included, has cpu and
  memory limits equal to its requests;
- **BestEffort** when no container sets any;
- **Burstable** otherwise.

Under node memory pressure the kubelet ranks pods for eviction by whether their
use exceeds their request, then by priority, then by how far it exceeds. A
Guaranteed pod's request equals its limit, so it cannot exceed it. A BestEffort
pod requests nothing, so any use exceeds it. Node-pressure eviction does not go
through the Eviction API, so PodDisruptionBudgets are not consulted.

### What Syg catches

A workload that declares a `disruption` budget but whose QoS class, derived from
its requests and limits, is Burstable or BestEffort. The report names the class.
A workload that states a class with `qos` is left to CHK-RES-004, which compares
the stated class with the derived one.

**Scope, a judgement call.** The QoS class could be reported for every
workload, but doing that would put a line in every check that nobody reads. The
rule reports it where it contradicts something the module says: a budget reads
as availability protection, and against node-pressure eviction it is none. Any
workload's class is shown by the editor's hover on `resources`.

### Why Syg checks rather than prevents

A Burstable workload is often the right choice, since it lets a pod use idle
capacity, and nothing about it is wrong. The rule informs: it makes the eviction
consequence of a resource edit visible when the edit is made.

### Kubernetes versions

QoS derivation and node-pressure eviction ranking were checked against the
kubernetes.io "Pod Quality of Service Classes" and "Node-pressure Eviction"
documentation for 1.32. The ordering was **not** reproduced on a test cluster:
the one used clamps OOM scores, so it cannot demonstrate QoS-ordered eviction. The derivation is
covered by unit tests against the documented rules.

### What Syg does not claim

Whether your nodes will ever run short of memory, or which pods would be evicted
first. Both depend on co-scheduled pods and real consumption (Tier 3, the
"node-pressure eviction risk" row). The class is the decidable proxy.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a pod will actually be evicted under node pressure depends on real consumption, on what else is scheduled beside it, and on node capacity over time. The QoS class is the decidable proxy, and that is what Syg reports.

## qos-mismatch

`CHK-RES-004` · warning · checked offline

A workload meant to be Guaranteed is Burstable, so it is evicted under node pressure before the pods it was meant to outlast.

### What you see

A database or a quorum member was meant to be Guaranteed, so that under node
memory pressure it is the last thing evicted. One sidecar without limits, or a
memory request rounded differently from its limit, makes the whole pod
Burstable. The difference shows up only on the day a node runs short of memory.

### Why it happens

The class is derived for the whole pod, from every container. Guaranteed
requires cpu and memory limits on every container, init containers included,
with requests equal to them; a request left unset defaults to its limit. One
container short of that makes the pod Burstable. The class is not a field anyone
writes. It appears only in `status.qosClass`, after the pod exists.

### What Syg catches

A workload that says `qos guaranteed` (or another class), directly or through a
profile, whose requests and limits derive a different class. For Guaranteed, the
finding lists each container missing a cpu or memory limit, or whose request
differs from its limit.

`qos` is an item of its own rather than part of `resources`, so a platform
profile can require the class (`locked qos guaranteed`) without fixing anyone's
quantities.

### Why Syg checks rather than prevents

Syg could derive limits from requests whenever `qos guaranteed` is said. That
would silently cap a container the author sized with a larger limit, and the
author would learn about it through an OOM kill. Reporting the mismatch keeps
each number where the author wrote it.

### Kubernetes versions

Checked against the kubernetes.io "Pod Quality of Service Classes" documentation
for 1.32. The derivation is the same in every supported release.

### What Syg does not claim

That Guaranteed is the right class for the workload, or that the requested
amounts are enough. Only that the stated intent and the derived class disagree.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## sidecar-without-requests

`CHK-RES-005` · warning · checked offline

The pod cannot reach the QoS class the app container was specified for, and is evicted earlier than intended under node pressure.

### What you see

The pod does not get the Quality of Service class its author specified it for. A
service carefully given equal requests and limits (the recipe for `Guaranteed`)
sits in `Burstable` instead, and under node memory pressure it is considered for
eviction earlier than the author intended. Nothing warns, because every object is
valid and the app container's own numbers are exactly right.

### Why it happens

**QoS is a property of the Pod, not of a container, and it is derived from every
container in the Pod.** The documentation states the criteria as conditions over
the whole set:

> "For a Pod to be given a QoS class of `Guaranteed`: Every Container in the Pod
> must have a memory limit and a memory request… Every Container in the Pod must
> have a CPU limit and a CPU request…"

"Every Container" includes sidecars and init containers. So one helper container
with no `resources` block is sufficient to prevent the pod from ever being
`Guaranteed`, no matter how precisely the application container is specified.

The classification then governs eviction ordering under node pressure, which is
where the cost is actually paid: the pod becomes a candidate sooner than its
author believed.

Two related details worth keeping straight:

- A pod is `BestEffort` only when **no** container has any CPU or memory request
  or limit. A single specified container is enough to make the pod `Burstable`,
  which is why this rule reports a *downgrade* rather than a collapse.
- Extended resources do not participate. The documentation is explicit that
  containers "can request other resources (not CPU or memory) and still be
  classified as `BestEffort`", so a sidecar asking only for a device is, for QoS
  purposes, asking for nothing. This rule and `CHK-RES-001` both test CPU and
  memory only, for exactly that reason.

### What Syg catches

A pod whose app container declares CPU/memory requests while an accompanying
sidecar or init container declares none. It deliberately stays silent when *no*
container declares anything: that is `CHK-RES-001`'s report, and duplicating it
here would be noise.

### Why Syg checks rather than prevents

The *value* of a sidecar's request is a genuine engineering choice with a valid
range, exactly as `CHK-RES-001`'s is. Syg cannot know that a log shipper needs
10m rather than 100m, and inventing a number would be worse than asking. What it
can do is notice the asymmetry (one container specified, another not) and say
what that costs, since the cost is not local to the container that caused it.

### Kubernetes versions

Verified against kubernetes.io documentation for Pod Quality of Service classes
(checked 2026-08). The QoS derivation has been stable since the classes were
introduced and is unchanged through v1.35.

### What Syg does not claim

Syg does not compute or assert the pod's resulting QoS class here; that is
`CHK-RES-003`'s job. It does not claim the pod *will* be evicted: that depends
on real node pressure and actual usage, which are runtime facts (Tier 3). And it
does not suggest a correct value, only that a value is missing.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

