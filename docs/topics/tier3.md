# tier3: what Syg will not check

**Not a rule.** These properties cannot be decided from configuration, and no
check pretends to decide them. `syg explain` names the adjacent limitation
on the rules beside them.

## The table

| Property | Why Syg refuses | What Syg does instead |
|---|---|---|
| Probe timing sufficiency (`initialDelaySeconds`, `timeoutSeconds` vs real startup/response latency) | Depends on actual application boot time, image version, and load | Checks structure (`CHK-PRB-002/004/005`), points to observability |
| HPA metric fitness (CPU target for an I/O-bound workload) | Requires observed traffic/utilization correlation | Checks the **precondition** only (`CHK-HPA-002`) |
| Node-pressure eviction risk from declared requests | Depends on real consumption, co-scheduling, and node capacity over time | Reports QoS class (`CHK-RES-003`) as the decidable proxy |
| Secret/ConfigMap **content** correctness | Values are runtime facts, deliberately absent from source | Checks existence and key references only |
| CPU-throttling causing probe failures | Requires node capacity and load | Reports the structural risk pattern only |
| Whether a rollout will succeed in practice | Depends on cluster capacity and application behavior | Checks that the strategy's worst case stays within the disruption budget (`CHK-PDB-003`) |

## Why refusing is a feature
A checker that emits confident diagnostics about undecidable properties teaches
its users to ignore diagnostics, which destroys the value of the decidable ones.

## What to do instead
The source is not where these questions are answered: observe the running
system. That means startup latency and probe failures, throttling and memory
use against requests, and the success of real rollouts. Then feed what you
learn back into the declarations, where Syg checks the structure.
