# Scaling

Autoscalers that cannot scale, fight the declared replica count, or undercut a budget.

## autoscaler-without-request

`CHK-HPA-002` · error · checked offline

The HPA reports an unknown metric and never scales; the workload stays at minReplicas through any amount of load.

### What you see

The autoscaler never scales, at any load.

The HPA exists and looks configured. `kubectl get hpa` shows the target column as
`<unknown>/70%`, a string that reads like a transient startup state rather than a
permanent one, so it is easy to glance past. The replica count stays at
`minReplicas` no matter what traffic arrives.

This is a bad failure to have because it is *silent in the direction of
under-provisioning*. Nothing breaks in normal conditions; the service simply has no
autoscaling, and discovers it during the first peak that needed it.

### Why it happens

This is arithmetic, and it is the whole rule.

A `Resource` metric with `type: Utilization` is computed as:

    utilisation = actual usage / the container's REQUEST

Not the limit. Not the node's capacity. The **request**. That is the denominator,
and it is the number the percentage is a percentage *of*.

With no request declared, there is no denominator. The metrics pipeline cannot
produce a utilisation figure, the HPA marks the metric unavailable, and, because it
will not scale on a metric it cannot evaluate, it does nothing.

This also explains a subtlety worth internalising: `averageUtilization: 70` does not
mean "70% of a CPU". It means 70% of whatever you requested. Halve the request and
the same real usage doubles the reported utilisation.

### What Syg catches

`scale on cpu at 70%` where no container declares a CPU request.

### Why Syg checks rather than prevents

Because the two declarations are separate and both are individually valid. A
`resources` block without CPU is legitimate; a `scale` on CPU is legitimate. Only
the combination is broken, and shaping the language to forbid it would mean
`scale` could not be written before `resources`: a needless ordering constraint on
an author mid-edit.

It is an **error** rather than a warning because, unlike most of this catalogue,
there is no configuration in which this works. It is not a risk or a smell; the
autoscaler is inert, and the author's intent is unambiguously unmet.

It is the most valuable autoscaling check that cannot be made a prevention, and
the reason is the contrast with what Syg refuses to do. Whether `70%` is the *right*
target depends on observed traffic and workload behaviour: it is not decidable from
source, and is listed as Tier 3. Whether a denominator exists at all is decidable right
here. Checking the precondition and declining the judgement is the honest split, and
a tool that guessed at the target value would teach its users to ignore it.

### Kubernetes versions

Verified against the kubernetes.io HorizontalPodAutoscaler documentation, which
states that for resource metrics the utilisation value is the percentage of the
resource *request* across the pods (checked 2026-08). Stable in `autoscaling/v2`.

Observed on k3s v1.32.12 with metrics-server: an
autoscaler on cpu over a Deployment with no cpu request reports
`ScalingActive: False` with "failed to get cpu utilization: missing request for
cpu in container api", and never scales.

### What Syg does not claim

Syg checks that a request exists for the metric being scaled on. It says nothing
about whether the request is the right size, whether the target percentage is
sensible, or whether CPU is even the right signal for this workload. A queue
consumer bound on I/O will not scale usefully on CPU no matter how the numbers are
set, and no compiler can see that.

It also does not verify that a metrics pipeline is installed in your cluster. An HPA
with a perfect configuration does nothing without one, and that is a fact about a
running cluster.

### Further reading

- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether the metric target is a sensible number, or whether CPU is even the right signal for this workload, depends on observed traffic and is not statically decidable. Syg checks the precondition (that a request exists to be a denominator) and refuses to opine on the value.

## autoscaler-bounds-invalid

`CHK-HPA-003` · error · checked offline

The API server rejects the object, or the autoscaler is admitted and cannot function.

### What you see

Either the object is rejected at apply time, which is the good case, or it is
admitted and the autoscaler cannot function.

The inverted range is usually a transposition: someone writes the numbers in the
order they thought of them rather than the order the syntax expects. Because the
two numbers are both plausible, review does not catch it, and the failure surfaces
as a deploy that will not apply: annoying, but loud and immediate.

A floor of zero is the more interesting mistake, because the author usually means
something real by it: they want the workload to scale to nothing when idle. That is
a genuine capability and this is not the mechanism for it. Written here, it either
fails admission or produces an autoscaler that cannot reach the state it was asked
for, and the intent is quietly lost.

### Why it happens

`minReplicas` and `maxReplicas` bound the range within which the HPA may set the
replica count. `maxReplicas` is required and must be at least 1; `minReplicas`
defaults to 1 and must be at least 1 unless the `HPAScaleToZero` feature gate is
enabled, which is not on by default.

An inverted range describes an empty interval: no integer satisfies both bounds, so
there is no replica count the autoscaler could legally choose.

Scaling to zero on demand is served by different machinery entirely: a
request-driven autoscaler such as KEDA or Knative, which holds requests while a
workload starts. The HPA has no such mechanism, which is why its floor starts at one.

### What Syg catches

`between 20 and 4` (an inverted range), or a floor below one replica.

### Why Syg checks rather than prevents

The values are ordinary numbers, and a language that could not express two numbers
in the wrong order would have to make the range a single opaque construct, which
would make it harder to read for the sake of a mistake that is cheap to report.

It is an error rather than a warning because there is no reading under which an
inverted range is intended. Unlike most of this catalogue, this rule is not about a
risk or a trade-off; it is about a statement with no satisfiable meaning.

The diagnostic underlines the maximum and points back at the minimum, because a
transposition is only visible when both numbers are in view.

### Kubernetes versions

Verified against the kubernetes.io HorizontalPodAutoscaler documentation and the
`autoscaling/v2` API reference, including the `minReplicas` default of 1 and its
dependency on the `HPAScaleToZero` alpha gate for lower values (checked 2026-08).

### What Syg does not claim

Syg checks the range is well-formed, not that it is well-chosen. A floor of 1 for a
workload that needs 4 to serve its baseline traffic is a correct-looking declaration
and a future incident, and nothing here can see that: it depends on observed load,
which is Tier 3.

### Further reading

- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/horizontal-pod-autoscaler-v2/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## replicas-fight-autoscaler

`CHK-HPA-004` · warning · checked offline

Under GitOps auto-sync, the reconciler re-applies the static replica count and the HPA rescales: the Deployment flaps between the two values and the Application never settles.

### What you see

Under a GitOps agent with automatic sync and self-heal, the Deployment flaps. The
agent re-applies the replica count from git, the HPA rescales to what the metrics
call for, the agent sees drift and re-applies, and the Application never settles.

Observed with a replica count written beside an HPA (k3s v1.32.12, Argo CD
v2.14.11): the HPA logged `New size: 3; reason: Current number of replicas below
Spec.MinReplicas` ten times in 2 minutes 41 seconds. The Deployment reached
generation 20, and the Application stayed OutOfSync. With Syg's output, the
opposite holds: over 60 seconds of self-heal, `spec.replicas` stays at the HPA's
floor.

### Why it happens

The naive claim, "a declared replica count and an HPA always fight", is not true
in recent Kubernetes.

The HPA controller owns `spec.replicas` through the scale subresource. A one-off
manual write of the field, such as `kubectl scale` or a single `kubectl apply`,
is corrected at the HPA's next evaluation: the controller computes the desired
count from metrics and its bounds, and writes it back. Current documentation also
describes implicitly deactivating the autoscaler when a workload is scaled
manually to zero. The two writers do not oscillate on their own.

The oscillation needs a second writer that re-applies the static count
continuously. A GitOps reconciler with self-heal is exactly that: it treats the
HPA's change as drift and reverts it on every sync. The symptom is therefore
scoped to that delivery path, and the rule says so.

### What Syg catches

A workload that writes `replicas N` and also declares `scale ... between MIN and
MAX`, where N is not the autoscaler's floor.

Syg never emits `spec.replicas` for an autoscaled workload, so the written count
changes nothing. The warning exists so the line is not dropped
silently: `replicas 4` reads as a promise, and the output does not keep it.

### Why Syg checks rather than prevents

Syg has already removed the conflict from its output by never writing the field
under an HPA. What remains is the source line, and forbidding `replicas` beside
`scale` outright would be a worse language: a count equal to the floor is
harmless, and an environment may move a workload in and out of autoscaling. So
the line is accepted and its effect, none, is reported.

### Kubernetes versions

The HPA algorithm and scale-subresource behaviour were checked against the
kubernetes.io HorizontalPodAutoscaler documentation (v1.36 pages). The GitOps
flapping was observed on Kubernetes v1.32.12 with Argo CD v2.14.11, and its
absence with Syg's output is verified on the same versions. Older releases without the
implicit-deactivation behaviour are reported to flap without GitOps too. That is
recorded, not asserted, because it was not reproduced here.

### What Syg does not claim

Syg does not know how your manifests are delivered. Without a GitOps agent
re-applying them, a written replica count would not flap on a recent cluster.
Syg leaves it out regardless, because the autoscaler's floor already states the
minimum. Nor does Syg predict how many replicas the HPA will choose; that depends
on load (Tier 3).

### Further reading

- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/#leaving-room-for-imperativeness

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## autoscaler-floor-below-budget

`CHK-HPA-005` · error · checked offline

Scale-down and node drains deadlock: the autoscaler tries to remove pods the budget forbids evicting, so the cluster autoscaler never completes and upgrades stall.

### What you see

Scale-down stops working, and then node drains stop working, and the two are not
obviously the same problem.

Consider `scale ... between 2 and 20` with `disruption { minAvailable 4 }`. Under
load the workload runs 12 pods and everything is fine: the budget has plenty of
slack. Traffic falls, the autoscaler scales down, and at 4 pods the budget starts
refusing evictions. The workload never reaches its floor of 2, so the cluster keeps
paying for capacity nothing needs, and the cluster autoscaler cannot consolidate the
nodes those pods are pinned to.

Then someone drains a node for maintenance and it hangs, because the budget will not
release the pod. `Cannot evict pod as it would violate the pod's disruption budget`.
A cluster upgrade rolling through nodes stalls at the first one hosting this
workload.

The delay between cause and symptom is what makes this expensive. The declaration
was written months earlier, at a moment when the numbers looked compatible, and the
failure arrives during an unrelated maintenance operation.

### Why it happens

Two controllers with no knowledge of each other.

The HPA sets `spec.replicas` within its range, based on metrics. The PDB constrains
the **Eviction API**, requiring that at least `minAvailable` pods matching its
selector remain available after any voluntary eviction.

The budget is evaluated against the pods that *actually exist* at that moment, not
against the declared replica count. So when the autoscaler brings the workload down
to its floor, the budget's arithmetic is done against that floor. If `minAvailable`
is greater than or equal to it, no eviction can succeed. The deadlock is permanent, since the
autoscaler will not scale back up without load.

Neither controller reports a conflict. The HPA is doing its job; the PDB is doing
its job; the combination has no legal move.

### What Syg catches

A disruption budget demanding at least as many available pods as the autoscaler's
floor permits to exist.

### Why Syg checks rather than prevents

Because it is arithmetic between two independently reasonable declarations, in two
different blocks, both of which are correct on their own. There is no shape a single
declaration could take that would make the conflict unrepresentable without merging
autoscaling and disruption into one construct, which would be a worse language for
the sake of one rule.

**Why this rule and `CHK-PDB-002` are not the same rule.** They are the same
arithmetic, so their domains are split by **visibility**, which is also the more
useful thing to tell a reader.

`CHK-PDB-002` owns the budget that is unsatisfiable even against the *declared*
replica count: wrong on the face of the source, findable by reading one block.

This rule owns the budget that **looks fine and is not**. `replicas 10` with
`minAvailable 8` reads correctly (eight of ten leaves ample slack) and deadlocks
the moment the autoscaler scales down to its floor of 2. Only this rule can name the
floor as the cause; reporting it as "PDB unsatisfiable" would send the reader to the
replica count, where they would find 10 and conclude the compiler was wrong.

Letting both fire would report one mistake twice with two explanations, which is
worse than either alone.

Both are among the rules `DIAG` requires multi-span rendering for, and the reason is
visible here: the conflict lives *between* two declarations, so a diagnostic
underlining only one of them sends the reader to a line that is not wrong.

### Kubernetes versions

Verified against the kubernetes.io disruptions documentation, the Eviction API
reference, and the HorizontalPodAutoscaler documentation (checked 2026-08).

### What Syg does not claim

Syg compares declared numbers. It does not know how many pods are running in your
cluster now, whether the workload has ever reached its floor, or whether a drain has
been attempted: all facts about a running cluster.

Percentage budgets are deliberately excluded here: `minAvailable: 50%` is evaluated
against the current replica count rather than a fixed number, so it does not produce
this deadlock in the same way. `CHK-PDB-001` owns the percentage arithmetic.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## autoscaler-vpa-overlap

`CHK-HPA-006` · error · checked offline

The two autoscalers chase each other: the VPA raises the request, utilisation (a percentage of the request) falls, the HPA scales in, per-pod load rises, the VPA raises the request again.

### What you see

Two control loops chase each other. The HPA scales on CPU utilisation, which is
usage divided by the CPU *request*. The VPA raises the request because pods are
busy. Utilisation falls, so the HPA scales in. Per-pod load rises, so the VPA
raises the request again. Replica counts and requests oscillate instead of
settling, and in `Recreate` or `Auto` mode every VPA change evicts pods to apply
it.

### Why it happens

HPA utilisation targets are computed against the pod's requests: 70% means 70%
of the requested CPU. The VPA recommender sets requests from observed usage, and
its updater applies them by evicting pods (or in place, where supported). Each
controller's output is the other's input. The VPA project documents that the two
must not be used together on CPU or memory; HPA on custom or external metrics,
with VPA on CPU and memory, is the supported combination.

### What Syg catches

A raw `VerticalPodAutoscaler` whose `targetRef` names a Syg workload that also
autoscales horizontally on the same resource. The VPA must not be in `Off` mode,
and its resource policy must leave that resource under its control. The default
is to control both cpu and memory for every container.

### Why Syg checks rather than prevents

Syg has no construct for a VPA, so the VPA reaches the module as a raw object,
and a raw object is something Syg can read but did not derive. The rule reads its
`targetRef`, mode and resource policy. A future `autoscale vertical` construct
could make the overlap unrepresentable, as `scale` did for `scaleTargetRef`.

### Kubernetes versions

Checked against the VerticalPodAutoscaler README and known-limitations
documentation (kubernetes/autoscaler, vertical-pod-autoscaler-1.3.0), and the
HorizontalPodAutoscaler documentation for the utilisation formula (Kubernetes
1.32). The fixture's VPA object is dry-run against the v1.3.0 CRD on the
integration cluster. The oscillation itself needs a recommender, an updater and
real load. It was **not** reproduced here; the rule rests on the documented
algorithms.

### What Syg does not claim

Syg does not predict the oscillation's amplitude or period, which depend on load
and on both controllers' tuning. It reads only what the VPA object says. A VPA
created by another tool, outside this module, is not seen (the closed world).

### Further reading

- https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler#known-limitations
- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

