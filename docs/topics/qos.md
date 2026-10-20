# qos: Quality of Service classes, and what they decide

**Not a rule.** A concept behind `CHK-RES-001..004`, `CHK-PDB-*` and `CHK-T2-CAP-001`.

## The three classes
The kubelet gives every pod a QoS class, derived from its containers' requests
and limits. Nobody writes it:

- **Guaranteed.** Every container, init containers included, has CPU and memory
  limits, and its requests equal them. A request left unset defaults to its
  limit.
- **BestEffort.** No container sets any CPU or memory request or limit.
- **Burstable.** Anything else.

## What the class decides
**Who is evicted when a node runs short of memory.** The kubelet ranks pods by:

1. whether their use exceeds their request;
2. their priority;
3. how far their use exceeds their request.

It evicts from the top, without consulting any PodDisruptionBudget. A
BestEffort pod requests nothing, so any use exceeds it, and it goes first. A
Guaranteed pod cannot exceed its request, so it goes last.

**What the scheduler reserves.** Requests are what a node must have free to
take the pod. Without them the scheduler packs pods onto nodes that cannot run
them all at once.

**What the kernel enforces.** A memory limit is a hard ceiling: past it the
container is OOM-killed. A CPU limit throttles: the container is paused for the
rest of each period, which can make probes time out on a busy node.

## What Syg does with it
- `CHK-RES-001` asks for requests.
- `CHK-RES-002` refuses limits below requests.
- `CHK-RES-003` reports the class where a disruption budget suggests the author
  expects protection the class does not give.
- `CHK-RES-004` compares `qos guaranteed|burstable|besteffort`, the class you
  intend, with the class your numbers derive.
- Hovering over `resources` in the editor shows the derived class.

## What Syg does not decide
Whether a request is the right *size*, and whether a node will come under
pressure, depend on real consumption over time (`syg explain tier3`).

## Further reading
- https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/
