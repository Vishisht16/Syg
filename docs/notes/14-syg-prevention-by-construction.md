# Chapter 14: Syg: Prevention by Construction

Every failure in these notes has had the same shape.

A Service selecting labels no Pod carries: both objects valid, traffic refused
(Chapter 9). An autoscaler with no denominator because a container omitted a resource
request: both objects valid, no scaling, ever (Chapter 10). A disruption budget
demanding more copies than exist: both objects valid, maintenance deadlocked forever
(Chapter 11). A Role never bound to the identity that needs it: both objects valid,
`403` at the first API call, possibly months later (Chapter 12).

**Valid objects. Broken relationship. Silence.**

Not one of these is a malformed document. Every one passes schema validation, applies
cleanly, and displays as healthy. The error is never *inside* an object; it is in the
**edge between two objects**, and no object owns its edges, so no object's validation
can defend them.

That observation is the whole of this chapter. Once you take it seriously, a
particular kind of solution becomes obvious, and a particular kind of honesty becomes
mandatory.

## The question that changes everything

Faced with a recurring error, the reflex of our industry is to write a check for it.
That reflex produced the linters of Chapter 13, and they work, within the ceiling we
identified: they report on generated output, after a build, and they can only detect.

But there is a prior question, and asking it first changes the answer:

> **Can the language be changed so that this error cannot be written at all?**

Consider the dangling Service. It happens because a human writes a selector in one
place and labels in another and they disagree. But *why is a human writing both?* The
selector's only purpose is to point at those Pods. The two values are not independent
decisions; they are one decision, typed twice.

So: derive them. Let the author declare the service once, and have the compiler
generate the selector, the Pod labels, the Service's selector, the budget's selector,
all from that single value. Now they cannot disagree, not because a checker verifies
it, but because there is only one value and no syntax for writing a second. The check
is not passed. **The check is unnecessary.**

This is prevention by construction, and its economics are different in kind from
detection. A check costs attention forever: it must run, be interpreted, be trusted,
and it fires only after you made the mistake. A prevented error costs nothing, ever,
because the situation in which it could occur does not arise. As Chapter 3 put it: a
guardrail catches you at the edge; the better road has no edge to reach.

## What that looks like

Chapters 9 through 12 described roughly four hundred lines of configuration for one
service. Here is the same service declared once:

```
module payments

service api {
  image    "registry.example.com/payments-api:1.4.2"
  replicas 4

  port http    8080
  port metrics 9090

  resources {
    cpu    500m
    memory 512Mi
    limits { cpu 2, memory 1Gi }
  }

  health {
    live  GET :http /healthz every 10s timeout 2s
    ready GET :http /readyz  every 5s
  }

  needs config app-settings
  needs secret db-credentials as DATABASE_URL

  scale on cpu at 70% between 4 and 20
  disruption { minAvailable 3 }

  expose :http at "payments.example.com"
}
```

Read it with everything you now know, because every line is an argument.

There is **no selector** anywhere, not because it was omitted, but because the
language has no syntax for one. The identity is derived from `service api`, and the
compiler emits the same derived value into the workload's selector, the Pod template's
labels, the Service's selector, and the budget's selector. Byte-identical, by
construction. **Chapter 9's dangling service cannot be written here.**

`port http 8080` is written once and becomes the container's port, the Service's port
and target, and the destination of the routing rule. `expose :http` is not a string
naming a Service; it is a *reference* to that declared port. Misspell it and you get
a compile error at that character, listing the ports that do exist. **Chapter 9's
broken route cannot be written here.**

`scale on cpu at 70%` and `cpu 500m` sit in the same declaration, so the compiler can
see both. Delete the CPU request and it can tell you immediately that your autoscaler
has lost its denominator. **Chapter 10's silent non-scaling is caught at the line you
wrote.**

`disruption { minAvailable 3 }` against `replicas 4` leaves room for exactly one
eviction: satisfiable. Change it to `4` and compilation fails, with the arithmetic
spelled out and the consequence named: node drains will hang. **Chapter 11's deadlock
is caught before it can be applied.**

`needs secret db-credentials as DATABASE_URL` resolves to a declared secret and a
declared key. Wrong name, wrong kind, or a key that does not exist: all compile
errors with suggestions. **Chapter 12's silent empty variable cannot be written here.**

Twenty-eight lines. Not because anything was hidden, but because the duplication was
removed and the relationships were made structural instead of textual.

## Prevention and detection, and knowing the difference

Some errors cannot be designed away, and pretending otherwise would be its own kind of
dishonesty. `minAvailable` is a genuine engineering choice with a valid range: you
cannot make a bad value unrepresentable without also forbidding the good ones. Same
for replica counts, resource sizes, and permission scopes.

So Syg splits its rules explicitly. A rule is either **prevented** (the language has
no way to express the error) or **checked** (the error is expressible, so a check
finds it and explains it). And the governing design rule is that a rule may only be a
check *after* prevention has been considered and rejected, for a reason its
explanation states. Detection is the fallback, never the first move.

When detection does fire, it lands where you can act on it: at your source line, with
the mechanism explained rather than the rule number cited.

```
error[budget-blocks-eviction]: disruption minAvailable 4 requires at least 4 of 4 replicas to stay available
  --> payments.syg:21:3
  21 |   disruption { minAvailable 4 }
     |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   5 |   replicas 4
     |   ^^^^^^^^^^ effective replicas = 4
   = consequence: no pod can ever be voluntarily evicted, so node drains hang
     indefinitely and cluster upgrades stall
   = help: set minAvailable to at most 3 so at least one pod can be evicted
```

Both participants in the relationship are shown, because the error is in the edge
between them. The consequence is stated in the operational terms of Chapter 11 (the
thing that will actually happen to you), not as "invalid configuration."

## The boundary, stated plainly

Now the part that determines whether any of this is trustworthy: **what Syg does not
know.**

A compiler can only reason about what it can see. Syg's world is the module being
compiled, everything it imports, and anything explicitly declared as external. That
boundary is called the **closed world**, and it is a first-class idea rather than an
apology, because the failure mode to avoid is not incompleteness; it is *undeclared*
incompleteness. A tool that implies it verified everything, when it verified what it
could see, is worse than one that draws the line clearly.

So: a service can reference something outside its world by declaring it `extern`,
which makes the reference *typed but trusted*: checked for shape, not for existence.
And where a check's soundness depends on seeing everything, Syg reports **reduced
coverage** rather than a clean result.

Three things it refuses outright, because they are not statically decidable:

- **Whether your probe timings are right.** That depends on how long your program
  actually takes to start under real load. Syg checks the *structure* (that liveness
  and readiness do not share a handler) and says nothing about the numbers.
- **Whether your autoscaling target is sensible.** Whether 70% is right for your
  workload depends on observed behaviour. Syg checks only the *precondition*: that the
  request exists so the arithmetic can function.
- **Whether your secret values are correct.** Values are runtime facts and are
  deliberately absent from the source.

Refusing to guess is a feature. A tool that emits confident diagnostics about things
it cannot know teaches its users to ignore diagnostics, which destroys the value of
the ones that are right.

## What is actually new here, and what is not

Measured against real configuration, the claim comes out smaller than it could have
been stated, and more precise.

Run an established linter over a corpus of real-world configuration, and **several
errors in these notes are already detected by existing tools**. Of the
misconfiguration classes that are common in practice, most are already caught by
KubeLinter. Any claim to be first at detecting them would be false.

Two classes are both common *and* shipped by no existing linter, and both come from
Chapter 11: the **disruption budget on a single-replica workload**, and the **shared
liveness/readiness probe**. Those, plus prevention at the authored source, plus the
ergonomics of twenty-eight lines instead of four hundred, are the honest claim.

The measurement comes with a caveat that belongs wherever its numbers are cited: the
corpus was mostly Helm charts, and templating *already*
derives selectors from shared values. So the prevention classes look rare in that
corpus not because the errors do not happen, but because chart authors had already
solved them the hard way. In hand-written configuration the same study found defect
rates three to eight times higher. Prevention's value concentrates exactly where the
corpus underrepresented it.

That is what it looks like to hold yourself to evidence: you get a smaller claim than
you wanted, stated precisely, and it survives contact with a skeptic.

## What the language is really doing

Step back and the mechanism is simple to state.

Kubernetes models your system as a graph whose edges are string queries and name
references, evaluated at runtime, validated by nothing. That design is why it is so
flexible, and why a healthy-looking cluster can route traffic into a void.

Syg builds that same graph at *authoring* time, with the edges made into checked
references instead of hopeful strings, and, wherever two ends of an edge were
previously typed separately by a human, derives both from one value so the edge cannot
dangle. It then emits ordinary Kubernetes YAML, so nothing downstream changes. No
runtime component, no admission controller, no agent. It is a compiler that runs
before the pipeline you already have.

The runtime keeps its looseness, which it needs. The authoring surface gets the
rigidity, which is where rigidity is free.

## Read the source

- **What Syg checks**: every rule, by what goes wrong, each with the Kubernetes
  mechanism, the production symptom and the verified version range:
  [checks](../checks.md)
- **The language**: every construct, in [the language reference](../language.md)
- **The derivation map**: every construct and the exact Kubernetes fields it
  produces: [the derivation map](../derivation-map.md)

---

*One chapter left. You have the machine, its failures, and the argument for making
those failures unrepresentable. What remains is the honest question of what to do with
it, because everything you have read is the foundation for expertise, not the
expertise itself.* → [Becoming the specialist](../notes/15-becoming-the-specialist.md)
