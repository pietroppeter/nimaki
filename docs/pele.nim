## Pele itself, at build time: `peleSvg(source)` runs the pinned npm package in Node (through
## tools/oracle.mjs, as the referee does) and gives the SVG, so a page can show a diagram drawn
## by Pele with `nbSvg peleSvg(text), caption`. Needs `node` and `reference/fetch.sh` (the
## setup does both). The same `now` and time zone as difftest.
import std/[os, osproc, json, strutils, strtabs]
import blocks

const fixedNow* = 1767225600000.0   ## 2026-01-01T00:00:00Z, as in tools/difftest.nim

proc peleRenders*(sources: openArray[string], options: JsonNode = nil): seq[JsonNode] =
  ## Pele's answers for several sources at once (one Node process): `{"ok", "type", "svg",
  ## "width", "height"}` or `{"ok": false, "code", "message"}`. `options` are Pele's render
  ## options, the same for every source.
  var input = ""
  for i, s in sources:
    let opts = if options == nil: newJObject() else: options.copy
    opts["now"] = %fixedNow
    input.add $(%*{"id": $i, "source": s, "options": opts}) & "\n"
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
