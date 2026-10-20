# crd: what Syg knows about custom resources

**Not a rule.** What Syg's support for custom resources is, and what it is not.

## The statement
**Syg's CRD support is declared-relationship-based, not semantic.** Syg knows
what a platform team tells it, and nothing more. It does not simulate
controllers.

## What Syg is told, and what it does with it
1. **The schema.** `syg schema vendor --from SRC` writes a
   CRD's OpenAPI schema into the module's `schemas/` directory. From then on,
   `check` validates every `raw` object of that kind against it, offline, with
   the field's path and the type the schema expects:
   - types, required fields, enums, patterns and bounds are checked;
   - unknown fields are errors with a suggestion;
   - CEL rules (`x-kubernetes-validations`) are **not** evaluated, and each
     object whose schema has them says so.
2. **The relationships.** A `relate` declaration says
   what a field means:

   ```
   relate networking.istio.io/v1 VirtualService {
     field spec.http[].route[].destination.host        references service
     field spec.http[].route[].destination.port.number references port of service
   }
   ```

   Paths use `[]` to traverse a list, and are checked against the schema where
   the relate is written. A path that does not exist, or a field that cannot
   hold what the relation reads, is a compile error citing the schema. Each
   value then becomes a `relates` edge in the graph, and these checks apply to
   it:
   - `CHK-REL-001`: the service, config, secret, identity or storage class it
     names exists;
   - `CHK-REL-002`: the port exists on that service;
   - `CHK-REL-003`: the selector matches something;
   - `CHK-REL-004`: a produced TLS secret covers the host it serves;
   - `CHK-REL-005`: one producer per name.

   A secret or config the resource `produces` becomes a name that
   `needs secret` resolves, with no `extern` standing in for it.
3. **Nothing else.** An unrelated custom resource is opaque. Its shape is
   validated if its schema is vendored, and every check that needs to see all
   objects of some kind reports reduced coverage for it (`syg explain
   coverage`).

## What Syg does not do
- **It does not know what a controller will do with an object:**
  - whether cert-manager can reach its issuer;
  - whether Istio's routing rules conflict;
  - whether a Rollout's analysis passes.

  A relation lets Syg read a field, not predict a controller.
- **It does not infer relationships.** A field nobody related is a value Syg
  carries and does not interpret, however obvious its meaning looks.
- **It does not check a relate against reality.** A relate that says a field is
  a service name, when the controller reads it as something else, makes Syg
  check the wrong thing confidently. Relates are platform code, and are
  reviewed like it.
- **It does not match across versions.** A relate names one apiVersion. An
  object of the same kind at another version is not related, and says so.

## Where relates come from
Write them in the module, or import a module that declares them. A relate
applies to every `raw` object of its apiVersion and kind in the module that
declares it, and in every module that imports it.

Syg bundles six such modules, with their CRD schemas:

```
import "syg.vishisht.tech/relate/gateway-api"          # HTTPRoute, GRPCRoute, Gateway
import "syg.vishisht.tech/relate/cert-manager"         # Certificate, Issuer
import "syg.vishisht.tech/relate/prometheus-operator"  # ServiceMonitor, PodMonitor
import "syg.vishisht.tech/relate/istio"                # VirtualService, DestinationRule, policies
import "syg.vishisht.tech/relate/argo-rollouts"        # Rollout
import "syg.vishisht.tech/relate/external-secrets"     # ExternalSecret
```

They are pinned in `syg.lock` like any import, so a Syg upgrade that changes
one is a reviewed change. `syg mod vendor NAME` copies one into `vendor/`,
where it takes precedence, to pin it or edit it.

A relation's reference resolves to the module's declarations, and to its raw
`v1` Services, ConfigMaps and ServiceAccounts.
