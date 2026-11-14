## devlog: 14 Nov 2026 C | How nimaki reads text | The second article on nimaki's own code: how its diagram types cut Mermaid text into tokens, in three families of lexer, and what happened when a new tool slipped one invisible character into every case of the corpus.
## kind: research
import std/[algorithm, json, os, sequtils, strformat, strutils, tables]
import nimib
import tabelline, tabelline/nimib
import ../blocks
import nimaki
from nimaki/js import utf16Len, jsTrimStart
from nimaki/diagrams/common/tokens import tokenize
from nimaki/diagrams/pie/parser import PIE_TOKENS
from nimaki/diagrams/journey/lexer as journeyLexer import nil

nbInit
nb.usePost()

# What this post counts, frozen: the census of the code it was written on (tools/census.nim) and
# seven runs of tools/mutate.nim, seeds 1 to 7. The numbers below come from these files.
const dataDir = currentSourcePath.parentDir / "data" / "how_nimaki_reads_text"
let census = parseJson(readFile(dataDir / "census.json"))
var runs: seq[JsonNode]
for seed in 1 .. 7: runs.add parseJson(readFile(dataDir / &"mutate-{seed}.json"))

proc thousands(n: int): string = insertSep($n, ',')

let
  commit = census["commit"].getStr
  shortCommit = commit[0 .. 6]
  lexers = census["lexers"].elems
  family = proc (name: string): seq[JsonNode] = lexers.filterIt(it["family"].getStr == name)
  tableTypes = family("table")
  jisonTypes = family("jison")
  outlineTypes = family("outline")
  jisonCode = jisonTypes.mapIt(it["code"].getInt).foldl(a + b, 0)
  statesOf = proc (t: string): int =
    for l in lexers:
      if l["type"].getStr == t: return l["states"].getInt
  mutated = runs.mapIt(it["cases"].getInt).foldl(a + b, 0)
  mutatedDifferent = runs.mapIt(it["different"].getInt).foldl(a + b, 0)
  copies = runs[0]["copies"].getInt
  perRun = runs[0]["cases"].getInt

proc names(rows: seq[JsonNode]): string = rows.mapIt(it["type"].getStr).join(", ")

nbText: fmt"""
The [first article on the code](../the-shape-of-the-port/) took the widest view of nimaki. This one
follows a diagram's text through its first step: **lexing**, cutting text into words, which every
one of the {lexers.len} diagram types on `main` does before anything else, at commit `{shortCommit}`.
Explaining the lexers asked one question I could not answer by reading: what do they do with
characters the corpus never has? So a new tool asked Pele and nimaki, {thousands(mutated)} times.

## The short version

- **A lexer turns text into tokens**, the words of a little language: `pie`, `"Dogs"`, `:`, `386`.
  A parser then reads the tokens, not the characters. In nimaki, as in Pele, both are written by
  hand, with no lexer or parser generator.
- **There are three families of lexer.** {tableTypes.len} types describe their tokens in a
  **table** and share one tokenizer (the types whose grammar Mermaid writes in Langium).
  {jisonTypes.len} have a **lexer of their own**, a hand-written port of the rules Jison compiled
  for Mermaid, with *start conditions* that change what a character means ({thousands(jisonCode)}
  lines of code in all). Two read an **indented outline**. Swimlane borrows flowchart's.
- **A new referee, `tools/mutate.nim`, slips one invisible or unusual character** (a no-break
  space, a line separator, a byte order mark, a letter outside the Basic Multilingual Plane...)
  into a random place of every corpus case nimaki draws, and compares nimaki's answer with Pele's.
  In {runs.len} runs, {thousands(mutated - mutatedDifferent)} of {thousands(mutated)} answers are
  identical. The **lexers held on every one**.
- **The {mutatedDifferent} differences come from five places past the lexers**: links whose host
  has a character outside ASCII, a YAML reader that counts indentation in bytes, a class member
  that grows by two pixels, a date that should not parse, and a link Pele drops. They are on the
  roadmap as one step, `reading-fixes`, with the cases that show them.
- On the way, the referee's own oracle turned out to stop on one kind of error (a front matter
  that is not YAML) and lose every case after it. Fixed in this pull request.

## What a lexer does

Reading `pie title Pets` one character at a time is hard: is `p` the start of `pie`, of a name, of
a title? A lexer reads the characters once and hands the parser bigger pieces, **tokens**, each
with a **kind** and the text it covers. A toy lexer for a pie, in a dozen lines: it tries a list of
patterns in order at the current position, and the first that matches makes the token.
"""

nbCode:
  type Rule = (string, proc (s: string, p: int): int)   # a kind, and where its match ends (-1: none)
  proc word(w: string): proc (s: string, p: int): int =
    result = proc (s: string, p: int): int = (if s.continuesWith(w, p): p + w.len else: -1)
  proc run(chars: set[char]): proc (s: string, p: int): int =
    result = proc (s: string, p: int): int =
      var e = p
      while e < s.len and s[e] in chars: inc e
      if e > p: e else: -1
  proc quoted(s: string, p: int): int =
    if p < s.len and s[p] == '"': (let q = s.find('"', p + 1); if q > 0: q + 1 else: -1) else: -1
  let rules: seq[Rule] = @[("keyword", word("pie")), ("string", quoted), (":", word(":")),
                           ("number", run({'0'..'9'})), ("space", run({' ', '\n'}))]
  proc lex(s: string): seq[string] =
    var p = 0
    while p < s.len:
      var matched = false
      for (kind, rule) in rules:
        let e = rule(s, p)
        if e > p:
          if kind != "space": result.add kind & " " & s[p ..< e]
          p = e
          matched = true
          break
      if not matched: raise newException(ValueError, "no token at " & $p)
  for token in lex("pie\n\"Dogs\": 386\n\"Cats\": 85"): echo token

nbText: fmt"""
That is the whole idea. Everything else is about doing it exactly as Mermaid does: which
patterns, in which order, what wins when two match, and what a character means *here*.

## Three families

Mermaid itself was written over ten years, and its grammars come in two generations: the older
diagram types have **Jison** grammars (a lexer of regular expressions and an LR parser,
generated), the newer ones **Langium** grammars (whose lexer is Chevrotain's). Pele rewrote both
by hand to behave the same, and nimaki ported Pele's rewrite. The family of each type, counted in
the code:
"""

block:
  type Row = object
    family: string
    types: int
    which: string
  let rows = @[
    Row(family: "a table of tokens, one shared tokenizer", types: tableTypes.len, which: names(tableTypes)),
    Row(family: "a lexer of its own (Jison's rules)", types: jisonTypes.len, which: names(jisonTypes)),
    Row(family: "an indented outline", types: outlineTypes.len, which: names(outlineTypes)),
    Row(family: "another type's lexer", types: family("borrowed").len, which: names(family("borrowed"))),
  ]
  let t = tabella(rows, rownameCol = "family"):
    tabHeader "How each diagram type reads its text", "at " & shortCommit & ", by tools/census.nim"
    colsLabel {"which": "the types"}
    optCssTheme()
  nbTable t

nbText: fmt"""
### A table of tokens

The Langium types do not have a lexer file at all. Their parser starts with a **table**: a list
of token types, each a literal (`"pie"`, `":"`) or a pattern, tried in order, first match wins,
exactly like the toy above. One function, `tokenize` in `diagrams/common/tokens.nim`, runs every
table. Here it is on a pie, with the real table of `pie/parser.nim`:
"""

nbCode:
  let pieText = "pie showData\n  title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85.5\n"
  let toks = tokenize(pieText, PIE_TOKENS, "pie")
  for i in 0 ..< toks.kinds.len - 1:
    echo PIE_TOKENS[toks.kinds[i]].name.alignLeft(12), escape(pieText[toks.starts[i] ..< toks.ends[i]])

nbText: """
The spaces are gone (their token type is *hidden*), and `title Pets` is one token: the pattern of
`title` takes the rest of the line. Three refinements, all from Chevrotain, make the table
behave as Mermaid's does:

- **First match wins, unless a longer one waits.** A keyword like `service` is also a valid name
  start (`serviceA`). A token type can list *longer alternatives*: when it matches, they are tried
  at the same place, and one that matches more text wins. Architecture and event modeling use it.
- **A quick index.** For each ASCII character, the tokenizer keeps the list of token types that
  can start with it, so at a `"` it tries only the string. That is speed, not meaning: the order
  inside each list is the table's.
- **No rescanning.** A pattern like Pele's number for pies reads a whole run of digits before it
  knows whether a fraction follows; tried again at every digit of a long run, that is quadratic
  time. Such patterns become small scanners that remember what they already read, and a pattern
  that needs a closer (a `---` front matter, a `%%{` directive) is given up for good once the
  closer is known to be missing.

### A lexer of its own

The Jison types each have a `lexer.nim`, a loop that ports, rule by rule, what Jison generated
from Mermaid's grammar. Their trick is **start conditions**: the lexer is in a *state*, and the
state decides which rules apply. Inside a string, `-->` is just text; outside, it is an arrow.
A toy with two states:
"""

nbCode:
  proc lexStates(s: string): seq[string] =
    var inString = false          # the state: INITIAL or string
    var p = 0
    var text = ""
    while p < s.len:
      let c = s[p]
      if inString:
        if c == '"':
          result.add "STR " & text
          text = ""
          inString = false        # back to INITIAL
        else: text.add c
        inc p
      elif c == '"':
        inString = true           # enter the string state
        inc p
      elif s.continuesWith("-->", p):
        result.add "ARROW"
        p += 3
      elif c in {'A'..'Z', 'a'..'z'}:
        var e = p
        while e < s.len and s[e] in {'A'..'Z', 'a'..'z'}: inc e
        result.add "ID " & s[p ..< e]
        p = e
      else: inc p
  echo lexStates("A --> B")
  echo lexStates("A --> \"not --> an arrow\"")

nbText: fmt"""
Real lexers have many more: flowchart's has {statesOf("flowchart")} states (strings, Markdown
strings, accessible descriptions, the text inside each kind of node shape, edge labels,
`click` callbacks, `@{{...}}` metadata), state diagrams {statesOf("state")}, agentflow and
block {statesOf("agentflow")}, class {statesOf("class")}. Some states are kept on a stack, so the
lexer can return to whatever state it came from. The small ones (journey, timeline, ishikawa)
need none. Here is journey's, on a journey:
"""

nbCode:
  let journeyText = "journey\ntitle My day\nsection Work\n  Code: 5: Me\n"
  let jt = journeyLexer.tokenize(journeyText)
  for i in 0 ..< jt.types.len:
    echo journeyLexer.TOKEN_NAMES[jt.types[i]].alignLeft(10), escape(jt.texts[i])

nbText: fmt"""
The text of a task's score (`: 5: Me`) is one `taskData` token: journey's lexer leaves the
splitting to the parser, as Mermaid's grammar does. Each family stops at the parser's door, and
every parser in nimaki is written by hand as a set of functions that call each other, one per
rule of the grammar (a *recursive descent* parser), even where Mermaid's was a generated table.

### An indented outline

Mindmap and kanban have no keywords inside: their structure is **indentation**, like Python's.
`diagrams/common/outline.nim` reads lines, measures how far each is indented, and gives the parser
tokens for *a node at this depth*. It is the one lexer that cares about the width of the space
at the start of a line, which makes it the place to watch in the next section.

## One odd character

All three families compare characters, and the porting guide warns about the place where Nim and
JavaScript disagree on what a character is: JavaScript strings are UTF-16, nimaki's are UTF-8
bytes ([decision 0011](../../decisions/#0011-strings-stay-utf-8-javascript-s-utf-16-is-counted-only-where-it-shows)).
The corpus is mostly ASCII, written by people who type spaces with the space bar. So
`tools/mutate.nim` takes every corpus case of a type nimaki draws, makes {copies} copies, and
slips into each, at a seeded random place, one of nine characters:
{runs[0]["inserts"].elems.mapIt(it.getStr).join(", ")}. Pele and nimaki then both answer every
copy, and the answers are compared byte for byte, errors included. Seven seeds give
{runs.len} × {thousands(perRun)} cases:
"""

block:
  type Row = object
    seed: int
    cases, identical, different: int
  var rows: seq[Row]
  for r in runs:
    rows.add Row(seed: r["seed"].getInt, cases: r["cases"].getInt, identical: r["identical"].getInt,
                 different: r["different"].getInt)
  let t = tabella(rows, rownameCol = "seed"):
    tabHeader "One character slipped in, nimaki against Pele", "tools/mutate.nim, " & $copies & " copies of each ported case"
    fmtInteger ["cases", "identical"]
    optCssTheme()
  nbTable t

# Sort the differences by cause, from the verdict's own words.
proc cause(d: JsonNode): string =
  let detail = d["detail"].getStr
  let parts = detail.split("` nimaki `")
  let pele = if parts.len > 1: parts[0] else: detail
  let nim = if parts.len > 1: parts[1] else: ""
  if "YAML" in detail: "yaml"
  elif "Invalid date" in detail: "date"
  elif "viewBox" in detail: "size"
  elif "href=" in pele and "href=" in nim: "host"
  elif "<a" in nim and "<a" notin pele: "dropped"
  else: "other"

var byCause: OrderedTable[string, seq[JsonNode]]
for c in ["host", "dropped", "yaml", "size", "date", "other"]: byCause[c] = @[]
for r in runs:
  for d in r["differences"]: byCause[cause(d)].add d

proc visible(s: string): string =
  ## The source with its odd characters made visible.
  s.multiReplace((" ", "⟨NBSP⟩"), (" ", "⟨LS⟩"), ("﻿", "⟨BOM⟩"), ("​", "⟨ZWSP⟩"),
                 ("　", "⟨IDEOGRAPHIC SPACE⟩"))

proc example(c: string, lines = 6): string =
  let src = byCause[c][0]["source"].getStr
  var shown = src.strip.splitLines
  # the line with the odd character, and a few around it
  var at = 0
  for i, l in shown:
    if l.anyIt(ord(it) >= 0x80): at = i
  let lo = max(0, at - lines div 2)
  "```mermaid\n" & visible(shown[lo .. min(shown.high, lo + lines - 1)].join("\n")) & "\n```"

doAssert byCause["other"].len == 0, "a difference this post does not explain: " & $byCause["other"]

nbText: fmt"""
The lexers held. Not one difference comes from cutting text into tokens: every type, every
family, read the odd character as Pele does. The {mutatedDifferent} differences come from code
further along, and they fall into five groups.

### Hosts with a character outside ASCII ({byCause["host"].len} cases)

A link's address goes through `new URL()` in Pele. For a host like `www.gΩithub.com`, the URL
standard turns the host into its ASCII form ([IDNA](https://url.spec.whatwg.org/#idna)):
lower case, mapped (`𝐀` becomes `a`), then Punycode, `xn--...`. nimaki's URL reader says in its
header that it keeps internationalized domain names as they are written, so the `href` differs.
One of them, with a mathematical bold `𝐀` slipped in (Pele's host becomes `www.githaub.com`):

{example("host")}

### Links Pele drops ({byCause["dropped"].len} cases)

The same mapping refuses some characters: a no-break space, an ideographic space or a line
separator in a host makes `new URL()` throw, and Pele draws the shape with no link. nimaki keeps
the link:

{example("dropped")}

### Indentation counted in bytes ({byCause["yaml"].len} case)

A flowchart node's `@{{ ... }}` metadata is YAML, and YAML's structure is indentation. Pele
measures the indentation of a line as `line.length - line.trimStart().length`, in UTF-16 units.
`util/yaml.nim` ports it as `line.len - jsTrimStart(line).len`, in **bytes**. For spaces the two
agree. A no-break space is one unit and two bytes:

{example("yaml")}
"""

nbCode:
  let line = "      \u00a0  other: \"clock\""   # six spaces, a no-break space, two spaces
  echo "JavaScript counts ", utf16Len(line) - utf16Len(jsTrimStart(line)), " units of indentation; ",
    "the port counts ", line.len - jsTrimStart(line).len, " bytes"

nbText: fmt"""
So Pele finds the line less indented than the block above it and stops with an error, and nimaki
reads it as part of the block. The fix is one line, `utf16Len` on both sides, as the porting
guide asks wherever a length shows.

### A class member two pixels taller ({byCause["size"].len} cases)

A line separator inside a class member's text (`draw⟨LS⟩()`) makes nimaki's class box two pixels
taller, or a few pixels narrower, than Pele's:

{example("size")}

Why, I have not traced yet: the measurer, the label splitter and the member parser all see that
character. It is the one cause still open.

### A date that should not parse ({byCause["date"].len} cases)

In a gantt chart, `2024-10-⟨LS⟩01` is not a date for Pele (`Invalid date`), and nimaki draws the
task. Gantt's dates go through a port of V8's date parser (`jsdate.nim`), which counts a line
separator as white space; where Pele's path refuses it first, I have not traced yet.

{example("date")}
"""

nbNote fmt"""
Seven seeds of {thousands(perRun)} cases each, nine characters, one per copy. That is a sample:
places where a character matters only in a rare context (inside a `click` callback, a
multi-line string) may need more seeds or a generator that aims at them. What it shows is that
nothing in the three families of lexer differs on these characters, at any of the places the
seeds reached, and that the differences live in four modules: the URL reader, the YAML reader,
class members, and dates.
""", nkDone, "What was checked"

nbText: fmt"""
## Two things the referee itself needed

- **The oracle stopped on bad front matter.** `tools/oracle.mjs` names the diagram type of each
  error, and when Pele's error carries none, it asks `detectType`, which throws again on front
  matter that is not YAML. The second throw ended the Node process, and every case after it in
  the batch was lost. The difftest corpus has no such case, so it never showed; the first run of
  `mutate` did. The oracle now catches it.
- **Half a character.** V8's `JSON.parse` error quotes the token it stopped at by its first
  UTF-16 unit, so for `𝐀` the message holds half a character, a lone surrogate. nimaki already
  writes the same half (its bytes, as WTF-8 does), but Nim's JSON reader refuses the oracle's
  `\uD835`. `mutate` reads it as those same bytes, and the two messages compare equal.

## What this changes for the port

- A new step on the [roadmap](../../roadmap/), `reading-fixes`: the YAML indentation (one line),
  links with characters outside ASCII in their host (IDNA, or an entry in the divergences), the
  class member with a line separator, and the gantt date. Each has its case in this post's data
  folder (`mutate-N.json`, under `differences`).
- `tools/mutate.nim` joins the referee. It fails while any difference stands, so it is not in CI
  yet; once `reading-fixes` is done, it can run there beside difftest and the fuzzers.
- `tools/census.nim` now also sorts the types into their families of lexer and counts their start
  conditions.
- Next articles: the layered layout file by file; the referee and fuzzers as code; the JavaScript
  layer in depth.

## Sources

- nimaki at commit [`{shortCommit}`](https://github.com/pietroppeter/nimaki/tree/{commit}):
  [`diagrams/common/tokens.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/diagrams/common/tokens.nim),
  [`diagrams/pie/parser.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/diagrams/pie/parser.nim),
  [`diagrams/journey/lexer.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/diagrams/journey/lexer.nim),
  [`diagrams/flowchart/lexer.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/diagrams/flowchart/lexer.nim),
  [`diagrams/common/outline.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/diagrams/common/outline.nim),
  [`util/yaml.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/util/yaml.nim),
  [`util/url.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/util/url.nim);
  the data of this post, [`how_nimaki_reads_text/`](https://github.com/pietroppeter/nimaki/tree/main/docs/devlog/data/how_nimaki_reads_text),
  made by [`tools/mutate.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/mutate.nim) and
  [`tools/census.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/census.nim).
- Pele at the pin: [`src/diagrams/common/tokens.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/tokens.ts),
  [`src/util/yaml.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/util/yaml.ts),
  [`src/util/url.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/util/url.ts).
- The tools Mermaid's grammars are written for: [Jison](https://github.com/zaach/jison) (its
  lexer's start conditions follow flex's), [Langium](https://langium.org/), and [Chevrotain](https://chevrotain.io/docs/), whose lexer
  Langium uses (its `LONGER_ALT`).
- The URL standard's [host parsing and IDNA](https://url.spec.whatwg.org/#host-parsing), and
  [UTS #46](https://www.unicode.org/reports/tr46/), the mapping that turns `𝐀` into `a`.
"""

nbSave
