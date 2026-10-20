# Chapter 5: Containers

Almost everyone who works near this technology carries a wrong picture of what a
container is, and the wrong picture is specific enough to name: they imagine a tiny,
lightweight virtual machine: the thing the last chapter described, only smaller. A
little computer-inside-the-computer, with its own miniature operating system, that
boots fast because it is small. It is a comfortable picture and it is completely
false, and holding it will quietly mislead you about performance, security, and how
the whole edifice above it works.

So let us take it apart and build the true picture from the kernel up, because once
you see what a container actually is, an enormous amount of Kubernetes stops being
magic and becomes obvious.

Here is the true picture, stated bluntly so we can spend the rest of the chapter
earning it: **a container is just a normal process running directly on the host's
Linux kernel, which has been lied to about the world around it and fenced in on how
much it can consume.** There is no guest operating system. There is no
virtualisation of hardware. There is no little computer. There is your host's one
kernel, running a process that happens to have a restricted view and a resource
cap. Everything else (the "isolation," the "image," the feeling that the process
lives in its own machine) is assembled from a handful of Linux kernel features
and a clever way of packaging files. Let us take those two halves in turn:
*isolation* (how the process is fenced off) and *packaging* (how its world is
shipped).

## Part one: isolation, or how to lie to a process convincingly

A container needs its process to *believe* it is alone on a clean machine, even
though it is sharing a kernel with dozens of other unrelated processes. The Linux
kernel provides exactly the tools to construct that illusion, and they are worth
knowing individually because their seams are where real production problems appear.

### Namespaces: controlling what a process can *see*

The first tool is the **namespace**. The kernel documentation defines it exactly:
a namespace "wraps a global system resource in an abstraction that makes it appear
to the processes within the namespace that they have their own isolated instance
of the global resource." Read that twice, because it is the whole idea. Normally,
certain resources are global to the machine: there is one list of process IDs, one
set of network interfaces, one filesystem tree, one hostname. A namespace takes one
of those global resources and gives a group of processes their *own private
instance* of it, so that what they see is not the machine's real state but a
partition of it that looks, from the inside, like the whole thing.

Linux has eight of these, and each isolates one specific global resource:

- The **mount** namespace (`CLONE_NEWNS`) gives the process its own set of
  filesystem mount points: its own idea of what the directory tree looks like.
  This is what lets a container have a completely different `/` from the host: the
  process sees a root filesystem that is really just some directory on the host,
  presented as if it were the top of the world.
- The **PID** namespace (`CLONE_NEWPID`) gives its own process-ID number space. The
  first process in a container becomes PID 1 *inside* (the `init` of its little
  world), while on the host it is some ordinary high-numbered PID. Processes inside
  cannot even see, let alone signal, processes outside, because to them those
  processes have no PID at all.
- The **network** namespace (`CLONE_NEWNET`) gives its own network stack: its own
  interfaces, IP addresses, routing table, and port space. This is the single most
  important namespace for understanding Kubernetes networking, and we will lean on
  it hard in Chapter 9. It is why a container can bind port 8080 "as if it owned
  the machine" while a dozen other containers on the same host also bind 8080:
  each has its own private network stack in which 8080 is free.
- The **UTS** namespace (`CLONE_NEWUTS`) isolates the hostname, which is why a
  container can have its own hostname distinct from the machine it runs on.
- The **IPC** namespace (`CLONE_NEWIPC`) isolates inter-process communication
  primitives (System V IPC, POSIX message queues), so containers cannot reach each
  other's shared-memory segments.
- The **user** namespace (`CLONE_NEWUSER`) isolates user and group IDs, and *maps*
  them: it can make a process that is UID 0 (root) *inside* the container map to
  some ordinary unprivileged UID *outside*. This is the security-critical one, so it
  is worth spending a sentence more on. Root inside a container is not a different
  kind of root: it is the same kernel's UID 0, and without a user namespace, root
  in the container is root on the host the instant the process escapes its other
  isolation. The mapping breaks that equality: the process can install packages and
  own files inside its own world exactly as root does, while the kernel accounts for
  it outside as some harmless UID like 100000, with none of root's authority over
  the host. This is the mechanism underneath a piece of advice you will meet
  everywhere (*don't run containers as root*), and it is also why that advice is
  worth following even when a user namespace is in play: the two are defences at
  different depths, not substitutes.
- The **cgroup** namespace (`CLONE_NEWCGROUP`) isolates the process's view of its
  own control-group hierarchy.
- The **time** namespace (`CLONE_NEWTIME`) isolates the boot and monotonic clocks.

A "container" is, mechanically, a process (or group of processes) placed into a
fresh set of these namespaces. When the process asks the kernel "what processes
exist?", the kernel answers from the process's PID namespace and it sees only its
own. When it asks "what network interfaces are there?", the kernel answers from its
network namespace. The process is not running in a sandbox that intercepts its
questions; it is asking the real kernel real questions and getting answers scoped
to its namespaces. The lie is told by the kernel itself, which is why it is both
so cheap and so convincing.

Now you can see why the "tiny VM" picture is wrong, and what it costs you to believe
it. Whenever a program wants something only the kernel can do (open a file, send a
packet, allocate memory, start another process), it asks, and those requests are
called **system calls**. They are the entire surface between a program and the
operating system. And a container's process makes them directly to the *host's*
kernel: the exact same kernel serving every other container and the host itself.
There is no second kernel anywhere in the picture.

This is why containers start in milliseconds (there is nothing to boot, you are just
starting a process inside some namespaces), and why they are so light you can run
hundreds on a laptop. But it is *also* why container isolation is fundamentally weaker
than a virtual machine's. Recall the shape of a VM from the last chapter: its own
guest kernel, with the hypervisor between it and the hardware, so a compromise inside
stays inside. A container shares the host kernel, so a single kernel vulnerability a
container process can trigger is a potential escape onto the host, and thus onto
every other container on it. This is not a flaw to be patched away; it is
intrinsic to the design's central trade. Containers buy their speed and density by
sharing the kernel, and the price of sharing the kernel is a shared attack surface.
(It is exactly this trade that projects like gVisor and Kata Containers exist to
buy back, by putting more of a boundary between the container and the real kernel,
at some cost in the speed and density that made containers attractive in the first
place.)

### Cgroups: controlling what a process can *consume*

Namespaces control what a process can *see*. They do nothing about what it can
*take*. A process alone in its namespaces can still try to allocate all the memory
on the machine, or peg every CPU, and starve everything else: isolation of view
is not isolation of resources. The second kernel feature closes that gap:
**control groups**, or **cgroups**.

A cgroup is a mechanism for organising processes into a hierarchy and imposing, on
each group, limits and accounting for the physical resources it uses. The modern
form, **cgroup v2**, presents a single unified hierarchy with a set of
*controllers*, each governing one resource. The two that matter most for
everything ahead are memory and CPU, and their behaviours are *different in kind*,
which is a distinction that will pay off enormously when we reach Kubernetes
resource management.

The **memory** controller enforces a hard ceiling. You can tell it that a group may
use, say, 512 MiB, and the kernel will hold the group to it. What happens on breach
is the important part: memory is not compressible: a process that needs a byte it
cannot get cannot simply be slowed down, it must be denied. When a group pushes
against its limit, the kernel first tries to *reclaim* memory from it (dropping
caches, swapping what it may); if reclaim cannot bring the group back under its
ceiling, the kernel's out-of-memory killer steps in and *kills* a process in that
group. This is the mechanism behind the dreaded `OOMKilled`
status you will meet in Kubernetes: it is not Kubernetes killing your container, it
is the Linux kernel's memory cgroup controller enforcing a hard limit the only way
a hard memory limit can be enforced: by terminating the offender.

The **CPU** controller behaves completely differently, because CPU *is*
compressible: a process that wants more CPU than it is allowed can simply be made
to wait. The controller offers two distinct knobs. One is *weight* (proportional
sharing): when CPU is contended, groups get time in proportion to their weights, so
a group is guaranteed a relative share but can burst higher when the machine is
idle. The other is a hard *bandwidth* cap (a quota per period): the group may use
at most, say, 50 milliseconds of CPU every 100, and when it exhausts that quota
before the period ends, the kernel *throttles* it, freezing its threads until the
next period begins. Throttling is CPU's version of the OOM kill, except nothing
dies: the process is merely stalled, which is why CPU pressure shows up as
mysterious latency spikes rather than crashes. That difference between the two
controllers (memory kills, CPU throttles) is not trivia; it is the physical
reason that Kubernetes treats memory and CPU so differently, and it is worth
carrying forward as your own hard-won knowledge rather than a rule to memorise.

Namespaces plus cgroups, then, are the whole of "isolation": the process sees a
private world (namespaces) and can consume only its allotted slice of the real one
(cgroups).

Three more mechanisms narrow things further, and they are worth knowing by name
because you will meet them in security discussions constantly. **Capabilities** break
root's authority into fragments, so a process can be given the one power it needs
instead of all of them. **Seccomp** (secure computing mode) is a kernel filter
listing which system calls a process may make at all; with a good filter, a
compromised process cannot even *reach* the dangerous ones. And **Linux Security
Modules**, of which **SELinux** and **AppArmor** are the common ones, enforce
*mandatory access control*: rules about what a process may touch, set by system
policy, which the process and its owner cannot relax. That last word is the point.
Ordinary file permissions can be changed by whoever owns the file; mandatory ones
cannot, which is exactly why they hold when an attacker owns the process.

That is the full toolbox from which "a container" is assembled. But we have only done
half the job. Isolating a process says nothing about *what* process, or where its
files come from, and that other half is what most people actually mean when they say
"container."

## Part two: packaging, or how to ship a process's entire world

Isolation makes a process *feel* alone on a clean machine. But a clean machine is
useless: your program needs its interpreter, its libraries, its configuration
files, an entire userland filesystem to run against. The disease the container image
cures is the oldest one in this field, and it has a name everyone knows: *works on my
machine*. The program ran on your laptop because your laptop happened to have the
right version of every library and file it depended on, and it broke in production
because that machine had subtly different ones. The image's job is to make that class of difference
*impossible* by shipping the program *together with its entire filesystem world*,
as one sealed, reproducible unit.

### Layers, and content addressing

An **OCI image** (OCI being the Open Container Initiative, the body that
standardised the format so it stopped belonging to Docker) is, at its heart, a
stack of read-only filesystem **layers**. The specification describes each layer as
"a changeset that describes a container's filesystem," and represents it as a tar
archive of files. Crucially, the layers *stack*: you take a base layer (say, a
minimal Linux userland), then a layer on top that adds your language runtime, then
a layer that adds your application's files, and the container's root filesystem is
what you get by unpacking these changesets *in order*, each one adding to or
overriding what is beneath it. At runtime a **union** (or **overlay**) filesystem
presents this stack as a single, ordinary-looking directory tree, and adds one
thin *writable* layer on top so the running container can create and modify files.
It does this by **copy-on-write**: a file from a lower read-only layer is left
exactly where it is until something tries to modify it, at which point the file is
copied up into the writable layer and the change is made to the copy. The original
is never touched. "Copy on write" is the whole rule in the name: do not copy when
you read, copy only at the moment of writing.

That "shared original" is doing quiet, important work. Because the lower layers are
read-only and identical across every container built from them, they can be
*shared*: ten containers built on the same base image do not carry ten copies of it
on disk or over the wire; they share the one set of base layers and differ only in
their top layers. This is why images are far more efficient to store and transfer
than shipping ten full filesystem tarballs, and it falls straight out of making the
lower layers immutable.

How does the system know two layers are "the same"? Through the second big idea:
**content-addressability**. Every layer, and the config, is identified not by a
name you chose but by the cryptographic hash (a SHA-256 **digest**) of its own
bytes. The identity *is* the content. This has consequences that ripple all the way
up to a Syg rule. Two layers with the same digest are, provably, byte-for-byte
identical, so deduplication and caching are exact and safe. A layer cannot be
tampered with without its digest changing, so integrity is verifiable by anyone who
recomputes the hash. And an image referenced by digest is *pinned to specific
bytes forever*: `myapp@sha256:9f3c…` does not mean "the latest myapp," it means
*that exact image and no other, for all time.*

### The manifest, the config, and the mutable-tag trap

Two more documents complete the picture. The **image manifest** is the small
top-level document that ties an image together: the spec says it contains "metadata
about the contents and dependencies of the image including the content-addressable
identity of one or more filesystem layer changeset archives"; that is, it lists,
by digest, the config and every layer that make up the image. The **image config**
is the document the manifest points at that holds the runtime settings baked into
the image: the default command to run, environment variables, the working
directory, exposed ports, and the ordered list of layer digests. When a runtime
prepares to start a container, it reads the manifest, fetches the config and the
layers it names by digest, stacks the layers into a root filesystem, and starts the
config's command inside a fresh set of namespaces and cgroups. That sentence is the
entire life-cycle of "running an image," and you now understand every word of it.

Images live in a **registry**, a content-addressable store you push images to and
pull them from by name. And here is where a subtlety becomes an operational hazard.
You usually refer to an image by a human-friendly **tag**: `myapp:1.4.2`, or the
infamous `myapp:latest`. But a tag is not the image. **A tag is a mutable pointer**:
it is a name in the registry that currently points at some digest, and whoever
controls the registry can move it to point at a different digest tomorrow. The
digest is the content; the tag is a label stuck to it that can be peeled off and
moved. This means that if you deploy `myapp:latest`, two machines that pull it a
minute apart can genuinely receive *different images*, because the tag moved in
between, and now you have a fleet running a mix of versions that you cannot tell
apart, rollbacks that don't roll back to what you think, and "it works on this Pod
but not that one" mysteries with no visible cause. The fix follows directly from
everything above: pin to a digest, or at minimum treat version tags as immutable by
convention, because the registry will not enforce it for you. Hold onto this one; a
Syg check acts on it directly.

## Immutability: the mental shift that changes operations

Step back from the mechanics and notice the shift in *stance* that images produce,
because it reorganises everything above them. Before containers, a server was a
long-lived thing you tended: you installed software on it, patched it in place,
fixed it when it drifted, and grew attached to it: the classic image is a *pet*,
named and nursed. An image inverts this completely. You do not patch a running
container; the whole point is that its lower layers are *read-only*. To change
anything real, you build a *new image*, with a new digest, and you *replace* the
running container with one built from the new image, throwing the old one away
entirely. Infrastructure becomes **immutable** and **disposable**: *cattle, not
pets*, in the industry's deliberately unsentimental phrase.

This is not merely a philosophy; it is what makes everything in the coming chapters
possible. Because a container is disposable and reproducible (built from pinned,
content-addressed layers so that the same image yields the same filesystem every
time), an orchestrator can freely kill one and start an identical replacement
somewhere else, confident it will behave the same. Replacing one version with the
next without downtime, restarting what has crashed, adding copies under load, moving
work off a machine that has died: every one of those is, underneath, an act of
*replacing containers*, and every one depends on a container built from an image
being reproducible and throwaway. Immutability is the ground the entire rest of the
system stands on.

## One last thing: nothing ever runs a bare container

One piece of vocabulary before the next chapter, because you will need it constantly
and it is a fact about containers rather than anything more advanced.

In practice, Kubernetes never places a single container on a machine. It places a
**Pod**: a wrapper around *one or more* containers that are guaranteed to run
together on the same machine, sharing a network address and able to share files.
The Pod, not the container, is the smallest thing the system will schedule.

Why wrap at all? Because a surprising number of useful containers only make sense
*next to* another one. A program that ships your application's logs somewhere
central has to be on the same machine, reading the same disk. A component that
handles encryption for your application's network traffic has to share its network
address to intercept it. These helpers are not separate services; they are part of
*this instance* of *this* application, and they must be placed, started, and killed
alongside it. Wrapping them together into one unit makes "these containers belong
to each other" a thing the system can understand and honour, rather than a hope.

That is the entire idea for now: **a Pod is one or more containers that live and die
together on one machine.** Chapter 8 returns to it properly: the lifecycle, what
happens when one of the containers crashes, and the controllers that create and
replace Pods on your behalf. Until then, whenever you read "Pod," you can safely
think *"the unit that holds my running container."*

## Where Syg stands

Containers are the atom Syg builds on, and two threads from this chapter connect
directly to the language. First, the image reference: because the tag-versus-digest
distinction is a genuine operational hazard grounded in how the OCI format works,
Syg parses image references *structurally* (pulling apart registry, repository,
tag, and digest rather than treating the whole thing as a string) so that a rule
([`mutable-image-tag`](../rules/identity.md#mutable-image-tag)) can reason about whether a reference is pinned or dangling on a
mutable tag. Second, and more quietly, the resource controllers you met here
(memory that kills, CPU that throttles) are the physical machinery underneath the
`resources` block you will write in Syg and the checks that guard it. When Chapter 10
explains why a Pod with no memory request is the first to die, it is this cgroup
memory controller doing the killing. Syg does not reimplement any of
this. It sits above it and helps you declare it without contradicting yourself.

## Read the source

- **`namespaces(7)`**: the Linux manual page enumerating every namespace type and
  what it isolates: https://man7.org/linux/man-pages/man7/namespaces.7.html
- **cgroup v2**: the kernel's admin guide, authoritative on the controllers,
  including the memory and CPU behaviour described here:
  https://docs.kernel.org/admin-guide/cgroup-v2.html
- **OCI Image Specification**: manifests, configs, layers, and content-addressable
  digests: https://github.com/opencontainers/image-spec/blob/main/spec.md
- **OCI Runtime Specification**: how a "bundle" (a root filesystem plus config) is
  actually run as a container: https://github.com/opencontainers/runtime-spec
- For a hands-on feel, the classic exercise is *"building a container from scratch"*
  using raw `clone(2)`, `unshare(1)`, and `pivot_root`: doing it once makes all of
  the above permanent.

---

*You can now run one container, and you understand precisely what that means. But
one container is a toy. Production is hundreds of them, across many machines,
dying and being replaced constantly, needing to find each other and survive the
loss of any single machine. Coordinating that is a genuinely hard problem, and the
answer to it (one single, beautiful idea) is the subject of the next chapter.* →
[Orchestration and desired state](../notes/06-orchestration-and-desired-state.md)
