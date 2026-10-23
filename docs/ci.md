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
| 2 | Usage or configuration error: a bad flag, a missing path, an unreadable `syg.yaml`, a snapshot or baseline Syg cannot read, a path through a link out of the repository. |
| 3 | Internal compiler error. Please report it. |

Gate on 1 to block a merge; treat 2 as a broken pipeline; treat 3 as a bug in
Syg. A pipe that closes early (`syg check ... | head`) ends Syg by SIGPIPE,
which a shell reports as 141, as for any Unix tool.

## Output formats

`--format` takes four values:

- `text` (the default) is for people, on stderr.
- `json` is one object on stdout: `$schema`, the URL of
  [its JSON schema](schemas/diagnostics-v1.json), and `findings`, the findings in
  order (`jq '.findings[]'`). Each position is a span, with an end.
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
      - uses: vishisht16/setup-syg@v1
      - run: syg check --format github services/
```

`setup-syg` installs Syg and puts it on `PATH`, after checking the download's
checksum and its provenance. Its `version` input pins a release.

Errors become `::error`, warnings `::warning`, and notes on a line `::notice`.
A note about the module as a whole (no baseline, no snapshot) is a plain log
line instead, because GitHub shows only ten annotations of each level per step
and those notes would crowd out the findings.

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
      - uses: actions/checkout@v7
      - uses: vishisht16/setup-syg@v1
        with:
          version: 1.0.0
      - name: syg check
        # Write the log even when there are findings; fail the job afterwards.
        run: syg check --format sarif services/ > syg.sarif || echo "SYG_EXIT=$?" >> "$GITHUB_ENV"
      - uses: github/codeql-action/upload-sarif@v4
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

## Other CI systems

Anywhere else, install the binary in the job, then run `syg check` and gate on
its exit code. The install script needs only `sh`, `tar` and `curl` or `wget`
(BusyBox's will do). It checks the archive against the release's `SHA256SUMS`
before installing it:

```yaml
# GitLab CI
syg:
  image: alpine:3
  script:
    - wget -qO- https://syg.vishisht.tech/install.sh | SYG_VERSION=1.0.0 SYG_INSTALL_DIR=/usr/local/bin sh
    - syg check --format json services/ > syg.json
  artifacts:
    when: always
    paths: [syg.json]
```

```yaml
# Bitbucket Pipelines
pipelines:
  pull-requests:
    '**':
      - step:
          image: alpine:3
          script:
            - wget -qO- https://syg.vishisht.tech/install.sh | SYG_VERSION=1.0.0 SYG_INSTALL_DIR=/usr/local/bin sh
            - syg check --strict services/
```

```groovy
// Jenkins, on an agent with sh and curl
sh 'curl -fsSL https://syg.vishisht.tech/install.sh | SYG_VERSION=1.0.0 SYG_INSTALL_DIR="$WORKSPACE/.bin" sh'
sh '"$WORKSPACE/.bin/syg" check services/'
```

Where a job can run a container's own command, the
[image](container.md) needs no installation. It has no shell, so it does
not serve as a job's image in GitLab CI, Bitbucket Pipelines or CircleCI,
which run a script inside it:

```console
$ docker run --rm -v "$PWD:/src:ro" ghcr.io/vishisht16/syg:1.0.0 check services/
```

Pin the version (`SYG_VERSION`, or the image's tag), so that a new release
changes your pipeline only when you choose. Within a version, a new rule
arrives as a warning, and fails a build no earlier than the next minor version
([compatibility](compatibility.md)).

## What CI cannot check

Tier-2 rules need a cluster snapshot. They are reported as skipped, never as
passed, when there is none. To run them in CI, capture a snapshot from the
cluster on a schedule (`syg snapshot -o cluster.snapshot.yaml`, read-only, with
the role in `docs/snapshot-rbac.yaml`). Commit it, and name it in `syg.yaml`'s
`snapshots:`. A snapshot older than `snapshotMaxAge` (30 days by default) warns.
