# What Syg catches

You do not need to learn these. When one applies, Syg reports it at the line, with what goes wrong, why, and how to fix it, and `syg explain NAME` tells the whole story. This page is for browsing.

Each rule has a readable name, which findings lead with, and a code (`CHK-…`) that stays the same forever, for tools. `syg.yaml` and `syg explain` take either.

## [Mistakes you can't make](../rules/prevented.md)

Mistakes the language makes impossible to write, so Syg never has to report them.

- [`missing-config`](../rules/prevented.md#missing-config): The pod never starts: it sits in CreateContainerConfigError, which reads as a container problem rather than a missing object
- [`missing-secret`](../rules/prevented.md#missing-secret): The same stuck pod, with the same misleading error, for a secret nobody created
- [`cross-namespace-reference`](../rules/prevented.md#cross-namespace-reference): The pod never starts, with the same CreateContainerConfigError as a missing object: the object exists, just in a namespace the pod cannot see
- [`autoscaler-target-missing`](../rules/prevented.md#autoscaler-target-missing): The autoscaler does nothing at all (no error, no events, no scaling), and the workload silently stays at whatever replica count it started with
- [`route-backend-missing`](../rules/prevented.md#route-backend-missing): An Ingress or HTTPRoute naming a Service that does not exist returns 502/503 for every request, while every object involved reports healthy
- [`route-port-missing`](../rules/prevented.md#route-port-missing): Routing to a port the Service does not expose yields refused connections
- [`service-port-unmapped`](../rules/prevented.md#service-port-unmapped): A Service targetPort with no matching containerPort yields refused connections
- [`policy-peer-missing`](../rules/prevented.md#policy-peer-missing): A peer selector that matches no pod allows nothing: the traffic it was written for is dropped
- [`probe-port-missing`](../rules/prevented.md#probe-port-missing): The kubelet cannot connect, so the probe fails forever: a readiness probe keeps the pod permanently out of service, and a liveness probe restarts it in a loop
- [`identity-missing`](../rules/prevented.md#identity-missing): The pod silently runs as the namespace's default ServiceAccount, with whatever permissions that account happens to carry: too many or too few, and never the ones intended
- [`unbound-permissions`](../rules/prevented.md#unbound-permissions): A correct, carefully-scoped Role grants nothing at all; the application receives 403 Forbidden at its first API call, possibly weeks after deployment
- [`token-automount`](../rules/prevented.md#token-automount): A credential for the API server sits in the filesystem of a workload that never calls the API server, widening what a compromise of that container reaches
- [`security-field-unset`](../rules/prevented.md#security-field-unset): The golden path's mandated posture silently does not apply to some workload or container, which is found by an audit or an incident rather than a review
- [`service-selects-nothing`](../rules/prevented.md#service-selects-nothing): A Service whose selector matches no pods returns connection refused / 503
- [`selector-template-mismatch`](../rules/prevented.md#selector-template-mismatch): The controller cannot own the pods it creates: either the API server rejects the object outright, or the workload creates pods endlessly and never becomes ready
- [`budget-selects-nothing`](../rules/prevented.md#budget-selects-nothing): A budget that matches nothing silently protects nothing, and one that matches too much blocks drains of unrelated workloads
- [`policy-selects-nothing`](../rules/prevented.md#policy-selects-nothing): A policy whose selector matches nothing isolates nothing, and one that matches other pods cuts their traffic
- [`shared-stateful-claim`](../rules/prevented.md#shared-stateful-claim): Replicas that were supposed to own separate state contend for one disk, or lose their data when rescheduled

## [Availability](../rules/availability.md)

Disruption budgets and rollouts that block node drains or take every replica down at once.

- [`budget-blocks-eviction`](../rules/availability.md#budget-blocks-eviction): Node drains hang indefinitely; cluster upgrades stall; autoscaler scale-down never completes
- [`budget-unsatisfiable`](../rules/availability.md#budget-unsatisfiable): Voluntary disruption becomes impossible once the workload is at its floor: drains hang, and the incident arrives during a cluster upgrade rather than a deploy
- [`rollout-exceeds-budget`](../rules/availability.md#rollout-exceeds-budget): Every deploy takes the workload below the availability its disruption budget promises; the budget records the breach and cannot prevent it
- [`eviction-policy-unset`](../rules/availability.md#eviction-policy-unset): A node drain hangs on pods that are running but not ready: the budget is already unmet, so the Eviction API refuses to evict even the pods that serve nothing
- [`single-replica-budget`](../rules/availability.md#single-replica-budget): Either the budget protects nothing, or it blocks every node drain in the cluster indefinitely, and which of the two depends on a value most authors set without noticing

## [Health probes](../rules/probes.md)

Probes that restart healthy pods, or send traffic to pods that are not ready.

- [`shared-probe-endpoint`](../rules/probes.md#shared-probe-endpoint): A brief downstream outage restarts every replica simultaneously, destroying capacity at the exact moment the system is already degraded
- [`liveness-checks-dependency`](../rules/probes.md#liveness-checks-dependency): A brief outage of a database or downstream service fails every replica's liveness probe at once, and the kubelet restarts them all: capacity is destroyed while the dependency is already degraded, and the restarts add load as it recovers
- [`slow-start-without-startup-probe`](../rules/probes.md#slow-start-without-startup-probe): A fixed initial delay is wrong both ways: a start slower than it gets the container killed in a restart loop, and every start faster than it leaves a wedged process unwatched for the whole delay
- [`missing-readiness-probe`](../rules/probes.md#missing-readiness-probe): Every rollout produces a burst of errors: the Service adds each new pod to its endpoints the moment the container starts, before the application can serve

## [Resources](../rules/resources.md)

Requests and limits that get pods evicted first, throttled, or scheduled where they do not fit.

- [`missing-requests`](../rules/resources.md#missing-requests): The pod is BestEffort: first to be evicted under node pressure, and not autoscalable on utilization
- [`limit-below-request`](../rules/resources.md#limit-below-request): The API server rejects the workload, so the deploy fails at apply time rather than here
- [`qos-class-report`](../rules/resources.md#qos-class-report): Under node memory pressure the kubelet evicts pods using more memory than they request, BestEffort and Burstable ones, and a disruption budget does not stop it
- [`qos-mismatch`](../rules/resources.md#qos-mismatch): A workload meant to be Guaranteed is Burstable, so it is evicted under node pressure before the pods it was meant to outlast
- [`sidecar-without-requests`](../rules/resources.md#sidecar-without-requests): The pod cannot reach the QoS class the app container was specified for, and is evicted earlier than intended under node pressure

## [Scaling](../rules/scaling.md)

Autoscalers that cannot scale, fight the declared replica count, or undercut a budget.

- [`autoscaler-without-request`](../rules/scaling.md#autoscaler-without-request): The HPA reports an unknown metric and never scales; the workload stays at minReplicas through any amount of load
- [`autoscaler-bounds-invalid`](../rules/scaling.md#autoscaler-bounds-invalid): The API server rejects the object, or the autoscaler is admitted and cannot function
- [`replicas-fight-autoscaler`](../rules/scaling.md#replicas-fight-autoscaler): Under GitOps auto-sync, the reconciler re-applies the static replica count and the HPA rescales: the Deployment flaps between the two values and the Application never settles
- [`autoscaler-floor-below-budget`](../rules/scaling.md#autoscaler-floor-below-budget): Scale-down and node drains deadlock: the autoscaler tries to remove pods the budget forbids evicting, so the cluster autoscaler never completes and upgrades stall
- [`autoscaler-vpa-overlap`](../rules/scaling.md#autoscaler-vpa-overlap): The two autoscalers chase each other: the VPA raises the request, utilisation (a percentage of the request) falls, the HPA scales in, per-pod load rises, the VPA raises the request again

## [Traffic](../rules/traffic.md)

Routes that lead nowhere, collide, or expose a host without TLS.

- [`route-path-incomplete`](../rules/traffic.md#route-path-incomplete): A route that resolves at every named hop but ends at no running container returns 503 with nothing reporting an error
- [`route-conflict`](../rules/traffic.md#route-conflict): Conflicting rules route nondeterministically depending on controller merge order, so which service answers can change on a restart
- [`host-without-tls`](../rules/traffic.md#host-without-tls): Traffic to a public hostname crosses the internet in plaintext

## [Network policy](../rules/network-policy.md)

Policies that cut off a dependency the module declares.

- [`policy-blocks-dependency`](../rules/network-policy.md#policy-blocks-dependency): Connections are refused or time out, and neither object's status says why
- [`reachability-report`](../rules/network-policy.md#reachability-report): Who can reach whom is invisible in the manifests: it is the union of every policy selecting each pod

## [Config and secrets](../rules/config.md)

Keys that do not exist, variables defined twice, configuration nothing reads.

- [`missing-key`](../rules/config.md#missing-key): The container starts with the variable unset, or crashes on first use (which of the two depends on how the value is consumed), and neither points at the missing key
- [`duplicate-env-var`](../rules/config.md#duplicate-env-var): One definition silently wins and the other is discarded, so the running value is not the one the reader of the source expects
- [`unused-config`](../rules/config.md#unused-config): Dead configuration accumulates and is maintained, reviewed, and rotated for no reason

## [Identity and images](../rules/identity.md)

Permissions wider than they need to be, and images that can change under you.

- [`mutable-image-tag`](../rules/identity.md#mutable-image-tag): Two deploys of the same manifest run different code, and a rollback returns to a tag whose contents have since changed, so it does not roll anything back
- [`image-not-pinned`](../rules/identity.md#image-not-pinned): The same manifest runs different code over time: a tag can be moved to another image, so what was reviewed is not what a node pulls next
- [`wildcard-permission`](../rules/identity.md#wildcard-permission): The grant silently widens over time: a component installed next year introduces a new resource kind, and this rule already covers it
- [`cluster-wide-permission`](../rules/identity.md#cluster-wide-permission): A namespaced Role naming a cluster-scoped resource grants nothing, so the workload gets 403 on a call its author believed was authorised
- [`unused-identity`](../rules/identity.md#unused-identity): Permissions are declared and reviewed but grant nothing, because nothing runs as the account

## [Storage and scheduling](../rules/storage.md)

Volumes and placement rules that pin pods, leave them Pending, or cannot be met.

- [`spread-exceeds-domains`](../rules/storage.md#spread-exceeds-domains): Pods beyond the number of topology domains stay Pending forever; or a rollout never progresses, because its surge pod has no domain to go to and no old pod is ever removed
- [`unknown-topology-key`](../rules/storage.md#unknown-topology-key): A misspelt key matches no node label: a strict spread or avoid leaves every pod Pending, a soft one silently spreads nothing
- [`unknown-taint`](../rules/storage.md#unknown-taint): Tolerating a built-in taint quietly opts out of what it protects: pods scheduled onto cordoned nodes, or kept forever on a node that has stopped responding
- [`spread-policy-implicit`](../rules/storage.md#spread-policy-implicit): Strict and soft differ between Pending forever and unbalanced; left unsaid, a reader cannot tell which the author meant
- [`storage-size-missing`](../rules/storage.md#storage-size-missing): The claim never binds, so every pod that mounts it sits Pending indefinitely while every object involved reports as valid
- [`shared-rwo-volume`](../rules/storage.md#shared-rwo-volume): The first replica runs and every other one stays Pending forever, which reads as a scheduling or capacity problem rather than a storage one
- [`storage-class-missing`](../rules/storage.md#storage-class-missing): The claim stays Pending with no provisioner willing to act on it, and nothing reports an error

## [Custom resources](../rules/custom-resources.md)

References inside operators' resources that point at nothing.

- [`resource-reference-missing`](../rules/custom-resources.md#resource-reference-missing): The custom resource applies cleanly and its controller finds nothing by that name at runtime: a mesh route answers 503 to every request it matches, a rollout's pods are refused their service account
- [`resource-port-missing`](../rules/custom-resources.md#resource-port-missing): Traffic or scraping aimed at a port the Service does not have goes nowhere: a mesh route fails its requests, a ServiceMonitor endpoint yields no target
- [`selector-matches-nothing`](../rules/custom-resources.md#selector-matches-nothing): A selector matching no labels selects nothing, silently: a ServiceMonitor scrapes no target and Prometheus reports no error
- [`certificate-host-mismatch`](../rules/custom-resources.md#certificate-host-mismatch): The certificate is issued and valid, and every client rejects it: the name it is presented for is not one it was issued for
- [`duplicate-producer`](../rules/custom-resources.md#duplicate-producer): One producer wins the name and the other never produces anything: cert-manager issues the first Certificate and leaves the second Ready=False (IncorrectCertificate), so the names only the second asked for are never served

## [Changes and platform rules](../rules/changes.md)

Changes the API server will refuse, and declarations your platform requires.

- [`missing-required-declaration`](../rules/changes.md#missing-required-declaration): A workload reaches production without what the platform requires of every service there: no disruption budget, so a drain takes it down entirely; no identity, so it shares the namespace's default account
- [`immutable-field-change`](../rules/changes.md#immutable-field-change): The apply is refused with `field is immutable` (a StatefulSet's claim templates or serviceName, a claim's class or access modes, a Job's pod template); the object must be deleted and recreated, which for a StatefulSet's storage means migrating data
- [`selector-change`](../rules/changes.md#selector-change): The apply is refused with `field is immutable`; a GitOps sync stays failed until someone deletes the Deployment, and deleting it takes every pod down at once

## [Checked against your cluster](../rules/cluster.md)

What only a snapshot of the cluster can tell: capacity, installed kinds, nodes, the network plugin.

- [`exceeds-cluster-capacity`](../rules/cluster.md#exceeds-cluster-capacity): Pods stay Pending with FailedScheduling: Insufficient cpu or memory
- [`kind-not-installed`](../rules/cluster.md#kind-not-installed): The apply fails with no matches for kind, or the object is stored at a version nothing serves
- [`extern-mismatch`](../rules/cluster.md#extern-mismatch): A pod fails at start (CreateContainerConfigError) or a call goes to a Service port that is not there, despite a clean compile
- [`gateway-missing`](../rules/cluster.md#gateway-missing): The HTTPRoute is accepted and serves nothing: its parentRef matches no Gateway, or the Gateway's class has no controller
- [`policy-not-enforced`](../rules/cluster.md#policy-not-enforced): Every NetworkPolicy is accepted and silently enforces nothing: traffic it was meant to block flows
- [`placement-unsatisfiable`](../rules/cluster.md#placement-unsatisfiable): Pods stay Pending with FailedScheduling: didn't match pod anti-affinity rules, or didn't match pod topology spread constraints
- [`taint-mismatch`](../rules/cluster.md#taint-mismatch): A toleration for a taint no node has does nothing; a taint on every node that the pods do not tolerate leaves them all Pending
- [`storage-class-unsupported`](../rules/cluster.md#storage-class-unsupported): The claim never binds, so its pod stays Pending with no error on any object
- [`api-version-not-served`](../rules/cluster.md#api-version-not-served): The apply fails because the version was removed in this cluster's Kubernetes, or will fail at its next upgrade

