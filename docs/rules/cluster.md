# Checked against your cluster

What only a snapshot of the cluster can tell: capacity, installed kinds, nodes, the network plugin.

## exceeds-cluster-capacity

`CHK-T2-CAP-001` · warning · checked against a cluster snapshot

Pods stay Pending with FailedScheduling: Insufficient cpu or memory.

### What you see

Pods stay `Pending` with `FailedScheduling: 0/N nodes are available: N
Insufficient cpu`. For the oversized pod this is permanent; for the module total
it happens at peak scale, when capacity matters most.

### Why it happens

The scheduler places a pod on a node whose allocatable resources, minus what is
already requested there, cover the pod's requests. A pod's effective request is
its app containers' and sidecars' together, or its largest init container's if
that is more.

### What Syg catches

A pod that requests more CPU or memory than the largest node can allocate, which
can never be scheduled; and a module whose requests at full scale (autoscaler
maxima, parallelism) exceed the whole cluster's allocatable capacity.

### Why Syg checks rather than prevents

Capacity belongs to the cluster, varies between clusters, and changes over time
(autoscaled node pools). It is a warning, not an error: the rest of the cluster
is not counted, and a cluster autoscaler may add nodes.

### Kubernetes versions

Observed on k3s v1.32.12 (2026-10): a pod requesting more CPU than the node
allocates stayed `Pending` with `FailedScheduling: 0/1 nodes are available: 1
Insufficient cpu`. Allocatable totals and the largest node come from the
snapshot's aggregated node inventory.

### What Syg does not claim

That the module fits alongside everything else already running; node affinity,
taints and topology (CHK-T2-SCH, not yet applicable); or extended resources.
Capacity is a decidable proxy, not a scheduling simulation.

### Further reading

- Kubernetes documentation: Resource Management for Pods and Containers; Node
  Allocatable.

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## kind-not-installed

`CHK-T2-CRD-001` · error · checked against a cluster snapshot

The apply fails with no matches for kind, or the object is stored at a version nothing serves.

### What you see

The apply fails for that object, and with GitOps the whole sync does:

```
resource mapping not found ... no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

### Why it happens

A custom kind exists only while its CustomResourceDefinition does, and is
reachable only at the versions the CRD marks `served`. Operators install their
CRDs, often from a separate chart, and upgrades retire versions.

### What Syg catches

An object of a custom kind (a `raw` Certificate or ServiceMonitor, or the
HTTPRoute every `expose` compiles to) whose CRD is not installed in the cluster,
or is installed without serving the version the module writes.

### Why Syg checks rather than prevents

Which CRDs a cluster has is decided by whoever runs it, outside the module.
Built-in kinds are checked against the pinned schema at Tier 1; custom kinds are
only knowable from the cluster, or from schemas vendored from it
(`syg schema vendor`).

### Kubernetes versions

Observed on k3s v1.32.12 (2026-10): applying an object of a kind with no CRD
fails with the "ensure CRDs are installed first" message above. Served versions
come from each CRD's `spec.versions[].served`, captured by `syg snapshot`.

### What Syg does not claim

That the object is valid against the CRD's schema: that is what vendoring the
schema checks. Nor that the operator behind the CRD is running.

### Further reading

- Kubernetes documentation: CustomResourceDefinitions, versions in CRDs.
- `syg explain CHK-T2-VER-001` (the same question for built-in kinds).

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## extern-mismatch

`CHK-T2-EXT-001` · warning · checked against a cluster snapshot

A pod fails at start (CreateContainerConfigError) or a call goes to a Service port that is not there, despite a clean compile.

### What you see

The module compiles clean, because an extern is trusted, and the pod fails at
start with `CreateContainerConfigError` (a missing ConfigMap or key), is refused
at creation (a missing ServiceAccount), or calls a port nothing listens on.

### Why it happens

A pod's ConfigMaps, Secrets and ServiceAccount are resolved by name in its own
namespace when the pod is created or started, not when the referencing object is
applied. A Service port that does not exist is not an error anywhere: the
connection simply fails.

### What Syg catches

An `extern` declaration the cluster contradicts: an extern service that does not
exist or does not expose a declared port; an extern config or secret that does
not exist or lacks a declared key; an extern identity with no ServiceAccount; an
extern storage class the cluster lacks. Only the namespaces the snapshot was
taken for (`syg snapshot --namespace`) can be checked, and the rule says so when
the build's namespace is not among them.

### Why Syg checks rather than prevents

An extern is, by definition, something the module does not own. Syg
type-checks references to it exactly as to owned objects, but whether the
declaration matches reality is a fact about a cluster.

### Kubernetes versions

The start-time failures are those of CHK-CFG-001..003, verified on k3s.
Secret key names are verified only when the snapshot was taken with
`--secret-keys`; without it, a Secret's existence is checked and its keys are
not.

### What Syg does not claim

Values: a key that exists may hold the wrong thing (`syg explain tier3`). The
snapshot is the cluster at capture time. Secrets are listed only where the
snapshot was granted that permission, and are otherwise skipped, not passed.

### Further reading

- `syg explain missing-key` (key references, checked without a cluster).

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## gateway-missing

`CHK-T2-NET-001` · error · checked against a cluster snapshot

The HTTPRoute is accepted and serves nothing: its parentRef matches no Gateway, or the Gateway's class has no controller.

### What you see

The route applies cleanly and serves nothing. Requests to its host get the
Gateway's 404, or no answer at all. The only trace is in the route's status:
`Accepted: False` with reason `NotAllowedByListeners` or `NoMatchingParent`, or
no status at all when nothing reconciles it.

### Why it happens

In the Gateway API, a route asks to attach to a Gateway through `parentRefs`,
and the Gateway decides. Its listeners say which routes they admit, by kind and
by namespace. A Gateway itself does nothing until the controller named by its
GatewayClass accepts the class and programs the data plane. The API server
validates none of this: a parentRef to a Gateway that does not exist is a valid
object.

### What Syg catches

An HTTPRoute whose parent Gateway is not in the cluster; whose Gateway's class
no controller has accepted; or whose Gateway has no HTTP or HTTPS listener that
admits it, because the listener named does not exist or admits routes only from
its own namespace (`allowedRoutes.namespaces.from: Same`, the default).

### Why Syg checks rather than prevents

Gateways are platform infrastructure in another namespace, run by a controller
Syg does not emit. Syg makes the attachment explicit (`extern gateway`, and
`via`), so the module states which Gateway and listener it depends on; whether
that Gateway exists, and admits this route, is a fact about a cluster.

### Kubernetes versions

Gateway API v1 (standard channel, v1.2.1). Observed on k3s v1.32.12 with the
Gateway API CRDs and no controller (2026-10): an HTTPRoute whose parentRef names
a nonexistent Gateway is created, and its status stays empty. Listener admission
(`allowedRoutes`, default `Same`) and the class Accepted condition are from the
Gateway API specification.

### What Syg does not claim

Hostname matching between the route and a listener's `hostname`, TLS certificate
validity, and the controller's own health are not checked. A route without a
known namespace (no environment, no `--namespace`) cannot be matched against
`allowedRoutes`, and is skipped. With `--target-traffic ingress`, routes are
Ingresses, which this rule does not model.

### Further reading

- Gateway API: Route attachment; Listener `allowedRoutes`; GatewayClass status.
- `syg explain CHK-NET-001` (the backend half, prevented at Tier 1).

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## policy-not-enforced

`CHK-T2-NET-002` · warning · checked against a cluster snapshot

Every NetworkPolicy is accepted and silently enforces nothing: traffic it was meant to block flows.

### What you see

None, which is the danger. The policy applies, lists and describes like any
other, and blocks nothing. Traffic it was written to stop flows freely, and the
first sign is the incident it was meant to prevent.

### Why it happens

NetworkPolicy is an API object only. The API server stores it; enforcement is
the CNI plugin's job, and Kubernetes does not require a plugin to do it. Flannel
implements none. Calico, Cilium, Antrea and kube-router do, and k3s runs an
embedded policy controller beside flannel unless it is started with
`--disable-network-policy`.

### What Syg catches

A NetworkPolicy in the module, in a cluster whose network plugin does not
enforce NetworkPolicy, or where the snapshot could not tell whether it does.

### Why Syg checks rather than prevents

Whether policies are enforced is a property of the cluster's network, not of the
module, and the same module is right on one cluster and inert on another. The
warning is loud on purpose: a tool that reported "network
policy verified" without it would mislead exactly where it matters.

### Kubernetes versions

NetworkPolicy semantics are stable since networking.k8s.io/v1 (Kubernetes 1.7).
The snapshot recognises the plugin from its DaemonSet in kube-system, and k3s
from its node arguments (`k3s.io/node-args`); the k3s case was observed on
v1.32.12 (2026-10). A plugin the snapshot does not recognise is reported as
unknown, never as enforcing.

### What Syg does not claim

That a policy is correct, or that an enforcing plugin enforces every policy
feature (some do not implement egress, or named ports). The detection is a
fingerprint: an unusual install may be misidentified, so the evidence is in the
snapshot for a reviewer to see.

### Further reading

- Kubernetes documentation: Network Policies ("you must be using a networking
  solution which supports NetworkPolicy").
- k3s documentation: network policy (the embedded kube-router controller).

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## placement-unsatisfiable

`CHK-T2-SCH-001` · error · checked against a cluster snapshot

Pods stay Pending with FailedScheduling: didn't match pod anti-affinity rules, or didn't match pod topology spread constraints.

### What you see

Pods stay Pending with "didn't match pod anti-affinity rules" or "didn't match
pod topology spread constraints (missing required label)". These cases are
correct on paper and impossible on this cluster.

### Why it happens

The scheduler filters nodes by taints, then by required anti-affinity, which
admits one matching pod per domain, then by strict spreads. That excludes nodes
lacking the key. What remains is what the cluster has.

### What Syg catches

Against a cluster snapshot:

- a strict self-avoid across a key with fewer domains for this workload than its
  effective minimum replica count (error), or than its autoscaler's maximum
  (warning);
- a spread across a label no node carries (strict: error; soft: warning);
- a declared `extern topology` domain count the cluster contradicts (warning).

Domains are counted from the snapshot (`nodes.domains`, distinct values per
label key). For a workload that tolerates none of the cluster's NoSchedule and
NoExecute taints, only untainted nodes count (`nodes.untaintedDomains`). A
workload that tolerates some of them is judged by every domain, an upper bound:
the snapshot keeps counts, not which node has which taint.

### Why Syg checks rather than prevents

Node inventory changes without the module changing. It is a Tier-2 fact, read
from a committed snapshot, so `check` stays offline.

### Kubernetes versions

Observed on k3s v1.32.12, one node, no zone label:

- two replicas with a strict self-avoid across hosts: one pod Pending;
- a strict spread across a label no node carried: every pod Pending;
- with the node tainted, a pod not tolerating the taint stayed Pending.

The snapshot of that cluster recorded the taint and the counts this rule reads.

### What Syg does not claim

That the cluster will have the same nodes at deploy time, or room on them
(CHK-T2-CAP-001). The tainted-node accounting is approximate when a workload
tolerates some taints and not others.

### Further reading

- https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## taint-mismatch

`CHK-T2-SCH-002` · warning · checked against a cluster snapshot

A toleration for a taint no node has does nothing; a taint on every node that the pods do not tolerate leaves them all Pending.

### What you see

A toleration for a taint that does not exist is usually a typo (`gpus` for `gpu`)
or a stale name, and it does nothing. The pods do not land on the dedicated
nodes the author had in mind, and since a toleration only permits, nothing pulls
them there either. A taint on every node that the pods do not tolerate leaves
them all Pending.

### Why it happens

A toleration matches a taint by key, by value (for `Equal`), and by effect (or
every effect). The scheduler places a pod only on a node whose NoSchedule taints
it tolerates; NoExecute also evicts running pods that do not tolerate it.

### What Syg catches

Against a cluster snapshot:

- a toleration of a custom taint that no node has (key, value and effect
  compared). Built-in taints are excluded, because the cluster places them only
  when it needs to;
- a NoSchedule or NoExecute taint that every node has and the workload does not
  tolerate.

### Why Syg checks rather than prevents

Taints are the cluster's; the module cannot know them without a snapshot.

### Kubernetes versions

Observed on k3s v1.32.12: with the node tainted `dedicated=gpu:NoSchedule`,
an untolerating pod stayed Pending ("1 node(s) had untolerated taint {dedicated:
gpu}") and a tolerating one ran. Against that cluster's snapshot the rule
reported both cases.

### What Syg does not claim

That a toleration puts pods on the tainted nodes: it only allows them there.
Placing them is a node selector's or affinity's job.

### Further reading

- https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## storage-class-unsupported

`CHK-T2-STO-001` · error · checked against a cluster snapshot

The claim never binds, so its pod stays Pending with no error on any object.

### What you see

The PersistentVolumeClaim stays `Pending`, and so does every pod that mounts it.
Nothing fails to apply. The claim's events say why, if anyone looks:
`ProvisioningFailed: storageclass.storage.k8s.io "slow" not found`, or, for an
unsupported mode on k3s's local-path provisioner, `NodePath only supports
ReadWriteOnce and ReadWriteOncePod`. The pod's own status says only that it is
waiting for its volume.

### Why it happens

A claim is bound by the provisioner of the StorageClass it names
(`spec.storageClassName`), or of the cluster's default class when it names none.
The class is resolved by name when the claim is provisioned, not when it is
created, so a missing class is never an admission error. A provisioner offers
only the access modes its storage can honour: a network block device attaches to
one node at a time, so ReadWriteMany is out of reach for it however the claim is
written.

### What Syg catches

A claim whose StorageClass is not in the cluster the snapshot describes, or that
names no class in a cluster with no default one, or that asks a class's
provisioner for an access mode it cannot provide (ReadWriteMany from a
block-storage provisioner, for instance).

### Why Syg checks rather than prevents

Which classes exist is a fact about a cluster, not about the module, and it
differs between clusters running the same module. Syg can make the dependency
explicit (`extern storageclass`, CHK-STO-004) but cannot know whether it is met
without looking at a cluster, which `check` never does. A snapshot
is that look, taken once and committed.

### Kubernetes versions

Observed on k3s v1.32.12 (2026-10): a claim naming a missing class stayed
`Pending` with the `not found` event above, and a ReadWriteMany claim on
`rancher.io/local-path` failed provisioning with the message above. The table of
access modes per provisioner comes from each driver's
documentation; a provisioner not in it is treated as unknown, and nothing is
reported for it.

### What Syg does not claim

The snapshot is the cluster at its capture time; a class created or deleted
since is not seen (a stale snapshot is reported). A supported access
mode does not guarantee capacity, quota or zone availability: the claim can still
wait for those. And an unknown provisioner is unknown, not approved.

### Further reading

- Kubernetes documentation: Storage Classes; Persistent Volumes, Access Modes.
- `syg explain CHK-STO-004` (the Tier-1 half: the class must be declared).

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

## api-version-not-served

`CHK-T2-VER-001` · error · checked against a cluster snapshot

The apply fails because the version was removed in this cluster's Kubernetes, or will fail at its next upgrade.

### What you see

The apply fails: `no matches for kind "HorizontalPodAutoscaler" in version
"autoscaling/v2"` on a 1.22 cluster, for instance. A deprecated version applies
today and breaks at the cluster upgrade that removes it, usually discovered
mid-upgrade.

### Why it happens

Kubernetes serves each API version for a range of releases. GA versions arrive
in a known release (autoscaling/v2 in 1.23), and deprecated beta versions are
removed on the published schedule of the deprecation policy.

### What Syg catches

An object at a built-in API version the cluster does not serve, because the
cluster is older than the version's introduction or newer than its removal; and,
as a warning, one the cluster serves but Kubernetes has scheduled for removal.

### Why Syg checks rather than prevents

Syg emits current GA versions, so a module compiled today is right for the
pinned version. What it cannot know without a snapshot is which version a given
cluster runs.

### Kubernetes versions

Syg's table of removals follows the Kubernetes deprecated
API migration guide (removals through 1.32). Syg's Tier-1 check already holds
`raw` objects to the pinned 1.32 schema; this rule compares with the actual
cluster's served versions instead, which is what differs when the cluster is not
1.32.

### What Syg does not claim

That a served version behaves identically across releases, or anything about
alpha feature gates.

### Further reading

- Kubernetes: Deprecated API Migration Guide; Deprecation Policy.

### Scope

A claim about the cluster as the snapshot recorded it, at the time it was captured. Without a snapshot the rule is skipped, never passed.

