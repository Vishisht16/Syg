# Syg in CI

`syg check` is the CI gate: it needs no network and no cluster credentials, and
it is safe on untrusted pull requests. It writes nothing.

Syg sends anonymous usage statistics, with no names, paths or code, from a CI
run as from anywhere else ([privacy](privacy.md)). They never change the
result, and a CI run waits at most 250 ms for them at exit. To turn them off,
set `SYG_TELEMETRY=off` (or `DO_NOT_TRACK=1`) in the job's environment.

## Exit codes

Every command uses the same four codes:

| Code | Meaning |
|---|---|
| 0 | Success. Warnings are allowed. |
| 1 | Check failures: errors, or warnings under `--strict`. For `syg mod tidy`, a module has changed since it was pinned. |
| 2 | Usage or configuration error: a bad flag, a missing path, an unreadable `syg.yaml`. |
| 3 | Internal compiler error. Please report it. |

Gate on 1 to block a merge; treat 2 as a broken pipeline; treat 3 as a bug in
Syg.

## Output formats

`--format` takes four values:

- `text` (the default) is for people, on stderr.
- `json` is an array of findings on stdout, described by
  [a JSON schema](schemas/diagnostics-v1.json); each position is a span, with an
  end.
- `sarif` is SARIF 2.1.0 on stdout, for code scanning. Every catalogued rule is
  described in the log with its rationale as help, so an alert explains itself
  the way `syg explain` does.
- `github` is GitHub Actions workflow commands on stdout. Each finding becomes
  an annotation on the pull request's diff, with no code-scanning setup.

`syg build` accepts `json`, `sarif` and `github` only with `-o DIR`. Without
`-o`, stdout is the manifest stream.

## GitHub annotations

The simplest integration: findings appear on the diff, errors fail the job,
and nothing needs GitHub Advanced Security.

```yaml
      - name: syg check
        run: ./syg check --format github services/
```

Errors become `::error`, warnings `::warning`, and notes on a line `::notice`.
A note about the module as a whole (no baseline, no snapshot) is a plain log
line instead, because GitHub shows only ten annotations of each level per step
and those notes would crowd out the findings. This repository's own CI runs
this step over `examples/`.

## GitHub code scanning

Results appear as alerts on the pull request, at the line of the `.syg` file
that caused them. Run `syg check` from the repository root, so the paths in the
log resolve against the checkout.

```yaml
name: syg
on: [pull_request, push]
permissions:
  contents: read
  security-events: write   # upload-sarif needs it
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install syg
        env:
          GH_TOKEN: ${{ github.token }}   # while the repository is private, a token with access to it
        run: |
          gh release download v1.0.0 --repo vishisht16/syg --pattern 'syg_1.0.0_linux_amd64.tar.gz' --pattern SHA256SUMS
          sha256sum --check --ignore-missing SHA256SUMS
          tar xzf syg_1.0.0_linux_amd64.tar.gz syg
      - name: syg check
        # Write the log even when there are findings; fail the job afterwards.
        run: ./syg check --format sarif services/ > syg.sarif || echo "SYG_EXIT=$?" >> "$GITHUB_ENV"
      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: syg.sarif
          category: syg
      - name: gate
        run: test "${SYG_EXIT:-0}" -eq 0
```

Code scanning on a private repository needs GitHub Advanced Security. Without
it, keep the `--format json` output as a build artifact, or rely on the exit
code alone.

Each result carries a `partialFingerprints` value made from its rule, file,
environment and message, not its line. An alert therefore follows its finding
when lines move above it.

## What CI cannot check

Tier-2 rules need a cluster snapshot. They are reported as skipped, never as
passed, when there is none. To run them in CI, capture a snapshot from the
cluster on a schedule (`syg snapshot -o cluster.snapshot.yaml`, read-only, with
the role in `docs/snapshot-rbac.yaml`). Commit it, and name it in `syg.yaml`'s
`snapshots:`. A snapshot older than `snapshotMaxAge` (30 days by default) warns.
