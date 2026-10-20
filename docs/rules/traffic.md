# Traffic

Routes that lead nowhere, collide, or expose a host without TLS.

## route-path-incomplete

`CHK-NET-004` · error · checked offline

A route that resolves at every named hop but ends at no running container returns 503 with nothing reporting an error.

### What you see

The canonical version of this is the dangling service: every object is valid,
every dashboard is green, and requests are refused or time out. Because the names
all agree, the usual debugging reflex (check the Ingress, check the Service)
finds nothing wrong at each step, and the missing piece is that no Pod exists at
the end of them.

### Why it happens

Routing is a chain of independent joins: route → Service by name, Service → Pods
by label selector, Pod → port by name. Each link is evaluated separately and
continuously, and none of them fails loudly when the *next* link is empty. A
Service whose selector matches nothing has an empty EndpointSlice; kube-proxy in
its common iptables mode installs a rule that rejects traffic to that ClusterIP,
so the client sees a refused connection immediately. A workload at zero replicas
produces the same empty EndpointSlice by a different route.

Derivation fixes the *names*. It cannot fix the absence of a workload, which is
why this rule is detected rather than prevented.

### What Syg catches

A route whose every *named* hop resolves, but whose path still ends nowhere: the
backing workload is absent from the closed world, or is scaled to zero replicas.

### Why Syg checks rather than prevents

Scaling a workload to zero is a legitimate operation, and referencing an `extern`
service is a legitimate way to describe something outside this module. Neither can
be forbidden. What Syg can do is traverse the whole path and say which specific
hop ends in nothing, at the line that declared the exposure.

### Kubernetes versions

Verified against kubernetes.io Service, EndpointSlice and virtual-IP
documentation (checked 2026-08).

### What Syg does not claim

Syg does not know whether a Pod that exists is actually serving. Readiness,
crash-looping, and application-level failure are runtime facts. It reports a
structurally empty path, not a sick one.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/service/
- https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/
- https://kubernetes.io/docs/reference/networking/virtual-ips/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a route's backend is healthy in practice depends on running pods, not source.

## route-conflict

`CHK-NET-005` · error · checked offline

Conflicting rules route nondeterministically depending on controller merge order, so which service answers can change on a restart.

### What you see

Traffic goes to one of them, and which one is not determined by anything you
wrote. The behaviour can change when a controller restarts, when objects are
re-applied in a different order, or when one of the two is redeployed, with no
configuration change accompanying the switch. This is a particularly unpleasant
incident because the trigger looks unrelated to the effect.

### Why it happens

The Ingress specification is explicit that overlapping paths across Ingress
objects have no defined precedence; resolution is left to the controller, and
controllers differ. Gateway API is stricter (it specifies matching precedence
and requires conflict resolution), but the resolution is still not something the
author chose, and the losing route silently receives nothing.

Either way, host plus path is the routing key, and two claims on one key is a
statement with no unique meaning.

### What Syg catches

Two exposed services claiming the same hostname and path prefix.

### Why Syg checks rather than prevents

Both declarations are individually legitimate. The conflict exists only in the
relationship between two separate services, which may be in different files, and
no single declaration can be shaped to make it impossible. It is a genuine
whole-graph property, and it is exactly the kind of thing a per-object schema
validator cannot see.

### Kubernetes versions

Verified against kubernetes.io Ingress documentation and the Gateway API
specification (checked 2026-08).

### What Syg does not claim

Syg compares declared hosts and path prefixes within the closed world. It does not
know about routes defined outside the module, nor about wildcard-host overlaps
resolved by a specific controller's rules.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/ingress/
- https://gateway-api.sigs.k8s.io/api-types/httproute/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## host-without-tls

`CHK-NET-006` · warning · checked offline

Traffic to a public hostname crosses the internet in plaintext.

### What you see

Requests to the host, including credentials, session tokens, and any personal
data in them, cross the network in plaintext, readable by anything on the path.
There is no error and no degraded behaviour; it simply works, over HTTP.

### Why it happens

An Ingress serves a host over TLS only when `spec.tls` names a Secret holding a
certificate for it; absent that, the controller serves plaintext HTTP. In Gateway
API the certificate belongs to the **Gateway's listener** rather than to the
route, which is the one place the two output targets differ in kind rather than
in spelling.

Syg records the declared intent either way: with the Ingress target the
certificate is emitted onto the object, and with the Gateway target it documents
that the route expects a TLS listener, which the platform team owns.

### What Syg catches

A service exposed on an external hostname with no certificate declared.

### Why Syg checks rather than prevents

Plaintext exposure is occasionally intentional: an internal-only hostname behind
a mesh that terminates TLS elsewhere, or a local development environment. Making
it unrepresentable would forbid legitimate configurations, so Syg warns and lets
the platform profile raise the severity where policy demands it.

### Kubernetes versions

Verified against kubernetes.io Ingress TLS documentation and the Gateway API
specification (checked 2026-08).

### What Syg does not claim

Syg does not verify that the named Secret exists in the cluster, that it contains
a valid certificate, or that the certificate matches the hostname. Those are
cluster and content facts (Tier 2 and Tier 3 respectively).

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/ingress/#tls
- https://gateway-api.sigs.k8s.io/guides/tls/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

