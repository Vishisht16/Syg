# Network policy

Policies that cut off a dependency the module declares.

## policy-blocks-dependency

`CHK-NP-002` · error · checked offline

Connections are refused or time out, and neither object's status says why.

### What you see

A connection that worked yesterday is refused, or hangs until the client times
out. Nothing in either object's status says why: the policy is valid, both
workloads are Ready, the Service has endpoints. When the path is DNS, every
lookup fails and the client reports an unknown host, which reads as a naming
problem rather than a network one.

The common way in is a change elsewhere. Someone adds a policy to restrict a
workload's egress, or a platform team applies a default-deny to the namespace,
and paths nobody was thinking about stop working.

### Why it happens

A pod is non-isolated in a direction until a NetworkPolicy of that direction
selects it. From then on, only traffic that some policy selecting it allows gets
through. Policies are additive: nothing can deny what another policy allows,
and nothing is allowed that no policy allows. A connection needs both ends: the
client's egress and the server's ingress.

Which directions a policy isolates is its `policyTypes`. Left out, the API
server sets it to `Ingress`, plus `Egress` when the policy has egress rules. So
a policy written only to restrict egress, with no `policyTypes`, isolates
ingress as well, with no ingress rule: every connection to the pods is cut.

Enforcement is the network plugin's. The API server stores policies; it does
not apply them (`CHK-T2-NET-002` checks the plugin).

### What Syg catches

A path the module says it needs, which the network policies selecting its pods
do not allow. The required paths are:

- **each `needs service` dependency.** The client's egress must allow the
  server on the port, and, when the server is a workload of the module, the
  server's ingress must admit the client;
- **DNS, for a workload with dependencies.** It reaches each one by its
  Service's name;
- **each exposed port.** The gateway's pods must be admitted;
- **the API server, for a workload whose identity has grants.**

The policies are Syg's (`policy`) and raw NetworkPolicies together, combined
the way Kubernetes combines them. A raw policy whose peers Syg cannot evaluate
(an `ipBlock`, a namespace selected by its labels) gives a coverage note, not a
verdict.

### Why Syg checks rather than prevents

Syg's own policies cannot cut what Syg derives: a dependency's egress, DNS and
an exposed port are added to every policy that isolates the direction. But the
other end is someone else's choice. A server's policy decides whom it admits,
and Syg does not open it on a client's behalf, because a client declaring
itself would defeat the server's isolation. A raw policy can say anything. So
the paths are checked, over every policy in the closed world.

### Kubernetes versions

NetworkPolicy is `networking.k8s.io/v1` since Kubernetes 1.7, and `policyTypes`
since 1.8, with the same defaulting since.

Observed on k3s v1.32.12, whose embedded kube-router enforces NetworkPolicy:

- **Declared paths connected:** a dependency; an exposed port, from another
  namespace; a peer in another namespace; DNS; the API server where allowed.
- **Every other path was refused:** an undeclared client, a port reserved to a
  peer, and the API server where the policy did not allow it.
- **The API server port:** a policy that allowed 443 alone did not let a pod
  reach `kubernetes.default:443`. The policy sees the translated address, the
  API server's own port (6443 on k3s). Syg's `apiserver` peer allows both
  ports.
- **The default-deny:** a default-deny applied with kubectl cut a path the
  module declared. `syg check` on the module, with that policy as raw, reported
  this rule for it.
- **The defaulted `policyTypes`:** a policy with only an egress rule and no
  `policyTypes` was stored with `["Ingress","Egress"]`, and cut ingress to its
  pods. `syg check` reported this rule for it too.
- **Probes:** a pod whose ingress admits nothing still passed its readiness
  probe. The kubelet probes from the node, which a policy does not isolate a
  pod from.

kube-router refused dropped connections; other plugins drop them, and the
client times out.

### What Syg does not claim

The verdict covers the policies in the closed world: Syg's, and the module's raw
NetworkPolicies. A policy applied by someone else to the namespace, or a
plugin's own policy kind (a CiliumNetworkPolicy, a Calico GlobalNetworkPolicy),
is outside it, and a custom resource in the module is reported as reduced
coverage for this rule.

An extern service's side of a path is not checked: the policies selecting its
pods are not in the closed world. A clean result does not say the cluster's
plugin enforces any of this (`CHK-T2-NET-002`). An extern service's port is
taken as the port its pods listen on, which is what a policy sees.

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/network-policies/
- https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/
- https://github.com/kubernetes/kubernetes/blob/master/pkg/apis/networking/v1/defaults.go

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

## reachability-report

`CHK-NP-003` · info · checked offline

Who can reach whom is invisible in the manifests: it is the union of every policy selecting each pod.

### What you see

Who can reach a pod is not written anywhere in the manifests. It is the union of
every policy that selects the pod, per direction, and each policy names its
peers by label selectors. A reviewer reading one policy sees one contribution
to that union. The question "can web reach the database?" ends up answered by
trying it.

### Why it happens

A pod is isolated in a direction once a NetworkPolicy of that direction selects
it. What it then allows is the union of the rules of every policy selecting it.
A rule's peers are pods chosen by label, namespaces chosen by label, or address
blocks, and its ports are numbers or the names of container ports.

Enforcement is the network plugin's, and some plugins enforce nothing.

### What Syg catches

Nothing is wrong: it reports, for each workload that links a policy, who may
reach it and whom it may reach, per direction. What Syg derived is marked:
exposed ports, DNS, and `needs service` dependencies.

It also flags:

- **an over-broad peer.** An extern service with no namespace is selected as
  every pod of the module's namespace, which is all that is known of it;
- **a policy that isolates nothing.** It declares neither direction, so no
  NetworkPolicy is emitted for it.

### Why Syg checks rather than prevents

It is a report, not a finding: a module's reachability is what its author
decided, and nothing about it is wrong in itself. It is computed from the graph
because the manifests do not state it anywhere.

### Kubernetes versions

NetworkPolicy semantics are unchanged since `networking.k8s.io/v1` (Kubernetes
1.7, `policyTypes` 1.8). The report's paths were exercised on k3s v1.32.12:
each allowed path connected and each other was refused.

### What Syg does not claim

The report covers the module's own policies, within the closed world. Policies
applied by others, and a plugin's own policy kinds, are outside it. Without a
snapshot the report says enforcement is unverified; with one, it says what the
snapshot shows about the network plugin (`CHK-T2-NET-002`).

### Further reading

- https://kubernetes.io/docs/concepts/services-networking/network-policies/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

