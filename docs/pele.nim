## Pele itself, at build time: `peleSvg(source)` runs the pinned npm package in Node (through
## tools/oracle.mjs, as the referee does) and gives the SVG, so a page can show a diagram drawn
## by Pele with `nbSvg peleSvg(text), caption`. Needs `node` and `reference/fetch.sh` (the
## setup does both). The same `now` and time zone as difftest.
##
## `nbMermaid(text, caption, options)` is the block a page draws with: nimaki draws the text, Pele
## draws it too, and the build fails when the two drawings are not the same bytes. So every
## diagram on the site is also a small test of the port.
import std/[os, osproc, json, strutils, strtabs, tables]
import nimib
import blocks
import nimaki
import ../tools/answers

const fixedNow* = 1767225600000.0   ## 2026-01-01T00:00:00Z, as in tools/difftest.nim

var answered: Table[(string, string), JsonNode]   ## Pele's answers, by source and options

proc ask(input: string): seq[JsonNode]

proc peleRenders*(sources: openArray[string], options: JsonNode = nil): seq[JsonNode] =
  ## Pele's answers for several sources at once (one Node process): `{"ok", "type", "svg",
  ## "width", "height"}` or `{"ok": false, "code", "message"}`. `options` are Pele's render
  ## options, the same for every source.
  var input = ""
  var asked: seq[int]   # the sources not asked before, in this run of the pages
  let opts = if options == nil: newJObject() else: options.copy
  opts["now"] = %fixedNow
  for i, s in sources:
    if (s, $opts) in answered: continue
    asked.add i
    input.add $(%*{"id": $i, "source": s, "options": opts}) & "\n"
  if asked.len > 0:
    for j in ask(input): answered[(sources[parseInt(j["id"].getStr)], $opts)] = j
  for s in sources: result.add answered[(s, $opts)]

proc ask(input: string): seq[JsonNode] =
  let (output, code) = execCmdEx("node " & quoteShell(repoDir / "tools" / "oracle.mjs"),
                                 env = newStringTable({"TZ": "UTC", "PATH": getEnv("PATH")}), input = input)
  doAssert code == 0, "peleSvg: the oracle failed (is Node installed, and reference/ fetched?):\n" & output
  for line in output.splitLines:
    if line.len > 0: result.add parseJson(line)

proc peleSvg*(source: string, options: JsonNode = nil): string =
  ## The SVG Pele draws for `source`; fails the build when Pele throws.
  let r = peleRenders([source], options)[0]
  doAssert r["ok"].getBool, "peleSvg: Pele throws " & r{"code"}.getStr & ": " & r{"message"}.getStr
  r["svg"].getStr

proc mermaidSvg*(text: string, options: JsonNode = nil): string =
  ## nimaki's drawing of `text`, checked against Pele's: the build fails when they differ.
  ## `options` are Pele's render options, as JSON (`%*{"maxWidth": 390}`); `now` is fixed.
  var o = toOptions(options)
  o.now = fixedNow
  let r = try: render(text, o)
          except CatchableError as e: raiseAssert "nbMermaid: nimaki cannot draw it: " & e.msg & "\n" & text
  let pele = peleRenders([text], options)[0]
  doAssert pele["ok"].getBool, "nbMermaid: Pele throws " & pele{"code"}.getStr & ": " & pele{"message"}.getStr
  let theirs = pele["svg"].getStr
  if r.svg != theirs:
    var at = 0
    while at < min(r.svg.len, theirs.len) and r.svg[at] == theirs[at]: inc at
    raiseAssert "nbMermaid: nimaki's drawing is not Pele's, from byte " & $at & ":\n  nimaki: " &
      r.svg[at ..< min(at + 80, r.svg.len)] & "\n  Pele:   " & theirs[at ..< min(at + 80, theirs.len)] &
      "\n" & text
  r.svg

template nbMermaid*(text: string, caption = "", options: JsonNode = nil) =
  ## A diagram drawn by nimaki from Mermaid text, checked against Pele (the same bytes, or the
  ## build fails), with its caption, and its text folded under it.
  let drawing = mermaidSvg(text, options)
  nbSvg drawing, caption
  nbFold "The Mermaid text of this diagram":
    nbText "```mermaid\n" & text.strip & "\n```\n"
