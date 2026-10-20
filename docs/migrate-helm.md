# Migrating from Helm

This walks through migrating a real service, [podinfo](https://github.com/stefanprodan/podinfo),
from its Helm chart to Syg: how to read the chart's output, how each object
becomes a few lines, how to check that nothing was lost, and how to cut over a
running release. Every command on this page is run by Syg's own CI, against a
real cluster, so it stays true. [From plain YAML](#from-plain-yaml), at the end,
covers manifests that no chart renders.

## 1. Render what you run today

Start from what the chart actually produces with your values, not from its
templates:

```console
$ helm template podinfo podinfo/podinfo --version 6.14.1 -n podinfo > helm-template.yaml
```

With default values, podinfo renders a Deployment, a Service, and three Pods
annotated `helm.sh/hook: test`. The hooks run under `helm test`; they are not
part of what is deployed, so they are not migrated.

## 2. Translate it

Read the Deployment and Service, and write down the decisions in them. The
rest (selectors, label sets, port wiring, the Service's backend) Syg derives:

```syg
module podinfo

service podinfo {
  image "ghcr.io/stefanprodan/podinfo:6.14.1"
  command "./podinfo" "--port=9898" "--prefix=/" "--cert-path=/data/cert"
    "--port-metrics=9797" "--grpc-port=9999" "--grpc-service-name=podinfo"
    "--level=info" "--random-delay=false" "--random-error=false"
  env PODINFO_UI_COLOR = "#34577c"
  replicas 1
  port http 9898
  port http-metrics 9797
  port grpc 9999
  resources { cpu 1m, memory 16Mi }
  health {
    live EXEC "podcli" "check" "http" "localhost:9898/healthz" every 10s timeout 5s after 1s failures 3
    ready EXEC "podcli" "check" "http" "localhost:9898/readyz" every 10s timeout 5s after 1s failures 3
  }
  scratch data at "/data"
  rollout { strategy rolling, maxUnavailable 1 }
  annotations {
    prometheus.io/scrape = "true"
    prometheus.io/port = "9898"
  }
  internal :http
  internal :grpc
}
```

How the chart's YAML maps:

| In the chart | In Syg |
|---|---|
| `containers[0].image`, `command`, `env` | `image`, `command`, `env` |
| `ports` (http, http-metrics, grpc) | three `port` lines; everything else refers to them by name |
| `resources.requests` | `resources { cpu, memory }` |
| `livenessProbe` / `readinessProbe`, `exec` with argv | `health { live, ready }`; `EXEC` with one string per argument runs it as written, with no shell |
| the `/data` emptyDir and its mount | `scratch data at "/data"`: one name, both sides |
| `strategy.rollingUpdate.maxUnavailable` | `rollout { maxUnavailable 1 }` |
| pod annotations | `annotations { ... }` |
| the Service, its selector and ports | `internal :http` and `internal :grpc` |

## 3. Check it

```console
$ syg check podinfo --namespace podinfo
2 notes
```

Clean. On a chart with problems, this is where they appear, at the line, with
the fix. Try `replicas 1` with a `disruption` budget to see one.

## 4. Compare with the chart

Build into the same namespace the chart rendered into, one file per object,
and compare each object with the chart's rendering of it. Any YAML diff will
do; with [yq](https://github.com/mikefarah/yq) v4 (mikefarah's, not the Python
wrapper of the same name):

```console
$ syg build podinfo --namespace podinfo -o out/
$ for f in out/*.yaml; do
>   kind=$(yq .kind "$f"); name=$(yq .metadata.name "$f")
>   echo "== $kind/$name"
>   diff <(yq -P "select(.kind == \"$kind\" and .metadata.name == \"$name\") | sort_keys(..)" helm-template.yaml) \
>        <(yq -P 'sort_keys(..)' "$f")
> done
```

Go through every difference and decide whether it is one you meant. For
podinfo they are:

- **Labels and selectors.** Syg derives its own label set, with an `instance`
  label beside `name`, and Helm's bookkeeping labels are gone. See
  [derivation](derivation.md).
- **Syg's provenance annotations**, on every object.
- **The Prometheus annotations** are on the Deployment as well as its pods.
  Prometheus reads the pods', which are the same.
- **No API token** is mounted: podinfo has no identity, so it does not get one.
- **Defaults the chart writes out** (`imagePullPolicy: IfNotPresent`,
  `successThreshold: 1`, `terminationGracePeriodSeconds: 30`, `emptyDir: {}`) are
  left to the API server, which fills in the same values.

Syg's own CI makes the same comparison for this example, and fails if a
difference appears that is not on that list.

## 5. Cut over

One difference needs a plan: **a Deployment's selector cannot change.** Syg's
selector includes the `instance` label, so applying Syg's Deployment over the
chart's is refused. Syg tells you before you try, if you give it the current
manifests as a baseline:

```console
$ syg check podinfo --namespace podinfo --baseline helm-template.yaml
error[selector-change]: the selector of Deployment podinfo changes from {"matchLabels":{"app.kubernetes.io/name":"podinfo"}} to {"matchLabels":{"app.kubernetes.io/instance":"podinfo-podinfo","app.kubernetes.io/name":"podinfo"}}, and a selector cannot change
   = consequence: the apply is refused with `field is immutable`: the object must be deleted and recreated, which takes every pod down at once
```

Three ways through, in order of preference:

1. **A new namespace.** Build with `--namespace podinfo-v2` (or declare an
   [environment](golden-paths.md) with its own namespace), apply, verify, move
   traffic to it, then `helm uninstall` the old release. No outage, and a way
   back.
2. **A new name.** Call the service `podinfo-v2` in the same namespace, and
   move traffic the same way.
3. **Delete and recreate** the Deployment in a maintenance window. The
   Service keeps its name, but every pod goes down at once.

Whichever you choose, `helm uninstall` the release once nothing uses it, so
Helm stops managing objects Syg now owns.

## 6. Run it

```console
$ kubectl create namespace podinfo-v2
$ syg build podinfo --namespace podinfo-v2 -o out/
$ kubectl apply -f out/
$ kubectl -n podinfo-v2 rollout status deployment/podinfo
deployment "podinfo" successfully rolled out
$ kubectl -n podinfo-v2 exec deploy/podinfo -- podcli check http localhost:9898/healthz
```

From here, the module is yours to improve: two replicas and a budget so a node
drain does not take podinfo down, a readiness probe on a different endpoint
from liveness (it already is), an `identity` if it ever calls the API.

## From Kustomize

podinfo's repository also has a Kustomize base. Its `kustomize build` adds an
autoscaler and limits, which translate directly:

```syg-fragment
  resources {
    cpu 100m
    memory 64Mi
    limits { cpu 2000m, memory 512Mi }
  }
  scale on cpu at 99% between 2 and 4
```

`replicas` is left out, so the autoscaler owns the count. Three Deployment
fields in that base have no Syg construct in 1.0: `minReadySeconds`,
`progressDeadlineSeconds` and `revisionHistoryLimit`. Without them the API
server's defaults apply: a pod counts as available as soon as it is ready, a
stuck rollout is reported after ten minutes, and ten old ReplicaSets are kept.
If one matters to you, keep that Deployment in a `raw` block until Syg models
it.

## From plain YAML

Manifests kept as YAML files migrate the same way, without step 1: the files
are what you run today. Translate each Deployment, StatefulSet or Job and the
Service in front of it into one workload, then check, compare and cut over as
above. What changes on the way, and is easy to miss:

- **Names.** Keep each workload's name: it becomes the Service name, which is
  how other workloads find it by DNS. The main container is renamed after the
  workload; see [names](language.md#names).
- **Selectors.** Hand-written labels such as `app: web, tier: frontend` are
  replaced by derived ones, so `syg check --baseline old.yaml` reports
  CHK-SEL-005 for every workload, and the cutover in step 5 applies. Your own
  labels can stay, with `labels { }`; they are never in a selector.
- **Service types.** Syg models ClusterIP Services (`internal`) and routes
  (`expose`). A `NodePort` or `LoadBalancer` Service stays a raw object, with a
  `relate` so its selector is still checked: see
  [other Service types](custom-resources.md#built-in-kinds).
- **Probes.** A workload with no readiness probe gets a warning (CHK-PRB-005):
  it receives traffic the moment its process starts. Adding one changes
  behaviour, for the better, and the warning's help suggests one for its port.
- **Defaults.** Fields the old YAML spells out at their default values are left
  to the API server, which fills in the same ones.
