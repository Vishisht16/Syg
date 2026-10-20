# Chapter 13: Why YAML Hurts

Here is a number that ought to be surprising and is instead completely ordinary: a
single production web service (one program, doing one job) typically requires
something on the order of **four hundred lines of configuration** before it can run
properly. Not four hundred lines of application code. Four hundred lines describing
*how to run* forty lines of application code.

You have now met almost every one of those lines and know what it is for. That is the
point of Chapters 5 through 12 (containers, reconciliation, the control plane,
workloads, networking, resources, availability, and configuration), and it is why this
chapter can be honest rather than merely complaining. The configuration is large
because *the problem is large*. Every field you would remove corresponds to a real
mechanism that a real failure taught someone to configure.

But size is not the same as pain, and it is worth being precise about which one we
are diagnosing. Plenty of large configurations are perfectly pleasant to work with.
The pain here has three specific sources, and only one of them is the format's fault.

## Source one: the same value, written in many places

Go back to the service from Chapter 9. To make it work you write a name in the
workload's selector; the same name in the Pod template's labels; the same name again
in the Service's selector; again in the disruption budget's selector; again wherever a
network policy selects it; and again, as a string, wherever something routes traffic
to it.

Six places. One idea. And nothing anywhere verifies that the six agree.

This is the deep structural problem, and it is not really about YAML at all; it is
about a data model in which the *relationships* between objects are expressed as
strings that happen to match. As Chapter 7 put it, the cluster is a stringly-typed
graph. Any configuration format that faithfully represents that model inherits the
problem: you will be writing the same value repeatedly, by hand, with no mechanism
checking your work.

Everything else in this chapter is a response to this one fact.

## Source two: environments multiply everything

You do not have one configuration. You have the development version, the staging
version, and the production version, differing in perhaps six values: the image tag,
the replica count, the resource sizes, the hostname, a couple of feature flags.

The obvious approach is to copy the directory three times. And it works, briefly,
until the copies drift: someone fixes a bug in production's configuration and forgets
staging, and now staging no longer tests what production runs, which is the entire
purpose of staging. What you actually want is to say "production is like the base,
except these six values", which is not a thing plain YAML can express, because YAML
has no concept of "like that, but different."

## Source three: the format itself

And now, briefly, YAML's own contribution. It is real but smaller than its reputation.

YAML is **whitespace-significant**, so an indentation mistake changes meaning rather
than producing a syntax error, and a misplaced key can quietly land in the wrong
block. It has surprising type coercion, the famous case being that unquoted `no`,
`yes`, `on`, and `off` were interpreted as booleans in YAML 1.1, which is why a
country code like `NO` could become `false`. It is easy to write and hard to *review*:
a deep nested block of pure data offers a reviewer no place to attach meaning.

But, and this matters for judging the alternatives, swapping YAML for JSON or TOML
would fix approximately none of the pain in sources one and two. The format is the
least of it.

## What people built, and what each one actually fixes

Four broad families of tool exist, and the useful way to hold them is by *which
source* each attacks.

### Templating: Helm

**Helm** treats configuration as text templates with variables filled in: you write
your YAML with placeholders, supply a values file, and Helm renders the final
manifests. It packages the result as a versioned, shareable **chart**, which is
genuinely valuable: it is how most third-party software is distributed for
Kubernetes, and installing a complex system in one command is not nothing.

What it fixes: source two, mostly. Different values per environment becomes easy.

What it does not fix: source one, at all. You are still writing that same name in six
places, now with the added indirection that they are six templated references, and
you must verify by rendering that they still agree. And templating brings its own
problem: the template is manipulating *text*, not structured data, so it does not know
it is producing YAML. Get the indentation of an inserted block wrong and you generate
syntactically invalid or semantically wrong output. You are, in the end, writing a
text-generating program whose output happens to be a structured format, without the
tooling that either the program or the format would normally give you.

### Overlays: Kustomize

**Kustomize** takes the opposite approach: no templates, no placeholders. You write
plain, valid YAML as a *base*, then declare **overlays** that patch it: "production
is the base, with replicas set to 10 and this hostname." Because everything is real
YAML at every stage, your editor and validators work throughout, which is a real
improvement, and it is built into `kubectl`.

What it fixes: source two, more elegantly than templating.

What it does not fix: source one, again. And it introduces a characteristic problem of
its own: with patches applied across several layers, understanding what actually gets
deployed requires mentally executing the whole overlay chain. It is easy to end up
with an overlay that changes the *shape* of the thing rather than just its values, and
now reasoning about "what does production actually look like" requires running the
tool.

### Programming languages: jsonnet, CUE, cdk8s, Pkl

The next family says: if we are generating structured data, use a real language with
abstraction and types. **jsonnet** is a data templating language. **cdk8s** lets you
write TypeScript or Python. **Pkl** is a configuration language with types.

**CUE** deserves singling out, because it is the closest ancestor of the idea this
book ends on. CUE is built on *unification*: values and types are the same thing, and
combining two definitions produces their most specific consistent combination.
Concretely, that means you can define a value once and have it appear in many places
by construction: the six copies of a name become one definition unified into six
positions, and they cannot disagree, because they are not copies. **That is a genuine
attack on source one**, and the first one we have seen.

Its limitation is not the mechanism but the economics: CUE is general-purpose. It
knows nothing about Kubernetes. Every team adopting it must encode the Kubernetes
relationships (which fields must agree with which, what a valid disruption budget
looks like) themselves. The power is real; the burden of expressing this specific
domain in it falls on each user.

### Checking the output: KubeLinter, Polaris, kubeconform

The final family does not generate anything. It reads finished manifests and looks for
problems. **kubeconform** validates them against the official schemas. **Polaris** and
**KubeLinter** check for known bad patterns, and, notably, KubeLinter ships genuine
cross-resource checks: a Service whose selector matches no workload, a route pointing
at a nonexistent Service, a disruption budget that permits nothing.

Being straightforward about this matters: **these tools already catch several of the
failures these notes have described.** Any claim that checking cross-resource problems is
a new idea would be false, and the Syg project's own research measured exactly this,
running KubeLinter over a corpus of real-world configuration and finding near-total
agreement wherever it ships an equivalent check.

But post-hoc checking has a ceiling, built into its position in the pipeline, and the
ceiling has two parts.

**It reports at the wrong place.** These tools read *rendered* output: the thousands
of lines your templates produced. So a diagnostic points at line 4,300 of generated
YAML, which is not a thing you can edit. You then have to work backwards to whichever
template or overlay produced it. The further your authoring source sits from the
rendered output, the longer that walk.

**It arrives at the wrong time.** Checking output means the output must exist, which
means rendering, which means a build step: realistically in CI, minutes after you
committed, rather than in your editor as you typed.

And underneath both: **a checker can only ever detect. It cannot prevent.** It finds
the mismatch between your six copies of a name. It cannot stop there being six copies.

## The pattern across all four

Line them up and something clarifies:

| Family | Attacks | Leaves untouched |
|---|---|---|
| Templating (Helm) | environments | duplication, and adds text-generation hazards |
| Overlays (Kustomize) | environments | duplication |
| General languages (CUE, jsonnet) | duplication, genuinely | but you must encode Kubernetes yourself |
| Linters (KubeLinter) | detection after the fact | prevention; reports at generated output |

Nobody in this list is wrong. Each solves a real problem, and most production systems
use two or three together. But notice that the deepest problem (the same value
written in six places with nothing checking that they agree) is attacked by exactly
one family, and that family requires each team to build the Kubernetes-specific
knowledge itself.

That gap is where the last idea in these notes lives. Suppose you took CUE's insight
(derive many fields from one value so they cannot disagree) and specialised it to this
one domain, shipping the Kubernetes relationships rather than asking each team to
write them. Suppose the failures from Chapters 9 through 12 became things you could
not *express*, and the residue that genuinely cannot be designed away were reported at
the line you actually wrote, as you typed, with the mechanism explained.

That is the entire proposition of the final chapter.

## Where Syg stands

This chapter is Syg's competitive landscape, stated honestly. Syg is not the first
tool to detect dangling selectors: KubeLinter does, and does so accurately. Nor is
Syg the origin of the derive-from-one-value idea: CUE and Timoni got there first,
and they are its architectural precedent. What Syg claims is narrower
and, precisely because it is narrow, defensible: it makes cross-resource disagreement
unrepresentable **at the source a human actually wrote**, and it ships the Kubernetes
relationship model so that no team has to encode it. The next chapter is where those
claims get cashed.

## Read the source

- **Helm**: charts, templating, and releases: https://helm.sh/docs/
- **Kustomize**: overlays and patches:
  https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- **CUE**: unification, and why values and types are the same thing:
  https://cuelang.org/docs/concept/. And **Timoni**, which applies it to Kubernetes:
  https://timoni.sh/
- **KubeLinter**, including its cross-resource checks:
  https://docs.kubelinter.io/ · **Polaris**: https://polaris.docs.fairwinds.com/ ·
  **kubeconform**: https://github.com/yannh/kubeconform
- **The YAML specification**, if you want to understand the type-coercion history:
  https://yaml.org/spec/

---

*You now understand the machine, the ways it breaks, and every serious attempt to make
configuring it bearable. Everything is finally in place for the idea these notes were
written to explain.* → [Syg: prevention by construction](../notes/14-syg-prevention-by-construction.md)
