# Security

To report a vulnerability in Syg, use GitHub's private vulnerability reporting
on this repository (Security → Report a vulnerability). Please do not open a
public issue for it.

Every release is built by this repository's release workflow, which signs
each archive with cosign (keyless, tied to the workflow) and records a build
provenance attestation. To check that a binary is one this workflow built:

```console
$ gh attestation verify syg_1.0.0_linux_amd64.tar.gz --repo vishisht16/syg
```

Syg never applies anything to a cluster. `syg snapshot` is the only command
that reads one, and it only reads; `check` and `build` need no network and no
credentials.
