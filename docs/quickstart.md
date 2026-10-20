# Quickstart

From nothing to a service running on a cluster, in a few minutes. You need
[`syg`](install.md), and `kubectl` with a cluster to apply to (any will do:
kind, k3d, minikube, or a real one).

## 1. Start a module

```console
$ syg init shop --service api
syg: wrote shop/shop.syg and shop/syg.yaml
next: set the image, then `syg check shop` and `syg build shop -o out/`
```

A *module* is a directory of `.syg` files that are compiled together. `init`
writes one service that already checks clean, and a commented `syg.yaml` for
project settings:

```syg
module shop

service api {
  image "registry.example.com/api:1.0.0"
  replicas 2
  port http 8080
  resources {
    cpu 100m
    memory 128Mi
    limits { cpu 100m, memory 128Mi }
  }
  qos guaranteed
  health {
    ready GET :http /readyz
    live GET :http /livez
  }
  disruption { maxUnavailable 1, evictUnhealthy true }
  internal :http
}
```

Each line is a decision about the service: two replicas, a port called `http`,
requests and limits equal (so the pod is Guaranteed, which is what `qos
guaranteed` says and Syg checks), a readiness and a liveness probe, a budget
that lets one pod at a time be evicted for maintenance, and a ClusterIP Service
for traffic from inside the cluster (`internal`).

## 2. Make it yours

Put in a real image. To follow along with something that runs, use the
Kubernetes project's test server, which answers HTTP on the port it is given:

```syg
module shop

service api {
  image "registry.k8s.io/e2e-test-images/agnhost:2.53"
  args "netexec" "--http-port=8080"
  replicas 2
  port http 8080
  resources {
    cpu 100m
    memory 128Mi
    limits { cpu 100m, memory 128Mi }
  }
  qos guaranteed
  health {
    ready GET :http /healthz
    live TCP :http
  }
  disruption { maxUnavailable 1, evictUnhealthy true }
  internal :http
}
```

`args` replaces the image's command arguments; each string is one argument.

## 3. Check it

```console
$ syg check shop
info[baseline]: CHK-SEL-005 and CHK-GEN-002 did not run: no baseline, so changes to immutable fields are not checked
   = help: `syg build -o DIR` compares with DIR's previous output; give --baseline PATH, or syg.yaml's baseline:, to check against deployed manifests
   = explain: syg explain immutable-field-change  (CHK-GEN-002)

info[snapshot]: Tier-2 rules skipped, no cluster snapshot: CHK-T2-CAP-001, CHK-T2-CRD-001, …
   = help: capture one with `syg snapshot -o FILE` and name it in syg.yaml (snapshots:) or with --snapshot
   = explain: syg explain snapshot

2 notes
```

Two notes, and no findings. The notes say what was *not* checked, because a
check that did not run must never look like one that passed: rules that compare
with what is deployed had nothing to compare with, and rules that need facts
about a real cluster had no [snapshot](checks.md#snapshots). Neither is a
problem for a first build.

Now make a mistake. Change `replicas 2` to `replicas 1`:

```console
$ syg check shop
…
warning[single-replica-budget]: disruption budget on api, which runs a single replica
  --> shop/shop.syg:21:3
     |
  21 |   disruption { maxUnavailable 1, evictUnhealthy true }
     |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  --> shop/shop.syg:9:3
    |
  9 |   replicas 1
    |   ^^^^^^^^^^ one replica here
   = consequence: with one replica there is no non-disruptive eviction: `minAvailable 1` blocks every drain of the node it lands on, and `maxUnavailable 1` permits the eviction the budget was written to prevent, so the budget either stops all maintenance or does nothing
   = help: run more than one replica if this workload needs to survive node maintenance; if a single replica is correct, remove the budget and accept the restart
   = explain: syg explain single-replica-budget  (CHK-PDB-005)

1 warning, 2 notes
```

Every finding reads the same way, top to bottom:

1. **What is wrong,** in its first line, with the rule's name in brackets:
   `single-replica-budget`.
2. **Where,** at the lines you wrote: here the budget, and the replica count
   it conflicts with.
3. **What will happen** in production if you ship it (`consequence`).
4. **What to do** about it (`help`).
5. **Where to read more** (`explain`): `syg explain single-replica-budget`
   prints the whole mechanism, which is also
   [on this site](rules/availability.md#single-replica-budget).

So there is nothing to learn in advance: you meet a rule when it applies,
with its explanation attached. A warning does not fail the command; an error
does, and so does a warning under `--strict`. Put `replicas 2` back.

## 4. Build it

```console
$ syg build shop -o out
$ ls out
deployment-api.yaml  poddisruptionbudget-api.yaml  provenance  service-api.yaml
```

`build` checks first, and writes nothing if there are errors. Then it writes one
file per object, and the provenance of every field under `provenance/`. The
Deployment's selector, the pod labels, the Service's selector and the budget's
selector are one derived value:

```console
$ grep -A3 'selector:' out/service-api.yaml
  selector:
    app.kubernetes.io/instance: shop-api
    app.kubernetes.io/name: api
  type: ClusterIP
```

## 5. Apply it

Syg never touches a cluster. Applying is your pipeline's job; by hand:

```console
$ kubectl create namespace shop
$ kubectl -n shop apply -f out/
deployment.apps/api created
poddisruptionbudget.policy/api created
service/api created
$ kubectl -n shop rollout status deployment/api
deployment "api" successfully rolled out
```

## 6. Ask why

`syg why` says where any generated field came from:

```console
$ syg why shop deployment/api spec.selector
Deployment/api
  declared at shop.syg:6:9

  spec.selector is made of:
    spec.selector.matchLabels
      derived, from the declaration at shop/shop.syg:6:9: derived from the module and workload name; the same value fills every selector site
```

## Next

- [Derivation](derivation.md): what Syg writes for you, and why those are the
  mistakes it removes.
- [Checks](checks.md): errors, warnings, tiers, snapshots and what a clean
  result claims.
- [Golden paths](golden-paths.md): profiles and environments, for a platform
  team serving many services.
- Run `syg check --format github` in CI to see findings on pull requests
  ([CI integration](ci.md)).
