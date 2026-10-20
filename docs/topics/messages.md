# Other messages

Findings whose code is not a rule's: what each one means, and what to do about it. `syg explain CODE` prints the same.

## api

**Not a rule.** An `api` error is the API server's validation, run before the
apply: a combination of fields Kubernetes refuses even though each one is
well-formed.

### What to do
The message names the field and the constraint. Its consequence is the
refusal itself, at apply time, so fixing the source is the only remedy.

## baseline

**Not a rule.** A `baseline` note says that `CHK-SEL-005` and `CHK-GEN-002` did
not run, because no previous output was found to compare against. Give one with
`--baseline PATH`, syg.yaml's `baseline:`, or build into the previous output
directory with `syg build -o DIR` (`syg explain CHK-SEL-005`).

## env

**Not a rule.** An `env` error means an environment tries to change something
it may not: the graph's structure (adding a port, a dependency, a policy), a
value a profile locks, or a secret's values.

### Why
An environment changes values, never structure, so every environment is
checked against the same set of resources. Structural
differences belong in the base declaration, or in a profile.

## limit

**Not a rule.** A `limit` error means an input is larger than Syg reads, or a
file kept producing errors past the point where more of them would help.

### The limits
- **A `.syg` file:** at most 8 MiB.
- **A compilation:** the module and everything it imports, at most 64 MiB of
  `.syg` source together.
- **A string:** at most 1.5 MiB. etcd refuses a request larger than that, so no
  Kubernetes object can hold a longer value.
- **A snapshot, a baseline manifest, a vendored CRD schema:** at most 64 MiB
  each; `syg.yaml` and `syg.lock`, at most 1 MiB.
- **Syntax errors:** after 50 in one file, Syg stops reporting the rest of
  that file's. The first ones are the ones to fix; the others usually follow
  from them.
- **The language server:** a message from the editor is at most 64 MiB, and
  its header at most 16 lines of 1 KiB.

### Why there are limits
A real module is far smaller than any of these. They are there so that an
input that is not one, such as a pull request written to exhaust the machine
that checks it, costs a bounded amount of memory and output: `syg check` is
meant to be safe to run on code nobody has reviewed yet.

### What to do
Split a module that is genuinely this large into modules that import each
other. A value longer than 1.5 MiB belongs in a volume or an image, not in a
ConfigMap.

## module

**Not a rule.** A `module` error concerns the module graph: an import that is
not on disk (imports resolve offline only, from a relative path or `vendor/`),
an import cycle, or an imported module missing from `syg.lock` or changed since
it was pinned.

It is also the error for what a module may not make Syg read, so that checking
a pull request reads nothing else on the machine running the check:

- **A file that is not a regular file.** A `.syg` file, a `schemas/` directory
  or a file in `vendor/` that is a symbolic link is an error, and its target is
  not read: a link committed in a pull request could otherwise point at any
  file the machine can read, and its first line would appear in an error. The
  path you name on the command line is yours, and is followed.
- **An import that leaves the repository.** An import is a directory relative
  to the importing module (`./x`, `../platform`), or a vendored module's name.
  An absolute path, a name with `..` in it, or a relative path that ends
  outside the git repository holding the module (links resolved, a `vendor/`
  that is a link included) is an error.

### What to do
Vendor a module from outside the repository: `syg mod get DIR` copies a
checked-out module into `vendor/` (regular files only) and pins it; `syg mod lock`
pins what is on disk after you have reviewed a change; `syg mod tidy` drops
pins nothing imports.

## profile

**Not a rule.** A `profile` error comes from expanding a golden path into a
workload: a parameter missing or of the wrong kind, an item the profile locks
being overridden, or an item the profile requires being absent.

### What to do
The secondary span points at the profile line involved. A locked item is the
platform team's decision: change it in the profile, not in the workload. A
required item must be declared on the workload (`syg init --profile` lists
them).

## raw

**Not a rule.** A `raw` finding concerns an escape-hatch object: YAML that does
not decode against its kind's schema (built-in, or vendored with
`syg schema vendor`), a header that disagrees with the body, or a kind that can
never be written raw (a Secret, whose values never live in source).

### What to know
A raw object is passed through unmodelled. Checks that must see every object of
its kind report reduced coverage for it (`syg explain coverage`), and a
`relate` declaration can tell Syg what its fields mean (`syg explain crd`).

## relate

**Not a rule.** A `relate` error concerns a statement about a custom resource
kind: a field path the kind's schema does not have, a relation phrase that does
not exist, or two contradictory relations on one field.

### What to know
`syg explain crd` describes what a relate tells Syg, and which bundled
libraries (`syg.vishisht.tech/relate/...`) already describe common operators.

## resolve

**Not a rule.** A `resolve` error means a reference names nothing, or names the
wrong kind of thing: a port the workload does not declare, a policy that is a
config, a profile that does not exist, a duplicate declaration.

### Why it is an error
In Syg every reference is a resolved pointer: a Service's backend, a mount's
ConfigMap, a binding's ServiceAccount, a policy's peers. The emitted YAML is
derived from what the name resolved to, so a name that resolves to nothing has
nothing to derive from. Hand-written YAML would carry the dangling string to the
cluster, where it fails later and quietly.

### What to do
The message names the nearest declaration when one is close ("did you mean
`settings`?"). A name in another module is written `alias.name`, and only
cluster-scoped names cross a module boundary (`syg explain CHK-CFG-004`).
Something that exists outside the module is declared `extern`
(`syg explain closed-world`).

## snapshot

**Not a rule.** A `snapshot` note says whether the rules that need a cluster
ran: skipped for want of a snapshot, or run against the snapshot it names,
with its age.

### How the cluster checks run

Some rules need facts only a real cluster has: its storage classes, the
custom resource kinds it serves, its gateways, its nodes and their capacity,
its network plugin. Syg never asks a live cluster while checking. It reads a
snapshot you capture with `syg snapshot -o FILE` and commit beside the module,
so a check gives the same answer on your laptop and in CI. Name it in
`syg.yaml` (`snapshots:`, per environment or `default`), or pass `--snapshot
FILE`.

- **Without a snapshot,** those rules are listed as skipped. A skip is never a
  pass, and the build still succeeds.
- **With one,** every finding names the snapshot and its age.
- **A snapshot older than `snapshotMaxAge`** (default 30 days) gets a warning
  naming when it was captured.

### What it does not claim

That the cluster still looks like the snapshot. A snapshot records one
moment: a node drained, a class deleted or a custom resource definition
upgraded since then is not in it. Capture a new one before a check that
matters, and keep `snapshotMaxAge` short enough that a stale one is reported.

### Further reading

- [Snapshots](../checks.md#snapshots): what a snapshot records,
  the permissions `syg snapshot` needs, and how to name one.
- `syg explain tier3`: what no snapshot can tell.

## syntax

**Not a rule.** A `syntax` error means the parser met a token it did not expect
where it was, or the file is not text Syg reads: a `.syg` file is UTF-8, and
the error for one that is not points at its first byte that is not (save the
file as UTF-8; a byte order mark is fine).

### What to do
- Read the caret: it points at the first token that does not fit. The mistake
  is usually there or just before it: a missing `{` or `}`, a missing comma
  inside a block, or a string without its closing quote.
- The message says what was expected ("expected a port reference like
  :http"). The language reference lists every construct and its form
  (`syg fmt` writes the canonical form of anything that parses).
- One mistake can confuse what follows: fix the first error and check again.

### What Syg does meanwhile
The parser recovers at the next declaration, so the rest of the file is still
checked, but rules that need the broken declaration do not run on it.

Tokens that nothing accepts, one after another on a line, are one mistake, and
one error underlines them all. After 50 errors in one file Syg stops
reporting that file's (`syg explain limit`): the first ones are the ones to
fix.

## type

**Not a rule.** A `type` error means a value has the wrong shape or is out of
range: memory written as a CPU quantity, a port above 65535, a name the API
server would refuse, an image reference that does not parse.

### Why it is checked here
These are the API server's own validations, applied to the source. The
alternative is an apply that fails in CI or, worse, in the cluster, pointing at
generated YAML instead of the line you wrote.

### What to do
The message says what the field takes and quotes what was found. Quantities
carry their unit (`500m`, `512Mi`); names are lower-case DNS labels; durations
are `10s`, `5m`.

