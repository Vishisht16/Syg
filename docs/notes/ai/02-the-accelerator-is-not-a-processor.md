# Chapter 2: The Accelerator Is Not a Processor

*Verified against: Kubernetes documentation for GPU scheduling, Pod QoS classes, and
Dynamic Resource Allocation (stable in v1.35). Checked August 2026.*

Start with a failure, because it is the fastest way in and because it is embarrassing
in a way you will remember.

A team runs a training job on eight accelerators. In cloud terms that is a machine
costing more per hour than most people's daily wage. The job is important, the hardware
is scarce, and the team has been waiting three days for capacity.

The machine it lands on runs short of memory. The agent on that machine picks a Pod to
evict, and it picks *theirs*: the eight-accelerator job, ahead of a small stateless web
service sitting on the same machine doing almost nothing.

Volume I's Chapter 10 taught you to be suspicious of exactly this reaction, so do not
say the system is broken. Ask instead what information it had. And the answer is
genuinely startling: **as far as the eviction machinery was concerned, that Pod had
asked for nothing at all.**

The documentation says so directly. Setting out when a Pod is classified `BestEffort`
(the class that dies first), it notes: *"Containers in a Pod can request other resources
(not CPU or memory) and still be classified as `BestEffort`."*

Eight accelerators is "other resources." The Pod declared no memory request and no
processor request, because the team was thinking about the expensive hardware and not
about the cheap hardware. So the classification that governs who gets killed never saw
the expensive part. Volume I put it as **you were not outbid; you never bid.** It
turns out you can fail to bid while holding the most valuable thing on the machine.

That is not a bug, and it is not a trick question. It is what happens when a resource
model built around exactly two commodities (processor time and memory) is asked to
account for a third that behaves like neither of them. This chapter is about why the
accelerator is that different, and what Kubernetes eventually built to handle it.

## What "not like a processor" actually means

Volume I's Chapter 10 built its argument on a distinction: memory is *incompressible* and
processor time is *compressible*. A program denied memory it needs cannot be politely
slowed down; it must be refused, which is why the kernel kills it. A program wanting
more processor time than it may have can simply be made to wait, which is why it gets
throttled instead. Memory kills; processor throttles.

An accelerator sits outside that dichotomy, for reasons worth being precise about.

**It is not meaningfully time-shared by default.** Processor time is divisible because
the kernel has spent thirty years learning to interleave threads at microsecond
granularity; that is what a scheduler *is*. Handing two unrelated processes alternating
slices of one accelerator is possible, but it is not the default, it is not free, and
the mechanisms that do it are separate features you opt into rather than the ambient
behaviour of the platform.

**Its memory is not overcommittable.** This is the sharper point. Ordinary system memory
can be overcommitted because most processes do not touch everything they allocate, and
the kernel has reclaim machinery (page cache eviction, swap) to claw back memory under
pressure. Accelerator memory has essentially none of that. A model's weights are
resident because they are needed on every single forward pass. There is no meaningful
sense in which they are "cold" and could be paged out. When accelerator memory runs out,
what happens is not reclaim followed by graceful degradation; it is an allocation
failure, and the program falls over.

**And it is allocated as a whole thing.** The scheduling documentation is explicit about
how you ask for one:

> "GPUs are only supposed to be specified in the `limits` section, which means:
> You can specify GPU `limits` without specifying `requests`, because Kubernetes will
> use the limit as the request value by default. You can specify GPU in both `limits`
> and `requests` but these two values must be equal. You cannot specify GPU `requests`
> without specifying `limits`."

Read that against Volume I and notice what has quietly disappeared. There, the gap
between request and limit was the entire design space. The request was your
reservation and your placement key; the limit was your ceiling; the distance between
them was headroom you could burst into and the thing that made a Pod `Burstable` rather
than `Guaranteed`. Here, that gap is *forbidden*. Request must equal limit. There is no
headroom, because there is nothing to burst into. You get whole devices, or you get
nothing.

So the two-number model collapses to one number, and the one number is
an integer count of physical objects.

## The device plugin, and why it stopped being enough

For most of Kubernetes' history, that integer was delivered by a mechanism called the
**device plugin**: a small agent, supplied by the hardware vendor, running on each
machine, whose job was to tell the agent on that node "this machine has four of
`vendor.example/gpu`," and to hand one over when a container asked. Your Pod said
`limits: {vendor.example/gpu: 1}` and the plumbing did the rest.

It worked, and it shipped an enormous amount of real work. But it had three limitations,
and rather than paraphrase them, here is how the Kubernetes documentation itself
characterises them when explaining why something replaced it. Device plugins, it says,

> "require per-container device requests, don't support device sharing, and don't
> support expression-based device filtering."

Take those one at a time, because each is a real operational problem.

**Per-container device requests.** The unit of allocation is the container, not the Pod.
If two containers in one Pod both need to touch the same accelerator (a common shape
once you have a sidecar doing anything with the device), the model has no way to express
"these two share this one."

**No device sharing.** Related but broader: one device, one claimant. Everything about
running several small jobs on one large accelerator has to happen outside the model,
through vendor-specific mechanisms that Kubernetes itself cannot see or reason about.

**No expression-based filtering.** This is the one that bites hardest in practice, and it
is worth making concrete. Under the device plugin model you ask for *a count of an opaque
name*. `vendor.example/gpu: 1` means "one thing that the vendor called gpu." It does not
mean "one accelerator with at least 40 gigabytes of device memory," or "one that
supports the numeric format my model was compiled for," or "two that are physically
connected by a fast interconnect so they can exchange gradients without crawling over
the network."

Those are the questions people actually have. The device plugin model's answer was that
you encode them as node labels and hope: putting `accelerator=a100-80gb` on machines by
hand and selecting on it, which is a string, matched by a query, that nothing validates.
If Volume I's Chapter 7 made you flinch at that sentence, good. It is the stringly-typed
graph again, now deciding where thirty thousand dollars of hardware gets used.

## Dynamic Resource Allocation

What replaced it is **Dynamic Resource Allocation**, or DRA, and its status is worth
stating precisely because this field is full of things described as production-ready
that are not. The documentation records it as **stable in Kubernetes v1.35 and enabled
by default**. It is not a preview and not a vendor extension; it is a core feature.

Here is the documentation's own definition:

> "DRA is a Kubernetes feature that lets you request and share resources among Pods.
> These resources are often attached devices like hardware accelerators. With DRA,
> device drivers and cluster admins define device classes that are available to claim in
> workloads. Kubernetes allocates matching devices to specific claims and places the
> corresponding Pods on nodes that can access the allocated devices."

Two nouns in there carry the design, and they are worth meeting properly.

A **DeviceClass** is the catalogue entry. In the documentation's words, it *"lets cluster
admins or device drivers define categories of devices in the cluster. DeviceClasses tell
operators what devices they can request and how they can request those devices."* This is
the platform team's artifact: the same paved-road move from Volume I's Chapter 3,
applied to hardware. Somebody who understands the fleet defines what kinds of device
exist and how to ask for them, once, so that nobody else has to know.

A **ResourceClaim** is the request. Again from the documentation:

> "A ResourceClaim defines the resources that a workload needs. Every ResourceClaim has
> requests that reference a DeviceClass and select devices from that DeviceClass.
> ResourceClaims can also use selectors to filter for devices that meet specific
> requirements, and can use constraints to limit the devices that can satisfy a request."

And the filtering is not string matching on node labels. DRA uses **CEL** (the Common
Expression Language, a small expression language already used elsewhere in Kubernetes for
policy), so a claim can express a real predicate over a device's actual attributes rather
than a hopeful match against a label somebody remembered to apply.

That is the substantive shift, and it is worth naming plainly. The request moved from
*"give me one of the things you called gpu"* to *"give me a device satisfying these
properties."* The first is a count of an opaque token. The second is a description that
the system can evaluate against what the hardware actually reports about itself.

Notice, too, that a ResourceClaim is a *Kubernetes object*, with a name, a spec, a
status, sitting in the same store as everything else, exactly as Volume I's Chapter 7
described. Which means the thing your Pod refers to when it asks for hardware is now a
real referent, not a string. That is a smaller change than it sounds and also a much
bigger one, and Chapter 9 comes back to why.

## The gap this leaves, and it is a real one

Now put DRA together with the failure this chapter opened on, and be honest about what
has and has not been fixed.

DRA gives you a far better way to *ask for* an accelerator. It says nothing about the
QoS classification, which still looks only at processor time and memory. That statement
from the documentation is unchanged: containers requesting other resources can still be
`BestEffort`.

So the eviction ranking machinery from Volume I (the one that decides who dies when a
machine runs short) remains blind to the most expensive thing on the machine. A Pod
holding eight accelerators still needs to declare ordinary memory and processor requests
if it wants the eviction machinery to treat it as anything other than a Pod that asked
for nothing.

I want to be careful about how I put this, because it would be easy to overclaim. This
is not a defect in DRA; DRA is an allocation mechanism and QoS is an eviction-ranking
mechanism, and they are answering different questions. But the *operational* consequence
is real and I have not seen it stated plainly: the two systems do not know about each
other, and the person who has to bridge them is you, by remembering to write memory and
processor requests on a Pod whose interesting resource is neither.

That is a small, specific, checkable piece of configuration hygiene (a container with a
device claim and no memory request), which is precisely the sort of thing that Volume I's
Chapter 14 argued a compiler should catch at the line you wrote it. Whether that is
worth building is a question Chapter 9 returns to.

## What to carry forward

Three things, and the rest of Part II builds on all of them.

**The two-number model does not transfer.** For accelerators, request equals limit by
rule; there is no headroom and no bursting. If you are reasoning about accelerator
capacity using the intuitions from Volume I, you will be wrong in the optimistic
direction.

**Asking for hardware is now a typed query, not a count.** DRA's DeviceClass and
ResourceClaim replace an opaque integer with a description evaluated against what the
device actually is. This is the same movement, from hopeful string to checked reference,
that Volume I spent its last three chapters arguing for.

**The classification machinery has not caught up.** Accelerators are invisible to QoS.
Declare ordinary resources on accelerator workloads, or the eviction ranking will treat
your most expensive Pod as your least important one.

## Read the source

### Verified against primary sources

- **Scheduling GPUs**: the rule that device limits and requests must be equal and that
  devices are whole numbers:
  https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/
- **Pod Quality of Service Classes**: the exact QoS criteria, and the explicit statement
  that containers requesting resources other than CPU and memory can still be
  `BestEffort`: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- **Dynamic Resource Allocation**: the definition quoted above, the stability status in
  v1.35, `ResourceClaim`, `DeviceClass`, CEL-based selection, and the characterisation of
  what device plugins could not do:
  https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/
- **Volume I, Chapter 10**: the requests/limits/QoS model this chapter renegotiates:
  [Resources, scheduling, and autoscaling](../../notes/10-resources-scheduling-and-autoscaling.md)

### Reported by (attributed)

- Nothing in this chapter rests on reported practice. Every claim above is either quoted
  from the Kubernetes documentation or is my own reasoning, marked below.

### My argument, not established fact

- That accelerator memory is meaningfully *less* overcommittable than system memory
  because model weights are hot on every forward pass is my reasoning about why the
  compressible/incompressible distinction from Chapter 10 does not extend. It is not a
  claim I am quoting from a specification.
- That the disconnect between DRA and QoS classification is an operational gap worth
  checking for in configuration is my argument. The two mechanisms answering different
  questions is a design fact; calling the seam between them a problem is a judgement.

---

*You can now ask for hardware properly. But a training job does not want one accelerator;
it wants sixty-four of them, at the same instant, and it would rather have none than
sixty-three. The scheduler you met in Volume I cannot express that, and the fix
reintroduces a deadlock whose shape you already know.*
→ [Work that cannot start halfway](../../notes/ai/03-work-that-cannot-start-halfway.md)
