# The Syg Engineering Notes, Volume II: Machine Learning and the Machines That Serve It

*What artificial intelligence actually did to platform engineering: the mechanisms
that changed, the disciplines that grew up around them, and the one change nobody has
finished thinking through.*

---

## This is a sequel, and it means it

[Volume I](../../notes/index.md) taught the field in its pure form: containers,
reconciliation, the control plane, workloads, networking, resources, availability,
configuration. Fifteen chapters, built so that no word arrived before its meaning.

**This volume assumes all of it.** Not as background reading, but as prerequisite. When
Chapter 2 here says a GPU breaks the requests-and-limits model, it assumes you know
what a request is, what a limit is, why memory kills and processor time throttles, and
what a QoS class is derived from. It will not rebuild any of that.

If you have not read Volume I, read it first. It will take longer than this one and it
is the part that makes you useful. This volume is what you read afterwards, when you
want to know why everything you just learned is being renegotiated.

## Who this is for

Someone who has finished Volume I (or who already knew that material) and who keeps
running into a wall of vocabulary that seems to mean something and might not.

You have heard that AI is transforming infrastructure. You have heard *MLOps*,
*AIOps*, *agentic operations*, *inference at scale*. You have probably noticed that
these words are used most confidently by people selling something, and least
confidently by people who operate systems. And you have not been able to tell which
parts are real engineering with specifications behind them, and which parts are a
conference talk.

That distinction is the entire purpose of this volume.

## What you will get

By the end you should be able to hold two things at once.

First, the **mechanisms**: why an accelerator cannot be overcommitted the way a
processor can, and what Kubernetes built to allocate one properly; why a distributed
training job cannot be scheduled one Pod at a time, and how the fix reproduces a
deadlock you already know; why a model server's readiness question is different in kind
from a web service's; why standard load balancing is close to worst-case for language
model inference, and what replaced it. These are real, specified, and checkable, and
they are taught here at the same depth as Volume I.

Second, the **judgment** to evaluate the rest. A large part of what is said about AI
and operations is not mechanism at all. Some of it is honest reported practice; some of
it is argument; some of it is marketing that has borrowed the grammar of engineering.
You will finish this volume able to sort those apart, which matters more than any
individual fact here, because the facts will move and the sorting skill will not.

Let me be honest about one edge in particular. Volume I could promise that every claim
was checked against stable, versioned, primary documentation, because Kubernetes has
that. Large parts of this subject do not. Writing both to a single standard would
require either inventing certainty or refusing to cover the interesting half. So this
volume does something else instead, and it is the next section, and it is the most
important thing on this page.

## How you can tell what I actually know

Every claim in this volume falls into one of three kinds, and you are never left to
guess which one you are reading.

**Mechanism.** Something with a specification, a reference implementation, or official
documentation behind it. These are quoted rather than paraphrased, and the source is
named in the text. If you see *"the documentation states"* followed by quotation marks,
that is a claim you can go and verify in about a minute, and you should.

**Reported practice.** Something a named person or team did, measured, and wrote up.
Attributed by name, always: never "studies show," never "it is widely known." You are
told who made the observation so you can weigh the source and read the original.

**My argument.** Reasoning I am doing, which you should treat as reasoning rather than
fact. These are marked in the text, in plain words, at the point where the argument
starts. The largest one is Chapter 9, which is an argument end to end and says so in
its first paragraph.

Every chapter closes with **Read the source**, split into exactly those three headings.
A claim that cannot be placed under one of them did not make it into the chapter.

**One more thing, and it is a real limitation.** This field moves faster than the one
in Volume I. Each chapter records the version it was verified against and the month it
was checked. When you read anything about this subject (including this), the first
question worth asking is *when was this true, and of what version?* Undated confidence
about AI infrastructure is the single most reliable signal that someone is not being
careful.

## How to read this

The same way as Volume I, and for the same reasons.

**Read it in order.** The chapters are in dependency order, and Part II builds a
vocabulary that Parts III and IV use.

**No word is used before it is explained**: the promise Volume I made, kept here too.
Where a term has to appear early, its meaning arrives in the same sentence. The
[glossary](../../notes/ai/glossary.md) catches anything that gets past me, and if one does, the
failure is mine and not a gap in you.

**Part II is dense; Parts III and IV are argumentative.** They are different kinds of
reading and it is worth knowing which you are in. Part II is mechanism, and rewards
slowness. Parts III and IV are about claims, history, and reasoning, and reward
skepticism, including toward me.

**If something does not click, keep going.** Still true, still the most useful advice
here.

## What extends what

This volume does not repeat Volume I. It renegotiates specific parts of it. Here is
exactly which parts:

| This volume | Renegotiates | Because |
|---|---|---|
| 1. Two revolutions | Vol I ch. 1–2 | The change is two changes, usually conflated |
| 2. The accelerator is not a processor | Vol I ch. 10 | Requests, limits, and QoS assume a compressible resource |
| 3. Work that cannot start halfway | Vol I ch. 10, 11 | The scheduler places one Pod at a time |
| 4. Shipping a model | Vol I ch. 5 | Image layers assume the payload is small and shared |
| 5. Serving a model | Vol I ch. 9 | Service load balancing assumes stateless short requests |
| 6. Staying up at model scale | Vol I ch. 11, 4 | Probes assume readiness is cheap to answer |
| 7. MLOps, honestly | Vol I ch. 2–3 | A second and third artifact enter the pipeline |
| 8. AIOps, honestly | Vol I ch. 1 | The oldest claim to have automated operations away |
| 9. When the author is not human | Vol I ch. 3, 14 | Detection assumes somebody reads the diagnostic |
| 10. Reading a fast-moving field | Vol I ch. 15 | Everything above will age |

## The path

**Part I: What actually changed**

1. [Two revolutions, wearing one name](../../notes/ai/01-two-revolutions.md): separating the workload
   change from the authorship change, and why conflating them makes both unreadable.

**Part II: The new workload**

2. [The accelerator is not a processor](../../notes/ai/02-the-accelerator-is-not-a-processor.md):
   why the resource model from Volume I does not transfer, and what Kubernetes built
   instead.
3. [Work that cannot start halfway](../../notes/ai/03-work-that-cannot-start-halfway.md):
   all-or-nothing scheduling, and a deadlock with a familiar shape.
4. [Shipping a model](../../notes/ai/04-shipping-a-model.md): when the payload is a hundred gigabytes
   and the layer-sharing economics stop working.
5. [Serving a model](../../notes/ai/05-serving-a-model.md): why round-robin is close to the worst
   thing you can do to an inference fleet.
6. [Staying up at model scale](../../notes/ai/06-staying-up-at-model-scale.md): readiness that takes
   minutes, and hardware that leaves with two minutes' notice.

**Part III: The disciplines**

7. [MLOps, honestly](../../notes/ai/07-mlops-honestly.md): what it means once you strip the tool list,
   and the paper that diagnosed it a decade early.
8. [AIOps, honestly](../../notes/ai/08-aiops-honestly.md): a term with a documented identity crisis,
   and the part of it that is real.

**Part IV: The new author**

9. [When the author is not human](../../notes/ai/09-when-the-author-is-not-human.md): the argument
   this volume exists to make, and what would prove it wrong.

**Part V: Closing**

10. [Reading a fast-moving field](../../notes/ai/10-reading-a-fast-moving-field.md): how to evaluate
    the next claim you meet, after this volume is out of date.

## On trusting any of this

Same standard as Volume I, with one addition. Every mechanism claim is checked against
primary documentation and quoted, so you can verify it yourself. Every reported claim
names its source. Every argument is labelled as mine.

And where I do not know, this volume says so rather than filling the gap with
confidence. There is a lot of that here. It is the honest shape of writing about
something while it is still moving.

→ [Chapter 1: Two revolutions, wearing one name](../../notes/ai/01-two-revolutions.md)
