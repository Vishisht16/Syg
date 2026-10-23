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
  profiles, and environments, each named by a DNS label, since the name
  becomes a directory, part of a namespace and an Argo CD Application's name.
- **What Syg does not model:** `extern` declarations for what other teams own,
  `raw` objects for anything else, and `relate` declarations, so that custom
  resources are checked like built-in ones. Relation libraries ship for
  cert-manager, Istio, the Prometheus Operator, Argo Rollouts, External Secrets
  and the Gateway API.

**The checks.**

- **Prevented:** 18 classes of mistake the language cannot express, among them
  selectors that match nothing, references to things that do not exist, and
  bindings to the wrong Role.
- **Checked:** 58 more, each with a readable name (`single-replica-budget`), a
  stable code (`CHK-PDB-005`), the line it is about, what will happen in
  production, and how to fix it.
- **Against a cluster:** 9 of the 58 need a snapshot of a cluster, which
  `syg snapshot` captures and the module commits.
- **Pod Security baseline:** a container's added capabilities and seccomp
  profile are checked against it, as written in the language or raw.
- **Raw objects:** RBAC written raw is checked for wildcards and bindings to
  cluster-admin, and a raw pod spec for what reaches into its node and what it
  asks of the kernel (capabilities, seccomp, AppArmor, SELinux, sysctls),
  whether a built-in kind's or a custom resource's, such as an Argo Rollout's
  template; any other raw object gets a note that no rule judges what it does.
  A raw object's name is checked by its kind's rule, as the API server checks
  it.
- **Explained:** `syg explain NAME` explains each one.

**The tools.**

- **Commands:** `syg check` and `syg build`, the latter to plain manifests, a
  Kustomize base with overlays, or Argo CD Applications. `syg build -o`
  replaces its directory whole or not at all, and never one another build
  wrote while it ran.
- **Findings in CI:** as text, JSON, SARIF or GitHub annotations. The JSON
  is one object that names its schema (`$schema`) beside the `findings`; the
  release candidates printed the bare array.
- **Inspecting:** `syg why`, where every generated field came from, and
  `syg graph`.
- **Writing:** `syg fmt`, `syg init` and `syg mod`.
- **Custom resources:** `syg schema vendor` copies CRD schemas from a file, an
  https URL or a snapshot into the module's `schemas/`, and nowhere else.
- **The editor:** `syg lsp`, with diagnostics as you type, hover, completion,
  go-to-definition and quick fixes.
- **The same on every platform:** a module that checks on macOS or Windows
  checks on Linux, since an import spelled otherwise than its directory is an
  error everywhere; `syg fmt` keeps a file's CRLF line endings, as Git for
  Windows checks files out; and a Windows console shows colour, not escape
  codes.

**Safe on code nobody has reviewed.** `syg check` can run on an untrusted pull
request, with no credentials and no network:

- it reads only regular files, inside the repository that holds the module,
  so a symbolic link, a Windows junction or an import cannot make it read, or
  print, a file of the machine running it, and a link the repository holds
  cannot lead a path you name, or a file Syg writes, out of it;
- every input is bounded (a file at 8 MiB, a module at 64 MiB, a string at
  1.5 MiB), and so is the work a module makes (200,000 items, profiles
  expanded, for the base and each environment): the largest checks measured
  take about 0.5 GB of memory, the largest builds about 1.3 GB, and what it
  prints grows with the input, never faster;
- a control character in a file, or in a file's name, cannot rewrite the
  terminal or the log a finding is printed to, nor forge a CI annotation.

**Distribution.**

- **Binaries:** static, for Linux, macOS and Windows on amd64 and arm64, by
  the install scripts, Homebrew, Scoop, `.deb` and `.rpm` packages, and the
  GitHub Action `vishisht16/setup-syg`.
- **A container image,** `ghcr.io/vishisht16/syg`, for amd64 and arm64. It
  holds the binary alone, and runs as a user of its own, not root.
- **Checked before it is published:** every file has a checksum and a
  keyless cosign signature, and every archive, package and image has
  provenance at SLSA v1.0 Build Level 3. A signed statement names the source
  commit each was built from. Every archive comes with software bills of
  materials, SPDX and CycloneDX; the image carries its own.
- **Shell completions** for bash, zsh, fish and PowerShell (`syg completion`),
  and a man page, which Homebrew and the Linux packages install.
- **Kubernetes:** supported versions are 1.30 to 1.33.

**Usage statistics.** Anonymous usage statistics, with no names, paths or
code, help decide what to improve. They never change a result or delay a
command, and `SYG_TELEMETRY=off` turns them off; see
[privacy](https://syg.vishisht.tech/privacy.html).
