## nimaki's side of the referee: its answer on a case, from the build compiled to C (in the tool's
## own process) or from the build compiled to JavaScript (tools/jsrunner.nim, run in Node). Used
## by tools/difftest.nim and tools/fuzz.nim, and by jsrunner itself.
##
## A case is the oracle's input: `{"id", "source", "options"}`, with the options Pele's render
## takes (now, fontSize, padding, maxWidth, idPrefix...).
import std/[json, options, strutils]
import nimaki/js
import verdict
import nimaki

when not defined(js):
  import std/[os, osproc, tables]
  import common

# A host's icons and typesetter, made up, the same as tools/oracle.mjs's.
proc testIcons(name: string): string =
  if "none" in name: "" else: "<path d=\"M0 0L" & $utf16Len(name) & " 24\"/>"

proc testMath(tex: string, size: float): MathMarkup =
  if "bad" in tex: return nil
  let n = utf16Len(tex)
  let width = float(n) * size * 0.55
  let height = size * (if "frac" in tex: 2.25 else: 1.2)
  if "nan" in tex: return MathMarkup(isSvg: true, markup: "<g/>", width: NaN, height: height)
  if "html" in tex: return MathMarkup(isSvg: false, markup: "<span class=\"m\">" & $n & "</span>", width: width, height: height)
  MathMarkup(isSvg: true, markup: "<svg viewBox=\"0 0 " & $n & " 1\"><rect width=\"" & $n & "\" height=\"1\"/></svg>",
             width: width, height: height)

proc toOptions*(j: JsonNode): RenderOptions =
  ## Pele's render options, as JSON, for nimaki's render.
  if j.isNil: return
  if j.hasKey("fontSize"): result.fontSize = some(j["fontSize"].getFloat)
  if j.hasKey("padding"): result.padding = some(j["padding"].getFloat)
  if j.hasKey("maxWidth"): result.maxWidth = some(j["maxWidth"].getFloat)
  if j.hasKey("idPrefix"): result.idPrefix = some(j["idPrefix"].getStr)
  if j.hasKey("responsive"): result.responsive = some(j["responsive"].getBool)
  if j.hasKey("fontFamily"): result.fontFamily = j["fontFamily"].getStr
  if j.hasKey("autoDirection"): result.autoDirection = some(j["autoDirection"].getBool)
  if j.hasKey("directionBreakpoint"): result.directionBreakpoint = some(j["directionBreakpoint"].getFloat)
  if j.hasKey("monospace"):
    for m in j["monospace"]: result.monospace.add m.getStr
  if j.hasKey("now"): result.now = some(j["now"].getFloat)
  if j{"icons"}.getStr == "test": result.icons = testIcons
  if j{"math"}.getStr == "test": result.math = testMath

proc nimakiAnswer*(source: string, options: JsonNode): Answer =
  ## nimaki's answer, in this process: an SVG, or the code and message of its error.
  try:
    let r = render(source, toOptions(options))
    Answer(ok: true, svg: r.svg)
  except PeleError as e:
    Answer(ok: false, code: e.code, message: e.msg)
  except CatchableError as e:
    Answer(ok: false, code: "internal", message: e.msg)

proc toAnswer*(j: JsonNode): Answer =
  ## An answer in the oracle's JSON (`ok`, then `svg` or `code` and `message`).
  if j["ok"].getBool: Answer(ok: true, svg: j["svg"].getStr)
  else: Answer(ok: false, code: j["code"].getStr, message: j["message"].getStr)

proc toJson*(id: string, a: Answer): JsonNode =
  if a.ok: %*{"id": id, "ok": true, "svg": a.svg}
  else: %*{"id": id, "ok": false, "code": a.code, "message": a.message}

when not defined(js):
  proc jsAnswers*(cases: seq[JsonNode], name: string): Table[string, Answer] =
    ## nimaki's answers from its JavaScript build: tools/jsrunner.nim compiled with nim js, run in
    ## Node with TZ=UTC as the oracle is. `name` names the files under build/js/.
    let dir = buildDir / "js"
    createDir dir
    let runner = dir / "jsrunner.js"
    let compile = "nim js --hints:off --warnings:off -d:nodejs -d:release -o:" & quoteShell(runner) & " " &
                  quoteShell(repoDir / "tools" / "jsrunner.nim")
    if execShellCmd(compile) != 0: quit "ERROR nim js failed: " & compile, 2
    var input = ""
    for c in cases: input.add $c & "\n"
    let inPath = dir / (name & "-in.jsonl")
    let outPath = dir / (name & "-out.jsonl")
    writeFile inPath, input
    let run = "TZ=UTC node " & quoteShell(runner) & " " & quoteShell(inPath) & " " & quoteShell(outPath)
    if execShellCmd(run) != 0: quit "ERROR the JavaScript build failed: " & run, 2
    for line in lines(outPath):
      if line.len > 0:
        let j = parseJson(line)
        result[j["id"].getStr] = toAnswer(j)

  proc updateJsData*(section, key: string, value: JsonNode) =
    ## Records a run of the JavaScript build in docs/data/js.json, which the pages read:
    ## `difftest` (the whole corpus), `fuzz` (by type), and `bytes`, the size of the build.
    let path = dataDir / "js.json"
    var data = if fileExists(path): parseFile(path)
               else: %*{"about": "Written by tools/difftest.nim --js and tools/fuzz.nim --js: the last runs of nimaki compiled to JavaScript. Do not edit by hand."}
    if key.len == 0: data[section] = value
    else:
      if not data.hasKey(section): data[section] = newJObject()
      data[section][key] = value
    let runner = buildDir / "js" / "jsrunner.js"
    if fileExists(runner): data["bytes"] = %getFileSize(runner)
    writeFile path, data.pretty & "\n"
