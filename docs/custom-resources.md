# Custom resources

Real clusters run operators: cert-manager, a service mesh, the Prometheus
Operator, Argo Rollouts. Their custom resources refer to your services,
secrets and ports by name, in YAML, and a wrong name there fails as silently as
a wrong selector. Syg handles them in three steps: write the object as **raw**
YAML, validate it against the operator's **schema**, and **relate** the fields
that refer to something, so Syg checks them.

Syg's support for custom resources is **declared-relationship-based, not
semantic**. It knows what a schema and a `relate` tell it, and nothing more.
It does not simulate an operator: whether cert-manager will issue a
certificate, or a mesh will route a request, happens in the cluster, after
Syg is done (`syg explain crd`).

## Raw objects

Any Kubernetes object can be written as YAML inside a module:

```syg-fragment
raw "networking.istio.io/v1/VirtualService" api {
  yaml """
    spec:
      hosts: [api]
      http:
      - timeout: 5s
        route:
        - destination: {host: api, port: {number: 8080}}
  """
}
```

The header is `GROUP/VERSION/Kind` (`v1/ConfigMap` for the core group), and
the name becomes `metadata.name`. Syg adds the namespace and its provenance
annotations (`syg.vishisht.tech/raw: "true"` among them, so anyone reading the object in
the cluster knows no check vouched for it), and emits the object as written.
It adds no labels: a raw object carries the labels you write.

The name must be one the API server takes for the kind: a lowercase DNS
subdomain for most kinds and every custom resource, a DNS label that starts
with a letter for a Service, at most 63 characters for a Job and 52 for a
CronJob, and any name without `/` or `%` for the RBAC kinds, upper case
included. Each object is written to a file named by its kind and name, so two
that would share one are an error: two RBAC names that differ only in case,
which macOS and Windows would write to one file, or one kind's name in two API
groups under one name (`syg explain raw`).

A Secret is never raw, since its values would then live in source: declare
`secret NAME { key ... }`, with keys only. That holds for a kind named Secret
in any group. Only the core group serves one, and `evil.example/v1/Secret`
would carry its values into source all the same.

Raw is the escape hatch for anything the language does not model, and it is
honest about what that costs: Syg does not see inside an object it knows
nothing about. A rule that needs to see every object of a kind (every route
to a Service, say) reports **reduced coverage** for a raw one, instead of a
clean result it has not earned. `syg check --stats` counts native and raw
objects, so you can see how much of a module Syg actually checks.

Three rules do read inside a raw object, so that it is not a way around them:

- `wildcard-permission` (CHK-RBAC-003) reads raw RBAC, for wildcards and for
  bindings to cluster-admin;
- `host-access` (CHK-SEC-002) reads the pod spec of a raw Pod, Deployment,
  StatefulSet, DaemonSet, Job or the like, and every one in a custom resource,
  wherever it is (any mapping with a list of containers or of init
  containers, as an Argo Rollout's `spec.template.spec`, one inside another
  included), for what the language has no way to write: a privileged
  container, the node's network, processes or IPC, a hostPath volume, a host
  port;
- `kernel-privileges` (CHK-SEC-003) reads the same pod specs, and the pod
  template's annotations, for what they ask of the kernel beyond Pod Security
  baseline: a capability outside the default set, seccomp or AppArmor
  `Unconfined`, an SELinux user, role or other type, a sysctl outside the safe
  set. It reads the workloads Syg derives too, for the two of these the
  language can write.

In a custom resource they read only what they judge, the pod's host
namespaces, security contexts, volumes and ports, each field on its own, so
that a value of the wrong type elsewhere hides nothing. One they read, of the
wrong type (`privileged: "true"`), is a warning at its line: they cannot
judge it.

A node agent that needs its node turns `host-access` off, or down to a warning,
in [`syg.yaml`](checks.md#configuring-rules), and one that needs more of the
kernel does the same with `kernel-privileges`. That records the decision, and
every check then names the rule it did not run.

A custom resource that holds pod templates as data, not to run them (a
policy's patterns, a documentation kind's examples), is read as one that runs
them, and its examples are reported as a running pod's settings would be.
Keep such objects in a module of their own, whose `syg.yaml` sets the two
rules to a warning or off: the module that imports it neither emits its raw
objects nor judges them.

A raw object in an imported module belongs to that module's own build: the
module that imports it type-checks it, but neither emits it nor runs its rules
on it, and the import gets a note saying so.

## Schemas

A raw object of a custom kind is validated against the kind's schema, as the
API server would, before anything is applied. Built-in kinds and the Gateway
API come with Syg. For an operator's kinds, vendor the CRD schemas into the
module's `schemas/`:

```console
$ syg schema vendor --from https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.crds.yaml
$ syg schema vendor --from cluster.snapshot.yaml --only monitoring.coreos.com
```

The source can be a CRD file, a directory, an https URL, or a
[snapshot](checks.md#snapshots). This is the one place Syg fetches anything,
and it is a command you run, never a side effect of `check` or `build`. A URL
is fetched over https only, redirects included, and a response larger than
64 MiB is refused rather than cut. A field the schema does not have, or a
value of the wrong type, is an error at the line in the YAML.

Each kind has one schema, from one CRD. A kind found twice in what you vendor,
in one source or two, is refused, naming both places: keep one. So are two
kinds whose file names differ only in case, such as `Widget` and `widget` of
one group, since macOS and Windows hold the two files as one; a module whose
`schemas/` holds two such files, or two files of one kind, is refused when it
is loaded.

A built-in kind's schema is Syg's own, and cannot be vendored over: `schema
vendor` skips one, and a vendored schema of one is refused when the module is
loaded, so a raw object and a `relate` of the kind are checked against the same
schema.

## Relations

A `relate` declaration says what a custom resource's fields mean:

```syg-fragment
relate networking.istio.io/v1 VirtualService {
  field spec.http[].route[].destination.host        references service
  field spec.http[].route[].destination.port.number references port of service
}
```

Each value such a field holds becomes an edge in Syg's graph, and the
relationship rules check it like any other:

```console
error[resource-reference-missing]: VirtualService api: spec.http[0].route[0].destination.host references service "apii", which this module does not declare
  --> mesh.syg:55:9
     |
  55 |         - destination: {host: apii, port: {number: 8080}}
     |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   = consequence: nothing by that name receives the traffic: a mesh route to it answers 503 to every request it matches (observed on Istio 1.26), and the object applies with no error or status
   = help: did you mean "api"?
```

The relations are:

| Relation | The field holds | Checked by |
|---|---|---|
| `references service`, `config`, `secret`, `identity` | the name of one of the module's | CHK-REL-001 |
| `references port of service` | a port, by number or name, of the service named nearest it in the object | CHK-REL-002 |
| `references GROUP/VERSION/Kind` | the name of a raw object of that kind, or an `extern resource` of it | CHK-REL-001 |
| `selects service`, `selects workload` | a label selector, which must match something | CHK-REL-003 |
| `produces secret`, `produces config` | a secret or config the resource creates, which `needs` and `tls` can then use | CHK-REL-005 |
| `provides host` | hosts the resource covers, checked against the TLS secret it produces | CHK-REL-004 |
| `requires storageclass` | the name of a storage class | CHK-REL-001 |

A field path is checked against the schema where the `relate` is written, so a
misspelt path is an error rather than a relation that silently checks nothing.
So are two relations on one field that contradict each other, and one relation
written twice in a module. One that an imported library also declares gets a
note: it is the same relation, checked once.

## Built-in kinds

`relate` is not only for custom resources. A built-in kind written as `raw`
can be related the same way, and that is how to keep a Service type Syg does
not model checked. Syg models ClusterIP Services (`internal`) and routes
(`expose`); a `NodePort` or `LoadBalancer` Service is raw, with its selector
related:

```syg-fragment
raw "v1/Service" frontend-nodeport {
  yaml """
    spec:
      type: NodePort
      selector: {app.kubernetes.io/name: frontend, app.kubernetes.io/instance: shop-frontend}
      ports: [{port: 80, targetPort: 80}]
  """
}

relate v1 Service {
  field spec.selector selects workload
}
```

Now a typo in the selector is an error, CHK-REL-003, whose help gives the
labels Syg put on the workload's pods (`syg build` shows them too). A relate
adds checks and hides nothing: the rules that read Services natively still do
not see inside the raw one, and the coverage note saying so stays.

The two selector relations differ in what they are compared with:

- **`selects workload`** matches **pod** labels: the selector of a Service, a
  PodDisruptionBudget, a PodMonitor or a NetworkPolicy, anything that picks
  pods.
- **`selects service`** matches the labels on **Service objects**: the
  selector of a ServiceMonitor, which picks Services and scrapes their
  endpoints.

A native NodePort and LoadBalancer construct is planned.

Choosing the wrong one gives a CHK-REL-003 error for a selector that is right,
with the other kind's labels in its help.

One thing a raw Service cannot have checked: its `targetPort`. `references port
of service` pairs a port with a service the same object names, and a Service
names none; it selects pods. Give `targetPort` as the container port's number
or name exactly as the workload declares it, and verify it once with `kubectl
get endpointslices`.

## Bundled libraries

Relations for common operators ship with Syg. Import one, and its relations
and schemas apply to your raw objects:

```syg-fragment
import "syg.vishisht.tech/relate/cert-manager"
import "syg.vishisht.tech/relate/istio"
```

The bundled libraries are `argo-rollouts`, `cert-manager`, `external-secrets`,
`gateway-api`, `istio` and `prometheus-operator`. Each is pinned in `syg.lock`
like any import. `syg mod vendor NAME` copies one into `vendor/`, where it takes
precedence, to pin it across Syg upgrades or to edit it.

## Things someone else owns

A custom object your resources refer to, but another team applies, is declared
`extern`:

```syg-fragment
extern resource "cert-manager.io/v1/ClusterIssuer" letsencrypt {}

relate cert-manager.io/v1 Certificate {
  field spec.issuerRef.name references cert-manager.io/v1/ClusterIssuer
}
```

It emits nothing. It puts the name in the closed world, so a relation can
resolve to it, and a [snapshot](checks.md#snapshots) checks the cluster serves its kind
(CHK-T2-CRD-001). As with every `extern`, it is trusted, not verified, until a
snapshot says otherwise.
