# Chapter 7: MLOps, Honestly

*Anchored on Sculley et al., NeurIPS 2015. Checked August 2026.*

If you ask what MLOps is, you will mostly be handed a list of tools (an experiment
tracker, a model registry, a feature store, a pipeline orchestrator) and told that
adopting them is the practice.

Volume I's Chapter 2 opened the same way about DevOps, and made the same complaint: each
of those answers has taken a symptom or a side-effect and mistaken it for the thing
itself. The tools are real and several are genuinely useful. But a list of tools cannot
tell you *why they exist*, which means it cannot tell you which of them you need, or what
to do when your situation does not match the list.

So let us do what that chapter did, and recover the actual idea.

## The one-sentence version

Here is MLOps, honestly: **ordinary software has one artifact whose lifecycle you have
to manage, and a machine learning system has three.**

Volume I was, from beginning to end, about managing one artifact. Your code becomes a
container image, the image is versioned by a digest, the digest is deployed, and if it
misbehaves you deploy the previous digest instead. Everything in that book (content
addressing, immutability, rolling updates, rollback) is machinery for handling *one*
thing that changes over time.

A machine learning system has:

- the **code**, exactly as before;
- the **data** it was trained on;
- and the **model** that resulted from applying the first to the second.

Each of those changes independently. Each can break the system. And the version control,
reproducibility, and rollback that Volume I took for granted for code do not come for
free for the other two, because the tooling that provides them for code does not know
they exist.

Almost everything called MLOps is an attempt to give artifacts two and three the
properties artifact one already had.

That is the whole idea. Now here is why it is harder than it sounds, which is the part
the tool lists never explain.

## The paper that saw it first

In 2015, before most of the tooling existed, a group at Google published a paper called
*Hidden Technical Debt in Machine Learning Systems*, by D. Sculley, Gary Holt, Daniel
Golovin, Eugene Davydov, Todd Phillips, Dietmar Ebner, Vinay Chaudhary, Michael Young,
Jean-François Crespo, and Dan Dennison. It remains the best diagnosis of this problem
that exists, and it is worth reading in the original.

Its framing is the technical-debt metaphor, and its warning is that machine learning
attracts debt with unusual speed. Machine learning, the paper says, *"offers a
fantastically powerful toolkit for building useful complex prediction systems quickly,"*
and it is *"dangerous to think of these quick wins as coming for free."* The specific
risk factors it enumerates are the table of contents for this entire discipline:
boundary erosion, entanglement, hidden feedback loops, undeclared consumers, data
dependencies, configuration debt, changes in the external world, and a collection of
system-level anti-patterns.

Notice the date. This is a decade old, it predates the products that now claim to solve
it, and it describes the problems those products are aimed at more precisely than their
marketing does. That is a useful thing to know about any field: the diagnosis usually
arrives well before the cure, and reading the diagnosis is how you evaluate the cure.

## Entanglement, and why you cannot modularise your way out

The paper's sharpest single idea is the one it calls the **CACE principle**: *Changing
Anything Changes Everything.*

Here is what it means concretely. In ordinary software, you manage complexity by drawing
boundaries. A function has inputs and outputs; a module has an interface; a service has
an API. The whole discipline of software engineering is the practice of arranging things
so that a change *here* provably cannot affect *there*. Volume I's entire architecture
(containers isolating processes, controllers that never call each other, interfaces like
the CRI that let implementations change underneath) is that instinct applied to
infrastructure.

A trained model has no such boundaries inside it. Change the distribution of one input
feature and the learned importance of every other feature can shift, because the model
found whatever relationships existed among all of them jointly. Add a feature, remove a
feature, change a hyper-parameter, change the sampling of the training data, change a
convergence threshold: any of these can change the behaviour of the whole thing, in ways
no interface documents and no type system constrains.

I want to draw out how deeply this cuts against Volume I, because it is not a small
inconvenience.

Volume I's answer to complexity, over and over, was *isolation*: make the pieces
independent so you can reason about them one at a time. The reason a Kubernetes cluster
is comprehensible at all is that the scheduler does not need to understand the kubelet.
A trained model is a component to which that strategy simply does not apply. You cannot
decompose it into parts that can be reasoned about separately, because the entanglement
is not an implementation detail you could refactor away; it is what the model *is*.

The practical consequence is that the verification story has to move. If you cannot
establish correctness by reasoning about the internals, you establish confidence by
*evaluating the whole thing on held-out data*, every time anything changes. That is why
evaluation infrastructure is not a nice-to-have in this field: it is the only thing
standing where, in ordinary software, types and tests and interfaces would be.

## Data is a dependency, and nothing in Volume I knows that

Now the second artifact, and the one with no analogue anywhere in the first volume.

Volume I taught dependency management thoroughly, and it always meant one thing: a
dependency is a piece of code, at a version, that your code calls. Volume I pinned image
digests, and warned about references to things that might not exist. All of it assumed
dependencies are *code*.

Training data is a dependency in exactly the sense that matters (your system's behaviour
depends on it), and it has almost none of the properties that make code dependencies
manageable. It is usually far too large to sit in version control. It often has no
version at all, being "whatever was in the warehouse when the job ran." It changes
because the world changes, without anyone editing anything. And crucially, the
*relationship* between a model and the data it came from is not recorded anywhere by
default.

Which produces a failure Volume I has no vocabulary for. Ask, of a model serving traffic
right now: **what exactly was it trained on?** For an alarming number of production
systems the honest answer is that nobody can reconstruct it, because the query that
produced the training set has since been edited, or the table it read has been
overwritten, or the pipeline pulled "the last 90 days" and 90 days ago is a different set
of rows today than it was then.

Compare that to Volume I's standard. There, if you asked "what exactly is running?", the
answer was a digest: a cryptographic hash naming exact bytes, which you could verify.
The gap between those two situations is most of what a model registry and a data
versioning system are trying to close.

## Training and serving are two different programs

There is one more failure mode worth naming precisely, because it is the most common
serious bug in production machine learning and it has no counterpart in Volume I at all.

A model is trained on features computed one way, usually in a batch job, over historical
data, in whatever language the data team uses. It then serves predictions on features
computed a *second* way: in the serving path, on live data, often in a different
language, written by a different team, under latency constraints the batch job never had.

If those two computations disagree even slightly, the model is being asked at serving time
a subtly different question than the one it was trained to answer. It will answer
confidently. The predictions will be worse, and there will be no error anywhere.

This is called **training/serving skew**, and I want to point out what shape it is,
because you already know this shape. Two pieces of logic, in two places, written by
different people, that are *supposed* to agree, with nothing checking that they do. It is
Volume I's Chapter 9 dangling service. It is Volume I's "the same value written in six
places." It is the identical structural failure (a relationship between two artifacts
that must hold, expressed nowhere, verified by nothing) showing up in a completely
different part of the stack.

The main structural answer the field has developed is the **feature store**: a system
where a feature is defined *once* and both the training path and the serving path read
their values from that one definition, rather than each computing its own. If that sounds
like the derivation argument from Volume I's Chapter 14 (define once, generate the
several places it is needed, so they cannot disagree), that is because it is the same
argument, discovered independently by people solving a different problem.

I find that genuinely encouraging, and I will say plainly that it is one of the reasons I
believe the argument in Chapter 9 of this volume. When two communities with no contact
converge on "derive the copies from one definition" as the fix for silent disagreement, it
is more likely to be a real principle than a preference.

## So what is MLOps

Putting it together, and stripping the tools out:

**MLOps is the practice of giving data and models the lifecycle guarantees that code
already had** (versioning, reproducibility, testing, deployment, rollback, and
monitoring) while accounting for two properties code does not have: that models are
entangled and cannot be verified by inspection, and that data changes without anyone
changing it.

The tools follow from that sentence rather than defining it. An experiment tracker exists
because entanglement means you cannot reason your way to the best configuration and must
therefore record what you tried. A model registry exists because "which model is in
production" needs to be answerable the way an image digest answers it for code. A feature
store exists because training and serving must not diverge. A monitoring system watching
input distributions exists because the world changes underneath a model that has not
changed at all, a phenomenon called **drift**, which is the closest thing this field has
to a failure that requires no trigger.

And the same caution Volume I raised about DevOps applies here with force. MLOps is not a
team you hire or a platform you buy. It is a set of properties your system either has or
does not, and you can have every tool on the list and none of the properties.

## What to carry forward

**Three artifacts, not one.** Code, data, model: each with an independent lifecycle, and
only the first well served by everything in Volume I.

**Entanglement defeats modular reasoning**, so confidence comes from evaluation rather
than inspection. That is a permanent difference in kind, not a tooling gap.

**Data is an unversioned dependency by default**, and "what was this trained on" is
usually unanswerable unless someone built the machinery to answer it.

**Training/serving skew is Volume I's dangling-edge failure** in a new location, and the
fix is the same one: derive both from a single definition.

## Read the source

### Verified against primary sources

- **Volume I, Chapter 2**: the "honestly" treatment this chapter mirrors, and the
  argument that a practice is not a tool list:
  [DevOps, honestly](../../notes/02-devops-honestly.md)
- **Volume I, Chapter 14**: the derive-from-one-definition argument that the feature
  store independently arrives at:
  [Syg: prevention by construction](../../notes/14-syg-prevention-by-construction.md)

### Reported by (attributed)

- **D. Sculley, Gary Holt, Daniel Golovin, Eugene Davydov, Todd Phillips, Dietmar Ebner,
  Vinay Chaudhary, Michael Young, Jean-François Crespo and Dan Dennison**, *"Hidden
  Technical Debt in Machine Learning Systems"*, NeurIPS 2015: the technical-debt framing,
  the enumerated risk factors, and the CACE principle:
  https://papers.nips.cc/paper/5656-hidden-technical-debt-in-machine-learning-systems
  The quoted phrases are from the paper's abstract; the CACE principle is stated there and
  is widely discussed under that name.

### My argument, not established fact

- The "three artifacts" formulation is my compression of the field. It is not how the
  Sculley paper frames things, and it is not a standard definition.
- That entanglement cuts specifically against Volume I's isolation strategy, and that
  this forces verification to move from inspection to evaluation, is my argument.
- That training/serving skew is structurally the same failure as Volume I's dangling
  service is my claim. The two are documented independently and nobody else is asserting
  they are one pattern.
- That the feature store and Syg's derivation argument converging is evidence the
  principle is real is my reasoning, and convergent evolution is suggestive rather than
  probative.

---

*That was the discipline built around the new workload, and it is real engineering with a
real diagnosis behind it. The next chapter takes a term with a far weaker claim to that
description (one whose own analysts have documented its identity crisis) and tries to
find the part of it that is true.*
→ [AIOps, honestly](../../notes/ai/08-aiops-honestly.md)
