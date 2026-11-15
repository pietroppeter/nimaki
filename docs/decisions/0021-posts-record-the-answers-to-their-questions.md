---
title: Posts record the answers to their questions
status: accepted
date: 2026-11-15
---

## Context

A devlog post tells one step as it happened, and AGENTS.md said it is not rewritten afterwards.
Many posts end with a question for Pietro, in an `nkQuestion` note: which proposals to make, which
option to take. When he answered, the answer went into the roadmap, a decision record or the next
post, and the question stayed open on the page where a reader meets it first. The post *Twelve
minutes of checks* (15 November) asked which CI changes to make; Pietro chose, then asked whether
posts are updated after a decision, and set this rule (15 November 2026).

## Decision

When Pietro answers a question a post asks, the post records the answer in the same note, under
the question: **Pietro's answer** with its date, what he chose, and a link to where it is carried
out (a roadmap step, a decision record, a pull request, a later post). The question and the rest
of the post stay as they were written. The thread that receives the answer updates the post, in
its next pull request.

A roadmap step (*post-answers*) goes through the posts written before this rule, finds the
questions that have been answered since, and adds the answers.

## Consequences

- A reader of a post sees whether its questions are still open, and where an answer led.
- A post's version (review mode) goes up when an answer is added; the post keeps its date.
- An answer that changes what must stay true still goes in a living page or in AGENTS.md as well;
  the note in the post only points to it.
