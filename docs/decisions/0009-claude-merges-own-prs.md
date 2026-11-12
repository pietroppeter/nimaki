---
title: Threads open, review and merge their own pull requests; Pietro steers with Start and Stop
status: accepted
date: 2026-11-12
---

## Context

Several threads work at once, and Pietro reviews from his phone, hours later. His first brief
said nothing goes to `main` without his go; the second said threads may open, review and merge
their own pull requests. Asked which holds, he chose the second on 12 November 2026.

## Decision

- One branch and one pull request per step. A thread merges its own pull request when CI is
  green and it has rebased on `main`. Tags and releases wait for Pietro.
- Pietro pauses and resumes the whole project with "Stop" and "Start" in the project chat. On
  Stop, every thread finishes the smallest safe unit, pushes, updates the roadmap and the devlog,
  and leaves its step resumable (a draft pull request is a save point).

## Consequences

- Review happens on the deployed pages and in the pull requests, after the merge; a correction
  is a new pull request.
- Because nothing waits, the roadmap's `owner` field is what keeps two threads off the same step.
