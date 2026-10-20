# Chapter 1: The Operational Burden

There is a particular kind of quiet that settles over a team right before a
**deploy**, before a version of their software stops being a thing they have and
becomes the thing everyone out there is using. Someone has the release notes open.
Someone else is watching a dashboard. A third person has their hand near the
keyboard, ready to run the **rollback** command they have already typed but not
pressed: the one that puts the previous version back if this one misbehaves. The code
has passed its tests. It worked on every machine anyone tried it on. And still, that
quiet, because everyone in the room knows that *working* and *continuing to work,
for everyone, while handling real traffic and real data and real failures* are two
very different properties, and the second one is about to be tested in the only
environment that ever really counts.

That gap, between software that is correct and software that stays alive, is the
whole reason operations exists as a discipline. Before we can talk about any of the
machinery that later chapters are built from, we have to sit with that gap honestly,
because every piece of that machinery is an attempt to make that room a little less
quiet.

## Writing software and running software are different jobs

When you write software, you are mostly working with possibility. You add a
function; the system can now do something it could not before. The work is
creative and additive, and the feedback is fast and forgiving: the compiler
complains, you fix it; the test fails, you fix it; eventually it runs and you have
made something that did not exist a moment ago.

Running software is the opposite kind of work. Nothing you do makes the system do
more; the best possible outcome of an operations action is that the system keeps
doing exactly what it already did. You are not fighting a blank page. You are
fighting entropy: hardware that fails, disks that fill, certificates that expire,
dependencies that go down, traffic that spikes, memory that leaks, clocks that
drift. The system wants to fall over, constantly and in a thousand small ways, and
your job is to keep it from doing so while people who are not you keep changing it
underneath you.

This asymmetry is worth feeling clearly, because it explains almost every cultural
and technical fight that follows. The developer's incentive is *change*: ship the
feature, fix the bug, move. The operator's incentive is *stability*: every change
is a risk, and the largest single cause of outages is not hardware or attackers:
it is a change that someone deliberately made. Google's Site Reliability Engineering
team (the group that popularised treating operations as an engineering discipline,
and whose written-up practice we will draw on repeatedly) puts a number on this from
its own incident history: roughly **70% of outages are due to changes in a live
system**: a deployment, a config edit, a flag flip. The thing that breaks your
system is, overwhelmingly, you.

Hold those two facts together. Change is the only source of value: software that
never changes slowly dies. Change is also the primary source of failure. The
entire field we are about to study is the search for a way to have a *high rate of
change* and *high stability at the same time*, when those two things appear to be
in direct opposition. Keep that framing; it is the thread that runs through every
chapter.

## What "running" actually means

Let us make "keeping it alive" concrete, because vagueness here hides everything
important.

A running service is a process (usually many processes, on many machines) holding
state in memory and talking to the outside world over the network. To keep it
running you must, continuously and correctly, do a surprising number of things.
The process must be started with the right configuration and the right secrets,
and restarted when it dies, and it *will* die, from bugs, from out-of-memory
kills, from the machine under it being rebooted. When it is unhealthy but not dead
(wedged, deadlocked, leaking), something must notice and act, because a process
that is up but not serving is often worse than one that is cleanly down. When
traffic rises, there must be more copies of it; when traffic falls, fewer, because
capacity costs money. Those copies must be discoverable: something has to know
which instances are alive *right now* and route requests only to those, updating
that knowledge every time an instance appears or disappears. The whole thing must
survive the loss of any single machine, because at scale a machine is always dying
somewhere. And through all of that, you must be able to deploy a new version
without dropping requests on the floor.

Every sentence in that paragraph names a mechanism these notes take apart properly
later. For now, notice only their shape: not one of them is about *features*. All of
them are about the system's relationship with failure and change over time. This is
the operational surface of a piece of software, and it is enormous, and it is almost
entirely invisible from inside the code.

## The nature of failure at scale

There is a specific reason operations gets harder, not just bigger, as systems
grow, and it is worth naming precisely because it reshapes how you have to think.

On one machine, failure is mostly binary: the program is running or it has
crashed. The moment you have more than one machine talking over a network, you
inherit *partial failure*: the situation where some parts of the system are up,
some are down, and, crucially, the up parts cannot always tell which is which. A
network link does not cleanly announce that it has failed; it just stops
delivering messages, and a message that has not arrived is indistinguishable, for
a while, from a message that is merely slow. This is the source of the hardest
problems in distributed systems: you cannot reliably tell the difference between a
component that is dead and one that is simply not answering yet, and you have to
keep the system correct without that knowledge.

Partial failure means that "is it working?" stops being a yes/no question and
becomes statistical. You do not ask whether the service is up; you ask what
fraction of requests are succeeding, at what latency, right now. Availability
becomes a *number*, and that number becomes the language operations speaks.

## Availability, and the tyranny of nines

Availability is usually quoted as a percentage of time the system is usefully
serving: 99.9%, 99.99%, and so on: "three nines," "four nines." The percentages
feel abstract until you convert them to their real currency, which is permitted
downtime. Three nines allows roughly forty-three minutes of unavailability per
month. Four nines allows about four minutes. Five nines, the fabled standard,
allows about twenty-six *seconds* a month.

Sit with those numbers, because they quietly dictate everything. Twenty-six
seconds a month is far less time than it takes a human to read an alert, open a
laptop, and understand what is happening. That single fact tells you that beyond a
certain reliability target, humans cannot be in the recovery path at all: the
system has to detect its own failures and heal itself faster than a person could
even be notified. When you later meet a system that restarts a crashed program within
seconds without waking anyone, or steers traffic away from a dead copy before a human
knows it died, understand that this is not a convenience. It is the only way the
arithmetic of availability can possibly work. Automation of recovery is not a
nice-to-have bolted onto operations; past a few nines it *is* operations.

There is a second, subtler consequence. If availability is a number, then perfect
availability is not the goal: it is impossible, and chasing it is ruinously
expensive. So you choose instead. You decide the reliability you actually need and
write it down as a number: **99.9% of requests succeed**, say, or *95% of requests
finish within 300 milliseconds*. A target stated that way has a name you will see
constantly: a **Service Level Objective**, or **SLO**. It is a promise about the
service, chosen rather than wished for.

And the moment you choose it, you have said something you may not have noticed: that
the remaining 0.1% is *allowed*. That remainder is your **error budget**, the framing
formalised at Google, and the shift it produces is the whole point. Failure stops
being a thing you merely avoid and becomes a thing you *spend*: on shipping features
faster, on taking calculated risks. If you are hitting your target with budget to
spare, you are being too cautious and shipping too slowly. If you are burning through
it, you slow down and stabilise. One number, and both sides of the argument from the
start of this chapter can negotiate against it instead of against each other.

Absorb the mindset shift, because it recurs: reliability is a resource to be budgeted,
not a virtue to be maximised.

## The wall, and why it made everything worse

For a long time, organisations solved the tension between change and stability by
solving it *structurally*: they put the two incentives into two different
departments. Developers wrote software and were measured on features shipped.
A separate operations team ran that software in production and was measured on
uptime. The developers "threw the release over the wall" to operations, who caught
it and were then responsible for keeping alive a thing they had not built and did
not fully understand.

You can predict the pathology from the incentives alone. Developers, rewarded for
change and shielded from its consequences, pushed for more and faster releases;
they never carried the pager, so a fragile deploy was not their problem at 3 a.m.
Operators, rewarded for stability and holding the pager, learned that every change
was a threat, and did the only rational thing: they slowed change down. Heavy
change-approval boards. Quarterly release windows. Long freezes. Each side, acting
sensibly within its own incentives, made the other's job worse. Releases grew
larger and rarer because they were hard to push, and *because* they were larger
and rarer, each one bundled more change, carried more risk, and was harder to
debug when it broke, which justified even more caution. A vicious cycle, and one
that felt like prudence from the inside.

This is the world DevOps was born to indict, and it is why, as we will see in the
next chapter, the first and most important claim of DevOps was not about tools at
all. It was that the wall itself was the bug.

## Toil, and the human cost the diagrams hide

There is one more piece of the burden that architecture diagrams never show, and
you should carry it with you because it is the emotional truth of the field.

Google's SRE writers gave it a precise name: *toil*. Toil is operational work that
is manual, repetitive, automatable, reactive, and scales linearly with the size of
the system: the work of a human doing, by hand, something a machine could do,
over and over, just to keep the lights on. Restarting a stuck process. Manually
adding a server because traffic grew. Copying a config file to ten machines.
Applying the same fix to the same recurring alert for the hundredth time. None of
it creates anything. All of it must be done. And it scales with the system: twice
the machines, twice the toil, which means that in a toil-dominated operation,
growth is punished with proportional pain, and the team's best people spend their
days performing scheduled chores a machine should have been doing, instead of
engineering.

Toil is not just inefficient; it is corrosive. It burns people out, it crowds out the
engineering work that would *reduce* toil, and it is where the pager and the 3 a.m.
wake-ups live.

Which gives the automation we met a few pages ago a second motive, quite separate from
the arithmetic. There, self-healing was *forced* on you: past a few nines, no human is
fast enough to be in the loop. Here it is something gentler and more human. Pushing
the linear, grinding work of keeping software alive down into the machine is how you
get people back: back to the additive, creative work that made them want to do this
in the first place. The first argument says a person cannot do it. The second says a
person should not have to.

## Where Syg stands

Everything in this chapter is upstream of Syg, and Syg touches only one slice of
it, but a slice that sits right on the fault line. If the largest single cause of
outages is a change someone made, then the highest-leverage moment to catch an
operational failure is *before the change ships*, while it is still text a person
is editing, not a running system a person is debugging. Syg's entire bet is to
move a specific and common class of these change-induced failures (the kind that
are valid on their face but broken in the way they relate to the rest of the
system) as far left as they can possibly go: to compile time, at the source, with
the mechanism explained. It does not touch toil, or availability math, or the
culture. It attacks exactly one thing: the deploy that was going to break in a way
you could have known about, and didn't.

That is a small claim against the size of the burden you have just seen. It is meant
to be. Real progress in this field is made of many such honest, bounded claims, and
being suspicious of the large ones is a habit worth acquiring early.

## Read the source

- **Google SRE Book**, *Site Reliability Engineering*: especially the chapters on
  the nature of SRE, on toil, and on error budgets. Free online:
  https://sre.google/sre-book/table-of-contents/
- **Accelerate** (Forsgren, Humble, Kim) and the annual **DORA** *State of DevOps*
  reports: the empirical research linking delivery practices to both speed and
  stability: https://dora.dev/research/
- **The Phoenix Project** (Kim, Behr, Spafford): a novel, but the sharpest
  portrait of the dev/ops wall and its incentive traps that exists.

---

*Next: the word "DevOps" got attached to a thousand products, most of which
missed the point. Chapter 2 recovers what it actually meant, and why the answer
was never a tool.* → [DevOps, honestly](../notes/02-devops-honestly.md)
