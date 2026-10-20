# Chapter 8: AIOps, Honestly

*Gartner's definition and the term's history verified; the critique is attributed and, in
places, mine. Checked August 2026.*

Some terms are contested. This one is worth approaching differently, because its own
industry has documented its confusion in unusual detail, and that documentation is the
most useful thing about it.

## Where the word came from

**AIOps** was coined by Gartner, the industry analyst firm, in 2016. It is worth being
precise about what it originally stood for, because the change is revealing: it was
introduced as shorthand for *Algorithmic IT Operations*, and within roughly a year the
same firm had redefined the acronym to mean *Artificial Intelligence for IT Operations*.

Sit with that for a moment. The letters stayed; the words behind them changed to the more
fashionable option. That is not a scandal (terms drift), but it does tell you something
about which way the pressure was running, and it is a useful piece of evidence when
someone presents the term as though it named a discovered thing rather than a coined one.

Gartner's own definition of an AIOps platform is that it combines big data and machine
learning functionality to support IT operations functions through the scalable ingestion
and analysis of the growing volume, variety and velocity of data that IT systems generate.

Read that as an engineer and notice what it does *not* say. It does not name a mechanism.
It does not say what problem is solved or how you would know it had been. It is a
description of an input (lots of operational data) and a technique (machine learning), with
the connection between them left as an exercise. Compare it to a definition from Volume I
(a PodDisruptionBudget constrains the Eviction API such that an eviction is refused when
granting it would drop healthy Pods below the budget), and the difference in kind is
obvious. One tells you what happens. The other tells you what is involved.

## The identity crisis is documented, not alleged

I want to be careful here, because "this term is vague" is an easy and lazy criticism.
What makes this case unusual is that the vagueness has been documented by the industry
itself rather than only by skeptics.

The recorded history is that the broad initial definition produced sustained confusion,
with different vendors characterising AIOps according to whatever they happened to be
selling; that the category suffered from a lack of clear boundaries about what an AIOps
solution did and did not do; and that vendors pitched it as ready to solve essentially all
operational problems, which overpromised and diluted the value proposition. Gartner itself
has since moved toward renaming and re-scoping the category.

That last fact is the one I would weigh most heavily. When the analyst firm that coined a
term concludes it needs re-scoping, the reasonable inference is not that the underlying
technology failed, but that the *category* was drawn around a technique rather than around
a problem, and categories drawn that way tend not to survive.

## What is actually real

Now the more useful question, because there is something real here and dismissing the whole
thing would be its own kind of laziness.

Strip away the platform framing and there is a genuine class of problem that statistical
methods address well, and it is a problem Volume I set up precisely. Chapter 1 of that
volume defined **toil**: operational work that is manual, repetitive, automatable, and
scales linearly with the size of the system. Chapter 2 defined **monitoring** and
**alerting**: collecting measurements, and rules over those measurements that summon a
human.

Put those together and you get a specific, mechanical difficulty. Alerting rules are
thresholds written by people. At small scale you can write good ones. At large scale you
cannot, for reasons that are arithmetic rather than cultural: there are too many signals,
their normal ranges vary by service and by time of day and by season, and every threshold
you write is a guess that will be wrong in one of two directions. Too tight and it fires
constantly, which trains people to ignore it. Too loose and it misses the incident.

Alert fatigue is the standard name for the result, and it is a real, expensive, and
extremely well-attested operational failure. Anyone who has carried a pager knows it.

The genuinely mechanical parts of AIOps address exactly this, and they are worth naming
separately from the platform pitch:

**Anomaly detection**: learning what a signal's normal range actually looks like, rather
than having a human guess a threshold. This is honest statistics applied to a problem that
is genuinely statistical, and it does not require anything to be intelligent.

**Event correlation**: recognising that four hundred alerts firing within thirty seconds
are one incident rather than four hundred, and grouping them. This is the single most
valuable thing in the category, and it is essentially a clustering problem.

**Noise reduction and deduplication**: suppressing the alerts that are consequences of
another alert you have already surfaced.

Notice what all three have in common: they operate on *telemetry the system already
produces*, they make a human's attention go further, and none of them takes an action. They
are improvements to the feedback loop from Volume I's Chapter 2, and they are valuable in
direct proportion to how much telemetry you have, which is why they became interesting at
the same time as everything else in this book.

Notice also what they are not. None of them requires a large language model. Most of this
category predates the current wave entirely and is closer to time-series statistics than to
anything people currently mean by AI. That is not a criticism; it is a reason to be
suspicious when the same capability is re-marketed each time the underlying technique
changes fashion.

## The line I would draw

Here is my argument, and you should weigh it as an argument rather than a finding.

The useful distinction in this category is not between AI and not-AI. It is between systems
that **inform a human decision** and systems that **take an action**.

Anomaly detection, correlation, and noise reduction all sit on the informing side. Their
failure mode is bounded: if they are wrong, a human sees a bad grouping or a spurious
anomaly, applies judgement, and moves on. The cost of a false positive is some attention.
That is a good trade, and it is why these capabilities are genuinely deployed and genuinely
useful.

Automated remediation sits on the other side, and its failure mode is not bounded in the
same way. A system that restarts a service, or scales a deployment, or reroutes traffic, is
acting on production. If its inference is wrong, the cost is not attention; it is an
outage caused by the thing that was supposed to prevent one. And Volume I gives you the
precise reason to be nervous, in the restart storm: a health check that *was* correctly
detecting a real problem responded in a way that converted a thirty-second dependency blip
into a multi-minute outage. That was a simple threshold with a simple action, and it still
went badly, because the action was correlated across the fleet.

An automated remediation system is that pattern with a more sophisticated trigger and a
wider range of actions. Sophistication of the trigger does not fix the structural issue,
which is that correlated automated action under uncertainty can amplify an incident rather
than resolve it.

So the question I would ask any vendor or team in this space is not "how good is your
model?" It is: **what does it do when it is wrong, and how would I find out?** For the
informing capabilities, those questions have good answers. For the acting ones, they are
the whole engineering problem, and they are where the honest conversation is.

## What this leaves

Strip the category down and you get something modest and real: **statistical methods
applied to operational telemetry, to make finite human attention go further.** That is a
useful thing. It is directly aimed at Volume I's toil argument. It deserves better than
the framing it has been given.

What it does not do is remove operations, and the version of the claim that says it does
is the version that produced the identity crisis. Volume I's Chapter 4 made a parallel
observation about cloud: it moved operations rather than removing it. This category has
made the same promise with a different technology and, so far, produced the same outcome.

Which leads directly to the next chapter, because there is a genuinely new version of this
claim (not "AI will watch your systems" but "AI will *write* them"), and that one changes
something structural rather than incremental. It is the one this volume exists to argue
about.

## What to carry forward

**The term was coined by an analyst firm, not discovered**, and its own coiner has moved
to re-scope it. That history is legitimate evidence about how much weight it carries.

**The real content is statistical, valuable, and mostly not new**: anomaly detection,
event correlation, noise reduction, all aimed at alert fatigue, which is a genuine and
expensive problem.

**The useful line is inform versus act.** Informing has a bounded failure mode. Acting does
not, and Volume I's restart storm is the reason to take that seriously.

## Read the source

### Verified against primary sources

- **Gartner's AIOps glossary definition**: the platform definition paraphrased above:
  https://www.gartner.com/en/information-technology/glossary/aiops-artificial-intelligence-operations
- **Volume I, Chapter 1**: toil, and the argument that automation exists to remove it:
  [The operational burden](../../notes/01-the-operational-burden.md)
- **Volume I, Chapter 11**: the restart storm, the worked example of correlated automated
  action making an incident worse: [Staying up](../../notes/11-staying-up.md)

### Reported by (attributed)

- The term's origin (Gartner, 2016), its original expansion as *Algorithmic IT Operations*,
  and the subsequent redefinition to *Artificial Intelligence for IT Operations* are
  reported consistently across the industry record, including the Wikipedia entry on AIOps
  and vendor and analyst commentary.
- The characterisation of the category's "identity crisis" (unclear boundaries,
  vendor-specific definitions, overpromising) is reported by industry commentators, notably
  Cribl's write-up of Gartner's re-scoping of the category:
  https://cribl.io/blog/from-aiops-to-event-intelligence-gartner-rebrand-fixes-industry-identity-crisis/
  This is a vendor blog, and vendors have interests; I cite it because it documents the
  re-scoping, not as a neutral assessment.

### My argument, not established fact

- That Gartner's definition names a technique and an input rather than a mechanism, and
  that this is why the category drifted, is my analysis.
- The inform-versus-act line as the useful distinction in this category is my argument,
  not a standard taxonomy.
- That automated remediation inherits the restart-storm risk structurally, because
  correlated automated action under uncertainty can amplify incidents, is my reasoning
  from Volume I's material, not a documented finding about any particular product.

---

*This chapter's subject was a claim about AI watching your systems, and it turned out to be
modest and mostly statistical. The next claim is different in kind: that AI is writing
them. That one is measured, it is happening now, and it undermines an assumption every
safety mechanism in both volumes quietly depends on.*
→ [When the author is not human](../../notes/ai/09-when-the-author-is-not-human.md)
