# Compatibility

Syg follows [semantic versioning](https://semver.org/). This page says which
surfaces that promise covers, which Kubernetes versions Syg supports, and how a
change is recorded.

## What a version promises

Within one major version (1.x), a program that compiled keeps compiling, and
builds to the same objects. In detail, these surfaces do not change:

| Surface | Where it is described |
|---|---|
| **The label and selector scheme.** Every selector Syg derives, and the labels it matches. A change would orphan every running workload's pods from their Services, budgets and policies, so it is the most critical surface of all. | the [derivation map](derivation-map.md) |
| **Generated output for an unchanged program.** The objects, their names, their fields and their order. | |
| **The grammar.** Every valid program stays valid. New constructs may be added. | the grammar |
| **Rule codes and names.** A code (`CHK-PDB-001`) and a readable name (`budget-blocks-eviction`) always name the same check, and neither is ever reused, even after its rule is retired. | `syg rules` |
| **Exit codes.** 0 success, 1 findings that fail the build, 2 could not do what was asked (a usage or configuration mistake, or a file it cannot read or write), 3 an internal error. `syg lsp` follows the Language Server Protocol: 0 after shutdown and exit, 1 without shutdown, 2 for a malformed frame. | `syg help`, [CI](ci.md) |
| **Machine-readable output.** The `--format json` schema, SARIF's fingerprints (`syg/v1`), and the provenance files, `provenance/ENV.json` (schema version 2). Fields may be added; none is renamed or removed. | the [JSON schema](schemas/diagnostics-v1.json), [CI](ci.md) |

Syg's own tests hold each of these: a pinned set of projects is built on every
change and compared, output and findings, with what 1.0.0 produced.

These may change in any release, because they are written for people:

- the wording of a diagnostic, its `help:` line, and its consequence;
- `syg explain` and the rationales;
- the text formats of `syg graph`, `syg why` and `--print-world`.

### New rules

A new rule can fail a build that passed before. So a new rule that would report
an **error** arrives at **warning** severity, and becomes an error no earlier
than the next minor version. A rule's severity can also be set per project in
`syg.yaml`. New warning and note rules arrive in any minor
version: they never change an exit code unless you build with `--strict`.

### Deprecation

A construct to be removed is deprecated first. Its use is a warning that names
the replacement for at least one minor version. It is removed only in a new
major version.

## Kubernetes versions

Syg validates against the Kubernetes **1.32** API schema; `syg version` prints it. Syg emits nothing newer than that schema, and
uses no field that 1.30 does not serve.

**Supported: 1.30 to 1.33.** Each minor in that range is tested, not inferred:

| Kubernetes | Tested on | What runs |
|---|---|---|
| 1.30 | kind, node v1.30.13 | a server-side dry run of every example and test program, reconciliation to Ready, probes, snapshots, and the suite that reproduces each checked mistake on the cluster |
| 1.32 | kind, node v1.32.5 | the same, plus network policy enforcement and Argo CD syncs |
| 1.32 | k3s v1.32.12 | all of the above, with cert-manager, Istio and the Prometheus Operator running |
| 1.33 | kind, node v1.33.1 | as 1.30 |

Outside the range Syg may well work, but no claim is made. With a cluster
snapshot, `api-version-not-served` (CHK-T2-VER-001) reports the API versions a
specific cluster does not serve.

## Recording a change

A change to any surface above is either a bug, and fixed, or intended, and
then a compatibility change: it follows the rules above, and is recorded here.

## Changes

| Version | Change | Why |
|---|---|---|
| 1.0.0 | The first release: every surface above is fixed from here. | |
