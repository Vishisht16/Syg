# The Syg Engineering Notes

*A ground-up path through the ideas that make Syg necessary: DevOps, Platform
Engineering, and Kubernetes, taught properly, from first principles.*

---

## Who this is for

You can program. You have written software, you are comfortable in a terminal, you
understand processes and files and networks well enough to reason about them.

What you have probably never done is *run* software for other people. You may have
never been woken at 3 a.m. because something you wrote stopped working. You may not
know what a cluster is, or a deploy, or a rollback. You may have heard words like
*Kubernetes* and *DevOps* thrown around and quietly filed them under "things other
people understand", and you may not even know the vocabulary well enough to know
what to type into a search box.

**That is exactly the reader these notes are written for.** Not a beginner in
technology, but a stranger to this particular corner of it. Nothing here assumes you
have operated anything, and nothing here will ask you to already know a word in
order to learn the next one.

## What you will get

By the end you should be able to sit in a room with a platform engineer or a site
reliability engineer and follow every word, not because you memorised commands, but
because you understand the *mechanisms*: why a maintenance operation can hang
forever, why a perfectly healthy service can refuse every request, why a program
gets killed first when a machine runs short of memory, why an automatic scaler can
sit there doing nothing while your service is overwhelmed. You will know these the
way the people who debug them at 3 a.m. know them: as consequences of specific parts
of the system acting on specific pieces of your configuration.

Let me be honest about the edges of that promise. Reading cannot, by itself, make you
a specialist: specialists are made by breaking things and fixing them, under real
pressure, on real systems. What reading *can* do, and what these notes are built to
do, is give you the complete conceptual and mechanical foundation that specialists
stand on, in one place instead of scattered across fifty blog posts of varying
accuracy. Most people who work with this technology never learn that layer; they
learn incantations that work until they don't. You will learn the machine. When you
then go and practise, you will move far faster, because you will understand *why*
every lever does what it does.

## How to read this

A few things worth knowing before you start.

**Read it in order, and read it to the end.** Each chapter is built out of the one
before it, so skipping ahead is the one reliable way to make this harder than it needs
to be.

**No word is used before it is explained.** That is the promise the chapter order
exists to keep: the sequence of chapters *is* the order the ideas depend on each
other, and where a term has to appear a little early, it arrives with its meaning
attached, in the same sentence, rather than a note saying you will understand it
later. You should never be asked to carry a word you have not been given. If one does
get past me anyway, the [glossary](../notes/glossary.md) will settle it in five seconds, and
the failure is mine, not a gap in you.

**Chapters 1–3 are the most abstract, and that is deliberate.** They are about *why
this field exists at all* (the human and organisational problem), and they contain
almost no technology. If they feel a little airy while you are reading them, that is
normal and expected; they are laying down the *reasons* that the machinery from
Chapter 4 onward exists to serve. They are also the chapters most worth re-reading
once you have something concrete to attach them to. Coming back is not remedial; it
is how they are meant to be used.

**Chapter 4 onward is dense on purpose.** It goes all the way down to the real
mechanism, because a comfortable half-truth about how this system behaves is exactly
what gets people paged at 3 a.m. Nobody absorbs a chapter like that in one pass, and
you are not supposed to. Read it once for the shape, and return when you next need the
detail; each chapter re-grounds what it needs rather than assuming you memorised it.

**If something does not click, keep going.** This is the most useful thing I can tell
you. A surprising amount of confusion in this subject is not conceptual difficulty.
It is simply that the piece a concept rests on has not arrived yet. Two chapters
later, the thing that felt slippery is often obvious, because the foundation under it
got built. Nothing in these notes requires you to be clever or to grind through on
willpower. If you are confused, the honest response is usually "keep reading," not
"try harder."

## The map of the territory

Here are the words that will come up most, in the order you will meet them, one line
each. Every one of them is properly built where it belongs; this is only so that none
of them is a complete surprise. Do not try to learn the list: glance at it now, and
come back to it if you ever lose your bearings.

| Term | In one line | Chapter |
|---|---|---|
| **Virtual machine** | A software-simulated computer with its own operating system, which is what a cloud provider actually rents you. | 4 |
| **Region / availability zone** | A geographic area, and a separately-powered building inside it. The boundary a failure does not cross. | 4 |
| **Container** | A program packaged with everything it needs to run, isolated from its neighbours by the operating system. | 5 |
| **Image** | The frozen, shareable file-system contents a container is started from. | 5 |
| **Pod** | One or more containers that always live and die together on the same machine: the smallest unit the system places. | 5, 8 |
| **Kubernetes** | The system that runs Pods across a fleet of machines and keeps them running. | 6 |
| **Desired state / reconciliation** | You declare what you want; a loop continuously works to make reality match it. The central idea of the whole system. | 6 |
| **Cluster** | A set of machines running Kubernetes together, plus the brain that coordinates them. | 7 |
| **Node** | One machine in that cluster, where your containers actually run. | 7 |
| **Control plane** | The brain: it stores what you want, decides where things go, and drives reality toward it. | 7 |
| **Label / selector** | Key-value tags on objects, and the queries that pick out sets of them. How nearly everything is wired to everything else. | 7 |
| **Deployment** | The declaration that says "keep N identical copies of this program running, and update them safely." | 8 |
| **Service** | A stable address that stands in front of a constantly-changing set of Pods. | 9 |
| **Requests / limits** | How much processor and memory you reserve for a container, and the ceiling it may not cross. | 10 |
| **Probe** | A health test the system runs against your container to decide whether to restart it or send it traffic. | 11 |
| **ConfigMap / Secret** | Objects holding settings and credentials, kept outside your program so the same image runs anywhere. | 12 |

## The path

**Foundations: why any of this exists**

1. [The operational burden](../notes/01-the-operational-burden.md): why "operations" became a
   discipline of its own, and the tension every later idea is trying to resolve.
2. [DevOps, honestly](../notes/02-devops-honestly.md): what the word actually means once you
   strip the marketing, why feedback loops are the whole game, and where the idea
   hits its ceiling.
3. [Platform Engineering and the paved road](../notes/03-platform-engineering-and-the-paved-road.md):
   attention as the real constraint, the internal platform as the answer, and the
   philosophy Syg is built to serve.

**The substrate: where the machines come from**

4. [The cloud](../notes/04-the-cloud.md): computers rented through an API, where the line of
   responsibility falls, why zones are the geometry of survival, and the fact that
   makes everything after it necessary: a machine can be taken away with two minutes'
   notice.

**The machine: Kubernetes from the ground up**

5. [Containers](../notes/05-containers.md): what a container actually *is* (it is not a small
   virtual machine), assembled from Linux kernel features and stacked file-system
   layers. Ends by introducing the Pod.
6. [Orchestration and desired state](../notes/06-orchestration-and-desired-state.md): the most
   important idea in the system: the reconciliation loop, and why declaring *what you
   want* beats commanding *what to do*.
7. [The control plane and the object model](../notes/07-kubernetes-control-plane-and-object-model.md):
   the parts of a cluster, and the data model (`spec` and `status`, labels and
   selectors) that everything else is written in.
8. [Workloads](../notes/08-workloads.md): how your code actually runs: the Pod's lifecycle,
   how a Deployment owns its Pods, why one field can never be changed, and the
   specialised controllers for stateful software, per-machine agents, and batch jobs.
9. [Networking and service discovery](../notes/09-networking-and-service-discovery.md): the
   flat Pod network, how a Service finds its backends, DNS, and how outside traffic
   gets in. Ends on the failure that motivates Syg.

**Living with it: where production actually hurts**

10. [Resources, scheduling, and autoscaling](../notes/10-resources-scheduling-and-autoscaling.md):
    requests and limits, who gets killed when a machine runs short, how the system
    chooses where to place work, and how it adds and removes copies automatically.
11. [Staying up](../notes/11-staying-up.md): planned versus unplanned disruption, the safety
    policy that can deadlock a maintenance operation, and the health check that can
    restart your entire fleet at once.
12. [Configuration, identity, and security](../notes/12-configuration-identity-and-security.md):
    how configuration and credentials reach a container, how permissions are granted,
    and why network rules fail closed in surprising ways.

**The problem, and the answer**

13. [Why YAML hurts](../notes/13-why-yaml-hurts.md): the configuration problem all of this
    created, and the existing tools that try to tame it.
14. [Syg: prevention by construction](../notes/14-syg-prevention-by-construction.md): how
    everything above collapses into one idea: derive the resources from a single
    declaration so that whole classes of error become impossible to write.
15. [Becoming the specialist](../notes/15-becoming-the-specialist.md): how to keep going once
    the notes run out.

## Where Syg appears

Syg is the reason these notes exist, but it is not their subject: the field is. Most
chapters end with a short **Where Syg stands** note connecting the mechanism you just
learned to a specific part of the language. Those notes are deliberately small, and
you can skip every one of them and still get the full value of the material. Learn the
machine first; the language is the easy part once you understand what it protects you
from.

If you want Syg's own reasoning about a given mechanism, every rule it checks has
an explanation written to the same standard of primary-source honesty as these
notes: what goes wrong, the Kubernetes mechanism behind it, and what Syg can and
cannot claim about it. They start at [what Syg checks](../checks.md).

## On trusting any of this

Every claim here about how the system behaves is checked against primary
documentation, and each chapter ends with a **Read the source** section pointing at
exactly where to verify it. Trust none of this because I wrote it; trust it because
you followed the link and saw it for yourself. Where something is genuinely uncertain
or version-dependent, the text says so rather than papering over it.

## When you finish

There is a second volume, [Machine Learning and the Machines That Serve
It](../notes/ai/index.md), and it is a sequel in the strict sense: it assumes
everything here and repeats none of it. It covers the five mechanisms in these notes that
training and inference renegotiate (the resource model, the scheduler, image
distribution, service load balancing, and readiness), and then the harder question of what
changes when configuration is written by something other than a person.

Read it afterwards, not instead. This volume is the part that makes you useful; that one
is what you read when you want to know why some of it is being renegotiated.

Let's begin where the whole field begins: with the uncomfortable fact that running
software for other people is a fundamentally different job from writing it.

→ [Chapter 1: The operational burden](../notes/01-the-operational-burden.md)
