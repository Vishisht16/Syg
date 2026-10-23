# Syg

**A typed language for a Kubernetes service's deployment surface, and a compiler
that derives the manifests from it.** You declare a service once: its image, its
ports, what it needs, how it is exposed, how it may be disrupted. Syg derives the
Deployment, Service, budget, autoscaler, route, identity and network policy, and
checks them together before anything reaches a cluster.

```syg
module shop

service api {
  image "registry.example.com/api:1.4.2"
  replicas 3
  port http 8080
  resources { cpu 250m, memory 256Mi }
  health {
    ready GET :http /readyz
    live  GET :http /livez
  }
  disruption { maxUnavailable 1, evictUnhealthy true }
  expose :http at "api.example.com" tls api-tls
}
```

`syg build` turns that into a Deployment, a Service, a PodDisruptionBudget and an
HTTPRoute. Their selectors, port names and backend references are derived once,
from the declaration, so they cannot disagree.

## What it gives you

**Mistakes you cannot write.** A Service whose selector matches no pod, a route
to a port the Service does not have, a RoleBinding to a Role that does not
exist, an autoscaler aimed at the wrong Deployment: in Syg there is no field in
which to write any of them. Selectors, references and bindings are derived from
names, and a name that does not resolve is a compile error at the line you
wrote. See [derivation](derivation.md).

**Two checks that matter, which linters do not ship.** Measured over a corpus of
48 real configurations, two mistakes stood out for how often they occur and how
much they cost:

- **A disruption budget on a single replica** ([`single-replica-budget`](rules/availability.md#single-replica-budget)): a budget that
  keeps one pod available, on a workload that runs one pod, blocks every node
  drain until someone deletes it.
- **Liveness and readiness on the same endpoint** ([`shared-probe-endpoint`](rules/probes.md#shared-probe-endpoint)): when a
  dependency slows down, every pod fails its liveness probe together, and the
  kubelet restarts the whole service at the moment it most needs to stay up.

Both are relationships between fields, or between objects, which is what Syg's
graph sees and a per-object linter does not.

**Less to write.** A service like the one above is about twenty lines of Syg
against a few hundred of YAML. That figure comes from charts, which carry
packaging boilerplate; hand-written manifests are shorter, though the
cross-references in them are exactly what goes wrong.

Every finding names the line you wrote, says what will fail in production and
why, and how to fix it, and `syg explain` tells the whole mechanism. There is
nothing to learn in advance; [what Syg catches](rules/index.md) is here to
browse.

## What it does not do

Syg is a compiler. It never applies anything to a cluster, and your delivery
pipeline (kubectl, Argo CD, Flux) stays as it is. It is not a general
configuration language, and it does not claim to be the first tool to check any
of these things. The full list is on the [non-goals](non-goals.md) page.

## Where to start

- [Install](install.md) the binary, then follow the [quickstart](quickstart.md):
  a service from `syg init` to a cluster in a few minutes.
- [Migrating from Helm](migrate-helm.md) walks through a real chart.
- The [language reference](language.md) and the [CLI reference](cli.md) are
  complete; the [rule catalogue](rules/index.md) lists every check.
- [Security](security.md) says what `syg check` protects against and how to
  verify a download; [network and data](network.md), every connection Syg
  makes; [support](support.md), where to ask.

Kubernetes is a registered trademark of The Linux Foundation. Syg is not
affiliated with or endorsed by it.
