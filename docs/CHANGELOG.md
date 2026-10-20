# Changelog

Every release, newest first. Versions follow [semantic versioning](https://semver.org/);
what each part of a version promises is on the
[compatibility](https://syg.vishisht.tech/compatibility.html) page.

## 1.0.0

The first release.

**The language.** A typed language for a Kubernetes service's deployment
surface:

- **Workloads:** `service`, `stateful` and `job` (with a schedule, a CronJob),
  with images, commands, ports, resources, probes, configuration, secrets,
  storage, init and sidecar containers, scaling, disruption budgets and
  rollouts.
- **Traffic:** in-cluster Services (`internal`), and routes from outside
  (`expose`), as Gateway API HTTPRoutes or Ingresses.
- **Access:** identities with their grants, and network policy, with
  `needs service` for dependencies.
- **Placement:** `spread`, `avoid` and `tolerate`.
- **Composition:** modules and imports pinned in `syg.lock`, golden-path
  profiles, and environments.
- **What Syg does not model:** `extern` declarations for what other teams own,
  `raw` objects for anything else, and `relate` declarations, so that custom
  resources are checked like built-in ones. Relation libraries ship for
  cert-manager, Istio, the Prometheus Operator, Argo Rollouts, External Secrets
  and the Gateway API.

**The checks.**

- **Prevented:** 18 classes of mistake the language cannot express, among them
  selectors that match nothing, references to things that do not exist, and
  bindings to the wrong Role.
- **Checked:** 56 more, each with a readable name (`single-replica-budget`), a
  stable code (`CHK-PDB-005`), the line it is about, what will happen in
  production, and how to fix it.
- **Against a cluster:** 9 of the 56 need a snapshot of a cluster, which
  `syg snapshot` captures and the module commits.
- **Explained:** `syg explain NAME` explains each one.

**The tools.**

- **Commands:** `syg check` and `syg build`, the latter to plain manifests, a
  Kustomize base with overlays, or Argo CD Applications.
- **Findings in CI:** as text, JSON, SARIF or GitHub annotations.
- **Inspecting:** `syg why`, where every generated field came from, and
  `syg graph`.
- **Writing:** `syg fmt`, `syg init` and `syg mod`.
- **The editor:** `syg lsp`, with diagnostics as you type, hover, completion,
  go-to-definition and quick fixes.

**Safe on code nobody has reviewed.** `syg check` can run on an untrusted pull
request, with no credentials and no network:

- it reads only regular files, inside the repository that holds the module,
  so a symbolic link or an import cannot make it read, or print, a file of the
  machine running it;
- every input is bounded (a file at 8 MiB, a module at 64 MiB, a string at
  1.5 MiB), and what it prints grows with the input, never faster;
- a control character in a file cannot rewrite the terminal or the log a
  finding is printed to.

**Distribution.**

- **Binaries:** static, for Linux, macOS and Windows on amd64 and arm64, with
  checksums, signatures and a software bill of materials.
- **Kubernetes:** supported versions are 1.30 to 1.33.

**Usage statistics.** Anonymous usage statistics, with no names, paths or
code, help decide what to improve. They never change a result or delay a
command, and `SYG_TELEMETRY=off` turns them off; see
[privacy](https://syg.vishisht.tech/privacy.html).
