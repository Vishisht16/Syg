# Chapter 4: Shipping a Model

*Verified against: OCI Image Specification and Volume I's treatment of image layers.
Measurements reported from an arXiv preprint, attributed below. Checked August 2026.*

Volume I's Chapter 5 made an argument about container images that was completely correct
and is about to stop being useful.

The argument went: an image is a stack of read-only layers, identified by the
cryptographic hash of their contents. Because the layers are immutable and
content-addressed, they can be *shared*: ten containers built from the same base image
do not carry ten copies of that base on disk or over the wire. They share one set of
layers and differ only in the thin top layer that is theirs. This is why images are far
more efficient to store and transfer than shipping ten full filesystem tarballs, and it
falls straight out of making the lower layers immutable.

Every word of that remains true. Now put a model in it.

## The number that breaks the argument

Layer sharing is efficient in proportion to how much of your image is *shared*. A typical
web service image is a base operating system layer, a language runtime layer, some
libraries, and then a few megabytes of your application. The first three are shared with
every other service in your company. The unique part (the part that must actually be
transferred when you deploy) is small.

A model server inverts that ratio completely. The base layers and the runtime are still
there and still shared. But sitting on top is a payload of model weights measured in tens
or hundreds of gigabytes, shared with *nothing*, because it is the entire point of this
particular deployment.

So the economics reverse. The layer-sharing machinery still works; it is simply now
optimising the negligible part of the transfer while the dominant part gets no benefit
from it at all.

A preprint by Georgii Kliukovkin, studying exactly this problem on Kubernetes, opens with
the consequence stated as plainly as I could want:

> "The startup latency of a model-serving pod on Kubernetes is dominated by one step:
> delivering the model weights."

Sit with what that means for everything Volume I taught you about Pods being cheap to
replace. Chapter 5 of that volume argued that immutability and disposability are what
make the whole system work: an orchestrator can freely kill a container and start an
identical replacement somewhere else, confident it will behave the same. That confidence
is intact. What has changed is the word *freely*. Replacement is no longer nearly free;
it is the dominant cost of every operation that involves moving a workload.

And every operation in Volume I involves moving a workload. Rolling updates replace Pods.
Node drains replace Pods. Autoscaling creates Pods. Eviction destroys Pods that then get
recreated elsewhere. All of that machinery was designed when the marginal cost of a new
Pod was seconds.

## Where the weights actually come from

There are broadly three ways to get weights into a serving container, and the choice has
consequences you can predict from Volume I.

**Bake them into the image.** The weights become layers, and the whole thing is one
content-addressed artifact. This is the most honest option in one specific way: it
preserves the property Volume I cared most about, which is that the image digest
identifies *everything* the container will run. Pin the digest and you have pinned the
model. The cost is enormous images and a registry doing work it was not designed for.

**Fetch them at startup from object storage.** The image stays small; an init container
downloads the weights before the serving container starts. This is the pattern most
model-serving stacks default to, and it is where the term **storage initializer** comes
from: an injected container whose only job is to pull the model from wherever it lives
into a volume the real container will read.

Notice, though, what this costs you in Volume I's terms. The image digest no longer
identifies what runs. Two Pods from the identical image can serve *different models* if
the thing at the other end of that storage path changed between them. If that sounds
familiar, it should: it is precisely the mutable-tag trap from Volume I's Chapter 5, in a
new location. There, the danger was that a tag is a pointer that can be moved while the
digest is the content. Here, the storage path is the pointer, and nothing about the Pod
records which bytes it actually got.

**Mount them from somewhere already local.** A shared volume, or a node-local cache that
survives Pod restarts, so that the second Pod scheduled onto a machine does not repeat
the download.

## The measurement that makes the third option obvious

That preprint compared these approaches on models from two to a hundred and forty
gigabytes (one-billion, seven-billion, and seventy-billion parameter classes). The
headline comparison, for a seventy-billion-class artifact:

- delivered as a node-cached OCI artifact: **11.7 seconds**
- re-downloaded from object storage: **40.7 minutes**

That is reported as a factor of roughly two hundred. The paper is also honest about the
cost side of the trade, noting that the first cold pull costs up to twice a plain
download, and that verifying hashes during transfer added under 0.1% overhead.

I want to be careful about how much weight to put on these numbers. This is a
single-author preprint rather than a peer-reviewed result or a vendor benchmark with an
independent replication, and the figures will depend enormously on hardware, network, and
storage backend. Treat them as an illustration of the *shape* of the problem (the gap
between a warm local read and a cold remote fetch is very large) rather than as figures
to plan capacity against.

The shape is what matters, and the shape is: **once the payload is large, where it comes
from dominates everything else about your startup time.**

## Why scale-to-zero becomes a different proposition

Now combine that with something Volume I treated as straightforwardly good.

Scaling to zero (running no copies at all when there is no traffic, and starting one
when a request arrives) is the purest expression of the cloud economics from Volume I's
Chapter 4. You pay for what you use; when you use nothing, you pay nothing. For an
ordinary web service with a two-second startup, the only cost is that the first request
after an idle period is a little slow.

For a model server, the first request after an idle period waits for the weights. If that
is minutes, scale-to-zero is not a pricing optimisation, it is an outage with a schedule.

This is why so much engineering effort in this space goes into things that look, from
Volume I's perspective, like elaborate workarounds: keeping warm pools of pre-loaded
replicas, caching weights on nodes so a restart is a local read, pre-fetching onto
machines before the Pod that needs them is scheduled. They are all attacking the same
number, and that number exists because the disposability assumption underneath the
orchestrator's whole design has quietly weakened.

I do not think that assumption is *broken*. Pods are still replaceable and the
reconciliation loop still works. But there is now a real cost attached to an operation
the system treats as free, and every piece of machinery that replaces Pods casually
(rolling updates, drains, autoscaling) is spending that cost on your behalf without
knowing it.

## The pinning question, which is a Volume I question

There is one more thing worth extracting, because it connects directly to what this
project cares about.

Volume I's Chapter 5 ended its image discussion with a rule: pin to a digest, because a
tag is a mutable pointer and the registry will not enforce otherwise. The reasoning was
that you cannot reason about a system whose components can change identity underneath
you.

Everything in that argument applies to model weights, and almost nothing in the current
tooling enforces it. A serving deployment typically names a storage location and a
version string. Whether that combination will resolve to the same bytes tomorrow is a
property of somebody's storage bucket policy, not of your configuration.

So the honest summary is: the industry solved this problem properly for container images
(content addressing, digests, verifiable integrity) and has not finished solving it for
the artifact that now dominates the deployment. Some of the work to close that gap is
exactly the OCI-artifact approach measured above, which gets weights back inside the
content-addressed world where images already live. That seems to me the right direction,
and I am stating that as an opinion rather than a finding.

## What to carry forward

**Layer sharing optimises the part that no longer matters.** The economics argument from
Volume I is intact and no longer decisive.

**Startup time is dominated by weight delivery**, which turns every Pod-replacing
operation into something with a real cost attached.

**Where the weights come from determines whether your deployment is reproducible.** Baked
into the image, the digest pins everything. Fetched at runtime, the pointer can move, and
you have re-created the mutable-tag problem in a place with no digest to fall back on.

**Scale-to-zero means something different here**, and warm capacity stops being waste and
starts being architecture.

## Read the source

### Verified against primary sources

- **OCI Image Specification**: layers as content-addressed changesets, and the digest as
  identity: https://github.com/opencontainers/image-spec/blob/main/spec.md
- **Volume I, Chapter 5**: the layer-sharing argument and the mutable-tag trap this
  chapter extends: [Containers](../../notes/05-containers.md)
- **Volume I, Chapter 4**: the pay-for-what-you-use economics that scale-to-zero
  expresses: [The cloud](../../notes/04-the-cloud.md)

### Reported by (attributed)

- **Georgii Kliukovkin**, *"Cold-Start Model Delivery in Kubernetes Inference Serving: An
  Empirical Study of OCI-Based Distribution and Its Integrity"* (arXiv preprint): the
  statement that startup latency is dominated by weight delivery, and the 11.7-second
  versus 40.7-minute comparison for a seventy-billion-class artifact:
  https://arxiv.org/abs/2607.16596. A single-author preprint, not peer-reviewed or
  independently replicated; treat the magnitudes as illustrative.

### My argument, not established fact

- That runtime weight-fetching re-creates Volume I's mutable-tag problem in a place with
  no digest to fall back on is my argument. It follows from how the pieces work, but no
  specification says it.
- That warm capacity for model servers is architecture rather than waste is a judgement.
- That moving weights into the content-addressed world is the right direction is an
  opinion, stated as one.

---

*The weights are on the machine and the server is running. Now traffic has to reach it,
and the load-balancing machinery from Volume I, which spreads requests across
interchangeable replicas, is about to make an assumption that is not merely suboptimal
here but close to exactly backwards.*
→ [Serving a model](../../notes/ai/05-serving-a-model.md)
