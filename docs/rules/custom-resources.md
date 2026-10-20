# Custom resources

References inside operators' resources that point at nothing.

## resource-reference-missing

`CHK-REL-001` · error · checked offline

The custom resource applies cleanly and its controller finds nothing by that name at runtime: a mesh route answers 503 to every request it matches, a rollout's pods are refused their service account.

### What you see

The object applies cleanly, and nothing reports a problem until traffic or a
controller needs the thing it names. For a mesh route, every request the route
matches fails. The VirtualService's status says nothing, and the only tool that
notices is `istioctl analyze`, and only if someone thinks to run it.

The other references fail the same way, each in its own controller's
vocabulary:
- a rollout's pods are refused a service account that does not exist;
- a resource waits forever for a secret nothing creates;
- a claim names a class with no provisioner.

### Why it happens

A custom resource's fields are opaque to the API server. Its schema says a field
is a string, and any string passes. The name is resolved later, by the
controller, against whatever exists at that moment. Nothing connects the string
to an object at admission time. That is the same gap an Ingress backend's
`service.name` has, and Syg closes it for its own routes by construction
(`CHK-NET-001`).

### What Syg catches

A value inside a custom resource that a `relate` declaration says names a
service, config, secret, identity or storage class, and that names none the
module declares or declares `extern`. For example, a VirtualService routing to
`apii` in a module whose service is `api`. A relation can also name any other
kind, `references GROUP/VERSION/Kind`: then the value must name a raw object of
that kind or an `extern resource` of it, as a Certificate's
`spec.issuerRef.name` names a ClusterIssuer.

### Why Syg checks rather than prevents

Because the reference is a string written into YAML, inside a `raw` block, and
Syg does not own the language it is written in.

For its own objects, Syg removes the string altogether: an `expose` names a
declaration, and there is no syntax for a backend name. A custom resource's
fields are the CRD author's, not Syg's. What a `relate` declaration buys is the
knowledge that this field holds a service name. With that, Syg can look the
value up among the module's declarations at compile time, and report a miss at
the line that holds it, with the nearest name it does know.

### Kubernetes versions

Observed on k3s v1.32.12 with Istio 1.26.0 (istiod, minimal profile, sidecar
injection), in a module Syg built:

- **The good case.** A VirtualService routing `api` to `api:8080`: 200 on every
  request through the client's sidecar.
- **The same VirtualService routing to `apii`.** The apply succeeds, and the
  status stays empty. Every request answers 503 from Envoy.
  `istioctl analyze -n mesh` reports `IST0101 Referenced host not found: "apii"`.

Requests were made from the application container. Requests from the
`istio-proxy` container run as Envoy's own UID, bypass the sidecar, and answer
200 whatever the route says. That pitfall is worth knowing when reproducing
this.

### What Syg does not claim

**Syg knows only what a relate declares** (`syg explain crd`). A field nobody related is
not looked at.

**Hosts outside the module's namespace are not checked.** A fully qualified
host, such as `api.example.com` or `name.other.svc.cluster.local`, is outside
the module's namespace or outside the cluster. Syg cannot see that world, so
these are left alone. A short name, or `name.ns.svc` naming a service the
module declares, is checked.

**An `extern` name resolves, and is trusted, not verified.** Whether the thing
it names exists in a real cluster is a Tier-2 question (`CHK-T2-EXT-001`).

### Further reading

- https://istio.io/latest/docs/reference/config/networking/virtual-service/#Destination
- https://istio.io/latest/docs/reference/config/analysis/ist0101/
- https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## resource-port-missing

`CHK-REL-002` · error · checked offline

Traffic or scraping aimed at a port the Service does not have goes nowhere: a mesh route fails its requests, a ServiceMonitor endpoint yields no target.

### What you see

The route or the scrape goes nowhere, and every object involved still reports
healthy:
- **A mesh route** answers 503 to every request it matches.
- **A ServiceMonitor endpoint** yields no target. Prometheus shows the job and
  never scrapes anything for it.

A common variant is a port that the container declares, but that the Service
does not publish. A ServiceMonitor names the Service's port, not the
container's.

### Why it happens

A Service publishes only the ports listed in its `spec.ports`. A mesh routes a
`destination.port.number` to a Service port, and the Prometheus Operator turns
each `endpoints[].port` into a relabel rule that keeps only endpoints whose port
name matches. A port that is absent matches nothing in either case, and neither
the API server nor the controller rejects the object that names it.

In Syg, a Service carries the ports a service exposes and those it lists as
`internal`. A port declared on the container alone is not on the Service.

### What Syg catches

A port, by number or by name, that a custom resource aims at a service the
module declares, and that the service's Kubernetes Service does not have. For
example:
- a VirtualService routing to `api` on port 8081, when `api` serves 8080;
- a ServiceMonitor scraping the endpoint port `metrcs`.

### Why Syg checks rather than prevents

Because the port is written in YAML that Syg does not own (see `CHK-REL-001`).
For an `expose`, the port is a `:name` reference that resolves against the
service's own declarations (`CHK-NET-002`, PREVENTED). A custom resource's port
is a number or a string in its own fields.

The relate declaration says the field is a port of a service. Syg pairs the
port with the service named nearest to it in the same object: the field sharing
the longest path with it. In a VirtualService that is the `destination.host`
beside the `destination.port`. In a ServiceMonitor it is the one
`spec.selector`, shared by every endpoint. The port is then looked up on that
Service as Syg emits it: a YAML integer by number, a string by name.

### Kubernetes versions

Observed on k3s v1.32.12, against modules Syg built:

- **Istio 1.26.0.** A VirtualService routing `api` to port 8081, when the Service
  has only 8080: every request answers 503 from Envoy. The good port answers 200.
  `istioctl analyze` reports `IST0101 Referenced host:port not found`.
- **Prometheus Operator v0.77.1, with a real Prometheus.** A ServiceMonitor whose
  endpoint port is `metrcs`: its scrape job exists, with no active target. Every
  endpoint discovered for it was dropped by relabelling. The correct ServiceMonitor
  beside it had one active target. Neither the operator log nor the Prometheus
  resource's conditions mention the problem.

### What Syg does not claim

**Some ports are not checked.** A port paired with a service Syg cannot
resolve is not checked; `CHK-REL-001` or `CHK-REL-003` reports that instead.
Neither is a port paired with an external host, or with an `extern service`
that declares no ports.

**Syg does not know whether anything listens on the port.** That is a runtime
fact.

**The pairing rule is a heuristic over the object's shape.** A CRD whose port
and service sit in unrelated parts of the object can pair them wrongly. Relate
such a kind's fields so their paths share the prefix that groups them.

### Further reading

- https://istio.io/latest/docs/reference/config/networking/virtual-service/#PortSelector
- https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Endpoint
- https://kubernetes.io/docs/concepts/services-networking/service/#multi-port-services

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## selector-matches-nothing

`CHK-REL-003` · error · checked offline

A selector matching no labels selects nothing, silently: a ServiceMonitor scrapes no target and Prometheus reports no error.

### What you see

Nothing, which is the problem. A selector that matches no labels selects no
object, and no component treats that as an error. A ServiceMonitor that matches
nothing produces a scrape job with no targets. The dashboards built on it stay
empty, and the alerts built on it never fire, because there is nothing to alert
on. The gap is found when the metrics are needed.

### Why it happens

A label selector is a query, not a reference: an empty result is a valid answer.
The API server validates the selector's syntax and never its matches. The
controller evaluates it continuously, and acts on whatever matches. Here that
is nothing. Syg's own selectors are derived from one value, so they cannot
disagree with the labels they select (`CHK-SEL-001`, PREVENTED). A custom
resource's selector is written by hand, against labels the author may never
have seen.

### What Syg catches

A label selector inside a custom resource, related as `selects service` or
`selects workload`, that matches none of the Services or pods the module emits.
The classic case is a ServiceMonitor selecting `app: api`, the label every
tutorial uses. Syg labels its objects `app.kubernetes.io/name` and
`app.kubernetes.io/instance`.

### Why Syg checks rather than prevents

Because the selector is written in YAML Syg does not own. What Syg does own is
the other side: the exact labels it emits on every Service and pod template. The
relate declaration says which field is a selector and what it selects, and Syg
compares the selector with those labels at compile time. When nothing matches,
the error shows the labels Syg emits, which are the ones to select on.

### Kubernetes versions

Observed on k3s v1.32.12 with Prometheus Operator v0.77.1 and a Prometheus
instance, against a Service Syg built:

- **The ServiceMonitor selecting `app.kubernetes.io/name: api`** had one active
  target.
- **The one selecting `app: api`** had a generated scrape job
  (`serviceMonitor/rel-obs/badselector/0`), no active target, and every
  discovered endpoint dropped. The operator logged no warning or error about it,
  and the Prometheus resource stayed `Available=True, Reconciled=True`.

### What Syg does not claim

**Only `matchLabels` is followed.** `matchExpressions` and namespace selectors
are not.

**A selector that matches something in this module may match more elsewhere in
the namespace.** That is not checked.

**Only the module's own objects are compared.** A selector meant for objects
outside the module, such as a shared monitoring Service, will be reported. Such
a resource belongs with those objects, not in this module.

### Further reading

- https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors
- https://prometheus-operator.dev/docs/developer/troubleshooting/#overview-of-servicemonitor-tagging-and-related-elements

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## certificate-host-mismatch

`CHK-REL-004` · error · checked offline

The certificate is issued and valid, and every client rejects it: the name it is presented for is not one it was issued for.

### What you see

The certificate is issued, valid, and trusted, and every client rejects it for
this host: a name mismatch at the TLS handshake. Nothing in the cluster is
unhealthy. The Certificate is `Ready`, the secret exists, the gateway serves it.
The failure lives entirely in the clients, and it usually surfaces when a host
is added to a route without being added to its certificate.

### Why it happens

A TLS secret is a key pair; the names it is good for are inside the
certificate, in its subjectAltName. cert-manager writes exactly the
`spec.dnsNames` it was given. A route or ingress serves whatever secret it
names, for whatever host it routes. Nothing compares the two. Clients do:
hostname verification (RFC 6125) rejects a certificate whose names do not cover
the host requested.

### What Syg catches

An `expose ... at HOST tls SECRET` whose secret a custom resource in the module
produces, where that resource does not provide `HOST`. For example, a
cert-manager Certificate whose `dnsNames` do not include the host the secret
serves. A wildcard `*.example.com` covers exactly one label in its place, as
in a certificate.

### Why Syg checks rather than prevents

Because the names live in the producing resource's YAML, and Syg does not write
that resource. Syg knows the host, from `expose`, and the secret name, and the
relate declaration tells it which resource produces that secret
(`produces secret`) and for which hosts (`provides host`). The rule compares
them at compile time, before a certificate is ever requested.

### Kubernetes versions

Observed on k3s v1.32.12 with cert-manager v1.21.0 running and a self-signed
Issuer:
- **The issued secret.** A Certificate with `dnsNames: [a.example.com]`
  produced a secret whose certificate's SAN is exactly `DNS:a.example.com`.
- **The handshake.** That key pair was served with `openssl s_server`, and curl
  was pointed at it. For `a.example.com` the subjectAltName matched. For
  `b.example.com` curl failed with `SSL: no alternative certificate subject name
  matches target host name 'b.example.com'`.

### What Syg does not claim

**Only produced secrets are checked.** A secret that only an `extern` names is
not checked: its certificate is outside the closed world.

**Syg does not check whether the certificate is issued, trusted, or unexpired,**
or whether the issuer it names exists. Those are runtime facts.

**Only `expose` hosts are compared.** Hosts served by raw Ingresses or
HTTPRoutes are not.

### Further reading

- https://cert-manager.io/docs/usage/certificate/
- https://www.rfc-editor.org/rfc/rfc6125#section-6.4

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## duplicate-producer

`CHK-REL-005` · error · checked offline

One producer wins the name and the other never produces anything: cert-manager issues the first Certificate and leaves the second Ready=False (IncorrectCertificate), so the names only the second asked for are never served.

### What you see

One producer wins and the other never produces anything. With cert-manager, the
first Certificate is issued and keeps the secret. The second stays
`Ready=False` with reason `IncorrectCertificate`: "Secret was issued for "a".
If this message is not transient, you might have two conflicting Certificates
pointing to the same secret." The hosts only the second asked for are served
the first one's certificate. That is `CHK-REL-004`'s failure, reached by a
different road, and it does not go away.

The usual cause is copy and paste: a new Certificate made from an old one, with
the `secretName` left as it was.

### Why it happens

A secret's name is the identity of the object in the namespace. Two producers of
one name are two controllers, or two objects of one controller, writing the same
object. cert-manager detects this: it records which Certificate a secret was
issued for, in the `cert-manager.io/certificate-name` annotation, and refuses
to reissue the secret for another. Other controllers may simply overwrite each
other.

A declared `secret` or `extern secret` of the same name is a third claim. It
says something outside the module creates the object the producer is about to
write.

### What Syg catches

Two custom resources that produce a secret or config of the same name, such as
two Certificates with one `secretName`. It also catches a produced name the
module also declares, with `secret`, `config` or `extern`.

### Why Syg checks rather than prevents

Because the names are written in YAML the module does not own. A relate
declaration marks a field as `produces secret`, and Syg collects every value
produced across the module's custom resources, and every declared name. It
reports a second claim on one name at the line that makes it. Syg's names are
one namespace across kinds, so a produced secret colliding with a declared
config is reported too.

### Kubernetes versions

Observed on k3s v1.32.12 with cert-manager v1.21.0:
- **The setup.** Two Certificates, `a` and `b`, both with
  `secretName: shared-tls`.
- **Who won.** `a` was issued (`Ready=True`), and `b` stayed
  `Ready=False, IncorrectCertificate`.
- **It stayed that way.** Polled every 10 seconds for two minutes, the secret's
  annotation stayed `a` throughout. Exactly one CertificateRequest existed,
  `a-1`. There was no tug of war, and `b` was simply never issued.

### What Syg does not claim

**Only producers in this module are seen.** Producers in other modules, or
installed by hand, are not.

**Syg does not model what each controller does on a collision.** The symptom
above is cert-manager's, observed. Another controller may overwrite instead.

### Further reading

- https://cert-manager.io/docs/usage/certificate/
- https://cert-manager.io/docs/troubleshooting/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

