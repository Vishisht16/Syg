# Glossary

Every term here is built properly somewhere in the chapters; this page exists so that
if one gets away from you mid-paragraph, you can settle it in five seconds and carry
on reading rather than scrolling backwards to find where you met it. Each entry says
what the thing *is* in a sentence or two and links to the chapter that develops it.

A definition is not a substitute for that chapter. It can tell you what a word means;
only the chapter can tell you why the thing exists and how it fails, which is the part
that actually makes you useful.

← [back to the notes](../notes/index.md)

---

**Alerting**: rules evaluated over monitored measurements that summon a human when
something crosses a line that matters. Monitoring produces the numbers; alerting decides
which of them are worth waking someone for. → [Ch 2](../notes/02-devops-honestly.md)

**API (application programming interface)**: a defined way for one program to ask
another to do something. Cloud providers put one in front of acquiring a machine, which
is what turned procurement into a function call and made infrastructure-as-code
possible. → [Ch 4](../notes/04-the-cloud.md)

**AppArmor**: see **Mandatory access control**. → [Ch 5](../notes/05-containers.md)

**Availability**: the fraction of time a system is usefully serving requests, usually
quoted as a percentage ("three nines" = 99.9%). Converting it to permitted downtime per
month is what makes it concrete. → [Ch 1](../notes/01-the-operational-burden.md)

**Availability zone (AZ)**: "one or more discrete data centers with redundant power,
networking, and connectivity" inside a region, physically separated by many kilometres.
The boundary a power or cooling failure does not cross, which is why copies that must
survive independently belong in different zones. → [Ch 4](../notes/04-the-cloud.md)

**Blameless postmortem**: a written review after an incident that treats the failure as
a property of the system rather than the fault of a person, so that people report
problems instead of hiding them. → [Ch 2](../notes/02-devops-honestly.md)

**cgroup (control group)**: the Linux kernel feature that limits and accounts for the
resources a group of processes may consume. Memory limits are enforced by killing;
processor limits by slowing down. → [Ch 5](../notes/05-containers.md)

**CI / Continuous Integration**: the discipline of merging every change back into the
shared main line of code constantly (at least daily), with an automated build and test
on each merge, so that integrating work never becomes a large painful event. → [Ch 2](../notes/02-devops-honestly.md)

**Cloud**: other people's computers, in other people's buildings, rented by the hour
and controlled through an API. The API is the part that changed engineering. → [Ch 4](../notes/04-the-cloud.md)

**Cluster**: a set of machines running Kubernetes together, plus the control plane that
coordinates them. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**ConfigMap**: a Kubernetes object holding non-secret configuration data that can be
handed to a container as environment variables or files. → [Ch 12](../notes/12-configuration-identity-and-security.md)

**Container**: a normal process running on the host's kernel that has been given an
isolated view of the system (its own file system, network, process list) and a cap on
what it may consume. Not a small virtual machine. → [Ch 5](../notes/05-containers.md)

**Container image**: the frozen, shareable file-system contents plus metadata that a
container is started from, built as a stack of read-only layers identified by
cryptographic hash. → [Ch 5](../notes/05-containers.md)

**Control plane**: the "brain" of a cluster: it stores the desired and current state,
decides where work should run, and runs the loops that drive reality toward what you
declared. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**Controller**: a program running a non-terminating loop that compares desired state to
current state and acts to close the gap. Kubernetes is built almost entirely out of
these. → [Ch 6](../notes/06-orchestration-and-desired-state.md)

**Copy-on-write**: the rule that a shared file is left alone until something tries to
modify it, at which point a private copy is made and the change applied to the copy. It
is how a container writes to a filesystem assembled from read-only image layers without
altering them. → [Ch 5](../notes/05-containers.md)

**CRI (Container Runtime Interface)**: the fixed API through which the kubelet asks
whichever container runtime is installed to pull images and start containers. The
indirection is why clusters could switch runtimes without any user-written object
changing. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**DaemonSet**: the declaration that says "run exactly one copy of this Pod on every
machine," used for per-machine agents. → [Ch 8](../notes/08-workloads.md)

**Data plane**: the worker nodes: the layer that carries the actual work, as opposed
to the control plane that decides about it. The split is a general architectural idea,
not a Kubernetes invention. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**Declarative**: describing the end state you want and letting the system work out how
to get there and stay there, as opposed to *imperative*: issuing the steps yourself. →
[Ch 6](../notes/06-orchestration-and-desired-state.md)

**Deploy / deployment (the act)**: pushing a new version of software out to the
machines that serve real users. → [Ch 1](../notes/01-the-operational-burden.md)

**Deployment (the object)**: the Kubernetes declaration that says "keep N identical
copies of this program running, and replace them safely when I change the version." →
[Ch 8](../notes/08-workloads.md)

**Desired state / current state**: what you asked for (`spec`) versus what is actually
true right now (`status`). Every Kubernetes object carries both. → [Ch 6](../notes/06-orchestration-and-desired-state.md)

**DNS**: the naming system that turns a stable name into an address, letting programs
find a service by name rather than by a location that keeps changing. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**East-west / north-south**: east-west traffic stays inside the cluster, Pod to Pod;
north-south crosses the boundary between the cluster and the outside world. The names
come from how architecture diagrams are conventionally drawn. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**Egress / ingress (traffic directions)**: egress is traffic a Pod sends out; ingress
is traffic arriving at it. Network policy tracks the two independently, which is the
source of its most common surprise. (Not to be confused with the **Ingress** object,
which is a north-south HTTP router.) → [Ch 12](../notes/12-configuration-identity-and-security.md)

**Elasticity**: the ability to acquire capacity for an hour and give it back. It turns
capacity from a fixed frame into a dial, and turns every resource number you write into
a recurring bill. → [Ch 4](../notes/04-the-cloud.md)

**EndpointSlice**: the continuously-updated list of addresses of the healthy Pods
currently backing a Service. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**Error budget**: the amount of failure your reliability target explicitly permits (the
gap between your target and 100%), used as a shared number to decide when to ship faster
and when to slow down and stabilise. → [Ch 1](../notes/01-the-operational-burden.md)

**etcd**: the distributed, consistent key-value store holding the entire state of a
cluster. The one component you protect above all others. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**Eviction**: the system deliberately removing a running Pod from a machine, either
because the machine is short of resources or because an operator is emptying it. → [Ch 10](../notes/10-resources-scheduling-and-autoscaling.md),
[Ch 11](../notes/11-staying-up.md)

**Extern**: a Syg declaration stating that a dependency exists outside the checked
world: a provider-managed database, for instance. Syg's model is closed, so what it
cannot see must be declared rather than silently ignored. → [Ch 4](../notes/04-the-cloud.md)

**Golden path / paved road**: the well-supported, opinionated way to do the common
thing, made so easy and safe that people choose it without being forced. → [Ch 3](../notes/03-platform-engineering-and-the-paved-road.md)

**Horizontal autoscaling**: automatically adding and removing copies of a program in
response to load. → [Ch 10](../notes/10-resources-scheduling-and-autoscaling.md)

**Hypervisor**: the layer between real hardware and virtual machines that gives each
guest a slice of the real processors and memory. It is why VM isolation is strong: the
only path out of a guest is through it. → [Ch 4](../notes/04-the-cloud.md)

**IaaS / PaaS / SaaS**: three common places to draw the line between what the provider
is responsible for and what you are: at the hypervisor (you run the operating system
upward), at the runtime (you hand over a program), or at the finished product. → [Ch 4](../notes/04-the-cloud.md)

**Infrastructure as code**: describing infrastructure in text that is
version-controlled, reviewed, and applied by a machine. Only possible because
infrastructure is acquired through an API. → [Ch 4](../notes/04-the-cloud.md)

**Ingress / Gateway**: the routing layer that maps external hostnames and URL paths to
internal Services, letting outside traffic reach your software. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**iptables**: the long-standing packet-filtering and address-rewriting engine built
into the Linux kernel. One of the two mechanisms kube-proxy uses to make a Service's
virtual IP resolve to a real Pod. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**IPVS (IP Virtual Server)**: a Linux kernel module built specifically for load
balancing. The other mechanism kube-proxy can use; it keeps backends in a hash table
rather than a rule list and so stays fast as the number of services grows. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**Job / CronJob**: declarations for work that runs to completion rather than forever,
optionally on a repeating schedule. → [Ch 8](../notes/08-workloads.md)

**kind / k3d**: tools that run a multi-node Kubernetes cluster on a laptop, each "node"
being a container rather than a real machine. Disposable, which is what makes them the
right place to break things on purpose. → [Ch 15](../notes/15-becoming-the-specialist.md)

**kubelet**: the agent running on every machine that starts and supervises the
containers assigned to it. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**Label / selector**: key-value tags attached to objects, and the queries that select
sets of objects by those tags. The main way resources are wired to each other and,
because nothing validates that a query matches anything, a common source of silent
failure. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**Level-triggered**: reacting to the current *state* of the world rather than to
*events*. It is why the system recovers from failures nobody wrote handling code for. →
[Ch 6](../notes/06-orchestration-and-desired-state.md)

**Lock-in**: the cost of leaving a provider, which rises with how deeply your software
depends on that provider's particular services, and which is paid at the worst moment,
after you have already decided to leave. → [Ch 4](../notes/04-the-cloud.md)

**Managed service**: infrastructure the provider operates for you: a database, a
queue, a cache. You trade cost and control for not carrying its pager. → [Ch 4](../notes/04-the-cloud.md)

**Mandatory access control**: an access-control model in which the rules about what a
process may touch are set by system policy and cannot be relaxed by the process or its
owner, unlike ordinary file permissions. SELinux and AppArmor are the Linux
implementations. → [Ch 5](../notes/05-containers.md)

**Monitoring**: continuously collecting measurements from a running system (request
rates, error counts, latencies, memory use) so that its behaviour is observable rather
than inferred. → [Ch 2](../notes/02-devops-honestly.md)

**Namespace (Kubernetes)**: a virtual partition of a cluster used to scope and separate
groups of objects. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**Namespace (Linux)**: a kernel feature giving a process its own private view of some
global resource (the process list, the network, the file system). → [Ch 5](../notes/05-containers.md)

**Node**: one machine in a cluster, where your containers actually run. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md)

**On-call / the pager**: the rotation that makes one engineer responsible for
responding when something breaks outside working hours. → [Ch 1](../notes/01-the-operational-burden.md)

**Pipeline (deployment pipeline)**: the automated road from a committed change to a
running production system: build, test, then a progression of stages, each a gate that
either lets the change through or stops it with a clear signal. → [Ch 2](../notes/02-devops-honestly.md)

**Pod**: one or more containers that always run together on the same machine, sharing a
network address and able to share files. The smallest unit the system schedules. → [Ch 5](../notes/05-containers.md)
(introduction), [Ch 8](../notes/08-workloads.md) (in full)

**PodDisruptionBudget**: a policy limiting how many copies of your software may be
voluntarily removed at once, protecting availability during maintenance, and capable of
deadlocking that maintenance if set wrong. → [Ch 11](../notes/11-staying-up.md)

**policyTypes**: the field on a NetworkPolicy naming which directions it governs. If
omitted, `Ingress` is *always* set and `Egress` is set only if the policy has egress
rules, which is how an intended egress-only policy silently cuts off inbound traffic. →
[Ch 12](../notes/12-configuration-identity-and-security.md)

**Probe**: a health test the system runs against a container. A *liveness* probe
decides whether to restart it; a *readiness* probe decides whether to send it traffic. →
[Ch 11](../notes/11-staying-up.md)

**QoS class**: the classification (Guaranteed, Burstable, BestEffort) that Kubernetes
derives from your resource requests and limits, which determines what gets killed first
when a machine runs short of memory. → [Ch 10](../notes/10-resources-scheduling-and-autoscaling.md)

**RBAC (role-based access control)**: the permission system: rules are written into
Roles, and a Role grants nothing at all until it is *bound* to an identity. → [Ch 12](../notes/12-configuration-identity-and-security.md)

**Reconciliation loop**: the continuous compare-and-correct cycle at the heart of
Kubernetes: read desired state, observe reality, act to close the gap, repeat forever. →
[Ch 6](../notes/06-orchestration-and-desired-state.md)

**Region**: a separate geographic area of a provider's infrastructure, "designed to be
isolated from the other Regions." Regions do not share fate, and by default do not share
your data. → [Ch 4](../notes/04-the-cloud.md)

**Registry**: the server that stores container images and serves them on request. → [Ch 5](../notes/05-containers.md)

**ReplicaSet**: the controller that keeps exactly N copies of a Pod template running.
Usually created and managed for you by a Deployment. → [Ch 8](../notes/08-workloads.md)

**Requests / limits**: how much processor time and memory a container reserves
(request) and the ceiling it may not exceed (limit). Requests drive placement and
survival; limits drive throttling and killing. → [Ch 10](../notes/10-resources-scheduling-and-autoscaling.md)

**restartPolicy**: the Pod field governing whether the kubelet restarts a container
that stops: `Always` (the default), `OnFailure`, or `Never`. It is the one repair the
system performs in place; a lost *Pod* is never restarted, only replaced. → [Ch 8](../notes/08-workloads.md)

**Rollback**: returning to the previously running version of software after a change
goes wrong. → [Ch 1](../notes/01-the-operational-burden.md), [Ch 8](../notes/08-workloads.md)

**Rolling update**: replacing running copies of a program with a new version a few at a
time, so the service stays available throughout. → [Ch 8](../notes/08-workloads.md)

**Scheduler**: the component that decides which machine each new Pod should run on, by
filtering out machines that cannot host it and scoring the rest. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md), [Ch 10](../notes/10-resources-scheduling-and-autoscaling.md)

**seccomp**: a Linux kernel filter listing which system calls a process may make at
all, so that a compromised process cannot reach the dangerous ones. → [Ch 5](../notes/05-containers.md)

**Secret**: a Kubernetes object holding sensitive data (passwords, tokens,
certificates) for delivery to a container. → [Ch 12](../notes/12-configuration-identity-and-security.md)

**SELinux**: see **Mandatory access control**. → [Ch 5](../notes/05-containers.md)

**Service**: a stable address and name standing in front of a constantly-changing set
of Pods, so clients never have to track individual copies. → [Ch 9](../notes/09-networking-and-service-discovery.md)

**ServiceAccount**: the identity a Pod runs as when it talks to the Kubernetes API. →
[Ch 12](../notes/12-configuration-identity-and-security.md)

**Shared responsibility model**: the explicit statement of where the provider's
obligations stop and yours begin. The provider secures the cloud; you secure what you
put in it. → [Ch 4](../notes/04-the-cloud.md)

**SLO (service level objective)**: the reliability target you commit to, from which the
error budget is derived. → [Ch 1](../notes/01-the-operational-burden.md)

**Spot instance**: spare provider capacity sold at a steep discount on the condition
that it can be reclaimed, with, on AWS, a two-minute warning. The clearest reason
software must treat losing a machine as routine rather than exceptional. → [Ch 4](../notes/04-the-cloud.md)

**SRE (site reliability engineering)**: the practice, originated at Google, of treating
operations as an engineering problem; also the name of the dedicated teams that do it. →
[Ch 2](../notes/02-devops-honestly.md)

**StatefulSet**: the declaration for software whose copies are *not* interchangeable
because each owns durable data, giving each a stable identity and its own storage. → [Ch 8](../notes/08-workloads.md)

**System call**: a request a program makes of the kernel for something only the kernel
can do: open a file, send a packet, allocate memory, start a process. A container's
processes make them directly to the *host's* kernel, which is why container isolation is
weaker than a virtual machine's. → [Ch 5](../notes/05-containers.md)

**Toil**: manual, repetitive operational work that scales linearly with the size of the
system and produces nothing new. The thing automation exists to remove. → [Ch 1](../notes/01-the-operational-burden.md)

**Virtual machine (VM)**: a software-simulated computer running its own complete
operating system, including its own kernel. Strong isolation, but it must boot, and it
carries a whole operating system's footprint, which is the trade a container refuses. →
[Ch 4](../notes/04-the-cloud.md)

**YAML**: a plain-text format for nested key-value data; the format essentially all
Kubernetes configuration is written in. → [Ch 7](../notes/07-kubernetes-control-plane-and-object-model.md), [Ch 13](../notes/13-why-yaml-hurts.md)
