# Container image

`ghcr.io/vishisht16/syg` holds the release binary alone on an empty image, for
linux/amd64 and linux/arm64.

## Tags

| Tag | Is |
|---|---|
| `1.0.0` | one release, never moved |
| `1` | the newest 1.x release |
| `latest` | the newest release |
| `1.0.0-rc.4` | a release candidate, which never moves `1` or `latest` |

For exact bytes in CI, pin a tag's digest after verifying it (below):
`ghcr.io/vishisht16/syg:1.0.0@sha256:...`.

## Running it

The image runs as user 65532, not root, and needs no capabilities and no
writable file system. Its working directory is `/src`:

```console
$ docker run --rm --read-only --cap-drop ALL -v "$PWD:/src:ro" ghcr.io/vishisht16/syg:1 check
```

To write into the directory you mount (`build -o`, `fmt -w`, `init`), run it
as the user who owns that directory:

```console
$ docker run --rm --read-only --cap-drop ALL --user "$(id -u):$(id -g)" \
    -v "$PWD:/src" ghcr.io/vishisht16/syg:1 build -o out
```

Podman takes the same flags. The [pre-commit](https://pre-commit.com) hooks
run the image as your user already.

The image has no shell. It suits a step that runs an image's own command:
`docker run`, a Tekton or Argo Workflows step, pre-commit. A CI job that runs
a script inside its image, as GitLab CI, Bitbucket Pipelines and CircleCI do,
needs a shell, so it installs the binary instead ([CI](ci.md#other-ci-systems)).

## Usage statistics

A CI job sends its statistics at exit, with no installation ID, as anywhere
else. Elsewhere the image has nowhere writable to remember anything. So it
sends nothing, and on a terminal it prints the one-line notice each time it
runs. `-e SYG_TELEMETRY=off` turns them off everywhere.

## Verifying it

The image is signed by the release workflow, keyless, and carries a
provenance attestation and an SBOM:

```console
$ cosign verify ghcr.io/vishisht16/syg:1.0.0 \
    --certificate-identity-regexp '(?i)^https://github\.com/vishisht16/syg/\.github/workflows/build\.yml@refs/(heads/main|tags/v.+)$' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
$ gh attestation verify oci://ghcr.io/vishisht16/syg:1.0.0 --repo Vishisht16/Syg \
    --signer-workflow Vishisht16/Syg/.github/workflows/build.yml
```

The same command with `--predicate-type https://spdx.dev/Document/v2.3`
checks the SBOM's attestation; add `--format json` to read it. Each tag
points at the digest these sign: the release workflow signs and checks the
image by digest before it publishes the release, and tags it after.

## What is inside

- `/usr/local/bin/syg`: the same bytes as the binary in the Linux archive for
  its platform, which the release workflow checks on amd64 and on arm64
  before it publishes;
- `/etc/ssl/certs/ca-certificates.crt`: Mozilla's certificate authorities, under
  the MPL 2.0, with their notice in `/usr/share/doc/ca-certificates`;
- `/usr/share/doc/syg`: the EULA, the privacy statement and the third-party
  notices.

Nothing else: no shell, no package manager.
