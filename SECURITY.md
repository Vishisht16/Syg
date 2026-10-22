# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository: **Security →
Report a vulnerability**. Please do not open a public issue for it.
`https://syg.vishisht.tech/.well-known/security.txt` points here too.

A report is most useful with:

- the version (`syg version`) and the platform;
- what you ran, and the smallest module or input that shows it;
- what an attacker gains: what they control (a pull request, a module, a
  flag, the editor's language server) and what they reach.

You get an answer in the report itself. A fix is released as a new version,
and published with an advisory in this repository, crediting you if you
wish.

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
workflow, `build.yml`, signs every file with cosign (keyless, tied to the
workflow and recorded in Sigstore's transparency log), and attests the
provenance of each archive, package and image. Its signing jobs run none of
the build's code. To check that a download is one it built:

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
