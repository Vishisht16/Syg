# coverage: what a reduced-coverage note means

**Not a rule.** This note explains one kind of `info` diagnostic.

## What the note says
A check ran, and part of the module was invisible to it. The note names the object
it could not see into and the checks affected:

```
info[coverage]: reduced coverage: raw DaemonSet log-agent is opaque to CHK-CFG-006, CHK-RBAC-005, CHK-STO-002
```

## Why Syg reports it instead of a clean result
Every Tier-1 check is a claim about the **closed world**: the module, its imports,
and its `extern` declarations. Some checks are only sound if they see *every* object
of some kind:

- **Objects that run pods** (Deployments, Jobs, DaemonSets, Pods...). `CHK-CFG-006`
  says a config is unused, `CHK-RBAC-005` that an identity is unused, and
  `CHK-STO-002` that a ReadWriteOnce claim is mounted by one workload. Each is true
  only if no pod Syg cannot see uses the thing. (`CHK-SEC-002` and
  `CHK-SEC-003` do read a raw object's pod spec, below, and report what they
  find there.)
- **Objects that route traffic** (Services, Ingresses, Routes). `CHK-NET-005` says
  no two routes claim a host and path, and `CHK-PRB-005` says which workloads
  receive traffic.
- **Objects that constrain availability** (HorizontalPodAutoscalers,
  PodDisruptionBudgets, and VerticalPodAutoscalers, which evict pods to apply the
  requests they choose). `CHK-PDB-001/002/005` and `CHK-HPA-005` judge a budget
  against a replica floor that another HPA or budget would change.

A `raw` block is opaque by design: Syg validates its shape against the Kubernetes
schema, but it does not model what the object *does*. A raw DaemonSet that mounts
`settings` makes "`settings` is unused" false, and the check cannot know that. A
clean result in that situation would read as a proof it is not. So the check still
runs over everything else, and the note states the limit.

A kind with no schema, which in practice means a CRD, is treated as able to do
anything. An Argo Rollout runs pods, a KEDA ScaledObject creates an HPA, and
nothing in a kind's name says which it is. So is an admission mutator (a
`MutatingWebhookConfiguration`, a `MutatingAdmissionPolicy`): it can change any
object as it is created, after Syg checked it, so every check that depends on
what is emitted reports reduced coverage for it.

## Pod specs in custom resources
`CHK-SEC-002` and `CHK-SEC-003` read a raw object's pod spec rather than
assume they see every pod. A built-in kind holds one, where its schema puts
it. A custom resource's kind does not say where, so they read every mapping in
it with a list of containers, or of init containers, wherever it is: an Argo
Rollout's `spec.template.spec`, an Elasticsearch's
`spec.nodeSets[0].podTemplate.spec`, a Prometheus's `spec`, an item of a list,
and one inside another. Only the object's own `metadata` and `status` are
passed over. The note says where they read, and that they read nothing else in
it:

```
info[coverage]: reduced coverage: raw Rollout web is opaque to CHK-CFG-006, CHK-NET-005, CHK-PRB-005, CHK-RBAC-005, CHK-STO-002
   = consequence: ...; CHK-SEC-002 and CHK-SEC-003 read its pod spec at spec.template.spec, and nothing else in it
```

A custom resource that may run pods and holds none they can read is opaque to
them, and the note names them with the rest: a kind Syg knows nothing of, or
an Argo Workflow whose templates each name one `container`. A pod spec inside
a string is not read either.

In a custom resource they decode only what they judge, each value on its own:
the pod's host namespaces and what they read of its security context, each
volume's `hostPath`, and in each container what they read of its security
context, each capability it adds and each port's `hostPort`. A value of the
wrong type anywhere else, an image given as a list or a `runAsUser` beside
`privileged`, hides nothing, and is not theirs to warn of. One they read, of
the wrong type, is a warning at its line, since what it asks of the node is
not judged:

```
warning[coverage]: raw Widget w: spec.template.spec.containers[1].securityContext.privileged does not decode as a pod's, so CHK-SEC-002 and CHK-SEC-003 cannot judge it
```

A custom resource that holds pod templates as data, a policy's patterns or a
documentation kind's examples, is read as one that runs them. Keep such
objects in a module of their own, whose `syg.yaml` sets the two rules to a
warning or off.

## Objects no check judges
Other kinds in the schema neither run pods, route traffic nor constrain
availability: RBAC, validating webhooks, namespaces, quotas, priority classes.
No check's verdict depends on them, so no check reports reduced coverage for
them. That would leave them unmentioned, and a raw ClusterRoleBinding to
cluster-admin would pass as silently as a ConfigMap. So each gets a note of its
own:

```
info[coverage]: raw ValidatingWebhookConfiguration shop-policy is checked against the Kubernetes schema only: no rule judges what it does
```

Its fields were validated, and it is emitted as written; what it allows, denies
or changes in the cluster is for review, as for a hand-written manifest. Raw
RBAC is the exception in part: `CHK-RBAC-003` reads raw Roles, ClusterRoles and
their bindings for wildcards and for cluster-admin, and the note says that is
all it reads. A raw NetworkPolicy gets no note, because `CHK-NP-002` evaluates
it, and neither does an object a `relate` declaration describes.

A `relate` declaration changes that. A relate states what a
kind's fields mean, so a related object is no longer opaque to the checks those
meanings serve: a config it references counts as consumed, and an identity it
references counts as used. It keeps one class of reach. A kind that names a
service as a destination routes traffic, and the traffic checks (`CHK-NET-005`,
`CHK-PRB-005`) do not follow a relation, so they still report reduced coverage
for it. A kind related through a pod template (`spec.template.spec...`, an
Argo Rollout) runs pods, which can mount claims and read what no relation
names, so it keeps the workload checks' note too, and so does a related
object that holds a pod spec no relation names a path in. See `syg explain crd`.

## Resources of an imported module
An import brings in a module's types, profiles, schemas and relations. What
the module deploys (its workloads, identities, policies, configs, secrets and
raw objects) belongs to its own build: a build that imports it type-checks
them, but does not emit them, and runs none of its rules on them. A raw
binding to cluster-admin in an imported module is neither deployed nor judged
by `CHK-RBAC-003` there. So the import says so, once per module:

```
info[coverage]: module platform declares 1 service and 2 raw objects, which this build type-checks but does not emit or run its rules on
```

To cover them, check and build that module itself, where they are its own. To
deploy one of them with the importing module, declare it there.

## What to do about it
Usually nothing: the note is advisory, and `syg check` still exits 0. It is there so
that whoever reads the result knows how far it extends. Two ways to remove it:

- express the object natively, if Syg has a construct for it, so that the checks
  can see it; or
- accept it. Some objects, such as controller infrastructure, admission webhooks
  and RBAC for a controller, belong in `raw`, and the note is the honest record
  of that.

## What Syg does not claim
The note is about objects Syg was *given* and could not model. It says nothing about
objects Syg was never given: workloads applied by other tools, or other teams'
modules in the same namespace. Those are outside the closed world entirely, and the
soundness claims of every check are scoped to that world (`syg explain closed-world`).
