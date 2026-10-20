# voluntary-disruption: drains, budgets and rollouts

**Not a rule.** A concept behind `CHK-PDB-001..005`, `CHK-HPA-005` and `CHK-RES-003`.

## Two kinds of disruption
**Involuntary.** A node fails, the kernel kills a container for memory, the
kubelet evicts under node pressure. Nothing asks permission.

**Voluntary.** Someone, or something, chooses to remove a pod: `kubectl
drain`, a cluster upgrade, the cluster autoscaler removing a node. These go
through the Eviction API, and the Eviction API consults PodDisruptionBudgets.

## What a budget does
A PodDisruptionBudget says how many of a set of pods must stay available
(`minAvailable`), or how many may be down (`maxUnavailable`). An eviction that
would break it is refused with HTTP 429, and the drain retries until it can
proceed.

- **No slack.** A budget that allows no disruption (`minAvailable` equal to the
  replicas) makes every drain of a node running one of its pods wait forever
  (`CHK-PDB-001`).
- **A single replica.** With one replica there is no eviction that keeps the
  service up. `minAvailable 1` blocks maintenance; `maxUnavailable 1` lets the
  outage through (`CHK-PDB-005`).
- **Unhealthy pods.** A pod that is running but not ready can be evicted only
  while the budget holds, unless `unhealthyPodEvictionPolicy: AlwaysAllow` says
  otherwise (`CHK-PDB-004`, `disruption { evictUnhealthy true }`).

## What a budget does not do
- **Rollouts.** A Deployment's rollout scales pods down directly, without
  evicting them, so the budget does not limit it. `CHK-PDB-003` checks that the
  rollout strategy's worst case stays inside the budget anyway.
- **Involuntary disruption.** A budget protects nothing from a node failure or
  from node-pressure eviction, which is decided by QoS class (`syg explain
  qos`, `CHK-RES-003`).

## Further reading
- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/
