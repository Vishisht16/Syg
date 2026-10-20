# Mistakes you can't make

Mistakes the language makes impossible to write, so Syg never has to report them.

Each of these is a mistake that hand-written Kubernetes YAML makes easy and Syg makes impossible: there is no way to write it. Syg still guards each one inside the compiler, so if a guard ever fired, it would be a bug in Syg, reported as one. They are listed here because knowing what you no longer have to check for is the point.

## missing-config

`CHK-CFG-001` · error · prevented: the language cannot express it

The pod never starts: it sits in CreateContainerConfigError, which reads as a container problem rather than a missing object.

### What you see

The pod never starts, and the error names the wrong thing.

The pod is scheduled, the image is pulled, and then the kubelet fails to construct
the container because it cannot resolve the reference. The status is
`CreateContainerConfigError`. That reads like a container problem (a bad entrypoint,
a broken image), and the first hour of debugging usually goes there. The actual
cause is a name typed in one file that does not match a name in another, or a
ConfigMap that lives in a different namespace, or one the deploy step forgot.

The pod retries this indefinitely. Nothing else in the system is unhealthy, and the
Deployment simply never reaches its desired replica count.

### Why it happens

`envFrom.configMapRef.name`, `env.valueFrom.configMapKeyRef.name`, and
`volumes.configMap.name` are all plain strings. They are resolved by the kubelet at
container-creation time, in the pod's namespace, and nothing validates them earlier:
not the API server on admission, not the scheduler.

So the reference is checked, but at the last possible moment, on the node, after
scheduling and image pull have already succeeded. Every object involved is
individually valid. The graph between them is broken, and the only thing that
notices is a kubelet, at runtime, reporting it in a way that points at the
container rather than the missing object.

### What Syg catches

A container consuming a ConfigMap that no manifest creates.

### How Syg prevents it

`needs config app-settings` is a typed reference, not a string. The name resolver
binds it to a `config` declaration in the module symbol table before a graph is
ever built. A name that does not resolve is a compile error at that source line,
with an edit-distance suggestion drawn from the names actually in scope.

The emitted `configMapRef.name` is then taken from the resolved node, the same
node the ConfigMap manifest is generated from, so the consumer and the object
cannot name different things.

Namespace agreement (`CHK-CFG-004`) comes free from the same design: a module
derives one namespace for everything in it, and there is no field in which to write
a different one, so the cross-namespace version of this failure is likewise
unrepresentable.

The reference is kind-checked too: `needs config db-credentials` where
`db-credentials` is a `secret` reports a kind mismatch pointing at both sites,
rather than a misleading missing-name error.

`extern config` covers a ConfigMap genuinely managed outside the module. Syg will
not emit it and cannot verify it exists; the gap is recorded as reduced coverage
rather than assumed sound.

### Kubernetes versions

Verified against the kubernetes.io ConfigMap documentation and the pod lifecycle
error states (checked 2026-08). Stable across supported versions.

### What Syg does not claim

Syg guarantees the reference resolves within the closed world it can see. It does
not verify that an `extern config` exists in your cluster: that requires cluster
access, which no stage of `check` or `build` has by design.

Whether the ConfigMap's *contents* are correct is a separate question;
`CHK-CFG-003` checks that a named key is declared, but the value behind that key is
not something Syg can reason about.

### Further reading

- https://kubernetes.io/docs/concepts/configuration/configmap/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## missing-secret

`CHK-CFG-002` · error · prevented: the language cannot express it

The same stuck pod, with the same misleading error, for a secret nobody created.

### What you see

The same stuck pod as `CHK-CFG-001`, with the same misleading error
(`CreateContainerConfigError`, pointing at the container rather than at the absent
object), but with a worse failure profile around it.

Secrets are more often managed outside the deployment that consumes them: created
by a secrets operator, synced from an external vault, or applied once by hand
during environment setup. That makes the reference more likely to be correct in one
environment and wrong in another. The service works in staging, where somebody
created the Secret months ago, and fails on first deploy to a new region where
nobody did.

It also fails *late* in a particular way. Because the missing object is a
credential, the natural debugging reflex (describe the pod, read the error, check
the container) is exactly the wrong direction, and the real answer lives in a
different system entirely.

### Why it happens

`envFrom.secretRef.name`, `env.valueFrom.secretKeyRef.name`, and
`volumes.secret.secretName` are plain strings, resolved by the kubelet at
container-creation time in the pod's namespace. Nothing validates them at admission.
The pod schedules, the image pulls, and only then does the container fail to be
constructed.

### What Syg catches

A container consuming a Secret that no manifest creates.

### How Syg prevents it

`needs secret db-credentials` is a typed reference resolved against a `secret`
declaration in the module symbol table. An unresolved name is a compile error with
a suggestion; the emitted `secretRef.name` comes from the resolved node.

Two design decisions matter here beyond the resolution itself.

First, **a `secret` declaration declares keys only, never values**. Writing `key DATABASE_URL = "postgres://..."` in Syg source is
a compile error. Values belong in a secrets manager; source control is not a
secrets manager, and a language that made it convenient to put them there would be
doing harm regardless of how good its checking was.

Second, and following from the first, **Syg emits no Secret object at all**. It
declares the shape and wires the references; the values arrive from whatever system
owns them. So the "existence" this rule prevents is existence *of the reference
target within the closed world*, meaning that a declaration exists describing what
this service consumes, not a claim that the credential is populated in your cluster.

`extern secret` is the honest form for a Secret managed entirely elsewhere: the
name resolves, nothing is emitted, and the gap is recorded as reduced coverage.

### Kubernetes versions

Verified against the kubernetes.io Secret documentation, including its statement
that Secrets are namespaced objects resolved within the pod's namespace (checked
2026-08). Stable across supported versions.

### What Syg does not claim

Syg cannot tell you whether the Secret exists in your cluster, whether it has been
populated, or whether its values are correct. Every one of those requires cluster
access, which no stage of `check` or `build` has by design, and which
`syg check` must not have, since it is meant to run safely on untrusted pull
requests with no credentials at all.

What it prevents is narrower and still worth having: the class where the consumer
and the declaration disagree about the name.

### Further reading

- https://kubernetes.io/docs/concepts/configuration/secret/
- https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## cross-namespace-reference

`CHK-CFG-004` · error · prevented: the language cannot express it

The pod never starts, with the same CreateContainerConfigError as a missing object: the object exists, just in a namespace the pod cannot see.

### What you see

It is the missing-object failure, made worse because the object is not missing.

For a ConfigMap or Secret, the pod is scheduled, the image is pulled, and the
container is never created. The pod sits in `CreateContainerConfigError`, and the
event reads `configmap "settings" not found`. Whoever is debugging runs `kubectl get
configmap settings`, perhaps with their own default namespace set to the platform
team's, sees that it exists, and stops trusting the error message.

A ServiceAccount fails earlier and more quietly. No pod is created at all: every
attempt by the ReplicaSet is refused with `FailedCreate … error looking up service
account checkout/deployer: serviceaccount "deployer" not found`. The Deployment
stays at zero ready replicas, and the reason is visible only in the ReplicaSet's
events, not on any pod, because there is no pod.

The failure is most likely exactly where a platform publishes a golden path. A
shared object lives in the platform team's namespace, and an application team
references it by name from theirs.

### Why it happens

ConfigMaps, Secrets and ServiceAccounts are namespaced objects. The fields that
reference them from a pod (`configMapRef.name`, `secretKeyRef.name`,
`volumes.configMap.name`, `serviceAccountName`) are bare names with no namespace
component. They are always resolved in the pod's own namespace, and there is no
syntax for any other. The Kubernetes ConfigMap documentation states that the Pod and
the ConfigMap must be in the same namespace.

The resolution happens late, in two different places:

- the kubelet resolves configs and secrets when it constructs the container, on
  the node, after scheduling;
- the `ServiceAccount` admission plugin resolves `serviceAccountName` when the pod
  object is created. That is the controller creating it, not `kubectl apply` of the
  Deployment, so the apply succeeds.

### What Syg catches

A pod whose ConfigMap, Secret or ServiceAccount exists, but in a different
namespace from the pod.

### How Syg prevents it

A Syg module is the unit that is deployed into one namespace. Within a module there
is nowhere to write a namespace: every config, secret, identity and workload a
module declares lands together, so a reference resolved inside the module cannot
cross a namespace. `CHK-CFG-001` and `CHK-CFG-002` already guarantee the reference
resolves.

Imports (`import "platform.paved" as paved`) are what could open a gap, because they
make another module's declarations visible. The resolver closes it at the
reference. A qualified reference to another module's `config`, `secret` or
`identity` resolves, so the diagnostic can name precisely what it points at, and is
then rejected at that source line. The suggestion is the fix: declare it in this
module, or use `extern` if something outside Syg creates it in this namespace.

Only cluster-scoped names cross the boundary, matching what Kubernetes itself
shares across namespaces. A `storage` class may be written `paved.fast-ssd`, and the
claim carries the class's cluster name.

A guard re-checks the property on the graph. Every config, secret and service
account a workload points at must be a node of the module's own graph, and a
violation is reported as a compiler bug rather than a user error.

### Kubernetes versions

Reproduced on a k3s cluster running Kubernetes v1.31.4 (2026-10). A ConfigMap and a
ServiceAccount were created in namespace `platform`, and two Deployments in
`checkout` referenced them. The first pod reached `CreateContainerConfigError`
(`configmap "settings" not found`). The second ReplicaSet reported `FailedCreate …
serviceaccount "deployer" not found` and created no pods. The same-namespace
requirement is documented for every supported version and has not changed.

### What Syg does not claim

An environment declares the namespace its build deploys to (or derives
`MODULE-ENV`), and Syg writes it on every namespaced object, so an environment's
output lands in one namespace by construction. A module without environments is
emitted without one, unless `syg build --namespace` names it, and then whoever
applies the output picks the namespace. Either way the guarantee is that a module's
objects reference each other only, so applying a module's output into any single
namespace is consistent. Syg cannot see how its output is applied, and splitting one
build across namespaces would break that.

Syg does not create the namespace. It must exist, as a platform team usually
ensures, before the output is applied.

An `extern config` or `extern secret` is assumed to exist in whatever namespace the
module is applied to. Syg has no cluster access during `check` or `build`, so that
remains an assumption, recorded as reduced coverage.

### Further reading

- https://kubernetes.io/docs/concepts/configuration/configmap/ ("The Pod and the
  ConfigMap must be in the same namespace")
- https://kubernetes.io/docs/concepts/configuration/secret/
- https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
- https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## autoscaler-target-missing

`CHK-HPA-001` · error · prevented: the language cannot express it

The autoscaler does nothing at all (no error, no events, no scaling), and the workload silently stays at whatever replica count it started with.

### What you see

Nothing, and "nothing" is the entire problem.

The HPA is created. `kubectl get hpa` lists it, with a name, a range, and a metric.
It reports no error. It emits no event anyone is watching. And it never scales
anything, ever. The workload sits at whatever replica count it was deployed with,
which is a *plausible* number, so no dashboard looks wrong.

The discovery moment is a traffic peak: load rises, capacity does not follow, and
the service degrades while an autoscaler that was supposed to prevent exactly this
sits inert in the same namespace. The post-mortem finds a one-character difference
between two strings in two files.

The near misses are equally quiet: the right name with the wrong `kind` (`Deployment`
where the workload is a `StatefulSet`), or the right name in the wrong namespace.

### Why it happens

`spec.scaleTargetRef` is an `apiVersion`/`kind`/`name` triple of plain strings. The
HPA controller resolves it against the scale subresource at reconcile time.

A reference that does not resolve is not an invalid object. The target may
legitimately be created after the HPA (that ordering is normal in GitOps), so there
is nothing for admission to reject. The controller records the failure in the HPA's
status conditions, which is a field almost nobody reads for an object that appears
to exist and appears fine.

### What Syg catches

An autoscaler whose `scaleTargetRef` names a workload that does not exist.

### How Syg prevents it

`scale` is an item *inside* the workload it scales:

```syg
service api {
  replicas 4
  resources { cpu 500m, memory 512Mi }
  scale on cpu at 70% between 4 and 20
}
```

There is no name to write, so there is no name to get wrong. The graph's `HPA` node
holds a `*Workload` pointer, and the emitted `scaleTargetRef` reads its `kind` and
`name` off that pointer: the same object the controller manifest is generated from.

Because the `kind` comes from the same pointer, the kind-mismatch variant is
prevented too: a `stateful` carrying a `scale` emits `kind: StatefulSet` without
anyone choosing it, and choosing it wrongly is not an available move.

The `Check` function is an invariant guard confirming the derivation held. If it
fires, the compiler contradicted itself, and the diagnostic says so.

### Kubernetes versions

Verified against the kubernetes.io HorizontalPodAutoscaler documentation and the
`autoscaling/v2` API reference for `scaleTargetRef` (checked 2026-08). `autoscaling/v2`
is stable since Kubernetes 1.23.

### What Syg does not claim

Syg guarantees the target resolves within the manifests it generates. It does not
know about HPAs created outside the module that might also target this workload:
two autoscalers on one workload fight, and that is invisible from here.

Whether the *metric target* is a sensible number for your traffic is not decidable
from source and is documented as Tier 3. Syg checks the precondition
(`CHK-HPA-002`) and declines to opine on the value.

### Further reading

- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## route-backend-missing

`CHK-NET-001` · error · prevented: the language cannot express it

An Ingress or HTTPRoute naming a Service that does not exist returns 502/503 for every request, while every object involved reports healthy.

### What you see

Every request to the host returns 502 or 503. The Ingress object is valid and
displays correctly; the Service it names simply is not there, or is spelled
differently. Nothing reports an error, because from each object's own point of
view nothing is wrong: the failure is in the edge between them.

### Why it happens

An Ingress backend names a Service by **string**:
`spec.rules[].http.paths[].backend.service.name`. Gateway API's HTTPRoute does the
same through `backendRefs[].name`. Neither is a checked reference. The API server
validates that the field is a well-formed name, not that anything answers to it.
When the ingress controller resolves the name and finds nothing, it has no
endpoints to route to and returns a gateway error.

### What Syg catches

An Ingress or HTTPRoute whose backend names a Service that does not exist. In Syg
this cannot be written, so the registered check is an invariant guard over the
compiler's own derivation rather than a check on your configuration.

### How Syg prevents it

`expose :http at "host"` names no backend at all. The backend is the enclosing
`service` declaration, and the compiler attaches it to the route as a resolved
pointer while building the graph. There is no production in the grammar for a
backend service name, so the mismatch has no syntax to be
written in. The Service itself is derived from the same declaration, so it
necessarily exists.

### Kubernetes versions

Verified against kubernetes.io Ingress documentation and the Gateway API
specification (checked 2026-08). The backend-by-name model is unchanged across
`networking.k8s.io/v1` and Gateway API v1.

### What Syg does not claim

Syg does not verify that an ingress controller is installed, that a Gateway
exists to attach the route to, or that DNS resolves the host. Those are cluster
facts, not source facts. A route to an `extern` service is typed but not verified
for existence, and is reported as reduced coverage.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/ingress/
- https://gateway-api.sigs.k8s.io/api-types/httproute/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## route-port-missing

`CHK-NET-002` · error · prevented: the language cannot express it

Routing to a port the Service does not expose yields refused connections.

### What you see

Connections are refused for that route while the Service works perfectly for
every other client. Because the Service exists and is healthy, attention goes to
the application rather than to the routing rule, which is where the mistake is.

### Why it happens

An Ingress backend port is given as `backend.service.port.name` or
`.port.number`, and an HTTPRoute's as `backendRefs[].port`. Both are matched
against the Service's `spec.ports` at routing time. A name with no match yields no
usable endpoint. This is a second string join, layered on top of the Service-name
join, which is why `CHK-NET-001` and this rule fail in the same way for different
reasons: the north-south path stacks references, and each one can dangle.

### What Syg catches

A route that resolves to the right Service but names a port that Service does not
expose. Unwritable in Syg; the registered check guards the derivation.

### How Syg prevents it

`expose :http` is a port *reference*, resolved against the ports declared on the
same service. An unresolved reference is a name-resolution error at the character
you wrote, listing the ports that do exist, not a runtime failure. The route in
the graph then holds a pointer to that specific port, and both the Service port
and the route's target are emitted from it.

### Kubernetes versions

Verified against kubernetes.io Service and Ingress documentation and the Gateway
API specification (checked 2026-08).

### What Syg does not claim

Syg does not verify that the container is actually listening on that port number;
a program that declares `port http 8080` and binds 9090 is a runtime fact
(Tier 3).

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/service/
- https://gateway-api.sigs.k8s.io/api-types/httproute/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## service-port-unmapped

`CHK-NET-003` · error · prevented: the language cannot express it

A Service targetPort with no matching containerPort yields refused connections.

### What you see

The Service has endpoints and looks entirely healthy, but every connection
through it is refused. The Pods are running and passing their probes; traffic is
simply being delivered to a port on which nothing is listening.

### Why it happens

A Service port has a `targetPort`, which may be a number or the *name* of a
container port. When it is a name, kube-proxy resolves it against the Pod's
`containerPort` entries. A name with no match means the endpoint address is
constructed with no valid port, and connections fail. The named form is the one
worth using (it survives a container port renumbering), and it is precisely the
form that introduces a string join between the Service and the pod template.

### What Syg catches

A Service whose `targetPort` names a port no container declares. Unwritable in
Syg; the registered check guards the derivation.

### How Syg prevents it

`port http 8080` is written once. The compiler emits it as the container port,
the Service port, and the Service's target, all from that one declaration. There
is no second place to write the name and therefore no way for the two to
disagree. The check verifies the compiler kept that promise.

### Kubernetes versions

Verified against kubernetes.io Service documentation (checked 2026-08). Named
`targetPort` resolution is long-standing and unchanged.

### What Syg does not claim

Same boundary as `CHK-NET-002`: that the process inside the container binds the
port it declared is not statically knowable.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/service/
- https://kubernetes.io/docs/reference/networking/virtual-ips/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## policy-peer-missing

`CHK-NP-001` · error · prevented: the language cannot express it

A peer selector that matches no pod allows nothing: the traffic it was written for is dropped.

### What you see

The traffic the rule was written for is cut. The client is refused or times
out. The policy reads correctly ("from app: web") and is valid, so the review
that approved it saw nothing wrong. The cause is a label: `app: web` where the
pods carry `app.kubernetes.io/name: web`, or a namespace label nobody set.

### Why it happens

A rule's peers are selectors. A `podSelector` is matched against pods in the
policy's namespace. A `namespaceSelector` is matched against namespaces' labels,
and its pods against the `podSelector` beside it. A selector matching nothing
is valid, and the rule then allows nothing.

### What Syg catches

A NetworkPolicy rule whose peer selector matches no pod, or a namespace selector
matching no namespace, so the rule allows nothing.

### How Syg prevents it

A peer is a reference, never a selector: a workload of the module, an extern
service, or `apiserver`.

- **Unknown names.** A name that resolves to nothing is a compile error with
  this code, naming the nearest declaration.
- **Workloads.** A workload peer's selector is derived from the workload, the
  same value its own pods carry.
- **Extern services.** An extern service's namespace is selected by
  `kubernetes.io/metadata.name`, which the API server sets on every namespace.
- **Other modules.** A workload of another module cannot be named. Its
  namespace is chosen by that module's environments, so it is declared here as
  an `extern service` with its namespace.
- **No selector syntax.** There is no syntax for a label selector, a namespace
  label or an address.

A `needs service` dependency resolves the same way.

### Kubernetes versions

Unchanged since `networking.k8s.io/v1` (Kubernetes 1.7). The
`kubernetes.io/metadata.name` namespace label Syg selects an extern service's
namespace by is set on every namespace since Kubernetes 1.21 (GA 1.22).

Observed on k3s v1.32.12:

- a peer workload of the module was admitted;
- an extern service's namespace was admitted, selected by that label;
- a pod of another namespace was refused.

### What Syg does not claim

An extern service's pods are not known. Without a namespace, an extern service
is selected as every pod of the module's namespace (`CHK-NP-003` flags it).
With one, it is every pod of that namespace. Syg does not check that an extern
service exists (`CHK-T2-EXT-001` does, against a snapshot).

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/network-policies/
- https://kubernetes.io/docs/reference/labels-annotations-taints/#kubernetes-io-metadata-name

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## probe-port-missing

`CHK-PRB-001` · error · prevented: the language cannot express it

The kubelet cannot connect, so the probe fails forever: a readiness probe keeps the pod permanently out of service, and a liveness probe restarts it in a loop.

### What you see

Which failure you get depends on which probe, and both are bad in different ways.

**A readiness probe** that can never succeed keeps the pod permanently out of
service. It is Running. Its containers are up. `kubectl get pods` shows `0/1
READY`, the Service has no endpoints, and every request to it fails, while the pod
itself reports no error, because from the container's point of view nothing is
wrong. During a rollout this stalls the deployment indefinitely, which is at least
loud.

**A liveness probe** that can never succeed is worse. The kubelet concludes the
container is unhealthy and restarts it. The new container has the same probe and
the same missing port, so it fails again. The pod enters `CrashLoopBackOff`, with
back-off growing between restarts, and the container logs show a perfectly healthy
application being killed for reasons that appear nowhere in them.

The commonest way in is a rename. A port called `http` becomes `http-api`, the
Service is updated, and a probe elsewhere in the file still says `http`.

### Why it happens

A probe's `port` is an `IntOrString`. As a string it names a `containerPort` by
name; as an integer it is a raw port number. Named ports are resolved against the
container's own `ports` list at probe time.

Nothing validates the name when the object is applied. A probe naming a port that
does not exist is a well-formed pod spec: the API server accepts it, the scheduler
places it, and the kubelet discovers the problem only when it first tries to
execute the probe. There is no admission-time relationship between the `ports` list
and the probe that references it; they are two independent parts of the same object
that happen to share a vocabulary.

### What Syg catches

A liveness, readiness, or startup probe pointing at a port the container does not
expose.

### How Syg prevents it

A probe port is written as a reference:

```syg
service api {
  port http 8080
  health {
    ready GET :http /healthz
  }
}
```

`:http` is a `PORTREF` token, resolved by the name resolver against the ports
declared on the *enclosing service*. A reference that does not
resolve is a compile error at that source line, listing the ports that are
available.

Crucially, the grammar offers no alternative. There is no production for a bare
port number in a probe handler and no production for an arbitrary string. The only
way to name a port is to refer to one that exists. So the rename that breaks
hand-written YAML breaks the *build* here, at the moment of renaming, naming both
sites.

The container port, the Service port, the Service `targetPort`, and the probe
target all derive from the one `port` declaration, which is the same mechanism that
makes `CHK-NET-003` prevented.

The `Check` function is an invariant guard confirming the derivation held. Its
user-facing diagnostic comes from the resolver, at the reference site, where the
author can see what they wrote.

### Kubernetes versions

Verified against the kubernetes.io documentation for configuring liveness,
readiness, and startup probes, and the `Probe` API reference's `port` field
(checked 2026-08). Stable across supported versions.

### What Syg does not claim

Syg guarantees the probe names a port the container declares. It does not know
whether anything is *listening* on that port, whether the HTTP path returns 200, or
whether the probe's timing is sane for the application: those are properties of a
running process, not of source.

Probe timing has its own rules (`CHK-PRB-002` and the startup-probe rules); this
one is only about the reference.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## identity-missing

`CHK-RBAC-001` · error · prevented: the language cannot express it

The pod silently runs as the namespace's default ServiceAccount, with whatever permissions that account happens to carry: too many or too few, and never the ones intended.

### What you see

The pod runs, and it runs as somebody, just not who you meant.

This is the part that surprises people. "I did not configure an identity" does not
mean "this pod has no identity". Every pod runs as a ServiceAccount; if none is
specified, or if the specified one is absent, the pod ends up associated with the
namespace's `default` account, whose permissions are whatever anyone has attached
to it over the lifetime of that namespace.

So the failure splits two ways, and both are quiet. If `default` has fewer
permissions than intended, the workload gets `403 Forbidden` on its first API call,
with the deployment long since green. If `default` has *more* (because someone
once bound a broad ClusterRole to it to unblock something), the workload silently
runs with permissions nobody reviewed and nobody intended to grant it. The second
case never produces an error at all.

### Why it happens

`spec.serviceAccountName` in a pod spec is a plain string. Kubernetes resolves it
by name within the pod's namespace at admission time. The behaviour when the name
does not resolve depends on the path: a pod referencing a missing ServiceAccount is
generally rejected by the ServiceAccount admission controller, but the far more
common shape of this bug is that the field was never set at all, because it is
optional, and omitting it is silently equivalent to choosing `default`.

Either way, the linkage between "the account I carefully created and granted
permissions to" and "the account this pod actually runs as" is carried by a string
typed in two different files, with nothing checking that the two agree.

### What Syg catches

A pod configured to run as a ServiceAccount that was never created.

### How Syg prevents it

A service does not write a ServiceAccount name. It writes a reference:

```syg
service api {
  identity payments-api
}
```

`payments-api` resolves to an `identity` declaration in the module symbol table. An
unresolved name is a compile error at that source line, with an edit-distance
suggestion, not a pod that quietly falls back to `default`.

The emitted `serviceAccountName` is then read from the resolved
`graph.ServiceAccount` node, which is the same object the ServiceAccount manifest
is generated from. The pod and the account it runs as are the same value, so they
cannot name different things.

The reference is also **kind-checked**: `identity my-config` where
`my-config` is a `config` reports a kind mismatch, pointing at both the use and the
declaration, rather than a confusing missing-name error.

There is a deliberate second half to this. A service that declares no identity is
*legal*: plenty of workloads never call the API server. Syg does not force an
identity on them; it sets `automountServiceAccountToken: false` so no unused
credential sits in the container filesystem, and `CHK-RBAC-006` says so at the
source line.

### Kubernetes versions

Verified against the kubernetes.io ServiceAccount documentation, which states that
every pod is associated with a ServiceAccount and that pods which do not specify
one are assigned the `default` ServiceAccount in their namespace (checked 2026-08).
Stable across all supported versions.

### What Syg does not claim

Syg guarantees the account it names exists in the manifests it generates. It does
not know what permissions the namespace's `default` account carries in your
cluster, so it cannot tell you how bad the fallback would have been, only that it
cannot happen here.

An `extern identity` names an account managed outside the module. Syg will not
create it and cannot verify it exists; that gap is recorded as reduced coverage
rather than assumed sound.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## unbound-permissions

`CHK-RBAC-002` · error · prevented: the language cannot express it

A correct, carefully-scoped Role grants nothing at all; the application receives 403 Forbidden at its first API call, possibly weeks after deployment.

### What you see

Nothing. That is the whole difficulty.

Every object applies cleanly. The Role exists and contains exactly the right
permissions; anyone reviewing the manifests will read it and conclude the workload
is correctly authorised. The pod starts, passes its probes, and serves traffic.

Then, at some later point, the application makes its first Kubernetes API call and
receives `403 Forbidden`. If that call happens on startup, the failure is at least
prompt. If it happens on a code path that only runs during failover, a leader
election, or a nightly reconcile, the gap between deploying the mistake and
discovering it can be weeks, and the discovery arrives during whatever incident
triggered the rare path.

### Why it happens

RBAC splits permissions across two objects, and the split is the source of the
failure.

A **Role** is a list of rules: these verbs, on these resources. It is a
*description*. On its own it confers nothing on anybody.

A **RoleBinding** connects a Role to one or more subjects: a ServiceAccount, a
user, a group.

The property to internalise is that **permissions are a property of the edge, not
of the Role**. A Role is inert until a binding confers it. So the failure mode is
not "the permissions were wrong"; it is "the permissions were right and were never
attached to anything". There is no validation that catches this, because there is
nothing invalid about a Role with no binding: it is a legal, well-formed object,
and plenty of legitimate Roles are bound later or by another team.

The mirror-image mistake is a binding that exists but names the wrong subject: the
right ServiceAccount name in the wrong namespace, or a name that drifted when the
account was renamed. Same silence, same delayed 403.

### What Syg catches

A Role that is never bound to the identity that needs it, and so grants nothing.

### How Syg prevents it

One declaration produces all three objects.

```syg
identity payments-api {
  may get, list, watch on configmaps
}
```

From this, Syg derives the ServiceAccount, the Role, and the RoleBinding together,
in `buildIdentities`: the binding is created in the same breath as the Role it
refers to, holding both ends as **resolved pointers** to the objects just built.

There is no point in the process at which a Role exists and a binding does not, and
there is no name written twice that could drift apart. The grammar has no
production for a binding subject, for a `roleRef`, or for a `serviceAccountName`.
Syg's tests assert that none of these parses; if any of them ever did, the
prevention would be gone regardless of what the guard reports.

The `Check` function is therefore an **invariant guard**, not a check on user input.
It walks every binding for both attached ends and every Role for a binding that
reaches it. If it fires, the compiler has contradicted itself, and it says so: the message
is framed as a compiler bug to report, not a configuration mistake to fix.

### Kubernetes versions

Verified against the kubernetes.io RBAC authorization documentation, which states
that a Role or ClusterRole "contains rules that represent a set of permissions" and
that a role binding "grants the permissions defined in a role to a user or set of
users" (checked 2026-08). The two-object structure has been stable since RBAC went
GA in `rbac.authorization.k8s.io/v1` (Kubernetes 1.8).

### What Syg does not claim

Syg guarantees the binding it generates is present and correctly attached. It does
not verify that the *permissions themselves* are the ones your application needs:
that is a fact about your code, not your configuration. A workload can be perfectly
bound to a Role that grants the wrong verbs, and Syg will emit it happily.

Nor does it reason about permissions granted from outside the module: a
ClusterRoleBinding created by a platform team, an `extern identity`, or an
aggregated ClusterRole can all confer permissions Syg cannot see. `extern identity`
records that gap as reduced coverage rather than pretending the closed world is
complete.

### Further reading

- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## token-automount

`CHK-RBAC-006` · error · prevented: the language cannot express it

A credential for the API server sits in the filesystem of a workload that never calls the API server, widening what a compromise of that container reaches.

### What you see

Nothing fails. The exposure is what changes.

By default, Kubernetes mounts the pod's ServiceAccount token into every container
at a well-known path. For a workload that calls the Kubernetes API, that is the
mechanism working as designed. For the large majority of workloads (an HTTP
service, a queue consumer, a batch job that touches only its own database), it
means a live API credential sits in the container filesystem for the lifetime of
the pod, used by nothing.

The cost appears only during an incident. An attacker who achieves file read in
that container, through a path traversal, an SSRF that reaches the filesystem, or a
dependency with a malicious postinstall, gets a token that authenticates to the API
server. What they can do with it depends on what has accumulated on the namespace's
`default` account over the years, which is rarely a number anyone can state.

### Why it happens

Every pod is associated with a ServiceAccount; pods that do not name one get the
namespace's `default`. Unless `automountServiceAccountToken` is set to `false` (on
either the ServiceAccount or the pod spec, with the pod spec winning), the kubelet
projects a token for that account into every container in the pod.

The default is `true`. This is a reasonable default for the API's original
audience and a poor one for the typical workload, and nothing in the system
distinguishes the two cases: a token is mounted whether or not any process will
ever open it.

### What Syg catches

A pod spec that omits `automountServiceAccountToken` and so inherits the permissive
default: a live API credential in the filesystem of a workload that never calls
the API server.

### How Syg prevents it

Syg never omits the field. The graph builder gives **every** workload an explicit
disposition toward the token, derived from something the author already wrote:

- the service declares an identity → it means to call the API, so the token stays;
- it declares none → `automountServiceAccountToken: false` is emitted.

So the permissive implicit default is not a state this compiler can produce. There
is no configuration in which a Syg-generated pod inherits a token by omission.

A warning here would fire on every workload that legitimately makes no API
calls, which is most of them, to tell each one that Syg had already done the right
thing. A warning that needs no action is how warnings become noise people learn to
skip, and it devalues the warnings that do need attention. So the bad state is
unreachable, and the rule's check is an invariant guard confirming that every
workload carries an explicit disposition.

Note what is deliberately *not* prevented: requiring an identity on every service.
That is a platform policy rather than a language rule, and `CHK-GEN-001` with
profile locks is where a team can make it mandatory if they want it.

### Kubernetes versions

Verified against the kubernetes.io ServiceAccount documentation, which describes
the default automounting behaviour and the `automountServiceAccountToken` field on
both the ServiceAccount and the pod spec (checked 2026-08). Since Kubernetes 1.24
these are short-lived projected tokens rather than long-lived Secret-based ones,
which reduces but does not remove the exposure.

### What Syg does not claim

Syg cannot tell whether your workload calls the Kubernetes API: that is a fact
about your code. It infers intent from whether an identity was declared, which is a
proxy and can be wrong in one direction: a workload that calls the API without
declaring an identity would previously have worked via the default account, and
will now fail. That failure is the intended outcome, and the diagnostic names the
fix, but it is a behaviour change worth knowing about when adopting Syg for an
existing service.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- https://kubernetes.io/docs/concepts/security/service-accounts/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## security-field-unset

`CHK-SEC-001` · error · prevented: the language cannot express it

The golden path's mandated posture silently does not apply to some workload or container, which is found by an audit or an incident rather than a review.

### What you see

Nothing fails. That is the symptom. A container that should run as a non-root user
on a read-only filesystem runs as root on a writable one, and it works, so nobody
notices. It surfaces in a compliance audit, or after a compromise, as the one
container in the fleet that was exempt from the posture everyone believed was
universal.

The usual routes in are mundane: a sidecar added after the template was written, an
init container that "needs root for one chown", an overlay that patches a field
back for one service, a team that copied the deployment from before the mandate
existed.

### Why it happens

`securityContext` is set per container (and partly per pod), and every field
defaults to the permissive choice. Without `runAsNonRoot` a container runs as
whatever user its image declares, root by default. Without
`readOnlyRootFilesystem` it can write to its own filesystem. Without dropping
capabilities it keeps the runtime's default set. Nothing in the API connects one
container's settings to another's, or a template's to a copy of it, so a mandate
expressed as configuration holds only where it was copied.

Admission controllers (Pod Security Admission, policy engines) can enforce a
baseline at the cluster, if they are installed and configured, and only at the
moment of admission, when the change is already merged.

### What Syg catches

A workload, or one container in it, running without a security setting the
platform's golden path mandates: `runAsNonRoot`, a read-only root filesystem,
dropped capabilities.

### How Syg prevents it

A platform team writes the mandate once, as `locked` fields in a profile:

```syg
profile web-service(image, port) {
  locked runAsNonRoot true
  locked readOnlyRootFilesystem true
}
```

Profile expansion writes locked fields into every workload that uses the profile,
before name resolution, so no later stage can miss them. Three properties close
the routes in:

- a workload's `security` applies to **every** container in its pod, init
  containers and sidecars included, so a container added later inherits it;
- setting a locked field in the workload, in an init or sidecar block, or in an
  environment's override is a compile error that names the profile and the lock;
- the profile is pinned by `syg.lock`, so a module cannot drift to a different
  version of the mandate unnoticed.

The check function is the invariant guard: it confirms that every container carries
each locked value, and it reports a compiler bug if one does not.

### Kubernetes versions

The defaults above are documented for `securityContext` and stable across every
supported version. The Syg-side behaviour was verified on k3s (Kubernetes v1.31.4):
a workload's security block, emitted to every container, ran with a root init
container that kept only `CAP_CHOWN` and non-root, read-only main and sidecar
containers.

### What Syg does not claim

Syg guarantees the posture of what it emits, for workloads that use the profile. A
workload that does not `use` the golden path is outside the mandate. Making the
profile mandatory for a team is an organisational decision, and a cluster-side
admission policy remains the backstop for anything not built by Syg.

`raw` objects are opaque: a raw Deployment is not covered.

Locking a field does not make the application work under it. A read-only root
filesystem breaks a program that writes to `/tmp`, until the workload declares a
`scratch` volume there, and Syg cannot know that in advance.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- https://kubernetes.io/docs/concepts/security/pod-security-standards/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## service-selects-nothing

`CHK-SEL-001` · error · prevented: the language cannot express it

A Service whose selector matches no pods returns connection refused / 503.

### What you see

The Service's EndpointSlices are empty; traffic to its ClusterIP is refused or returns 503. The workload is healthy and running, yet nothing can reach it. It is one of the most confusing failures to debug, because every individual resource is "valid".

### Why it happens

The EndpointSlice controller "continuously scans for Pods that match its selector, and then makes any necessary updates to the set of EndpointSlices for the Service." A selector matching zero pods yields an EndpointSlice set with no ready endpoints, so kube-proxy has no backend to route to and connections fail. The Deployment's own `spec.selector` is likewise immutable and must equal its pod-template labels or the controller cannot own its pods.

### What Syg catches

A Service (or PDB, or NetworkPolicy) whose label selector matches none of the pods it is meant to target.

### How Syg prevents it

The user never writes a selector. Syg derives the Deployment `spec.selector`, the pod-template `metadata.labels`, the Service `spec.selector`, and the PDB `spec.selector` from **one** value, `labels.SelectorLabels(module, service)`, so they are byte-identical by construction. A mismatch cannot be expressed, so no check needs to run; the compiler carries only a defensive invariant guard that would fire solely on a derivation bug.

### Kubernetes versions

Verified against kubernetes.io documentation (v1.36, checked 2026-07); EndpointSlices have been GA since v1.21 and the selector→endpoint mechanism is stable across that range.

### What Syg does not claim

Soundness is scoped to the closed world (`syg explain closed-world`). A Service that targets an `extern` workload is a trusted-unverified edge, and a mismatch outside the compiled module cannot be seen.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/service/
- https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## selector-template-mismatch

`CHK-SEL-002` · error · prevented: the language cannot express it

The controller cannot own the pods it creates: either the API server rejects the object outright, or the workload creates pods endlessly and never becomes ready.

### What you see

For a Deployment, the apply fails: `selector does not match template labels`. That
is the good case: loud, immediate, before anything is running.

The bad case is what happens next. `spec.selector` is **immutable**. Once a workload
exists, that field cannot be changed, so a label rename that seemed cosmetic cannot
be applied at all. The fix is to delete and recreate the workload, which for a
Deployment is an outage and for a StatefulSet means detaching and reattaching every
replica's storage. A rename nobody thought was risky becomes a maintenance window.

The worst case is a controller that *does* accept a mismatched pair and then cannot
recognise its own pods: it creates a fresh set alongside the old ones, which keep
running with nothing managing them. Now there are two generations of the workload
serving traffic, and only one of them responds to changes.

### Why it happens

A controller finds its pods by label selector, not by ownership records alone. The
Deployment, StatefulSet, Job and CronJob specs each carry a `selector` and a pod
`template`, and the requirement is that the selector match the template's labels;
otherwise the controller creates pods it then cannot find.

The API server validates this for Deployments at admission. What it cannot do is
prevent the *shape* of the problem, because the two fields are separate parts of one
object that merely need to agree, and nothing at authoring time compares them.

Kubernetes also forbids mutating the selector after creation, precisely because the
controller's relationship to its pods would break. That immutability is what turns a
typo into a redeploy.

### What Syg catches

A controller whose `spec.selector` and `spec.template.metadata.labels` disagree, so
it cannot own the pods it creates.

### How Syg prevents it

There is no production for a selector and none for pod-template labels. Both sites
are filled from one `labels.SelectorLabels(module, name)` call, so they are
byte-identical by construction rather than by agreement.

The more kinds of workload there are, the more this matters. A Deployment, a
StatefulSet, a Job and a CronJob each carry their own selector and their own template: four more
chances for the pair to drift in hand-written YAML. Here, adding a controller adds
no new way to get this wrong, because every kind fills the pair from the same call.

The selector is deliberately a **subset** of the template labels. The template also
carries `managed-by` and `part-of`, which the selector excludes on purpose: a value
that might change across versions must never enter an immutable field, or the
mistake is welded into every workload ever created from it. The guard therefore checks subset, not equality.

### Kubernetes versions

Verified against the kubernetes.io Deployment and StatefulSet documentation,
including the statements that `.spec.selector` must match `.spec.template.metadata.labels`
and that the selector is immutable after creation (checked 2026-08). Stable since
`apps/v1`.

### What Syg does not claim

Syg guarantees the pair agrees in the manifests it generates. It cannot help with a
workload that already exists in a cluster with a different selector: that is a
migration, and changing Syg's label scheme is a breaking change requiring a major
version precisely because of it.

A mutating admission webhook that rewrites pod labels after the fact is also outside
what a closed-world compiler can see.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## budget-selects-nothing

`CHK-SEL-003` · error · prevented: the language cannot express it

A budget that matches nothing silently protects nothing, and one that matches too much blocks drains of unrelated workloads.

### What you see

Two failures in opposite directions, both silent.

**Matching nothing.** The budget protects zero pods. It exists, it appears in
`kubectl get pdb`, and it does nothing. The team believes the service is guarded
against voluntary disruption. Then a node drain during a routine cluster upgrade
evicts every replica at once and the service goes down, during an operation
specifically designed not to cause outages. The PDB was there the whole time, and
the review that approved it saw a correct-looking object.

**Matching too much.** A selector broader than intended makes one budget cover
several workloads. Drains start blocking with `Cannot evict pod as it would violate
the pod's disruption budget` for a workload nobody associated with this PDB, cluster
upgrades stall, and the operator's options are to wait or to force, which discards
the protection entirely for everything the budget covers.

### Why it happens

A PDB selects pods by label selector and constrains how many of them may be
voluntarily evicted at once. The Eviction API consults it; a drain is a sequence of
evictions.

Nothing connects a PDB to a *workload*. It selects pods, and any pods matching the
selector fall under it regardless of which controller owns them. So a PDB matching
nothing is completely valid, and a PDB spanning several workloads is a legitimate
thing to want, which means neither can be rejected. `kubectl get pdb` does show
`ALLOWED DISRUPTIONS`, but reading it correctly requires already knowing what the
number should be.

### What Syg catches

A PodDisruptionBudget whose selector matches nothing, or matches more than the
workload it was written for.

### How Syg prevents it

The budget is not a separate declaration that names a target. It is written *inside*
the workload it guards:

```syg
service api {
  replicas 3
  disruption { minAvailable 2 }
}
```

Its selector is filled from the same `labels.SelectorLabels(module, name)` call as
the workload's own, and the graph attaches the workload as a resolved pointer, the
`guards` edge. There is no production for a PDB selector, and no way to declare a
budget that is not attached to exactly one workload.

That shape removes the ambiguity as well as the mismatch: one budget guards one
workload, always, because the budget lives inside the thing it guards. The
"matches too much" failure is not a stricter check here; it is a sentence the
language cannot form.

Whether the budget's *value* is sane (a `minAvailable` equal to the replica count
blocks all voluntary disruption) is `CHK-PDB-001`'s question, and that one is a
genuine check because it is about arithmetic rather than shape.

### Kubernetes versions

Verified against the kubernetes.io disruptions documentation and the PodDisruptionBudget
API reference (checked 2026-08). Stable since `policy/v1` in Kubernetes 1.21.

### What Syg does not claim

Syg guarantees the budget it generates selects exactly its own workload's pods. It
does not know about PDBs created outside the module that might also match those
pods, and a second budget from elsewhere in the cluster would compound with this one
invisibly.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## policy-selects-nothing

`CHK-SEL-004` · error · prevented: the language cannot express it

A policy whose selector matches nothing isolates nothing, and one that matches other pods cuts their traffic.

### What you see

Two failures, both silent.

**Matching nothing.** The policy isolates no pod. The workload stays open in
both directions, and everyone believes it is isolated, because the policy is
there and reads correctly.

**Matching other pods.** A selector broader than intended (`part-of: shop`)
isolates every workload carrying the label. Their traffic is cut to what this
one policy allows, which was written for another workload's peers.

### Why it happens

A NetworkPolicy applies to the pods its `podSelector` matches in its namespace.
Nothing ties it to a workload, and a selector matching nothing is valid. Once a
pod is selected by a policy of a direction, only what some policy allows gets
through in that direction.

### What Syg catches

A NetworkPolicy whose `podSelector` matches nothing, or pods other than the
workload it was written for.

### How Syg prevents it

A policy is a separate declaration, and a workload links it with
`policy NAME`. The NetworkPolicy derived for that workload takes its
`podSelector` from the same `labels.SelectorLabels(module, name)` value as the
Deployment's selector, the pod template's labels, the Service's selector and the
budget's. There is no production for writing a pod selector. A golden test holds
the five byte-identical.

One policy may be linked by several workloads; each gets its own NetworkPolicy,
selecting its own pods. A workload links at most one policy, so what isolates it
is written in one place.

### Kubernetes versions

Unchanged since `networking.k8s.io/v1` (Kubernetes 1.7). Observed on k3s
v1.32.12: the derived selector isolated exactly the
linked workload's pods; other pods in the namespace stayed open.

### What Syg does not claim

Syg guarantees that the policies it emits select exactly their workloads' pods.
It does not know about policies created outside the module that also select
them. Kubernetes unions those with Syg's, and `CHK-NP-002` judges the union
only for the raw policies in the closed world.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/network-policies/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## shared-stateful-claim

`CHK-STO-003` · error · prevented: the language cannot express it

Replicas that were supposed to own separate state contend for one disk, or lose their data when rescheduled.

### What you see

It depends on the access mode, and the quieter outcome is the worse one.

With a `ReadWriteOnce` claim, `db-0` starts and `db-1` and `db-2` stay Pending
forever: the `CHK-STO-002` symptom, at least visible.

With a `ReadWriteMany` claim, all three pods start, and three replicas of a database
write to the same directory. Postgres detects the second process and refuses to
start; something less defensive corrupts its data slowly and silently, and the
corruption is discovered later, from the data rather than from the cluster.

In both cases the object still says `kind: StatefulSet`, and the reason it was made
one (each replica owns a distinct piece of durable state) has been discarded
without anything saying so.

### Why it happens

A StatefulSet has two ways to give its pods storage, and they mean opposite things.

`spec.volumeClaimTemplates` is the per-replica form. The controller creates one PVC
per ordinal (`data-db-0`, `data-db-1`, `data-db-2`), and each follows its pod's
stable identity: if `db-1` is rescheduled, its replacement is also `db-1` and gets
`data-db-1` reattached. This is what makes a StatefulSet a StatefulSet.

`spec.template.spec.volumes[].persistentVolumeClaim.claimName` is the shared form,
the same shape a Deployment uses. Every replica mounts the one named claim.

Both are valid on a StatefulSet, and they must both remain valid: a StatefulSet
legitimately mounts shared ConfigMap and Secret volumes that way. So nothing in the
schema can encode "this particular volume was meant to be per-replica", and the
`volumes` form is the one every Deployment example teaches, which makes reaching for
it the natural mistake.

### What Syg catches

A StatefulSet whose replicas share one PersistentVolumeClaim instead of each
holding their own.

### How Syg prevents it

The per-replica shape follows from the *declaration's kind*, and the author has no
way to state it.

```syg
stateful db {
  replicas 3
  storage data at "/var/lib/postgresql" { size 100Gi, access ReadWriteOnce }
}
```

`buildWorkload` sets `VolumeClaim.PerReplica` from `svc.Kind == ast.KindStateful`.
The author writes a name, a path, a size, a class and access modes, and nothing
else. The grammar has no `claimName`, no `shared` flag, and no `volumes` escape
hatch through which the Deployment shape could be reached.

Change `stateful` to `service` and the identical declaration means something
different and correct: a standalone PVC the replicas share, which is the right shape
for a single-replica workload with a disk. So the two forms exist, both are
reachable, and *which one you get is decided by the word you chose for the
workload*, just as that word decides the controller.

Whether the shared form is safe at a given replica count is `CHK-STO-002`'s
question, and that one is a check, because it depends on values rather than shape.

### Kubernetes versions

Verified against the kubernetes.io StatefulSet documentation, including its
description of `volumeClaimTemplates` providing stable storage that follows a pod's
identity across rescheduling (checked 2026-08). Stable since `apps/v1`.

### What Syg does not claim

Syg guarantees a `stateful`'s storage is per-replica in the manifests it generates.
It does not reason about whether your application is correct as a multi-replica
stateful system: replication, leader election, and split-brain behaviour are
properties of your software, and a StatefulSet gives you stable disks, not a
correct distributed database.

It also does not manage the PVCs' lifecycle: volumeClaimTemplates deliberately do
not delete their claims when replicas scale down, which is data-preserving and
occasionally surprising.

### Further reading

- https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

