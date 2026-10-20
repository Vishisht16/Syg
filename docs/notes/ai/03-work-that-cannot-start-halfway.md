# Chapter 3: Work That Cannot Start Halfway

*Verified against: Kueue documentation (API v1beta2, supported on Kubernetes 1.34+).
Checked August 2026.*

Volume I's Chapter 10 described the scheduler's loop, and it is worth restating exactly,
because everything in this chapter comes from one word in it.

The scheduler watches for Pods with no machine assigned. For **each one**, it filters
the machines that cannot run it, scores the ones that can, and binds it to the winner.
Then it moves on to the next Pod.

*Each one.* One Pod at a time, independently, with no notion that this Pod has anything
to do with the one before it. That independence is a feature: it is why the scheduler
is simple enough to be reliable, and why it composes with everything else. For every
workload in Volume I it is exactly right. A Deployment wants five replicas; if three are
placed now and two in a minute, you have three-fifths of your capacity, serving
three-fifths of your traffic. Partial progress is real progress.

Now take a distributed training job that needs sixty-four workers.

Place sixty-three of them and you have not achieved sixty-three sixty-fourths of
anything. The workers exchange gradients at every step; a worker whose partners do not
exist cannot take a step. So the sixty-three sit there, holding sixty-three
accelerators, consuming budget at the full rate, computing nothing, waiting for a
sixty-fourth that may never arrive.

That is not a degraded service. It is a *stalled* one that costs exactly as much as a
working one.

## Two jobs, and a deadlock you have met before

It gets worse than waste, and the way it gets worse should feel familiar.

The Kueue documentation (Kueue being the Kubernetes-native job queueing project that
exists to solve this) states the problem plainly:

> "Many batch workloads, such as synchronized distributed training, require all of their
> Pods to run at the same time to make progress. For such workloads, partial scheduling
> is wasteful at best: Pods that start hold onto resources while waiting for the rest,
> and two such jobs can deadlock by each holding a fraction of the resources the other
> needs."

Read that last clause slowly, because you have seen this shape before.

You have a cluster with a hundred accelerators. Two training jobs arrive, each wanting
sixty-four. The scheduler, doing its job perfectly, one Pod at a time, places fifty
Pods of job A and fifty Pods of job B. Every accelerator is now allocated. Neither job
has enough to start. Neither job will release what it holds, because neither has failed;
they are both simply *waiting*, which is a legitimate state.

Nothing is broken. Every Pod is valid. Every scheduling decision was individually
correct. The cluster is at a hundred percent allocation and zero percent utilisation,
and it will stay that way until a human notices and kills something.

If that reminds you of Volume I's Chapter 11 (the drain that waits forever because a
disruption budget can never be satisfied), you are exactly right, and the resemblance is
not a coincidence. Both are the same structural failure: **a set of individually
reasonable decisions that together reach a state no further individual decision can
escape.** In the drain case, the Eviction API keeps refusing politely and the drain
keeps retrying politely, forever. Here, two jobs keep waiting politely, forever.

Volume I gave you the name for the general pattern: valid objects, broken relationship,
silence. This is that pattern applied to *time* rather than to references: the
relationship that is broken is between Pods that needed to arrive together and did not.

## All-or-nothing admission

The fix is conceptually simple and structurally significant: stop making the decision
per Pod, and start making it per *job*.

This is usually called **gang scheduling** (scheduling a gang of Pods as one unit), and
Kueue's documentation calls the property **all-or-nothing scheduling**. The mechanism it
describes is admission control placed *in front of* the scheduler:

> "By default, a Workload is only unsuspended when the quota for all of its pod sets can
> be reserved at once."

Three things in that sentence are doing work, and they are worth unpacking because they
explain the whole design.

**"Workload"** is a new object. Not a Pod, not a Job: a Kueue object representing the
whole unit of work, including how many Pods it needs. It exists precisely because the
thing you need to reason about has no representation in the core API. The scheduler
could never have made this decision, because the scheduler is handed Pods and nobody
ever told it which Pods belong together.

**"Unsuspended"** is the enforcement point, and it is elegant. Kueue does not fight the
scheduler or replace it. It holds the job in a *suspended* state (created, recorded,
visible, but not producing Pods) until the decision to admit it has been made. Only
then does it let the Pods be created, at which point the ordinary scheduler places them
in the ordinary way. The gang decision happens *before* the scheduler ever sees anything,
which is why the two mechanisms do not conflict.

**"Reserved at once"** is the actual guarantee. Quota for every pod set is checked and
held as a single transaction. Either the whole job's requirement fits, and it is
admitted, or it does not, and it waits in a queue without holding anything.

Notice what that last part fixes. In the deadlock above, the disaster was that partially
admitted jobs *held* resources while waiting. Under all-or-nothing admission, a job that
cannot fully fit holds nothing at all. It waits in a queue, consuming no accelerators,
and the resources stay available for a job that *can* fit. The deadlock is not detected
and recovered from; it is made unreachable.

That is the prevention-versus-detection distinction from Volume I's Chapter 3, showing
up in a scheduler. You could imagine building a deadlock *detector*: watch for jobs that
have been partially placed for too long, and kill one. People have built such things.
Admission control is better for exactly the reason Volume I gave: the situation in which
the error could occur does not arise.

## Where the Pods actually land still matters

There is a second problem, and it is one you cannot see from the resource counts at all.

Sixty-four accelerators are not interchangeable. Two accelerators in the same physical
machine can exchange data over an internal interconnect at enormous bandwidth. Two in
different racks exchange data over the network, orders of magnitude more slowly. For a
workload whose every step involves all workers exchanging gradients, the *topology* of
the placement can dominate the runtime: the same job, same hardware count, can differ
in wall-clock time by a large factor depending on how the pieces were spread.

The plain resource model has no vocabulary for this. "Sixty-four accelerators available"
is true whether they are four machines of sixteen or sixty-four machines of one, and
those are completely different propositions.

Kueue's answer is **Topology Aware Scheduling**, and its documentation is direct about
how strongly it recommends it: TAS *"is strongly recommended for all multi-pod batch and
ML workloads to ensure Kueue validates physical node placement and topology domain fit
before committing admission."*

Note *before committing admission*: this is the same architectural move again. The
topology question is folded into the admission decision, rather than discovered
afterwards when the job turns out to be slow.

There is a genuine echo here of Volume I's Chapter 4, and it is worth drawing out. There,
you learned that availability zones are failure boundaries, and that copies which must
survive independently belong in different zones: spread is *safety*. Here the
consideration runs the other way: for a tightly-coupled training job, spread is *cost*,
and you want the pieces as close together as the hardware allows. Same cluster, same
scheduler, opposite objective, because the workloads have opposite relationships to
distance. A serving fleet wants to be spread so that one building's failure cannot take
it out. A training job wants to be packed so that its gradients do not cross a network.

Holding both of those at once, correctly, for different workloads on the same cluster, is
a fair description of what platform engineering for machine learning actually involves.

## Fairness, and why a queue reappears

One more thing follows from all-or-nothing admission, and it is organisational rather
than technical.

The moment jobs *queue*, somebody has to decide the order of the queue. That is not a
scheduling question; it is a policy question, and it is the same question Volume I's
Chapter 1 raised about the wall between teams: how do you arbitrate competing demands
without it becoming a matter of who shouts loudest?

Kueue's answer is quota borrowing between named queues with configurable fairness: teams
get nominal quota, can borrow unused quota from others, and can be preempted back down
to their nominal share when the lender wants it. I am describing this at a level of
abstraction rather than in detail, because the details are the part most likely to have
changed by the time you read this, and because the shape matters more than the syntax.

The shape is: **a shared scarce resource forces an explicit allocation policy, and if
you do not write one down, you get an implicit one that nobody agreed to.** In Volume I,
that argument produced the error budget, a single number both sides negotiate against.
Here it produces cluster quota. It is the same organisational insight arriving through
different hardware.

## What to carry forward

**Per-Pod scheduling is an assumption, not a law.** It is right for services and wrong
for gangs, and the fix is a layer above the scheduler rather than a change to it.

**The deadlock is the drain deadlock wearing different clothes.** Individually valid
decisions reaching a collectively inescapable state. You now have two instances of that
pattern; you will start seeing more.

**All-or-nothing admission prevents rather than detects**, which is why it beats every
deadlock-detector design you could build instead.

**Topology is not visible in resource counts**, and for tightly-coupled work it can
matter more than the counts do.

## Read the source

### Verified against primary sources

- **Kueue: all-or-nothing scheduling**: the partial-scheduling waste, the two-job
  deadlock quoted above, and the rule that a Workload is unsuspended only when quota for
  all its pod sets can be reserved at once:
  https://kueue.sigs.k8s.io/docs/concepts/all_or_nothing/
- **Kueue: overview and concepts**, including Topology Aware Scheduling and the
  recommendation quoted above: https://kueue.sigs.k8s.io/docs/overview/
- **Volume I, Chapter 10**: the one-Pod-at-a-time scheduler this chapter renegotiates:
  [Resources, scheduling, and autoscaling](../../notes/10-resources-scheduling-and-autoscaling.md)
- **Volume I, Chapter 11**: the drain deadlock this chapter's deadlock rhymes with:
  [Staying up](../../notes/11-staying-up.md)

### Reported by (attributed)

- The claim that placement topology can change a distributed training job's wall-clock
  time substantially is widely reported by practitioners and is the stated motivation for
  Kueue's Topology Aware Scheduling. I have not verified a specific magnitude against a
  primary measurement, and deliberately do not quote one here.

### My argument, not established fact

- That the two-job quota deadlock and Volume I's drain deadlock are *the same structural
  failure* is my framing. Both are documented independently; nobody but me is claiming
  they are instances of one pattern.
- That spread-for-safety and pack-for-speed being opposite objectives on one cluster is
  the defining tension of ML platform work is my characterisation, not a claim from any
  specification.

---

*You can now get sixty-four accelerators allocated together, in the right places. The
next problem is that before any of them can compute anything, something has to move a
hundred and forty gigabytes onto them, and the image-distribution machinery Volume I
praised was designed on the assumption that this would never happen.*
→ [Shipping a model](../../notes/ai/04-shipping-a-model.md)
