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

**Not a rule.** A `baseline` note says that `CHK-SEL-005` and `CHK-GEN-002`
compared nothing:

- **No baseline:** no previous output was found to compare against, so they
  did not run. Give one with `--baseline PATH`, syg.yaml's `baseline:`, or
  build into the previous output directory with `syg build -o DIR`
  (`syg explain CHK-SEL-005`).
- **A baseline of something else:** the baseline given holds none of the
  objects this build emits. The rules match an object by its kind and name, so
  another module's output, or the wrong directory, passes them as an empty
  baseline would. Point the baseline at this module's own previous manifests,
  and for an environment, at that environment's.

## config

**Not a rule.** A `config` note lists the rules `syg.yaml` turned off, which
therefore did not run. It is in every check that runs without them, in every
output format, as the notes for rules skipped without a snapshot or a baseline
are: a check that did not run a rule did not pass it. A pull request that turns
a rule off shows the note in its own check, beside whatever the rule would have
found.

### What syg.yaml can change
- A DETECTED rule can be turned off, or given another severity (`error`,
  `warning` or `info`), under `rules:`. A rule at another severity still runs,
  and its findings show at that severity.
- A PREVENTED rule cannot be configured: it is what the language means, not a
  setting.

### What to do
If the rule should run, take it out of `rules:`. To see what it finds without
failing the check, set it to `warning` instead of `off`.

## env

**Not a rule.** An `env` error means an environment tries to change something
it may not: the graph's structure (adding a port, a dependency, a policy), a
value a profile locks, or a secret's values.

### Why
An environment changes values, never structure, so every environment is
checked against the same set of resources. Structural
differences belong in the base declaration, or in a profile.

## limit

**Not a rule.** A `limit` error means an input is larger than Syg reads, a
module is more than Syg compiles in one run, or a file kept producing errors
past the point where more of them would help.

### The limits
- **A `.syg` file:** at most 8 MiB.
- **A compilation's source:** the module and everything it imports, at most
  64 MiB of `.syg` source together.
- **A compilation's work:** at most 200,000 items. An item is a declaration,
  or one thing written in one: an `image`, a `port`, an `env`, a key of a
  config, an entry of `labels`, a probe, a number, a line of a raw object's
  YAML. A workload counts nine more, for what Syg derives from it: a
  Deployment, StatefulSet or Job, with its pod template, costs more to build
  than anything a workload says. The count covers the module and everything
  it imports, with each profile's items counted again in every workload that
  uses it, and it is taken once for the base and once for each environment,
  since each is compiled on its own. 200,000 items is about 5,000 services as
  full as the ones in the language reference, or 1,000 with four
  environments, and at most 18,181 workloads.
- **A string:** at most 1.5 MiB. etcd refuses a request larger than that, so no
  Kubernetes object can hold a longer value.
- **A snapshot, a baseline manifest, a vendored CRD schema:** at most 64 MiB
  each, and so is what `syg schema vendor` reads from one URL: a larger
  response is refused, not cut. `syg.yaml` and `syg.lock`, at most 1 MiB.
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

Bytes alone do not bound the work. 100,000 minimal services fit in 10 MB of
source and took 5 GB of memory to build; a profile of 5,000 items used by 400
workloads is a 111 KB module that took 3.4 GB. Nor do the lines of source: a
service that says only its image derives a Deployment of a hundred lines, and
100,000 of them, in 5.8 MB, took 3.6 GB. Within all of these limits, the
largest checks measured take about 0.5 GB of memory, and the largest builds
about 1.3 GB.

### What to do
Split a module that is genuinely this large into modules that are each built
on their own: an imported module counts toward the module that imports it,
and is not deployed by it. A profile used by many workloads adds its items to
each, and each environment compiles the module again. A value longer than
1.5 MiB belongs in a volume or an image, not in a ConfigMap.

## module

**Not a rule.** A `module` error concerns the module graph: an import that is
not on disk (imports resolve offline only, from a relative path or `vendor/`),
an import cycle, or an imported module missing from `syg.lock` or changed since
it was pinned.

It is also the error for what a module may not make Syg read, so that checking
a pull request reads nothing else on the machine running the check:

- **A file that is not a regular file.** A `.syg` file, a `schemas/` directory
  or a file in `vendor/` that is a link (a symbolic link, or on Windows a
  junction) is an error, and its target is not read: a link committed in a
  pull request could otherwise point at any file the machine can read, and its
  first line would appear in an error.
- **A link out of the repository, on a path you name.** A path named on the
  command line, and one Syg writes to (`build -o`, `syg.lock`, `vendor/`,
  `schemas/`, `snapshot -o`), follows a link only to somewhere in the same
  repository: a link the repository holds that leads out of it could have come
  with the pull request, and is refused, unread and unwritten. A link outside
  every repository, yours or the system's, is followed.
- **An import that leaves the repository.** An import is a directory relative
  to the importing module (`./x`, `../platform`), or a vendored module's name.
  An absolute path, a name with `..` in it, or a relative path that ends
  outside the git repository holding the module (links resolved, a `vendor/`
  that is a link included) is an error. So is an import spelled otherwise than
  its directory: macOS and Windows find `../Platform` for `platform`, Linux
  does not, and the module would check on one and fail on the other.

An import brings in a module's types, profiles, schemas and relations, not
what it deploys: its resources are emitted and checked by its own build, and
the import says so (`syg explain coverage`).

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
`syg schema vendor`), a header that disagrees with the body, a name the API
server refuses for the kind, or a kind that can never be written raw: a
Secret, whose values never live in source. That holds for a kind named Secret
in any group, since only the core group serves one, and
`evil.example/v1/Secret` would carry its values into source all the same.

### Names
A raw object's name follows the API server's rule for its kind, as checked on
Kubernetes 1.32:

- most kinds, and every custom resource: a DNS subdomain, lowercase letters,
  digits, `-` and `.`, at most 253 characters;
- a Service: a DNS label that starts with a letter, at most 63 characters,
  since it becomes a DNS name of its own;
- a Namespace: a DNS label, at most 63 characters;
- a Job: at most 63 characters, since its name is a label on its pods, unless
  it picks its pods itself (`spec.manualSelector`); a CronJob: at most 52,
  since every Job it starts is named after it with 11 characters added;
- a Role, ClusterRole, RoleBinding, ClusterRoleBinding or
  CertificateSigningRequest: any name but `.` and `..`, without `/` or `%`.
  Upper case is allowed.

Each object is written to its own file, `KIND-NAME.yaml`, so two objects that
would share one are an error, since the second would silently replace the
first: two RBAC names that differ only in case, which macOS and Windows
filesystems ignore by default, and one kind's name in two API groups (Istio's
`Gateway` and the Gateway API's) under one name. A name too long for a file's
name (more than 255 bytes with its kind) is cut, with a hash of the whole name
added, so it is still a file of its own.

### What to know
A raw object is passed through unmodelled. Checks that must see every object of
its kind report reduced coverage for it (`syg explain coverage`), and a
`relate` declaration can tell Syg what its fields mean (`syg explain crd`).

Three rules read inside a raw object, so that the escape hatch is not the way
around them: `CHK-RBAC-003` reads raw RBAC for wildcards and bindings to
cluster-admin, `CHK-SEC-002` reads a raw pod spec for what reaches into its
node (a privileged container, a host namespace, a hostPath volume, a host
port), and `CHK-SEC-003` for what it asks of the kernel (capabilities, seccomp,
AppArmor, SELinux, sysctls). A pod spec is a built-in kind's, where its schema
puts it, or any mapping in a custom resource with a list of containers or of
init containers, wherever it is, as an Argo Rollout's `spec.template.spec`. A NetworkPolicy is read by `CHK-NP-002`,
and the fields a `relate` declares by the relation checks.

A raw object in an imported module is type-checked by the module that imports
it, and neither emitted nor judged there: it belongs to its own module's build,
and the import says so.

## relate

**Not a rule.** A `relate` error concerns a statement about a custom resource
kind: a field path the kind's schema does not have, a relation phrase that does
not exist, two contradictory relations on one field, or one relation declared
twice in a module, which counts once.

A relation the module declares that an imported library also declares gets a
note rather than an error: the two are one relation, and a library that comes
to declare what the module already does must not break its build. Delete the
module's own to rely on the import's, or keep it so that the relation holds
without the import.

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
carry their unit (`500m`, `512Mi`) and are what Kubernetes counts: CPU in whole
millicores, memory and storage in whole bytes. Names are lower-case DNS labels;
durations are `10s`, `5m`.

