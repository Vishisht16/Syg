# Checks

[Derivation](derivation.md) removes the mistakes that come from writing a value
twice. What is left are decisions that can be wrong together: a budget that
blocks every drain, an autoscaler with nothing to take a percentage of, probes
that restart a slow service. Syg builds the whole module into one graph (every
workload, Service, route, budget, autoscaler, identity and policy, and the edges
between them) and runs its rules over that graph.

## Errors, warnings and notes

Each finding has a severity:

- **error**: the configuration will fail. `check` and `build` exit 1, and
  `build` writes nothing.
- **warning**: it will probably fail, or fail under conditions Syg cannot see.
  The command succeeds, unless you pass `--strict`.
- **info** (a note): something you should know, never a failure. Notes also say
  what was *not* checked.

Every finding carries the source lines it is about, the consequence in
production, a fix where one can be computed, and the rule to `syg explain`.

## Prevented and detected

Every rule in the [catalogue](rules/index.md) is one of two kinds:

- **PREVENTED**: the language cannot express the mistake (a selector, a role
  reference, a port name that resolves to nothing). The rule stays as a guard
  that would report a bug in Syg, and its page explains the failure ruled out.
- **DETECTED**: a combination of choices you can write and should not. These
  are the checks you will see.

A rule is only DETECTED after prevention was considered and rejected for a
recorded reason; each rule's page says why it is a check and not a prevention.

## What a clean result claims

A check's verdict is about the **closed world**: this module, the modules it
imports, and its `extern` declarations. Syg sees nothing else on the cluster,
and does not pretend to. Two consequences:

- An `extern` declaration (a secret, a service, a storage class someone else
  owns) is **trusted, not verified**. When a check relies on one, a note says
  so. A [snapshot](#snapshots) verifies them.
- A `raw` object (any Kubernetes object, written as YAML) is passed through.
  A rule that must see every object of a kind to be right, such as "every
  Service has a readiness-probed backend", reports **reduced coverage** for it,
  rather than a clean result it has not earned.

`syg check --print-world` lists exactly what the closed world contains. `syg
explain closed-world` and `syg explain coverage` say more.

## Tiers

- **Tier 1** rules need only the source. They run on every check, with no
  network and no cluster credentials, in CI on an untrusted pull request.
- **Tier 2** rules need facts about a real cluster: whether a storage class
  exists, whether the CNI enforces NetworkPolicy, whether the API versions you
  emit are served. They run against a snapshot.
- **Tier 3** is what no static tool can know: whether a probe's timeout is long
  enough under load, whether a request is the right size. Syg checks the
  structure around those and says where it stops (`syg explain tier3`).

## Snapshots

`syg snapshot -o cluster.snapshot.yaml` records a cluster's facts: Kubernetes
version, served APIs, nodes and their labels and taints, storage classes,
gateways, the CNI, and the names of objects your externs refer to. It is the
only command that talks to a cluster, it only reads, and it never records
secret values. It needs only get and list, on a handful of resources. A
least-privilege ClusterRole for it, and an optional per-namespace Role for
Secret names:

```yaml
# The permissions `syg snapshot` needs: every verb is get or list.
#
# Bind syg-snapshot cluster-wide to the identity that runs the snapshot. It does
# NOT cover Secrets: Kubernetes RBAC cannot allow listing Secret names without
# also allowing their values to be read, so Secrets are a separate, per-namespace
# grant (syg-snapshot-secrets below). Without it the snapshot records no Secrets
# for that namespace and says so, and checks that would use them report that they
# could not.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: syg-snapshot
rules:
  - apiGroups: [""]
    resources: [namespaces]        # kube-system's UID identifies the cluster
    verbs: [get]
  - apiGroups: [""]
    resources: [nodes, services, configmaps, serviceaccounts]
    verbs: [list]
  - apiGroups: [apps]
    resources: [daemonsets]        # recognising the CNI plugin
    verbs: [list]
  - apiGroups: [apiextensions.k8s.io]
    resources: [customresourcedefinitions]
    verbs: [list]
  - apiGroups: [storage.k8s.io]
    resources: [storageclasses]
    verbs: [list]
  - apiGroups: [networking.k8s.io]
    resources: [ingressclasses]
    verbs: [list]
  - apiGroups: [gateway.networking.k8s.io]
    resources: [gatewayclasses, gateways]
    verbs: [list]
---
# Optional, per namespace named with --namespace: Secret names (through the
# metadata API, which returns no data) and, with --secret-keys, their key names.
# Syg never records a value, but this grant could read one, which is why it is
# separate and namespaced.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: syg-snapshot-secrets
  namespace: REPLACE-WITH-NAMESPACE
rules:
  - apiGroups: [""]
    resources: [secrets]
    verbs: [list]
```

A snapshot is meant to be committed beside the module, so a check in CI sees
the same cluster you did. Most of its size is the schemas of the cluster's
custom resource definitions, which `syg schema vendor --from` can read: on a
cluster with a service mesh and a few operators that is several megabytes of
YAML. Refresh it when the cluster changes; a check reports one older than
`snapshotMaxAge` as stale.

Name the snapshot in `syg.yaml`, per environment if they deploy to different
clusters:

```yaml
snapshots:
  default: cluster.snapshot.yaml
  prod: prod.snapshot.yaml
```

or pass `--snapshot FILE`. Every Tier-2 finding names the snapshot and its age,
and a stale one is reported. Without one, Tier-2 rules are listed as skipped:
never passed.

## Baselines

Some fields cannot change once an object exists: a Deployment's selector, a
StatefulSet's volume claims. Two rules (CHK-SEL-005, CHK-GEN-002) compare the new
build with what is deployed, and report a change the API server would refuse.
`syg build -o DIR` compares with what `DIR` held from the previous build; give
`--baseline PATH`, or `baseline:` in `syg.yaml`, to compare with the manifests
actually running.

## Configuring rules

`syg.yaml`, beside the module's `.syg` files, can turn a DETECTED rule off or
change its severity, and require declarations of every workload:

```yaml
rules:
  CHK-RES-003: off
  CHK-IMG-001: error
require:
  default: [disruption]
  prod: [identity, policy]
```

PREVENTED rules cannot be turned off: they are not settings, they are what the
language means.

## In CI

`syg check` exits 1 on errors (and on warnings with `--strict`), 2 on a usage
or configuration mistake, and 3 on a bug in Syg. `--format github` turns
findings into annotations on the pull request, `--format sarif` feeds code
scanning, and `--format json` is for your own tools. See [CI
integration](ci.md).
