# Chapter 1: Two Revolutions, Wearing One Name

*Verified against: the 2025 DORA report. Checked August 2026.*

Here is a sentence you have read some version of a hundred times: *AI is transforming
software infrastructure.*

It is true, and it is nearly useless, and the uselessness is not because the sentence
is vague. It is because the sentence is describing two entirely different things at
once, and they have almost nothing to do with each other. Until you pull them apart,
every article on this subject will read as noise, because it *is* noise, produced by
authors moving between two subjects without signalling which one they are in.

So let us pull them apart first. Everything else in this volume sits on one side or the
other of the line we are about to draw.

## The first revolution: a new kind of workload

The first change is that a new sort of program showed up, and it does not fit the
machinery you learned in Volume I.

Be concrete about what "does not fit" means, because this is not a vague complaint
about scale. Volume I taught you specific mechanisms with specific assumptions built
into them, and this workload violates those assumptions one by one:

- Volume I's Chapter 10 taught that a container declares a **request** and a **limit**, that
  memory is incompressible so exceeding it gets you killed, and that processor time is
  compressible so exceeding it merely gets you throttled. A graphics processor is
  neither. You cannot give a training job 40% of one the way you give it 40% of a
  processor core, and the request/limit/QoS arithmetic simply does not carry over.
- Volume I's Chapter 10 also taught that the scheduler considers **one Pod at a
  time**: filter the
  machines that cannot run it, score the ones that can, bind it, move on. A distributed
  training job needs sixty-four Pods placed *simultaneously or not at all*, because
  sixty-three of them running is not sixty-three sixty-fourths of a training run. It is
  nothing, burning money.
- Volume I's Chapter 5 taught that container images are efficient because layers are immutable and
  shared, so ten containers from one base image do not carry ten copies of it. That
  argument holds right up until the payload is a hundred and forty gigabytes of model
  weights that nothing else shares.
- Volume I's Chapter 9 taught that a Service spreads traffic across ready Pods, effectively at
  random, because one replica is as good as another. For a language model server, one
  replica is emphatically *not* as good as another: the one that already has your
  conversation in memory is worth far more than the one that does not.
- Volume I's Chapter 11 taught that a readiness probe is a cheap, frequent question. For a model
  server, "are you ready?" means "have you finished loading a hundred gigabytes of
  weights," and the answer is *no* for several minutes after the container starts.

That is five mechanisms from Volume I, each renegotiated. Not replaced: renegotiated,
which is why this volume is a sequel and not a correction. The reconciliation loop
still works exactly as Volume I's Chapter 6 described. The control plane is unchanged. Labels and
selectors still join everything to everything. What changed is a layer of assumptions
sitting on top of that foundation, and Part II of this volume works through the five
changes above, one chapter each, with the specifications that describe them.

This first revolution is, in the end, *ordinary engineering*. It is well-specified,
actively developed in public, and verifiable. It is also the half that gets written
about least, because it is difficult and undramatic.

## The second revolution: a new kind of author

The second change has nothing to do with what runs on your cluster. It is about who
writes the configuration.

For the entire span of Volume I, an unstated assumption held: **a human being wrote
the text, and a human being read it.** Every safety mechanism in that book depends on
it. A linter reports a problem *to someone*. A code review catches a mistake *because
someone reads the diff*. A diagnostic explains a consequence *to a person who will act
on it*. Volume I's Chapter 14 and its argument about prevention versus detection is an argument
about what best serves a human author.

That assumption is now partially false, and becoming more so. Configuration is written
by models. Pull requests are reviewed by models. Incidents are triaged, and sometimes
remediated, by automated systems acting faster than a person could be paged.

This is a change in the *authorship* of infrastructure, and it is entirely orthogonal
to the first revolution. You can run a fleet of language models with every line of
configuration hand-written by people. You can also have agents writing configuration
for a boring web application with no machine learning anywhere near it. These two
revolutions are routinely bundled into one word, *AI*, and they have essentially
nothing in common except the technology's name.

Parts III and IV of this volume are about the second one.

## Why the conflation is not harmless

You could argue this is a pedantic distinction. It is not, and here is the practical
damage it does.

When the two are bundled, claims migrate between them illegitimately. A vendor
demonstrates something genuinely impressive about the *first* revolution (real
speedups on real inference hardware, with numbers), and the credibility of that
demonstration attaches to claims about the *second*, which have not been demonstrated
at all. You are shown a benchmark and sold a philosophy.

It also runs the other way. Reasonable skepticism about autonomous agents remediating
production incidents gets applied to the mechanism half, where it is simply wrong:
Dynamic Resource Allocation is a stable, documented Kubernetes feature, and being
cynical about AI marketing is not a reason to be uninformed about it.

Keeping the two apart is the difference between reading this field and being marketed
to by it.

## What the evidence actually says about the second revolution

We can be more precise about the authorship change than most writing on it manages,
because it has been measured, by the same research programme Volume I already leaned
on.

The DORA research programme has spent years surveying delivery performance across
thousands of organisations. Volume I's Chapter 2 used its central historical finding:
that speed and stability rise together, because the practices producing one produce the
other. That finding demolished the intuition that shipping slower is safer.

The 2025 report turned that instrument on AI adoption, and the results are worth
reading closely rather than in summary. On adoption: *"90% of survey respondents report
using AI at work"* and *"more than 80% believe it has increased their productivity."*
On trust, in the same breath: *"30% report little or no trust in the code generated by
AI."* Hold those two together: near-universal adoption, widespread belief in the
productivity gain, and a third of practitioners not trusting the output. That is not a
contradiction. It is a description of people using a tool they are also auditing.

Then the delivery findings. *"Unlike last year, we observe a positive relationship
between AI adoption on both software delivery throughput and product performance."*
Throughput up: that is new, and it is good news. And then: *"However, AI adoption does
continue to have a negative relationship with software delivery stability."*

Read that pair again, because it is the most important empirical fact in this volume.
Volume I's Chapter 2 taught you that speed and stability travel *together*. Here is a
practice that raises one and lowers the other, which, against the DORA programme's own
historical finding, is genuinely strange and worth explaining rather than nodding at.

The report offers its own explanation, and it is mechanical rather than moral: *"AI
accelerates software development, but that acceleration can expose weaknesses
downstream. Without robust control systems, like strong automated testing, mature
version control practices, and fast feedback loops, an increase in change volume leads
to instability."*

And the framing the report leads with: *"AI doesn't fix a team; it amplifies what's
already there. Strong teams use AI to become even better and more efficient. Struggling
teams will find that AI only highlights and intensifies their existing problems."*

## The thread worth pulling

There is one more observation in that research, and it is quieter than the headline
numbers. Analysis of the report notes that the time AI saves during creation is
frequently reallocated to auditing and verifying what was produced: that AI *shifts*
the work required for delivery rather than removing it.

Sit with what that implies. If generating a change becomes dramatically cheaper while
*reviewing* a change stays roughly as expensive as it always was, then the bottleneck
in your delivery process moves. It moves to review. And review is the step performed by
the scarcest, least parallelisable resource you have, which is a human being reading
carefully.

That relocation is, I will argue later in this volume, the single most consequential
thing about the second revolution, more consequential than any question about how good
the generated code is. Chapter 9 makes that argument in full, and marks itself as an
argument.

For now, notice how the layers stack, because the rest of this volume keeps them
separate. The throughput and stability findings are DORA's, measured and quoted. The
reallocation-to-auditing observation is analysis of that report rather than a headline
finding, which is a weaker footing and is marked as such wherever it appears. And the
conclusion I draw about what any of it means for safety machinery is mine alone.

## What this volume will and will not do

It will teach the mechanism half properly, at Volume I's depth, with the specifications
quoted.

It will treat the second half as what it is: a real change, partially measured, heavily
marketed, and not yet finished happening. Where there is evidence, you get the evidence
with its source. Where there is only argument, you are told it is argument.

It will not predict the future. There is a lot of writing about AI and infrastructure
that is really writing about what the author hopes will be true in three years, and it
is not marked as such, and it ages into confident nonsense. When this volume speculates
it will say so, briefly, and move on.

Now let us go and look at the machine, because the mechanism half is the part you can
actually learn, and it starts with a piece of hardware that refuses to behave like
anything in Volume I.

## Read the source

### Verified against primary sources

- **The 2025 DORA report**: the adoption, trust, throughput, and stability findings
  quoted above, and the amplifier framing: https://dora.dev/research/2025/dora-report/
  and the announcement summarising its headline results:
  https://cloud.google.com/blog/products/ai-machine-learning/announcing-the-2025-dora-report
- **Volume I, Chapter 2**: the earlier DORA finding this chapter contrasts against,
  that throughput and stability rise together:
  [DevOps, honestly](../../notes/02-devops-honestly.md)

### Reported by (attributed)

- The observation that time saved in creation is reallocated to auditing and
  verification comes from analysis of the 2025 DORA report rather than from a headline
  finding of it; it is reported here as such, and Chapter 9 returns to it.

### My argument, not established fact

- That the two changes described here are *orthogonal*, and that conflating them is the
  main reason writing on this subject is hard to read, is my framing. The DORA findings
  are evidence about the authorship change only; nothing in them speaks to accelerator
  scheduling.
- That the relocation of the bottleneck to review is the most consequential feature of
  the second revolution is an argument, developed and defended in Chapter 9.

---

*The mechanism half begins with the most basic thing a cluster does: hand a program a
piece of hardware and promise nobody else is using it. Volume I made that promise with
two numbers and a control group. Neither survives contact with a graphics processor.*
→ [The accelerator is not a processor](../../notes/ai/02-the-accelerator-is-not-a-processor.md)
