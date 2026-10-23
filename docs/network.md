# Network and data

Every connection Syg makes and what it carries, and how to run Syg through a
proxy, behind a corporate certificate authority, or with no network at all.

## What connects, and when

| What | Where to | When |
|---|---|---|
| Usage statistics | `https://api.syg.vishisht.tech/v1/events` | After a command, in the background; in CI at exit, waiting at most 250 ms. Outside CI, never before the one-line notice has been shown on a terminal. What is sent is on the [privacy](privacy.md) page. |
| The update check | `https://api.syg.vishisht.tech/v1/version` | At most once a day, in the background, outside CI. It sends Syg's version, the operating system and the architecture. |
| `syg schema vendor --from URL` | the https URL you give | Only when you run it. |
| `syg snapshot` | the API server your kubeconfig names | Only when you run it; it only reads. |

Nothing else connects. `check`, `build`, `fmt`, `explain`, `mod` and `lsp`
read and write files, and `mod get` copies a module from a directory on the
machine: getting it there (`git clone`, a release archive) is yours.

`SYG_TELEMETRY=off` or `DO_NOT_TRACK=1` turns off both the statistics and the
update check, for one command or a whole CI job; `syg telemetry off` turns
them off for your user. A connection that fails changes nothing: no output,
no exit code, no delay beyond the 250 ms a CI run waits at exit.

## Proxies

Syg's HTTPS client reads the standard variables: `HTTPS_PROXY` (and
`HTTP_PROXY`), with `NO_PROXY` for hosts to reach directly, in capitals or
not. `syg snapshot` uses the kubeconfig's `proxy-url` when it names one, and
the same variables otherwise.

## Certificates

- **Linux:** Syg trusts the system's certificate authorities. `SSL_CERT_FILE`
  (a bundle) or `SSL_CERT_DIR` (a directory) replaces them, for instance with
  a bundle that adds your company's authority.
- **macOS and Windows:** Syg uses the system's trust store, where a corporate
  authority is usually installed already.
- **The container image:** it holds Mozilla's authorities at
  `/etc/ssl/certs/ca-certificates.crt`. Mount a bundle of your own and point
  `SSL_CERT_FILE` at it:

```console
$ docker run --rm -v "$PWD:/src" -v /etc/ssl/corp-bundle.pem:/corp.pem:ro \
    -e SSL_CERT_FILE=/corp.pem --user "$(id -u):$(id -g)" \
    ghcr.io/vishisht16/syg:1 schema vendor --from https://example.com/crds.yaml
```

## Without a network

`syg check` and `syg build` need no network. With none, the statistics and the
update check give up in the background, and nothing else changes. Before each
release, the release workflow runs `check` and `build` in a namespace with no
network at all, with statistics on, and checks that their exit codes and
timing are unchanged.

To install on a machine with no network:

1. **On a connected machine,** download the archive for the platform,
   `SHA256SUMS`, the archive's `.sigstore.json` and the release's
   `.intoto.jsonl`.
2. **Check them** as the [security](security.md#verifying-a-download) page
   shows. Its offline check needs one more file, the trusted root, fetched
   there too.
3. **Carry them over,** check the checksum again, and unpack. The `.deb` and
   `.rpm` packages install with `dpkg -i` or `rpm -i`.

Set `SYG_TELEMETRY=off` on such a machine, so that nothing is attempted.

## Seeing what is sent

`syg telemetry show` prints the queued events exactly as they will be sent.

To watch the requests themselves, point `SYG_TELEMETRY_URL` at a listener on
your own machine. Then send the queue to it:

```console
$ nc -l 127.0.0.1 8080 &
$ SYG_TELEMETRY_URL=http://127.0.0.1:8080 syg telemetry send
```

`SYG_TELEMETRY_URL` takes only an address on the same machine (`127.0.0.1`,
`::1` or `localhost`), so it can never send the statistics anywhere else.
