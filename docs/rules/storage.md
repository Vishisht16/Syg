# Storage and scheduling

Volumes and placement rules that pin pods, leave them Pending, or cannot be met.

## spread-exceeds-domains

`CHK-SCH-001` · error · checked offline

Pods beyond the number of topology domains stay Pending forever; or a rollout never progresses, because its surge pod has no domain to go to and no old pod is ever removed.

### What you see

Pods beyond the domain count stay Pending with "didn't match pod anti-affinity
rules" for good. The rollout case is worse, because it looks healthy until the
next deploy. The new ReplicaSet's surge pod finds every domain taken by an old
pod and waits. The controller removes no old pod until a new one is ready, so
`kubectl rollout status` times out on every release.

### Why it happens

A required pod anti-affinity term places a pod only in a domain with no pod
matching its selector. Syg's selector is the workload's own, which matches the
old ReplicaSet's pods as well as the new one's. So with one pod per domain, a
domain frees up only when an old pod is removed. A Deployment rollout removes old
pods only within `maxUnavailable`, which rounds down, and surges new ones within
`maxSurge`, which rounds up. When `maxUnavailable` is 0, nothing ever frees a
domain.

### What Syg catches

A workload that keeps its own pods apart (`avoid { across KEY strict }`) across a
topology key whose number of domains the module declares
(`extern topology KEY { domains N }`):

- **more pods than domains.** The effective minimum (the autoscaler's floor, if
  any) is above N. Error.
- **room for fewer than the autoscaler may want.** The autoscaler's maximum is
  above N. Warning.
- **a rollout with nowhere to go.** A Deployment's replicas equal N, and its
  rollout takes no pod down first. That is the default 25% for three replicas
  or fewer: 25% of 3 rounds down to 0 unavailable and up to 1 surge. Error.

### Why Syg checks rather than prevents

The number of domains is a fact about the cluster, not the module. The module
can state it (`extern topology`) and Syg can do the arithmetic, but nothing in a
declaration's shape can make "more pods than racks" unwritable. A snapshot gives
the real count, to CHK-T2-SCH-001.

### Kubernetes versions

Observed on k3s v1.32.12, which has one node (one hostname domain):

- two replicas with a strict self-avoid: the second pod stayed Pending, "1 node(s)
  didn't match pod anti-affinity rules";
- one replica, with the default rollout and an image change: the new pod stayed
  Pending and the old one kept running; `kubectl rollout status` timed out.

### What Syg does not claim

That the declared domain count is right: a snapshot checks it. A soft avoid and
a spread are not reported: a soft constraint never blocks scheduling, and a
spread allows several pods per domain.

### Further reading

- https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity
- https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## unknown-topology-key

`CHK-SCH-002` · error · checked offline

A misspelt key matches no node label: a strict spread or avoid leaves every pod Pending, a soft one silently spreads nothing.

### What you see

A key no node carries puts every node outside every domain. A strict spread then
leaves every pod Pending, "missing required label", and a soft one spreads
nothing, silently: a misspelt topology key never spreads, and nothing says so.

### Why it happens

A topology key is a node label key, matched as a string. For a spread with
DoNotSchedule, nodes without the label are filtered out. With ScheduleAnyway the
constraint is scored, and a node without the label scores like any other. The
API server accepts any label key, so the mistake survives validation.

### What Syg catches

A `spread` or `avoid` across a key that is neither one Kubernetes sets on every
node (`kubernetes.io/hostname`, `topology.kubernetes.io/zone`,
`topology.kubernetes.io/region`) nor declared with `extern topology KEY`. The
deprecated `failure-domain.beta.kubernetes.io/zone` and `/region` are a warning
that names the replacement. The nearest known key is suggested.

### Why Syg checks rather than prevents

Custom topology labels are legitimate (racks, rooms, power domains), so the key
cannot be a closed list. The module declares the ones it relies on, which makes
the set closed for this module, and a key outside it is reported.

### Kubernetes versions

Observed on k3s v1.32.12: a strict spread across
`topology.kubernetes.io/zonee` left both pods Pending, "1 node(s) didn't match
pod topology spread constraints (missing required label)". The soft one ran
both pods.

### What Syg does not claim

That the cluster's nodes carry a declared key, or the well-known ones. A k3s node
has no zone label. A snapshot checks this (CHK-T2-SCH-001).

### Further reading

- https://kubernetes.io/docs/reference/labels-annotations-taints/
- https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## unknown-taint

`CHK-SCH-003` · warning · checked offline

Tolerating a built-in taint quietly opts out of what it protects: pods scheduled onto cordoned nodes, or kept forever on a node that has stopped responding.

### What you see

Tolerating the cordon means a node being drained for maintenance keeps receiving
these pods. Tolerating unreachable forever means that when a node stops
responding, these pods are never evicted and rescheduled. They stay bound to a
machine that may never come back, and the Service routes to endpoints that do not
answer until someone deletes them.

### Why it happens

The node lifecycle controller taints a node `not-ready` or `unreachable` with
NoExecute when it fails. A pod is evicted from it after its `tolerationSeconds`:
the API server gives every pod 300 seconds by default. A toleration with no
seconds tolerates the taint forever. `kubectl cordon` taints the node
`unschedulable`, and a pod tolerating that is scheduled onto it anyway.

### What Syg catches

A toleration that opts a workload out of a protection Kubernetes applies itself:

- `node.kubernetes.io/unschedulable`, the cordon;
- `node.kubernetes.io/not-ready` or `node.kubernetes.io/unreachable` with
  NoExecute and no time limit (`for`).

A toleration of a custom taint is not reported here: only the cluster knows
whether that taint exists, which is CHK-T2-SCH-002's question against a
snapshot. (A module declares no taints of its own, so there are none to check
without a cluster.)

### Why Syg checks rather than prevents

Node-level agents (log shippers, CNI daemons) legitimately tolerate everything,
and a stateful workload may prefer to wait out a short partition. The rule warns,
and suggests a bound.

### Kubernetes versions

Checked against the kubernetes.io "Taints and Tolerations" documentation for
1.32 (taint-based evictions, the 300s defaults). On k3s v1.32.12 a NoSchedule
taint kept an untolerating pod Pending and let a tolerating one run
(CHK-T2-SCH-002).

### What Syg does not claim

That a node will fail, or how long a partition lasts. The suggested five minutes
is a judgement; Kubernetes' default is 300 seconds.

### Further reading

- https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/#taint-based-evictions

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## spread-policy-implicit

`CHK-SCH-004` · info · checked offline

Strict and soft differ between Pending forever and unbalanced; left unsaid, a reader cannot tell which the author meant.

### What you see

The two modes fail in opposite directions. A strict constraint keeps pods
balanced and leaves a pod Pending when it cannot be placed. A soft one never
blocks scheduling and may leave every pod in one zone. A reader of an unmarked
constraint cannot tell which the author meant, and the difference shows only on
the day a zone runs out of room.

### Why it happens

`whenUnsatisfiable` is required in a TopologySpreadConstraint: `DoNotSchedule`
filters nodes, `ScheduleAnyway` scores them. Anti-affinity is
`requiredDuringScheduling` (a filter) or `preferredDuringScheduling` (a score).

### What Syg catches

A `spread` or `avoid` that says neither `strict` nor `soft`. Syg emits it soft:
`ScheduleAnyway` for a spread, a preferred anti-affinity term (weight 100) for
an avoid.

### Why Syg checks rather than prevents

The language could require the word. It defaults to soft instead, so a first
draft schedules. The info line asks for the choice without failing the build.

### Kubernetes versions

Observed on k3s v1.32.12: a strict spread across a key no node carried
left every pod Pending, and the soft one placed them all.

### What Syg does not claim

That soft or strict is right for the workload.

### Further reading

- https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/#spread-constraint-definition

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## storage-size-missing

`CHK-STO-001` · error · checked offline

The claim never binds, so every pod that mounts it sits Pending indefinitely while every object involved reports as valid.

### What you see

The pod never starts, and nothing anywhere says why.

The claim is created and sits in `Pending`. The pod that mounts it is also
`Pending`, with an event reading `pod has unbound immediate PersistentVolumeClaims`.
Every object involved is valid; `kubectl get pvc` shows the claim exists. What it
does not show, unless you know to look, is that no provisioner will act on a claim
that has not asked for a specific amount of storage or stated how it needs to be
mounted.

This is a first-deploy failure rather than a drift failure, which is the one mercy:
it fails immediately, in the environment where someone is watching. But it fails in
a way that points at scheduling, and the fix lives in a different object.

### Why it happens

Dynamic provisioning matches a PersistentVolumeClaim against a StorageClass, and the
provisioner needs two things from the claim to act: `spec.resources.requests.storage`
(how much) and `spec.accessModes` (how it will be mounted, which determines what
kind of volume can satisfy it).

`accessModes` is a required field in the PVC schema; a claim without it is rejected.
A missing storage request is subtler: the field is technically optional in the type,
so the object is accepted, and the claim then simply never binds because no
provisioner can decide what to create.

### What Syg catches

A `storage` block with no `size`, or no `access` mode, or neither.

### Why Syg checks rather than prevents

It could be prevented by making both fields mandatory in the grammar, and that was
considered. It is a check because a `storage` block with neither field is not
meaningless: it is *incomplete*, which is a different thing.

Requiring them syntactically would mean an author cannot write down the storage they
intend and fill in the numbers afterwards; they would have to invent values to get
the file to parse, and invented values are worse than absent ones because they look
deliberate. Reporting it as an error achieves the same outcome (nothing reaches a
cluster without them) while letting a half-written declaration exist in a working
tree.

The diagnostic names both missing fields in one message rather than reporting them
separately, since they are one omission from the author's point of view.

### Kubernetes versions

Verified against the kubernetes.io persistent-volumes documentation for the
PersistentVolumeClaim spec and the dynamic-provisioning flow (checked 2026-08).

### What Syg does not claim

Syg checks the fields are present, not that the values are right. A 1Gi request for
a database that will hold 100Gi is a correct-looking declaration and a future
incident, and nothing here can see that.

Whether the requested size is available, or the access mode supported, depends on
the StorageClass and the cluster: Tier 2 (`CHK-T2-STO-001`).

### Further reading

- https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## shared-rwo-volume

`CHK-STO-002` · error · checked offline

The first replica runs and every other one stays Pending forever, which reads as a scheduling or capacity problem rather than a storage one.

### What you see

One pod runs. The rest never do.

The Deployment reports `1/3 READY` and stays there. The two Pending pods have
events saying `0/5 nodes are available: 1 node(s) had volume node affinity
conflict` or `Multi-Attach error for volume "pvc-..."`: messages that read like a
capacity or scheduling problem, which sends the investigation toward node pools,
taints, and resource requests. The actual cause is that the volume attached to the
node the first pod landed on, and no other node can have it.

In one line: *"using a Deployment where
you needed a StatefulSet is how you get replicas fighting over one disk."* It is
expensive because the fix is usually structural (the workload needed per-replica
storage all along), and by the time it is understood, the shape has often been
worked around with a replica count of 1 and a note that says "do not scale this".

### Why it happens

A PersistentVolumeClaim's access modes describe how a volume may be mounted:

- `ReadWriteOnce`: mountable read-write by a **single node**. Note *node*, not
  *pod*: several pods on the same node can share it, which is why this sometimes
  appears to work in a single-node test cluster and fails in production.
- `ReadOnlyMany`: read-only by many nodes.
- `ReadWriteMany`: read-write by many nodes, and supported by relatively few
  storage backends (NFS, CephFS, some cloud filesystems; typically not the default
  block storage class).
- `ReadWriteOncePod`: a single *pod*, the strictest mode.

Most default storage classes on the major clouds provision block devices, which are
ReadWriteOnce. So the common case is a workload that scales past one replica while
mounting a volume that structurally cannot follow it.

### What Syg catches

More than one replica sharing a single claim whose access mode is
`ReadWriteOnce`.

### Why Syg checks rather than prevents

Because the conflict lives in the relationship between two independently reasonable
values, and both are legitimate on their own.

`replicas 3` is fine. `access ReadWriteOnce` is fine: it is the correct mode for
most block storage, and the *right* choice for a `stateful` workload where every
replica has its own disk. Only the combination of "more than one replica" and "one
shared claim" and "ReadWriteOnce" is wrong, and no single declaration can be shaped
to make that combination unrepresentable without forbidding one of the three in
cases where it is correct.

Note what this rule deliberately does **not** fire on: a per-replica claim on a
`stateful`. There, ReadWriteOnce with many replicas is exactly right, because each
replica has its own volume. Reporting it would be the false positive that trains
people to ignore the rule.

Note also what "more than one replica" means per kind. For a Deployment or a
StatefulSet it is the replica count; for a **job it is `parallelism`**, and reading
`replicas` there would silently miss an identical failure: four pods running in
parallel against one ReadWriteOnce disk produces the same three-stay-Pending
outcome, reached through a different keyword. A job with no `parallelism` runs one
pod at a time, so a shared claim there is fine and is not reported.

The suggestion names the structural fix first (declare it as a `stateful`), because
that is usually the real answer, with ReadWriteMany offered second and hedged, since
it depends on a storage class that supports it.

### Kubernetes versions

Verified against the kubernetes.io persistent-volumes documentation, including the
access-mode table and its statement that `ReadWriteOnce` allows the volume to be
mounted by a single node (checked 2026-08). `ReadWriteOncePod` is stable since
Kubernetes 1.29.

Observed on k3s v1.32.12, one node, local-path storage: two replicas sharing a
ReadWriteOnce claim both ran, on the one node holding the volume. That is the
single-node case described under why it happens, and it is the trap: a
one-node test cluster shows nothing wrong. The multi-node symptom described
under what you see is the documented behaviour, not observed on one node.

### What Syg does not claim

Syg reads the access mode you declared. It does not know what your storage class
actually supports, so it cannot tell you whether `ReadWriteMany` is available in
your cluster: that requires reading installed StorageClasses and is Tier 2
(`CHK-T2-STO-001`).

It also cannot tell whether your application is safe to run as multiple writers
against one filesystem even when the storage permits it. Concurrent access being
*possible* is not concurrent access being *correct*, and which of those you have is
a property of your software.

### Further reading

- https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## storage-class-missing

`CHK-STO-004` · error · checked offline

The claim stays Pending with no provisioner willing to act on it, and nothing reports an error.

### What you see

The claim stays `Pending`, and the pod with it, indefinitely.

The distinguishing detail is how little noise there is. A claim naming a
nonexistent StorageClass does not error: it applies, and simply matches no
provisioner. The only trace is an event on the claim itself,
`ProvisioningFailed: storageclass.storage.k8s.io "fast-ssd" not found`; the pod
that will not start says only that it waits for its volume. (Observed on k3s
v1.32.12: the persistentvolume-controller records the event above.)

The usual cause is environment drift: `fast-ssd` exists in the cluster where this
was written and `premium-rwo` is what the new region calls the same thing. The
manifest is unchanged and correct-looking, and it silently does nothing.

### Why it happens

`spec.storageClassName` on a PVC selects which provisioner handles the claim.
Kubernetes resolves it by name at bind time. A name matching no StorageClass leaves
the claim unbound forever: there is no fallback to the default class, because
naming a class explicitly is itself the statement that the default is not wanted.

Omitting the field entirely is different and legitimate: the claim then uses the
cluster's default StorageClass. Syg treats an absent `class` that way and says
nothing about it.

### What Syg catches

A `class` naming a StorageClass that the module neither declares nor declares
`extern`.

### Why Syg checks rather than prevents

Because a StorageClass is cluster infrastructure that Syg does not own or emit.
There is no declaration Syg could derive the name from: the class is provided by
the platform, not by this module.

What Syg *can* do is require the name to be introduced before it is used, so that
`extern storageclass fast-ssd {}` becomes an explicit statement: this module depends
on a class the cluster provides. That turns an invisible environmental assumption
into a line someone reviews, and gives the diagnostic a list of candidates for its
"did you mean".

The reference is bound in the resolver, at the source line, so the error underlines
the class name the author wrote rather than the claim it belongs to.

### Kubernetes versions

Verified against the kubernetes.io storage-classes documentation and the PVC
`storageClassName` semantics, including default-class behaviour when the field is
omitted (checked 2026-08).

### What Syg does not claim

Declaring `extern storageclass fast-ssd {}` asserts only that this module expects
such a class to exist. Syg cannot verify it does: that requires reading the
cluster's StorageClasses, which no stage of `check` or `build` does.
Existence in a real cluster is `storage-class-unsupported` (CHK-T2-STO-001), and until a snapshot
is supplied it is reported as skipped rather than passed.

Nor does Syg know a class's provisioner, its supported access modes, or its
`volumeBindingMode`, all of which affect whether a claim binds.

### Further reading

- https://kubernetes.io/docs/concepts/storage/storage-classes/
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether the storage class exists in your cluster is a fact about a running cluster (storage-class-unsupported, CHK-T2-STO-001), reported as skipped until a snapshot is supplied.

