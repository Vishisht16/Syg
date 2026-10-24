# Security

How Syg protects you when it reads code nobody has reviewed, how to check
that a download is the one Syg's release workflow built, and how to report a
vulnerability.

## Safe on an untrusted pull request

`syg check` is meant to run on a pull request before anyone has reviewed it,
with no credentials and no network. That rests on five properties:

- **It reads only the module.** It reads regular files inside the git
  repository that holds the module. A symbolic link out of the repository, a
  named pipe or a device is refused unread. So is an import, or a path in
  `syg.yaml`, that leads out of the repository ([paths](cli.md#paths)).
- **Everything it reads is bounded.** A file is at most 8 MiB, a module 64
  MiB, a string 1.5 MiB, and the work a module makes 200,000 items. Its
  memory and its output grow with the input, never faster (`syg explain
  limit`).
- **What it prints cannot take over a terminal or a log.** A control
  character in a file, or in a file's name, is shown as a symbol. It cannot
  move the cursor, start a line of its own or forge a GitHub annotation.
- **It needs no network and no credentials.** `check` and `build` connect to
  nothing but the usage statistics and the daily update check, and neither
  ever changes a result ([network](network.md)). Only `syg snapshot` reads a
  cluster, and it only reads.
- **It never applies anything to a cluster.**

A way around any of these is a vulnerability: [report it](#reporting-a-vulnerability).

## What it does not protect against

- **A check that misses a mistake.** That is a bug, not a vulnerability.
  Syg's checks are claims about a module's closed world (`syg explain
  closed-world`). A clean result is not a guarantee that a deployment is
  correct.
- **What a module asks for.** Syg reports the privileged pods, host access and
  wildcard RBAC it can see. What is approved and deployed is your decision.
- **The machine it runs on.** That covers a compromised CI runner, and a
  `syg` that is not the one released. Check what you download, below.
- **Secrets.** Syg declares a secret's keys and never holds their values.
  Keep the values in a secrets manager.

## Verifying a download

Every release is built and signed in public, by the release workflow of
[github.com/vishisht16/syg](https://github.com/vishisht16/syg):

- every file the build makes is listed in `SHA256SUMS`;
- each of those is signed with [cosign](https://docs.sigstore.dev),
  keyless, beside it in a `.sigstore.json`. A signature names the workflow
  that made it, and is recorded in Sigstore's public transparency log;
- each archive and package also carries a provenance attestation, a signed
  statement of how it was built; `syg_1.0.0.intoto.jsonl` holds them all.

The checksum, on any machine:

```console
$ sha256sum --check --ignore-missing SHA256SUMS
syg_1.0.0_linux_amd64.tar.gz: OK
```

The provenance, with the [GitHub CLI](https://cli.github.com) signed in:

```console
$ gh attestation verify syg_1.0.0_linux_amd64.tar.gz --repo Vishisht16/Syg \
    --signer-workflow Vishisht16/Syg/.github/workflows/build.yml
```

The signature, with cosign 3 or newer:

```console
$ cosign verify-blob syg_1.0.0_linux_amd64.tar.gz \
    --bundle syg_1.0.0_linux_amd64.tar.gz.sigstore.json \
    --certificate-identity-regexp '(?i)^https://github\.com/vishisht16/syg/\.github/workflows/build\.yml@refs/(heads/main|tags/v.+)$' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

What the installers check for you:

- `install.sh` checks the checksum, and the signature too when cosign 3 or
  newer is installed;
- the GitHub Action checks the checksum and the provenance.

On a machine with no network, first fetch Sigstore's trusted root on a
connected machine (`gh attestation trusted-root > trusted_root.jsonl`). Bring
it, with the release's `syg_1.0.0.intoto.jsonl`, and check the provenance
from those files alone:

```console
$ gh attestation verify syg_1.0.0_linux_amd64.tar.gz --repo Vishisht16/Syg \
    --signer-workflow Vishisht16/Syg/.github/workflows/build.yml \
    --bundle syg_1.0.0.intoto.jsonl --custom-trusted-root trusted_root.jsonl
```

The container image is checked the same way, as its page shows
([verifying it](container.md#verifying-it)).

## How a release is built

- **In public, from a private source.** The release workflow runs in the
  public repository, on GitHub's hosted runners, with no caches. It checks
  the source out at the release's tag, runs its tests and builds every
  platform, then deletes the checkout. Its logs never show the source.
- **The jobs that build cannot sign, and the jobs that sign build nothing.**
  A reusable workflow, `build.yml`, builds and tests with read-only
  permissions and no token that can sign. Its signing jobs receive only the
  finished files, sign them and attest how they were made, and run none of
  the build's code.
  - That is why verification names `build.yml` as the signer.
  - It is SLSA v1.0 Build Level 3 provenance, as GitHub describes it for
    attestations made in a reusable workflow.
- **Which source it came from.** The provenance names the workflow and the
  public repository's commit. A second signed statement, in the same
  `syg_1.0.0.intoto.jsonl`, names the source's tag and commit, and the
  toolchain and flags the build used. Each binary records its commit too
  (`go version -m syg`).
- **Reproducible.** The build pins:
  - the Go version the source names;
  - `CGO_ENABLED=0` and `-trimpath`;
  - archives packed with fixed times and owners.

  So the same commit gives the same bytes, and whoever has the source can
  rebuild a release and compare it with `SHA256SUMS`. The source is private,
  so that is an auditor's check.
- **The image.** It is the Linux archives' binaries, copied onto an empty
  image: nothing runs inside it while it is built, and the builder's own
  image is pinned by digest. Before the release is published, it is run on
  amd64 and on arm64, natively, as the [container](container.md) page runs
  it, and its binary is compared with the archive's.
- **What is in it.** Each archive comes with two software bills of materials,
  SPDX (`.spdx.json`) and CycloneDX (`.cdx.json`). They list the Go modules
  the binary links, as the binary records them. The image carries one as an
  attestation. `THIRD_PARTY_NOTICES.txt`, in every archive and package,
  holds their licences.

## How Syg is tested

Every change is tested on Linux, macOS and Windows, fuzzed, scanned, and run
against real clusters. Before 1.0, Syg also went through six rounds of
testing whose brief was to break it. [How Syg was tested](testing.md) says
what it went through, what broke and what changed, and what has not been
tested yet.

## Test it yourself

Break it if you can, and tell us how. Fuzz it, feed it hostile modules,
attack its language server, its installers and its release files: the
next section says how to report what you find, and the one after it, what
you can expect from us.

**Safe harbor.** Security research done in good faith and within this
policy is authorized:

- we will not take legal action against you for it, or ask anyone else to;
  if someone else does, we will make it known that you acted within this
  policy;
- the license agreement forbids reverse engineering, decompiling and
  disassembling Syg; for security research within this policy, we waive
  that restriction.

Within this policy means:

- test on your own machines and your own installations;
- no load or denial-of-service tests against `syg.vishisht.tech` or the
  statistics relay, `api.syg.vishisht.tech`, which other people use: a
  finding about either is still welcome;
- do not access, change or delete anyone else's data, and if you come
  across some, stop and tell us;
- give us the time below to fix a problem before you make it public.

This policy covers what Syg owns. It cannot authorize anything against
GitHub, Vercel or PostHog, whose own policies apply. If you are unsure
whether something is covered, ask first: syg@vishisht.tech.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on
[the public repository](https://github.com/vishisht16/syg/security/advisories/new),
or write to syg@vishisht.tech, and please do not open a public issue.
`/.well-known/security.txt` on this site points there too.

A report is most useful with:

- the version (`syg version`) and the platform;
- what you ran, and the smallest module or input that shows it;
- what an attacker gains: what they control (a pull request, a module, a
  flag, the editor's language server) and what they reach.

## What you can expect from us

- An acknowledgement within 3 business days.
- Within 14 days, our assessment: whether it is a vulnerability, how severe,
  and what happens next.
- A fix within 30 days for a critical or high severity problem, and within
  90 days for the rest. If it will take longer, we tell you why, and when.
- A coordinated disclosure: when the fix is released as a new version, with
  an advisory, or 90 days after your report, whichever comes first.
- Credit in the advisory and in the hall of fame below, if you wish. Your
  name is never shared without your consent.

## Hall of fame

The people who found a vulnerability in Syg and reported it, with our
thanks. None yet: the first report that leads to a fix puts its reporter
here.

## Supported versions

The latest release. A fix is not backported to earlier ones: upgrading is the
fix.
