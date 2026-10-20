# Derivation

Most Kubernetes misconfigurations that break production are not wrong values.
They are two values that should agree and do not: a Service selector that no
longer matches its pods, a route to a port name the Service does not have, a
RoleBinding naming a Role that was renamed, an autoscaler aimed at last year's
Deployment. Each object is valid on its own, so the API server accepts it, and
nothing fails until traffic or a drain finds the gap.

Syg removes that class by **deriving** every value that must agree from one
declaration, instead of asking you to write it twice.

## One name, every selector

```syg
module shop

service api {
  image "registry.example.com/api:1.4.2"
  replicas 3
  port http 8080
  resources { cpu 250m, memory 256Mi }
  health { ready GET :http /readyz }
  disruption { maxUnavailable 1, evictUnhealthy true }
  internal :http
}
```

From `module shop` and `service api`, Syg derives one label set:

```yaml
app.kubernetes.io/name: api
app.kubernetes.io/instance: shop-api
```

It is written, byte for byte, into the Deployment's `spec.selector`, the pod
template's labels, the Service's selector, the budget's selector and, when the
service has one, the NetworkPolicy's `podSelector`. There is no `selector` in
the language, so there is no way to write one that differs. The scheme is
fixed: a Deployment's selector cannot change once it exists, so changing the
scheme would be a breaking change ([compatibility](compatibility.md)).

## References, not strings

Where YAML repeats a name, Syg has a reference that must resolve:

| You write | Syg derives | The YAML mistake it removes |
|---|---|---|
| `port http 8080`, then `:http` | the container port, the Service port and `targetPort`, the probe port, the route's backend port | a probe or route naming a port that does not exist |
| `internal :http`, `expose :http at "HOST"` | a Service with the right selector and port; an HTTPRoute (or Ingress) whose backend is that Service | a route to a Service, or a port, that does not exist |
| `identity reader` and `may get on configmaps` | a ServiceAccount, a Role, and the RoleBinding that joins them; the pod's `serviceAccountName` | a Role nothing binds, a binding to a missing Role, a pod running as an account that is not there |
| `needs config settings as LOG_LEVEL` | the ConfigMap, and the `configMapKeyRef` that reads it | a pod waiting forever in `CreateContainerConfigError` |
| `scale on cpu at 70% between 3 and 10` | the HorizontalPodAutoscaler's `scaleTargetRef`, and no `spec.replicas` on the Deployment | an autoscaler aimed at nothing, or fighting a GitOps controller over the replica count |
| `stateful db { storage data at "/var/lib/db" { ... } }` | a StatefulSet, its headless Service, and a claim per replica | replicas sharing one disk |

A reference that does not resolve is an error at the line you wrote, before
any YAML exists:

```syg-fail
module shop

service api {
  image "registry.example.com/api:1.4.2"
  port http 8080
  resources { cpu 250m, memory 256Mi }
  needs config settings as LOG_LEVEL
}
```

```console
error[missing-config]: unknown config "settings"
```

These mistakes are **prevented**: there is no source that produces them. The
rules that name them (CHK-SEL-001, CHK-NET-001, CHK-RBAC-002 and the rest) stay
in the catalogue as guards that would report a bug in Syg itself, and their
pages explain the failure they rule out. The [rule
catalogue](rules/index.md) marks each rule PREVENTED or DETECTED.

## What you still decide

Derivation removes the second copy of a value, not the decision. How many
replicas, how much memory, whether a budget allows an eviction, whether
liveness and readiness probe the same thing: those are choices, and some
combinations of them fail in production. Those are what Syg's
[checks](checks.md) are for.

## Seeing what was derived

Every emitted field has a recorded origin: written by you, set by a
[profile](golden-paths.md), overridden by an environment, or derived, with the
rule of derivation. `syg why` reads it:

```console
$ syg why shop deployment/api spec.replicas
```

and so does the editor: hovering a line shows the Kubernetes fields it
produces. The complete map of construct to fields is the [derivation
map](derivation-map.md).
