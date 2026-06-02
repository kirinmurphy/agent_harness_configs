---
name: blog
description: >
  Write a long-form architecture blog post about a real design decision in a
  codebase. Follows a fixed 6-beat storyline arc. Written so the architectural
  ideas are comprehensible across the whole audience spectrum — non-technical to
  highly technical — without becoming a coding tutorial. Trigger: /blog, "write a
  blog post", "draft the architecture article", "blog about <topic>".
---

# Architecture Blog Writer

Write a long-form architecture blog post grounded in real code. The subject is an
architectural **decision** and its story, not a feature list and not a code walkthrough.

## Audience model (read this first — it governs everything)

The audience spans non-technical to highly technical and everywhere between.

- **This is NOT a coding tutorial.** The purpose is to convey architectural ideas
  and the relationships between them, not to teach programming. Code examples
  illustrate *relationships*, not *how-to*.
- **Comprehensible, not condescending.** A non-technical reader should be able to
  follow the logic of every decision — explained without assuming they already have
  the context. But the writing is not *for* an audience with zero code background.
- **Don't overwhelm the technical reader.** The extra context that helps a less
  technical reader must stay concise and woven in. A highly technical reader should
  find the piece logical and fluid, never padded with beginner explanation.
- **One spine for everyone.** Aim for prose where every reader, at their own level,
  finds it coherent. Avoid forking the article into "simple version" and "real
  version." Explain the concept once, at the right altitude, when it's needed.

## Code rules

- Code is **not in the foreground.** Prose and the storyline carry the article.
- Include code only when a concept is fundamental to the implementation and a small
  reference makes the architectural relationship clearer.
- Show **only enough code to explain the architectural idea** — never the full
  implementation, never every detail. Trim to the few lines that reveal the relationship.
  Strip what is ceremony rather than idea: error-handling wrappers (try/catch/throw),
  logging, optional methods the prose never names, defensive guards, multi-line branches
  that collapse to one. If a line isn't what the surrounding prose is pointing at, cut it.
  A real snippet trimmed to its intent beats a complete one that buries the point.
- Do not annotate code with general programming practice. Don't explain syntax or
  teach the language. The snippet exists to show how pieces relate, nothing more.
- **Don't show code for generic or rudimentary logic.** If the snippet is the same
  thing anyone would write regardless of this architecture (a read-decide-write loop, a
  basic null check, a standard CRUD call), describe it in one prose sentence and cut the
  block. Spend the code budget only on what is non-obvious or specific to *this* design —
  the platform quirk, the deliberate seam, the surprising line. A block earns its place
  by showing something the prose can't say as cleanly, not by proving the code exists.
- A diagram or analogy is often better than code for this audience — prefer it when
  it conveys the relationship more directly.
- Snippets must be real, taken from the actual repo. Never invent code.

## Before writing

1. Identify the topic. If the user named one, use it. Otherwise read the project's
   blog-candidates list (e.g. `docs/possible-blog-posts.md`) and ask which to write.
2. Read the actual code for that topic (the listed key files). Ground the article in
   what the code really does — real names, real flow. Never invent behavior.
3. Read any linked source/design docs for the original reasoning and tradeoffs.
4. Save the draft to `docs/blog/<slug>.md` (or the project's blog directory).

## The 6-beat arc (mandatory spine, in order)

Build context progressively. Introduce each technical concept ONLY at the moment a
decision requires it — concepts arrive as the answer to "why?", never as a glossary
up front. This is what keeps the piece readable across skill levels.

1. **The Problem** — Open with the real-world problem in plain language. What was
   broken, slow, fragile, or impossible before. State why it mattered through the
   concrete consequence, not through narrative or appeals to feeling.

2. **The Experience We Wanted** — The user-facing outcome driving the design. Describe
   the behavior the product should produce, stated as a goal. Do not stage a scene or
   address the reader in the second person to set it up.

3. **What That Forced On Us** — The architectural necessities the experience
   *demands*. The bridge beat: introduce the core technical concepts here, each one
   justified by beat 2. "Because we wanted X, we now needed Y."

4. **How We Built It** — The implementation and how it satisfies beat 3. Walk the
   real flow using real component/function names. Code references (small, relationship-
   focused) live here if anywhere. Prose still leads.

5. **What It Still Lacks** — Honest gaps and limits of the chosen solution. Builds
   trust. Don't oversell.

6. **Roads Not Taken** — Alternatives and their tradeoffs. Why the chosen path won,
   and fairly, where an alternative might be better. Surface the pros/cons that
   mattered. Keep this tighter than beats 3–4.

## Voice & restraint (governs word choice everywhere)

The register is matter-of-fact. Logical and flowing, but agnostic to emotion and to
subjective coloring of an outcome. Let the reader draw the value judgment; the prose
supplies the facts and the reasoning.

- **No emotional or evaluative adjectives about the work itself.** Cut words like
  *uncomfortable, proudest, happy, striking, awkward, elegant, beautiful, painful,
  scary, gold, exciting*. If a word rates how the reader or author should *feel* about
  a fact, remove it and let the fact stand.
- **Opinion is allowed; emotion is not.** Comparative, defensible judgments belong in
  the piece — "A is more reliable than B," "this approach is overkill for the current
  case," "the index is the better fit." State them flatly, backed by the reason. What's
  banned is sentiment *about* the outcome, not the analytical conclusion.
- **No staged scenes or second-person narration to set up a point.** Don't write
  "Picture the end of a workday" or "You've just made a few commits." State the
  situation directly: "At the end of a set of commits, a developer wants a review."
- **Say it the short way.** Prefer the plain phrasing over the evocative one.
  "machinery we built might be more than the problem currently needs" → "the design
  may be more than the problem needs." Cut clauses that restate what was just said.
- **Cut sentences that carry no new information.** A sentence whose only job is to
  segue, announce, or restate ("That requirement is where the design starts," "This
  is where it gets interesting," "With that established, we can move on") adds words
  without adding fact. The next beat's content is the transition; let it transition.
  Delete the connector sentence and start the real point.
- **Drop enumerating scaffolding; lead with the noun.** When you list two or three
  things, the "The first is… / The second is…" framing and a preceding "There are two
  X" announce are scaffolding the items don't need. Cut the announce and open each item
  with its own subject: "The first is expiry. … The second is failure." → "Expiry. …
  Failure." The label carries the structure on its own.
- **Don't re-coin an established term.** Once a concept has a name in the piece, refer
  to it by that name. Re-describing it inline as decoration ("the logic that decides
  'this is request four, reject it'" when "the rejection logic" already names it) is
  fluff, and alliterative or vivid restatements are the worst offenders. Name it once,
  then use the name.
- **No aphoristic closers.** End on the concrete point, not a wisdom line. Ban endings
  shaped like "Sometimes the thing you're proudest of is the one that teaches you X."
  The conclusion should be the logical takeaway, stated once.

A sentence passes if removing every adjective and adverb leaves the same factual claim
intact. If removing them changes the meaning, the modifiers were probably coloring, not
information — cut them.

## Tone & structure

- **Storyline first.** Narrate how the decision unfolded, not a static description.
- **Progressive concepts.** First use of a term gets a one-line plain gloss, tied to
  why it matters right then — kept short so it doesn't slow a technical reader.
- **No jargon before its justification.** If a concept hasn't earned its place in the
  story, don't name it yet.
- **Honest, not promotional.** Beats 5 and 6 win credibility.
- Title: concrete and curiosity-driven, not generic.
- Section headers map to the 6 beats but phrased in the article's own voice.
- **Use `###` subheaders to name and split a beat's sub-topics.** When a beat covers more
  than one distinct idea, give each its own subheader rather than running them together
  under one heading. Even a single-topic beat reads better when the topic is *named* — an
  unlabeled section makes the reader infer what it's about. Naming the sub-topic is itself
  the value: it tells the reader what they're about to read and lets a skimmer navigate.
  Phrase subheaders in the article's voice, like the beat headers.
- Target 1,200–2,000 words unless asked otherwise.
- End with a short "What's next" only if the source docs describe a real planned
  evolution.

## After drafting

- Report the saved path.
- Note any place where the code and the design-doc reasoning disagreed, so the user
  can reconcile.
