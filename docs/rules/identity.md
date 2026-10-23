# Identity and images

Permissions wider than they need to be, and images that can change under you.

## mutable-image-tag

`CHK-IMG-001` · warning · checked offline

Two deploys of the same manifest run different code, and a rollback returns to a tag whose contents have since changed, so it does not roll anything back.

### What you see

The manifest stops describing what runs.

A tag is a pointer, and pointers move. Two deploys of a byte-identical manifest, a
week apart, can run different code, and nothing in the cluster records that they
differed, because from Kubernetes' point of view nothing changed. The Deployment's
spec is the same, so a re-apply is a no-op; pods that restart pull whatever the tag
points at *now*, while pods that do not keep running the old image. A single
Deployment can end up running two versions simultaneously, indefinitely, with one
`image:` line in the source.

The consequence that matters most arrives during an incident. A bad release goes
out, and the response is to roll back to the previous tag. But the previous tag
is also mutable, and may point somewhere else than it did. The rollback completes,
reports success, and does not restore the code anyone believed it restored.
Debugging then proceeds from a false premise about what is running.

The no-tag case is the same failure with less warning: omitting a tag is not
"whatever was there", it is an explicit `latest`.

### Why it happens

An image reference is `registry/repository:tag` or `registry/repository@digest`. The
tag is a mutable label in the registry that can be repointed at any time; the digest
is a content hash and identifies exactly one image.

Two Kubernetes behaviours compound this. First, when no tag is given the reference
defaults to `latest`: omitting it is a choice, not an absence. Second, the default
`imagePullPolicy` is derived from the tag: `Always` for `latest`, `IfNotPresent`
otherwise. So `latest` maximises the chance that different nodes pull at different
moments and therefore run different content.

Kubernetes does not resolve tags at apply time and does not record what a tag
resolved to. There is no point at which the cluster remembers which image the
manifest meant.

### What Syg catches

`image "registry.example.com/api:latest"`, or an image with no tag at all, which
means `latest`.

In a study of 48 real configurations, mostly public Helm charts, 27.1% had this
mistake: the third most common found.

### Why Syg checks rather than prevents

Because a mutable tag is sometimes what the author wants, and the language should
not lie about that.

A development loop rebuilding `myapp:dev` on every commit is a real workflow, and
one Syg has no business forbidding. Preventing mutable tags would push that case
into an escape hatch, where it would get less scrutiny rather than more.

Severity is a `warning` by default and configurable by platform profile, which is
where this belongs: whether a production environment may run a mutable tag is a
policy decision, and `CHK-IMG-002` exists for teams that want digest pinning
enforced as a lock rather than advised as a rule.

The check itself is structural rather than textual. `types.ParseImage` splits the
reference into registry, repository, tag and digest, so `IsMutableTag` asks about
the *tag component*, so a registry with a port (`localhost:5000/app:1.2`)
is parsed correctly rather than mistaken for a tag, and a digest-pinned reference
that also carries a tag is correctly treated as pinned.

### Kubernetes versions

Verified against the kubernetes.io images documentation, including the default-to-
`latest` behaviour, the imagePullPolicy defaulting rules, and the description of
digests as immutable identifiers (checked 2026-08). Stable across supported versions.

### What Syg does not claim

Syg reads the reference, not the registry. It cannot tell you whether a version tag
like `:1.4.2` is *actually* immutable: plenty of registries permit overwriting one,
and some teams do. A digest is the only reference that is immutable by construction,
and the suggestion says so.

It also does not verify the image exists, is pullable, or contains what you expect.
Those are facts about a registry, not about source.

### Further reading

- https://kubernetes.io/docs/concepts/containers/images/
- https://kubernetes.io/docs/concepts/configuration/overview/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a version tag is actually immutable depends on your registry's policy. Only a digest is immutable by construction.

## image-not-pinned

`CHK-IMG-002` · error · checked offline

The same manifest runs different code over time: a tag can be moved to another image, so what was reviewed is not what a node pulls next.

### What you see

A tag is a pointer that the registry lets anyone with push access move. The
manifest that was reviewed and approved names `api:1.4.2`; next week a rebuild,
a compromised pipeline or an honest mistake pushes different content under the
same tag. The next pod scheduled pulls it, while older pods still run the old
image, and the cluster runs two programs under one name.

### Why it happens

The kubelet resolves a tag at pull time, and `imagePullPolicy` decides whether a
cached copy is reused. A digest (`@sha256:...`) is the hash of the image
manifest: the runtime verifies it, and it cannot name other content.

### What Syg catches

An image referenced by tag where pinning by digest is required. A profile can
require it, with `required digest` for every workload that uses the profile, or
`syg.yaml` can, with `require: { prod: [image-digest] }` for one environment (or
`default` for every build). Every container is checked, init containers and
sidecars included, after the environment's `image tag` or `image digest`
overrides are applied.

### Why Syg checks rather than prevents

Pinning is a platform policy, not a property every workload needs. A
development environment may deliberately follow a moving tag, which is why the
requirement is set per profile or per environment. Where it is set, it is
checked.

### Kubernetes versions

Image reference resolution is the container runtime's, checked against the
kubernetes.io "Images" documentation for 1.32. It is unchanged across supported
releases.

### What Syg does not claim

That the digest names the image you meant, or that it is free of
vulnerabilities. Syg checks the reference's form, not the registry. A digest
written by hand is as trustworthy as whoever wrote it.

### Further reading

- https://kubernetes.io/docs/concepts/containers/images/#image-names

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## wildcard-permission

`CHK-RBAC-003` · error · checked offline

The grant silently widens over time: a component installed next year introduces a new resource kind, and this rule already covers it.

### What you see

There is no symptom at the time. That is what makes the rule worth having.

A wildcard grant works. It works on the day it is written, it works in review, and
it works in production. The consequence arrives later, and it arrives without any
change to the source: someone installs a new controller or operator next quarter,
that component registers new resource kinds, and every wildcard rule in the cluster
silently expands to cover them.

So the permissions a wildcard grants are not the permissions anyone approved. They
are the permissions that existed at approval time, *plus everything added since*.
The audit that certified this workload was correctly scoped becomes untrue without
anybody editing the file that was audited.

### Why it happens

This rule rests on the RBAC **matching property**, and it is important to state it
as a factual property rather than as advice.

RBAC rules match by comparison against the request: a rule permits a request when
the request's verb appears in the rule's `verbs` and its resource appears in the
rule's `resources`. The `*` entry matches *any* value in that position. It is not
expanded at write time into the list of things that exist; there is no such
expansion step. Matching happens per request, against whatever the API server
serves at that moment.

The consequence follows directly: a rule with `verbs: ["*"]` matches verbs that do
not exist yet, and `resources: ["*"]` matches resource kinds introduced by a future
Kubernetes version or by a CRD installed tomorrow. An explicit list does not have
this property, which is the entire difference between the two.

**A note on grounding.** The rule rests on the matching property above, which is
checkable against the specification, and not on an "avoid wildcards" warning: the
primary RBAC documentation contains no such warning verbatim.

### What Syg catches

A `*` in the verbs or resources of a grant.

It reads RBAC written as `raw` objects too, so the escape hatch is not the way
around it:

- a raw `Role` or `ClusterRole` with `*` in a rule's `verbs`, `resources`,
  `apiGroups`, or a ClusterRole's `nonResourceURLs`, reported at that line;
- a raw `RoleBinding` or `ClusterRoleBinding` whose `roleRef` is the ClusterRole
  `cluster-admin`, which is every wildcard at once: over every verb, resource and
  API group, in the namespace for a RoleBinding and in the whole cluster for a
  ClusterRoleBinding.

### Why Syg checks rather than prevents

Because wildcards are sometimes correct, and a language that made them
unrepresentable would be lying about that.

A cluster-administration tool genuinely may need `*`. Some operators legitimately
manage resource kinds that do not exist until they create the CRDs. Removing the
ability to express this would push those cases into an escape hatch, where they
would receive *less* scrutiny than a flagged wildcard does.

So the wildcard is writable, and writing one produces a diagnostic pointing at the
exact `*`: not at the grant, at the token. Severity is configurable by platform
profile, so a team that has made a considered decision can set it to a warning
without losing the record that a decision was made.

### Kubernetes versions

Verified against the kubernetes.io RBAC authorization reference, which documents
`*` as matching all resources or all verbs in a `PolicyRule` (checked 2026-08).
Stable since `rbac.authorization.k8s.io/v1`.

### What Syg does not claim

Syg reports the wildcard. It cannot tell you whether your workload needs it: that
depends on what your code calls, which Syg does not read.

For raw RBAC, this rule is all that reads it. A raw binding to a role other than
cluster-admin, or a raw role that lists `secrets` among its resources, is not
judged: whom it grants what is for review. Every raw RBAC object gets an `info`
note that says so (`syg explain coverage`).

It also does not attempt to compute what a wildcard currently expands to in your
cluster. That would require knowing the installed API surface, which is a fact
about a running cluster rather than about source, and is out of scope for a Tier-1
check by construction.

### Further reading

- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- https://kubernetes.io/docs/concepts/security/rbac-good-practices/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## cluster-wide-permission

`CHK-RBAC-004` · error · checked offline

A namespaced Role naming a cluster-scoped resource grants nothing, so the workload gets 403 on a call its author believed was authorised.

### What you see

`403 Forbidden` on a call the author was certain they had authorised.

The grant reads correctly. `may get, list on nodes` is exactly what the workload
needs, and there it is in the Role, applied and green. But a namespaced Role cannot
grant access to nodes, so the permission is not merely insufficient: it does
nothing at all. Every object involved is valid. The rule is present in the Role and
the Role is bound. The call is still denied.

The usual next step is to widen the grant, retry, and eventually reach for a
ClusterRole with `*` because "RBAC is being difficult", turning a scoping mistake
into a permanent over-grant.

### Why it happens

Kubernetes resources are either namespaced or cluster-scoped. Pods, ConfigMaps,
Secrets and Services live in a namespace; Nodes, Namespaces, PersistentVolumes,
StorageClasses and CustomResourceDefinitions do not.

A `Role` is namespaced, and its rules are evaluated within its namespace. A rule in
a Role can only grant access to namespaced resources, because there is no namespace
for a cluster-scoped resource to be *in*. Granting access to cluster-scoped
resources requires a `ClusterRole`, bound with a `ClusterRoleBinding`.

Nothing rejects the mismatched Role. Naming `nodes` in a namespaced Role is legal
YAML and a legal API object; it simply matches no request that will ever be made.

### What Syg catches

A namespaced grant naming a resource kind that does not live in a namespace.

### Why Syg checks rather than prevents

The declaration is individually well-formed. `may get on nodes` is a sentence Syg
should be able to express; the mistake is only visible once you know that `nodes`
is cluster-scoped, which is a fact about Kubernetes rather than about the shape of
the grant.

Syg could have made cluster scope inferable, quietly upgrading such a grant to a
ClusterRole. It deliberately does not. Cluster-wide access is a meaningful
widening of blast radius, and the decision to take it should be visible in the
source at the line that takes it:

```syg
may get on nodes across cluster
```

So the opt-in is a keyword the author writes, and the rule reports the case where
they named a cluster-scoped kind without it. Silently doing the right thing here
would remove a reviewer's ability to see the choice.

### Kubernetes versions

Verified against the kubernetes.io RBAC authorization reference, which states that
a Role sets permissions within a particular namespace, and that a ClusterRole is
needed for cluster-scoped resources such as nodes (checked 2026-08).

### What Syg does not claim

The list of cluster-scoped kinds Syg knows is a fixed set covering the core API and
common extensions. It does not know the scope of custom resources introduced by
CRDs in your cluster: determining that requires reading installed CRDs, which is a
Tier-2 concern. A grant naming a cluster-scoped custom resource without
`across cluster` will not be reported.

Syg also does not check the converse: a `across cluster` grant on a namespaced kind
is legal (a ClusterRole may grant namespaced resources across all namespaces) and
is intentionally not flagged here, though it is a genuine widening.

### Further reading

- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## unused-identity

`CHK-RBAC-005` · info · checked offline

Permissions are declared and reviewed but grant nothing, because nothing runs as the account.

### What you see

None, directly, which is why this is an `info` and not a warning.

The cost is to people rather than to the running system. An unused identity is
reviewed in every security audit, considered in every "who can read our secrets"
question, and carried forward through every migration, while granting nothing to
anybody. It also misleads: someone reading the module reasonably concludes that
*something* runs with these permissions, and reasons about the blast radius of a
compromise accordingly.

The more concerning version is the leftover: a workload was deleted, its identity
was not, and the permissions it was granted now sit unattached. If a future
declaration reuses the name, it silently inherits a permission set nobody chose for
it.

### Why it happens

There is no mechanism to describe, and that is the point. A ServiceAccount with a
Role and a RoleBinding, running no pods, is a completely valid and completely inert
configuration. Kubernetes has no notion of an unused account and no reason to
report one: the objects are well-formed and the API server has no opinion about
whether anything uses them.

Only a whole-module view can see this, because it requires knowing every workload
in the module and what each runs as.

### What Syg catches

An `identity` declaration that no workload runs as.

### Why Syg checks rather than prevents

Preventing it would mean refusing to compile a module whose identity is not yet
referenced, which would make ordinary work unpleasant: declaring the identity
before the service that will use it is a perfectly reasonable order to write things
in, and an author part-way through a change should not be blocked.

It is also not always a mistake. An identity may be declared for a workload that
lives in another module, or kept deliberately during a migration. Reporting it at
`info` says "this is worth a look" without asserting it is wrong.

Syg does not emit the ServiceAccount, Role, or RoleBinding for an unreferenced
identity. Reporting dead configuration and then creating it anyway would be
incoherent.

### Kubernetes versions

Not version-dependent. This concerns the relationship between declarations within a
module, not any Kubernetes behaviour.

### What Syg does not claim

Syg sees one module. An identity unused here may be used by a workload in another
module that shares the namespace, and Syg has no way to know that. The diagnostic
says nothing runs as it *in this module*, which is the honest scope of the claim.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- https://kubernetes.io/docs/concepts/security/rbac-good-practices/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## host-access

`CHK-SEC-002` · error · checked offline

Where Pod Security baseline is enforced, the workload is accepted and its pods are refused, forever (FailedCreate, zero replicas); where it is not, they run with the node's processes, network or files, and a compromised container is a compromised node.

### What you see

It depends on the namespace the pods land in.

Where Pod Security admission enforces the `baseline` level (a namespace
labelled `pod-security.kubernetes.io/enforce: baseline` or stricter, or a
cluster-wide default), a Deployment, DaemonSet or Job with such a template is
accepted, with a warning, and every pod its controller then creates is refused.
The workload sits at zero ready replicas, and the reason is in `FailedCreate`
events on the ReplicaSet: `violates PodSecurity "baseline:latest": host
namespaces (hostNetwork=true, hostPID=true), hostPath volumes (volume "root"),
privileged (container "agent" must not set securityContext.privileged=true)`. A
bare Pod is refused when it is applied.

Where nothing enforces it, the pods run, and nothing says anything at the time.
The cost arrives with the first compromise of one of these containers: what
takes the container also has the part of the node the pod was given, and from
the node, the credentials of everything else that runs there.

### Why it happens

Each setting removes part of the isolation between a container and its node:

- **privileged** gives the container every capability and the node's devices;
  Pod Security's own description is that privileged pods disable most security
  mechanisms.
- **hostPID** puts the container in the node's process namespace: it sees every
  process on the node, and with the capabilities to do so can signal or trace
  them.
- **hostNetwork** gives the pod the node's network stack: it can bind the
  node's addresses and reach what listens on the node's loopback, and
  NetworkPolicy's behaviour for such pods is undefined, left to the network
  plugin.
- **hostIPC** shares the node's System V IPC and POSIX shared memory.
- **hostPath** mounts a path of the node's filesystem; `/` is all of it, the
  kubelet's credentials and the container runtime's socket included.
- **hostPort** binds a port on the node's own address, outside the Service
  that would otherwise front the pod.
- **Windows HostProcess** runs the container as a process on the Windows host.

The Pod Security Standards' `baseline` level, "minimally restrictive policy
which prevents known privilege escalations", forbids every one of them, and
Pod Security admission enforces it per namespace.

### What Syg catches

A pod spec that gives its pods part of their node:

- a privileged container (`securityContext.privileged: true`), init containers
  included;
- a host namespace: `hostNetwork`, `hostPID` or `hostIPC`;
- a `hostPath` volume;
- a container port with a `hostPort`;
- a Windows HostProcess pod or container.

A workload Syg derives cannot have any of these: the language has no way to
write them. A `raw` object can, so the rule reads the pod spec of every raw
Pod, PodTemplate, ReplicationController, Deployment, ReplicaSet, StatefulSet,
DaemonSet, Job and CronJob. The escape hatch is not the way around the
language. It reads a custom resource's too: each mapping in one with a list of
containers, or of init containers, is a pod spec, wherever it is: an Argo
Rollout's `spec.template.spec`, an Elasticsearch's
`spec.nodeSets[0].podTemplate.spec`, a Prometheus's `spec`, which takes a pod's
fields as its own, an item of a list, or one inside another. Each object is
reported once, at the first such setting, with the others marked beside it.

### Why Syg checks rather than prevents

For the workloads Syg derives it is a prevention: there is nothing to write.
For raw objects it is a check, because some workloads do need their node: a
network plugin, a log collector reading `/var/log`, a node exporter, a storage
driver. Refusing them would leave no way to declare them in Syg at all.

So the raw object is written as it is, and the rule reports what reaches the
node, as an error by default. A module that runs a node agent sets
`host-access: off`, or `warning`, under `rules:` in `syg.yaml`, which records
that the decision was made.

### Kubernetes versions

Checked on Kubernetes 1.32 (k3s v1.32.12, 2026-10-20), with server-side dry
runs and one Deployment created for real. In a namespace labelled
`pod-security.kubernetes.io/enforce: baseline`, a Pod with `hostNetwork`,
`hostPID`, a `hostPath` volume and a privileged container is refused, the
message naming each; so are `hostIPC`, a `hostPort`, a privileged init
container and a pod-level Windows HostProcess. A Deployment with the same
template is accepted with a warning, and its ReplicaSet's pods are refused
(`FailedCreate`). Without the label, the same Pod is accepted. Pod Security
admission is stable since Kubernetes 1.25.

### What Syg does not claim

Syg reports the settings. Whether the workload needs them depends on what it
does, which Syg does not read.

It does not check the rest of Pod Security's baseline level: capabilities a
container adds, seccomp, AppArmor and SELinux options and sysctls are
`CHK-SEC-003`'s, for raw pod specs and for the workloads Syg derives. Nor does
it check the `restricted` level.

In a custom resource it reads what has a pod spec's shape, and nothing else: a
container written another way, as an Argo Workflow's single `container`, or a
pod spec inside a string, is not read, and the coverage note names the rule
for an object that may run pods and holds no pod spec it can read (`syg
explain coverage`). There it decodes only the fields it judges, each on its
own, so that a value of the wrong type elsewhere hides nothing; one it judges,
of the wrong type, is a warning. Whether the operator runs pods from what it
reads is the operator's; the rule reads the spec as written, so a custom
resource that holds pod templates as data, a policy's patterns or a
documentation kind's examples, is judged as one that runs them: keep such
objects in a module whose `syg.yaml` turns the rule off or down. Whether your
namespaces enforce Pod Security is a fact of the cluster, which a Tier-1 check
does not see.

### Further reading

- https://kubernetes.io/docs/concepts/security/pod-security-standards/
- https://kubernetes.io/docs/concepts/security/pod-security-admission/
- https://kubernetes.io/docs/concepts/storage/volumes/#hostpath
- https://kubernetes.io/docs/concepts/services-networking/network-policies/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## kernel-privileges

`CHK-SEC-003` · error · checked offline

Where Pod Security baseline is enforced, the workload is accepted and its pods are refused, forever (FailedCreate, zero replicas); where it is not, the container runs with kernel powers, such as SYS_ADMIN or every system call, that make a compromised container a compromised node.

### What you see

It depends on the namespace the pods land in.

Where Pod Security admission enforces the `baseline` level, the Deployment,
StatefulSet or Job is accepted with a warning, and every pod its controller
then creates is refused. The workload sits at zero ready replicas, and the
reason is in `FailedCreate` events: `violates PodSecurity "baseline:v1.32":
non-default capabilities (container "api" must not include "NET_ADMIN",
"SYS_ADMIN" in securityContext.capabilities.add), seccompProfile (container
"api" must not set securityContext.seccompProfile.type to "Unconfined")`. A
bare Pod is refused when it is applied.

Where nothing enforces it, the pods run, and nothing says anything at the time.
The cost arrives with the first compromise of the container: what takes it
also has the powers it was given over the node's kernel.

### Why it happens

A container is a set of processes on its node's kernel, confined by what the
kernel lets them do:

- **Capabilities** divide root's powers. The runtime's default set is what an
  ordinary process inside a container needs. `SYS_ADMIN` alone covers mounting
  filesystems and much of what a privileged container can do; `NET_ADMIN`
  reconfigures the network; `SYS_PTRACE` reads and writes other processes'
  memory; `DAC_READ_SEARCH` reads any file by handle, the basis of known
  container escapes.
- **seccomp** filters the system calls a container may make. `RuntimeDefault`
  blocks the ones containers have no use for, many of them the way into kernel
  vulnerabilities; `Unconfined` allows every one.
- **AppArmor** and **SELinux** confine what a process may touch, by profile
  and by label. `Unconfined`, or an SELinux type such as `spc_t` (a "super
  privileged container"), turns that confinement off.
- **sysctls** set kernel parameters. The safe ones are namespaced, so a pod
  changes only its own; any other changes the node for every pod on it.

The Pod Security Standards' `baseline` level, "minimally restrictive policy
which prevents known privilege escalations", forbids each of these, and Pod
Security admission enforces it per namespace.

### What Syg catches

A container that asks the kernel it shares with its node for more than Pod
Security's `baseline` level allows:

- a Linux capability beyond the container runtime's default set. Baseline lets
  a container add only `AUDIT_WRITE`, `CHOWN`, `DAC_OVERRIDE`, `FOWNER`,
  `FSETID`, `KILL`, `MKNOD`, `NET_BIND_SERVICE`, `SETFCAP`, `SETGID`,
  `SETPCAP`, `SETUID` and `SYS_CHROOT`. Names are compared as written, so
  `CAP_CHOWN` and `ALL` are refused too;
- a seccomp profile of `Unconfined`, for the pod or a container;
- an AppArmor profile of `Unconfined`, by field or by the
  `container.apparmor.security.beta.kubernetes.io/NAME: unconfined`
  annotation;
- an SELinux user or role, or an SELinux type other than `container_t`,
  `container_init_t`, `container_kvm_t` and `container_engine_t`;
- a sysctl outside the safe set, the ones the kernel keeps apart for each pod.

Two of these can be written in the language, and the rule reads every
container of every workload Syg derives for them: `security { add ... }` with a
capability beyond the default set, and `seccomp Unconfined`. A workload's
`security` block applies to each container in its pod, sidecars and init
containers included, so it is reported once, naming each container that has
it. A `raw` object can carry all five, so the rule reads the pod spec, and the
pod template's annotations, of every raw Pod, PodTemplate,
ReplicationController, Deployment, ReplicaSet, StatefulSet, DaemonSet, Job and
CronJob, and each pod spec in a custom resource, as `CHK-SEC-002` does: a
mapping with a list of containers or of init containers, wherever it is, as an
Argo Rollout's `spec.template.spec`, with the annotations of the `metadata`
beside it. Each object is reported once, at the first such setting, with the
others marked beside it.

### Why Syg checks rather than prevents

Some workloads need these powers: a network plugin needs `NET_ADMIN`, a
debugger `SYS_PTRACE`, a tool that builds images some of `SYS_ADMIN`. Refusing
them would leave no way to declare those workloads in Syg at all.

So the workload is compiled as written, and the rule reports what it asks of
the kernel, as an error by default. A module that runs such a workload sets
`kernel-privileges: off`, or `warning`, under `rules:` in `syg.yaml`; every
check then names the rule as one that did not run. A profile can also lock the
whole `security` item (CHK-SEC-001), so that a platform team's golden path
cannot be given these powers at all.

### Kubernetes versions

Checked on Kubernetes 1.32 (k3s v1.32.12, 2026-10-20), with server-side dry
runs in a namespace labelled `pod-security.kubernetes.io/enforce: baseline`
and `enforce-version: v1.32`. Each capability of the default set, alone, is
accepted; `SYS_ADMIN`, `NET_ADMIN`, `NET_RAW`, `SYS_PTRACE`,
`DAC_READ_SEARCH`, `ALL`, `CAP_CHOWN` and `chown` are refused, in an init
container too. seccomp and AppArmor `Unconfined`, at the pod and at a
container, and the AppArmor annotation `unconfined`, are refused;
`RuntimeDefault` and `Localhost` are accepted. An SELinux user, a role, and the
type `spc_t` are refused; the four container types and a level are accepted.
The twelve safe sysctls are accepted, among them `net.ipv4.tcp_rmem` and
`net.ipv4.tcp_wmem`, new in 1.32; `kernel.msgmax`, `net.core.somaxconn` and
`net.ipv4.ip_forward` are refused, and so is a safe one written with `/` for
`.`. A Deployment Syg built with `add SYS_ADMIN, NET_ADMIN` and
`seccomp Unconfined` was accepted with a warning, and its ReplicaSet's pods
were refused (`FailedCreate`). Pod Security admission is stable since
Kubernetes 1.25.

### What Syg does not claim

Syg reports the settings. Whether the workload needs them depends on what it
does, which Syg does not read.

It checks Pod Security's `baseline` level, not `restricted`, which also
requires dropping every capability, running as non-root and a seccomp profile.
The `/proc` mount type (`procMount: Unmasked`), which baseline also forbids, is
left out: Kubernetes 1.32 stores it as `Default` unless its `ProcMountType`
feature gate is on, which it is not by default, and the server accepted it. Host namespaces, hostPath volumes, host ports and
privileged containers are `CHK-SEC-002`'s.

In a custom resource it reads what has a pod spec's shape, and nothing else,
as `CHK-SEC-002` does: a container written another way is not read, and the
coverage note names the rule for an object that may run pods and holds no pod
spec it can read. It decodes only the fields it judges, each on its own, and
one of the wrong type is a warning. A custom resource that holds pod templates
as data is judged as one that runs them, as for `CHK-SEC-002`. Whether your
namespaces enforce Pod Security is a fact of the cluster, which a Tier-1 check
does not see.

### Further reading

- https://kubernetes.io/docs/concepts/security/pod-security-standards/
- https://kubernetes.io/docs/concepts/security/pod-security-admission/
- https://kubernetes.io/docs/tutorials/security/seccomp/
- https://kubernetes.io/docs/tutorials/security/apparmor/
- https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/
- https://man7.org/linux/man-pages/man7/capabilities.7.html

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

