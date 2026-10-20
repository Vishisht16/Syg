# Derivation map

For every construct of the language, the Kubernetes fields it produces. Each
row is a contract: Syg's tests pin the output of every one.

The most important rows are the **derived** ones (marked *derived*): one Syg
value produces two or more Kubernetes fields, which therefore cannot disagree.
That is how Syg prevents a class of mistake rather than checking for it; see
[derivation](derivation.md).

## Identity (derived: the core prevention)

| Syg | Derives (Kubernetes) |
|---|---|
| `service NAME` / `stateful NAME` / `job NAME` (*derived*) | the controller itself: a Deployment, a StatefulSet, or a Job (a CronJob when a `schedule` is present). Choosing the controller is choosing the **word**, with the meaning explicit rather than buried in a `kind:` field |
| `service NAME` | Deployment `metadata.name`; the canonical label set (`app.kubernetes.io/{name,instance,managed-by,part-of}`) on Deployment `metadata.labels` and pod-template `metadata.labels`; **and the immutable selector `{name,instance}` used byte-identically at** Deployment `spec.selector.matchLabels`, Service `spec.selector`, and PDB `spec.selector`: *all from one value* |

## `service` items

| Syg | Derives (Kubernetes) |
|---|---|
| `image "REF"` | container `image`; parsed structurally (registry/repo/tag/digest), which is what lets CHK-IMG-001 ask about the tag component rather than substring-match |
| `replicas N` | Deployment `spec.replicas`, **except under `scale`**: an HPA owns the count, so `spec.replicas` is not written (every apply would reset it). A `replicas` that differs from the autoscaler's floor is reported as not emitted |
| `port NAME N [PROTO]` (*derived*) | container `ports[].{name,containerPort,protocol}`; and, when exposed, the Service port's `name`/`targetPort` (by name) |
| `resources { cpu Q, memory Q }` | container `resources.requests.{cpu,memory}` (normalized quantities) |
| `resources { limits { cpu Q, memory Q } }` | container `resources.limits.{cpu,memory}` |
| `health { live \| ready \| startup <handler> <opts> }` | container `livenessProbe` / `readinessProbe` / `startupProbe`; `GET :p /path`→`httpGet{path,port:p}`, `TCP :p`→`tcpSocket{port:p}`, `EXEC "c"`→`exec{command:["/bin/sh","-c","c"]}`, `EXEC "a" "b" ...`→`exec{command:["a","b",...]}` (argv, no shell); opts `after`→`initialDelaySeconds`, `every`→`periodSeconds`, `timeout`→`timeoutSeconds`, `failures`→`failureThreshold` |
| `needs config C` (*derived, checked*) | container `envFrom[].configMapRef.name = C`. C is resolved against a declaration at compile time, so a missing ConfigMap is a compile error (CHK-CFG-001), not a pod stuck in `CreateContainerConfigError` |
| `needs config C as KEY` (*derived, checked*) | container `env[]{name:KEY, valueFrom.configMapKeyRef{name:C,key:KEY}}` |
| `needs config C at PATH` (*derived, checked*) | pod `volumes[]{name:config-C, configMap.name:C}` + container `volumeMounts[]{name:config-C, mountPath:PATH}` |
| `needs secret S [as KEY \| at PATH]` (*derived, checked*) | same shapes as config with `secretRef` / `secretKeyRef` / `secret.secretName` |
| `needs service NAME [:PORT]` (*checked*) | **nothing emitted on its own**: the depends-on edge to a workload of the module or an `extern service`. A policy isolating this workload's egress gets a *derived* rule allowing it, and the server's ingress must admit the client, which CHK-NP-002 checks. The port is the server's |
| `env NAME = "V"` | container `env[]{name:NAME, value:V}` |
| `internal :p` (*derived*) | a ClusterIP `Service` named after the workload, whose `spec.selector` is the derived selector and whose `ports[]` targets the named port `p`. Only ClusterIP is modelled: traffic from outside goes through `expose` (a route); a NodePort or LoadBalancer Service is written `raw`, and a `relate v1 Service { field spec.selector selects workload }` checks its selector (CHK-REL-003) |
| *(the main container)* | named after the workload; `init` and `sidecar` containers by their own names. A migrated Deployment's container name therefore changes, which matters to `kubectl logs -c` and to nothing that selects |
| `disruption { minAvailable N \| maxUnavailable N [evictUnhealthy B] }` (*derived, checked*) | a `PodDisruptionBudget` with the derived `spec.selector` and the given budget as `spec.minAvailable` / `spec.maxUnavailable`; `evictUnhealthy true` → `spec.unhealthyPodEvictionPolicy: AlwaysAllow`, `false` → `IfHealthyBudget`, unset → not written (CHK-PDB-004 asks for the choice); checked by CHK-PDB-001 |
| `resources { nvidia.com/gpu N }` | container `resources.requests`/`limits` under the qualified name; integer-only, since a device cannot be divided |
| `scratch NAME at "PATH" { ... }` (*derived*) | pod `volumes[]{name:NAME, emptyDir{medium,sizeLimit}}` **and** container `volumeMounts[]{name:NAME, mountPath:PATH}`: *one declared name on both sides*, so the pair cannot disagree |
| `init NAME { ... }` | pod `spec.initContainers[]`, in declared order; references inside resolve exactly as on the app container |
| `sidecar NAME { ... }` | an additional entry in pod `spec.containers[]`, after the app container |
| `mount NAME at "PATH"` (inside init/sidecar) (*derived, checked*) | `volumeMounts[]` referring to a `scratch` volume declared on the enclosing workload |
| `expose :p at "HOST" [path P] [via GATEWAY] [tls S]` (*derived*) | a ClusterIP `Service` (as `internal` would) **and** an `HTTPRoute` (default) or `Ingress` (`--target-traffic=ingress`) whose backend and port are the resolved Service and port: *no backend name is written*. The HTTPRoute's `parentRefs` is the extern gateway `via` names, or the module's only one, with its namespace and listener as `namespace`/`sectionName`; with no extern gateway it is `--gateway` (default `default`) in the route's own namespace |
| `identity NAME` (*derived, checked*) | pod `spec.serviceAccountName`, read from the resolved ServiceAccount node |
| *no `identity` on a service* (*derived*) | pod `spec.automountServiceAccountToken: false`, so an unused API credential is never left in the container filesystem (CHK-RBAC-006) |
| `storage NAME at "PATH" { ... }` on a `stateful` (*derived*) | a StatefulSet `volumeClaimTemplates[]` entry **and** the container's `volumeMounts[]`, both named from the one declaration. Per-replica follows from the KIND, not from anything written here, which is what makes CHK-STO-003 prevented |
| `storage NAME at "PATH" { ... }` on a `service` (*derived*) | a standalone `PersistentVolumeClaim` **and** the matching `volumeMounts[]` entry. Shared across replicas, which is safe at one replica and is what CHK-STO-002 examines beyond that |
| `stateful NAME` (any) (*derived*) | a headless `Service` (`clusterIP: None`) carrying the same derived selector, **and** the StatefulSet's `spec.serviceName` pointing at it: the stable per-ordinal DNS identity that makes a StatefulSet worth using |
| `schedule "CRON"` | CronJob `spec.schedule`; its presence is also what selects CronJob over Job |
| `parallelism N` / `completions N` / `retries N` / `deadline D` | Job `spec.parallelism` / `completions` / `backoffLimit` / `activeDeadlineSeconds` |
| *(any `job`)* (*derived*) | pod `restartPolicy: OnFailure`. `Always` is invalid for a Job and contradicts the kind; retries are the Job controller's business, expressed as `retries` |
| `scale on METRIC at TARGET between MIN and MAX` (*derived*) | a `HorizontalPodAutoscaler` whose `spec.scaleTargetRef` kind and name are read off the workload this is declared inside; there is no syntax for a `scaleTargetRef` (CHK-HPA-001). `at 70%` becomes an `averageUtilization` target, which is a percentage **of the request**, which is why CHK-HPA-002 exists |
| *(a `scale` anywhere)* | changes `EffectiveMinReplicas` for the workload to the HPA floor rather than the declared `replicas`, which is the number CHK-PDB-002 and CHK-HPA-005 both judge a disruption budget against |
| `command "..." ...` / `args "..." ...` | the main container's `command` / `args`, verbatim, one string per argv element (no shell is added) |
| `rollout { strategy rolling, maxUnavailable N, maxSurge N }` | `spec.strategy` (`RollingUpdate` with the two bounds, or `Recreate`). With no block nothing is written and Kubernetes' default (25% / 25%) applies, which is also what CHK-PDB-003 judges against |
| `security { ... }` (*derived*) | a `securityContext` on **every** container, init and sidecars included, with any per-container override layered on top; `fsGroup` becomes the pod's `securityContext.fsGroup`. A posture written once cannot be forgotten on the sidecar |
| `labels { KEY = "V", ... }` | `metadata.labels` on the workload and its pod template (`spec.template.metadata.labels`), and on the Services, PodDisruptionBudget, HorizontalPodAutoscaler, HTTPRoute and PersistentVolumeClaims it owns, beside the derived labels. **Never in a selector**: `spec.selector`, the Service selector and the budget's selector stay the derived pair. The derived keys `app.kubernetes.io/{name,instance,managed-by,part-of}` and `syg.vishisht.tech/*` cannot be written. Merged per key with a profile's (a lock is per key, `labels.KEY`); an environment may set or add values |
| `annotations { KEY = "V", ... }` | `metadata.annotations` on the workload and `spec.template.metadata.annotations`, beside Syg's `syg.vishisht.tech/*` (which cannot be written). Merged per key like `labels` |
| `qos guaranteed \| burstable \| besteffort` | nothing emitted: the intended QoS class, compared with the class derived from every container's requests and limits (CHK-RES-004). A profile can lock it (`locked qos guaranteed`) |
| `spread { across KEY, ... [skew N] [strict\|soft] }` | one `spec.template.spec.topologySpreadConstraints` entry per key: `topologyKey`, `maxSkew` (1 by default), `whenUnsatisfiable` (`DoNotSchedule` when strict, `ScheduleAnyway` when soft or unsaid), a *derived* `labelSelector` (the workload's selector), and on a Deployment `matchLabelKeys: [pod-template-hash]`, so a rollout's old and new pods are spread separately. Keys are well-known or declared with `extern topology` (CHK-SCH-002) |
| `avoid { across KEY, ... [with W, ...] [strict\|soft] }` | `spec.template.spec.affinity.podAntiAffinity` terms, one per key and target: `requiredDuringSchedulingIgnoredDuringExecution` when strict, `preferredDuringSchedulingIgnoredDuringExecution` (weight 100) otherwise, each with the *derived* selector of the workload itself or of each `with` workload, a resolved reference (CHK-SCH-001) |
| `tolerate KEY[=VALUE][:EFFECT] [for D]` | a `spec.template.spec.tolerations` entry: `operator: Equal` and `value` with a value, `Exists` without; `effect` (every effect when unsaid); `tolerationSeconds` from `for`, NoExecute only (CHK-SCH-003) |
| `policy NAME` (on a workload) (*derived, checked*) | a `NetworkPolicy` named after the workload. `spec.podSelector.matchLabels` is *derived*, byte-identical to the workload's selector (CHK-SEL-004), and `spec.policyTypes` is always written, listing exactly the directions the policy declares; left out, the API server would default it to `Ingress`, so an egress-only policy would cut ingress. Not emitted when the policy declares neither direction |
| `policy NAME { ingress { PEER [:PORT], ... } egress { ... } }` | for each workload that links it, `spec.ingress[]` / `spec.egress[]` rules, one per peer: a workload peer's `podSelector` is *derived* from its selector; an `extern service` with `namespace "NS"` is a `namespaceSelector` on `kubernetes.io/metadata.name: NS`, and without one a `podSelector: {}` (every pod of the namespace, CHK-NP-003 flags it); `apiserver` is a ports-only egress rule on TCP 443 and 6443, since a policy sees the translated address. Ports are numbers, the subject's in ingress and the peer's in egress. *Derived* rules follow the written ones: each exposed port, open to any source (the gateway's pods are not in the closed world); DNS (UDP and TCP 53, any destination); and each `needs service` dependency not already allowed. Peers resolve, never select (CHK-NP-001). No namespace-wide default-deny is ever emitted |
| `extern host NAME { address "...", port ... }` | **nothing emitted**: an endpoint outside the cluster. As a policy peer, an IP or CIDR address is an `ipBlock`; as a `needs service` dependency of a workload whose egress is isolated, an `ipBlock` rule, or, for a host named by DNS, its port to any destination |
| `extern resource "GROUP/VERSION/Kind" NAME {}` | **nothing emitted**: a custom object someone else owns, in the closed world by name; a snapshot checks its kind is served (CHK-T2-CRD-001) |
| `extern topology KEY { domains N }` | nothing emitted: declares a node label key spreads and avoids may use, and how many domains it has, for CHK-SCH-001's arithmetic (checked against a snapshot by CHK-T2-SCH-001) |

## Top-level declarations

| Syg | Derives (Kubernetes) |
|---|---|
| `config NAME { key K = "V" }` | a `ConfigMap` named NAME with `data[K]=V` (owned), emitted only when some container consumes it, since reporting dead configuration (CHK-CFG-006) and then creating it would be incoherent |
| `secret NAME { key K }` | **no object emitted**: keys only. Values come from a secrets manager, and only reference wiring is produced |
| `identity NAME { may VERBS on RESOURCES }` (*derived, the whole chain*) | a `ServiceAccount`, a `Role`, **and** the `RoleBinding` that connects them: the binding's `subjects[].name` is the emitted ServiceAccount and its `roleRef.name` is the emitted Role, both attached as resolved pointers. A Role grants nothing until it is bound, so deriving the binding rather than asking for it is what makes the forgotten RoleBinding unrepresentable (CHK-RBAC-001, CHK-RBAC-002). Each rule's `apiGroups` is *derived* from the resource (`deployments` → `apps`; `certificates.cert-manager.io` → `cert-manager.io`), one rule per group, because a resource granted in the wrong group grants nothing |
| `may ... across cluster` (*derived*) | the same chain as a `ClusterRole` + `ClusterRoleBinding`, named `MODULE-NAME` so it cannot collide in the cluster-wide name space. Without the opt-in the grant is namespaced, so widening the blast radius is always written down (CHK-RBAC-004) |
| `extern secret \| config \| service \| identity \| storageclass \| gateway NAME { ... }` | **no object emitted**: a typed, trusted-unverified symbol used for reference resolution. An extern service may say `namespace "NS"`, where its pods run, for a policy peer. A StorageClass is cluster infrastructure Syg never owns; declaring it extern turns an invisible environmental assumption into a reviewable line (CHK-STO-004). A gateway (`extern gateway NAME { namespace "infra", listener https }`) is a platform Gateway that routes attach to; a snapshot verifies externs against the cluster (CHK-T2-EXT-001, CHK-T2-NET-001) |
| `relate APIVERSION KIND { field PATH RELATION }` | **no object emitted**: a statement about a custom resource kind's fields. Each value it reaches in a `raw` object of that kind is a `relates` edge checked by CHK-REL-001..005. A value at a `produces secret\|config` field becomes a symbol `needs` resolves; it is the producer's to create, so Syg emits **no** Secret or ConfigMap for it, and a `needs secret` on it derives the same `secretRef` / `secretKeyRef` / volume as for any secret. A config, secret or identity a relation references counts as consumed, so a ConfigMap or ServiceAccount it names is emitted. `references GROUP/VERSION/Kind` resolves to a raw object or an `extern resource` of that kind and emits nothing |

## Output targets

| `syg build --target` | Layout |
|---|---|
| `plain` | one environment's manifests (`--env`), flat |
| `kustomize` | `base/` (the base declarations, no namespace) and `overlays/<env>/kustomization.yaml`, holding only JSON patches, one per object that differs. `kustomize build overlays/<env>` equals `syg build --env <env>` (checked against kustomize in Syg's CI) |
| `argo` | `envs/<env>/` (that environment's manifests) and `apps/<env>.yaml`, an Argo CD `Application` with `destination.namespace` set to the environment's namespace (checked against a real Argo CD in Syg's CI) |

## Profiles

| Syg | Derives (Kubernetes) |
|---|---|
| `profile NAME(params) { ... }` | **nothing emitted**: a template, expanded into each workload that `use`s it. `internal profile` is not visible to importers |
| `use alias.PROFILE(args)` (*expanded*) | nothing of its own. The workload is as if its items had been written by hand, with the arguments substituted, so its manifests are byte-identical to that hand-written workload's |
| `locked FIELD` | the same field as written, plus a guarantee: no workload, container or environment on the golden path can emit anything else (CHK-SEC-001 for security fields) |
| (provenance) | the provenance file (`provenance/ENV.json`) records `profile` and `profileVersion` (the `syg.lock` hash) for every resource the profiled workload owns |

## Environments

| Syg | Derives (Kubernetes) |
|---|---|
| `environment NAME { ... }` | one complete build per environment, compiled and checked as its own graph. `syg build --env NAME` emits it |
| `namespace "NS"` (or the default `MODULE-NAME`) (*derived*) | `metadata.namespace` on every namespaced object of that build, and the `subjects[].namespace` of every ClusterRoleBinding. Never written on cluster-scoped kinds |
| `WORKLOAD { replicas, image tag, image digest, resources, scale, disruption, rollout, expose, env }` | the same objects as the base, with those values changed: the diff between two environments is confined to overridden fields. `image tag` keeps the repository; on a digest-pinned image it is refused, because it would drop the pin, and `image digest "sha256:..."` changes the pinned image. On an autoscaled workload, `replicas` is refused in favour of `scale between MIN and MAX` |
| `config NAME { key K = "V" }` | that ConfigMap's `data[K]` in this environment |

## The escape hatch

| Syg | Derives (Kubernetes) |
|---|---|
| `raw "G/V/Kind" NAME { yaml """...""" }` | the YAML, **verbatim**, with `apiVersion`, `kind` and `metadata.name` from the header, and the provenance annotations plus `syg.vishisht.tech/raw: "true"`. Nothing is derived from it, and nothing derived points at it: it is an opaque node, and the checks it could affect say so (`info[coverage]`) |

## Modules and imports

| Syg | Derives (Kubernetes) |
|---|---|
| `import "PATH" [as ALIAS]` | **nothing emitted**. The imported module's declarations become resolvable as `ALIAS.name`, and its resources are emitted only by its own build. A module is the unit deployed into one namespace |
| `import "syg.vishisht.tech/relate/NAME"` | **nothing emitted**: a module of the bundled relation library, read from the binary unless `vendor/syg.vishisht.tech/relate/NAME` exists. Its relate declarations apply to the importer's raw objects and its vendored CRD schemas validate them; it is pinned in `syg.lock` like any import |
| `class ALIAS.NAME` (in `storage`) (*derived*) | `spec.storageClassName: NAME`, the class's name in the cluster. A StorageClass is cluster-scoped, so it is the one kind of name that may cross a module boundary |
| `needs config ALIAS.NAME`, `identity ALIAS.NAME` | **rejected** (CHK-CFG-004). A `configMapRef`, `secretKeyRef` or `serviceAccountName` carries no namespace and resolves in the pod's own, so a reference into another module's namespace would never resolve |
| `syg.lock` | nothing in the manifests. It pins each imported module's content hash, so that two checkouts emit identical output |

## Provenance (every emitted object)

| | Kubernetes |
|---|---|
| *(always)* | `metadata.annotations` `syg.vishisht.tech/module`, `syg.vishisht.tech/service`, `syg.vishisht.tech/compiler-version`, and `syg.vishisht.tech/source`, the declaration's file relative to the module (the line is in the provenance file, whose `fields` give every field's span and origin) |
| *(always)* | `metadata.labels` on **every** object: a workload's own objects (its Services, budget, autoscaler, routes, claims) carry its selector labels plus `managed-by`/`part-of`; module-level objects (ConfigMaps, the RBAC chain) carry `managed-by`/`part-of`. Label-selecting tools such as a ServiceMonitor find them alongside the workload |
| *(always)* | the provenance file beside the manifests, `provenance/ENV.json` (`provenance/base.json` for a module without environments; the layouts write one per environment), in a subdirectory so that `kubectl apply -f DIR` applies only objects: each resource mapped to its declaration (file, line, column) plus every derived value and the reason behind it. `syg why` reads it. |
