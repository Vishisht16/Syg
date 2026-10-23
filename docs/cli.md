# CLI reference

```text
syg <command> [args]
```

A module path is a directory, or a `.syg` file in one (the whole directory is
compiled). It defaults to the current directory. Flags may come before or after
the path. An argument a command does not take is an error (exit 2), as an
unknown flag is: `syg check a b` does not quietly check only `a`. After `--`,
every argument is a name or a path, even one that starts with `-`, as in
`syg mod get -- -dir`.

`--help` after a command lists its flags, and exits 2, as Go's own tools do.

## Exit codes

Every command uses the same four:

| Code | Meaning |
|---|---|
| 0 | success; warnings and notes allowed |
| 1 | findings that fail: an error, or a warning under `--strict`. For `mod tidy`, a module changed since it was pinned |
| 2 | Syg could not do what was asked: a usage or configuration mistake (a bad flag, an unknown rule in `syg.yaml`), a file it cannot read or write (a snapshot or baseline it was given, standard output included), or a path it will not follow (see [paths](#paths)) |
| 3 | an internal error in Syg. Please report it |

A process that runs out of memory is stopped by the operating system, often
with no message (a shell reports 137), or by the Go runtime, with code 2 and
stderr starting with `fatal error`. Syg's [input limits](#limits) bound what
any input costs: about 0.5 GB of memory for the largest checks measured, and
about 1.3 GB for the largest builds. To hold Syg to less on a small CI runner,
set `GOMEMLIMIT` (as in `GOMEMLIMIT=512MiB`): the Go runtime then collects
garbage more often to stay near it, which is slower and keeps the peak lower.
It is a target, not a ceiling: what a compilation needs at once, it still
takes.

A pipe that closes early, as in `syg rules | head`, ends Syg as it ends any
Unix tool: by SIGPIPE, which a shell reports as 141. If the reader took
everything before it closed, the code is 0. Windows has no SIGPIPE: there Syg
stops as quietly when a write finds the pipe closed, and the code is 2.

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

- `json`: one object, `{"$schema": "https://syg.vishisht.tech/schemas/diagnostics-v1.json", "findings": [...]}`,
  described by [that schema](schemas/diagnostics-v1.json);
- `sarif`: SARIF 2.1.0, for code scanning;
- `github`: workflow annotation commands, for a GitHub Actions step.

A file's name is printed as its characters: a newline, an escape or another
control character in it shows as its symbol (`␊`, `␛`). A name cannot start a
line of its own in a log, so it cannot forge a GitHub annotation, and it cannot
send a control sequence to your terminal.

`--snapshot` and `--baseline` override `syg.yaml`'s `snapshots:` and
`baseline:`. A snapshot or baseline that cannot be read is reported as an error
in every format, and the code is 2. `--print-world` lists the closed world the
checks cover; `--stats` counts objects Syg models against raw ones.

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

A build replaces the directory only if it is still what the build began with,
so of two builds into one `-o` at once, the later exits 2 and writes nothing.
Builds one after the other each replace it. While it swaps the new output in, a build holds a claim
beside the directory, `.DIR.syg-lock`, for a few renames; one left by a build
stopped at that moment is taken over after a minute.

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

Each object is written to its own file, `KIND-NAME.yaml` (`deployment-api.yaml`).
A name too long for a file's name, more than 255 bytes with its kind, is cut
and a hash of the whole name added, the same on every build. The provenance of
every field is written to `provenance/` beside the manifests;
`kubectl apply -f DIR` applies only the manifests.

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
syg fmt [path ...] [-w | --check]
```

Prints the canonical layout of each file, in every path given: a `.syg` file,
or a directory's. `-w` rewrites the files, and none of them if any has an
error; `--check` lists each file that is not canonical, with a diff of what
`-w` would change, and exits 1 if there is any.

Line endings are no part of the layout: a file whose lines end in CRLF, as Git
for Windows checks files out by default, keeps them.

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
`mod get` vendors what the compiler reads. `DIR` is a directory on this
machine, such as a clone: `mod get ../platform` vendors the module checked out
beside yours.

A bundled relation library needs no vendoring: import it by its path
(`import "syg.vishisht.tech/relate/istio"`) and pin it with `syg mod lock`, as
any import is pinned, so that a release of Syg that changes the library shows
in review. `mod vendor NAME` copies one into `vendor/` if you want a copy that
later releases of Syg leave alone.

`syg.lock` holds one pin per module. A module pinned twice is an error, which
`syg mod lock` clears by writing the file again. Every file `mod` writes is
written whole, to a new file renamed into place: an interrupted write leaves
the file as it was.

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
into the module's `schemas/`. Each `--from` is one source, taken whole, comma
and all, and a file named twice, as itself and through its directory, is read
once. A file or directory is read as any [path you name](#paths) is,
regular files only, up to 64 MiB a file. A URL is fetched once, over https
only (`HTTPS://` too), and so is each redirect, at most ten of them, since what
a schema allows is what `check` accepts. A response larger than 64 MiB is
refused, not cut. A password or token in the URL is never printed.

A CRD's group, kind and version name the file its schema is written to,
`schemas/GROUP/Kind_version.json`, so each must be what the API server takes
for a CRD: a group is a DNS subdomain with at least one dot, a version a DNS
label that starts with a letter, a kind letters, digits and `-`. A kind's
schema is vendored from one CRD, so one group, version and kind read twice, in
one source or two, is refused, naming both places. So are two kinds whose
files differ only in case, as `Widget` and `widget` do, in one run or with a
file already in `schemas/`: macOS and Windows hold the two as one file. Each of
these is exit 2, before anything is written. A kind built into Syg
(Kubernetes's own, and the Gateway API's) is skipped, and said so: its raw
objects are validated against Syg's own schema, whatever is vendored. When
nothing is vendored, the message says what each source held.

## lsp, version

```text
syg lsp        a language server on stdin and stdout
syg version    the version, and the Kubernetes schema it validates against
```

`syg lsp` takes the two launch flags the protocol names for a server on stdin
and stdout, `--stdio` and `--clientProcessId`, so a client that passes them
works. It offers no other transport (`--pipe`, `--socket`, `--node-ipc`), and
`syg lsp --help` lists its flags instead of starting a server.

`syg lsp` exits as the Language Server Protocol says: 0 after `shutdown` and
then `exit`, 1 when the session ends without `shutdown`. A malformed message
frame (a header of more than 16 lines or 1 KiB a line, a missing or negative
`Content-Length`, or one over 64 MiB) is 2, since nothing after it can be read
in step. A message that is well framed but not JSON gets a parse error, and the
session goes on. Header lines end with CRLF, as the protocol says; a bare LF is
read the same way.

A file the editor asks about without having opened it is read as a [path you
name](#paths) is: a link out of its repository is refused, and so is anything
that is not a regular file, such as a named pipe.

## completion

```text
syg completion bash|zsh|fish|powershell
```

Prints a script that completes Syg's commands, their flags and the values a
flag takes, `.syg` files and directories, the rules (by name or code) and
topics `syg explain` takes, and the libraries `syg mod vendor` copies. Homebrew and the `.deb` and
`.rpm` packages install the scripts for bash, zsh and fish, and the man page,
`man syg`. Otherwise, load one:

```console
$ source <(syg completion bash)        # bash, in ~/.bashrc
$ source <(syg completion zsh)         # zsh, in ~/.zshrc, after compinit
$ syg completion fish > ~/.config/fish/completions/syg.fish
> syg completion powershell | Out-String | Invoke-Expression   # in $PROFILE
```

A script is fixed text, made by the `syg` that printed it: completing a word
runs nothing. After an upgrade, load it again to complete what is new.

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
| the work of a compilation | 200,000 items, profiles expanded, counted once for the base and once for each environment |
| a string | 1.5 MiB, more than any Kubernetes object can hold |
| a snapshot, a baseline manifest, a vendored CRD schema | 64 MiB each |
| `syg.yaml`, `syg.lock` | 1 MiB each |
| syntax errors reported for one file | 50, then one note |
| a language server message | 64 MiB, after a header of at most 16 lines of 1 KiB |

An item is a declaration, or one thing written in one: an `image`, a `port`, an
`env`, a config key, a label, a line of a raw object's YAML. A workload counts
nine more, for the objects Syg derives from it. 200,000 is about 5,000 full
services, or 1,000 with four environments; within it, the largest checks
measured take about 0.5 GB of memory and the largest builds about 1.3 GB.

A `.syg` file must be UTF-8 (a byte order mark is fine), and Syg reads only
regular files: a symbolic link in a module, in `vendor/` or in `schemas/` is an
error, not followed. An import stays inside the git repository that holds the
module. A source line longer than 160 characters is shown as a window around
the finding. `syg explain limit` says more.

## Paths

A path you name, as an argument or with a flag (`-o`, `--snapshot`,
`--baseline`), is followed through links (symbolic links, and on Windows
junctions too), with one exception: a link inside a git repository that leads
out of it. A pull request could have added
that link, so Syg refuses it before reading or writing anything through it, and
exits 2:

```text
syg: deploy is a link out of the repository (/work/app); Syg follows no link a repository holds out of itself
```

A link to somewhere else in the same repository is followed, and so is a link
outside every repository: your own, or the system's, such as `/tmp` on macOS.
The same holds for what Syg writes beside a module: `syg.lock`, `vendor/`,
`schemas/`, the files `init` creates, and `snapshot -o`. Each is written as a
new file and renamed into place, so a link at its path is replaced, never
written through.

On Windows, a path that names a file's alternate data stream
(`app.syg:hidden`) is refused: Syg reads a file, not its streams.

A hard link is a regular file to Syg, as to any program. Git cannot record
one, so a checkout of a pull request never holds one; only a process on the
machine can make one.

## Environment

| Variable | What it does |
|---|---|
| `SYG_TELEMETRY` | `off` (or `0`, `false`, `no`) turns the usage statistics and the update check off |
| `DO_NOT_TRACK` | any value but `0`, `false` or `no` turns them off too |
| `SYG_CONFIG_DIR` | where Syg keeps its settings and the queue of statistics to send; by default `syg` in your configuration directory (`~/.config/syg` on Linux, `~/Library/Application Support/syg` on macOS, `%AppData%\syg` on Windows) |
| `NO_COLOR` | any value turns colour off, as `--no-color` does |
| `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` | the proxy for what Syg fetches: the statistics, the update check, and `schema vendor --from` an https URL |
| `SSL_CERT_FILE`, `SSL_CERT_DIR` | on Linux, the certificate authorities to trust in their place; macOS and Windows use the system's |
| `KUBECONFIG` | the kubeconfig `syg snapshot` reads, unless `--kubeconfig` names one |
| `CI`, `GITHUB_ACTIONS`, `GITLAB_CI`, ... | a CI run: statistics carry no installation ID and are sent at exit, and there is no update check |

The [network page](network.md) says what each connection is, and how to run
Syg with none.

Findings are coloured only when they go to a terminal, and never with
`NO_COLOR` or `--no-color`. On Windows, Syg turns on the console's processing
of colour for the time it runs, and colours nothing on a console older than
Windows 10, which has none. Colour never carries meaning on its own: each
finding starts with its severity in words (`error`, `warning`, `info`), and
points at its line with text. Syg never moves the cursor or redraws a line, so
a screen reader reads its output as it is printed. For tools, `--format json`,
`sarif` and `github` carry the same findings.

## syg.yaml

Optional, beside the module's files. Paths in it (`snapshots:`, `baseline:`)
are relative to the directory that holds it; paths given as flags
(`--snapshot`, `--baseline`, `-o`) are relative to where you run `syg`.

A path in `syg.yaml` stays inside the git repository that holds the module (or
the module's directory, outside a repository), and names a regular file or
directory, not a link (a symbolic link, or on Windows a junction). Checking a pull request then reads nothing else
on the machine. A file elsewhere is named with the flag, which is followed as
any [path you name](#paths) is.

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
