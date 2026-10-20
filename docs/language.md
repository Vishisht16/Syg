# Language reference

A module is a directory of `.syg` files that begin with the same `module NAME`
line. Files can be split however you like; the module is compiled as one. This
page covers every construct, with what it means. The exact Kubernetes fields
each one produces are in the [derivation map](derivation-map.md), and the
formal syntax is the [grammar](grammar.md).

Comments start with `#`. Whitespace and line breaks only separate words, and
`syg fmt` lays a file out canonically, with one item per line in every block;
the examples on these pages put short blocks on one line
(`resources { cpu 100m, memory 64Mi }`) to keep them short, which is valid but
not what `syg fmt --check` accepts. Strings are in double quotes; a block
string, between `"""` lines, is taken verbatim with its common indentation
removed.

## Workloads

```syg
module shop

service api {
  image "registry.example.com/api:1.4.2"
  replicas 3
  port http 8080
  port metrics 9090
  resources {
    cpu 250m
    memory 256Mi
    limits { cpu 250m, memory 256Mi }
  }
  health {
    ready   GET :http /readyz every 5s failures 3
    live    TCP :http
    startup GET :http /healthz every 5s failures 30
  }
  env LOG_FORMAT = "json"
  internal :http
  internal :metrics
}

stateful db {
  image "registry.example.com/postgres:16.4"
  replicas 3
  port pg 5432
  resources { cpu 500m, memory 1Gi }
  health { ready TCP :pg }
  storage data at "/var/lib/postgresql" {
    size 20Gi
    access ReadWriteOnce
  }
  internal :pg
}

job report {
  image "registry.example.com/report:2.0.0"
  resources { cpu 100m, memory 64Mi }
  schedule "0 3 * * *"
  retries 2
  deadline 30m
}
```

There are three kinds of workload:

| Declaration | Emits | Notes |
|---|---|---|
| `service NAME` | a Deployment | the stateless default |
| `stateful NAME` | a StatefulSet, and a headless Service for it | each replica gets its own `storage`; there is no way to share one claim |
| `job NAME` | a Job, or a CronJob with `schedule` | `parallelism`, `completions`, `retries` (backoffLimit) and `deadline` |

Inside a workload:

| Item | Meaning |
|---|---|
| `image "REF"` | the main container's image. A tag, or a digest (`@sha256:...`); `latest` or no tag is a warning (CHK-IMG-001) |
| `command "..." ...`, `args "..." ...` | replace the image's entrypoint and arguments; each string is one argument, and no shell is added |
| `replicas N` | the replica count. Absent on an autoscaled workload, which leaves the count to the autoscaler |
| `port NAME N [UDP\|SCTP]` | a named container port. Everything else refers to it as `:NAME` |
| `resources { cpu Q, memory Q, limits { ... } }` | requests, and limits. Extended resources by name: `nvidia.com/gpu 1` (whole numbers), `ephemeral-storage 1Gi` |
| `qos guaranteed\|burstable\|besteffort` | the QoS class you intend; Syg derives the actual class from the resources and checks they agree (CHK-RES-004) |
| `health { ready\|live\|startup PROBE }` | probes: `GET :port /path`, `TCP :port`, or `EXEC "command"` (run by `/bin/sh -c`) or `EXEC "arg" "arg" ...` (argv, no shell), with `every`, `timeout`, `after` (initial delay) and `failures` |
| `env NAME = "V"` | an environment variable |
| `needs config NAME [as VAR \| at "PATH"]` | consume a config: all of its keys as variables, one key as `VAR`, or the whole config as files at `PATH` |
| `needs secret NAME [as VAR \| at "PATH"]` | the same for a secret |
| `needs service NAME [:PORT]` | a dependency on another workload or an `extern service`: allowed by [network policy](network-policy.md), and checked |
| `internal :PORT` | a ClusterIP Service for in-cluster traffic on that port. The only Service type modelled: for a NodePort or LoadBalancer, see [other Service types](custom-resources.md#built-in-kinds) |
| `expose :PORT at "HOST" [path "/P"] [via GATEWAY] [tls SECRET]` | a Service, and an HTTPRoute (or an Ingress) for traffic from outside |
| `identity NAME` | run as that identity's ServiceAccount, with its grants |
| `policy NAME` | isolate the workload with a [network policy](network-policy.md) |
| `storage NAME at "PATH" { size Q, class C, access MODE }` | a volume claim, mounted at PATH. Per replica on a `stateful`; shared on a `service` |
| `scratch NAME at "PATH" [{ medium memory }]` | an emptyDir, mounted at PATH |
| `init NAME { ... }`, `sidecar NAME { ... }` | more containers, each with its own image, command, resources and `mount NAME at "PATH"` of the workload's scratch volumes |
| `labels { K = "V" }`, `annotations { K = "V" }` | your own metadata, on the workload, its pods and the objects it owns. Never in a selector |

## Availability and scaling

```syg
module shop

service api {
  image "registry.example.com/api:1.4.2"
  port http 8080
  resources { cpu 250m, memory 256Mi }
  health { ready GET :http /readyz }
  internal :http
  scale on cpu at 70% between 3 and 10
  disruption { maxUnavailable 1, evictUnhealthy true }
  rollout { strategy rolling, maxUnavailable 0, maxSurge 1 }
  spread { across topology.kubernetes.io/zone }
  avoid { across kubernetes.io/hostname }
}
```

| Item | Meaning |
|---|---|
| `scale on cpu\|memory at P% between MIN and MAX` | a HorizontalPodAutoscaler on that resource's utilisation, which needs a request to take a percentage of (CHK-HPA-002) |
| `disruption { minAvailable N\|P%, evictUnhealthy BOOL }` (or `maxUnavailable`) | a PodDisruptionBudget. `evictUnhealthy true` lets a drain evict pods that are not ready |
| `rollout { strategy rolling\|recreate, maxUnavailable N, maxSurge N }` | the update strategy, checked against the budget (CHK-PDB-003) |
| `spread { across KEY, ... [skew N] [strict\|soft] }` | spread pods across a node label's values (`topologySpreadConstraints`) |
| `avoid { across KEY [with W, ...] [strict\|soft] }` | keep pods apart, from each other or from workloads `W` (pod anti-affinity) |
| `tolerate KEY[=VALUE][:EFFECT] [for 5m]` | tolerate a node taint |
| `security { runAsNonRoot true, readOnlyRootFilesystem true, drop ALL, ... }` | the security context of every container, sidecars and init containers included |

`strict` placement must be met or the pod waits; `soft` (the default) is a
preference. Placement keys other than the well-known ones are declared with
`extern topology KEY { domains N }`, which also tells Syg how many domains
there are, so it can tell when a strict rule cannot be met (CHK-SCH-001).

## Configuration and secrets

```syg
module shop

config settings {
  key LOG_LEVEL = "info"
  key FEATURE_X = "enabled"
}

secret db-credentials {
  key DATABASE_URL
}

service api {
  image "registry.example.com/api:1.4.2"
  port http 8080
  resources { cpu 250m, memory 256Mi }
  health { ready GET :http /readyz }
  internal :http
  needs config settings
  needs secret db-credentials as DATABASE_URL
}
```

A `config` is a ConfigMap, emitted only when something consumes it. A `secret`
declares its **keys only**. Syg never holds a secret's value: the Secret
object comes from your secrets manager, and Syg emits only the references to
it, checked against the keys declared. For the same reason Syg never
validates a secret's contents: whether a key holds a valid password,
certificate or token is outside what it can see (`syg explain tier3`).

## Identities

```syg
module shop

identity reader {
  may get, list, watch on configmaps
  may get on secrets
}

service api {
  image "registry.example.com/api:1.4.2"
  port http 8080
  resources { cpu 250m, memory 256Mi }
  health { ready GET :http /readyz }
  internal :http
  identity reader
}
```

An `identity` is a ServiceAccount, a Role with its grants, and the RoleBinding
between them, all derived from one name. `may ... across cluster` makes the
grant a ClusterRole and ClusterRoleBinding instead, so widening a grant to the
whole cluster is always written down. A workload without an identity does not
mount an API token.

## Things outside the module

```syg-fragment
extern secret tls-cert { key tls.crt, key tls.key }
extern config shared-flags { key REGION }
extern service billing { port http 8080, namespace "billing" }
extern host payments-gateway { address "203.0.113.10", port https 443 }
extern identity ci-deployer {}
extern storageclass fast-ssd {}
extern gateway edge { namespace "infra", listener https }
extern topology topology.kubernetes.io/zone { domains 3 }
extern resource "cert-manager.io/v1/ClusterIssuer" letsencrypt {}
```

An `extern` declares something another team, or the cluster, provides. It
emits nothing; it gives the name a type, so references to it are checked like
any other. Externs are **trusted, not verified**: a check that relies on one
says so, and a [snapshot](checks.md#snapshots) verifies them against the cluster.

## Custom resources, profiles, environments

These have their own pages:

- `raw`, `relate` and `import "syg.vishisht.tech/relate/..."`: [custom resources](custom-resources.md).
- `profile`, `use`, `import`, `environment`: [golden paths](golden-paths.md).
- `policy`, `needs service`: [network policy](network-policy.md).

## Names

Names are lowercase letters, digits and `-`, starting with a letter, because
they become Kubernetes object names. A module name may have dots
(`acme.platform`). Within a module, each kind of declaration has its own
names: a config and a secret may share one, two services may not.

What the names become, so a migration keeps what other things depend on:

- A workload's name is the Deployment's, StatefulSet's or Job's name, its
  Service's name (so it is the in-cluster DNS name), and the name of its main
  container. A container named something else before is renamed: `kubectl
  logs -c OLD`, and dashboards keyed on the container name, need the new one.
  `init` and `sidecar` containers keep the names you give them.
- A config or secret's name is the ConfigMap's or Secret's name.
- An identity's name is the ServiceAccount's name.
- The labels, and so the selectors, are always derived:
  `app.kubernetes.io/name` and `app.kubernetes.io/instance` from the workload
  and the module. No name reproduces a selector written by hand, which is why
  a migration deploys into a new namespace or under a new name (see
  [migrating](migrate-helm.md#5-cut-over)). The derivation map
  lists every field.
