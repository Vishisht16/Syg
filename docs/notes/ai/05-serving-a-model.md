# Chapter 5: Serving a Model

*Verified against: Kubernetes Gateway API Inference Extension documentation and the
Kubernetes blog announcing it. `InferencePool` is at v1. Checked August 2026.*

This is the chapter where Volume I is not merely incomplete but actively wrong, and I
want to earn that claim carefully, because it is a strong thing to say about material I
spent fifteen chapters building.

Volume I's Chapter 9 constructed service discovery from the ground up. A Service holds a
label selector. The EndpointSlice controller continuously scans for ready Pods matching
that selector and maintains the list of their addresses. `kube-proxy` programs kernel
rules on every node so that a packet aimed at the Service's virtual address is rewritten
to one of those Pods. The load balancing happens down in the kernel, invisibly, with no
cooperation from your application.

That design rests on one assumption, stated in Volume I as the reason it works: **one
replica is as good as another.** Requests are short, stateless, and interchangeable, so
spreading them evenly across ready backends is very close to optimal, and the cheapest
way to do it is the best way.

Hold that sentence next to what a language model server actually is.

## Why the assumption fails

The Kubernetes blog introducing the Gateway API Inference Extension states the mismatch
directly, and it is worth quoting in full because every clause is load-bearing:

> "Unlike typical short-lived, stateless web requests, LLM inference sessions are often
> long-running, resource-intensive, and partially stateful. For example, a single
> GPU-backed model server may keep multiple inference sessions active and maintain
> in-memory token caches."

Take the three properties one at a time, because each breaks a different part of the
Volume I picture.

**Long-running.** An ordinary web request occupies a backend for milliseconds. A
generation request can occupy one for many seconds, sometimes minutes. When requests are
short, an unlucky distribution evens out almost immediately: send two requests to the
same backend and the imbalance has evaporated by the time you notice. When requests are
long, an unlucky distribution *persists*: a backend that received three long requests is
saturated for the duration, while a neighbour sits idle, and round-robin cheerfully sends
it a fourth because round-robin is not looking.

**Resource-intensive.** The cost of a request is not uniform, and it is not knowable from
the connection. Two requests to the same endpoint can differ by orders of magnitude in
work depending on how much text is being processed and generated. Counting connections
(which is the most sophisticated thing a conventional load balancer typically does) is
therefore a poor proxy for load, because one connection is not one unit of anything.

**Partially stateful.** This is the one that turns the problem from "suboptimal" into
"backwards." Those in-memory token caches mean a model server accumulates state that is
*specific to the conversation it has been handling*. A backend that has already processed
the first four thousand tokens of your conversation can continue it far more cheaply than
a backend starting from nothing, because the expensive intermediate computation is
already sitting in its memory.

So the replicas are not interchangeable. They are differentiated by what they happen to
remember. And Volume I's machinery (kernel rules that rewrite a destination address with
no knowledge of anything above the packet) is structurally incapable of knowing that,
because it was designed by people who correctly observed that it did not matter.

The blog is blunt about the consequence for existing infrastructure: traditional load
balancers focused on HTTP path or round-robin *"lack the specialized capabilities needed
for these workloads,"* and *"don't account for model identity or request criticality
(e.g., interactive chat vs. batch jobs)."*

That last point is worth pausing on separately. In Volume I, a Service fronted one thing.
Here, one pool of expensive hardware may be serving several models, and several *classes*
of request against them: an interactive chat where a human is watching the cursor blink,
and a bulk batch job where nobody is. Those have completely different latency
requirements and completely different claims on the hardware when it is contended. There
is no field anywhere in a Service that can express that distinction.

## What replaced it

The **Gateway API Inference Extension** is the Kubernetes project addressing this. It
does not replace Services or the Gateway API; it extends the routing layer with types
that understand what is behind them.

The central object is the **InferencePool**. Its documentation describes it as a group of
Pods dedicated to serving AI models, where the Pods within a pool share the same compute
configuration, accelerator type, base model, and model server. The `InferencePool` API has
graduated to **v1**.

Notice the design decision embedded in that definition, because it is the same one Volume
I kept pointing at. The pool is defined by *homogeneity*: these Pods are alike in the ways
that matter for routing. That is what makes it possible to reason about them as a set
while still distinguishing between them by live state.

The routing decision itself is made by a component the project calls an **Endpoint
Picker** (the reference implementation is usually written EPP). Rather than a kernel rule
picking a backend by rotation, the Endpoint Picker consumes metrics emitted by the model
servers themselves and chooses an endpoint based on what those servers are actually
doing. The documentation names the kinds of signal it can route on, including prefix
cache status and the availability of particular LoRA adapters.

Two pieces of vocabulary there, since the volume promised not to use a word before
explaining it.

A **prefix cache** is the retained intermediate computation described above: the part of
the work that depends only on the text seen so far. If a server already holds the prefix
for your conversation, continuing it is dramatically cheaper than starting elsewhere, so
"which server has my prefix" is genuinely the most valuable routing signal available.

A **LoRA adapter** is a small set of additional weights that specialises a large base
model for a particular task, loaded on top of the base model rather than replacing it.
One server holding one base model can serve many adapters. So "which adapters does this
server currently have loaded" is a real constraint on where a request can usefully go;
routing to a server that would have to load an adapter first is a different proposition
from routing to one that already has it.

Put those together and the shape of the change is clear. Volume I's routing decision was
*"pick any ready backend"* and could be made in the kernel with no information. The
inference routing decision is *"pick the backend whose current in-memory state makes this
particular request cheapest, subject to how loaded it already is"*, and that requires
application-level knowledge that the kernel could never have had.

## The separation of concerns, and why it is familiar

There is a second thing the extension does that has nothing to do with performance, and
it is arguably the more durable contribution.

The blog describes the ownership split: a pool object lets platform operators manage
*where and how* models are served (the compute, the scaling, the accelerator type),
while a separate user-facing object lets the AI/ML owners manage *what* is served, mapping
a public model name to the actual model within a pool.

If that reads as familiar, it should. It is precisely the platform-engineering move from
Volume I's Chapter 3: the platform team owns the complex substrate and offers it as a
service; the stream-aligned team consumes it through an interface sized to their actual
job. A data scientist should be able to say "serve this model under this name" without
knowing which accelerator family the pool runs on, and a platform engineer should be able
to change the accelerator family without every model owner rewriting anything.

I flag one caution here. The exact names and shapes of the user-facing objects in this
extension have moved during its development: this is a young API in a fast-moving area,
and the model-facing type in particular has been revised. The `InferencePool` at v1 is the
stable part. If you are implementing rather than learning, check the current API reference
rather than trusting the names in any prose written months earlier, including this.

## What Volume I still gets right

It would be easy to over-rotate here, so let me be precise about the boundary.

Everything structural from Volume I still holds. The Pods are still Pods. They are still
selected by labels. Their readiness still governs whether they receive traffic, and
readiness is still the thing the next chapter is about. The reconciliation loop still
maintains the mapping. An `InferencePool` is a Kubernetes object with a spec and a status
like everything else, watched and reconciled by a controller, exactly as Volume I's
Chapter 7 described.

What changed is one layer: **who makes the per-request decision, and with what
information.** Volume I's answer was "the kernel, with none." That answer was right for
the workload it was designed for and remains right for the overwhelming majority of
traffic in the world. It is wrong for this one, and the fix was not to change the
foundation but to add a component above it that knows more.

That is worth noticing as a pattern, because it is how this whole field has absorbed
machine learning. Not by replacing the orchestrator, but by adding objects that carry the
extra knowledge the general mechanism could not.

## What to carry forward

**Interchangeability was an assumption, and it is now false.** A model server's replicas
differ by what they remember, which makes "any ready backend" the wrong answer.

**Connection counts are a bad proxy for load** when request costs vary by orders of
magnitude.

**Routing moved up the stack**, from kernel packet rewriting to an application-aware
component consuming server metrics, because the necessary information does not exist at
the packet level.

**The ownership split is the platform pattern again** (pool operators own where and how,
model owners own what), and that part will outlast the current API names.

## Read the source

### Verified against primary sources

- **Introducing Gateway API Inference Extension** (Kubernetes blog): the description of
  inference sessions as long-running, resource-intensive and partially stateful; the
  inadequacy of round-robin and HTTP-path load balancing; and the ownership split between
  pool and model:
  https://kubernetes.io/blog/2025/06/05/introducing-gateway-api-inference-extension/
- **Gateway API Inference Extension documentation**: `InferencePool` at v1, the Endpoint
  Picker, and routing on prefix-cache status and LoRA adapter availability:
  https://gateway-api-inference-extension.sigs.k8s.io/ and the `InferencePool` API
  reference: https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/
- **Volume I, Chapter 9**: the Service, EndpointSlice and kube-proxy machinery this
  chapter renegotiates:
  [Networking and service discovery](../../notes/09-networking-and-service-discovery.md)

### Reported by (attributed)

- Nothing here rests on unattributed reported practice. The explanations of prefix caching
  and LoRA adapters are my own descriptions of mechanisms the documentation names but does
  not define.

### My argument, not established fact

- That Volume I's routing model is *backwards* rather than merely suboptimal for this
  workload is my characterisation. The documentation says traditional load balancing lacks
  needed capabilities; calling it backwards is my stronger phrasing, and it rests on the
  prefix-cache point: that the cheapest backend is a specific one, not any one.
- That the pool/model ownership split will outlast the current API names is a prediction,
  and predictions in this area age badly. I include it because the underlying pattern is
  from Volume I's Chapter 3 and considerably older than this API.

---

*Traffic now reaches the right server. But Volume I's mechanism for deciding whether a
server should receive traffic at all assumed the question was cheap to answer. Here the
honest answer is "ask me again in four minutes", and the machinery has one field that
was built for exactly this and is almost always left empty.*
→ [Staying up at model scale](../../notes/ai/06-staying-up-at-model-scale.md)
