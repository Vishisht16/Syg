# Non-goals

What Syg will not do, by design, and the failure each refusal prevents.

1. **Deploying, applying, or mutating cluster state.** Syg is a compiler; delivery stays with the existing pipeline. *(Prevents: the adoption wall of "replace your GitOps".)*
2. **Runtime or admission-time enforcement.** No webhook, no operator, no agent. *(Prevents: reimplementing the API server.)*
3. **A general-purpose configuration or programming language.** No user functions, loops, or arbitrary expressions. *(Prevents: losing whole-graph analyzability, which is the entire value proposition.)*
4. **Claiming undecidable properties.** No probe-timing, HPA-metric-fitness, eviction-risk, or secret-content judgments.
5. **Unbounded whole-graph verification.** All claims are scoped to a declared closed world.
6. **Simulating controllers or CRD semantics.** CRD support is declared-relationship-based only.
7. **Cluster provisioning or infrastructure (Terraform's domain).** Syg describes workloads, not clusters or cloud resources.
8. **Multi-cluster scheduling or placement decisions.**
9. **Being first-of-its-kind.** Several checks exist in KubeLinter and Polaris today; Syg's claim is prevention-by-construction, source-located diagnostics, graph-level reasoning and explanation, not novelty.
10. **Secret value management.** Syg declares keys and consumption shape; values belong to a secrets manager.
11. **Displacing Helm/Kustomize as packaging formats.** Syg emits into them.
