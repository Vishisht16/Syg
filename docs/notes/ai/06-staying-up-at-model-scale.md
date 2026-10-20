# Chapter 6: Staying Up at Model Scale

*Verified against: Kubernetes probe documentation and EC2 Spot Instance documentation.
Checked August 2026.*

Volume I's Chapter 11 taught you three probes and the different verbs they represent.
Liveness restarts the container. Readiness removes it from the traffic list. Startup
holds the other two off while a slow program wakes up.

It also taught, at length, the most expensive mistake in that family: pointing liveness
and readiness at one dependency-checking endpoint, so that a brief database wobble
restarts your entire fleet simultaneously. That chapter spent its second half on the
restart storm because the study behind this project found it both common and uncaught.

All of that still applies, unchanged. What this chapter adds is that model serving takes
the *third* probe (the one Volume I introduced in a single paragraph and then largely
left alone) and makes it the most important of the three.

## Readiness that takes minutes

Recall Volume I's framing: a readiness probe asks *is this container ready to serve
requests right now?* The implicit expectation is that the answer is cheap to compute and
arrives quickly after startup. A web service binds a port, warms nothing much, and is
ready in a second or two.

A model server has to load its weights. Chapter 4 of this volume covered where those
weights come from and how long that takes; the number that matters here is that the gap
between "container started" and "can serve a request" is measured in minutes, not
seconds, and for large models can be several of them.

Now run Volume I's machinery against that fact and watch what happens.

The kubelet starts the container. Liveness probing begins after whatever
`initialDelaySeconds` was configured: typically tens of seconds, because that is what
people copy from examples written for web services. The probe fires. The server is
loading weights and does not answer. The probe fails. It fails again. It reaches its
failure threshold, and the kubelet, doing exactly its job, **restarts the container.**

Which starts the weight loading over from the beginning.

The result is a Pod that can never become ready, restarting forever, with a restart
counter climbing and no error anywhere that says *your liveness probe is killing this
before it can finish waking up*. Every individual component is behaving correctly.
Volume I's pattern again: valid objects, broken relationship, silence.

## The field that exists for exactly this

The fix is not a clever timeout. It is the **startup probe**, and Volume I described its
purpose accurately in one sentence: while a startup probe is still failing, the other two
probes are held off entirely, which prevents a slow starter from being killed by a
liveness probe before it has finished waking up.

The Kubernetes documentation states the mechanism plainly: *"If a startup probe is
configured, Kubernetes does not execute liveness or readiness probes until the startup
probe succeeds."* And it names the consequence of failure: *"If the startup probe fails,
the kubelet kills the container, and the container is subjected to its restart policy."*

So a startup probe with a generous failure threshold gives the model server a long,
explicitly bounded window to load, during which liveness cannot touch it, and after
which, if it genuinely has not come up, it is killed for a real reason rather than an
impatient one.

Two things about this deserve emphasis, because I think this is the single most
practically useful paragraph in Part II.

First, the startup probe lets you express *two different timeouts for two different
questions*, which is precisely the two-verbs insight from Volume I applied to time
instead of consequence. "How long may this take to start?" and "how long may it hang once
running?" are different questions with different right answers (minutes and seconds
respectively), and without a startup probe you are forced to answer both with one number.
Set that one number high enough for the slow start and you have made liveness useless for
the rest of the container's life, because a genuinely wedged server now takes minutes to
be noticed. Set it low enough for liveness to be useful and you have guaranteed the
restart loop above.

That is a real dilemma with no good resolution *inside* the two-probe model, and the
startup probe dissolves it rather than trading it off.

Second, the documentation's guidance on where the slow-start problem belongs is explicit,
and it is worth having: *"For containers that need to work on loading large data,
configuration files, or migrations during startup, consider using a startup probe."*
Loading large data is exactly the case.

## Where the readiness answer comes from

There is a subtler question underneath the timing, and it is one Volume I never had to
ask: what does the readiness endpoint actually *check*?

For a web service, "am I ready" usually means "have I bound my port and finished my
initialisation." For a model server, it has to mean "are the weights loaded and is the
model able to run a forward pass." Those are not the same thing, and a server that
answers the first while meaning the second will be added to the traffic list before it
can serve anything, reproducing, on every deploy, the burst of errors Volume I described
as the cost of a missing readiness probe.

Which loops back to Volume I's warning with a twist. That chapter cautioned against
readiness probes that check *dependencies*, because their failure is correlated across
the fleet and shedding all traffic at once is rarely what you want. A model server's
readiness check is not a dependency check (the weights are local, loaded, and its own),
so it does not carry that risk. It is a genuine self-check that happens to be expensive
to satisfy. The rule from Volume I stands, and this is not an exception to it; it is a
case where the expensive local check is the correct one.

## Hardware that leaves with two minutes' notice

Now the other half of staying up, and it comes from Volume I's chapter on the cloud
rather than its chapter on probes.

That chapter established the fact this whole field is built on: providers rent spare
capacity cheaply on the condition they can reclaim it, and AWS's documentation is exact
about the notice you get: *"a warning that is issued two minutes before Amazon EC2 stops
or terminates your Spot Instance."*

Volume I used that to argue that machine loss must be routine rather than exceptional,
because software that treats it as an emergency is not viable at cloud scale. For a
stateless web replica, two minutes is generous: finish in-flight requests, stop taking
new ones, exit. The reconciliation loop starts a replacement elsewhere and nobody notices.

Now apply it to a training job that has been running for twenty hours.

The two-minute notice is still two minutes. What has changed is what is lost. A stateless
replica loses nothing, because it held nothing. A training job holds twenty hours of
accumulated computation in accelerator memory, and if it has not written that state
somewhere durable, the notice is not a chance to shut down gracefully. It is a
notification that twenty hours are gone.

This is why **checkpointing** (periodically writing the training state to durable
storage so a job can resume rather than restart) stops being hygiene and becomes
structural. Without it, the economics of cheap reclaimable capacity are not merely risky
but incoherent: you took a large discount in exchange for accepting interruption, and
then built something that cannot survive interruption.

And notice that this interacts with the chapter before last. Resuming from a checkpoint
means *reading a large object back onto an accelerator*, which is the same delivery
problem Chapter 4 described from the other direction. The frequency of checkpointing is
therefore a real trade with real numbers on both sides: checkpoint too rarely and an
interruption costs you a lot of recomputation; checkpoint too often and you spend a
meaningful fraction of your expensive hardware's time writing state instead of training.

I am not going to give you a rule for where that balance sits, because it depends on the
interruption rate you actually observe and the cost of your storage path, and anyone
offering a universal number for it is guessing. What I will say is that it is a decision
that has to be *made*, and that the failure mode is making it by default, which means
not checkpointing, which means discovering the policy during the interruption.

## Disruption budgets, briefly

One more connection worth drawing, since Volume I spent a whole section on it.

A PodDisruptionBudget constrains voluntary disruption: it tells the Eviction API how many
copies must remain available while somebody deliberately drains a machine. Volume I's
central warning was that a budget with no slack deadlocks the drain forever, and that a
budget on a single-replica workload is deadlocked by construction.

That warning applies with more force here, for a reason specific to this workload:
accelerator-backed replicas are expensive and therefore few. A serving deployment with
three replicas has a budget arithmetic that is tight by default, and a single-replica
model deployment (which is extremely common while a model is being evaluated, or for a
model with modest traffic) is exactly the by-construction deadlock Volume I described.
The cost of accelerators pushes teams toward exactly the replica counts where disruption
budgets stop working.

Nothing about the mechanism has changed. What has changed is that the configuration most
likely to trigger the failure is now also the configuration most likely to be economically
attractive.

## What to carry forward

**The startup probe is not optional here.** It is the field that lets you answer "how long
may starting take?" and "how long may hanging take?" with different numbers, and without
it you must get one of them wrong.

**Readiness means weights loaded**, not port bound, and this is the rare case where an
expensive local readiness check is the right one.

**Checkpointing is what makes cheap interruptible capacity coherent**, and its frequency
is a real trade rather than a default.

**Disruption budgets get harder as replicas get expensive**, pushing you toward the replica
counts where Volume I's deadlock is structural.

## Read the source

### Verified against primary sources

- **Liveness, readiness and startup probes**: the rule that liveness and readiness are
  not executed until the startup probe succeeds, the consequence of startup-probe failure,
  and the guidance to use a startup probe for containers loading large data:
  https://kubernetes.io/docs/concepts/workloads/pods/probes/
- **Spot Instance interruption notices**: the two-minute warning:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html
- **Volume I, Chapter 11**: the three probes, the restart storm, and the disruption-budget
  deadlock this chapter extends: [Staying up](../../notes/11-staying-up.md)
- **Volume I, Chapter 4**: the reclaimable-capacity bargain:
  [The cloud](../../notes/04-the-cloud.md)

### Reported by (attributed)

- Nothing in this chapter rests on reported practice. The failure narrative at the start is
  constructed from the documented behaviour of the components rather than drawn from a
  specific published incident, and I would rather say so than imply I am reporting one.

### My argument, not established fact

- That the startup probe *dissolves* rather than trades off the one-timeout dilemma is my
  framing of why the field exists.
- That the economics of accelerators push teams toward exactly the replica counts where
  disruption budgets deadlock is my argument. The mechanism is documented in Volume I; the
  claim that cost pressure makes the dangerous configuration more likely is mine.
- I decline to give a checkpointing frequency, and note that anyone offering a universal
  one is guessing. That is an opinion about other people's advice.

---

*Part II is done: you now know the five mechanisms that had to change and why. Part III
turns to the disciplines that grew up around this work, starting with a word that has
been attached to a great many products, and a paper from 2015 that diagnosed the whole
problem before most of those products existed.*
→ [MLOps, honestly](../../notes/ai/07-mlops-honestly.md)
