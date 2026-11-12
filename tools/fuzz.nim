## fuzz, the referee's second half: generates many inputs for a diagram type from a seeded
## grammar of the type, renders them with Pele (in Node, through tools/oracle.mjs) and with
## nimaki, and compares byte for byte, with the options the generator picks (font size,
## padding, maxWidth, config...). The corpus has few cases per type; this finds what it misses.
##
##   nim r tools/fuzz.nim pie                 1000 cases of pie, seed 1
##   nim r tools/fuzz.nim timeline            the same for timeline
##   nim r tools/fuzz.nim flowchart           and for flowchart
##   options:
##     --cases:N         how many cases (default 1000)
##     --seed:S          the seed of the generator (default 1)
##     --show:N          print at most N differences as ERROR lines (default 10)
##     --package:PATH    the oracle package (default reference/npm/package or $PELE_PACKAGE)
##
## The last run of each type is summed up in docs/data/fuzz.json, which the pages read. Each
## failing case is written whole to build/fuzz/<type>-<seed>.jsonl, so it can be replayed.
import std/[os, osproc, strutils, json, random, parseopt, options]
import common, verdict
import nimaki

type Gen = object
  rng: Rand

proc pick[T](g: var Gen, xs: openArray[T]): T = xs[g.rng.rand(xs.high)]
proc chance(g: var Gen, p: float): bool = g.rng.rand(1.0) < p

const labels = [
  "Dogs", "Cats", "Rats", "ash", "bat", "a b c", "Calcium", "__proto__", "constructor", "",
  "Ünïcödé", "日本語のラベル", "中文", "한국어", "emoji 🎉", "x&amp;y", "#35; hash", "a<b>bold</b>",
  "*em*", "fa:fa-car icon", "with \\\"quote\\\"", "tab\there", "very long label that goes on and on and on",
  "a\\nb", "&lt;tag&gt;", "#quot;q#quot;", "soft­hyphen", "zero​width", "（括弧）", "x",
  "Iron", "Magnesium", "percent %", "semi; colon", "a  b   c", "Ω≈ç√", "́combining",
]
const numbers = ["386", "85", "15", "0", "60", "40", "42.96", "50.05", "10.01", "5", "0.5",
                 "100", "1", "2", "3", "0.001", "99.99", "1000000", "33.333", "66.667", "12.5",
                 "0.1", "7", "250", "0.0", "0.004", "2.5", "17.5", "0.75"]
const badNumbers = ["1e3", "007", "1.", "-3", "1.2.3", "-0", "x"]
const colors = ["#ff0000", "red", "rgb(10, 20, 30)", "hsl(120 50% 50%)", "#abc", "var(--pele-x)",
                "url(x)", "notacolor", "transparent", "rgba(0,0,0,0.3)", "#12345678", "black",
                "white", "hsl(200deg, 40%, 20%)", "color-mix(in srgb, red, blue)", "lightgray"]

proc section(g: var Gen): string =
  let q = if g.chance(0.9): "\"" else: "'"
  result = q & g.pick(labels) & q & (if g.chance(0.5): " " else: "") & ":" &
    (if g.chance(0.7): " " else: (if g.chance(0.5): "  " else: "")) &
    (if g.chance(0.04): g.pick(badNumbers) else: g.pick(numbers))
  if g.chance(0.05): result.add " %% trailing"
  if g.chance(0.03): result.add " junk"

proc frontMatter(g: var Gen): string =
  var lines = @["---"]
  if g.chance(0.3): lines.add "title: " & g.pick(labels)
  lines.add "config:"
  lines.add "  pie:"
  if g.chance(0.6): lines.add "    textPosition: " & g.pick(["0.5", "0.9", "0", "1", "1.5", "-1", "abc", "0.75"])
  if g.chance(0.5): lines.add "    donutHole: " & g.pick(["0.2", "0.5", "0.9", "0.95", "0", "x"])
  if g.chance(0.5): lines.add "    legendPosition: " & g.pick(["left", "right", "top", "bottom", "center", "none", "~"])
  if g.chance(0.5):
    lines.add "  themeVariables:"
    for i in 1 .. g.rng.rand(1 .. 10):
      lines.add "    pie" & $i & ": \"" & g.pick(colors) & "\""
  if g.chance(0.2): lines.add "  pie:\n    useMaxWidth: false"
  lines.add "---"
  lines.join("\n") & "\n"

proc pieSource(g: var Gen): string =
  if g.chance(0.3): result.add frontMatter(g)
  if g.chance(0.1): result.add "%%{init: {\"pie\": {\"textPosition\": 0.6}, \"themeVariables\": {\"pie1\": \"" & g.pick(colors) & "\"}}}%%\n"
  if g.chance(0.05): result.add "  \n"
  result.add "pie"
  if g.chance(0.4): result.add " showData"
  if g.chance(0.4): result.add " title " & g.pick(labels)
  result.add "\n"
  let n = g.rng.rand(0 .. 12)
  for i in 0 ..< n:
    let indent = g.pick(["", "  ", "    ", "\t"])
    let r = g.rng.rand(1.0)
    if r < 0.75: result.add indent & section(g)
    elif r < 0.8: result.add indent & "%% a comment " & g.pick(labels)
    elif r < 0.84: result.add indent & "title " & g.pick(labels)
    elif r < 0.87: result.add indent & "accTitle: " & g.pick(labels)
    elif r < 0.9: result.add indent & "accDescr: " & g.pick(labels)
    elif r < 0.92: result.add indent & "accDescr {\n    " & g.pick(labels) & "\n  " & g.pick(labels) & "\n}"
    elif r < 0.95: result.add ""
    elif r < 0.955: result.add indent & g.pick(["garbage", "\"unterminated : 3", "\"a\" 3", "\"a\" : x", ": 5"])
    else: result.add indent & section(g) & " " & section(g)
    result.add(if g.chance(0.05): "\r\n" else: "\n")
  if g.chance(0.1): result.add "   "

const timelineWords = [
  "2002", "LinkedIn", "Facebook", "Google", "2004", "Industry 4.0", "Web 2.0", "", "a b",
  "Ünïcödé", "日本語のテキスト", "emoji 🎉🎉", "x&amp;y", "#35; hash", "a<b>bold</b>c", "<br>",
  "line<br/>break", "a < b", "fa:fa-car icon", ":fa-car", "&lt;tag&gt;", "#quot;q#quot;",
  "Supercalifragilisticexpialidocious", "aVeryLongWordWithoutAnySpacesThatMustBeCutSomewhere",
  "very long text that goes on and on and wraps over several lines in the box", "x",
  "tab\there", "soft­hyphen", "zero​width", "（括弧）", "ideo\u3000space", "nbsp here",
  "__proto__", "constructor", "Ω≈ç√", "́combining", "WWWWWWWWWWWWWWWWWWWWWWWWW", "<i>it</i>",
  "*em*", "%% not a comment", "50%", "title", "section", "timeline",
]
const timelineOdd = ["1:2", "a: b", ":fa-car", "x:y"]   # a colon that is not followed by a space

proc timelineSource(g: var Gen): string =
  if g.chance(0.15):
    result.add "---\n"
    if g.chance(0.5): result.add "title: " & g.pick(timelineWords) & "\n"
    result.add "config:\n"
    if g.chance(0.5): result.add "  timeline:\n    disableMulticolor: " & g.pick(["true", "false", "1", "x"]) & "\n"
    if g.chance(0.5):
      result.add "  themeVariables:\n"
      for i in 0 .. g.rng.rand(0 .. 4):
        result.add "    cScale" & $i & ": \"" & g.pick(colors) & "\"\n"
    result.add "---\n"
  if g.chance(0.05): result.add "%%{init: {\"timeline\": {\"disableMulticolor\": true}}}%%\n"
  if g.chance(0.05): result.add "%% leading comment\n"
  result.add(if g.chance(0.03): g.pick(["timelineLR", "timeline x", "timelines", "Timeline", "TIMELINE"])
             else: g.pick(["timeline", "timeline", "timeline", "timeline LR", "timeline TD",
                           "timeline  td", "timeline\tLR", "timeline lr"]))
  result.add "\n"
  let n = g.rng.rand(0 .. 14)
  var periods = 0
  for i in 0 ..< n:
    let indent = g.pick(["", "  ", "    ", "\t", " "])
    var r = g.rng.rand(1.0)
    # an event before any period is an error: rarely
    if r >= 0.35 and r < 0.55 and periods == 0 and not g.chance(0.05): r = 0.0
    if r < 0.35:
      inc periods
      result.add indent & g.pick(timelineWords)
      for k in 0 ..< g.rng.rand(0 .. 3):
        result.add(if g.chance(0.03): g.pick([" :", ":"]) else: g.pick([" : ", ": ", " :\t"]))
        result.add(if g.chance(0.03): g.pick(timelineOdd) else: g.pick(timelineWords))
    elif r < 0.55: result.add indent & g.pick([": ", ":  ", ":\t"]) & g.pick(timelineWords)
    elif r < 0.7: result.add indent & "section " & g.pick(timelineWords)
    elif r < 0.73: result.add indent & "section"
    elif r < 0.77: result.add indent & g.pick(["title ", "title", "title  ", "Title\t"]) & g.pick(timelineWords)
    elif r < 0.8: result.add indent & "accTitle: " & g.pick(timelineWords)
    elif r < 0.83: result.add indent & "accDescr: " & g.pick(timelineWords)
    elif r < 0.85: result.add indent & "accDescr {\n    " & g.pick(timelineWords) & "\n  " & g.pick(timelineWords) & "\n}"
    elif r < 0.88: result.add indent & "%% " & g.pick(timelineWords)
    elif r < 0.9: result.add indent & "# hash comment"
    elif r < 0.93: result.add ""
    elif r < 0.93: result.add indent & g.pick(["title\u3000", "section\u00a0", ":\u3000", "accTitle:\u2003", "title\u2028"]) & g.pick(timelineWords)
    elif r < 0.935: result.add indent & g.pick(["garbage : : x", ":", "::", ": ", "accDescr {", "accTitle", "section :", "x # y"])
    else: result.add indent & g.pick(timelineWords) & " : " & g.pick(timelineWords) & " : " & g.pick(timelineWords)
    result.add(if g.chance(0.05): "\r\n" else: "\n")
  if g.chance(0.1): result.add "   "


const flowIds = ["A", "B", "C", "D", "E", "F", "node1", "n_2", "x", "end1", "Ünï", "日本", "a-b", "v", "o", "1"]
const flowLabels = [
  "Start", "End", "Is it?", "a b c", "Ünïcödé", "日本語のラベル", "emoji 🎉", "x&amp;y", "#35; hash",
  "a<b>bold</b>", "line<br/>break", "\"quoted text\"", "\"`**md** text`\"", "fa:fa-car icon",
  "very long label that goes on and on and wraps over several lines in the box", "Ω≈ç√", "x",
  "soft­hyphen", "zero​width", "a  b", "Supercalifragilisticexpialidocious",
]
const flowOpens = [("[", "]"), ("(", ")"), ("((", "))"), ("([", "])"), ("[[", "]]"), ("[(", ")]"),
                   ("{", "}"), ("{{", "}}"), (">", "]"), ("[/", "/]"), ("[\\", "\\]"), ("[/", "\\]"),
                   ("[\\", "/]"), ("(((", ")))")]
const flowLinks = ["-->", "---", "-.->", "==>", "--o", "--x", "<-->", "o--o", "x--x", "-.-", "===",
                   "~~~", "--->", "---->", "==>", "-..->", "<==>", "-->", "-->"]
const flowColors = ["#ff0000", "red", "#abc", "transparent", "#12345678", "black", "white", "lightgray", "notacolor"]
const flowShapes = ["rect", "rounded", "stadium", "fr-rect", "cyl", "circle", "diam", "hex", "lean-r",
                    "lean-l", "trap-b", "trap-t", "dbl-circ", "text", "notch-rect", "lin-rect",
                    "sm-circ", "fr-circ", "fork", "hourglass", "brace", "brace-r", "braces", "bolt",
                    "doc", "delay", "h-cyl", "lin-cyl", "curv-trap", "div-rect", "tri", "win-pane",
                    "f-circ", "notch-pent", "flip-tri", "sl-rect", "docs", "st-rect", "bow-rect",
                    "cross-circ", "tag-doc", "tag-rect", "flag", "odd", "lin-doc", "cloud", "bang",
                    "datastore", "folder", "bucket", "console", "browser", "person", "Rect", "nope"]

proc flowNode(g: var Gen): string =
  result = g.pick(flowIds)
  let r = g.rng.rand(1.0)
  if r < 0.5:
    let (o, c) = g.pick(flowOpens)
    result.add o & (if g.chance(0.02): "" else: g.pick(flowLabels)) & c
  elif r < 0.6:
    result.add "@{ shape: " & g.pick(flowShapes) &
      (if g.chance(0.6): ", label: \"" & g.pick(flowLabels).replace("\"", "") & "\"" else: "") & " }"
  elif r < 0.63:
    result.add "@{ icon: \"fa:user\", form: " & g.pick(["circle", "square", "rounded", "x"]) &
      ", label: \"" & g.pick(["User", "", "a b"]) & "\", pos: " & g.pick(["t", "b"]) & " }"
  elif r < 0.65:
    result.add "@{ img: \"" & g.pick(["https://example.com/a.png", "javascript:alert(1)", "x.png"]) &
      "\", label: \"Pic\", w: " & g.pick(["60", "100", "0", "5000"]) & ", h: 60, constraint: " & g.pick(["on", "off"]) & " }"
    if g.chance(0.15): result.add ":::" & g.pick(["hot", "cold", "internal-link"])

proc flowLink(g: var Gen): string =
  let link = g.pick(flowLinks)
  let r = g.rng.rand(1.0)
  if r < 0.2: link & "|" & g.pick(flowLabels).replace("|", "") & "|"
  elif r < 0.27 and link in ["-->", "==>", "-.->", "---"]:
    (if link == "==>": "== " elif link == "-.->": "-. " else: "-- ") & g.pick(["text", "a b", "日本"]) & " " & link
  elif r < 0.3: "e" & $g.rng.rand(0 .. 3) & "@" & link
  else: link

proc flowStatement(g: var Gen, depth: int, edges: var int): string =
  let r = g.rng.rand(1.0)
  if r < 0.55:
    result = flowNode(g)
    for k in 0 ..< g.rng.rand(0 .. 3):
      if g.chance(0.1): result.add " & " & flowNode(g)
      result.add " " & flowLink(g) & " " & flowNode(g)
      inc edges
  elif r < 0.62 and depth < 3:
    result = "subgraph " & g.pick(["S1", "S2", "one", "two words", "S1[\"Title here\"]", "x[\"" & g.pick(flowLabels).replace("\"", "") & "\"]", ""]) & "\n"
    if g.chance(0.3): result.add "  direction " & g.pick(["LR", "RL", "TB", "BT"]) & "\n"
    for k in 0 ..< g.rng.rand(0 .. 4): result.add "  " & flowStatement(g, depth + 1, edges) & "\n"
    result.add "end"
  elif r < 0.66: result = "classDef " & g.pick(["hot", "cold", "default"]) & " fill:" & g.pick(flowColors) & ",stroke:" & g.pick(flowColors) & (if g.chance(0.3): ",color:#fff" else: "")
  elif r < 0.69: result = "class " & g.pick(flowIds) & "," & g.pick(flowIds) & " " & g.pick(["hot", "cold"])
  elif r < 0.72: result = "style " & g.pick(flowIds) & " fill:" & g.pick(flowColors) & ",stroke-width:" & g.pick(["2px", "4px"]) & (if g.chance(0.3): ",font-weight:bold" else: "")
  elif r < 0.75 and edges > 0:
    result = "linkStyle " & (if g.chance(0.2): "default" else: $g.rng.rand(0 .. edges - 1)) &
      (if g.chance(0.2): " interpolate " & g.pick(["basis", "linear", "step", "stepBefore", "cardinal"]) else: "") &
      " stroke:" & g.pick(flowColors) & (if g.chance(0.4): ",stroke-width:3px" else: "")
  elif r < 0.78: result = "click " & g.pick(flowIds) & " " & g.pick(["href \"https://example.com\"", "\"https://example.com\" \"tip\"", "callback", "call cb()", "\"javascript:x\" _blank", "\"[[Note]]\""])
  elif r < 0.8: result = g.pick(flowIds) & " --> " & g.pick(flowIds) & "\n" & g.pick(flowIds) & " --> " & g.pick(flowIds)
  elif r < 0.82: result = "%% " & g.pick(flowLabels)
  elif r < 0.84: result = "accTitle: " & g.pick(flowLabels)
  elif r < 0.85: result = "accDescr { " & g.pick(flowLabels) & "\n  " & g.pick(flowLabels) & " }"
  elif r < 0.87: result = g.pick(flowIds) & " --> " & g.pick(flowIds) & "; " & g.pick(flowIds)
  elif r < 0.88: result = g.pick(["garbage ((", "A -->", "-->", "A[unclosed", "end", "subgraph", "A@{ shape: }", "A --> B --x"])
  else:
    let a = g.pick(flowIds)
    result = a & " --> " & a
    inc edges

proc flowchartSource(g: var Gen): string =
  if g.chance(0.15):
    result.add "---\n"
    if g.chance(0.4): result.add "title: " & g.pick(flowLabels).replace("\"", "") & "\n"
    result.add "config:\n  flowchart:\n"
    if g.chance(0.4): result.add "    curve: " & g.pick(["basis", "linear", "step", "stepAfter", "natural", "monotoneX", "x"]) & "\n"
    if g.chance(0.3): result.add "    nodeSpacing: " & g.pick(["10", "80", "0", "x"]) & "\n"
    if g.chance(0.3): result.add "    rankSpacing: " & g.pick(["10", "100", "3000"]) & "\n"
    if g.chance(0.3): result.add "    wrappingWidth: " & g.pick(["50", "100", "400"]) & "\n"
    if g.chance(0.2): result.add "    inheritDir: " & g.pick(["true", "false"]) & "\n"
    result.add "---\n"
  result.add g.pick(["flowchart", "graph"])
  result.add(if g.chance(0.1): "" else: " " & g.pick(["TD", "TB", "LR", "RL", "BT", "TD", "LR", ">", "v"]))
  result.add(if g.chance(0.1): ";\n" else: "\n")
  var edges = 0
  for i in 0 ..< g.rng.rand(0 .. 12):
    result.add g.pick(["", "  ", "    ", "\t"]) & flowStatement(g, 0, edges)
    result.add(if g.chance(0.03): "\r\n" else: "\n")

proc options(g: var Gen): JsonNode =
  result = newJObject()
  if g.chance(0.3): result["fontSize"] = %g.pick([12, 14, 16, 18, 20, 11])
  if g.chance(0.2): result["padding"] = %g.pick([0, 4, 8, 16])
  if g.chance(0.3): result["maxWidth"] = %g.pick([200, 300, 320, 390, 500, 640, 100, 800, 1200])
  if g.chance(0.05): result["autoDirection"] = %g.chance(0.5)
  if g.chance(0.05): result["directionBreakpoint"] = %g.pick([0, 400, 1000])
  if g.chance(0.1): result["idPrefix"] = %g.pick(["x", "my-id", "a\"b"])
  if g.chance(0.1): result["responsive"] = %g.chance(0.5)
  if g.chance(0.05): result["fontFamily"] = %g.pick(["Inter", "\"Fira Sans\", sans-serif", "bad;font", "Times New Roman"])

proc toOptions(j: JsonNode): RenderOptions =
  if j.hasKey("fontSize"): result.fontSize = some(j["fontSize"].getFloat)
  if j.hasKey("padding"): result.padding = some(j["padding"].getFloat)
  if j.hasKey("maxWidth"): result.maxWidth = some(j["maxWidth"].getFloat)
  if j.hasKey("idPrefix"): result.idPrefix = some(j["idPrefix"].getStr)
  if j.hasKey("responsive"): result.responsive = some(j["responsive"].getBool)
  if j.hasKey("fontFamily"): result.fontFamily = j["fontFamily"].getStr
  if j.hasKey("autoDirection"): result.autoDirection = some(j["autoDirection"].getBool)
  if j.hasKey("directionBreakpoint"): result.directionBreakpoint = some(j["directionBreakpoint"].getFloat)
  if j.hasKey("now"): result.now = j["now"].getFloat

proc nimakiAnswer(source: string, options: JsonNode): Answer =
  try:
    let r = render(source, toOptions(options))
    Answer(ok: true, svg: r.svg)
  except PeleError as e:
    Answer(ok: false, code: e.code, message: e.msg)
  except CatchableError as e:
    Answer(ok: false, code: "internal", message: e.msg)

proc main() =
  var kind = ""
  var count = 1000
  var seed = 1
  var show = 10
  var packageArg = ""
  for k, key, val in getopt():
    case k
    of cmdLongOption, cmdShortOption:
      case key
      of "cases": count = parseInt(val)
      of "seed": seed = parseInt(val)
      of "show": show = parseInt(val)
      of "package": packageArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: kind = key
    of cmdEnd: discard
  if kind notin ["pie", "timeline", "flowchart"]: quit "ERROR fuzz knows only: pie, timeline, flowchart", 2
  let packageDir = packageDirFrom(packageArg)
  var g = Gen(rng: initRand(seed))
  var cases: seq[JsonNode]
  for i in 0 ..< count:
    let opts = g.options()
    opts["now"] = %1767225600000.0
    cases.add %*{"id": kind & "/" & $seed & "/" & $i, "source": (if kind == "pie": g.pieSource() elif kind == "flowchart": g.flowchartSource() else: g.timelineSource()), "options": opts}
  let dir = buildDir / "fuzz"
  createDir dir
  let inPath = dir / (kind & "-" & $seed & "-in.jsonl")
  let outPath = dir / (kind & "-" & $seed & "-out.jsonl")
  var input = ""
  for c in cases: input.add $c & "\n"
  writeFile inPath, input
  if execShellCmd("TZ=UTC node " & quoteShell(repoDir / "tools" / "oracle.mjs") & " " &
                  quoteShell(packageDir) & " < " & quoteShell(inPath) & " > " & quoteShell(outPath)) != 0:
    quit "ERROR the oracle failed", 2
  var answers: seq[JsonNode]
  for line in lines(outPath):
    if line.len > 0: answers.add parseJson(line)
  var identical, different, shown, rendered = 0
  var failing = ""
  for i, c in cases:
    let a = answers[i]
    let want = if a["ok"].getBool: Answer(ok: true, svg: a["svg"].getStr)
               else: Answer(ok: false, code: a["code"].getStr, message: a["message"].getStr)
    if want.ok: inc rendered
    let got = nimakiAnswer(c["source"].getStr, c["options"])
    let o = compare(c["id"].getStr, kind, want, got)
    if o.verdict == vIdentical: inc identical
    else:
      inc different
      failing.add $c & "\n"
      if shown < show:
        echo "ERROR ", o.id, ": ", o.detail, "; source ", escapeJson(c["source"].getStr), ", options ", $c["options"]
        inc shown
  let failPath = dir / (kind & "-" & $seed & ".jsonl")
  writeFile failPath, failing
  # the summary the pages show: the last run of each type
  let dataPath = dataDir / "fuzz.json"
  var data = if fileExists(dataPath): parseFile(dataPath) else: %*{"about": "Written by tools/fuzz.nim: the last run for each diagram type. Do not edit by hand.", "types": {}}
  data["types"][kind] = %*{"seed": seed, "cases": cases.len, "identical": identical, "different": different,
                           "rendered": rendered, "errors": cases.len - rendered}
  writeFile dataPath, data.pretty & "\n"
  echo "fuzz: ", kind, ", seed ", seed, ", ", cases.len, " cases: ", identical, " identical, ",
    different, " different", (if different > 0: " (" & failPath & ")" else: "")
  if different > 0: quit 1

when isMainModule:
  main()
