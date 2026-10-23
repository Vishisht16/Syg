# Performance

Measured, not estimated. Each figure below is held by a test that fails when it
regresses.

| Workload | Budget | Measured |
|---|---|---|
| `syg check`, cold, 200 services in one module | 5 s | 36 ms |
| editor: an edit to one file until its diagnostics arrive, 200 services in 20 modules | 200 ms median | 2.8 ms median, 3.6 ms p95 |
| the same, with all 200 services in one module | | 35 ms median, 42 ms p95 |
| `syg build -o`, 2,000 services in one module, each with a policy, a dependency, spread and avoid | 500 MB | **290 MiB** peak memory, **4.9 s**, 8,003 files |

The reference machine is a 4-core linux/amd64 container. The build is measured
as a separate process, so the memory figure is the operating system's, not the
Go heap's.

## Where the time goes

Checking and building grow linearly with the number of services: 0.47 s to
check the 2,000-service module, 4.9 s to build and write it. Of a build,
rendering YAML takes about 40% and writing the files about 30%. Every rule that
relates objects to each other, such as which Services select a workload, uses an
index built once per compilation, so no check grows faster than the module.

## The largest modules

The work of one compilation is bounded at 200,000 items (see the
[limits](cli.md#limits)). At that bound, the largest check measured takes
about 0.5 GB of memory, and the largest build about 1.3 GB, since a build holds
its whole output in memory before it writes the first file. On a CI runner with
less, set `GOMEMLIMIT` (as in `GOMEMLIMIT=512MiB`): the Go runtime collects
garbage more often to stay near it, which is slower, and keeps the peak lower.
