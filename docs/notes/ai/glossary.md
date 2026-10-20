# Glossary, Volume II

Every term here is built properly somewhere in the chapters. This page exists so that if
one gets away from you mid-paragraph, you can settle it in five seconds and carry on.

This volume assumes Volume I's vocabulary. For anything from there (Pod, Service,
selector, request, limit, QoS, probe, eviction), see the [Volume I
glossary](../../notes/glossary.md), which is not repeated here.

← [back to Volume II](../../notes/ai/index.md) · [Volume I](../../notes/index.md)

---

**AIOps**: a term coined by Gartner in 2016, originally for *Algorithmic IT Operations*
and redefined within about a year to *Artificial Intelligence for IT Operations*. In
practice its real content is statistical methods applied to operational telemetry: anomaly
detection, event correlation, and alert-noise reduction. → [Ch 8](../../notes/ai/08-aiops-honestly.md)

**Alert fatigue**: the failure mode where alerting rules fire so often, or so often
uselessly, that people stop attending to them. The genuine problem most of AIOps is aimed
at. → [Ch 8](../../notes/ai/08-aiops-honestly.md)

**All-or-nothing scheduling**: see **Gang scheduling**.
→ [Ch 3](../../notes/ai/03-work-that-cannot-start-halfway.md)

**CACE principle**: "Changing Anything Changes Everything." Sculley et al.'s name for the
fact that in a trained model no input is really independent, so altering one feature,
hyper-parameter or sampling choice can change the behaviour of the whole thing.
→ [Ch 7](../../notes/ai/07-mlops-honestly.md)

**Checkpointing**: periodically writing a training job's state to durable storage so that
an interrupted job can resume rather than restart. What makes cheap reclaimable capacity
coherent for long-running training. → [Ch 6](../../notes/ai/06-staying-up-at-model-scale.md)

**Cold start**: the time between a model-serving Pod starting and its being able to answer
a request, dominated by delivering the model weights rather than by starting the process.
→ [Ch 4](../../notes/ai/04-shipping-a-model.md)

**DeviceClass**: a DRA object in which cluster admins or drivers define a category of
device available to be claimed, and how it may be requested. The platform team's artifact:
it says what kinds of hardware exist and how to ask for them.
→ [Ch 2](../../notes/ai/02-the-accelerator-is-not-a-processor.md)

**Device plugin**: the older mechanism by which a vendor agent advertised devices to a
node and handed them to containers. Superseded by DRA, which the Kubernetes documentation
notes fixes its three limitations: per-container requests, no sharing, and no
expression-based filtering. → [Ch 2](../../notes/ai/02-the-accelerator-is-not-a-processor.md)

**DRA (Dynamic Resource Allocation)**: the Kubernetes framework for requesting and sharing
devices, stable and enabled by default since v1.35. Replaces "give me one of the thing you
called gpu" with a description of the device you need, evaluated against what the hardware
reports. → [Ch 2](../../notes/ai/02-the-accelerator-is-not-a-processor.md)

**Drift**: the degradation of a model's performance over time because the world it is
predicting about changed, while the model did not. The closest thing this field has to a
failure that requires no trigger. → [Ch 7](../../notes/ai/07-mlops-honestly.md)

**Endpoint Picker (EPP)**: the component in the Gateway API Inference Extension that
chooses which model server should receive a request, using metrics the servers emit rather
than rotation. → [Ch 5](../../notes/ai/05-serving-a-model.md)

**Entanglement**: the property that a trained model cannot be decomposed into parts that
can be reasoned about separately, which is why confidence comes from evaluation rather than
inspection. See also **CACE principle**. → [Ch 7](../../notes/ai/07-mlops-honestly.md)

**Feature store**: a system where a feature is defined once and both the training path and
the serving path read from that one definition, so the two cannot disagree. The field's
structural answer to training/serving skew. → [Ch 7](../../notes/ai/07-mlops-honestly.md)

**Gang scheduling**: placing a group of Pods all at once or not at all, because the
workload makes no progress with a subset running. Prevents the deadlock in which two
partially-placed jobs each hold a fraction of what the other needs.
→ [Ch 3](../../notes/ai/03-work-that-cannot-start-halfway.md)

**InferencePool**: the Gateway API Inference Extension object describing a group of Pods
serving models on shared compute, alike in accelerator type, base model and model server.
At v1. → [Ch 5](../../notes/ai/05-serving-a-model.md)

**Kueue**: the Kubernetes-native job queueing project providing all-or-nothing admission,
quota between queues, and topology-aware placement for batch and ML workloads.
→ [Ch 3](../../notes/ai/03-work-that-cannot-start-halfway.md)

**LoRA adapter**: a small set of additional weights that specialises a large base model for
a particular task, loaded on top of the base rather than replacing it. One server holding
one base model can serve many adapters, which makes "which adapters are loaded here" a real
routing constraint. → [Ch 5](../../notes/ai/05-serving-a-model.md)

**MLOps**: the practice of giving data and models the lifecycle guarantees code already
had: versioning, reproducibility, testing, deployment, rollback and monitoring. Not a team
or a tool list. → [Ch 7](../../notes/ai/07-mlops-honestly.md)

**Model registry**: a system recording which model version exists and which is deployed, so
that "what is running" is answerable the way an image digest answers it for code.
→ [Ch 7](../../notes/ai/07-mlops-honestly.md)

**Prefix cache**: the retained intermediate computation for the text a model server has
already processed in a conversation. A server holding your prefix can continue far more
cheaply than one starting fresh, which makes it the most valuable inference routing signal.
→ [Ch 5](../../notes/ai/05-serving-a-model.md)

**Prevention versus detection**: Volume I's distinction between making an error
unrepresentable and reporting it after the fact. Chapter 9 argues the distinction changes
character when the author is not human, because detection assumes a reader.
→ [Ch 9](../../notes/ai/09-when-the-author-is-not-human.md)

**ResourceClaim**: a DRA object stating what a workload needs, referencing a DeviceClass
and using selectors and constraints to filter for devices meeting specific requirements.
A real object with a name and a status, rather than an integer count of an opaque token.
→ [Ch 2](../../notes/ai/02-the-accelerator-is-not-a-processor.md)

**Startup probe**: the probe that holds liveness and readiness off until it succeeds. Rare
in Volume I's world, load-bearing here, because it is what lets you answer "how long may
starting take?" and "how long may hanging take?" with different numbers.
→ [Ch 6](../../notes/ai/06-staying-up-at-model-scale.md)

**Storage initializer**: an injected init container that downloads model weights from
object storage into a volume before the serving container starts. Convenient, and it costs
you the property that the image digest identifies what runs.
→ [Ch 4](../../notes/ai/04-shipping-a-model.md)

**Topology Aware Scheduling**: placement that accounts for the physical arrangement of
machines, because for tightly-coupled training the distance between workers can dominate
runtime in a way resource counts cannot express.
→ [Ch 3](../../notes/ai/03-work-that-cannot-start-halfway.md)

**Training/serving skew**: the failure where features are computed one way during training
and a subtly different way at serving time, so the model answers a different question than
it was trained on, confidently and with no error anywhere.
→ [Ch 7](../../notes/ai/07-mlops-honestly.md)
