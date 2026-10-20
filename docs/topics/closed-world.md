# closed-world: what Syg's checks are claims about

**Not a rule.** The scope of every check that runs without a cluster.

## The closed world
A compilation's closed world is exactly:

- the declarations of the module being compiled;
- the declarations reachable through its transitive imports;
- its `extern` declarations.

Nothing else. `syg check --print-world` lists it.

## What a clean result means
A Tier-1 check proves a property *of the closed world*, never of a cluster.
"No route points at a missing Service" means no route in the module points at
a Service the module does not declare or declare `extern`. It says nothing
about objects someone else applied to the namespace.

## Where the world is known to be incomplete
Syg says so, rather than reporting a clean result it cannot vouch for:

- **A `raw` object** is passed through unmodelled. A check that must see every
  object of its kind reports *reduced coverage* for it (`syg explain
  coverage`). A raw NetworkPolicy is the exception: Syg reads it.
- **An `extern` declaration** is trusted, not verified. Its keys, ports and
  namespace are taken at their word. A snapshot can verify them
  (`CHK-T2-EXT-001`), and a check that judges both ends of a path checks only
  the module's end of one that reaches an extern (`CHK-NP-002`).
- **Facts about a running cluster** are Tier 2: they need a snapshot, and are
  reported as skipped without one. They include whether a storage class exists,
  whether pods fit the nodes, and whether the network plugin enforces policy.
- **Properties no source can settle** are Tier 3, and are never checked
  (`syg explain tier3`).

## Why bounded is not useless
A type system that cannot see untyped code becomes bounded, not useless. The
failure to avoid is *undeclared* incompleteness. Syg makes the boundary
explicit, enumerable and reported, so you know what was proven and what was
not.
