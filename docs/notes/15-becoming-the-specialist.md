# Chapter 15: Becoming the Specialist

You have read the whole thing. Before anything else, it is worth being clear about
what that actually bought you, because both overestimating and underestimating it
would be a mistake.

You now hold the mechanical model. You know what a container is at the level of kernel
features rather than metaphor. You know the one idea (continuous reconciliation
toward a declared desired state) that the entire system is built from, and why it is
*level-triggered* observation of current state rather than reaction to events, which is
why it heals from failures nobody wrote recovery code for. You know the parts of a
cluster and how a single submitted file cascades through them. You know how workloads
are owned, why one field is immutable forever, how traffic finds a shifting set of
copies, what a resource request actually controls (four different things), who gets
killed when a machine runs short and why it is not the QoS ordering everyone quotes,
how a safety policy can deadlock maintenance permanently, and why a Role grants nothing
until it is bound.

More usefully than any individual fact, you have a *pattern*: valid objects, broken
relationship, silence. You will now recognise that shape in mechanisms these notes never
covered, which is the real transferable skill.

What you do not have is experience. Every one of those mechanisms you know as
description; specialists know them as memory: of the night it happened, what the
symptoms looked like before anyone knew the cause, and which wrong theory wasted the
first forty minutes. That gap is real and reading cannot close it.

The good news is that it closes *fast* from where you now stand, and much faster than
it does for people who learned incantations. When something breaks, you will not be
pattern-matching against half-remembered blog posts; you will be reasoning about which
controller, acting on which field, produced this. That is the difference between
practice that compounds and practice that merely accumulates.

So this chapter is about how to spend the next few months.

## Build a cluster you are allowed to destroy

The single highest-value thing you can do is get a real cluster on your own machine
and break it deliberately. **kind** ("Kubernetes in Docker") and **k3d** (which runs
**k3s**, a small, fully-conformant Kubernetes distribution, in Docker the same way)
both give you a multi-machine cluster on a laptop in about a minute; each "node" is a
container rather than a real machine, which is exactly enough realism to learn from.
Both are disposable: when you wreck one, you delete it and make another. There is no
faster way to convert knowledge into instinct, because there is no fear.

What matters is *how* you use it. Do not deploy things and watch them work. Deploy
things and watch them **fail**, deliberately, one mechanism at a time. Every chapter
you have read contains an experiment:

- Write a Service whose selector matches nothing, then try to reach it. Look at the
  EndpointSlice and see it empty. Feel what "healthy objects, refused connection" is
  like to debug when you *already know the answer*, because next time you will not.
- Create a Deployment with three replicas and a budget demanding all three available,
  then drain the machine. Watch the drain hang. Watch it keep hanging. Then fix the
  budget and watch it complete instantly.
- Point liveness and readiness at the same dependency-checking endpoint, then break the
  dependency and watch the whole fleet restart at once.
- Deploy something with no resource request, fill the machine, and watch which Pod the
  system chooses to kill.
- Ask for more memory than any machine has, and go read the `Pending` Pod's events to
  see the scheduler explaining itself.
- Write a Role without a binding and watch the `403` arrive from an application that
  looked perfectly configured.

Each of these takes ten minutes and buys you a memory that a chapter cannot. This is
also, not coincidentally, exactly the discipline the Syg project imposes on itself:
before a rule ships claiming to prevent a production failure, someone must demonstrate
that the failure actually occurs on a real cluster. Claims about behaviour are cheap;
reproductions are not.

## Learn to read the system's own answers

Most debugging in this world is not clever. It is knowing where the system already
wrote down what it did.

`kubectl describe` on any object shows you its **events**: the running log of what the
controllers decided about it. A Pod stuck `Pending` will tell you, in plain text, that
no machine had enough memory. A Pod in a config error will name the missing ConfigMap.
An enormous fraction of the questions people bring to colleagues are answered in the
output they did not read.

Then, in rough order of usefulness: `kubectl get <kind> -o yaml` to see an object's
real `spec` and `status` rather than a summary; `kubectl logs` (with `--previous` for a
container that has already restarted, which is where the evidence usually is); and
`kubectl get events --sort-by=.lastTimestamp` for a cluster-wide view of what has been
happening.

The habit worth building is this: when something is wrong, before forming a theory,
**ask the system what it observed**. `status` is the system's own account of current
reality, and it is almost always more accurate than your model of it.

## Read primary sources, and keep the habit

You have seen throughout that mechanism claims were checked against official
documentation and quoted rather than paraphrased. That was not pedantry. More than
once, a widely-repeated claim turned out not to survive checking, including the
popular account of eviction ordering, which is an approximation of a rather different
underlying rule, and a much-quoted warning about liveness probes that could not be
found in the documentation it was attributed to.

So: when you read something about how this system behaves (including anything in these
notes), check it. The Kubernetes documentation is genuinely good, versioned, and
specific about behaviour. When it is ambiguous, the source code is public and, for
questions of "what does this controller actually do," often faster to read than another
blog post.

Keep the version in mind, too. Behaviour changes across releases, and an answer that
was true in an older version and is confidently repeated forever is one of the most
common ways people acquire false beliefs about this system.

## Where to go deeper

The natural next subjects, roughly in order of how often they will matter:

**Observability**: metrics, logs, and traces, and the practice of knowing what your
system is doing. These notes deliberately did not cover it, and it is the largest
single gap in your model right now. Prometheus is the standard entry point.

**Operators and custom resources**: Chapter 6's reconciliation idea extended so *you*
can add your own object kinds with your own controllers. Once the loop clicks, this is
a smaller step than it appears, and it is how most sophisticated software is packaged
for Kubernetes now.

**Service meshes**: a layer that takes over network traffic between services to add
retries, encryption, and observability without changing application code. Powerful, and
a significant complexity cost; understand what problem you have before adopting one.

**Multi-cluster and the storage layer**, when scale or statefulness forces them on you.

And for the reliability practice around all of it, the **Google SRE books**
(sre.google/books, free) remain the best written material on operating systems at
scale: service level objectives, incident response, and the discipline of deciding how
reliable something needs to be rather than assuming more is better.

## A closing word on the field

There is a particular temptation in infrastructure work, which is to accumulate tools,
to measure your competence by how many things you have used. Resist it. The tools
turn over every few years. What does not turn over is the set of ideas underneath them:
that declaring desired state and reconciling toward it beats issuing commands; that
observing current state beats reacting to events; that isolation and resource control
are kernel features and not magic; that relationships between objects are where systems
actually break; and that the most valuable thing a tool can do is make a mistake
impossible rather than merely detectable.

Those ideas are what you have spent fourteen chapters acquiring. They will still be
true when the current generation of tooling is a footnote, and they are what will let
you learn the next generation in days rather than months.

The last thing worth saying is the thing these notes have been quietly arguing all
along. Every mechanism here exists because something went wrong for someone, at 3
a.m., badly enough that they built something to stop it happening again. The disruption budget
exists because an upgrade took a service down. The readiness probe exists because a
deploy served errors for thirty seconds. Reconciliation exists because someone got
tired of restarting processes by hand.

Understanding this field means understanding those incidents: not the configuration
syntax, but *what happened to a real person* that made the syntax necessary. That is
the knowledge these notes have been trying to transfer, and it is why the mechanism
mattered more than the command.

Go and break something you are allowed to break. You will be surprised how quickly it
starts feeling like yours.

## Read the source

- Disposable local clusters: **kind** (https://kind.sigs.k8s.io/) and **k3d**
  (https://k3d.io/).
- **Kubernetes documentation**, especially the Concepts and Tasks sections:
  https://kubernetes.io/docs/
- **Google SRE books**, free online: https://sre.google/books/
- **Programming Kubernetes** (Hausenblas & Schimanski): for writing controllers, once
  the reconciliation loop feels natural.
- **The CNCF landscape**, used carefully as a map rather than a shopping list:
  https://landscape.cncf.io/

---

*That is the end of the notes. To look something up, the [glossary](../notes/glossary.md) is
one page and links back into every chapter, and the [contents](../notes/index.md) will take
you to any of them directly. And if you want to see the ideas in Chapter 14 at work,*
[Syg's documentation](../index.md) *starts with a quickstart, and*
[what Syg checks](../checks.md) *explains each rule's Kubernetes mechanism to the
same standard as these chapters.*

← [back to the beginning](../notes/index.md)
