# Chapter 10: Reading a Fast-Moving Field

*Checked August 2026, which is exactly the point of this chapter.*

Volume I closed by telling you that reading cannot make you a specialist, and that the way
to close the gap is to build a cluster you are allowed to destroy and break it on purpose.
That advice is unchanged and applies here: every mechanism in Part II can be reproduced on
a laptop, and doing so will teach you more than re-reading it.

This chapter is about the other thing you need, which Volume I needed less.

Volume I described a system whose fundamentals have been stable for years. The
reconciliation loop is not going to change. Labels and selectors are not going to change.
That corpus will age slowly and gracefully.

This volume will not. A meaningful fraction of what you have just read will be wrong within
two years, and I do not know which fraction. So the last useful thing I can give you is not
another mechanism. It is a way of evaluating the next claim you meet, after this volume has
stopped being current.

## Ask when, and of what version

The first question to ask of any claim about this field is not whether it is true. It is
**when was this true, and of what version?**

That sounds pedantic until you notice how much writing on this subject carries no date at
all, or carries a publication date while describing behaviour from two versions earlier. A
post explaining that GPUs must be requested as whole integers through a device plugin was
correct for years and is now describing a superseded mechanism: Dynamic Resource
Allocation is stable and enabled by default, and a reader who found that post today would
be learning the previous generation's constraints as though they were permanent.

Neither the author nor the post did anything wrong. It aged. That is the normal condition
of writing in a field like this, and the only defence is the habit of checking the date and
the version before you check anything else.

This is why every chapter in this volume opens with what it was verified against and when.
It is not ceremony. It is so you can tell how much to trust it in two years, without having
to guess.

## Distinguish a specification from a product page

The second habit is the one that does the most work, and it is a distinction Volume I could
mostly take for granted.

When Volume I made a claim, it linked to `kubernetes.io`: versioned, open, and
community-governed documentation for an implementation you can read. That is a **specification**: a
description of behaviour that something is obliged to exhibit, which you can check.

Much of what is written about AI and operations is not that. It is a **product page**: a
description of what something does, published by the people selling it, with no external
obligation behind it. Product pages are not lies. But they are answerable to a different
standard, and the two look increasingly alike because product pages have learned to adopt
the grammar of engineering: version numbers, architecture diagrams, the word "primitive."

Three questions separate them reliably:

**Is there an artifact I can read that is not marketing?** A specification, an API
reference, a repository, an RFC. If the deepest available description of a mechanism is a
blog post with a call-to-action at the bottom, you are reading a product page.

**Who is obliged by it?** A specification binds implementations; that is what makes it
useful. A product page binds nobody, including its author, who may change the behaviour in
the next release without telling you.

**Does it say what happens when it is wrong?** This is the sharpest test, and it is the one
I used in Chapter 8. Engineering documentation describes failure modes because engineers
need them. Marketing rarely does, because failure modes are not a selling point. A
description of a system that contains no account of how it fails is not a technical
description, whatever its formatting suggests.

## Watch the specifications, not the announcements

If you want to track this field rather than react to it, the useful move is to follow the
places where the mechanisms are actually decided.

The Kubernetes Special Interest Groups do their work in public: proposals, design
documents, and the arguments about them. That is where you find out what is coming, and
more importantly *why*, which is the part that lets you evaluate whether it will matter to
you. The Gateway API Inference Extension repository, the Kueue repository, and the Dynamic
Resource Allocation work in the Kubernetes project are the three most relevant to Part II
of this volume, and all three are readable.

For the research side, the DORA programme continues to publish annually, and it is the only
instrument I know of that measures the questions in Chapter 9 rather than asserting answers
to them. If its findings on AI adoption and stability shift, Chapter 9's argument shifts
with them, and I would rather you tracked the source than took my word for the state of it.

For the underlying diagnosis, Sculley et al. remains worth re-reading. A decade-old paper
that still describes your problems accurately is telling you something about which parts of
the field are fundamental and which are fashion.

## Be specific about what you do not know

The last habit is the one this volume has tried to model rather than merely recommend.

There is enormous pressure in this subject to speak confidently, because confidence is what
gets read. The result is a body of writing in which the verified, the reported, and the
speculated are indistinguishable, not because anyone is lying, but because nobody marked
the boundaries and the reader has no way to reconstruct them.

The three-way split at the end of every chapter here exists for that reason. It was
uncomfortable to write, because it makes visible exactly how much of any interesting claim
is argument rather than fact. That discomfort is the useful part. If you write about this
field (internally, for your team, in a design document), I would recommend the discipline
regardless of format: say which parts you checked, which parts you are repeating from
someone else, and which parts are your reasoning. It costs a line and it changes how much
your reader can rely on you.

## What this volume expects to get wrong

In that spirit, my own list, so you can check it later.

**The API names in Chapter 5 will change.** The Gateway API Inference Extension is young
and its model-facing types have already been revised once during development. `InferencePool`
is at v1 and is the stable part; treat the surrounding names as current-at-time-of-writing.

**The cold-start figures in Chapter 4 will not replicate exactly.** They come from a
single-author preprint, and they depend on hardware and network conditions I cannot
generalise from. The shape of the finding (that delivery dominates startup) is what I
expect to survive.

**Chapter 8's category may be renamed out from under it.** Gartner has already moved to
re-scope AIOps. The mechanisms I described as the real content of it will survive under
whatever the next label is.

**Chapter 9's argument may be overtaken.** I set out four falsification conditions there,
and the most likely one is that review tooling improves enough to keep pace with generation.
If that happens, the argument weakens considerably and I would rather you noticed than that
I quietly stopped mentioning it.

**Anything I have described as settled that is actually contested.** I have tried to mark
these, and I will have missed some. Where a chapter states a mechanism without quoting a
source, treat it with more suspicion than the parts that quote.

## A closing word

Volume I ended by arguing that the tools turn over and the ideas do not, and that what you
should be accumulating is the second thing.

That advice matters more here, not less. Almost every specific fact in this volume has a
shelf life. What does not expire is the shape of the reasoning: that a resource which cannot
be overcommitted needs a different allocation model than one which can; that work which
cannot start halfway needs admission control rather than per-item scheduling; that a payload
which dominates transfer time changes what "disposable" means; that replicas differentiated
by in-memory state cannot be balanced by a mechanism that cannot see state; that a safety
strategy which assumes a reader is only as good as the reading.

Those are not facts about 2026. They are the reasons behind the facts, and they will let
you evaluate the next generation of mechanisms in an afternoon rather than a quarter.

And the habit underneath all of it is the one Volume I asked for and this volume has tried
to earn: check it yourself. Follow the links. The parts of this that are true will survive
your checking, and the parts that are not deserve to be caught.

## Read the source

### Verified against primary sources

- **Kubernetes SIG structure and public design process**: where mechanisms are decided in
  the open: https://github.com/kubernetes/community/blob/master/sig-list.md
- **Gateway API Inference Extension**:
  https://github.com/kubernetes-sigs/gateway-api-inference-extension ·
  **Kueue**: https://github.com/kubernetes-sigs/kueue ·
  **Dynamic Resource Allocation**:
  https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/
- **Volume I, Chapter 15**: the practise-and-break-things advice this chapter assumes
  rather than repeats:
  [Becoming the specialist](../../notes/15-becoming-the-specialist.md)

### Reported by (attributed)

- **The DORA programme**, publishing annually, as the instrument measuring Chapter 9's
  questions: https://dora.dev/research/
- **Sculley et al.**, NeurIPS 2015, as the diagnosis that has outlasted the tooling built
  in response to it:
  https://papers.nips.cc/paper/5656-hidden-technical-debt-in-machine-learning-systems

### My argument, not established fact

- The three tests for separating a specification from a product page are mine, in
  particular the claim that an absent account of failure modes is the sharpest signal.
- The list of what this volume expects to get wrong is my judgement about my own work, and
  is offered so that it can be checked against rather than quietly revised.

---

*That is the end of Volume II. To look something up, the [glossary](../../notes/ai/glossary.md) covers
this volume's vocabulary and links back into the chapters. [Volume I](../../notes/index.md)
remains the foundation, and if any of this felt like it was standing on something you had
not quite absorbed, that is where to go. The [contents](../../notes/ai/index.md) will take you anywhere
in this volume directly.*
