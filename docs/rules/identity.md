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

