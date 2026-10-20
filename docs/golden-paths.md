# Golden paths

A platform team usually wants every service to start from the same decisions:
non-root, a read-only filesystem, a disruption budget, sensible requests, a
rolling update that never drops below capacity. Syg expresses that as a
**profile** in a module the platform team owns, which application modules
**import** and **use**. Each application then varies what it needs per
**environment**.

## A profile

```syg-fragment
module acme.platform

profile web(image, port) {
  image $image
  port http $port

  locked runAsNonRoot true
  locked readOnlyRootFilesystem true

  required identity
  required disruption

  default replicas 3
  default resources { cpu 200m, memory 256Mi }
  default health {
    ready GET :http /readyz
    live  TCP :http
  }
  default rollout { strategy rolling, maxUnavailable 0, maxSurge 1 }
}
```

A profile takes parameters (`$image`, `$port`) and contributes items to every
workload that uses it, each in one of four modes:

- **unmoded** (`image $image`): set from the consumer's arguments.
- **`default`**: a value the workload may replace with its own.
- **`locked`**: a value nothing may change, neither the workload nor an
  environment. An attempt is an error naming the profile.
- **`required`**: a declaration the workload must make itself: here an
  identity and a disruption budget. `required digest` requires every image to
  be pinned by digest.

## Using it

```syg-fragment
module payments

import "../platform" as platform

identity payments-api {
  may get on configmaps
}

service api {
  use platform.web(image: "registry.example.com/payments:2.1.0", port: 8080)
  identity payments-api
  disruption { maxUnavailable 1, evictUnhealthy true }
  internal :http
}
```

The workload gets the profile's items, and adds its own. Overriding a locked
item, or leaving out a required one, is an error at the `use` line:

```console
error[profile]: profile acme.platform/web requires identity, and api declares none
error[profile]: runAsNonRoot is locked by profile acme.platform/web
```

`syg why payments deployment/api spec.template.spec.containers[0].securityContext.runAsNonRoot`
says the value came from the profile, locked, at its line; the editor's hover
says the same.

## Imports and pinning

`import "../platform"` names a module by a relative directory, which must be
inside the git repository that holds the application. A module from elsewhere
is vendored into `vendor/` with `syg mod get DIR`, from a checkout you fetched
yourself; checking and building never need the network, and never read outside
the repository.

Every import is pinned by content hash in `syg.lock`:

```console
$ syg mod lock payments
syg: pinned 1 module(s) in payments/syg.lock
```

If the platform module changes, the application's check fails until someone
re-pins it deliberately, so a platform change never lands in an application
unreviewed. `syg mod tidy` adds pins for new imports and drops unused ones, but
never re-pins a changed module.

## Environments

```syg-fragment
module payments

environment staging {
  api {
    image tag "2.2.0-rc1"
    replicas 2
  }
}

environment prod {
  namespace "payments"
  api {
    replicas 6
    resources { cpu 500m, memory 512Mi }
  }
}
```

An environment changes values only: replicas, image tag or digest, resources,
scaling, budget, rollout, exposure, environment variables, labels and
annotations, and its own configs. It cannot add a workload or change what a
profile locked. Its namespace is the one it declares, or `MODULE-ENV`
(`payments-staging`).

Each environment is checked as its own graph, so an override that breaks a
rule is found where it is written. Had the budget above been `minAvailable 2`,
staging's two replicas could never be evicted:

```console
error[budget-blocks-eviction]: disruption minAvailable 2 requires at least 2 of 2 replicas to stay available
  --> app.syg:12:3
     |
  12 |   disruption { minAvailable 2, evictUnhealthy true }
     |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  --> environments.syg:6:5
    |
  6 |     replicas 2
    |     ^^^^^^^^^^ effective replicas = 2
   = environment: staging
   = consequence: no pod can ever be voluntarily evicted, so node drains hang indefinitely and cluster upgrades stall
   = help: set minAvailable to at most 1 so at least one pod can be evicted
```

## Building environments

`syg build payments --env prod -o out/` builds one environment. For GitOps,
build all of them at once:

- `--target kustomize` writes a base and an overlay per environment, and
  `kustomize build overlays/prod` gives exactly what `--env prod` does.
- `--target argo --argo-repo URL` writes a directory and an Argo CD
  Application per environment.

A test in this repository builds every environment through all three and
requires them to agree, object for object.
