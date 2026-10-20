# Chapter 4: The Cloud, and Where the Machines Come From

We are about to go down into the machine. But we have been saying "machine" for
three chapters without ever asking an obvious question, and it is worth asking now,
because the answer quietly determines everything that follows.

Where do the machines come from?

The last chapter left you with a platform team whose job is to make infrastructure
available on demand, without a human in the loop. Hold that phrase against how
computing worked for most of its history and it should sound impossible. Someone had
to *buy* a server. It arrived on a pallet. Somebody racked it, cabled it, gave it
power and cooling and an address, and only then, weeks later, could anyone run
anything on it. "On demand, without a human in the loop" was not a philosophy
failure; it was a physics failure. You cannot self-service a purchase order.

So before we look at how a program is packaged and placed, we should look at the
change that made packaging and placing *worth automating* in the first place. Almost
everything in the rest of these notes is a response to a world where machines became
cheap, plentiful, and (this is the part that matters most) **disposable**.

## What "the cloud" actually is

Strip away the marketing and it is embarrassingly simple: **the cloud is other
people's computers, in other people's buildings, rented by the hour and controlled
through an API.**

Three parts of that sentence carry the weight, and the third carries the most.

*Other people's computers* is the boring part, and on its own it is not new. Renting
server space from someone else was a business in the 1990s. You would call a company,
negotiate, and a month later a machine was yours to log into.

*Rented by the hour* is more interesting: it means capacity stops being something you
own and becomes something you spend, which changes how you think about it in ways this
chapter comes back to.

*Controlled through an API* is the part that changed engineering. An **API**
(application programming interface) is simply a defined way for one program to ask
another program to do something: a set of requests it will understand and answer.
Cloud providers put an API in front of the act of acquiring a machine. That is the
whole trick. It means that "give me a server with eight processors and 32 gigabytes
of memory, in this city, on this network" stopped being a *conversation with a person*
and became a *function call*. It returns in under a minute.

Sit with how strange that is if you are meeting it fresh. Acquiring a computer used
to be a procurement event, with a budget line and a lead time and a human being who
could say no. Now it is a line of code, and, critically, a line of code that
another program can execute without asking anyone.

That single move is the root of a phrase you will hear constantly: **infrastructure
as code**. If infrastructure is acquired through an API, then the *description* of
your infrastructure can be a text file, kept in version control alongside your
program, reviewed like a program, and applied by a machine. This is why the platform
team of the last chapter is a plausible idea at all. They are not standing between
you and a warehouse; they are wrapping an API that already exists in a better,
safer, more opinionated interface. And it is why *configuration*, text describing
infrastructure, became the medium of this entire discipline, which is eventually
where Syg comes in.

## The virtual machine, and why one server can be many

There is a mechanism under "rented by the hour" that you need, because the next
chapter is going to define containers partly by contrast with it.

The provider does not have one physical computer waiting for each customer. It has
large physical machines, and it slices each one into several **virtual machines**,
usually just *VMs*, or, in Amazon's vocabulary, *instances*. A virtual machine is a
software-simulated computer: it believes it has its own processors, its own memory,
its own disk and network card, and it runs its own complete operating system,
including its own **kernel**: the core of the operating system, the part that
actually talks to hardware and arbitrates between programs.

The thing making that illusion is a **hypervisor**: a layer sitting between the real
hardware and the virtual machines, which hands each VM a slice of the real processors
and memory and intercepts its attempts to touch hardware directly. The isolation is
strong precisely because it is drawn so low. Each VM has its own kernel, so a
compromise or a crash inside one guest has, in principle, nowhere to go: the
hypervisor is the only path out, and it is a small, hardened, heavily-scrutinised
piece of software.

Strong isolation, though, is not free. A virtual machine has to *boot* a whole
operating system, from firmware to login prompt, which takes tens of seconds to
minutes. It carries the memory footprint of that entire operating system whether your
program needs it or not. Ten VMs on a host means ten kernels, ten sets of system
processes, ten copies of a great deal of machinery that is identical in all ten.

Hold that cost in mind: the whole operating system, booting, per guest. It is the
price of drawing the isolation boundary that low, and it is precisely the price the
next chapter's subject refuses to pay.

## Where the line of responsibility falls

You will meet three acronyms constantly, and they are usually taught as a taxonomy to
memorise, which is a waste of a good idea. They are better understood as answers to
one question: **how much of the stack are you still responsible for?**

Picture the stack from the bottom: building, power, network hardware, physical
server, hypervisor, guest operating system, runtime and libraries, your application,
your data. Somewhere on that list there is a line. Above it is yours; below it is
theirs. The service models are just three common places to draw the line.

- **Infrastructure as a Service (IaaS)** draws it low. You rent virtual machines,
  storage, and networks. The provider handles everything physical and the hypervisor;
  you handle the operating system upward: patching it, securing it, and everything
  you install on it. You get maximum control and maximum work.
- **Platform as a Service (PaaS)** draws it high. You hand over your program; the
  provider runs it. Operating system, patching, capacity, restarts on crash: all
  theirs. You get much less work and much less control, and you live inside whatever
  shape the platform expects your program to have.
- **Software as a Service (SaaS)** draws it at the top. You are not running software
  at all; you are using someone's finished product. Your email, your issue tracker.

The industry name for the line itself is the **shared responsibility model**, and it
is worth taking literally, because the most expensive cloud security incidents happen
when someone assumes the provider's side of the line extends further than it does.
The provider secures *the cloud*: buildings, hardware, hypervisor. You secure what
you put *in* it: your operating system, your credentials, your access rules, your
data. Nobody patches your application for you because you rented the machine it runs
on.

Notice, by the way, that the previous chapter's internal platform is this same idea
turned inward. A platform team is drawing a responsibility line inside your own
company and taking everything below it.

## The economics, which are not a footnote

It is tempting to skip the money. Do not, because the money is why engineering
practice changed, and because two of the failure modes later in these notes are
fundamentally about a resource number that is also a price.

The old model was **capital expenditure**: you bought machines. That money was spent
up front, for hardware you would own for years, sized for the *worst* load you could
imagine, because if you guessed low, you were stuck until the next purchase. The
consequence was that almost every server ran at a fraction of its capacity almost all
of the time, and everyone knew it, and it was the rational choice anyway.

The cloud model is **operational expenditure**: you rent, and you pay for what you
use, by the hour or the second. Two things follow, and both changed how engineers
think.

The first is **elasticity**: because capacity is rented, you can have more of it for
an hour and then give it back. Traffic triples on a Friday night, you run more copies
of your program; the rush ends, you run fewer; you pay for the peak only while the
peak is happening. Capacity stopped being a fixed frame you had to fit inside and
became a dial you turn.

The second is subtler and more important for these notes. **Every resource decision
is now visibly a spending decision.** When you owned the machines, asking for more
memory was asking to use something already paid for. When you rent, the number you
write in a configuration file is multiplied by hours and appears on an invoice. This
is why Chapter 10 (where you will write down how much memory and processor your
program may claim) is not an academic exercise in capacity planning. Ask for too
much and you are burning money continuously, on every copy, forever. Ask for too
little and your program is killed under load. The tension between those two is
genuinely difficult, and it exists because someone is metering you.

## Regions, zones, and the geometry of failure

Now the part that matters most for everything after this chapter, because it is where
"the cloud" stops being a commercial arrangement and becomes an engineering
constraint.

Providers organise capacity geographically. A **region** is a separate geographic
area: a city or metropolitan area, with a name like `us-east-1` or `europe-west4`.
AWS's documentation puts the intent plainly: "Each Region is designed to be isolated
from the other Regions. This achieves the greatest possible fault tolerance and
stability." Regions do not share fate, and by default they do not share your data
either.

Inside a region are **availability zones**. An availability zone is "one or more
discrete data centers with redundant power, networking, and connectivity" within a
region: separate buildings, separate power feeds, separate cooling, "physically
separated by a meaningful distance, many kilometers, from any other AZ, although all
are within 100 km (60 miles) of each other," and joined by "high-bandwidth,
low-latency networking."

Read that description as an engineer rather than a brochure, because it is describing
a very specific thing: **a boundary that failures do not cross.** Power fails per
building. Cooling fails per building. A flood, a fire, a badly-timed maintenance
window: these take out a facility, not a metropolitan area. Zones exist so that
"this data centre has gone dark" and "our service has gone dark" can be different
sentences.

And that gives you a rule worth carrying: **copies of your program that must survive
independently have to be in different zones.** Three copies of a service in one zone
is not redundancy against the failure that actually happens; it is three copies of the
same bet. The "many kilometers" is what makes them independent, and the "low-latency
networking" is what makes spreading them affordable: they can still talk to each
other quickly enough to behave as one system. Every mechanism you will meet later for
spreading work across machines is, underneath, reaching for this geometry.

## The database you do not operate

There is one more thing on offer, and it changes what a platform team spends its life
doing.

Providers do not only rent machines; they rent *running services*. A **managed
service** is a piece of infrastructure the provider operates for you: a database, a
message queue, a cache, an object store. You do not install it, patch it, back it up,
monitor its disk, or handle its failover when a machine dies at 3 a.m. You ask the
API for a database, you get a hostname and credentials, and someone else carries that
pager.

For anyone who has actually run a database, this is not a small convenience. Running
a database well (replication, backups you have *tested restoring*, version upgrades
without downtime, failover that works when you need it rather than when you rehearsed
it) is a specialist job that quietly consumes a team.

The honest trade is real, though, and it is worth naming now rather than discovering
later. A managed service costs more per unit of raw capacity than the same software
on rented machines. It gives you less control: you get the configuration knobs the
provider exposes and no others, and the versions they support, on their upgrade
schedule. And it is the single largest source of **lock-in**: the deeper your
software depends on one provider's particular service, the more expensive leaving
becomes, and that cost is paid at the worst possible moment, which is when you have
already decided to leave.

Reasonable teams answer this differently, and both answers are defensible. What is
not defensible is not noticing you made the choice.

## Why all of this made automation unavoidable

Here is where this chapter earns its place, because everything from
Chapter 5 onward is a response to what the cloud did to the *lifetime of a machine*.

Consider what changed, in order.

**Machines became numerous.** When acquiring a server takes a function call, teams
stop running four large servers and start running forty small ones. Anything you were
willing to do by hand on four machines is impossible on forty, and unthinkable on four
hundred. Manual operations did not become unfashionable; they became arithmetically
impossible.

**Machines became short-lived.** A rented machine has no reason to be permanent. You
create one for an afternoon's work and destroy it. Fleets grow and shrink with
traffic. The idea of a named, long-lived, individually-cared-for server (the one with
the hand-tuned configuration that nobody dares reboot) stops making sense when the
machine costs money per hour and can be replaced in ninety seconds.

**And machines became reclaimable, on the provider's schedule.** This is the sharpest
one. Providers sell spare capacity cheaply on the condition that they can take it back.
AWS calls these **Spot Instances**, and its documentation is exact about the deal:
"You can launch Spot Instances on spare EC2 capacity for steep discounts in exchange
for returning them when Amazon EC2 needs the capacity back," and when that happens you
get "a warning that is issued two minutes before Amazon EC2 stops or terminates your
Spot Instance."

Two minutes.

Read that as a design brief, because that is what it is. If a machine running your
software can be taken away with two minutes' notice (and it can, at a price so much
lower than the alternative that a great deal of the industry takes the deal), then
software that treats a machine's death as an exceptional event is simply not viable.
The exception is now scheduled. It happens on a Tuesday afternoon, on purpose, for
commercial reasons, and it will happen again on Wednesday.

Even without spot pricing you get the same lesson more gently: providers perform
maintenance on their hardware, and instances get retired with notice. The physical
machine under your virtual one is not permanent either.

So put the three together. Many machines, none of them long-lived, several of which
may be taken away at short notice; and, from the previous chapters, a team that must
keep a service continuously available on top of that substrate.

The only way that adds up is if **losing a machine is routine and handled without a
human**. Not "recovered from," which implies an incident. *Routine.* The system must
notice a copy of your program has gone, and start another somewhere else, at three in
the morning, without waking anyone, because at the scale the cloud makes normal, this
will happen often enough that human involvement would be a full-time job producing
nothing.

That requirement, *make machine loss a non-event*, is what the software we spend the
rest of these notes on exists to satisfy. It has a name: an **orchestrator**, a system
that decides which of your programs run on which machines and keeps that arrangement
true as machines come and go. That is the subject of everything from Chapter 6 on.

It is also why the *next* chapter has to come first. To move a program to a different
machine automatically, in seconds, you need it packaged so that it runs *identically*
on any machine, with no hand-tuning and no surprises. Without that, "start it
somewhere else" is a research project rather than an operation. That package is the
container.

## You can rent the orchestrator too

An orchestrator has a coordinating brain: a set of components that remember what you
want running and continuously drive reality toward it. That brain is called the
**control plane**, and the machines it coordinates, together with the brain itself,
are a **cluster**. Both get taken apart properly in Chapter 7; what matters here is
that the brain is software too, needing to be kept available, upgraded and backed
up, which is exactly the kind of work providers sell you out of.

So they rent it. You ask the API for a cluster; the control plane is operated by the
provider, and your own machines run your actual programs. It is the managed-service
trade from a moment ago, applied to the orchestrator itself, and it is why in most
organisations the control plane is something people interact with constantly and never
once see running.

## The honest part

Two things about the cloud are true and are usually left out of the pitch.

**It moved operations; it did not remove it.** The work of racking servers is gone.
The work of deciding how much memory a program may use, what happens when a machine
disappears, which copies must be in different buildings, who is allowed to talk to
what, and why the bill doubled last month: all of that is still yours, and there is
arguably more of it than before, because the system you are operating is larger and
more dynamic than the one you would have built out of purchased hardware. Everything
after this chapter is that remaining work.

**Elasticity is a bill, not a magic trick.** A dial you can turn up is a dial you can
forget you turned up. The most common cloud cost failure is not a dramatic mistake; it
is a hundred small over-allocations that each looked reasonable, multiplied by hours,
multiplied by copies, running quietly for a year. Chapter 10's resource numbers are
where you will personally participate in that.

## Where Syg stands

Syg is deliberately, almost stubbornly, uninvolved with the cloud.

It emits standard Kubernetes objects (Kubernetes being the orchestrator these notes
build toward, which Chapter 3 named and Chapter 6 onward explains) and nothing else.
It calls no provider's API, holds no provider's credentials, and knows nothing about
regions, zones, instance types, or billing. What it produces runs on a rented cluster
from any provider, or on one you built yourself, unchanged, because it never names
anything below the Kubernetes interface.

That is worth noticing early, because it is the answer to the portability worry the
managed-cluster trade raises. An interface you deliberately refuse to see past is what
portability is actually made of, and Kubernetes uses the same trick internally, in a
place Chapter 7 will show you.

There is one place the cloud does show up in the language, and it is the honest one.
Some of what your software depends on is *not* in your configuration at all: the
managed database, the object store, the queue the provider operates. Syg's model of
the world is deliberately closed (it verifies relationships between things it can
see), so anything it cannot see must be declared as **`extern`**: an explicit
statement that this dependency exists and lives outside the checked world. Chapter 14
develops why a closed world is what makes graph-level verification possible at all.
For now, the point is a small one about honesty: a tool that quietly ignored what it
could not see would be claiming more than it knows.

## Read the source

- **What is cloud computing**: the provider's own framing of the service models:
  https://aws.amazon.com/what-is-cloud-computing/
- **Regions and Availability Zones**: the isolation guarantees quoted above, and the
  physical-separation figures:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html
  and https://aws.amazon.com/about-aws/global-infrastructure/regions_az/
- **Spot Instance interruptions**: the bargain, and the two-minute notice:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html and
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html
- **The shared responsibility model**: exactly where the provider's obligations stop:
  https://aws.amazon.com/compliance/shared-responsibility-model/
- **Google Cloud: geography and regions**, the same concepts in a second vendor's
  words, which is a useful check on which parts are universal:
  https://cloud.google.com/docs/geography-and-regions

---

*You now know where the machines come from, why there are so many of them, and why
one of them dying is a Tuesday rather than an emergency. That last fact is a demand on
your software: it must be able to start somewhere else, immediately, and behave
identically when it does. Which means we need to talk about how a program is packaged,
and about the picture almost everyone carries of that packaging, which is wrong in a
specific and costly way.* → [Containers](../notes/05-containers.md)
