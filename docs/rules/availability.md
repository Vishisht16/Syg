# Availability

Disruption budgets and rollouts that block node drains or take every replica down at once.

## budget-blocks-eviction

`CHK-PDB-001` · error · checked offline

Node drains hang indefinitely; cluster upgrades stall; autoscaler scale-down never completes.

### What you see

`kubectl drain` hangs indefinitely; a rolling node upgrade stalls part-way; the cluster autoscaler can never scale a node down. This is the canonical 3 a.m. incident: the cluster looks healthy but no node can be emptied.

### Why it happens

A PDB constrains the Eviction API: a voluntary eviction is permitted only while the number of healthy pods would remain at or above the budget. The docs' own example: a Deployment with `replicas: 5` and a PDB allowing 4 lets the Eviction API evict one pod at a time; when the budget is exhausted "the drain command will block." If `minAvailable` equals the effective replica count, or `maxUnavailable` resolves to 0, then `allowedDisruptions ≤ 0` and no voluntary eviction can ever succeed.

**Both percentages round up.** For a PodDisruptionBudget the documentation is explicit in both directions: for `minAvailable`, "Kubernetes rounds up to the nearest integer, so in this case, 4 Pods must be available"; and "when you specify the value `maxUnavailable` as a percentage, Kubernetes rounds up the number of Pods that may be disrupted." Do **not** confuse this with a Deployment's rolling-update `maxUnavailable`, which rounds *down*: a different mechanism on a different object. Conflating the two produces a false positive: `maxUnavailable: 30%` on 3 replicas is `ceil(0.9) = 1`, a perfectly satisfiable budget, which a `floor()` implementation would wrongly report as a deadlock. This rule's implementation and its regression test (`TestPDB001MaxUnavailablePercentRoundsUp`) exist to pin that.

### What Syg catches

A PodDisruptionBudget whose `minAvailable` equals (or exceeds) the workload's effective replica count, or whose `maxUnavailable` resolves to 0: a budget with no slack.

### Why Syg checks rather than prevents

`minAvailable` and `maxUnavailable` are legitimate operational choices with a valid range, and a healthy service *should* have a budget. Prevention would mean removing a valid configuration. Syg therefore detects the unsatisfiable case, computing against the **effective** minimum replica count (the HPA floor if present, else `replicas`) so the check is correct under autoscaling.

### Kubernetes versions

Verified against kubernetes.io documentation (v1.36, checked 2026-07); the `policy/v1` PodDisruptionBudget and this eviction behavior have been GA since v1.21.

### What Syg does not claim

Syg does not predict whether a drain *will* hang in a specific incident: that also depends on pod health and `unhealthyPodEvictionPolicy`. It flags the structural precondition only. Involuntary disruptions (node failure) are never constrained by a PDB and are out of scope.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## budget-unsatisfiable

`CHK-PDB-002` · error · checked offline

Voluntary disruption becomes impossible once the workload is at its floor: drains hang, and the incident arrives during a cluster upgrade rather than a deploy.

### What you see

Voluntary disruption becomes impossible, and nobody finds out until maintenance.

`replicas 3` with `minAvailable 3` means every pod must remain available after any
eviction, so no eviction is ever permitted. The objects apply cleanly. The service
runs correctly. Nothing is wrong until someone drains a node, and then the drain
hangs indefinitely with `Cannot evict pod as it would violate the pod's disruption
budget`.

The timing is the cruelty. This is discovered during a cluster upgrade, a node
replacement, or an autoscaler consolidation: operations that happen on someone
else's schedule, often out of hours, and usually to a person who did not write the
budget and has no context for why the drain is stuck. The available responses are to
wait, or to `--force`, which discards protection for everything on the node.

### Why it happens

A PDB constrains the Eviction API: after an eviction, at least `minAvailable` pods
matching its selector must remain available. The Eviction API is what `kubectl
drain` and the cluster autoscaler use; it does not constrain deletion or involuntary
disruption.

When `minAvailable` equals the pod count, evicting any pod would take availability
below the floor, so the API refuses, every time, forever. The budget is not
"strict"; it is unsatisfiable.

**The subtlety this rule exists for is which number to compare against.** The
obvious answer is the declared replica count, and it is wrong whenever an autoscaler
is present: the declared count is a starting position the HPA immediately takes over,
and the number that will actually be running at the workload's floor is the HPA's
`minReplicas`. `replicas 10` with `minAvailable 8` reads fine and deadlocks the
moment the autoscaler scales down to a floor of 2.

Syg computes this once, in `graph.EffectiveMinReplicas` (the HPA floor when one
exists, else the declared count), and both this rule and `CHK-HPA-005` consume it.
That is the reason it is one shared function rather than two similar loops, and it
is a subtlety most linters miss.

### What Syg catches

`minAvailable` greater than or equal to the number of replicas the workload is
guaranteed to run.

### Why Syg checks rather than prevents

Because it is arithmetic between two values that are each individually sensible, in
declarations that are each individually correct. Preventing it would mean the
language could not express a replica count and a budget independently, and the
relationship between them is exactly the thing an author is reasoning about when
they write both.

**Division of labour with `CHK-HPA-005`.** The two are the same arithmetic, split
by **visibility**. This rule owns the budget that is unsatisfiable against the
*declared* replica count: wrong on the face of the source. `CHK-HPA-005` owns the
budget that looks fine against the declared count and only deadlocks once the
autoscaler reaches its floor, because only that rule can name the floor as the
cause. Firing both would report one mistake twice.

`CHK-PDB-001` is the adjacent rule for the always-impossible forms
(`maxUnavailable: 0`, or a percentage that rounds to the whole set); this one is
about the specific count.

### Kubernetes versions

Verified against the kubernetes.io disruptions documentation and the Eviction API
reference (checked 2026-08). Stable since `policy/v1` in Kubernetes 1.21.

### What Syg does not claim

Syg compares declared numbers against the effective minimum it can compute from
source. It does not know the running replica count, and it cannot see PDBs created
outside the module that might also select these pods: two budgets compound
invisibly.

Percentage budgets are handled by `CHK-PDB-001`, whose rounding rules are their own
piece of arithmetic.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## rollout-exceeds-budget

`CHK-PDB-003` · error · checked offline

Every deploy takes the workload below the availability its disruption budget promises; the budget records the breach and cannot prevent it.

### What you see

Every deploy quietly breaks the availability promise the team wrote down.

The budget says "never fewer than three of these four pods". The rollout replaces
two at a time. During each deploy the workload runs on two pods, half its capacity,
for as long as the new pods take to become ready. If they never become ready, it
stays there. Under load this is latency, then errors, on a schedule that matches the
deploy log. Nothing reports it as a misconfiguration: the budget records the breach
in its status (`currentHealthy: 2`, `desiredHealthy: 3`), and nobody reads a
budget's status during a deploy.

The team believes the budget protects them because it does during node drains. It
does not protect them from their own rollouts, and the two feel like the same kind
of event.

### Why it happens

A PodDisruptionBudget constrains exactly one thing, the **Eviction API**. `kubectl
drain`, the cluster autoscaler and node upgrades evict pods through it, and the
budget refuses any eviction that would take healthy pods below `minAvailable` (or
above `maxUnavailable`).

A Deployment rollout does not evict anything. The Deployment controller scales the
old ReplicaSet down and the new one up, and the ReplicaSet controller deletes pods
directly. The budget is never consulted. How far a rollout may dip is set by the
Deployment's own `strategy`:

- `RollingUpdate` with `maxUnavailable` (default 25%, rounded **down**) and
  `maxSurge` (default 25%, rounded **up**). If both resolve to 0, `maxUnavailable`
  becomes 1 so the rollout can progress.
- `Recreate`, which stops every pod before starting any.

So the budget and the strategy are two independent statements about one quantity:
how many pods may be unavailable. Kubernetes enforces each in its own context and
never compares them. Syg compares them. The worst case uses the effective minimum
replica count, the HPA floor when there is one, because a rollout may start while
the autoscaler sits at its floor.

### What Syg catches

A Deployment whose update strategy takes more pods down at once than its own
PodDisruptionBudget allows to be unavailable.

### Why Syg checks rather than prevents

The rollout and the budget are separate declarations, and each is a legitimate
choice on its own. A fast rollout is reasonable for a workload with no budget, and
a tight budget is reasonable for one rolled out carefully. Only the pair can
contradict itself, so Syg cannot shape either declaration to make the conflict
unrepresentable. Instead it checks the pair, with the same arithmetic the two
controllers use:

- `minAvailable M`: a rollout may take down at most `floor − M` pods;
- `maxUnavailable U`: at most `U` (rounded up, as for a budget);
- `recreate` takes down all of them;
- no `rollout` block means Kubernetes' default 25%, and the diagnostic says so.

A budget with no slack at all (`minAvailable` ≥ the floor) is reported by
`CHK-PDB-001`/`CHK-PDB-002` instead, so that one root cause gives one diagnostic.

### Kubernetes versions

Demonstrated on a k3s cluster running Kubernetes v1.31.4 (2026-10):

- **The budget does not gate rollouts.** Deployments with 2 replicas, a budget of
  `minAvailable: 2` (`disruptionsAllowed: 0`), and rollouts of `maxUnavailable 0,
  maxSurge 1` and of `maxUnavailable 1, maxSurge 0`. Both rollouts completed.
- **The rollout breaches the budget.** A Deployment with 4 replicas,
  `maxUnavailable 2, maxSurge 0`, and a budget of `minAvailable: 3`, updated to a
  revision whose pods never become ready. The Deployment dropped to
  `availableReplicas: 2`. The budget reported `currentHealthy: 2, desiredHealthy:
  3, disruptionsAllowed: 0`, recording a breach it had no way to prevent.

Rollout rounding is from the Deployment controller's `ResolveFenceposts`, stable
across supported versions.

This is not a deadlock in which "the deployment waits for capacity the budget
prevents from being freed": the first experiment above shows no such wait. The
rule rests on the mechanism the second experiment demonstrates.

### What Syg does not claim

Syg checks the strategy's worst case, not what a rollout actually does. A rollout
whose new pods become ready instantly may never dip to the worst case, and Syg still
reports it, because the dip is real whenever readiness is slow, which is exactly
when it hurts.

StatefulSets and DaemonSets are not checked. A StatefulSet replaces one pod at a
time, so its rollout only conflicts with a budget that `CHK-PDB-001` already
reports. Syg does not emit DaemonSets.

Involuntary disruption is outside every budget: node failure, OOM kills, and
evictions under node pressure.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/ ("workload
  resources (such as Deployment and StatefulSet) are not limited by PDBs when doing
  rolling upgrades")
- https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

### Where this stops

Whether a rollout will succeed in practice depends on cluster capacity and on how the application behaves while it starts. Syg checks that the strategy's worst case stays within the disruption budget.

## eviction-policy-unset

`CHK-PDB-004` · warning · checked offline

A node drain hangs on pods that are running but not ready: the budget is already unmet, so the Eviction API refuses to evict even the pods that serve nothing.

### What you see

A node drain hangs on pods that serve nothing. Suppose a bad config, a missing
dependency or a crash-looping sidecar leaves enough pods unready that the budget
is no longer met. The Eviction API then refuses every eviction, including those
of the unready pods themselves. `kubectl drain` retries indefinitely, and a
cluster upgrade stalls on that node.

Observed on k3s v1.32.12 (L1): two pods running but never ready, under
`minAvailable: 1`. With the policy unset, or `IfHealthyBudget`, evicting either
pod returned HTTP 429, "Cannot evict pod as it would violate the pod's disruption
budget", with `currentHealthy: 0` and `desiredHealthy: 1`. With `AlwaysAllow`
the same eviction returned 201 and the pod was replaced.

### Why it happens

A budget is evaluated against healthy (ready) pods. Under `IfHealthyBudget`, a
running pod that is not ready may be evicted only while the budget is satisfied:
`currentHealthy >= desiredHealthy`. When it is not, unready pods are protected
like healthy ones. Under `AlwaysAllow` they may always be evicted, which is what a
drain needs when they are broken, and the wrong choice when they are a quorum
member about to become ready.

### What Syg catches

A `disruption` budget that does not say what happens to pods that are running but
not ready: no `evictUnhealthy true` (the `AlwaysAllow` policy) and no
`evictUnhealthy false` (`IfHealthyBudget`, the API server's default).

### Why Syg checks rather than prevents

Neither value is right for every workload. Syg could pick one silently, but
`AlwaysAllow` evicts a slow-starting pod that was about to become ready, which
matters for a quorum, and `IfHealthyBudget` hangs drains on broken pods. The
choice belongs to whoever knows the workload, so the rule asks for it and
`evictUnhealthy false` records "the default, on purpose".

### Kubernetes versions

`unhealthyPodEvictionPolicy` is alpha in 1.26, beta (on by default) in 1.27, and
GA in 1.31. Syg pins the 1.32 schema. Behaviour was verified on k3s v1.32.12
through the Eviction API, as described under what you see. On a cluster older than 1.27 the
field is dropped and the default applies; a cluster snapshot records the server
version, against which CHK-T2-VER-001 reports.

### What Syg does not claim

Syg does not know whether your pods will ever be unready during a drain, or
whether your drain tooling forces evictions past budgets. It reports that the
choice was left implicit.

### Further reading

- https://kubernetes.io/docs/tasks/run-application/configure-pdb/#unhealthy-pod-eviction-policy
- https://kubernetes.io/docs/concepts/scheduling-eviction/api-eviction/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## single-replica-budget

`CHK-PDB-005` · warning · checked offline

Either the budget protects nothing, or it blocks every node drain in the cluster indefinitely, and which of the two depends on a value most authors set without noticing.

### What you see

One of two, and which one you get depends on a value most authors set without
thinking about it.

**With `minAvailable: 1`** (the common choice): the budget requires one pod to stay
available, and there is exactly one pod. So *no* eviction is ever permitted. Every
`kubectl drain` of the node hosting it hangs. A cluster upgrade rolling through
nodes stops dead at that one. The cluster autoscaler cannot consolidate the node and
keeps paying for it. Nothing reports an error: the drain simply waits, forever, and
someone eventually finds `Cannot evict pod as it would violate the pod's disruption
budget` and reaches for `--force`, which discards the protection for everything on
the node.

**With `maxUnavailable: 1`**: the budget permits exactly the eviction it was written
to prevent. The single pod goes down during any drain. The budget is decorative,
and worse than absent, because it appears in reviews and dashboards as protection
that does not exist.

The pattern that produces this is a platform policy: *every service must declare a
disruption budget*. A boilerplate `minAvailable: 1` gets copied into services that
run one replica, and the policy that was meant to improve availability blocks
maintenance across the estate.

### Why it happens

A PDB constrains the **Eviction API**, which is what `kubectl drain` and the cluster
autoscaler use. It does not constrain deletion, node failure, or anything else
involuntary.

The arithmetic is unforgiving at one replica. `minAvailable: 1` against one pod
means the eviction of that pod would take availability to zero, so the API refuses
it, and always will, since scaling is not something the budget does. `maxUnavailable: 1`
against one pod permits taking it, which is a total outage of the workload.

There is no value that produces a useful budget for a single replica, because a
budget expresses "how much of this can go away at once" and the only options are
"all of it" or "none of it".

### What Syg catches

A PodDisruptionBudget guarding a workload that runs one replica.

In a study of 48 real configurations, mostly public Helm charts, this was the
most common mistake of all: **50.0%**, half of everything measured.

### Why Syg checks rather than prevents

Because both declarations are correct in isolation, and the workload's replica count
is not the budget's business to constrain.

`replicas 1` is a legitimate and common choice: a workload that genuinely cannot
run two copies, or a development environment, or something whose brief unavailability
is acceptable. `disruption { minAvailable 1 }` is a legitimate declaration. Only the
pair is a mistake, and forbidding the pair would mean the language refused to express
a configuration that a platform policy may well require.

It is a `warning` rather than an error for that reason: the author may be complying
with a mandate, and the right response is often to change the replica count rather
than the budget. The suggestion names that first.

The rule consults `EffectiveMinReplicas`, not the declared count, so a workload with
an autoscaler whose floor is 1 is reported too: the budget is just as useless there,
and the declared `replicas` may be a larger number that hides it.

### Kubernetes versions

Verified against the kubernetes.io disruptions documentation and the Eviction API
reference, including the statement that PDBs apply to voluntary disruption only
(checked 2026-08). Stable since `policy/v1` in Kubernetes 1.21.

### What Syg does not claim

Syg reports the structural mismatch. It cannot tell you whether one replica is the
right count for your workload: that depends on whether the software can run
multiple copies, which is a property of your application.

Nor does it know your platform's policy. If a mandate requires a budget on every
service, this diagnostic is the signal that the mandate and the replica count
disagree, not a claim that the mandate is wrong.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

