# Install

Syg is one static binary, with no runtime dependencies, for Linux, macOS and
Windows on amd64 and arm64.

## macOS and Linux

With [Homebrew](https://brew.sh):

```console
$ brew install vishisht16/tap/syg
```

Or with the install script, which downloads the release for your platform,
checks it against the published checksums (and its signature, when cosign 3 or
newer is installed), and puts `syg` in `~/.local/bin` (no `sudo`):

```console
$ curl -fsSL https://syg.vishisht.tech/install.sh | sh
```

`SYG_VERSION=1.0.0` pins a version, and `SYG_INSTALL_DIR=/usr/local/bin`
chooses where it goes.

## Windows

With [Scoop](https://scoop.sh):

```console
> scoop bucket add syg https://github.com/vishisht16/syg
> scoop install syg
```

Or with PowerShell, the equivalent of the install script:

```console
> irm https://syg.vishisht.tech/install.ps1 | iex
```

## In CI and containers

In GitHub Actions, the action checks the download's checksum and provenance:

```yaml
- uses: vishisht16/setup-syg@v1
- run: syg check --format github
```

In any other CI system, install with the script above, as the [CI](ci.md)
page shows for GitLab, Bitbucket and Jenkins. Where a step runs an image's own
command, there is the [container image](container.md), which runs as a user
of its own, not root:

```console
$ docker run --rm -v "$PWD:/src:ro" ghcr.io/vishisht16/syg:1.0.0 check
```

`.deb` and `.rpm` packages are attached to every release, and tools that
install from GitHub releases work too: `mise use github:vishisht16/syg`.

Homebrew and the `.deb` and `.rpm` packages install shell completions for
bash, zsh and fish, and the man page (`man syg`). Elsewhere, `syg completion`
prints the script for your shell ([CLI](cli.md#completion)).

## By hand

Download the archive for your platform from the
[releases](https://github.com/vishisht16/syg/releases), with `SHA256SUMS`,
check it, and put `syg` on your `PATH`:

```console
$ sha256sum --check --ignore-missing SHA256SUMS
syg_1.0.0_linux_amd64.tar.gz: OK
$ tar xzf syg_1.0.0_linux_amd64.tar.gz
$ install syg ~/.local/bin/
$ syg version
syg 1.0.0 (Kubernetes 1.32 schema, k8s.io/api v0.32.13)
```

On macOS use `shasum -a 256 --check`. macOS quarantines a file downloaded with
a browser, and Gatekeeper then refuses to run it, since Syg's binaries are
not notarized by Apple. Clear the quarantine once with
`xattr -d com.apple.quarantine ./syg`. (Homebrew and the install script are
not affected.) On Windows, unzip the `.zip` and put `syg.exe` on your `PATH`.

Every archive is also signed with [cosign](https://docs.sigstore.dev), keyless,
by the release workflow, carries a provenance attestation, and comes with two
software bills of materials (`.spdx.json` and `.cdx.json`). The
[security](security.md#verifying-a-download) page shows how to check each.

Syg sends anonymous usage statistics; the [privacy](privacy.md) page says what,
and `SYG_TELEMETRY=off` turns them off.

## Your editor

`syg lsp` is a language server: diagnostics as you type, hover that says which
Kubernetes fields a line derives, completion, go-to-definition and references,
and formatting. Any editor with a language-server client can run it. Associate
`*.syg` files with the command `syg lsp`, which speaks over stdin and stdout.

For Neovim:

```lua
vim.filetype.add({ extension = { syg = "syg" } })
vim.api.nvim_create_autocmd("FileType", {
  pattern = "syg",
  callback = function(ev)
    vim.lsp.start({ name = "syg", cmd = { "syg", "lsp" }, root_dir = vim.fs.dirname(ev.file) })
  end,
})
```

For Helix, in `languages.toml`:

```toml
[language-server.syg]
command = "syg"
args = ["lsp"]

[[language]]
name = "syg"
scope = "source.syg"
file-types = ["syg"]
language-servers = ["syg"]
```

In VS Code, a generic language-client extension that runs a command for a file
type works the same way.

## Next

The [quickstart](quickstart.md) takes a new service from `syg init` to a
cluster.
