## devlog: 15 Nov 2026 J | The answers in the posts | Older posts asked Pietro questions and kept asking them after he had answered. Each answered question now shows its answer, its date and where it was carried out; the ones still open are listed here.
## kind: research
import std/[json, os, strformat, strutils, sequtils]
import nimib
import ../blocks

nbInit
nb.usePost()

const here = currentSourcePath().parentDir
let questions = parseJson(readFile(here / "data" / "the_answers_in_the_posts" / "questions.json"))["questions"].elems
proc slug(post: string): string = post.replace('_', '-')
proc title(post: string): string =
  ## the title of a post, from its first line
  readFile(here / post & ".nim").splitLines[0].split(" | ")[1]
let
  byPietro = questions.filterIt(it["by"].getStr == "pietro")
  byStep = questions.filterIt(it["by"].getStr == "step")
  stillOpen = questions.filterIt(it["by"].getStr == "open")
  posts = deduplicate(questions.filterIt(it["by"].getStr != "open").mapIt(it["post"].getStr))

# Every answered question must show its answer in its post: the build fails otherwise.
for q in questions:
  if q["by"].getStr != "open":
    doAssert q["marker"].getStr in readFile(here / q["post"].getStr & ".nim"),
      q["post"].getStr & " does not show its answer to: " & q["question"].getStr

nbText: &"""
## The findings, first

- **{questions.len} questions** in the posts written before 15 November ask for a choice, of
  Pietro or of a later step. **{byPietro.len} were answered by Pietro** and
  **{byStep.len} by a later step**; **{stillOpen.len} are still open**.
- The {byPietro.len + byStep.len} answers are now in {posts.len} posts, under their questions:
  who answered, when, what was chosen, and a link to where it was carried out (a decision record,
  a later post). The rest of each post is as it was written.
- Every answer was already somewhere, in a decision record, the roadmap or a later post. What was
  missing was the way back: a reader who met the question first found it still asked.
- This page checks itself: each answered question names a few words its post must now hold, and
  the build fails if a post loses them.

## Why posts change now

A post tells one step as it happened, and is not rewritten. Many ended with a question for
Pietro, in a note of the kind *question*. When he answered, the answer went where the work
continued, and the question stayed open on the page where a reader meets it first. On 15 November,
after choosing among the proposals of [*Twelve minutes of checks*](../twelve-minutes-of-checks/),
Pietro set a rule
([decision 0021](../../decisions/#0021-posts-record-the-answers-to-their-questions)): the answer is
written under its question, with its date and a link, and nothing else in the post changes. The
post's version goes up; its date stays.

This step did the same for the posts that came before the rule.

## How the questions were found

Three passes over the {len(toSeq(walkFiles(here / "*.nim"))) - 2} earlier posts' sources:

1. every note of the kind *question* (`nkQuestion`);
2. every line naming Pietro, which finds the questions asked in the text ("for Pietro to choose",
   "waits for Pietro", "Pietro's go-ahead");
3. the words of proposals and options ("proposed", "options", "a later step", "is open").

Each candidate was then read in its context, and its answer looked for in the decision records,
the roadmap, the later posts and the project chat. Two notes of the kind *question* are not
questions: *A stage for a port* and *Pomice* show what each kind of note looks like, with a sample
text.
"""

nbText: "## The answered questions"

block:
  var t = "| Post | Question | Answer | By |\n| --- | --- | --- | --- |\n"
  for q in questions:
    if q["by"].getStr == "open": continue
    let who = if q["by"].getStr == "pietro": "Pietro, " & q["answered"].getStr
              else: "a later step, " & q["answered"].getStr
    t.add &"| [{title(q[\"post\"].getStr)}](../{slug(q[\"post\"].getStr)}/) | {q[\"question\"].getStr} | {q[\"answer\"].getStr} ({q[\"where\"].getStr}) | {who} |\n"
  nbText: t

nbText: """
Two answers were marked *Answered* rather than *Pietro's answer*: nobody asked him, because the
next step settled them. The strings were decided the same day by the first port, which tried what
the research post leaned to; the block that checks each diagram against Pele was built by a later
thread. *Dates and styles in JavaScript* had its answer already, added the day it was merged; it
now also links where the answer was carried out.

## Still open
"""

block:
  var t = "| Post | Question |\n| --- | --- |\n"
  for q in stillOpen:
    t.add &"| [{title(q[\"post\"].getStr)}](../{slug(q[\"post\"].getStr)}/) | {q[\"question\"].getStr} |\n"
  nbText: t

nbNote """
- **Pointing nim-regex's author to the proposal** is Pietro's call: nimaki does not open issues
  or pull requests on other projects.
- **1.0.0** is for the day the API is meant to stay (decision 0020), also Pietro's call. It was
  not asked as a question, so nothing is pending on it yet.
- **A smaller JavaScript build** is for a later step, not for Pietro; it is not on the roadmap.
""", nkQuestion, "Open"

nbText: &"""
[*Twelve minutes of checks*](../twelve-minutes-of-checks/), the post that led to the rule, shows
Pietro's answer to its proposals already: its own thread added it, as the rule asks.

## What this changes for the port

- {posts.len} posts show the answers to their questions: {posts.mapIt("*" & title(it) & "*").join(", ")}.
- The roadmap step *The answers in the posts* is done. From now on, the thread that receives an
  answer adds it to the post, in its next pull request (decision 0021).
- `docs/devlog/data/the_answers_in_the_posts/questions.json` lists every question with its answer
  or as open; this page fails to build if a post loses an answer.

## Sources

- [Decision 0021](../../decisions/#0021-posts-record-the-answers-to-their-questions), and the
  records the answers point to: 0011, 0014, 0016, 0019, 0020.
- The [roadmap](../../roadmap/), and Pietro's messages in the project chat of 14 and 15 November
  2026 (not public).
- The posts themselves, read at the commit of this page.
"""

nbSave
