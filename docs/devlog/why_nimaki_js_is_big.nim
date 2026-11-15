## devlog: 15 Nov 2026 Q | Why nimaki.js is big | nimaki's JavaScript build weighs about ten megabytes, five times Pele's bundle even compressed. What -d:danger does (the pages used it already), what fills the file, why Nim writes JavaScript this way, what other Nim projects do about it, and the plan to make it small.
## kind: research
import std/[json, os, osproc, strformat, strutils, tables, algorithm, math]
import nimib
import tabelline, tabelline/nimib
import ../blocks

nbInit
nb.usePost()

# ---------------------------------------------------------------------------------------------
# The data: tools/jssize.nim built nimaki.js in each mode, minified it and measured it.
const here = docsDir / "devlog" / "data" / "why_nimaki_js_is_big"
let
  sizes = parseFile(here / "sizes.json")
  files = sizes["files"].getElems
  pele = sizes["peleBundle"]
  anatomy = sizes["anatomy"]
  jsRuns = parseFile(docsDir / "data" / "js.json")["difftest"]

proc file(name: string): JsonNode =
  for f in files:
    if f["name"].getStr == name: return f
  raise newException(KeyError, name)
func mb(bytes: int): string = &"{bytes / 1_000_000:.1f} MB"
func kb(bytes: int): string = $int(round(bytes / 1000)) & " KB"
func size(bytes: int): string = (if bytes >= 1_000_000: mb(bytes) else: kb(bytes))
func pct(part, whole: int): string = $int(round(100 * part / whole)) & "%"
func times(a, b: int): string = &"{a / b:.1f}"

let
  debug = file("debug")
  release = file("release")
  danger = file("danger")
  minified = file("danger, minified")
  wrapped = file("danger, in a function, minified")
  total = anatomy["total"].getInt
  what = anatomy["what"]
  areas = anatomy["areas"]
  forum = parseFile(here / "nimforum.json")
  forumJs = forum["raw"].getInt
  forumJsGzip = forum["gzip"].getInt
  identical = jsRuns["identical"].getInt + jsRuns["diagrammari"]["identical"].getInt
  cases = jsRuns["cases"].getInt + jsRuns["diagrammari"]["cases"].getInt

nbText: &"""
## The findings, first

- **nimaki.js, the file a page loads to draw diagrams, is {mb(danger["raw"].getInt)}**, and
  {kb(danger["gzip"].getInt)} once compressed the way a web server sends it (gzip). Pele's bundle,
  which draws the same diagrams, is {kb(pele["raw"].getInt)}, and {kb(pele["gzip"].getInt)}
  compressed: nimaki's is {times(danger["gzip"].getInt, pele["gzip"].getInt)} times larger.
- **-d:danger was already on.** The pages have always built nimaki.js with it. It takes the file
  from {mb(release["raw"].getInt)} (-d:release) to {mb(danger["raw"].getInt)}: about a tenth.
- **But the referee did not check that file.** The tools that compare nimaki's JavaScript build
  with Pele built it with -d:release. They now build it as the pages do, and on that build
  {identical} of {cases} drawings are still identical to Pele's.
- **The file is mostly long names and white space.** A third of it is names that Nim makes up
  (a function `greet` becomes `greet__greet_u4`), an eighth is indentation; strings are written as lists
  of numbers, and every object type carries a description of itself.
- **A minifier shortens all of that.** Pele's own minifier, esbuild, takes nimaki.js to
  {mb(wrapped["raw"].getInt)} ({kb(wrapped["gzip"].getInt)} compressed), once the file is wrapped
  in a function so that its names can be shortened too.
- **Other Nim projects ship small programs**, and either do not minify at all (Nim's own
  documentation search) or minify with Google's Closure Compiler (the Nim forum). None that we
  found ships anything of nimaki's size: nimaki is a port of some 50,000 lines of TypeScript.
- **The plan**, for the next pull request: write nothing that the browser already knows how to
  do (its own URL parser replaces 0.7 MB of tables), minify as Pele does, and, as Pele does, give a
  page one file per diagram type, so that a page of flowcharts loads the flowchart and not the
  other 32 types.
"""

nbText: """
## The sizes

Each line is the same program, `src/nimaki/web.nim`, compiled with `nim js`: first in each of
Nim's three modes, then minified. *gzip* and *brotli* are the two ways a web server compresses a
file before it sends it; the browser unpacks it. They are what a phone actually downloads.
"""

block:
  type Row = object
    build, flags, raw, gzip, brotli: string
  var rows: seq[Row]
  for f in files:
    rows.add Row(build: f["name"].getStr, flags: f["flags"].getStr, raw: size(f["raw"].getInt),
                 gzip: size(f["gzip"].getInt), brotli: size(f["brotli"].getInt))
  rows.add Row(build: "Pele's bundle", flags: "pele.global.js, " & sizes["pele"].getStr,
               raw: size(pele["raw"].getInt), gzip: size(pele["gzip"].getInt),
               brotli: size(pele["brotli"].getInt))
  let t = tabella(rows, rownameCol = "build"):
    tabHeader "nimaki.js, every way", &"""{sizes["nim"].getStr}; esbuild {sizes["esbuild"].getStr}"""
    optCssTheme()
  nbTable t

nbText: &"""
Two things this table does not show. Nim's `--opt:size` and `--opt:speed`, which matter for the C
build, change nothing in JavaScript: the file comes out byte for byte the same. And turning off
the stack traces (`--stacktrace:off`, `--linetrace:off`) changes nothing either, because
-d:danger turns them off already.

## What -d:danger does

Nim compiles a program in one of three modes:

| Mode | What it is for | What it keeps |
|---|---|---|
| default (debug) | writing the program | every check, and a stack trace that says where an error happened |
| `-d:release` | the program you give to people | every check, with the optimizer on |
| `-d:danger` | the fastest program | no checks at all |

A *check* is a small test that Nim adds to the program where something could go wrong: is this
index inside the list (`a[i]` with `i` too large)? Did this sum of integers overflow? Is this
value inside its range? Is this reference nil? Is this `assert` true? With the checks, a bug
stops the program with an error that names it. Without them, the program carries on with a wrong
value. In JavaScript the wrong value is often `undefined`, which then turns up somewhere else.

Each check is a few lines of JavaScript, written again at every place it is needed, so turning
them off shrinks the file: from {mb(release["raw"].getInt)} to {mb(danger["raw"].getInt)} here,
and from 263 KB to under 1 KB for a small program
[in a thread of the Nim forum](https://forum.nim-lang.org/t/7282#46128) (most of the 263 KB was the
code of the checks and of the error messages they print).

### Is it good practice?

Nim's own guide calls it a *dangerous release build*: the `danger` symbol "turns off all runtime
checks and turns on the optimizer" ([Nim Compiler User Guide](https://nim-lang.org/docs/nimc.html)).
The Nim community is of two minds about it, and both minds have a point:

- **Against:** safety is one of Nim's main features, so a program run without its checks is not
  the program people actually use: "Benchmarking with key feature disabled would be wrong"
  ([alexeypetrushin, 2021](https://forum.nim-lang.org/t/8074#51682)).
- **For:** when Nim is compared with a language that has no such checks (JavaScript, TypeScript),
  -d:danger is the fair comparison; "nim gives you the levers to tune for safety/performance, no
  reason not to leverage this" ([timothee, 2021](https://forum.nim-lang.org/t/8074#51718)). For
  the JavaScript backend in particular, the forum's standing advice to someone who finds the file
  large is to compile with -d:danger ([t/9725](https://forum.nim-lang.org/t/9725#63995),
  [t/9725](https://forum.nim-lang.org/t/9725#63998)), and the Nim wiki page for TypeScript
  programmers names both flags for a production build
  ([Nim for TypeScript Programmers](https://github.com/nim-lang/Nim/wiki/Nim-for-TypeScript-Programmers)).

The way to read it: -d:danger is a good choice for a program whose behaviour is checked some
other way, and a poor one for a program that relies on its checks to find its bugs. nimaki is
the first kind. Every drawing it makes is compared, byte for byte, with Pele's: the corpus, the
fuzzers that make up new diagrams, Pele's own test suites. A check that would have fired shows up
there as a drawing that differs. Nothing in nimaki catches a check's error on purpose: its own
errors (a diagram Pele refuses) are written by hand and stay in every mode.
"""

nbNote &"""
Until today the referee checked the -d:release build and the pages shipped the -d:danger one.
`tools/answers.nim` (difftest and the fuzzers in JavaScript) and `tools/peletests.nim` (Pele's own
tests) now compile with -d:danger too. difftest on that build: {identical} of {cases} drawings
identical to Pele's. The C build is not affected: it stays a debug build for the referee and a
-d:release build for the fuzzers, where the checks earn their keep.
""", nkDone, "Checked"

nbText: """
## What fills the file

To see what Nim writes, here is a small program: a function that greets, an object with two
numbers, and a function that hands back a moved copy of it.
"""

let greetSource = readFile(here / "greet.nim")
nbText: "```nim\n" & greetSource & "```"

nbText: """
The page compiles it with `nim js -d:danger` as it is built, runs it in Node, and shows what
came out:
"""

nbCode:
  let outDir = repoDir / "build" / "why_nimaki_js_is_big"
  createDir outDir
  let js = outDir / "greet.js"
  let (log, code) = execCmdEx("nim js --hints:off --warnings:off -d:danger -o:" & quoteShell(js) &
                              " " & quoteShell(here / "greet.nim"))
  doAssert code == 0, log
  let program = readFile(js)
  echo "greet.js: ", program.len, " bytes, ", program.countLines, " lines"
  echo "it prints: ", execProcess("node " & quoteShell(js)).strip

proc functionOf(js, name: string): string =
  ## The text of one top-level function of a JavaScript file Nim wrote.
  let a = js.find("function " & name)
  let b = js.find("\n}\n", a)
  js[a .. b + 2]

let greetJs = readFile(repoDir / "build" / "why_nimaki_js_is_big" / "greet.js")
var greetName, movedName = ""
for line in greetJs.splitLines:
  if line.startsWith("function greet__"): greetName = line[9 ..< line.find('(')]
  if line.startsWith("function moved__"): movedName = line[9 ..< line.find('(')]

nbText: "Here is `greet` as Nim wrote it:\n\n```js\n" & functionOf(greetJs, greetName) & "```"

nbText: """
Five things make it longer than a person would write it, `function greet(name) { return "Hello, " + name + "!" }`:

1. **Indentation and empty lines**, which the browser does not need.
2. **Long names.** Nim gives each function its module and a number (`greet__greet_u4`) and each
   variable a number too (`result_` and ten digits), so that two things of the same name never clash
   in the one file it writes.
3. **Strings as lists of numbers.** A Nim string is a list of bytes, so `"Hello, "` becomes
   `[72,101,108,108,111,44,32]`, which is longer, and which a minifier cannot shorten.
4. **Copies.** In Nim, `let b = a` makes a copy of an object or a string; in JavaScript it only
   gives the same object a second name. To keep Nim's meaning, the generated code calls `nimCopy`
   where a value is handed over, and `nimCopy` needs to know the shape of what it copies.
5. **Type information.** That shape is a small object written at the top of the file, one for
   each type the program uses (`NTI` and a number, `= {size: 0, kind: 18, ...}`), whether or not anything
   is ever copied.

Here is `moved`, where the copy happens (`result = p` in Nim):
"""

nbText: "```js\n" & functionOf(greetJs, movedName) & "```"

nbText: &"""
The program is {kb(greetJs.len)} because the file also holds the parts of Nim's library that it
uses: turning a number into text, joining strings, `echo`. That part is paid once, and in nimaki it
is small. The five things above are paid at every line, and nimaki has many lines.

### In nimaki.js

`tools/jssize.nim` reads the -d:danger nimaki.js line by line and adds up each kind of text.
These overlap (an indented line can hold a long name), so they do not add up to the whole:
"""

block:
  type Row = object
    what, bytes, share: string
  let names = {"indentation": "indentation", "names": "names Nim made up",
               "strings": "strings written as lists of numbers",
               "typeInfo": "type information", "tables": "number tables (Unicode, IDNA)"}.toOrderedTable
  var rows: seq[Row]
  for k, label in names:
    rows.add Row(what: label, bytes: size(what[k].getInt), share: pct(what[k].getInt, total))
  let t = tabella(rows, rownameCol = "what"):
    tabHeader "What fills nimaki.js", &"of {mb(total)}, -d:danger, before minifying"
    optCssTheme()
  nbTable t

nbText: """
And by where the code comes from (these do add up to the whole):
"""

block:
  type Row = object
    part, bytes, share: string
  var rows: seq[Row]
  var pairs: seq[(string, int)]
  for k, v in areas: pairs.add (k, v.getInt)
  pairs.sort(proc (a, b: (string, int)): int = cmp(b[1], a[1]))
  for (k, v) in pairs: rows.add Row(part: k, bytes: size(v), share: pct(v, total))
  let t = tabella(rows, rownameCol = "part"):
    tabHeader "Where nimaki.js comes from", "the 33 diagram types, the shared core (layout, SVG, text), the models of `parse`..."
    optCssTheme()
  nbTable t

nbText: &"""
Two parts stand out.

- **Number tables.** The top-level code holds tables of Unicode, for one job: writing a web
  address whose host is not in plain ASCII (`exampleΩ.com`) the way the browser writes it
  (`xn--example-...`). Pele asks the browser (`new URL()`); the port carries a copy of the rules
  (IDNA, from the URL parser of Node), because the C build has no browser to ask. The JavaScript
  build does have one.
- **The models of `parse`.** `nimaki.parse` hands a page the model of a diagram, in the shape of
  Pele's. The code that writes it is generic: Nim writes a separate copy of it for every type it
  meets, and the models have many types. It is {kb(anatomy["modules"]["modeljson"].getInt)}, the
  largest single module.
"""

nbFold "The 40 largest modules":
  type Row = object
    module, bytes: string
  var rows: seq[Row]
  for k, v in anatomy["modules"]:
    rows.add Row(module: k, bytes: kb(v.getInt))
  let t = tabella(rows, rownameCol = "module"):
    tabHeader "Code by module", "the top-level functions of each module of nimaki.js, -d:danger, before minifying"
    optCssTheme()
  nbTable t

nbText: &"""
## Why Nim writes JavaScript this way

None of this is an accident. The forum has gone over it many times, and the answers agree:

- The checks are there because JavaScript has almost none: it "hides errors behind `undefined`
  and `NaN`", and Nim's types (ranges, overflow) need checks to mean what they mean
  ([t/9725](https://forum.nim-lang.org/t/9725#63995)).
- The copies and the type information keep Nim's value semantics: in Nim, assigning an object
  copies it ([the same reply](https://forum.nim-lang.org/t/9725#63995); and in
  [issue 20190](https://github.com/nim-lang/Nim/issues/20190), the type information is "kept for
  copying, to emulate Nim value type semantics"). nimaki met the cost of these copies before, in
  speed rather than size ([Copies on the way out](../copies-on-the-way-out/)).
- The redundancy costs little once the file is minified and compressed, and sometimes it even
  makes the code faster: the same reply notes that Nim's output "shrinks down by **a lot** if you
  minify it or gzip it". One contributor
  measured a 400 KB game script that became 166 KB minified and 20 KB gzipped: "Nim doesn't do
  much wrong other than add redundancy" ([issue 20190](https://github.com/nim-lang/Nim/issues/20190)).
- Nim does not minify by itself; "you can use any other minifier software to do that kind of
  post-processing of JavaScript"
  ([Nim for TypeScript Programmers](https://github.com/nim-lang/Nim/wiki/Nim-for-TypeScript-Programmers)).
- Nim does drop the code a program never calls ("only the used symbols get compiled", the same
  page). nimaki's problem is that a page calls everything: one file holds every diagram type, and
  the page might draw any of them.

Araq, Nim's author, has a view of his own on the whole question: "As long as the size is
reasonable (for the initial download), say under 1MB, 'Size of the produced JS file' is a
meaningless number" ([t/7282](https://forum.nim-lang.org/t/7282#46130)), and later, "focus on
your application instead. Features, usability, etc." ([t/9148](https://forum.nim-lang.org/t/9148#59898)).
Others answered him that the size matters on a slow phone connection
([xigoi](https://forum.nim-lang.org/t/7282#46142)) and when the script blocks the page
([alexeypetrushin](https://forum.nim-lang.org/t/7282#46145)). He also holds that Nim's output
suits a minifier well, "because we don't use dynamic field lookups"
([t/9148](https://forum.nim-lang.org/t/9148#62591)); one user found that a minifier that also
renames the *fields* of objects broke the code ([xigoi](https://forum.nim-lang.org/t/9148#62599)),
which is why the minifier below leaves fields alone. nimaki.js is past Araq's one megabyte even
compressed, so by either view it is too big.

Two more tips from those threads, for completeness: `--opt:size` "doesn't affect the JS backend at
all" ([Yardanico](https://forum.nim-lang.org/t/9148#59876), as measured above), and "if you use
ref everywhere (which makes sense for JS), Nim will not emit a bunch of deep copy helpers"
([summarity on Hacker News, 2025](https://news.ycombinator.com/item?id=45097227)). The second would
mean rewriting nimaki's objects, against the porting guide's choice of Nim's plain objects, so it
is noted and not taken.

## What other Nim projects do

We looked for Nim projects that ship JavaScript to browsers and checked how they build it.

| Project | How its JavaScript is built | Size |
|---|---|---|
| Nim's documentation search (`dochack.js`) | `nim js -d:release`, not minified ([nimpaths.nim](https://github.com/nim-lang/Nim/blob/devel/compiler/nimpaths.nim)) | 55 KB, in Nim 2.2.4's own docs |
| The Nim forum ([nimforum](https://github.com/nim-lang/nimforum)) | `nim js -d:release`; the repository has a `minify` task with Google's Closure Compiler ([nimforum.nimble](https://github.com/nim-lang/nimforum/blob/master/nimforum.nimble)), but the forum does not use it | `forum.js`, as served on 15 November 2026: {kb(forumJs)}, not minified, compiled with Nim 2.0.8; {kb(forumJsGzip)} gzipped |
| Stardust, a game by dom96 | Closure Compiler ([dom96, 2022](https://forum.nim-lang.org/t/9148#59902)) | 1.32 MB, by his count then |
| HappyX, a web framework | its command line tool minifies, "from 600+ Kb to 50-60 Kb" by its author's count ([t/10219](https://forum.nim-lang.org/t/10219#67838)); not checked here | |
| [closure_compiler](https://github.com/yglukhov/closure_compiler), a Nim wrapper | for Closure's strongest mode, which "is incompatible" with Nim's output until it is given a list of the names to keep | |
| Pele, for comparison | esbuild, minified, one file for every type and also one file per type that a page loads when it needs it (`scripts/build.mjs` in Pele) | {kb(pele["raw"].getInt)} |

So Pietro's fear about the forum was right: the forum ships its JavaScript as Nim writes it. Its
repository has a minify step, but the file the forum serves is not minified (its first line is
still Nim's `/* Generated by the Nim Compiler v2.0.8 */`). When the forum was discussed on Hacker
News in 2021, its author said the JavaScript "could definitely use a lot of minification", and
that when he built the forum "optimising the code size didn't make the cut"
([dom96](https://news.ycombinator.com/item?id=28330921),
[dom96](https://news.ycombinator.com/item?id=28333647)). A web server compresses the file when it
sends it, which hides much of the difference. What the search did not find is a Nim project that
ships a library of nimaki's size to browsers: the Nim programs that run in browsers are apps,
where the sizes people argue about are tens or hundreds of kilobytes.
"""

nbNote """
Pietro opened the sandbox to Hacker News, dev.to and the forum's search after this post was first
written, and the sources above were then read. Two remain unread: two blog posts about porting to
JavaScript with Nim (ronynn.github.io) are no longer online. A dev.to post on JavaScript targets in
Nim ([medy, 2023](https://dev.to/dumblepytech1/techniques-for-developing-javascript-targets-in-nim-27nj))
is about wrapping React-like code, and says nothing about size. The forum threads were read through
a Markdown reader of Pietro's (tomd), one thread at a time.
""", nkWarning, "Sources"

nbText: &"""
## What this changes for the port

The research points at three things, each measured on a quick prototype:

1. **Ask the browser.** In the JavaScript build, `new URL()` does what the port's IDNA code does,
   as it does for Pele; the C build keeps its own. The prototype is 0.7 MB smaller, and
   every drawing is still identical to Pele's.
2. **Minify as Pele does**, with the same esbuild, after wrapping the file in a function. Prototype:
   {mb(wrapped["raw"].getInt)} raw, {kb(wrapped["gzip"].getInt)} compressed, before the other two.
3. **One file per diagram type**, as Pele's lazy loading has. A prototype with only the flowchart
   (the shared core and one type) is 0.67 MB minified and 162 KB compressed; with only the pie
   chart, 78 KB compressed. Pele's whole bundle is {kb(pele["gzip"].getInt)} compressed.

For diagrammari this third one matters most. Its client mode puts Pele's whole bundle into each
page and calls `pele.mount` (`src/mari/render_html.nim` in diagrammari), and it knows the type of
each diagram when it builds the page: it could put in only the types the page draws. That is a
proposal for diagrammari, not a change to it.

The next pull request does the three, measures each step with `tools/jssize.nim`, and writes the
sizes that diagrammari's client mode would load.

## Sources

- The sizes: `nim r tools/jssize.nim`, run on 15 November 2026, written to
  `docs/devlog/data/why_nimaki_js_is_big/sizes.json`.
- [Nim Compiler User Guide](https://nim-lang.org/docs/nimc.html): the release and danger symbols.
- The Nim forum's `forum.js`, fetched from forum.nim-lang.org on 15 November 2026 and measured as
  above (`docs/devlog/data/why_nimaki_js_is_big/nimforum.json`).
- Nim forum: [Hello Javascript!](https://forum.nim-lang.org/t/9148) (2022),
  [Best Web Framework Features?](https://forum.nim-lang.org/t/10219) (2023).
- Hacker News: [Nimforum: Lightweight alternative to Discourse written in Nim](https://news.ycombinator.com/item?id=28329672)
  (2021), [A review of Nim 2](https://news.ycombinator.com/item?id=45057734) (2025).
- Nim forum: [JS compiler produces a large file (with -d:release)?](https://forum.nim-lang.org/t/9725)
  (December 2022), [Client-side JS with Nim](https://forum.nim-lang.org/t/7282) (December 2020),
  [Nim JSON parsing is 30 times slower than Node.JS](https://forum.nim-lang.org/t/8074) (June 2021).
- [Js output bloat, nim-lang/Nim issue 20190](https://github.com/nim-lang/Nim/issues/20190)
  (August 2022, closed).
- [Nim for TypeScript Programmers](https://github.com/nim-lang/Nim/wiki/Nim-for-TypeScript-Programmers),
  Nim wiki: build modes and minification.
- [nimforum.nimble](https://github.com/nim-lang/nimforum/blob/master/nimforum.nimble): the
  frontend and minify tasks. Nim's `compiler/nimpaths.nim`: how `dochack.js` is built.
- [closure_compiler](https://github.com/yglukhov/closure_compiler): Nim's output and Closure's
  advanced mode.
- Pele 1.13.0's `scripts/build.mjs` and `scripts/browser-build.mjs`: esbuild, minified, and the
  lazy chunks; its `package-lock.json` pins esbuild {sizes["esbuild"].getStr}.
- diagrammari's `src/mari/render_html.nim` at the pinned commit (`reference/DIAGRAMMARI`): client mode.
"""

nbSave
