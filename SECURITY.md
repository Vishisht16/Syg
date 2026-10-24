# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository: **Security →
Report a vulnerability**, or write to syg@vishisht.tech. Please do not open a
public issue for it. `https://syg.vishisht.tech/.well-known/security.txt`
points here too.

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
  an advisory in this repository, or 90 days after your report, whichever
  comes first.
- Credit in the advisory and in the
  [hall of fame](https://syg.vishisht.tech/security.html#hall-of-fame), if
  you wish. Your name is never shared without your consent.

## Testing Syg: safe harbor

Break it if you can, and tell us how. Fuzz it, feed it hostile modules,
attack its language server, its installers and its release files. Security
research done in good faith and within this policy is authorized:

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
- give us the time above to fix a problem before you make it public.

This policy covers what Syg owns. It cannot authorize anything against
GitHub, Vercel or PostHog, whose own policies apply. If you are unsure
whether something is covered, ask first: syg@vishisht.tech.

What Syg went through before its release, what broke, and what has not been
tested yet: [how Syg was tested](https://syg.vishisht.tech/testing.html). To
test what comes next before it is released, write to syg@vishisht.tech.

## What is covered

- `syg` itself: in particular, `syg check` is meant to be safe to run on a
  pull request nobody has reviewed yet. It reads only regular files inside the
  repository that holds the module, every input it reads is bounded, and what
  it prints cannot rewrite the terminal or the log. A way around any of that
  is a vulnerability.
- The installers (`install.sh`, `install.ps1`), the GitHub Action
  ([setup-syg](https://github.com/vishisht16/setup-syg)), the container
  image, the packages, and the release workflow that builds them.
- The relay that receives the usage statistics (`relay/`).

A check that misses a mistake in a module is a bug, not a vulnerability:
open an issue for it.

## Supported versions

The latest release. A fix is not backported to earlier ones; upgrading is the
fix.

## Verifying a release

Every release is built by this repository's release workflow. A reusable
workflow, `build.yml`, signs every file the build makes with cosign
(keyless, tied to the workflow and recorded in Sigstore's transparency log),
and attests the provenance of each archive, package and image. Its signing
jobs run none of the build's code. To check that a download is one it built:

```console
$ gh attestation verify syg_1.0.0_linux_amd64.tar.gz --repo Vishisht16/Syg \
    --signer-workflow Vishisht16/Syg/.github/workflows/build.yml
```

or, with cosign 3:

```console
$ cosign verify-blob syg_1.0.0_linux_amd64.tar.gz \
    --bundle syg_1.0.0_linux_amd64.tar.gz.sigstore.json \
    --certificate-identity-regexp '(?i)^https://github\.com/vishisht16/syg/\.github/workflows/build\.yml@refs/(heads/main|tags/v.+)$' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

and the image, with `cosign verify ghcr.io/vishisht16/syg:1.0.0` and the same
two certificate flags, or `gh attestation verify oci://ghcr.io/vishisht16/syg:1.0.0`
with the same `--repo` and `--signer-workflow`. Verifying offline, and what
the provenance and the source statement say:
[security](https://syg.vishisht.tech/security.html).

`install.sh` checks the archive against the release's `SHA256SUMS`, and its
signature when cosign 3 or newer is installed. setup-syg checks the checksum
and the provenance.

## What Syg does not do

Syg never applies anything to a cluster. `syg snapshot` is the only command
that reads one, and it only reads; `check` and `build` need no network and no
credentials.
