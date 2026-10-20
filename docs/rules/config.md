# Config and secrets

Keys that do not exist, variables defined twice, configuration nothing reads.

## missing-key

`CHK-CFG-003` · error · checked offline

The container starts with the variable unset, or crashes on first use (which of the two depends on how the value is consumed), and neither points at the missing key.

### What you see

This is the nastier sibling of `CHK-CFG-001`, because it does not stop the pod.

What happens depends entirely on how the value is consumed, and neither outcome
points at the missing key:

- **Consumed as an environment variable with `configMapKeyRef`**: by default the
  container fails to start, which at least surfaces promptly. But if the reference
  is marked optional, or if the key is absent from a whole-object `envFrom`, the
  container starts with the variable simply *unset*.
- **Read by application code with a fallback**: the code sees an empty string and
  takes its default path. A `LOG_LEVEL` that silently defaults is harmless. A
  `FEATURE_FLAG` that silently defaults to off, or a `TIMEOUT` that defaults to
  zero, is an incident whose cause is invisible in every manifest and every log
  line.

The failure is therefore *quiet and delayed*, and when it is finally noticed the
investigation starts from the behaviour rather than from the configuration.

### Why it happens

A `configMapKeyRef` or `secretKeyRef` names both an object and a key within it.
The object reference is resolved by the kubelet at container creation; the key
lookup happens at the same moment. A missing key causes container creation to fail
*unless* the reference sets `optional: true`, in which case the variable is omitted
and the container starts normally.

With `envFrom`, every key in the object becomes a variable. There is no declaration
of which keys the container expects, so a key that was renamed or never added
produces no error anywhere: the variable is simply not in the environment.

### What Syg catches

`needs config settings as LOG_LEVL` where the config declares `LOG_LEVEL`.

The object exists. The reference to it is fine. The *key* is wrong.

### Why Syg checks rather than prevents

Because the two sides are genuinely separate declarations, and the key set is data
rather than structure.

`CHK-CFG-001` is preventable because the *object* reference can be a resolved
pointer: there is one node, and pointing at it is all that is required. A key is
different: it is one string chosen from a set that the referenced declaration
defines, and the reference site names it directly because naming it is the point.
Making it a pointer would mean the language had a separate syntactic form for every
key, which is not a language anyone would want to write.

So Syg checks it, and can check it exactly because the key set is declared:

```syg
config settings { key LOG_LEVEL = "info" }
```

The diagnostic lists the keys that *are* declared, which is usually enough to see
the typo without opening the other file.

**Where this check runs matters.** It is implemented over the resource graph rather
than over the AST, using `Workload.AllContainers()`. That is deliberate: an
AST-walking version has to remember to visit init containers and sidecars
separately, and forgetting one is silent. An init container that references a
key that does not exist must fail compilation like any other container, so the
traversal that cannot forget is the one worth having.

### Kubernetes versions

Verified against the kubernetes.io documentation for ConfigMaps and Secrets as
environment variables, including the `optional` field's effect on missing keys
(checked 2026-08).

### What Syg does not claim

Where no keys are declared, there is nothing to check against, and Syg says
nothing. That is the normal shape of an `extern config` whose keys the author chose
not to enumerate. Asserting a key is missing when the key set was never known
would be a false positive dressed as certainty.

Where keys *are* written down, extern or not, they are the contract and the
reference is held to them.

Syg also does not check values. A key that exists but holds an empty string, or a
malformed URL, is outside what a compiler can see.

### Further reading

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/
- https://kubernetes.io/docs/concepts/configuration/configmap/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

### Where this stops

Whether a config or secret's VALUES are correct (a database URL that resolves, a certificate that matches its key) is a runtime fact, and secret values are deliberately absent from source. Syg checks that the object exists and that every key referenced is declared, and nothing about the content.

## duplicate-env-var

`CHK-CFG-005` · warning · checked offline

One definition silently wins and the other is discarded, so the running value is not the one the reader of the source expects.

### What you see

The running value is not the one the source appears to set.

Someone adds an override for `DATABASE_URL` at the top of a service, not noticing
that a `needs secret ... as DATABASE_URL` further down defines the same name. One
of them wins. Which one is determined by list order, which is determined by the
order Syg emits them, which is not something the author was thinking about.

The debugging experience is unusually bad because the source contains the correct
value. It is right there, visible, apparently applied. `kubectl describe pod` shows
both entries. Only reading the container's actual environment reveals which one
took effect, and by then the assumption "the manifest says X, so the value is X"
has usually cost an hour.

### Why it happens

`spec.containers[].env` is a list, not a map. The API server does not reject
duplicate names in it. When the kubelet constructs the container's environment, it
processes the list in order, and a later entry with the same name overwrites an
earlier one.

`envFrom` interacts with this too: keys from `envFrom` sources are applied first,
and explicit `env` entries take precedence over them. So a variable arriving from a
whole-object `envFrom` can be silently replaced by an `env` entry with no
indication that anything was overridden.

No warning is produced at any layer. Duplicate names are legal.

### What Syg catches

One container defining the same environment variable name twice: from two literal
`env` entries, or from a literal and a `needs ... as NAME` that collide.

### Why Syg checks rather than prevents

Syg could plausibly make this unrepresentable by treating a container's environment
as a map keyed by name, where a repeated key is a parse-level duplicate.

It does not, because the collision usually spans *different constructs*: a literal
`env` and a keyed `needs`, which are separate items with different shapes and
different purposes. Unifying them into one namespace at the syntax level would
either forbid legitimate patterns or produce a confusing error at a place where
only one of the two declarations is visible.

Reporting it, with the container named and both sources implicated, gives the
author the whole picture at once. Severity is `warning` rather than `error` because
an intentional override (a base set plus a deliberate replacement) is a real
pattern, even if it is one better expressed another way.

### Kubernetes versions

Verified against the kubernetes.io container environment documentation and the
`EnvVar` API reference, which define `env` as an ordered list and specify that
`env` entries take precedence over `envFrom` (checked 2026-08).

### What Syg does not claim

Syg compares names it can see: literal `env` entries and keyed `needs`. It cannot
see the keys inside a whole-object `envFrom` unless that object declares its keys,
so a variable arriving from an undeclared `extern config` can still collide with a
literal without being reported.

It also does not judge which of two definitions was intended. The diagnostic says
the name is defined more than once and that one silently wins; choosing is the
author's.

### Further reading

- https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/
- https://kubernetes.io/docs/concepts/configuration/configmap/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`).

## unused-config

`CHK-CFG-006` · info · checked offline

Dead configuration accumulates and is maintained, reviewed, and rotated for no reason.

### What you see

None. This is hygiene, reported at `info`, and it should be read that way.

The cost is carried by people. Dead configuration is reviewed in every change that
touches the file, considered in every question about what a service reads, and
migrated forward indefinitely. For secrets it is worse than tidiness: an unused
secret declaration is still rotated, still audited, and still suggests to a reader
that some component depends on a credential that nothing actually uses.

The commoner cause is a half-finished removal. A feature was deleted, the code that
read `FEATURE_CONFIG` went with it, and the declaration stayed. The next person to
read the module cannot tell that from a declaration whose consumer is simply
somewhere they have not looked yet.

### Why it happens

None to describe, and that is the reason a compiler is the right place for this.
An unreferenced ConfigMap is a perfectly valid object. Kubernetes has no notion of
"unused" and no reason to acquire one: the object is well-formed, and something
outside the cluster's knowledge might read it at any time.

Seeing this requires knowing every container in the module and every reference each
one makes, which is a whole-graph property rather than a property of any object.

### What Syg catches

A `config` or `secret` declaration that no container in the module consumes.

### Why Syg checks rather than prevents

Refusing to compile an unreferenced declaration would make ordinary work
unpleasant. Writing the config before the service that consumes it is a natural
order, and an author mid-change should not be blocked by an incomplete module.

It is also not reliably a mistake. A config may be consumed by a workload in
another module sharing the namespace, or kept deliberately through a migration. At
`info`, the diagnostic says "worth a look" without asserting anything is wrong.

Syg does not emit manifests for unreferenced config: `ownedRefs` in the graph
builder gates emission on actual consumption. Reporting dead configuration and then
creating it anyway would be incoherent.

### Kubernetes versions

Not version-dependent. This concerns relationships between declarations in a
module, not Kubernetes behaviour.

### What Syg does not claim

Syg sees one module. A config unused here may well be consumed by something
outside it, and the diagnostic scopes its claim accordingly: nothing in *this
module* references it.

It also cannot see consumption that does not go through a declared reference, such as an
application that reads a ConfigMap through the Kubernetes API at runtime, rather
than having it mounted, is invisible to this check by construction.

### Further reading

- https://kubernetes.io/docs/concepts/configuration/configmap/
- https://kubernetes.io/docs/concepts/configuration/secret/

### Scope

A claim about the closed world: this module, the modules it imports, and its extern declarations, which are trusted, not verified. It says nothing about objects others apply to the cluster (`syg explain closed-world`). It assumes it sees every object of its kind, so a raw object it cannot see into is reported as reduced coverage (`syg explain coverage`).

