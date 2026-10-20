# Changes and platform rules

Changes the API server will refuse, and declarations your platform requires.

## missing-required-declaration

`CHK-GEN-001` · error · checked offline

A workload reaches production without what the platform requires of every service there: no disruption budget, so a drain takes it down entirely; no identity, so it shares the namespace's default account.

### What you see

A platform's guarantees are only as good as their weakest workload. "Every
production service has a disruption budget" becomes untrue the day one service
ships without one. Nobody notices until a node drain takes all its replicas at
once. A missing identity means a workload quietly running as the namespace's
default ServiceAccount, sharing whatever was granted to it.

### Why it happens

None of these is required by the API: a Deployment without a budget, an identity
or a probe is valid. That is the point. Kubernetes leaves completeness to policy
engines at admission time. This rule moves the policy to compile time, where the
finding names the workload and the requirement, before anything is applied.

### What Syg catches

A workload that lacks something the platform requires of every workload in a
build, as `syg.yaml` states it:

```yaml
require:
  default: [identity]                 # every build
  prod: [disruption, readiness, resources, labels.team]
```

The requirements are:
- `identity`, its own ServiceAccount;
- `disruption`, a budget (jobs are exempt);
- `health`, any probe, or `readiness`, a readiness probe (jobs are exempt);
- `resources`, cpu and memory requests on every container;
- `limits`, cpu and memory limits on every container;
- `security`, a security block;
- `labels.KEY`, a label;
- `image-digest`, reported per image by CHK-IMG-002.

Each environment is checked against `default` plus its own list. A finding that
the base build already has is not repeated per environment.

### Why Syg checks rather than prevents

What a platform requires is the platform's choice, and it differs between
environments: development may run without budgets, production may not. The
language cannot make one set of declarations mandatory for everyone. A profile
can (`required disruption`), and `syg.yaml` states the per-environment policy
that this rule checks.

### Kubernetes versions

Not version-dependent: the rule checks the module's own declarations. The
mechanisms behind each requirement are those of the corresponding rules
(CHK-PDB-*, CHK-RBAC-006, CHK-PRB-005, CHK-RES-001).

### What Syg does not claim

That the required declarations are well chosen. A budget can be present and
wrong, which CHK-PDB-001/002/005 judge. Workloads outside the module are not
seen (the closed world).

### Further reading

- https://kubernetes.io/docs/concepts/policy/
- `syg explain CHK-PDB-005`, `syg explain CHK-RBAC-006`

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## immutable-field-change

`CHK-GEN-002` · error · checked offline

The apply is refused with `field is immutable` (a StatefulSet's claim templates or serviceName, a claim's class or access modes, a Job's pod template); the object must be deleted and recreated, which for a StatefulSet's storage means migrating data.

### What you see

The apply is refused, and the remedy is expensive. For a StatefulSet, deleting it
and recreating it with new claim templates does not change the disks the existing
replicas already have, because claims outlive their StatefulSet. A larger or faster
disk means migrating data. For a claim, a new class means a new, empty volume.

### Why it happens

- **StatefulSet.** Only `replicas`, `ordinals`, `template`, `updateStrategy`,
  `persistentVolumeClaimRetentionPolicy` and `minReadySeconds` may be updated.
- **PersistentVolumeClaim.** The spec is immutable after creation, except
  `resources.requests`, which can grow when the class allows expansion, and
  `volumeAttributesClassName`.
- **Job.** The pod template is immutable. A Job is replaced, not updated.

### What Syg catches

A change, between the baseline and this build, to a field Kubernetes fixes when
the object is created:

- a StatefulSet's `serviceName`, `podManagementPolicy` and `volumeClaimTemplates`
  (a claim template added, removed, or with a different size, class or access
  mode);
- a PersistentVolumeClaim's `storageClassName` and `accessModes`;
- a Job's pod template.

Values are compared by containment. Each value Syg emits must match the
baseline's, and a field only the baseline has (`volumeMode: Filesystem`, filled
in by the API server) is not a change. So a cluster export works as a baseline.

The baseline is found as for CHK-SEL-005, and the two rules share it.

### Why Syg checks rather than prevents

Each of these values is the author's to choose, and choosing differently is fine
for an object that does not exist yet. Whether it exists is a fact about the
cluster, carried by the baseline, not by the source. So the change is compared,
not forbidden.

### Kubernetes versions

Observed on k3s v1.32.12:

- A StatefulSet whose claim template grew from 1Gi to 2Gi was refused: "updates
  to statefulset spec for fields other than 'replicas', 'ordinals', 'template',
  'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds'
  are forbidden".
- A claim whose access mode changed was refused: "spec is immutable after
  creation except resources.requests and volumeAttributesClassName for bound
  claims".
- A Job whose image changed was refused on `spec.template`.

Given the first build as baseline, Syg reported each of these.

### What Syg does not claim

That a claim may grow: expansion depends on the StorageClass's
`allowVolumeExpansion`, which only a snapshot could tell, so a size change in a
standalone claim is not reported. A field the baseline lacks is not reported
either, since its old value is unknown. Without a baseline the rule does not
run, and says so.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims
- https://kubernetes.io/docs/concepts/workloads/controllers/job/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## selector-change

`CHK-SEL-005` · error · checked offline

The apply is refused with `field is immutable`; a GitOps sync stays failed until someone deletes the Deployment, and deleting it takes every pod down at once.

### What you see

The deploy fails at apply time, and keeps failing:

```
Deployment.apps "api" is invalid: spec.selector: Invalid value: ...: field is immutable
```

A GitOps agent reports the Application as failed to sync on every retry. The way
out is to delete the Deployment and apply the new one, which takes every pod down
at once, so the routine rename becomes an outage that has to be planned.

### Why it happens

A controller finds its pods by its selector, so the API server fixes the selector
when the object is created: `spec.selector` of a Deployment, StatefulSet,
DaemonSet or ReplicaSet in `apps/v1` cannot be updated. Every other field of the
pod template can change and be rolled out; the selector cannot.

### What Syg catches

A Deployment or StatefulSet whose `spec.selector` in this build differs from the
selector of the same object in the baseline. The baseline is the previous
build's output (`syg build -o DIR` reads DIR), or `--baseline PATH` /
`syg.yaml` `baseline:` naming deployed manifests. Any YAML is read, so a
`kubectl get -o yaml` export, with the API server's defaults, works as well as
Syg's own output.

The author never writes a selector: Syg derives it from the module and workload
names. So the usual cause is renaming the module, whose name
is in every instance label, and the finding then points at the `module` line.
A workload that keeps its name but changes kind (a `service` turned `stateful`)
is a warning: the old object is not replaced, it stays running beside the new
one.

### Why Syg checks rather than prevents

Syg already prevents the selector from disagreeing with the pod template (CHK-SEL-002)
and from being written at all. What it cannot know from the source alone is that
an older version of the object exists in a cluster: a module may legitimately be
renamed before it is ever deployed. That fact lives in the previous output, so the
rule compares against it, and says when it had nothing to compare against.

### Kubernetes versions

Observed on k3s v1.32.12: a Deployment built as module `orders`, then
applied as module `shop`, was refused with `spec.selector: Invalid value ...
field is immutable`. Syg, given the first build as baseline, reported the same
change at the `module` line. The rule has held since `apps/v1` (Kubernetes 1.9).

### What Syg does not claim

That the baseline is what the cluster runs: it is what the build was compared
with. A baseline that is out of date gives an out-of-date answer. Without one,
the rule does not run, and an info line says so.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#label-selector-updates

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

