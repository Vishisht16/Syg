# Chapter 6: Orchestration and Desired State

You can now run a single container, and you understand it to the kernel. Now hold
the real problem in your head for a moment, because it is bigger than it first
looks. You do not have one container. You have hundreds, spread across dozens of
machines. Each machine can die at any moment, taking its containers with it. Each
container can crash on its own. Traffic rises and you need more copies; it falls
and you want fewer. When you ship a new version, the old containers must be
replaced by new ones without dropping a single request. And every one of those
containers needs to find and talk to the others, whose locations are changing
constantly as they die and move and scale.

Now ask yourself: *who does all of that?* Who notices a machine died and starts its
containers elsewhere? Who counts the copies and starts a new one when the number
drops? Who watches the load and scales? If the answer is "a human with scripts,"
you have rebuilt the toil from Chapter 1 in its purest and most punishing form: a
person, or a room of them, manually herding thousands of moving parts, forever,
losing. This is the problem an **orchestrator** exists to solve, and Kubernetes is
the orchestrator that won. But before we name any of its parts, we have to
understand the one idea that makes the whole thing possible, because it is not an
implementation detail, it is a genuinely different way of commanding a system, and
once it clicks, most of Kubernetes will feel inevitable rather than arbitrary.

## Two ways to tell a system what to do

There are, fundamentally, two ways to command a computer system, and the difference
between them is the difference between a fragile pile of scripts and a system that
heals itself.

The first is **imperative**: you issue a sequence of commands describing the *steps
to take*. "Start a container of version 1.4 on machine three. Then start another on
machine seven. If one dies, restart it. When the new version comes, stop the old
ones one at a time and start new ones." This is how most people first think about
automation, because it is how we think about doing the task ourselves: as a
procedure. And it works, right up until reality stops cooperating, which it does
immediately and forever. The imperative approach encodes a *path* from the current
situation to the goal, and it is only correct if reality follows that exact path.
But reality is adversarial. What if the machine is already full when you try step
one? What if a container dies *during* the upgrade, in a state your script's
if-statements never anticipated? What if the script itself crashes halfway through,
leaving the system in a partial state that no clean rerun can recover, because
rerunning step one now does the wrong thing? Every imperative automation of a
changing system eventually drowns in this: an ever-growing thicket of special cases
for every way the world can differ from the path you assumed, and the world has
infinitely many ways.

The second is **declarative**: you describe the *desired end state*, and you leave
the question of how to reach it (and how to stay there) to the system. You do not
say "start a container, and if it dies restart it, and if the node fails move it."
You say: *"I want three healthy copies of version 1.4 running, at all times."* That
is a statement about the destination, with nothing said about the route. It does
not describe steps, it describes a *fact you want to be true*, and it stays true as
a goal no matter what the current situation is or how it got there. The genius is
in what this lets the system do, and to see it we need the mechanism that turns a
declaration of desire into a system that relentlessly pursues it.

## The reconciliation loop

That mechanism is the **control loop**, or **reconciliation loop**, and it is the
beating heart of Kubernetes: the single idea from which self-healing, scaling,
rollouts, and rescheduling all fall out as consequences rather than features. The
Kubernetes documentation defines it by borrowing from control theory: "In robotics
and automation, a control loop is a non-terminating loop that regulates the state
of a system," and "controllers are control loops that watch the state of your
cluster, then make or request changes where needed. Each controller tries to move
the current cluster state closer to the desired state." Your **cluster** is the set
of machines running your software together, plus the coordinating brain that manages
them; Chapter 7 takes its anatomy apart piece by piece.

The docs reach for the same example everyone does, because it is exactly right: a
thermostat. When you set a thermostat to 20°C, you are declaring a *desired state*.
The actual room temperature is the *current state*. The thermostat does not execute
a procedure ("turn the heater on for eleven minutes"); it runs a loop. Forever, it
compares desired to current, and acts to close the gap: too cold, heat; too warm,
stop; and then it looks again, and again. You never tell it the steps. You tell it
the goal, and its loop does whatever is necessary, continuously, to make the goal
true and keep it true as the world changes: as someone opens a window, as night
falls, as the seasons turn.

Kubernetes builds its entire self out of loops of exactly this shape. Every object
in the system carries two faces, and this pairing is so fundamental that we will
build the next chapter on it: a **`spec`**, which is *the desired state you
declared* (what you want), and a **`status`**, which is *the current state the
system observes* (what actually is). For every kind of object, a controller runs a
non-terminating loop: read the desired state from the `spec`, observe the current
state of the world, and if they differ, take action to make the current state come
closer to the desired, then loop, forever.

Watch it work. You declare that you want three identical copies of your program
running. The object you write to say that is called a **Deployment**, which Chapter 8
covers in full, and which for now you can read as simply "keep N copies of this thing
running." A controller observes two copies, sees the gap, and requests a third. Later
a machine dies and a copy vanishes; the very next pass of the loop observes two again,
sees the gap again, and requests a replacement again.

Nobody told it a machine died. Nobody wrote a handler for machine failure. The loop
did what it always does (compare, and close the gap), and *that is the self-healing.*

## The deepest point: level-triggered, not edge-triggered

Here is the idea that separates people who *use* Kubernetes from people who *understand*
it, and it is worth slowing all the way down for, because almost nothing else in the
system makes full sense without it.

There are two ways to build a system that reacts to change, and they sound similar
but behave completely differently under failure. An **edge-triggered** system reacts
to *events*: to the *transitions*, the moments of change. "*When* a Pod dies, start
a new one." "*When* a node fails, reschedule." It listens for the edge (the instant
something changes) and fires an action in response. This is the intuitive design,
and it is a trap, for one devastating reason: **if you miss the event, you are wrong
forever.** Events are ephemeral. If the component that was supposed to hear "the Pod
died" was itself restarting at that instant, or the message was lost to a network
blip, or it was busy, then the event passes unhandled, and nothing will ever fire
it again. The Pod is dead, the replacement was never started, and the system will
sit in that broken state permanently, because the only thing that would have fixed
it was an event that has already come and gone. Edge-triggered systems accumulate
missed edges into permanent, silent drift.

A **level-triggered** system does not react to events at all. It continuously
observes the *current level* (the actual state of the world *right now*) and drives
it toward the desired state, regardless of what events did or didn't happen to
produce that state. It does not ask "did a Pod die?" It asks "how many Pods are
running *right now*, and how many do I want?" And if those differ, it acts, and if
they don't, it doesn't. Notice what this buys you: **a level-triggered loop cannot
miss an event, because it does not depend on events.** If it was asleep or crashed
or blinded at the exact moment a Pod died, it does not matter in the slightest: the
next time the loop runs, it observes the current level (one Pod short) and closes
the gap. The system is *self-correcting by construction*, because correctness does
not depend on having witnessed any particular transition; it depends only on being
able to observe the present and knowing the goal.

This is *why* Kubernetes heals. Not because someone wrote clever recovery code for
each failure mode, but because level-triggered reconciliation makes recovery the
*same operation as normal operation*. The loop that starts your third replica when
you first deploy is the identical loop that replaces it when a node dies, when you
delete a Pod by hand, when the process crashes, when a cluster upgrade drains a
machine. The controller never learns *why* the current state differs from the
desired: a crash and a deliberate deletion and a hardware failure are
indistinguishable and irrelevant to it. It sees a gap and closes it. Convergence
toward your stated intent is not a feature bolted onto Kubernetes; it is the only
thing Kubernetes does, applied relentlessly, to everything.

Once you hold this, a cascade of Kubernetes' properties stops being surprising.
Idempotency (you can apply the same declaration a hundred times and nothing bad
happens) is obvious, because the loop only ever acts on the gap between current
and desired, and re-declaring a state that already holds produces no gap and thus no
action. Tolerance of controller crashes is obvious: a controller that dies and
restarts simply resumes observing and closing gaps, having missed nothing that
matters. And the whole discipline of **GitOps** (storing your desired state in Git
and letting a controller continuously reconcile the cluster to match it) is just
this idea taken to its conclusion: Git holds the `spec`, the cluster is the
`status`, and a reconciliation loop drives one toward the other forever, so that the
running system is *provably* whatever the repository says, self-correcting against
any drift, because that is what level-triggered reconciliation *is*.

## How controllers actually act, and why there are so many

One more mechanical point, because it explains the shape of everything to come. A
controller often does not perform the work itself. In the docs' words, a controller
"might carry the action out itself; more commonly, in Kubernetes, a controller will
send messages to the **API server** that have useful side effects." The API server is
the single front door through which every part of the system reads and writes the
shared record of desired and current state: for now, simply "the place where the
objects live."

The docs' example is a batch job. You declare a Job, with the desired state "run this piece
of work through to completion." The Job's controller sees it and runs nothing at all;
it *asks the API server to create Pod objects* (Pods being, as the last chapter
introduced, the units that hold running containers). Those Pod objects are themselves
desired state, which *other* controllers observe and act on: one that decides which
machine each Pod should run on, and one that runs on each machine and actually starts
the containers there. Meanwhile the Job's controller watches how those Pods are doing
and updates the Job's status to match.

So the real system is not one giant loop but *many small ones, chained*: each
controller reconciles its own kind of object, and it acts by writing desired state
for the next controller down, which reconciles *that* and writes desired state for
the next. Complex behaviour ("run this batch job with retries across a fleet of
machines, rescheduling around failures") is not implemented anywhere as a single
procedure. It *emerges* from a pipeline of simple, independent, level-triggered
loops, each doing one dumb thing well: compare, close the gap, repeat. This is
separation of concerns raised to an architecture, and it is why Kubernetes can be
extended almost without limit: to add a new capability, you add a new controller
with its own object kind and its own loop, and it composes with all the others by
the same mechanism, needing to understand none of them.

Which should raise a question. If controllers never call each other, and each one
reconciles "its own" objects, how does a controller know which objects are its own?
The answer is the quiet machinery the entire next chapter is built around, and it is
more elegant than you would expect.

None of this is new or unproven, incidentally. Kubernetes is the open
reincarnation of **Borg**, the cluster manager Google ran internally for a decade
before publishing the paper that described it, and the declarative,
reconciliation-driven design is the distilled lesson of running planet-scale
infrastructure long enough to learn that imperative orchestration does not survive
contact with reality. You are not learning a fashion. You are learning the shape that this
problem forces on anyone who solves it at scale.

## Where Syg stands

This chapter is where Syg's design philosophy meets its deepest justification. Syg
produces **desired state** (the declarations the reconciliation loops consume), and
it runs entirely at authoring time, long before any controller sees the config. Why
does that matter so much? Because a reconciliation loop is *relentless and
uncritical*. It does not check that your desired state is coherent or sane; it drives
the world toward whatever you declared, forever. Declare something internally
contradictory (a rule that sends traffic to a set of copies that will never exist, a
safety policy that makes a necessary maintenance action impossible), and the loops do
not error and stop. They *faithfully pursue the broken goal*, over and over, and you
are left with a system behaving exactly as designed and nonetheless wrong. That is the precise reason catching incoherence *before* the
declaration reaches the reconcilers is so valuable: once it is in the loop, nothing
in the loop will ever object. Syg's job is to make sure the desired state you hand
this tireless machinery is one that is actually worth converging on.

## Read the source

- **Kubernetes: Controllers**: the primary description of the control loop, the
  thermostat, and desired-vs-current state:
  https://kubernetes.io/docs/concepts/architecture/controller/
- **Kubernetes: the reconciliation / declarative model** overview:
  https://kubernetes.io/docs/concepts/overview/working-with-objects/
- **"Large-scale cluster management at Google with Borg"** (Verma et al., 2015):
  the paper Kubernetes descends from:
  https://research.google/pubs/large-scale-cluster-management-at-google-with-borg/
- On **level- vs edge-triggered** design, the Kubernetes API conventions and design
  docs are the canonical engineering references; the principle also appears
  throughout the SRE literature as the reason declarative systems self-heal.

---

*A reconciliation loop needs three things to exist: somewhere to durably store the
desired and current state, a way for controllers to notice when that state changes,
and the controllers themselves. Those things, plus something that decides which
machine each Pod runs on, and an agent on every machine that actually starts the
containers, are the anatomy of a Kubernetes cluster. The next chapter names each of
them and shows you the data model they all speak.* →
[The control plane and the object model](../notes/07-kubernetes-control-plane-and-object-model.md)
