# Syg

**Syg is a typed language for the part of Kubernetes configuration that goes
wrong: how a service's objects refer to each other.** You declare a service
once; Syg derives its Deployment, Service, disruption budget, autoscaler,
routes, identity and network policy, and checks them as one graph before
anything reaches a cluster.

```syg
module shop

service api {
  image "registry.example.com/shop-api:1.4.2"
  replicas 3
  port http 8080
  resources { cpu 250m, memory 256Mi }
  health {
    live GET :http /livez
    ready GET :http /readyz
  }
  disruption { maxUnavailable 1, evictUnhealthy true }
  internal :http
}
```

That is a Deployment, a Service and a PodDisruptionBudget, with every selector,
label and port reference derived from the one declaration, and it checks
clean.

## What it gives you

**Mistakes you cannot write.** A Service whose selector matches no pod, a route
to a port that does not exist, a RoleBinding to a Role that is not there, an
autoscaler aimed at the wrong Deployment: Syg has no field in which to write
them. Selectors, references and bindings are derived from names, and a name
that does not resolve is an error at the line you wrote.

**Checks that matter, which linters do not ship.** In a study of 48 real
configurations, two relationship mistakes stood out for how often they occur:

- **`single-replica-budget`**: a disruption budget on a single replica. With
  `minAvailable 1` it blocks every node drain and cluster upgrade until someone
  forces it; with `maxUnavailable 1` it protects nothing.
- **`shared-probe-endpoint`**: liveness and readiness on the same endpoint.
  When a dependency slows down, every pod fails liveness at once, and the
  kubelet restarts the whole service when it most needs to stay up.

Every finding names the line, says what will happen in production, and how to
fix it. Change `replicas 3` to `replicas 1` above:

```console
$ syg check shop
warning[single-replica-budget]: disruption budget on api, which runs a single replica
  --> shop/shop.syg:12:3
     |
  12 |   disruption { maxUnavailable 1, evictUnhealthy true }
     |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  --> shop/shop.syg:5:3
    |
  5 |   replicas 1
    |   ^^^^^^^^^^ one replica here
   = consequence: with one replica there is no non-disruptive eviction: `minAvailable 1` blocks every drain of the node it lands on, and `maxUnavailable 1` permits the eviction the budget was written to prevent, so the budget either stops all maintenance or does nothing
   = help: run more than one replica if this workload needs to survive node maintenance; if a single replica is correct, remove the budget and accept the restart
   = explain: syg explain single-replica-budget  (CHK-PDB-005)
```

**It fits what you have.** `syg build` writes plain manifests, a Kustomize
base with overlays, or Argo CD Applications. Syg never applies anything: your
pipeline does, as it does today. Custom resources (cert-manager, Istio, the
Prometheus Operator, ...) are written as YAML inside a module and checked
through declared relations.

## Install

```console
$ brew install vishisht16/tap/syg                       # macOS, Linux
$ curl -fsSL https://syg.vishisht.tech/install.sh | sh  # macOS, Linux
> scoop bucket add syg https://github.com/vishisht16/syg; scoop install syg   # Windows
```

In GitHub Actions, `uses: vishisht16/setup-syg@v1`; in other CI, the install
script, or the image `ghcr.io/vishisht16/syg` where a step runs an image's own
command. Every download is checksummed, signed, attested and comes with an
SBOM: [security](https://syg.vishisht.tech/security.html) says how to verify
them, and [install](https://syg.vishisht.tech/install.html) covers `.deb` and
`.rpm` packages, shell completions and downloading by hand.

A binary downloaded with a browser on macOS is quarantined; clear it with
`xattr -d com.apple.quarantine ./syg`. Homebrew and the install script need
nothing.

## Learn it

- [Quickstart](https://syg.vishisht.tech/quickstart.html): a service from
  `syg init` to a cluster.
- [What Syg catches](https://syg.vishisht.tech/rules/): every check, by what
  goes wrong.
- [Language](https://syg.vishisht.tech/language.html) and
  [CLI](https://syg.vishisht.tech/cli.html) reference.
- [Migrating](https://syg.vishisht.tech/migrate-helm.html) from Helm,
  Kustomize or plain YAML.

The same documentation is in [`docs/`](docs/README.md), and `syg explain NAME`
explains any finding offline.

## What Syg will not do

These are out of scope by design, each to prevent a specific failure:

1. **Deploying, applying, or mutating cluster state.** Syg is a compiler; delivery stays with the existing pipeline. *(Prevents: the adoption wall of "replace your GitOps".)*
2. **Runtime or admission-time enforcement.** No webhook, no operator, no agent. *(Prevents: reimplementing the API server.)*
3. **A general-purpose configuration or programming language.** No user functions, loops, or arbitrary expressions. *(Prevents: losing whole-graph analyzability, which is the entire value proposition.)*
4. **Claiming undecidable properties.** No probe-timing, HPA-metric-fitness, eviction-risk, or secret-content judgments.
5. **Unbounded whole-graph verification.** All claims are scoped to a declared closed world.
6. **Simulating controllers or CRD semantics.** CRD support is declared-relationship-based only.
7. **Cluster provisioning or infrastructure (Terraform's domain).** Syg describes workloads, not clusters or cloud resources.
8. **Multi-cluster scheduling or placement decisions.**
9. **Being first-of-its-kind.** Several checks exist in KubeLinter and Polaris today; Syg's claim is prevention-by-construction, source-located diagnostics, graph-level reasoning and explanation, not novelty.
10. **Secret value management.** Syg declares keys and consumption shape; values belong to a secrets manager.
11. **Displacing Helm/Kustomize as packaging formats.** Syg emits into them.

## Licence, privacy, security

Syg is distributed under the [Syg EULA](EULA.md). The code in this
repository that builds, publishes and installs it is under the MIT licence
([LICENSE](LICENSE)). Syg sends anonymous usage statistics, with no names,
paths or code; [PRIVACY.md](PRIVACY.md) says exactly what, and
`SYG_TELEMETRY=off` turns them off. To report a vulnerability, see
[SECURITY.md](SECURITY.md); for anything else, [SUPPORT.md](SUPPORT.md).

The source is not public. This repository holds the releases, the installers
and the [relay](relay/) that receives the usage statistics. Every release here
is built and tested by this repository's own
[release workflow](.github/workflows/release.yml).

Kubernetes is a registered trademark of The Linux Foundation. Syg is not
affiliated with or endorsed by it.
