# CLI reference

```text
syg <command> [args]
```

A module path is a directory, or a `.syg` file in one (the whole directory is
compiled). It defaults to the current directory. Flags may come before or after
the path.

## Exit codes

Every command uses the same four:

| Code | Meaning |
|---|---|
| 0 | success; warnings and notes allowed |
| 1 | findings that fail: an error, or a warning under `--strict`. For `mod tidy`, a module changed since it was pinned |
| 2 | Syg could not do what was asked: a usage or configuration mistake (a bad flag, an unknown rule in `syg.yaml`), or a file it cannot read or write, standard output included |
| 3 | an internal error in Syg. Please report it |

If the Go runtime itself stops Syg, as it does when memory runs out, the code
is 2 and stderr starts with `fatal error`. Syg's [input limits](#limits) keep
that from happening on any input.

## check

```text
syg check [path] [--env NAME] [--format text|json|sarif|github] [--strict]
          [--snapshot FILE] [--baseline PATH] [--namespace NS]
          [--print-world] [--stats] [--no-color]
```

Parses, resolves, type-checks and builds the graph, then runs every rule, for
the base module and each environment (or only `--env NAME`). It needs no
network and no credentials. Findings go to stderr as text, or to stdout in a
machine format:

- `json`: an array of findings, described by [a JSON schema](schemas/diagnostics-v1.json);
- `sarif`: SARIF 2.1.0, for code scanning;
- `github`: workflow annotation commands, for a GitHub Actions step.

`--snapshot` and `--baseline` override `syg.yaml`'s `snapshots:` and
`baseline:`. `--print-world` lists the closed world the checks cover; `--stats`
counts objects Syg models against raw ones.

## build

```text
syg build [path] -o DIR [--env NAME] [--target plain|kustomize|argo]
          [--target-traffic gateway|ingress] [--gateway NAME] [--ingress-class C]
          [--namespace NS] [--format ...] [--strict]
          [--argo-repo URL] [--argo-path P] [--argo-revision R]
          [--argo-namespace NS] [--argo-auto-sync]
```

Checks, then writes the manifests: nothing at all if there is an error. With
`-o`, the directory is replaced atomically, and only if it is empty or a
previous build wrote it. Without `-o`, one YAML stream goes to stdout.

- A module with environments needs `--env`, or a layout target that writes
  them all: `kustomize` (a base and an overlay per environment) or `argo` (a
  directory and an Argo CD Application per environment, which needs
  `--argo-repo`).
- A module without environments gets no namespace unless you give
  `--namespace`; cluster-wide grants need one.
- `--target-traffic ingress` emits Ingress objects instead of Gateway API
  HTTPRoutes.
- A flag that becomes a name in the manifests is checked as the same name
  written in source would be, before anything is read: `--namespace` and
  `--argo-namespace` as namespaces, `--gateway` and `--ingress-class` as object
  names, and `--argo-path` as a path within the repository, without `..`. A
  bad value exits 2.

The provenance of every field is written to `provenance/` beside the
manifests; `kubectl apply -f DIR` applies only the manifests.

## explain, rules, why, graph

```text
syg explain RULE|TOPIC        the mechanism behind a rule, or a topic
syg explain --list            every rule and topic
syg rules [--json]            the rule catalogue
syg why [path] KIND/NAME [FIELD] [--env NAME]
syg graph [path] [--format dot|json] [--service NAME] [-reachability]
```

`why` says where an emitted object, or one of its fields, came from: written,
derived (and by which rule of derivation), from a profile, or from an
environment. `graph` prints the resource graph the checks run on; `--format
json` marks edges to extern objects as trusted, not verified.

## fmt

```text
syg fmt [path] [-w | --check]
```

Prints the canonical layout of each file. `-w` rewrites the files; `--check`
lists each file that is not canonical, with a diff of what `-w` would change,
and exits 1 if there is any.

## init

```text
syg init [dir] [--name MODULE] [--service NAME] [--import MODULE --profile NAME]
```

Writes a module whose one service checks clean, and a commented `syg.yaml`.
With `--import` and `--profile`, the service uses a platform team's profile,
and the import is pinned.

## mod

```text
syg mod lock [path]           pin every import's content hash in syg.lock
syg mod tidy [path]           pin new imports, drop unused pins; never re-pin a changed one
syg mod get DIR [path]        vendor the module checked out in DIR, and pin it
syg mod vendor NAME [path]    copy a bundled relation library into vendor/
```

Syg never downloads a module: fetch it yourself (git, an archive), and
`mod get` vendors what the compiler reads.

## snapshot, schema

```text
syg snapshot -o FILE [--kubeconfig F] [--context C] [--namespace NS,...]
             [--secret-keys] [--timeout D]
syg schema vendor --from SNAPSHOT|CRD.yaml|DIR|URL [--only GROUP[/Kind]] [path]
```

`snapshot` is the only command that talks to a cluster. It only reads, and
records no secret value; `--secret-keys` records Secret key names, which needs
`get` on Secrets. `--namespace` records the Services, ConfigMaps, Secrets and
ServiceAccounts there, to verify externs. `schema vendor` copies CRD schemas
into the module's `schemas/`.

## lsp, version

```text
syg lsp        a language server on stdin and stdout
syg version    the version, and the Kubernetes schema it validates against
```

`syg lsp` exits as the Language Server Protocol says: 0 after `shutdown` and
then `exit`, 1 when the session ends without `shutdown`. A malformed message
frame (a header of more than 16 lines or 1 KiB a line, a missing or negative
`Content-Length`, or one over 64 MiB) is 2, since nothing after it can be read
in step. A message that is well framed but not JSON gets a parse error, and the
session goes on.

## telemetry

```text
syg telemetry [status|on|off|show|send]
```

Syg sends anonymous usage statistics, so that what gets fixed and improved
follows how it is used. No module, service or file name, no path, no message
and no code ever leaves your machine; the [privacy page](privacy.md) lists
exactly what is sent. A one-line notice says so the first time Syg runs on a
terminal, and nothing is recorded before it. Sending never delays a command or
changes its result: a command queues its event and, at most once an hour,
starts `syg telemetry send` in the background to send the queue. A CI run
sends its event at exit instead, waiting at most 250 ms.

- `status` says whether it is on, and why.
- `off` and `on` turn it off or on for your user.
- `show` prints exactly what is queued to be sent.
- `send` sends it now, and prints nothing.

`SYG_TELEMETRY=off` or `DO_NOT_TRACK=1` turns it off too, for one command or a
whole CI job. Syg also checks for a newer release at most once a day, and
prints a one-line notice on a terminal when there is one; that check is off
whenever telemetry is.

## Limits

`syg check` is meant to be safe to run on code nobody has reviewed yet, such as
a pull request, so what it reads, and what it prints about it, is bounded:

| Input | At most |
|---|---|
| a `.syg` file | 8 MiB |
| a compilation: the module and everything it imports | 64 MiB of `.syg` source |
| a string | 1.5 MiB, more than any Kubernetes object can hold |
| a snapshot, a baseline manifest, a vendored CRD schema | 64 MiB each |
| `syg.yaml`, `syg.lock` | 1 MiB each |
| syntax errors reported for one file | 50, then one note |
| a language server message | 64 MiB, after a header of at most 16 lines of 1 KiB |

A `.syg` file must be UTF-8 (a byte order mark is fine), and Syg reads only
regular files: a symbolic link in a module, in `vendor/` or in `schemas/` is an
error, not followed. An import stays inside the git repository that holds the
module. A source line longer than 160 characters is shown as a window around
the finding. `syg explain limit` says more.

## syg.yaml

Optional, beside the module's files. Paths in it (`snapshots:`, `baseline:`)
are relative to the directory that holds it; paths given as flags
(`--snapshot`, `--baseline`, `-o`) are relative to where you run `syg`.

A path in `syg.yaml` stays inside the git repository that holds the module (or
the module's directory, outside a repository), and names a regular file or
directory, not a symbolic link. Checking a pull request then reads nothing else
on the machine. A file elsewhere is named with the flag, which is the caller's
choice and is followed as given.

```yaml
rules:                 # DETECTED rules only: off, error, warning or info
  CHK-RES-003: off
snapshots:             # per environment, or default
  default: cluster.snapshot.yaml
snapshotMaxAge: 168h   # older is reported as stale
baseline: ../deployed/{env}
require:               # declarations every workload must make
  default: [disruption]
  prod: [identity, policy]
```
