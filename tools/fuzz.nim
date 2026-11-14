## fuzz, the referee's second half: generates many inputs for a diagram type from a seeded
## grammar of the type, renders them with Pele (in Node, through tools/oracle.mjs) and with
## nimaki, and compares byte for byte, with the options the generator picks (font size,
## padding, maxWidth, config...). The corpus has few cases per type; this finds what it misses.
##
##   nim r tools/fuzz.nim pie                 1000 cases of pie, seed 1
##   nim r tools/fuzz.nim timeline            the same for timeline
##   nim r tools/fuzz.nim flowchart           and for flowchart (and the other ported types)
##   options:
##     --cases:N         how many cases (default 1000)
##     --seed:S          the seed of the generator (default 1)
##     --show:N          print at most N differences as ERROR lines (default 10)
##     --package:PATH    the oracle package (default reference/npm/package or $PELE_PACKAGE)
##     --js              compare Pele with nimaki compiled to JavaScript (tools/jsrunner.nim, in
##                       Node); records the run in docs/data/js.json instead of fuzz.json
##
## The last run of each type is summed up in docs/data/fuzz.json, which the pages read. Each
## failing case is written whole to build/fuzz/<type>-<seed>.jsonl, so it can be replayed.
import std/[os, osproc, strutils, json, random, parseopt, options, sequtils, tables]
import common, verdict, answers
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

const stateIds = ["A", "B", "C", "Still", "Moving", "Crash", "s1", "s2", "Long_name_state", "X", "fork1",
                  "Ünï", "[*]", "[*]", "[*]", "First", "Second", "N1"]
const stateLabels = ["", "text", "a b c", "EvNewValue", "Ünïcödé", "日本語のラベル", "emoji 🎉", "x&amp;y",
                     "*em*", "**bold**", "a<br>b", "very long transition label that goes on and on and on",
                     "#35; hash", ":colon", "  spaces  ", "fa:fa-car icon", "a\\nb", "<b>tag</b>", "$x^2$"]
const stateColors = ["#ff0000", "red", "#abc", "transparent", "#12345678", "black", "white", "lightgray", "notacolor"]

proc stateStatement(g: var Gen, depth: int): string =
  let r = g.rng.rand(1.0)
  if r < 0.4:
    result = g.pick(stateIds) & (if g.chance(0.08): ":::" & g.pick(["hot", "cold"]) else: "") & " --> " &
      g.pick(stateIds) & (if g.chance(0.05): ":::" & g.pick(["hot", "cold"]) else: "")
    if g.chance(0.35): result.add " : " & g.pick(stateLabels)
  elif r < 0.5 and depth < 3:
    result = "state " & g.pick(["A", "B", "Comp", "\"Composite title\" as C2", "s1", "First", "Ünï"]) & " {\n"
    if g.chance(0.25): result.add "  direction " & g.pick(["LR", "RL", "TB", "BT"]) & "\n"
    let n = g.rng.rand(0 .. 5)
    for k in 0 ..< n:
      result.add "  " & stateStatement(g, depth + 1) & "\n"
      if g.chance(0.12): result.add "  --\n"
    result.add "}"
  elif r < 0.55: result = "state " & g.pick(stateIds.filterIt(it != "[*]")) & " " & g.pick(["<<fork>>", "<<join>>", "<<choice>>"])
  elif r < 0.6: result = "state \"" & g.pick(stateLabels).replace("\"", "") & "\" as " & g.pick(stateIds.filterIt(it != "[*]"))
  elif r < 0.66: result = g.pick(stateIds.filterIt(it != "[*]")) & " : " & g.pick(stateLabels)
  elif r < 0.71:
    let id = g.pick(stateIds.filterIt(it != "[*]"))
    if g.chance(0.5): result = "note " & g.pick(["left of", "right of"]) & " " & id & " : " & g.pick(stateLabels)
    else: result = "note " & g.pick(["left of", "right of"]) & " " & id & "\n  " & g.pick(stateLabels) & "\n  " & g.pick(stateLabels) & "\nend note"
  elif r < 0.73: result = "note \"" & g.pick(stateLabels).replace("\"", "") & "\" as N" & $g.rng.rand(1 .. 3)
  elif r < 0.76: result = "classDef " & g.pick(["hot", "cold", "default"]) & " fill:" & g.pick(stateColors) & ",stroke:" & g.pick(stateColors) & (if g.chance(0.3): ",color:#fff" else: "") & (if g.chance(0.2): ",font-weight:bold" else: "")
  elif r < 0.79: result = "class " & g.pick(stateIds.filterIt(it != "[*]")) & (if g.chance(0.3): "," & g.pick(stateIds.filterIt(it != "[*]")) else: "") & " " & g.pick(["hot", "cold"])
  elif r < 0.82: result = "style " & g.pick(stateIds.filterIt(it != "[*]")) & " fill:" & g.pick(stateColors) & ",stroke-width:" & g.pick(["2px", "4px"]) & (if g.chance(0.05): ",font-style:italic" else: "")
  elif r < 0.84: result = "click " & g.pick(stateIds.filterIt(it != "[*]")) & " " & g.pick(["href \"https://example.com\"", "\"https://example.com\" \"tip\"", "\"javascript:x\" \"t&amp;t\"", "\"\"\"x\"\"\" \"\"q\"\""])
  elif r < 0.86: result = g.pick(stateIds) & " --> " & g.pick(stateIds) & "\n" & g.pick(stateIds) & " --> " & g.pick(stateIds)
  elif r < 0.88: result = "%% " & g.pick(stateLabels)
  elif r < 0.89: result = "accTitle: " & g.pick(stateLabels)
  elif r < 0.9: result = "accDescr { " & g.pick(stateLabels) & "\n  " & g.pick(stateLabels) & " }"
  elif r < 0.91: result = g.pick(["hide empty description", "scale 350 width", "direction LR"])
  elif r < 0.92: result = g.pick(["garbage {", "A -->", "-->", "state", "}", "note left of", "state A <<nope>>", "A --> B : x : y", "x-y --> a.b", "--"])
  elif r < 0.96:
    let a = g.pick(stateIds.filterIt(it != "[*]"))
    result = a & " --> " & a & (if g.chance(0.5): " : " & g.pick(stateLabels) else: "")
  else: result = g.pick(stateIds.filterIt(it != "[*]"))

proc stateSource(g: var Gen): string =
  if g.chance(0.15):
    result.add "---\n"
    if g.chance(0.4): result.add "title: " & g.pick(stateLabels).replace("\"", "").replace(":", "") & "\n"
    result.add "config:\n"
    if g.chance(0.5): result.add "  flowchart:\n    curve: " & g.pick(["basis", "linear", "step", "stepAfter", "natural", "x"]) & "\n"
    result.add "  state:\n"
    if g.chance(0.3): result.add "    nodeSpacing: " & g.pick(["10", "80", "0", "x"]) & "\n"
    if g.chance(0.3): result.add "    rankSpacing: " & g.pick(["10", "100", "3000"]) & "\n"
    if g.chance(0.3): result.add "    wrappingWidth: " & g.pick(["50", "100", "400"]) & "\n"
    result.add "    useMaxWidth: true\n"
    result.add "---\n"
  result.add g.pick(["stateDiagram-v2", "stateDiagram", "stateDiagram-v2"]) & "\n"
  if g.chance(0.2): result.add "  direction " & g.pick(["LR", "RL", "TB", "BT"]) & "\n"
  for i in 0 ..< g.rng.rand(0 .. 12):
    result.add g.pick(["", "  ", "    ", "\t"]) & stateStatement(g, 0)
    result.add(if g.chance(0.03): "\r\n" else: "\n")
proc swimlaneSource(g: var Gen): string =
  ## A flowchart whose top-level subgraphs are lanes: lanes of steps, handoffs between them, a
  ## few loose steps (they share an unnamed lane) and groups inside lanes.
  if g.chance(0.1): result.add "---\nconfig:\n  flowchart:\n    rankSpacing: " & g.pick(["10", "100"]) & "\n---\n"
  result.add(if g.chance(0.03): g.pick(["swimlane", "Swimlane-beta"]) else: "swimlane-beta")
  result.add(if g.chance(0.2): "" else: " " & g.pick(["TD", "TB", "LR", "RL", "BT", "LR"]))
  result.add "\n"
  var edges = 0
  for lane in 0 ..< g.rng.rand(0 .. 4):
    result.add "  subgraph " & g.pick(["Customer", "Support", "Ops", "L" & $lane, "x[\"" & g.pick(flowLabels).replace("\"", "") & "\"]"]) & "\n"
    for k in 0 ..< g.rng.rand(0 .. 4):
      result.add "    " & (if g.chance(0.6): flowNode(g) else: flowStatement(g, 1, edges)) & "\n"
    result.add "  end\n"
  for i in 0 ..< g.rng.rand(0 .. 8):
    let r = g.rng.rand(1.0)
    if r < 0.7:
      result.add "  " & g.pick(flowIds) & " " & flowLink(g) & " " & g.pick(flowIds) & "\n"
      inc edges
    else: result.add "  " & flowStatement(g, 1, edges) & "\n"

const classIds = ["Animal", "Duck", "Fish", "Zebra", "A", "B", "C", "note0", "interface0", "1st", "Ünï",
                  "日本", "x_y", "a-b", "`Back tick`", "List~int~", "Map~K, V~", "ns.Inner"]
const classMembers = ["+String name", "-int age", "#id", "~pkg", "+isMammal() bool", "+mate()", "-swim($speed) int$",
                      "+run()*", "static$", "abstract*", "List~int~ items", "+get(List~T~ list) Map~K, V~",
                      "+ a b c", "<<interface>>", "", "Ünïcödé field", "$$x^2$$", "&lt;tag&gt;", "run)",
                      "+method(a, b) : int", "very long member name that goes on and on and on and on", "+f()$"]
const classArrows = ["<|--", "*--", "o--", "-->", "--", "..>", "..|>", "..", "--|>", "--*", "--o", "<--", "()--",
                     "--()", "<|..", "*..", "<|--|>", "<-->", "--", "-->"]

proc className(g: var Gen): string = g.pick(classIds)

proc classStatement(g: var Gen, depth: int): string =
  let r = g.rng.rand(1.0)
  if r < 0.3:
    result = "class " & g.className()
    if g.chance(0.15): result.add "[\"" & g.pick(["Label", "a b", "日本", "", "x&amp;y"]) & "\"]"
    let s = g.rng.rand(1.0)
    if s < 0.45:
      result.add " {\n"
      for k in 0 ..< g.rng.rand(0 .. 5): result.add "    " & g.pick(classMembers) & "\n"
      result.add "  }"
    elif s < 0.55: result.add ":::" & g.pick(["hot", "cold"])
    elif s < 0.62: result.add " <<" & g.pick(["interface", "abstract", "Service"]) & ">>"
  elif r < 0.6:
    result = g.className()
    if g.chance(0.2): result.add " \"" & g.pick(["1", "0..*", "many", "1..n", "$$n$$"]) & "\""
    result.add " " & g.pick(classArrows) & " "
    if g.chance(0.2): result.add "\"" & g.pick(["1", "0..*", "many", "*"]) & "\" "
    result.add g.className()
    if g.chance(0.35): result.add " : " & g.pick(["uses", "has", "a b", "日本", "very long relation label here", "<<x>>"])
  elif r < 0.68: result = g.className() & " : " & g.pick(classMembers)
  elif r < 0.74 and depth < 3:
    result = "namespace " & g.pick(["Shapes", "ns", "a.b", "Outer.Inner", "Ünï"]) & " {\n"
    for k in 0 ..< g.rng.rand(1 .. 3):
      let s = classStatement(g, depth + 1)
      if s.startsWith("class ") or s.startsWith("note") or s.startsWith("namespace"): result.add "  " & s & "\n"
      else: result.add "  class " & g.className() & "\n"
    result.add "}"
  elif r < 0.8: result = "note " & (if g.chance(0.6): "for " & g.className() & " " else: "") & "\"" & g.pick(["a note", "line<br/>two", "日本", "x"]) & "\""
  elif r < 0.84: result = "classDef " & g.pick(["hot", "cold", "default"]) & " fill:" & g.pick(flowColors) & ",stroke:" & g.pick(flowColors) & (if g.chance(0.3): ",color:#fff" else: "") & (if g.chance(0.2): ",font-size:20px" else: "")
  elif r < 0.87: result = "cssClass \"" & g.className() & "," & g.className() & "\" " & g.pick(["hot", "cold"])
  elif r < 0.9: result = "style " & g.pick(["Animal", "Duck", "A"]) & " fill:" & g.pick(flowColors) & (if g.chance(0.4): ",stroke-width:4px" else: "") & (if g.chance(0.2): ",font-style:italic" else: "")
  elif r < 0.93: result = g.pick(["click ", "link ", "callback "]) & g.className() & " " & g.pick(["href \"https://example.com\"", "\"https://example.com\" \"tip\"", "call cb()", "\"javascript:x\" _blank", "\"cb\" \"tip\""])
  elif r < 0.95: result = "direction " & g.pick(["TB", "BT", "LR", "RL"])
  elif r < 0.96: result = g.pick(["accTitle: a title", "accDescr: described", "accDescr {\n  multi\n  line\n}"])
  elif r < 0.97: result = "<<" & g.pick(["interface", "enum"]) & ">> " & g.className()
  elif r < 0.995: result = "%% " & g.pick(flowLabels)
  else: result = g.pick(["garbage ((", "class", "A <|-- ", "class A {", "}", "namespace {", "A : ", "--> B"])

proc classSource(g: var Gen): string =
  if g.chance(0.2):
    result.add "---\n"
    if g.chance(0.4): result.add "title: " & g.pick(["Classes", "A title", "日本"]) & "\n"
    result.add "config:\n  class:\n"
    if g.chance(0.4): result.add "    hideEmptyMembersBox: " & g.pick(["true", "false"]) & "\n"
    if g.chance(0.4): result.add "    hierarchicalNamespaces: " & g.pick(["true", "false"]) & "\n"
    if g.chance(0.3): result.add "    nodeSpacing: " & g.pick(["10", "80", "x"]) & "\n"
    if g.chance(0.3): result.add "    rankSpacing: " & g.pick(["10", "100"]) & "\n"
    result.add "    useMaxWidth: true\n---\n"
  result.add(if g.chance(0.03): g.pick(["classDiagram-v3", "ClassDiagram"]) elif g.chance(0.2): "classDiagram-v2" else: "classDiagram")
  result.add "\n"
  for i in 0 ..< g.rng.rand(1 .. 12):
    result.add g.pick(["  ", "    ", "", "\t"]) & classStatement(g, 0)
const erIds = ["CUSTOMER", "ORDER", "LINE-ITEM", "A", "B", "C", "p[Person]", "a[\"Customer Account\"]", "\"two words\"",
               "Ünï", "日本", "x_1", "car", "u", "1", "S1", "id1", "DELIVERY-ADDRESS"]
const erRelIds = ["CUSTOMER", "ORDER", "LINE-ITEM", "A", "B", "C", "\"two words\"", "Ünï", "日本", "x_1", "car",
                  "S1", "id1", "DELIVERY-ADDRESS", "p", "a"]
const erLefts = ["||", "|o", "}o", "}|", "o|", "o{", "|{", "one or zero", "zero or more", "one or more", "only one",
                 "many(0)", "many(1)", "1+", "0+", "1", "u", "many", "zero or one", "one"]
const erRights = ["||", "o|", "o{", "|{", "|o", "}o", "}|", "one or zero", "zero or more", "one or more", "only one",
                  "many(0)", "many(1)", "1+", "0+", "1", "u", "many"]
const erTypes = ["string", "int", "float", "List~int~", "Map~string,int~", "type?", "Ünï", "decimal(10,2)",
                 "`weird type`", "*PK", "x~y~z"]
const erNames = ["name", "id", "firstName", "created_at", "日本", "a-b", "x.y", "List~str~"]

proc erAttribute(g: var Gen): string =
  result = g.pick(erTypes) & " " & g.pick(erNames)
  if g.chance(0.3): result.add " " & g.pick(["PK", "FK", "UK", "PK, FK", "pk,uk", "FK,PK,UK"])
  if g.chance(0.25): result.add " \"" & g.pick(stateLabels).replace("\"", "") & "\""

proc erStatement(g: var Gen, depth: int): string =
  let r = g.rng.rand(1.0)
  if r < 0.45:
    let sep = if g.chance(0.7): (if g.chance(0.5): "--" else: "..") else: g.pick([" to ", " optionally to "])
    result = g.pick(erRelIds) & (if g.chance(0.05): ":::hot" else: "") & " " & g.pick(erLefts) & sep & g.pick(erRights) &
      " " & g.pick(erRelIds) & (if g.chance(0.04): ":::cold" else: "") & " : " &
      g.pick(["places", "has", "\"insured for\"", "\"\"", "contains", "uses", "日本", "a-b", "\"a b c\""])
  elif r < 0.62:
    result = g.pick(erIds) & (if g.chance(0.1): ":::" & g.pick(["hot", "cold"]) else: "") & " {\n"
    for k in 0 ..< g.rng.rand(0 .. 5): result.add "    " & erAttribute(g) & "\n"
    result.add "  }"
  elif r < 0.68: result = g.pick(erIds)
  elif r < 0.73 and depth < 2:
    result = "subgraph " & g.pick(["S1", "S2", "Group", "\"Quoted\"", "G [A title]", "H [\"Quoted title\"]"]) & "\n"
    if g.chance(0.3): result.add "  direction " & g.pick(["LR", "RL", "TB", "BT"]) & "\n"
    for k in 0 ..< g.rng.rand(0 .. 4): result.add "  " & erStatement(g, depth + 1) & "\n"
    result.add "end"
  elif r < 0.77: result = "classDef " & g.pick(["hot", "cold"]) & " fill:" & g.pick(stateColors) & ",stroke:" & g.pick(stateColors) & (if g.chance(0.3): ",color:#fff" else: "") & (if g.chance(0.2): ",font-weight:bold" else: "")
  elif r < 0.8: result = "class " & g.pick(["A", "B", "CUSTOMER", "S1"]) & (if g.chance(0.3): ",ORDER" else: "") & " " & g.pick(["hot", "cold"])
  elif r < 0.83: result = "style " & g.pick(["A", "B", "CUSTOMER", "S1", "id1"]) & " fill:" & g.pick(stateColors) & ",stroke-width:" & g.pick(["2px", "4px"]) & (if g.chance(0.2): ",font-family:monospace" else: "")
  elif r < 0.86:
    let a = g.pick(erRelIds)
    result = a & " " & g.pick(erLefts) & "--" & g.pick(erRights) & " " & a & " : " & g.pick(["self", "parent of", "x"])
  elif r < 0.88: result = "%% " & g.pick(stateLabels)
  elif r < 0.89: result = "accTitle: " & g.pick(stateLabels)
  elif r < 0.9: result = "accDescr { " & g.pick(stateLabels) & "\n  " & g.pick(stateLabels) & " }"
  elif r < 0.92: result = "direction " & g.pick(["LR", "RL", "TB", "BT"])
  elif r < 0.925: result = g.pick(["A ||--", "A {", "}", "A ||--o{ B", "end", "A |x--|| B : y", "style", "A[unclosed"])
  else: result = g.pick(erRelIds) & " " & g.pick(erLefts) & "--" & g.pick(erRights) & " " & g.pick(erRelIds) & " : " & g.pick(["has", "a"])

proc erSource(g: var Gen): string =
  if g.chance(0.15):
    result.add "---\n"
    if g.chance(0.4): result.add "title: " & g.pick(["Order example", "日本", "A title"]) & "\n"
    result.add "config:\n  er:\n"
    if g.chance(0.3): result.add "    nodeSpacing: " & g.pick(["10", "80", "0", "x"]) & "\n"
    if g.chance(0.3): result.add "    rankSpacing: " & g.pick(["10", "100", "3000"]) & "\n"
    result.add "    useMaxWidth: true\n"
    result.add "---\n"
  result.add "erDiagram\n"
  if g.chance(0.15): result.add "  direction " & g.pick(["LR", "RL", "TB", "BT"]) & "\n"
  for i in 0 ..< g.rng.rand(0 .. 10):
    result.add g.pick(["", "  ", "    ", "\t"]) & erStatement(g, 0)
    result.add(if g.chance(0.03): "\r\n" else: "\n")

const reqNames = ["test_req", "test_req2", "test_entity", "R1", "E1", "\"quoted name\"", "\"Ünï 日本\"", "a.b", "x",
                  "test_req", "R1", "E1"]
const reqKinds = ["requirement", "functionalRequirement", "interfaceRequirement", "performanceRequirement",
                  "physicalRequirement", "designConstraint", "Requirement", "REQUIREMENT"]
const reqRels = ["contains", "copies", "derives", "satisfies", "verifies", "refines", "traces"]

proc reqName(g: var Gen): string = (if g.chance(0.02): g.pick(["Ünï", "日本"]) else: g.pick(reqNames))

proc reqStatement(g: var Gen): string =
  let r = g.rng.rand(1.0)
  if r < 0.25:
    result = g.pick(reqKinds) & " " & reqName(g) & (if g.chance(0.1): ":::" & g.pick(["hot", "cold"]) else: "") & " {\n"
    for k in 0 ..< g.rng.rand(0 .. 5):
      result.add "    " & (if g.chance(0.03): g.pick(["type: x", "risk: none", "text: *em*"]) else: g.pick([
        "id: " & g.pick(["1", "1.1", "R-7", "\"q id\""]),
        "text: " & g.pick(["the test text.", "\"quoted text\"", "\"*em* text\"", "\"日本語\"", "a very long requirement text that wraps around the box", "x", "\"**bold** and $x^2$\""]),
        "risk: " & g.pick(["low", "medium", "high", "High"]),
        "verifymethod: " & g.pick(["analysis", "demonstration", "inspection", "test", "Test"])])) & "\n"
    result.add "  }"
  elif r < 0.4:
    result = "element " & reqName(g) & (if g.chance(0.1): ":::hot" else: "") & " {\n"
    for k in 0 ..< g.rng.rand(0 .. 2):
      result.add "    " & g.pick(["type: " & g.pick(["simulation", "word doc", "\"quoted\"", "\"**bold**\""]),
                                   "docRef: " & g.pick(["reqs/test_entity", "github.com/x", "\"q\""])]) & "\n"
    result.add "  }"
  elif r < 0.65:
    if g.chance(0.7): result = reqName(g) & " - " & g.pick(reqRels) & " -> " & reqName(g)
    else: result = reqName(g) & " <- " & g.pick(reqRels) & " - " & reqName(g)
  elif r < 0.7:
    let a = reqName(g)
    result = a & " - " & g.pick(reqRels) & " -> " & a
  elif r < 0.75: result = "classDef " & g.pick(["hot", "cold", "important"]) & " fill:" & g.pick(stateColors) & ",stroke:" & g.pick(stateColors) & (if g.chance(0.3): ",color:#fff" else: "") & (if g.chance(0.2): ",font-weight:bold" else: "")
  elif r < 0.79: result = "class " & g.pick(["test_req", "R1", "E1", "x"]) & (if g.chance(0.3): "," & g.pick(["test_entity", "x"]) else: "") & " " & g.pick(["hot", "cold", "important"])
  elif r < 0.83: result = "style " & g.pick(["test_req", "R1", "E1", "x", "a.b"]) & " fill:" & g.pick(stateColors) & ",stroke-width:" & g.pick(["2px", "4px"]) & (if g.chance(0.2): ",font-style:italic" else: "")
  elif r < 0.86: result = reqName(g) & ":::" & g.pick(["hot", "cold"])
  elif r < 0.88: result = "%% " & g.pick(stateLabels)
  elif r < 0.89: result = "accTitle: " & g.pick(stateLabels)
  elif r < 0.9: result = "accDescr { " & g.pick(stateLabels) & "\n  " & g.pick(stateLabels) & " }"
  elif r < 0.93: result = "direction " & g.pick(["LR", "RL", "TB", "BT"])
  elif r < 0.945: result = g.pick(["requirement x {", "}", "a - b -> c", "element {", "a -> b", "style", "risk: high"])
  else: result = reqName(g) & " - " & g.pick(reqRels) & " -> " & reqName(g)

proc requirementSource(g: var Gen): string =
  if g.chance(0.1): result.add "---\ntitle: " & g.pick(["Requirements", "日本", "A title"]) & "\n---\n"
  if g.chance(0.05): result.add "accTitle: before\n"
  result.add g.pick(["requirementDiagram", "requirementDiagram", "  requirementDiagram"]) & "\n"
  for i in 0 ..< g.rng.rand(0 .. 10):
    result.add g.pick(["", "  ", "    ", "\t"]) & reqStatement(g)
    result.add(if g.chance(0.03): "\r\n" else: "\n")

proc gitSource(g: var Gen): string =
  ## Mostly valid histories: the generator tracks branches, the current branch and commit ids,
  ## then sometimes breaks a rule on purpose.
  if g.chance(0.25):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(["History", "A title", "日本"]) & "\n"
    result.add "config:\n  gitGraph:\n"
    for key in ["showBranches", "showCommitLabel", "rotateCommitLabel", "parallelCommits"]:
      if g.chance(0.3): result.add "    " & key & ": " & g.pick(["true", "false", "1"]) & "\n"
    if g.chance(0.2): result.add "    mainBranchName: " & g.pick(["trunk", "main", "develop", "1"]) & "\n"
    if g.chance(0.15): result.add "    mainBranchOrder: " & g.pick(["0", "2", "-1", "x"]) & "\n"
    result.add "---\n"
  result.add(if g.chance(0.03): g.pick(["gitgraph", "gitGraph:", "GitGraph"]) else: "gitGraph")
  if g.chance(0.4): result.add " " & g.pick(["LR", "TB", "BT"]) & ":"
  elif g.chance(0.1): result.add ":"
  result.add "\n"
  var branches = @["main"]
  var current = "main"
  var ids: seq[string]
  var idBranch: seq[string]
  var heads = @[false]
  let names = ["develop", "feature", "fix/bug-1", "release.v2", "x", "日本", "\"quoted name\"", "feature-2", "commits"]
  for i in 0 ..< g.rng.rand(1 .. 16):
    let indent = g.pick(["  ", "    ", "", "\t"])
    let r = g.rng.rand(1.0)
    var line = ""
    if r < 0.4:
      line = "commit"
      if g.chance(0.3):
        let id = g.pick(["a1", "b2", "c3", "fix", "日本", "same", "x y"])
        line.add " id: \"" & id & "\""
        ids.add id
        idBranch.add current
      if g.chance(0.25): line.add " tag: \"" & g.pick(["v1.0", "v2", "release candidate", "", "日本"]) & "\""
      if g.chance(0.1): line.add " tag: \"" & g.pick(["extra", "x"]) & "\""
      if g.chance(0.2): line.add " type: " & g.pick(["NORMAL", "REVERSE", "HIGHLIGHT"])
      if g.chance(0.2): line.add (if g.chance(0.5): " msg: " else: " ") & "\"" & g.pick(["a message", "", "fix it", "日本"]) & "\""
      heads[branches.find(current)] = true
    elif r < 0.55:
      let name = g.pick(names)
      line = "branch " & name
      if g.chance(0.2): line.add " order: " & g.pick(["1", "2", "0", "5", "10"])
      let clean = name.strip(chars = {'"'})
      if clean notin branches:
        branches.add clean
        heads.add heads[branches.find(current)]
      current = clean
      if g.chance(0.7): line.add "\n" & indent & "commit"
    elif r < 0.7:
      let name = g.pick(branches)
      line = g.pick(["checkout ", "switch "]) & (if ' ' in name: "\"" & name & "\"" else: name)
      current = name
    elif r < 0.85 and branches.len > 1:
      var name = g.pick(branches)
      if name == current and branches.len > 1 and g.chance(0.9):
        while name == current: name = g.pick(branches)
      line = "merge " & (if ' ' in name: "\"" & name & "\"" else: name)
      if g.chance(0.5): line = "commit\n" & indent & line
      if g.chance(0.2): line.add " id: \"" & g.pick(["m1", "m2", "merge-it"]) & "\""
      if g.chance(0.2): line.add " tag: \"" & g.pick(["v1", "merged"]) & "\""
      if g.chance(0.15): line.add " type: " & g.pick(["NORMAL", "REVERSE", "HIGHLIGHT"])
    elif r < 0.92 and ids.len > 0:
      var k = g.rng.rand(ids.high)
      for tries in 0 ..< 4:
        if idBranch[k] != current: break
        k = g.rng.rand(ids.high)
      line = "cherry-pick id: \"" & ids[k] & "\""
      if g.chance(0.2): line.add " tag: \"" & g.pick(["picked", ""]) & "\""
      if g.chance(0.1): line.add " parent: \"" & g.pick(ids) & "\""
    elif r < 0.95: line = g.pick(["accTitle: a title", "accDescr: described", "accDescr {\n  multi\n  line\n}", "title A history"])
    elif r < 0.98: line = "%% " & g.pick(flowLabels)
    else: line = g.pick(["garbage", "commit id:", "branch", "merge", "checkout nowhere", "commit type: OTHER"])
    result.add indent & line
    result.add(if g.chance(0.03): "\r\n" else: "\n")

const ucIds = ["User", "Admin", "Login", "Checkout", "Profile", "Payload", "Auth", "Shop", "Guest", "Pay", "x1", "Sys"]
const ucLabels = ["Sign in", "Place order", "\"Quoted case\"", "Edit profile", "日本語", "a very long use case name that has to wrap", "**bold** label", "x", "Ünï"]
const ucJson = ["{\"ok\": true}", "{}", "{\"2\": \"b\", \"1\": \"a\", \"name\": \"n\"}",
                "{\"colors\": [\"Red\", \"Green\"], \"n\": 3, \"z\": null}",
                "{\"address\": {\"city\": \"Oslo\", \"zip\": 123}, \"items\": [{\"name\": \"A\"}, {}], \"e\": []}",
                "{\"dup\": \"old\", \"dup\": \"new\", \"f\": 1.5e3, \"neg\": -0}",
                "{\"long\": \"a value long enough to need wrapping in the table cell of the json node\"}",
                "{\"a\": tru}", "{a: 1}", "{\"a\": 1,}", "{\"a\": 01}", "{\"a\" 1}", "{\"a\": \"x\\q\"}",
                "{\"esc\": \"line\\nbreak \\u00e9 \\\"q\\\"\"}", "{\"nested\": {\"deep\": {\"deeper\": [1, [2, 3]]}}}"]
const ucArrows = ["-->", "-->", "<--", "--", "--->", "---->", "--|>", "--o", "--x", "o--", "x--", "<---", "-- label -->",
                  "<-- label --", "-- \"quoted label\" --o", "o-- why --", "..> : include", "..> : extend", "..> : INCLUDE",
                  "-- uses ---", "-- x --x", "e1@-->", "e2@--"]

proc ucId(g: var Gen): string = (if g.chance(0.03): g.pick(["\"Gen id\"", "\"`md`\"", "\"日本\""]) else: g.pick(ucIds))

proc ucElement(g: var Gen, actor: bool): string =
  result = g.ucId()
  if not result.startsWith("\"") and g.chance(0.4):
    let l = g.pick(ucLabels)
    result.add(if actor or g.chance(0.5): "(" & l & ")" else: "[" & l & "]")
  if g.chance(0.12):
    result.add "@{ " & g.pick(["type: hollow", "type: awesome", "business: true", "icon: user", "type: normal, business: false",
                               "business: true, type: hollow", "icon: \"\"", "type: rect", "animation: fast"]) & " }"
  if g.chance(0.1): result.add " <<" & (if g.chance(0.05): " " else: g.pick(["Human", "System", "ext"])) & ">>"
  if g.chance(0.05): result.add ":::" & g.pick(["hot", "cold", "hot,cold"])

proc ucStatement(g: var Gen, depth: int): string =
  let r = g.rng.rand(1.0)
  if r < 0.18:
    result = "actor " & g.ucElement(true)
    if g.chance(0.2): result.add ", " & g.ucElement(true)
    elif g.chance(0.15): result.add " " & g.pick(ucArrows) & " " & g.ucId()
  elif r < 0.32: result = g.ucElement(false)
  elif r < 0.6:
    result = g.ucId() & (if g.chance(0.03): ":::hot" else: "") & " " & g.pick(ucArrows) & " " &
      (if g.chance(0.15): g.ucElement(false) else: g.ucId())
  elif r < 0.66 and depth == 0:
    result = "systemBoundary " & g.pick(["Auth", "Shop", "\"Ordering system\"", "Sys[The system]", "S2"]) &
      (if g.chance(0.2): "@{ type: " & g.pick(["package", "rect"]) & " }" else: "") &
      (if g.chance(0.1): ":::hot" else: "") & "\n"
    for k in 0 ..< g.rng.rand(0 .. 4):
      result.add "  " & (if g.chance(0.3): "actor " & g.ucElement(true) else: g.ucElement(false)) & "\n"
    result.add(if g.chance(0.97): "end" else: "")
  elif r < 0.7: result = "note for " & g.ucId() & " " & g.pick(["\"Remember this\"", "plain words here", "`**md**`", "x"])
  elif r < 0.75: result = "json " & g.pick(["Payload", "Data", "Session"]) & (if g.chance(0.5): " " else: "") & "@" & (if g.chance(0.3): g.pick(ucJson) else: g.pick(ucJson[0 .. 6])) & (if g.chance(0.2): ":::" & g.pick(["data", "hot"]) else: "")
  elif r < 0.79: result = g.pick(["Auth", "e1", "e2", "Payload", "User", "Login", "Nope"]) & "@{ " & g.pick(["type: package", "animation: fast", "animate: true", "animation: slow", "business: true", "type: hollow", "icon: cog", "type: rect", "x: 1"]) & " }"
  elif r < 0.83: result = "classDef " & g.pick(["hot", "cold", "default", "data"]) & " fill:" & g.pick(stateColors) & ",stroke:" & g.pick(stateColors) & (if g.chance(0.3): ",color:#fff" else: "") & (if g.chance(0.2): ",stroke-width:3px" else: "")
  elif r < 0.86: result = "class " & g.ucId() & (if g.chance(0.3): "," & g.ucId() else: "") & " " & g.pick(["hot", "cold", "data"])
  elif r < 0.89: result = "style " & g.pick(["User", "Login", "Auth", "e1", "Payload", "Nope"]) & " fill:" & g.pick(stateColors) & ",stroke-width:" & g.pick(["2px", "4px"]) & (if g.chance(0.2): ",font-style:italic" else: "")
  elif r < 0.91: result = "%% " & g.pick(stateLabels)
  elif r < 0.92: result = "accTitle: " & g.pick(stateLabels)
  elif r < 0.93: result = "accDescr { " & g.pick(stateLabels) & "\n    " & g.pick(stateLabels) & " }"
  elif r < 0.95: result = "direction " & g.pick(["LR", "RL", "TB", "BT", "TD"])
  elif r < 0.955: result = g.pick(["package X", "actor", "end", "-->", "note X", "json x @{", "classDef", "A B C"])
  else: result = g.ucId() & " --> " & g.ucId()

proc usecaseSource(g: var Gen): string =
  if g.chance(0.1): result.add "---\ntitle: " & g.pick(["Use cases", "日本", "A title"]) & "\n---\n"
  result.add (if g.chance(0.02): g.pick(["usecase", "usecase-beta x"]) else: "usecase-beta") & "\n"
  for i in 0 ..< g.rng.rand(0 .. 10):
    result.add g.pick(["", "", "  ", "\t"]) & g.ucStatement(0)
    result.add(if g.chance(0.03): "\r\n" else: "\n")

const afIds = ["a", "b", "c", "brief", "draft", "lint", "ok", "ship", "x1", "Ünï", "日本", "n-2", "end1", "connectors", "team", "tools"]
const afFlows = ["team", "writer", "reviewer", "tools", "inner", "a", "Ünï"]
const afLabels = ["Brief", "Draft the notes", "run_linter", "Clean?", "a b c", "日本語のラベル", "emoji 🎉", "x&amp;y",
                  "**bold** text", "a very long label that goes on and on and has to wrap in its box", "x", "", "Ω≈ç√"]
const afShapes = ["task", "tool", "input", "decision", "refdoc", "action", "round", "rect", "roundedRect",
                  "subroutine", "subprocess", "framed-rectangle", "lean-right", "diamond", "lin-doc", "hexagon", "hex",
                  "stadium", "circle", "cylinder", "doc", "odd", "cloud", "bolt", "Task", "lean_right", "nope",
                  "constructor", "connector", "1", "[a]", "collapsedGroup"]
const afMeta = ["view: \"collapsed\"", "view: collapsed", "protocol: \"http\"", "label: \"Relabelled\"",
                "label: \"**md**\", labelType: markdown", "animate: true", "curve: basis", "curve: linear",
                "connectorRef: \"x.y\"", "value: 3", "w: 10", "a: [1, 2]", "a: {b: c}", "__proto__: x",
                "label: 42", "shape:", "bad: [", "\"unterminated", "- 1", "view: \"collapsed\""]
const afOpens = [("[", "]"), ("[", "]"), ("[", "]"), ("(", ")"), ("(", ")"), ("[[", "]]"), ("[", "]"),
                 ("[", "]"), ("(", ")"), ("{", "}"), ("((", "))")]
const afLinks = ["-->", "-->", "-->", "-.-", "-.-", "--x", "--->", "-..-", "---x", "-->", "-.-", "--x", "-->"]
const afColors = ["#ff0000", "red", "#abc", "transparent", "#12345678", "black", "white", "notacolor"]

proc afMetaBody(g: var Gen): string =
  if g.chance(0.12):
    # The multi-line form, sometimes with the commas of the single-line one.
    result = "\n"
    for k in 0 ..< g.rng.rand(1 .. 3):
      result.add "    " & g.pick(afMeta) & (if g.chance(0.4): "," else: "") & "\n"
    result.add "  "
  else:
    var parts: seq[string]
    for k in 0 ..< g.rng.rand(1 .. 2): parts.add g.pick(afMeta)
    result = " " & parts.join(", ") & " "

proc afNode(g: var Gen, last: bool): string =
  ## Metadata ends a statement: Mermaid takes no link after it.
  result = g.pick(afIds)
  let r = if last or g.chance(0.03): g.rng.rand(1.0) else: 0.35 + g.rng.rand(0.3)
  if r < 0.35:
    let label = g.pick(afLabels)
    result.add "[\"" & (if label == "" and g.chance(0.9): "x" else: label) & "\"]@{ shape: " & g.pick(afShapes) & " }"
  elif r < 0.55:
    let (o, c) = g.pick(afOpens)
    let label = g.pick(afLabels).replace("&", "and")
    result.add o & (if label == "" and g.chance(0.9): "x" else: label) & c
  elif r < 0.55 + (if last: 0.07 else: 0.0):
    result.add "@{ shape: " & g.pick(afShapes) & (if g.chance(0.5): ", label: \"" & g.pick(afLabels) & "\"" else: "") & " }"
  elif r < 0.65 and last:
    result.add "@{" & afMetaBody(g) & "}"
  if (r >= 0.35 and r < 0.55 or g.chance(0.05)) and g.chance(0.05): result.add ":::" & g.pick(["hot", "cold", "internal-link"])

proc afLink(g: var Gen): string =
  let link = g.pick(afLinks)
  let r = g.rng.rand(1.0)
  if r < 0.15:
    let label = g.pick(afLabels).replace("|", "")
    link & "|" & (if label == "": "x" else: label) & "|"
  elif r < 0.22 and link in ["-->", "--x", "---"]:
    "-- " & g.pick(["yes", "no", "a b", "日本"]) & " " & link
  elif r < 0.25: "e" & $g.rng.rand(0 .. 3) & "@" & link
  else: link

proc afStatement(g: var Gen, depth: int, edges: var int): string =
  let ind = repeat("  ", depth + 1)
  let r = g.rng.rand(1.0)
  if r < 0.45:
    let n = g.rng.rand(0 .. 3)
    result = afNode(g, n == 0)
    for k in 0 ..< n:
      if g.chance(0.08): result.add " & " & afNode(g, false)
      result.add " " & afLink(g) & " " & afNode(g, k == n - 1)
      inc edges
  elif r < 0.57 and depth < 3:
    let head = g.rng.rand(1.0)
    result =
      if head < 0.75: "flow " & g.pick(afFlows) & (if g.chance(0.7): "[\"" & g.pick(afLabels) & "\"]" else: "") &
                      (if g.chance(0.15): "@{" & afMetaBody(g) & "}" else: "") & "\n"
      elif head < 0.85: "flow\n"
      else: "global\n"
    if g.chance(0.2): result.add ind & "  direction " & g.pick(["LR", "RL", "TB", "BT"]) & "\n"
    for k in 0 ..< g.rng.rand(0 .. 4): result.add ind & "  " & afStatement(g, depth + 1, edges) & "\n"
    result.add ind & "end"
  elif r < 0.6:
    result = "connector " & g.pick(["github", "llm", "api", "Ünï"]) & (if g.chance(0.6): "[\"" & g.pick(afLabels) & "\"]" else: "") &
      (if g.chance(0.3): "@{" & afMetaBody(g) & "}" else: "")
  elif r < 0.66: result = g.pick(@afIds & @afFlows) & "@{" & afMetaBody(g) & "}"
  elif r < 0.69: result = "classDef " & g.pick(["hot", "cold", "default"]) & " fill:" & g.pick(afColors) & ",stroke:" & g.pick(afColors) & (if g.chance(0.3): ",color:#fff" else: "")
  elif r < 0.71: result = "class " & g.pick(afIds) & "," & g.pick(afFlows) & " " & g.pick(["hot", "cold"])
  elif r < 0.73: result = "style " & g.pick(@afIds & @afFlows) & " fill:" & g.pick(afColors) & ",stroke-width:" & g.pick(["2px", "4px"]) & (if g.chance(0.3): ",font-weight:bold" else: "")
  elif r < 0.75 and edges > 0:
    result = "linkStyle " & (if g.chance(0.2): "default" else: $g.rng.rand(0 .. edges - 1)) &
      (if g.chance(0.2): " interpolate " & g.pick(["basis", "linear", "step", "cardinal"]) else: "") &
      " stroke:" & g.pick(afColors)
  elif r < 0.77: result = "click " & g.pick(afIds) & " " & g.pick(["href \"https://example.com\"", "\"https://example.com\" \"tip\"", "callback", "\"[[Note]]\""])
  elif r < 0.8: result = "%% " & g.pick(afLabels)
  elif r < 0.81: result = "accTitle: " & g.pick(afLabels)
  elif r < 0.82: result = "accDescr: " & g.pick(afLabels)
  elif r < 0.85:
    # An edge into a flow from inside it, or across flows.
    result = g.pick(afIds) & " " & g.pick(["-->", "-.-", "--x"]) & " " & g.pick(afFlows)
    inc edges
  elif r < 0.87: result = g.pick(["garbage ((", "a -->", "-->", "a[unclosed", "end", "flow", "a@{ shape: }", "a --> b --x", "a <-- b", "subgraph x", "a -.-> b", "a --- b", "a ==> b"])
  else:
    let a = g.pick(afIds)
    result = a & " " & g.pick(["-->", "-.-"]) & " " & a
    inc edges

proc agentflowSource(g: var Gen): string =
  if g.chance(0.2):
    result.add "---\n"
    if g.chance(0.4): result.add "title: " & g.pick(afLabels) & "\n"
    result.add "config:\n"
    if g.chance(0.3): result.add "  direction: " & g.pick(["LR", "TB", "x"]) & "\n"
    if g.chance(0.6):
      result.add "  agentflow:\n"
      result.add "    nodeSpacing: " & g.pick(["10", "80", "0", "x"]) & "\n"
      if g.chance(0.4): result.add "    wrappingWidth: " & g.pick(["50", "200", "3000"]) & "\n"
      if g.chance(0.4): result.add "    minNodeWidth: " & g.pick(["20", "200"]) & "\n"
      if g.chance(0.3): result.add "    rankSpacing: " & g.pick(["10", "100"]) & "\n"
    if g.chance(0.4):
      result.add "  flowchart:\n"
      result.add "    curve: " & g.pick(["basis", "linear", "step", "natural"]) & "\n"
      if g.chance(0.5): result.add "    inheritDir: " & g.pick(["true", "false"]) & "\n"
    result.add "---\n"
  result.add "agentflow-beta"
  result.add(if g.chance(0.08): "" else: " " & g.pick(["TB", "LR", "RL", "BT", "TD", "TB", "LR", ">", "v", "TB", "LR"]))
  result.add(if g.chance(0.05): ";\n" else: "\n")
  var edges = 0
  for i in 0 ..< g.rng.rand(0 .. 10):
    result.add g.pick(["  ", "  ", "", "\t"]) & afStatement(g, 0, edges)
    result.add(if g.chance(0.03): "\r\n" else: "\n")

# Labels: the features of src/text/label.ts in the types that draw them. The words are safe in
# every place a label goes here (no quotes, semicolons, colons or brackets of the grammars).
const lbWords = ["Start", "a", "label", "Ünïcödé", "日本語のラベル", "中文標點，測試。", "emoji 🎉", "Ω≈ç√",
                 "Supercalifragilisticexpialidocious", "super­cali­fragilistic", "zero​width​breaks",
                 "x&amp;y", "#35; hash", "&lt;tag&gt;", "snake_case_word", "2*3*4", "a  b", "ﬂow"]
const lbMarks = ["<b>bold</b>", "<i>it</i>", "<strong>s</strong>", "<em>e</em>", "<code>code()</code>", "<u>u</u>",
                 "H<sub>2</sub>O", "x<sup>2</sup>", "<sub>a<sup>b</sup></sub>", "<span>span</span>", "<br>", "<br/>",
                 "List<T>", "<kbd>K</kbd>", "<b>open", "</b>", "**bold**", "*it*", "_it_", "__b__", "** x**", "\\n",
                 "fa:fa-car", "fab:fa-github", "fa:fa-none", "fas:fa-user icon", "fa:fa-car ", "$$x^2$$",
                 "$$\\frac{a}{b}$$", "$$bad$$", "$$html$$", "$$nan$$", "$$a$$ and $$b$$", "$$unclosed", "$$ $$"]

proc lbLabel(g: var Gen): string =
  for k in 0 ..< g.rng.rand(1 .. 6):
    if k > 0: result.add(if g.chance(0.8): " " else: "")
    result.add(if g.chance(0.45): g.pick(lbMarks) else: g.pick(lbWords))
  if g.chance(0.05): result = repeat(result & " ", g.rng.rand(2 .. 6))

proc labelsSource(g: var Gen): string =
  case g.rng.rand(0 .. 5)
  of 0, 1:
    result = "flowchart " & g.pick(["TD", "LR"]) & "\n"
    for i in 0 ..< g.rng.rand(1 .. 6):
      let a = g.pick(["A", "B", "C", "D"])
      let b = g.pick(["A", "B", "C", "D", "E"])
      let md = g.chance(0.3)
      let la = if md: "\"`" & lbLabel(g) & "`\"" else: "\"" & lbLabel(g) & "\""
      case g.rng.rand(0 .. 3)
      of 0: result.add "  " & a & "[" & la & "]\n"
      of 1: result.add "  " & a & "[" & la & "] -->|" & lbLabel(g).replace("|", "") & "| " & b & "\n"
      of 2: result.add "  subgraph S" & $i & "[" & la & "]\n    " & a & " --> " & b & "\n  end\n"
      else: result.add "  " & a & "(" & la & ") --- " & b & "{" & "\"" & lbLabel(g) & "\"}\n"
  of 2:
    result = "sequenceDiagram\n"
    for i in 0 ..< g.rng.rand(1 .. 6):
      let a = g.pick(["Alice", "Bob", "Carol"])
      let b = g.pick(["Alice", "Bob", "Carol"])
      if g.chance(0.3): result.add "  Note over " & a & ": " & lbLabel(g) & "\n"
      elif g.chance(0.1): result.add "  participant " & a & " as " & lbLabel(g) & "\n"
      else: result.add "  " & a & "->>" & b & ": " & lbLabel(g) & "\n"
  of 3:
    result = "stateDiagram-v2\n"
    for i in 0 ..< g.rng.rand(1 .. 6):
      let a = g.pick(["S1", "S2", "S3"])
      if g.chance(0.4): result.add "  " & a & " : " & lbLabel(g) & "\n"
      elif g.chance(0.3): result.add "  note right of " & a & " : " & lbLabel(g) & "\n"
      else: result.add "  " & a & " --> " & g.pick(["S1", "S2", "S3"]) & " : " & lbLabel(g) & "\n"
  of 4:
    result = "classDiagram\n"
    for i in 0 ..< g.rng.rand(1 .. 5):
      let a = g.pick(["Animal", "Duck", "Fish"])
      if g.chance(0.4): result.add "  note for " & a & " \"" & lbLabel(g) & "\"\n"
      else: result.add "  " & a & " --> " & g.pick(["Animal", "Duck", "Fish"]) & " : " & lbLabel(g) & "\n"
  else:
    # Types that do not typeset math still read the markup.
    result = "timeline\n  title " & lbLabel(g) & "\n"
    for i in 0 ..< g.rng.rand(1 .. 4): result.add "  " & lbLabel(g) & " : " & lbLabel(g) & "\n"

const scores = ["5", "1", "3", "4", "2", "0", "7", "-1", "2.5", " 4 ", "", "x", "1e1", "0x3", "Infinity",
                "3.", ".5", "NaN", "\u30003"]
const actors = ["Me", "Cat", "Dog", "", " Me ", "Ünï", "日本", "Zed", "a b", "Me", "emoji 🎉",
                "<b>bold</b>", "very long actor name that wraps", "\uE000", "😀"]

proc journeyWord(g: var Gen): string =
  ## A `;` or `#` ends any text in journey, so words with them are rare.
  result = g.pick(timelineWords)
  while (';' in result or '#' in result) and not g.chance(0.05): result = g.pick(timelineWords)

proc journeySource(g: var Gen): string =
  if g.chance(0.1):
    result.add "---\n"
    if g.chance(0.6): result.add "title: " & g.journeyWord() & "\n"
    result.add "---\n"
  if g.chance(0.05): result.add "%% leading comment\n"
  result.add(if g.chance(0.03): g.pick(["Journey", "journeys", "journey x"]) else: "journey")
  result.add "\n"
  let n = g.rng.rand(0 .. 12)
  for i in 0 ..< n:
    let indent = g.pick(["", "  ", "    ", "\t"])
    let r = g.rng.rand(1.0)
    if r < 0.55:
      var task = g.journeyWord()
      if task == "" or task.startsWith("title") or task.startsWith("section"): task = "Task"
      result.add indent & task & g.pick([": ", ":", " : "]) & g.pick(scores)
      if g.chance(0.8):
        result.add ":"
        var people: seq[string]
        for k in 0 .. g.rng.rand(0 .. 4): people.add g.pick(actors)
        result.add " " & people.join(g.pick([", ", ",", " , "]))
      if g.chance(0.03): result.add ":" & g.pick(actors)
    elif r < 0.7: result.add indent & "section " & g.journeyWord()
    elif r < 0.72: result.add indent & "section"
    elif r < 0.76: result.add indent & g.pick(["title ", "title", "title  ", "Title\t"]) & g.journeyWord()
    elif r < 0.79: result.add indent & "accTitle: " & g.journeyWord()
    elif r < 0.82: result.add indent & "accDescr: " & g.journeyWord()
    elif r < 0.84: result.add indent & "accDescr {\n    " & g.journeyWord() & "\n  " & g.journeyWord() & "\n}"
    elif r < 0.87: result.add indent & "%% " & g.journeyWord()
    elif r < 0.89: result.add indent & "# hash comment"
    elif r < 0.92: result.add ""
    elif r < 0.95: result.add indent & g.pick(["title\u3000", "section\u00a0"]) & g.journeyWord()
    elif r < 0.97: result.add indent & g.pick(["Task", "Task:", ": 5", "a; b: 3", "Task 5", "x # y: 3", ":"])
    else: result.add indent & g.pick(actors) & ": " & g.pick(scores) & ": " & g.pick(actors) & "," & g.pick(actors)
    result.add(if g.chance(0.05): "\r\n" else: "\n")

proc infoSource(g: var Gen): string =
  if g.chance(0.15): result.add "---\ntitle: " & g.pick(labels) & "\n---\n"
  if g.chance(0.1): result.add g.pick(["\n", "%% comment\n", "  \n"])
  result.add(if g.chance(0.03): g.pick(["Info", "infox", "info:"]) else: "info")
  if g.chance(0.4): result.add g.pick([" showInfo", "\nshowInfo", " showinfo", "  showInfo  "])
  result.add "\n"
  for i in 0 ..< g.rng.rand(0 .. 4):
    let r = g.rng.rand(1.0)
    let indent = g.pick(["", "  ", "\t"])
    if r < 0.35: result.add indent & "title " & g.pick(labels)
    elif r < 0.55: result.add indent & "accTitle: " & g.pick(labels)
    elif r < 0.7: result.add indent & "accDescr: " & g.pick(labels)
    elif r < 0.8: result.add indent & "accDescr {\n  " & g.pick(labels) & "\n" & g.pick(labels) & "\n}"
    elif r < 0.88: result.add indent & "%% " & g.pick(labels)
    elif r < 0.95: result.add ""
    else: result.add indent & g.pick(["showInfo", "garbage", "title", "info"])
    result.add(if g.chance(0.05): "\r\n" else: "\n")

proc packetSource(g: var Gen): string =
  if g.chance(0.35):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  packet:\n"
    for key in ["bitsPerRow", "rowHeight", "bitWidth", "paddingX", "paddingY"]:
      if g.chance(0.3): result.add "    " & key & ": " & g.pick(["8", "16", "32", "64", "1", "0", "7.5", "500", "-3", "x", "20"]) & "\n"
    if g.chance(0.3): result.add "    showBits: " & g.pick(["false", "true", "0"]) & "\n"
    if g.chance(0.3): result.add "    bitOrder: " & g.pick(["descending", "ascending", "x"]) & "\n"
    result.add "    useMaxWidth: true\n---\n"
  result.add(if g.chance(0.03): g.pick(["Packet", "packet-alpha", "packets"])
             elif g.chance(0.3): "packet-beta" else: "packet")
  result.add "\n"
  var bit = 0
  for i in 0 ..< g.rng.rand(0 .. 12):
    let indent = g.pick(["", "  ", "\t"])
    let r = g.rng.rand(1.0)
    let label = "\"" & g.pick(labels) & "\""
    if r < 0.45:
      let width = g.pick([1, 1, 2, 4, 8, 8, 16, 16, 24, 32, 3, 40, 64, 100])
      if g.chance(0.02): bit += g.pick([-1, 1, 2])   # not contiguous: an error
      if width == 1 and g.chance(0.5): result.add indent & $bit & ": " & label
      else: result.add indent & $bit & "-" & $(bit + width - 1) & ": " & label
      bit += width
    elif r < 0.75:
      let width = g.pick([1, 2, 4, 8, 16, 32, 5, 12, 48, 0])
      result.add indent & "+" & $width & g.pick([": ", ":", " : "]) & label
      bit += max(width, 1)
    elif r < 0.8: result.add indent & "title " & g.pick(labels)
    elif r < 0.83: result.add indent & "accTitle: " & g.pick(labels)
    elif r < 0.86: result.add indent & "accDescr: " & g.pick(labels)
    elif r < 0.89: result.add indent & "%% " & g.pick(labels)
    elif r < 0.98: result.add ""
    else: result.add indent & g.pick(["1.5: \"x\"", "x: \"y\"", "5-3: \"back\"", "+: \"z\"", "0-: \"a\"", "007: \"z\"", $bit & "-" & $bit & " \"no colon\""])
    result.add(if g.chance(0.05): "\r\n" else: "\n")

const seqNames = ["Alice", "Bob", "John", "A", "B", "C", "Ünï", "日本", "API", "DB", "a_b", "Q🎉", "Alice", "Bob"]
const seqOddNames = ["x y", "a-b", "1", "a#b", "a,b"]
const seqTexts = ["Hello", "Hi Bob!", "", "a long message that goes on and on and on until it has to wrap somewhere",
                  "wrap:wrapped text that is long enough to need wrapping in the diagram", "nowrap:no wrap here",
                  "a<br>b", "<b>bold</b>", "Ünïcödé", "日本語のテキスト", "emoji 🎉",
                  "fa:fa-car icon", "50%", "tab\there", "ideo\u3000space", "$$x^2$$", "*em*"]
const seqArrows = ["->>", "-->>", "->", "-->", "-x", "--x", "-)", "--)", "<<->>", "<<-->>", "-|\\", "-|/",
                   "-\\\\", "-//", "--|\\", "--|/", "--\\\\", "--//", "/|-", "\\|-", "//-", "\\\\-",
                   "/|--", "\\|--", "//--", "\\\\--"]
const seqKinds = ["participant", "actor", "participant", "participant"]
const seqShapes = ["boundary", "control", "entity", "database", "collections", "queue", "actor", "participant", "other"]

proc sequenceSource(g: var Gen): string =
  if g.chance(0.3):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(seqTexts) & "\n"
    result.add "config:\n"
    if g.chance(0.2): result.add "  wrap: " & g.pick(["true", "false"]) & "\n"
    result.add "  sequence:\n"
    for key in ["actorMargin", "width", "height", "messageMargin", "noteMargin", "boxMargin"]:
      if g.chance(0.15): result.add "    " & key & ": " & g.pick(["0", "10", "40", "100", "150", "3000", "-5", "x", "7.5"]) & "\n"
    for key in ["mirrorActors", "rightAngles", "hideUnusedParticipants", "showSequenceNumbers", "wrap"]:
      if g.chance(0.15): result.add "    " & key & ": " & g.pick(["true", "false", "1"]) & "\n"
    if g.chance(0.15): result.add "    messageAlign: " & g.pick(["left", "right", "center", "x"]) & "\n"
    result.add "---\n"
  if g.chance(0.05): result.add "%%{wrap}%%\n"
  if g.chance(0.05): result.add "%% leading comment\n"
  result.add(if g.chance(0.03): g.pick(["sequenceDiagramx", "sequence", "SequenceDiagram"]) else: "sequenceDiagram")
  result.add "\n"
  var depth: seq[string]
  var inBox = false
  for i in 0 ..< g.rng.rand(0 .. 18):
    let indent = g.pick(["", "  ", "    ", "\t"])
    let r = g.rng.rand(1.0)
    let a = if g.chance(0.03): g.pick(seqOddNames) else: g.pick(seqNames)
    let b = g.pick(seqNames)
    if inBox and r < 0.7:
      if g.chance(0.3):
        result.add indent & "end"
        inBox = false
      else: result.add indent & g.pick(seqKinds) & " " & a
    elif r < 0.35:
      result.add indent & a & g.pick(seqArrows) & (if g.chance(0.85): "" else: g.pick(["+", "+", "-", "()"])) & b & g.pick([": ", ":", " : "]) & g.pick(seqTexts)
    elif r < 0.37:
      result.add indent & a & "()" & g.pick(seqArrows) & g.pick(["", "()"]) & b & ": " & g.pick(seqTexts)
    elif r < 0.45:
      result.add indent & g.pick(seqKinds) & " " & a
      let k = g.rng.rand(1.0)
      if k < 0.3: result.add " as " & g.pick(seqTexts)
      elif k < 0.45: result.add "@{ \"type\": \"" & g.pick(seqShapes) & "\" }"
      elif k < 0.5: result.add "@{ \"type\": \"" & g.pick(seqShapes) & "\", \"alias\": \"" & g.pick(seqNames) & "\" }"
      elif k < 0.52: result.add "@{ bad: [ }"
    elif r < 0.52:
      result.add indent & "Note " & g.pick(["left of ", "right of ", "over ", "over "]) & a
      if g.chance(0.3): result.add "," & b
      result.add ": " & g.pick(seqTexts)
    elif r < 0.62 and depth.len < 4:
      let kind = g.pick(["loop", "alt", "opt", "par", "critical", "break", "rect", "par_over"])
      let text = if kind == "rect": g.pick(["rgb(200, 150, 255)", "rgba(0,0,255,0.1)", "red", "#abc", "", "notacolor"]) else: g.pick(seqTexts)
      result.add indent & kind & " " & text
      depth.add kind
    elif r < 0.66 and depth.len > 0:
      let kind = depth[^1]
      if kind == "alt": result.add indent & "else " & g.pick(seqTexts)
      elif kind == "par" or kind == "par_over": result.add indent & "and " & g.pick(seqTexts)
      elif kind == "critical": result.add indent & "option " & g.pick(seqTexts)
      else:
        result.add indent & "end"
        discard depth.pop()
    elif r < 0.7 and depth.len > 0:
      result.add indent & "end"
      discard depth.pop()
    elif r < 0.73:
      result.add indent & "activate " & a
      if g.chance(0.6): result.add "\n" & indent & a & "->>" & b & ": " & g.pick(seqTexts) & "\n" & indent & "deactivate " & a
    elif r < 0.76: result.add indent & g.pick(["autonumber", "autonumber 10", "autonumber 1 5", "autonumber off", "autonumber 1.5 0.25"])
    elif r < 0.79 and depth.len == 0 and not inBox:
      result.add indent & "box " & g.pick(["", "Aqua ", "rgb(33,66,99) ", "transparent ", "lightgray ", "notacolor "]) & g.pick(seqTexts)
      inBox = true
    elif r < 0.82:
      let fresh = if g.chance(0.9): "New" & $i else: a
      result.add indent & "create " & g.pick(seqKinds) & " " & fresh & "\n"
      result.add indent & b & "->>" & fresh & ": " & g.pick(seqTexts)
    elif r < 0.84:
      result.add indent & "destroy " & a & "\n"
      result.add indent & a & "-x" & b & ": " & g.pick(seqTexts)
    elif r < 0.86: result.add indent & g.pick(["title ", "title: "]) & g.pick(seqTexts)
    elif r < 0.87: result.add indent & "accTitle: " & g.pick(seqTexts)
    elif r < 0.88: result.add indent & "accDescr: " & g.pick(seqTexts)
    elif r < 0.9: result.add indent & g.pick(["links ", "link ", "properties ", "details "]) & a & ": " &
      g.pick(["{\"class\": \"my-class x\"}", "{\"a\": \"http://x\"}", "Repo @ https://x", "\"str\"", "{bad"])
    elif r < 0.92: result.add indent & "%% " & g.pick(seqTexts)
    elif r < 0.975: result.add ""
    else: result.add indent & g.pick(["garbage ->", "A->>B: x&amp;y", "A->>", "Note left B", "end", "else x", "->>B: x", "A-->>B", "participant", "A->>B: x; B->>A: y"])
    result.add(if g.chance(0.05): "\r\n" else: "\n")
  while depth.len > 0 and g.chance(0.9):
    result.add "end\n"
    discard depth.pop()
  if inBox and g.chance(0.9): result.add "end\n"

const radarNames = ["A", "B", "speed", "power", "x1", "my-axis", "titleX", "a_b", "Z9", "Q", "r2d2", "maxi"]
const radarOdd = ["ü", "axis", "curve", "max", "-x", "x-"]   # names the grammar takes for something else
const radarNumbers = ["1", "2", "3", "4", "5", "0", "10", "2.5", "100", "0.5", "1.25", "99999", "0.0"]

proc radarNumber(g: var Gen): string =
  if g.chance(0.02): g.pick(["07", "1.", "1.2.3", "-1"]) else: g.pick(radarNumbers)

proc radarLabel(g: var Gen): string =
  if g.chance(0.4): "[\"" & g.pick(labels) & "\"]" else: ""

proc radarSource(g: var Gen): string =
  if g.chance(0.3):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  radar:\n"
    for key in ["width", "height", "marginTop", "marginLeft", "axisScaleFactor", "axisLabelFactor", "curveTension"]:
      if g.chance(0.2): result.add "    " & key & ": " & g.pick(["0", "0.5", "1", "1.2", "200", "500", "-1", "x", "5000"]) & "\n"
    result.add "    useMaxWidth: true\n---\n"
  result.add(if g.chance(0.03): g.pick(["radar", "Radar-beta", "radar-betax"])
             else: g.pick(["radar-beta", "radar-beta:", "radar-beta :"]))
  result.add "\n"
  var axes: seq[string]
  let nAxes = g.rng.rand(0 .. 7)
  for i in 0 ..< nAxes:
    var name = if g.chance(0.02): g.pick(radarOdd) else: g.pick(radarNames)
    if name in axes: name = name & $i
    axes.add name
  if axes.len > 0:
    result.add "  axis "
    for i, a in axes:
      result.add (if i > 0: g.pick([", ", ","]) else: "") & a & g.radarLabel()
    result.add "\n"
  for i in 0 ..< g.rng.rand(0 .. 4):
    let r = g.rng.rand(1.0)
    if r < 0.6:
      result.add "  curve c" & $i & g.radarLabel() & "{"
      let n = if g.chance(0.9): axes.len else: g.rng.rand(1 .. 6)
      if g.chance(0.3) and axes.len > 0:
        for k in 0 ..< max(n, 1):
          result.add (if k > 0: ", " else: "") & axes[k mod axes.len] & g.pick([": ", ":", " "]) & g.radarNumber()
      else:
        for k in 0 ..< max(n, 1):
          result.add (if k > 0: g.pick([", ", ",", ",\n    "]) else: "") & g.radarNumber()
      result.add "}\n"
    elif r < 0.7: result.add "  showLegend " & g.pick(["true", "false"]) & "\n"
    elif r < 0.78: result.add "  " & g.pick(["ticks", "max", "min"]) & " " & g.radarNumber() & "\n"
    elif r < 0.85: result.add "  graticule " & g.pick(["circle", "polygon"]) & "\n"
    elif r < 0.9: result.add "  title " & g.pick(labels) & "\n"
    elif r < 0.93: result.add "  accTitle: " & g.pick(labels) & "\n"
    elif r < 0.96: result.add "  %% " & g.pick(labels) & "\n"
    elif r < 0.985: result.add "\n"
    else: result.add "  " & g.pick(["axis", "curve x{}", "ticks x", "graticule square", "max 3, min 1", "showLegend true, ticks 3", "accDescr {", "curve y{1, 2", "titlex"]) & "\n"

const xyNumbers = ["0", "1", "5", "10", "2.5", "-3", "+4", ".5", "-.25", "100", "1000", "7000",
                   "0.001", "33.3", "-100", "12", "99999", "1.5", "42", "3"]
const xyWords = ["jan", "feb", "mar", "apr", "Sales", "Revenue (in $)", "Q1", "Q2", "x_1", "a+b", "#1",
                 "A&B", "2024", "rate*2", "one.two", "a-b", "y=x"]

proc xyNumber(g: var Gen): string =
  if g.chance(0.03): g.pick(["1.", "1e3", "x", "--1", "1.2.3", ""]) else: g.pick(xyNumbers)

proc xyText(g: var Gen): string =
  ## A word run, or a quoted string (a quote inside ends it).
  if g.chance(0.5): "\"" & g.pick(labels).replace("\"", "") & "\"" else: g.pick(xyWords)

proc xyValues(g: var Gen, n: int, labelled: bool): string =
  result = "["
  for k in 0 ..< n:
    result.add (if k > 0: g.pick([", ", ",", " , "]) else: "") & g.xyNumber()
    if labelled and g.chance(0.4): result.add " \"" & g.pick(labels).replace("\"", "") & "\""
  result.add "]"

proc xychartSource(g: var Gen): string =
  if g.chance(0.4):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  xyChart:\n"
    for key in ["width", "height", "showDataLabel", "showTitle", "showLegend", "chartOrientation"]:
      if g.chance(0.2):
        result.add "    " & key & ": " & g.pick(["0", "200", "500", "900", "true", "false", "horizontal", "vertical", "x", "5000", "-1"]) & "\n"
    for axisKey in ["xAxis", "yAxis"]:
      if g.chance(0.2):
        result.add "    " & axisKey & ":\n"
        for key in ["showTitle", "showLabel", "showTick", "showAxisLine"]:
          if g.chance(0.4): result.add "      " & key & ": " & g.pick(["true", "false"]) & "\n"
    result.add "---\n"
  result.add(if g.chance(0.03): g.pick(["xychart-betax", "XYchart", "xy-chart"])
             else: g.pick(["xychart-beta", "xychart", "xychart-beta horizontal", "xychart horizontal", "xychart-beta vertical"]))
  result.add "\n"
  var nCats = 0
  for i in 0 ..< g.rng.rand(1 .. 6):
    let r = g.rng.rand(1.0)
    if r < 0.12: result.add "  title " & g.xyText() & "\n"
    elif r < 0.3:
      result.add "  x-axis"
      if g.chance(0.6): result.add " " & g.xyText()
      if g.chance(0.6):
        nCats = g.rng.rand(1 .. 8)
        result.add " ["
        for k in 0 ..< nCats: result.add (if k > 0: g.pick([", ", ","]) else: "") & g.xyText()
        result.add "]"
      elif g.chance(0.6): result.add " " & g.xyNumber() & " --> " & g.xyNumber()
      result.add "\n"
    elif r < 0.42:
      result.add "  y-axis"
      if g.chance(0.6): result.add " " & g.xyText()
      if g.chance(0.6): result.add " " & g.xyNumber() & " --> " & g.xyNumber()
      result.add "\n"
    elif r < 0.85:
      let line = g.chance(0.5)
      result.add "  " & (if line: "line" else: "bar")
      if g.chance(0.5): result.add " " & g.xyText()
      let n = if nCats > 0 and g.chance(0.7): nCats else: g.rng.rand(1 .. 10)
      result.add " " & g.xyValues(n, line or g.chance(0.1)) & "\n"
    elif r < 0.9: result.add "  accTitle: " & g.pick(labels) & "\n"
    elif r < 0.93: result.add "  accDescr {\n    " & g.pick(labels) & "\n  }\n"
    elif r < 0.96: result.add "  %% " & g.pick(labels) & "\n"
    elif r < 0.98: result.add "\n"
    else: result.add "  " & g.pick(["line", "bar []", "x-axis [", "y-axis 1 -->", "title", "pie", "line [1, 2", "bar \"a\" [1 2]"]) & "\n"
  if g.chance(0.5):
    let line = g.chance(0.5)
    result.add "  " & (if line: "line" else: "bar") & " " & g.xyValues(if nCats > 0: nCats else: g.rng.rand(1 .. 10), line) & "\n"

const treemapValues = ["10", "25", "1", "0", "100", "3.5", "1,000", "2_5", "1000000", "0.01", "7", "42", "12.", "99999999", "1e3"]
const treemapOdd = ["1.2.3", ".", ",5", "_"]

proc treemapValue(g: var Gen): string =
  if g.chance(0.03): g.pick(treemapOdd) else: g.pick(treemapValues)

proc treemapLabel(g: var Gen): string =
  ## A quote ends a name, so labels with one are rare.
  result = g.pick(labels)
  while '"' in result and not g.chance(0.05): result = g.pick(labels)
const treemapFormats = [",", "$0,0", "$,", ".2f", ",.1f", "d", ".1%", "e", ".3e", "+,", "~", ".3~f", ">10,", "*^12.2f", "x", ".0f", "$,.2f", "(,", ",d", ".25f", "s", "%"]
const treemapStyles = ["fill:#f96", "fill:red,stroke:#333,stroke-width:2px", "color:white", "font-weight:bold",
                       "font-size:20px", "font-style:italic", "fill:#123456;color:#fff", "fill:rgb(1\\,2\\,3)", "stroke:blue", ""]

proc treemapSource(g: var Gen): string =
  if g.chance(0.4):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  treemap:\n"
    if g.chance(0.4): result.add "    valueFormat: \"" & g.pick(treemapFormats) & "\"\n"
    if g.chance(0.2): result.add "    showValues: " & g.pick(["false", "true"]) & "\n"
    for key in ["nodeWidth", "nodeHeight", "padding", "diagramPadding"]:
      if g.chance(0.15): result.add "    " & key & ": " & g.pick(["1", "10", "20", "40", "64", "100", "0", "500", "x"]) & "\n"
    result.add "    useMaxWidth: true\n---\n"
  result.add(if g.chance(0.03): g.pick(["Treemap", "treemaps", "treemap-alpha"])
             else: g.pick(["treemap-beta", "treemap"]))
  result.add "\n"
  var classes: seq[string]
  for i in 0 ..< g.rng.rand(0 .. 2):
    let name = g.pick(["hot", "cold", "big_one", "x1"])
    classes.add name
    result.add "classDef " & name & " " & g.pick(treemapStyles) & (if g.chance(0.3): ";" else: "") & "\n"
  var depth = 0
  for i in 0 ..< g.rng.rand(0 .. 16):
    let r = g.rng.rand(1.0)
    let indent = repeat("    ", depth)
    let label = (if g.chance(0.9): "\"" & g.treemapLabel() & "\"" else: "'" & g.treemapLabel() & "'")
    let cls = if classes.len > 0 and g.chance(0.2): ":::" & g.pick(classes) else: ""
    if r < 0.3:
      result.add indent & label & cls
      depth = min(depth + 1, 3)
    elif r < 0.8:
      result.add indent & label & g.pick([": ", ":", " : ", ", ", ","]) & g.treemapValue() & cls
      if g.chance(0.3): depth = max(0, depth - g.rng.rand(1 .. 2))
    elif r < 0.85: result.add "title " & g.pick(labels)
    elif r < 0.88: result.add "accTitle: " & g.pick(labels)
    elif r < 0.91: result.add indent & "%% " & g.pick(labels)
    elif r < 0.985: result.add ""
    else: result.add indent & g.pick(["garbage", "\"x\": ", "\"y\" 5", ":::", "classDef", "\"unterminated"])
    result.add(if g.chance(0.05): "\r\n" else: "\n")

const treeFiles = ["README.md", "index.ts", "main.nim", "Makefile", "package.json", "logo.PNG", ".gitignore",
                   "a.b.c", "notes.txt", "report final.pdf", "x", "日本語.md", "émoji 🎉.png", "data.csv", "test_x.py"]
const treeDirs = ["src/", "docs/", "tests/", "node_modules/", "a b/", "日本/", "build/", "/", "deep/"]
const treeClasses = ["highlight", "dim", "highlight extra", "x-y", "_a"]
const treeIcons = ["", "file", "folder", "none", "mdi:language-typescript", "logos:nim", "rocket", "a-b:c_d"]

proc treeName(g: var Gen, dir: bool): string =
  if g.chance(0.15): return g.pick(labels).replace("\\\"", "").replace("\t", " ")
  if dir: g.pick(treeDirs) else: g.pick(treeFiles)

proc treeEntry(g: var Gen): string =
  let dir = g.chance(0.35)
  var name = g.treeName(dir)
  if name.startsWith("##") or name.startsWith(":::") or name.startsWith("icon(") or name.startsWith("%%"):
    name = "n" & name
  if name == "" or g.chance(0.08): name = "\"" & name & "\""
  elif g.chance(0.02): name = "'" & name & "'"
  result = name
  if g.chance(0.15): result.add g.pick([" ", "  ", "\t"]) & ":::" & g.pick([" ", ""]) & g.pick(treeClasses)
  if g.chance(0.12): result.add " icon(" & g.pick(treeIcons) & ")"
  if g.chance(0.15): result.add " ## " & g.pick(labels)
  if g.chance(0.05): result.add g.pick(["  ", " \t"])

proc treeViewSource(g: var Gen): string =
  if g.chance(0.4):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  treeView:\n"
    if g.chance(0.4): result.add "    showIcons: " & g.pick(["true", "false", "1"]) & "\n"
    if g.chance(0.2): result.add "    defaultIconPack: " & g.pick(["mdi", "logos", "\"\""]) & "\n"
    if g.chance(0.2): result.add "    filenameIcons:\n      README.md: mdi:book\n      Makefile: none\n"
    if g.chance(0.2): result.add "    extensionIcons:\n      .ts: logos:typescript\n      md: mdi:markdown\n      png: \"\"\n"
    for key in ["paddingX", "paddingY", "rowIndent", "lineThickness"]:
      if g.chance(0.15): result.add "    " & key & ": " & g.pick(["0", "1", "2", "5", "10", "30", "0.1", "500", "x"]) & "\n"
    result.add "    useMaxWidth: true\n---\n"
  result.add(if g.chance(0.03): g.pick(["treeView", "treeview-beta", "treeView-beta extra"]) else: "treeView-beta")
  result.add "\n"
  if g.chance(0.2): result.add "title " & g.pick(labels) & "\n"
  if g.chance(0.1): result.add "accTitle: " & g.pick(labels) & "\n"
  if g.chance(0.1): result.add(if g.chance(0.5): "accDescr: " & g.pick(labels) & "\n" else: "accDescr {\n  " & g.pick(labels) & "\n}\n")
  let box = g.chance(0.35)
  let unit = if box: g.pick([4, 4, 3, 2]) else: g.pick([2, 4, 1])
  var depth = 0
  for i in 0 ..< g.rng.rand(0 .. 16):
    let r = g.rng.rand(1.0)
    if r < 0.85:
      if i > 0: depth = max(0, min(depth + g.rng.rand(-2 .. 1), 4))
      if box and depth > 0:
        var prefix = ""
        for d in 1 ..< depth: prefix.add(if g.chance(0.7): "│" & repeat(" ", unit - 1) else: repeat(" ", unit))
        prefix.add(g.pick(["├", "└", "┣", "┗"]) & repeat(g.pick(["─", "━"]), max(1, unit - 2)) & " ")
        if g.chance(0.05): prefix = prefix.replace("    ", "\t")
        result.add prefix & g.treeEntry()
      else:
        result.add repeat(" ", depth * unit) & g.treeEntry()
    elif r < 0.9: result.add repeat(" ", depth * unit) & "%% " & g.pick(labels)
    elif r < 0.93 and box: result.add "│"
    elif r < 0.985: result.add ""
    else: result.add g.pick(["├──", "  indented", "\"unterminated", ":::", "icon(", "Section ─ A.txt", "## x"])
    result.add(if g.chance(0.05): "\r\n" else: "\n")

const outlineDelims = [("[", "]"), ("(", ")"), ("((", "))"), (")", "("), ("))", "(("), ("{{", "}}"), ("(-", "-)"), ("", "")]
const outlineIcons = ["fa fa-book", "mdi:rocket", "logos:nim", ""]
const outlineClasses = ["urgent", "large", "a b", "highlight"]

proc outlineText(g: var Gen): string =
  if g.chance(0.1): return "\"`**bold** and _it_`\""
  if g.chance(0.1): return "\"" & g.pick(labels).replace("\"", "") & "\""
  result = g.pick(labels)
  for bad in ["(", ")", "[", "]", "{", "}", "\"", "\n", "@"]: result = result.replace(bad, "")
  if result == "": result = "x"

proc outlineNode(g: var Gen, kanban: bool): string =
  let (open, close) = g.pick(outlineDelims)
  let id = g.pick(["a", "node1", "Root", "id_2", "x-y", "日本", "Ünï"])
  if open == "":
    result = g.outlineText().replace("\"", "").replace("`", "")
    if result.strip == "" or result.strip.startsWith("%%"): result = id
  else:
    result = (if g.chance(0.7): id else: "") & open & g.outlineText() & close
  if kanban and g.chance(0.3):
    var parts: seq[string]
    if g.chance(0.5): parts.add "ticket: " & g.pick(["MC-2037", "42", "'a b'", "\"x\""])
    if g.chance(0.5): parts.add "assigned: " & g.pick(["'knsv'", "bob", "\"Ann Lee\""])
    if g.chance(0.5): parts.add "priority: " & g.pick(["'High'", "Very High", "low", "'Very Low'", "Medium", "urgent"])
    if g.chance(0.2): parts.add "label: " & g.pick(["'Relabelled'", "new"])
    if g.chance(0.1): parts.add "icon: " & g.pick(["mdi:rocket", "x"])
    if g.chance(0.04): parts.add "shape: " & g.pick(["rect", "Rect", "my_shape"])
    if g.chance(0.03): parts.add g.pick(["[unclosed", "a: : b"])
    result.add(g.pick(["@{ ", "@{"]) & parts.join(", ") & " }")

proc outlineSource(g: var Gen, kanban: bool): string =
  let kind = if kanban: "kanban" else: "mindmap"
  if g.chance(0.4):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  " & kind & ":\n"
    if kanban:
      if g.chance(0.3): result.add "    sectionWidth: " & g.pick(["100", "150", "300", "50", "x"]) & "\n"
      if g.chance(0.3): result.add "    ticketBaseUrl: '" & g.pick(["https://example.com/browse/#TICKET#", "javascript:alert(1)", "/t/#TICKET#"]) & "'\n"
    else:
      if g.chance(0.3): result.add "    maxNodeWidth: " & g.pick(["100", "150", "300", "50", "x", "0"]) & "\n"
    result.add "    useMaxWidth: true\n---\n"
  if g.chance(0.1): result.add "%% a comment\n"
  result.add(if g.chance(0.03): g.pick([kind & "x", kind.toUpperAscii, "  " & kind & " extra"]) else: kind)
  result.add "\n"
  let unit = g.pick([2, 4, 1])
  var depth = 0
  for i in 0 ..< g.rng.rand(0 .. 16):
    let r = g.rng.rand(1.0)
    if r < 0.8:
      if i > 0: depth = max(if kanban: 1 else: 1, min(depth + g.rng.rand(-2 .. 1), if kanban: 2 else: 4))
      if i == 0: depth = (if kanban: 1 else: 0)
      result.add repeat(" ", (depth + 1) * unit) & g.outlineNode(kanban)
    elif r < 0.87: result.add repeat(" ", (depth + 1) * unit) & "::icon(" & g.pick(outlineIcons) & ")"
    elif r < 0.93: result.add repeat(" ", (depth + 1) * unit) & ":::" & g.pick(outlineClasses)
    elif r < 0.96: result.add repeat(" ", depth * unit) & "%% " & g.pick(labels)
    elif r < 0.99: result.add ""
    else: result.add g.pick(["(", "a[b", "::icon(", "\"", "x)y", "@{ a: 1"])
    result.add(if g.chance(0.04): "\r\n" else: "\n")

proc mindmapSource(g: var Gen): string = g.outlineSource(false)
proc kanbanSource(g: var Gen): string = g.outlineSource(true)

const emKinds = ["ui", "cmd", "command", "evt", "event", "rmo", "readmodel", "pcr", "processor"]
const emNames = ["CartUI", "AddItem", "ItemAdded", "Cart.Items", "Inventory.Changed", "X", "a_b", "External.Thing", "Long.Name.Here"]
const emTypes = ["json", "jsobj", "figma", "salt", "uri", "md", "html", "text"]

proc eventmodelingSource(g: var Gen): string =
  if g.chance(0.1): result.add "---\ntitle: " & g.pick(labels) & "\n---\n"
  result.add(if g.chance(0.03): g.pick(["eventmodel", "eventmodeling x"]) else: "eventmodeling")
  result.add "\n"
  if g.chance(0.05): result.add "title " & g.pick(labels) & "\n"
  if g.chance(0.05): result.add "accTitle: " & g.pick(labels) & "\n"
  if g.chance(0.05): result.add "accDescr { " & g.pick(labels) & " }\n"
  var frames = 0
  var dataNames: seq[string]
  let indent = g.pick(["", "  ", "    "])
  for i in 0 ..< g.rng.rand(0 .. 12):
    let r = g.rng.rand(1.0)
    if r < 0.7:
      inc frames
      var line = g.pick(["tf", "timeframe", "tf", "rf", "resetframe"]) & " " &
        (if g.chance(0.95): align($frames, 2, '0') else: $g.rng.rand(1 .. frames)) & " " &
        g.pick(emKinds) & " " & g.pick(emNames)
      if frames > 1 and g.chance(0.2):
        for k in 0 ..< g.rng.rand(1 .. 2): line.add " ->> " & align($g.rng.rand(1 .. frames - 1), 2, '0')
      if g.chance(0.15):
        let name = g.pick(["Data1", "Data2", "Missing"])
        dataNames.add name
        line.add " [[" & name & "]]"
      elif g.chance(0.2):
        line.add(if g.chance(0.3): " `" & g.pick(emTypes) & "`" else: "")
        line.add " " & g.pick(["{ id: 7 }", "{ name: string, price: 20.4 }", "\"quoted text\"", "'single'", "{ \"a\": { \"b\": 1 } }"])
      result.add indent & line
    elif r < 0.78:
      let name = g.pick(["Data1", "Data2"])
      result.add indent & "data " & name & (if g.chance(0.2): " `json`" else: "") & " {\n" & indent & "  description: '" &
        g.pick(["john", "a much longer description that goes past the forty-eight columns of a box"]) & "'\n" & indent & "  price: 20.4\n}"
    elif r < 0.84 and frames > 0:
      result.add indent & "note " & align($g.rng.rand(1 .. frames), 2, '0') & " {\n" & indent & "  " & g.pick(labels) & "\n}"
    elif r < 0.9 and frames > 0:
      result.add indent & "gwt " & align($g.rng.rand(1 .. frames), 2, '0') & " given evt " & g.pick(emNames).replace(".", "") &
        (if g.chance(0.5): " when cmd AddItem" else: "") & " then evt ItemAdded rmo Cart"
    elif r < 0.93: result.add indent & "entity " & g.pick(emNames)
    elif r < 0.96: result.add indent & g.pick(["%% comment", "// comment", "/* block */"])
    elif r < 0.99: result.add ""
    else: result.add indent & g.pick(["tf 01", "tf x ui A", "data X {", "gwt 01 given", "tf 01 ui A [[B", "note 01 { x }"])
    result.add(if g.chance(0.04): "\r\n" else: "\n")
proc ishikawaSource(g: var Gen): string =
  if g.chance(0.2): result.add "---\ntitle: " & g.pick(labels) & "\n---\n"
  if g.chance(0.1): result.add g.pick(["\n", "%% comment\n", "  \n\n", "   %% c\n"])
  result.add(if g.chance(0.03): g.pick(["Ishikawa", "ishikawax", "fishbone"]) elif g.chance(0.3): "ishikawa-beta" else: "ishikawa")
  result.add(if g.chance(0.05): " " else: "")
  result.add "\n"
  var level = 0
  for i in 0 ..< g.rng.rand(0 .. 22):
    let r = g.rng.rand(1.0)
    if i > 0:
      if r < 0.4: level = min(level + 1, 6)
      elif r < 0.7: level = max(level - g.rng.rand(1 .. 3), 1)
    let unit = if g.chance(0.95): g.pick(["  ", "    ", "\t"]) else: g.pick(["\u3000", " ", "\u00a0 "])
    var indent = ""
    for k in 0 ..< level: indent.add unit
    let q = g.rng.rand(1.0)
    if q < 0.85: result.add indent & g.pick(labels)
    elif q < 0.9: result.add indent & "%% " & g.pick(labels)
    elif q < 0.97: result.add ""
    else: result.add indent & g.pick(["ishikawa", "x %% y", "a\tb"])
    result.add(if g.chance(0.05): "\r\n" else: "\n")

const cynefinDomains = ["complex", "complicated", "clear", "chaotic", "confusion"]

proc cynefinSource(g: var Gen): string =
  if g.chance(0.4):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  cynefin:\n"
    if g.chance(0.4): result.add "    seed: " & g.pick(["1", "42", "0", "-7", "1.5", "123456789", "1e16", "x", "99999999999"]) & "\n"
    if g.chance(0.3): result.add "    boundaryAmplitude: " & g.pick(["0", "4", "8", "20", "50", "60", "2.5"]) & "\n"
    if g.chance(0.2): result.add "    showDomainDescriptions: " & g.pick(["false", "true", "0"]) & "\n"
    if g.chance(0.2): result.add "    width: " & g.pick(["100", "300", "640", "1000", "50", "20000"]) & "\n"
    if g.chance(0.2): result.add "    height: " & g.pick(["100", "300", "440", "900", "50"]) & "\n"
    result.add "---\n"
  if g.chance(0.05): result.add "%% comment\n"
  result.add(if g.chance(0.03): g.pick(["cynefin", "Cynefin-beta", "cynefin-betax"]) elif g.chance(0.2): "cynefin-beta:" else: "cynefin-beta")
  result.add "\n"
  for i in 0 ..< g.rng.rand(0 .. 14):
    let indent = g.pick(["", "  ", "    ", "\t"])
    let r = g.rng.rand(1.0)
    let q = if g.chance(0.9): "\"" else: "'"
    if r < 0.45:
      result.add indent & g.pick(cynefinDomains) & "\n"
      for k in 0 ..< g.rng.rand(0 .. 5):
        result.add indent & "  " & q & g.pick(labels) & q & "\n"
    elif r < 0.75:
      result.add indent & g.pick(cynefinDomains) & g.pick([" --> ", "-->", " -->  "]) & g.pick(cynefinDomains)
      if g.chance(0.6): result.add g.pick([" : ", ": ", ":"]) & q & g.pick(labels) & q
    elif r < 0.8: result.add indent & "title " & g.pick(labels)
    elif r < 0.83: result.add indent & "accTitle: " & g.pick(labels)
    elif r < 0.86: result.add indent & "accDescr: " & g.pick(labels)
    elif r < 0.9: result.add indent & "%% " & g.pick(labels)
    elif r < 0.97: result.add ""
    else: result.add indent & g.pick(["complexity", "clear --> ", "x --> clear", "\"loose\"", "chaotic -> clear"])
    result.add(if g.chance(0.05): "\r\n" else: "\n")
const rrWords = ["a", "b", "expr", "term", "digit", "letter", "railroad", "title-x", "_x", "x-1", "nonterminal", "sequence"]
const rrStrings = ["x", "+", "a b", " ", "  ", "<br>", "#35;", "&amp;", "日本", "*", "\\n", "\\\"", "if", "", "very long terminal text here", "'", "tab\\t", "🎉"]
const rrSingle = ["x", "\"", "a b", "it\\'s"]

proc rrTerm(g: var Gen): string =
  ## a quoted string in the style of IR, EBNF and PEG
  if g.chance(0.85): "\"" & g.pick(rrStrings) & "\"" else: "'" & g.pick(rrSingle) & "'"

proc rrIr(g: var Gen, depth: int): string =
  let r = g.rng.rand(1.0)
  if depth <= 0 or r < 0.4:
    case g.rng.rand(2)
    of 0: return "terminal(" & g.rrTerm() & ")"
    of 1: return "nonterminal(\"" & g.pick(rrWords) & "\")"
    else: return "special(\"" & g.pick(["any char", "x", "  "]) & "\")"
  let kind = g.pick(["sequence", "choice", "optional", "oneOrMore", "zeroOrMore", "sequence", "choice"])
  if kind in ["optional", "oneOrMore", "zeroOrMore"]: return kind & "(" & g.rrIr(depth - 1) & ")"
  var parts: seq[string]
  for i in 0 ..< g.rng.rand(1 .. 4): parts.add g.rrIr(depth - 1)
  kind & "(" & parts.join(g.pick([", ", ",", " ,\n  "])) & ")"

proc rrEbnf(g: var Gen, depth: int): string =
  var alts: seq[string]
  for a in 0 ..< (if g.chance(0.4): g.rng.rand(2 .. 4) else: 1):
    var terms: seq[string]
    for t in 0 ..< g.rng.rand(1 .. 4):
      var term = ""
      let r = g.rng.rand(1.0)
      if depth > 0 and r < 0.25:
        let (o, c) = g.pick([("(", ")"), ("[", "]"), ("{", "}")])
        term = o & " " & g.rrEbnf(depth - 1) & " " & c
      elif r < 0.55: term = g.rrTerm()
      elif r < 0.9: term = g.pick(rrWords)
      else: term = "? " & g.pick(["any char", "x", "日本"]) & " ?"
      if g.chance(0.25): term.add g.pick(["?", "*", "+", "*?", "+"])
      if g.chance(0.08): term.add " - " & g.pick(["\"x\"", "letter", "( a | b )"])
      terms.add term
    alts.add terms.join(g.pick([", ", " ", " , "]))
  alts.join(g.pick([" | ", "\n  | "]))

proc rrAbnf(g: var Gen, depth: int): string =
  var alts: seq[string]
  for a in 0 ..< (if g.chance(0.4): g.rng.rand(2 .. 4) else: 1):
    var elems: seq[string]
    for t in 0 ..< g.rng.rand(1 .. 4):
      var e = if g.chance(0.3): g.pick(["*", "1*", "*3", "2*5", "3", "0*1", "1*1", "12", "99999999999999999999999*"]) else: ""
      let r = g.rng.rand(1.0)
      if depth > 0 and r < 0.25:
        let (o, c) = g.pick([("(", ")"), ("[", "]")])
        e.add o & g.rrAbnf(depth - 1) & c
      elif r < 0.5: e.add "\"" & g.pick(["x", "a b", "<br>", "", "日本", "\\"]) & "\""
      elif r < 0.65: e.add g.pick(["%x41-5A", "%d13.10", "%b0101", "%x20"])
      else: e.add g.pick(["ALPHA", "DIGIT", "rule-1", "a", "expr"])
      elems.add e
    alts.add elems.join(" ")
  alts.join(g.pick([" / ", "\n  / "]))

proc rrPeg(g: var Gen, depth: int): string =
  var alts: seq[string]
  for a in 0 ..< (if g.chance(0.4): g.rng.rand(2 .. 4) else: 1):
    var items: seq[string]
    for t in 0 ..< g.rng.rand(1 .. 4):
      var item = if g.chance(0.15): g.pick(["&", "!"]) else: ""
      let r = g.rng.rand(1.0)
      if depth > 0 and r < 0.25: item.add "(" & g.rrPeg(depth - 1) & ")"
      elif r < 0.55: item.add g.rrTerm()
      elif r < 0.9: item.add g.pick(rrWords)
      else: item.add "."
      if g.chance(0.25): item.add g.pick(["?", "*", "+"])
      items.add item
    alts.add items.join(" ")
  alts.join(g.pick([" / ", "\n  / "]))

proc railroadSource(g: var Gen): string =
  ## The four notations, mostly valid, with a broken rule now and then.
  if g.chance(0.3):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(["Grammar", "日本", "A long title for a grammar diagram"]) & "\n"
    result.add "config:\n  railroad:\n"
    for key in ["fontSize", "padding", "horizontalSeparation", "verticalSeparation", "arcRadius", "markerRadius", "strokeWidth"]:
      if g.chance(0.2): result.add "    " & key & ": " & g.pick(["0", "4", "10", "24", "-1", "1000", "x", "2.5"]) & "\n"
    if g.chance(0.2): result.add "    showMarkers: " & g.pick(["false", "true", "0"]) & "\n"
    result.add "---\n"
  let notation = g.pick(["railroad", "ebnf", "abnf", "peg"])
  let keyword = if notation == "railroad": "railroad-beta" else: "railroad-" & notation & "-beta"
  result.add(if g.chance(0.03): g.pick(["Railroad-Beta", "railroad-betax", "railroad"]) else: keyword)
  result.add "\n"
  if g.chance(0.2): result.add g.pick(["title Grammar", "title \"Quoted title\"", "title", "title 'x\\ty'", "title a %% c"]) & "\n"
  if g.chance(0.1): result.add "accTitle: Rules\n"
  if g.chance(0.1): result.add g.pick(["accDescr: A grammar\n", "accDescr {\n  many\n   lines\n}\n"])
  if g.chance(0.05): result.add g.pick(["%% comment\n", "/* block */\n", "# hash\n", "(* iso *)\n", "; abnf comment\n"])
  for i in 0 ..< g.rng.rand(1 .. 5):
    let name = g.pick(["expr", "term", "digit", "a", "rule-1", "x_y", "letter"])
    let depth = g.rng.rand(0 .. 3)
    var line = case notation
      of "railroad": name & " = " & g.rrIr(depth) & ";"
      of "ebnf": name & g.pick([" = ", " ::= "]) & g.rrEbnf(depth) & " ;"
      of "abnf": name & " = " & g.rrAbnf(depth) & ";"
      else: name & " <- " & g.rrPeg(depth) & ";"
    if g.chance(0.04): line = line[0 ..< line.len - 1]
    if g.chance(0.03): line.add g.pick([" )", " junk", " =", " ; trailing"])
    result.add line & "\n"

proc ganttDate(g: var Gen, fmt: string, y, m, d, h, mi: int): string =
  ## A date written in the chart's format, with a slip now and then.
  let p2 = proc (n: int): string = (if n < 10: "0" & $n else: $n)
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  case fmt
  of "DD/MM/YYYY": p2(d) & "/" & p2(m) & "/" & $y
  of "YYYY-MM-DD HH:mm": $y & "-" & p2(m) & "-" & p2(d) & " " & p2(h) & ":" & p2(mi)
  of "HH:mm": p2(h) & ":" & p2(mi)
  of "X": $(1767225600 + (d - 1) * 86400 + h * 3600)
  of "x": $(1767225600000 + (d - 1) * 86400000 + h * 3600000)
  of "MMM D YYYY": months[m - 1] & " " & $d & " " & $y
  of "YYYY": $(y + d)
  of "D": $d
  of "YYYY-MM-DDTHH:mm:ssZ": $y & "-" & p2(m) & "-" & p2(d) & "T" & p2(h) & ":" & p2(mi) & ":00+00:00"
  else: $y & "-" & p2(m) & "-" & p2(d)

proc ganttSource(g: var Gen): string =
  ## Mostly valid charts: dates in the chart's format, references to earlier tasks, durations,
  ## exclusions and tick intervals, with a broken line now and then.
  if g.chance(0.3):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(["Plan", "日本", "A long plan title"]) & "\n"
    result.add "config:\n  gantt:\n"
    for key in ["fontSize", "sectionFontSize", "barHeight", "barGap", "numberSectionStyles", "leftPadding",
                "rightPadding", "useWidth", "topPadding", "gridLineStartPadding"]:
      if g.chance(0.12): result.add "    " & key & ": " & g.pick(["0", "4", "12", "30", "75", "200", "900", "x", "-5"]) & "\n"
    if g.chance(0.15): result.add "    topAxis: " & g.pick(["true", "false"]) & "\n"
    if g.chance(0.15): result.add "    displayMode: " & g.pick(["compact", "\"\"", "other"]) & "\n"
    if g.chance(0.1): result.add "    axisFormat: \"" & g.pick(["%d %b", "%H:%M", "%Y"]) & "\"\n"
    if g.chance(0.1): result.add "    tickInterval: " & g.pick(["1day", "1week", "2month", "x"]) & "\n"
    if g.chance(0.1): result.add "    weekday: " & g.pick(["monday", "friday", "nope"]) & "\n"
    result.add "---\n"
  result.add(if g.chance(0.03): g.pick(["Gantt", "gantt2", "gant"]) else: "gantt")
  result.add "\n"
  let fmt = if g.chance(0.65): "YYYY-MM-DD"
            else: g.pick(["DD/MM/YYYY", "YYYY-MM-DD HH:mm", "HH:mm", "X", "x", "MMM D YYYY", "YYYY", "D",
                          "YYYY-MM-DDTHH:mm:ssZ", "Do MMMM YYYY", "YYYY-MM-DD ww", "LL"])
  if fmt != "YYYY-MM-DD" or g.chance(0.5): result.add "  dateFormat " & fmt & "\n"
  if g.chance(0.3): result.add "  title " & g.pick(["Project plan", "日本", "x  y", "title"]) & "\n"
  if g.chance(0.25):
    result.add "  axisFormat " & g.pick(["%Y-%m-%d", "%b %d", "%e %B", "%H:%M", "%a %d", "%W", "%j", "%U", "%V",
                                         "%G-W%V", "%x", "%-d/%-m", "%c", "%%", "%q", "%I %p", "%s", "%Z"]) & "\n"
  if g.chance(0.2):
    result.add "  tickInterval " & g.pick(["1day", "2day", "1week", "1month", "6hour", "15minute", "1year", "0day",
                                           "30second", "500millisecond", "3week", "day"]) & "\n"
  if g.chance(0.15): result.add "  weekday " & g.pick(["monday", "sunday", "friday", "Wednesday"]) & "\n"
  if g.chance(0.15): result.add "  excludes " & g.pick(["weekends", "weekends, 2026-01-07", "monday sunday",
                                                         "2026-01-05", "Weekends", "friday"]) & "\n"
  if g.chance(0.08): result.add "  includes " & g.pick(["2026-01-10", "saturday", "2026-01-03, 2026-01-04"]) & "\n"
  if g.chance(0.08): result.add "  weekend " & g.pick(["friday", "saturday"]) & "\n"
  if g.chance(0.1): result.add "  todayMarker " & g.pick(["off", "stroke-width:5px,stroke:#0f0,opacity:0.5", "on"]) & "\n"
  if g.chance(0.08): result.add "  inclusiveEndDates\n"
  if g.chance(0.05): result.add "  topAxis\n"
  if g.chance(0.05): result.add "  accTitle: Plan\n  accDescr: A plan\n"
  if g.chance(0.04): result.add g.pick(["  %% note\n", "  % one\n", "  accDescr {\n many\n }\n"])
  var ids: seq[string]
  let year = g.pick([2026, 2026, 2025, 1999, 2014])
  let month = g.rng.rand(1 .. 12)
  for s in 0 ..< g.rng.rand(1 .. 3):
    if s > 0 or g.chance(0.7): result.add "  section " & g.pick(["Design", "Build", "日本", "Test & ship", "a<br>b"]) & "\n"
    for t in 0 ..< g.rng.rand(1 .. 5):
      var data: seq[string]
      if g.chance(0.3): data.add g.pick(["done", "active", "crit", "milestone", "crit, done", "active, crit", "vert"])
      let hasId = g.chance(0.5)
      let id = "t" & $(ids.len + 1)
      let r = g.rng.rand(1.0)
      var start = ""
      if ids.len > 0 and r < 0.3:
        start = "after " & g.pick(ids) & (if g.chance(0.2): " " & g.pick(ids) else: "")
      elif r < 0.75:
        start = g.ganttDate(fmt, year, month, g.rng.rand(1 .. 28), g.rng.rand(0 .. 23), g.rng.rand(0 .. 59))
      elif r < 0.8:
        start = g.pick(["2026-01-05", "Jan 5, 2026", "01/05/2026", "2026/1/5 10:00", "bad date", "after nope"])
      let stop = if ids.len > 0 and g.chance(0.1): "until " & g.pick(ids)
                 elif g.chance(0.6): g.pick(["3d", "1w", "2h", "30m", "1M", "1y", "0.5d", "10s", "100ms", "5d", "12h", "2d", "0d", "x"])
                 else: g.ganttDate(fmt, year, month, g.rng.rand(1 .. 28), g.rng.rand(0 .. 23), g.rng.rand(0 .. 59))
      if hasId:
        data.add id
        ids.add id
        if start == "": start = g.ganttDate(fmt, year, month, 1, 9, 0)
      if start != "": data.add start
      data.add stop
      let name = g.pick(["Research", "Write code", "Review", "日本語", "A task with a long name", "x", "Ship it",
                         "a<br>b", "  spaced  "])
      var line = "    " & name & " :" & data.join(", ")
      if g.chance(0.03): line = "    " & name
      if g.chance(0.02): line.add ", extra, fields, here"
      result.add line & "\n"
  if ids.len > 0 and g.chance(0.1):
    result.add "  click " & g.pick(ids) & g.pick([" href \"https://example.com\"", " call cb()", " call cb(1) href \"x\""]) & "\n"

const wardleyNames = ["User", "Web Site", "Customer Service", "Cup of Tea", "Tea", "Kettle", "Power", "Hot Water",
                      "Data-Store", "A&B", "x_1", "Compute (cloud)", "Business", "Public", "CRM", "a", "Z9"]
const wardleyOddNames = ["\"Quoted name\"", "\"日本語\"", "'single'", "title x", "note", "component", "build",
                         "-dash", "9lives", "a->b", "\"\""]
const wardleyDecimals = ["0.1", "0.95", "0.5", "0.33", "0.79", "0.62", "0.05", "1.0", "0.0", "0.99", "0.25",
                         "45.5", "100.0", "0.001", "0.85", "0.15", "0.71", "0.45"]
const wardleyBadDecimals = ["100.5", "5", "1", "0", "-0.5", "1e2", ".5"]
const wardleyInts = ["0", "5", "10", "-5", "-10", "20", "100", "1", "3", "2"]
const wardleyArrows = [" -> ", " -> ", "->", " --> ", " -.-> ", " > ", " +'flows'> ", " +'back'< ", " +'both'<> ",
                       " +'' > ", " +<> ", " +> ", " +< "]

proc wardleySource(g: var Gen): string =
  proc decimal(g: var Gen): string =
    if g.chance(0.02): g.pick(wardleyBadDecimals) else: g.pick(wardleyDecimals)
  proc coords(g: var Gen): string =
    "[" & g.decimal & (if g.chance(0.8): ", " else: ",") & g.decimal & "]"
  if g.chance(0.3):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  wardley-beta:\n"
    if g.chance(0.4): result.add "    showGrid: " & g.pick(["true", "false", "1"]) & "\n"
    if g.chance(0.3): result.add "    width: " & g.pick(["300", "640", "900", "1200", "50", "20000"]) & "\n"
    if g.chance(0.3): result.add "    height: " & g.pick(["200", "400", "600", "900", "x"]) & "\n"
    result.add "---\n"
  if g.chance(0.05): result.add "%% comment\n"
  result.add(if g.chance(0.03): g.pick(["wardley", "Wardley-beta", "wardley-betax"]) else: "wardley-beta")
  result.add "\n"
  var declared: seq[string]
  proc newName(g: var Gen): string =
    if g.chance(0.05): return g.pick(wardleyOddNames)
    result = g.pick(wardleyNames)
    if g.chance(0.3): result.add " " & g.pick(["One", "Two", "B", "x2", "(v2)"])
  proc known(g: var Gen): string =
    if declared.len == 0 or g.chance(0.05): g.newName() else: g.pick(declared)
  for i in 0 ..< g.rng.rand(0 .. 18):
    let indent = g.pick(["", "  ", "    ", "\t"])
    let r = g.rng.rand(1.0)
    if r < 0.3:
      let n = g.newName()
      declared.add n
      result.add indent & "component " & n & " " & g.coords
      if g.chance(0.25): result.add " label [" & g.pick(wardleyInts) & ", " & g.pick(wardleyInts) & "]"
      if g.chance(0.2): result.add " (" & g.pick(["build", "buy", "outsource", "market"]) & ")"
      if g.chance(0.1): result.add g.pick([" inertia", " (inertia)"])
    elif r < 0.38:
      let n = g.newName()
      declared.add n
      result.add indent & "anchor " & n & " " & g.coords
    elif r < 0.58:
      result.add indent & g.known() & g.pick(wardleyArrows) & g.known()
      if g.chance(0.2): result.add g.pick(["; label", ";limited by", "; 日本"])
    elif r < 0.63:
      result.add indent & "evolve " & g.known() & " " & g.decimal
    elif r < 0.68 and declared.len > 0:
      result.add indent & "pipeline " & g.pick(declared) & " {\n"
      for k in 0 ..< g.rng.rand(1 .. 4):
        let n = g.newName()
        result.add indent & "  component " & n & " [" & g.decimal & "]"
        if g.chance(0.2): result.add " label [" & g.pick(wardleyInts) & ", " & g.pick(wardleyInts) & "]"
        result.add "\n"
      result.add indent & "}"
    elif r < 0.72:
      result.add indent & "note \"" & g.pick(labels).replace("\"", "") & "\" " & g.coords
    elif r < 0.76:
      result.add indent & "annotation " & $g.rng.rand(1 .. 12) & "," & "[" & g.pick(@wardleyDecimals & @["1", "0", "50"]) &
        ", " & g.pick(wardleyDecimals) & "] \"" & g.pick(labels).replace("\"", "") & "\""
    elif r < 0.78:
      result.add indent & "annotations [" & g.pick(["0.1", "0.9", "5", "0.5"]) & ", " & g.pick(["0.1", "0.9", "50", "0.5"]) & "]"
    elif r < 0.82:
      result.add indent & g.pick(["accelerator ", "deaccelerator "]) & g.newName() & " " & g.coords
    elif r < 0.85:
      result.add indent & "evolution " & g.pick(["Genesis", "Uncharted"]) &
        (if g.chance(0.4): "@" & g.pick(["0.25", "0.2", "0.5"]) else: "") & " -> " &
        g.pick(["Custom", "Custom Built", "Emerging"]) & (if g.chance(0.4): "@" & g.pick(["0.5", "0.45"]) else: "") &
        (if g.chance(0.6): " -> Product" & (if g.chance(0.4): "@0.75" else: "") & " -> Commodity" &
          (if g.chance(0.4): "@1.0" else: "") else: "") & (if g.chance(0.2): " / Utility" else: "")
    elif r < 0.87:
      result.add indent & "size [" & g.pick(["400", "800", "1100", "100", "20000"]) & ", " & g.pick(["300", "600", "800"]) & "]"
    elif r < 0.9: result.add indent & "title " & g.pick(labels)
    elif r < 0.92: result.add indent & "accTitle: " & g.pick(labels)
    elif r < 0.94: result.add indent & "accDescr: " & g.pick(labels)
    elif r < 0.96: result.add indent & "%% " & g.pick(labels)
    elif r < 0.98: result.add ""
    else: result.add indent & g.pick(["component", "anchor X [1, 2]", "evolve", "pipeline X {", "}", "size [1.5, 2]", "@"])
    result.add(if g.chance(0.03): "\r\n" else: "\n")

const archIds = ["api", "db", "disk1", "server", "gateway", "cache", "web", "queue", "auth", "store", "a", "b_2", "x-y",
                 "edge9"]
const archIcons = ["(database)", "(server)", "(disk)", "(internet)", "(cloud)", "(logos:aws)", "(mdi-home)", "(unknown)"]
const archTitles = ["[API]", "[Database]", "[My Server]", "[\"Quoted title\"]", "['single \\' quote']", "[日本語]",
                    "[a very long title that will need to wrap somewhere]", "[  spaced  ]", "[x]", "[**bold**]",
                    "[emoji 🎉 here]", "[\"\"]"]
const archIconTexts = ["\"PG\"", "\"Postgres database cluster\"", "\"🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉\"", "\"a\"", "\"日本語のテキストです長い\"",
                       "\"one two three four five six seven eight nine ten\""]
const archSides = ['L', 'R', 'T', 'B']

proc architectureSource(g: var Gen): string =
  if g.chance(0.25):
    result.add "---\n"
    if g.chance(0.3): result.add "title: " & g.pick(labels) & "\n"
    result.add "config:\n  architecture:\n"
    if g.chance(0.4): result.add "    iconSize: " & g.pick(["24", "48", "80", "4", "600", "x"]) & "\n"
    if g.chance(0.3): result.add "    fontSize: " & g.pick(["10", "16", "22", "2"]) & "\n"
    if g.chance(0.3): result.add "    padding: " & g.pick(["0", "10", "40", "300"]) & "\n"
    result.add "---\n"
  if g.chance(0.05): result.add "%% comment\n"
  result.add(if g.chance(0.03): g.pick(["architecture", "Architecture-beta", "architecture-betax"]) else: "architecture-beta")
  result.add "\n"
  var groups, nodes: seq[string]
  var used: seq[string]
  proc fresh(g: var Gen): string =
    for t in 0 ..< 5:
      let id = (if g.chance(0.01): g.pick(["Lb", "Rx", "Top"]) else: g.pick(archIds)) &
        (if g.chance(0.3): $g.rng.rand(1 .. 9) else: "")
      if id notin used or g.chance(0.02):
        used.add id
        return id
    "n" & $used.len
  for i in 0 ..< g.rng.rand(0 .. 3):
    let id = g.fresh()
    result.add "  group " & id
    if g.chance(0.5): result.add g.pick(archIcons)
    if g.chance(0.8): result.add g.pick(archTitles)
    if groups.len > 0 and g.chance(0.4): result.add " in " & g.pick(groups)
    groups.add id
    result.add "\n"
  for i in 0 ..< g.rng.rand(0 .. 9):
    let id = g.fresh()
    if g.chance(0.85):
      result.add "  service " & id
      let r = g.rng.rand(1.0)
      if r < 0.5: result.add g.pick(archIcons)
      elif r < 0.7: result.add g.pick(archIconTexts)
      if g.chance(0.8): result.add g.pick(archTitles)
    else:
      result.add "  junction " & id
    if groups.len > 0 and g.chance(0.5): result.add " in " & g.pick(groups)
    nodes.add id
    result.add "\n"
  for i in 0 ..< g.rng.rand(0 .. 10):
    let r = g.rng.rand(1.0)
    if r < 0.75 and nodes.len > 0:
      let a = if g.chance(0.97): g.pick(nodes) else: g.pick(@["nope"] & groups)
      let b = if g.chance(0.97): g.pick(nodes) else: g.pick(@["nope"] & groups)
      result.add "  " & a & (if groups.len > 0 and g.chance(0.06): "{group}" else: "") & ":" & g.pick(archSides) &
        (if g.chance(0.2): " <" else: " ") &
        (if g.chance(0.25): "-" & g.pick(archTitles) & "-" else: "--") &
        (if g.chance(0.3): "> " else: " ") & g.pick(archSides) & ":" & b &
        (if groups.len > 0 and g.chance(0.06): "{group}" else: "")
    elif r < 0.85 and nodes.len > 1:
      result.add "  align " & g.pick(["row", "column"])
      var members: seq[string]
      for k in 0 ..< g.rng.rand(2 .. 4):
        let m = g.pick(nodes)
        if m notin members or g.chance(0.05): members.add m
      for m in members: result.add " " & m
    elif r < 0.88: result.add "  title " & g.pick(labels)
    elif r < 0.9: result.add "  accTitle: " & g.pick(labels)
    elif r < 0.92: result.add "  accDescr: " & g.pick(labels)
    elif r < 0.95: result.add "  %% " & g.pick(labels)
    elif r < 0.97: result.add ""
    else: result.add "  " & g.pick(["service", "group g in", "a:Q -- L:b", "align diagonal a b", "junction"])
    result.add(if g.chance(0.03): "\r\n" else: "\n")

const
  c4Headers = ["C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment"]
  c4Shapes = ["Person", "Person_Ext", "System", "SystemDb", "SystemQueue", "System_Ext",
    "SystemDb_Ext", "SystemQueue_Ext", "Container", "ContainerDb", "ContainerQueue",
    "Container_Ext", "ContainerDb_Ext", "ContainerQueue_Ext", "Component", "ComponentDb",
    "ComponentQueue", "Component_Ext", "ComponentDb_Ext", "ComponentQueue_Ext"]
  c4Boundaries = ["Enterprise_Boundary", "System_Boundary", "Boundary", "Container_Boundary",
    "Deployment_Node", "Node", "Node_L", "Node_R"]
  c4Rels = ["Rel", "BiRel", "Rel_Up", "Rel_U", "Rel_Down", "Rel_D", "Rel_Left", "Rel_L",
    "Rel_Right", "Rel_R", "Rel_Back", "RelIndex"]
  c4Ids = ["a", "b", "web", "db", "api", "customer", "spa", "q", "global", "x1", "Ünï"]
  c4Texts = ["Web App", "Uses", "Reads from", "JSON/HTTPS", "Java, Spring", "a b c", "",
    "Ünïcödé", "日本語", "emoji 🎉", "x&amp;y", "#35; hash", "very long description that goes on and on and wraps",
    "fa:fa-car", "<b>b</b>", "a\\nb", "semi; colon", "x#y"]
  c4Keys = ["descr", "techn", "sprite", "tags", "link", "label", "type", "bgColor", "fontColor",
    "borderColor", "shape", "offsetX", "offsetY", "textColor", "lineColor", "alias", "legendText", "nope"]
  c4Values = ["red", "#ff8800", "rgba(0,0,0,0.2)", "person", "database", "queue", "pipe", "rounded",
    "box", "cylinder", "db", "component", "tag1,queue", "https://example.com", "javascript:alert(1)",
    "-40", "20", "abc", "3", "0", "x"]

proc c4Attr(g: var Gen, ids: seq[string], last = false): string =
  # An unquoted value runs to the next comma, through `)` and line breaks: rare in last place.
  let r = if last and g.chance(0.95): g.rng.rand(0.6) else: g.rng.rand(1.0)
  if r < 0.12: "$" & g.pick(c4Keys) & "=\"" & g.pick(c4Values) & "\""
  elif r < 0.17: ""
  elif r < 0.6: "\"" & g.pick(c4Texts) & "\""
  elif r < 0.66: g.pick(c4Values)
  elif r < 0.7: "\"" & g.pick(c4Values) & "\""
  else: g.pick(c4Texts)

proc c4Args(g: var Gen, first: string, count: int, ids: seq[string]): string =
  result = "(" & first
  for i in 0 ..< count: result.add (if g.chance(0.1): "," else: ", ") & g.c4Attr(ids, i == count - 1)
  if g.chance(0.15) or (count == 0 and g.chance(0.9)):
    result.add ", $" & g.pick(c4Keys) & "=\"" & g.pick(c4Values) & "\""
  result.add(if g.chance(0.02): "" else: ")")

proc c4Source(g: var Gen): string =
  if g.chance(0.1): result.add "---\ntitle: " & g.pick(labels) & "\n---\n"
  if g.chance(0.05): result.add "%% comment\n"
  result.add(if g.chance(0.02): g.pick(["C4context", "C4", "c4Context"]) else: g.pick(c4Headers))
  result.add "\n"
  var ids: seq[string]
  var depth = 0
  proc id(g: var Gen): string =
    if ids.len > 0 and g.chance(0.15): g.pick(ids)
    else: g.pick(c4Ids) & (if g.chance(0.5): $g.rng.rand(1 .. 20) else: "")
  var opened = false
  for i in 0 ..< g.rng.rand((if g.chance(0.02): 0 else: 1) .. 14):
    let indent = repeat("  ", depth)
    # The first statement in a boundary is a shape, almost always.
    let r = if opened and g.chance(0.97): g.rng.rand(0.39) else: g.rng.rand(1.0)
    opened = false
    if r < 0.4:
      let alias = if g.chance(0.04): "$alias=\"" & g.pick(c4Ids) & "\"" else: g.id()
      result.add indent & g.pick(c4Shapes) & g.c4Args(alias, g.rng.rand(0 .. 5), ids)
      ids.add alias
    elif r < 0.55 and depth < 4:
      let alias = g.id()
      result.add indent & g.pick(c4Boundaries) & g.c4Args(alias, g.rng.rand(0 .. 4), ids)
      let r2 = g.rng.rand(1.0)
      result.add(if r2 < 0.85: "{" elif r2 < 0.97: "\n" & indent & "{" else: " {")
      ids.add alias
      inc depth
      opened = true
    elif r < 0.62 and depth > 0:
      dec depth
      result.add repeat("  ", depth) & "}"
    elif r < 0.84 and ids.len > 0:
      let rel = g.pick(c4Rels)
      var args = "(" & (if rel == "RelIndex": $g.rng.rand(1 .. 9) & ", " else: "") & g.pick(ids) & ", " &
        (if g.chance(0.98): g.pick(ids) else: "nope")
      let count = g.rng.rand((if g.chance(0.95): 1 else: 0) .. 4)
      for k in 0 ..< count: args.add ", " & g.c4Attr(ids, k == count - 1)
      if g.chance(0.1) or (count == 0 and g.chance(0.9)): args.add ", $" & g.pick(c4Keys) & "=\"" & g.pick(c4Values) & "\""
      result.add indent & rel & args & ")"
    elif r < 0.875 and ids.len > 0:
      result.add indent & "UpdateElementStyle(" & g.pick(ids)
      for k in 0 ..< g.rng.rand(1 .. 3):
        result.add ", $" & g.pick(["bgColor", "fontColor", "borderColor", "shape", "sprite", "techn", "legendText"]) &
          "=\"" & g.pick(c4Values) & "\""
      result.add ")"
    elif r < 0.9 and ids.len > 1:
      result.add indent & "UpdateRelStyle(" & g.pick(ids) & ", " & g.pick(ids)
      for k in 0 ..< g.rng.rand(1 .. 3):
        result.add ", $" & g.pick(["textColor", "lineColor", "offsetX", "offsetY"]) & "=\"" & g.pick(c4Values) & "\""
      result.add ")"
    elif r < 0.91:
      result.add indent & "UpdateLayoutConfig(" &
        (if g.chance(0.5): "$c4ShapeInRow=\"" & g.pick(["1", "2", "3", "6", "0", "x"]) & "\""
         else: g.pick(["1", "2", "3"])) &
        (if g.chance(0.5): ", $c4BoundaryInRow=\"" & g.pick(["1", "2", "3", "0"]) & "\"" else: "") & ")"
    elif r < 0.93: result.add indent & "title " & g.pick(labels)
    elif r < 0.94: result.add indent & "accTitle: " & g.pick(labels)
    elif r < 0.95: result.add indent & "accDescr: " & g.pick(labels)
    elif r < 0.955: result.add indent & "accDescr {\n  " & g.pick(labels) & "\n  more\n}"
    elif r < 0.96: result.add indent & "direction " & g.pick(["TB", "LR", "BT", "RL"])
    elif r < 0.975: result.add indent & "%% " & g.pick(labels)
    elif r < 0.993: result.add ""
    else: result.add indent & g.pick(["Person", "Rel(a)", "System(a, \"b\"", "}", "Foo(a)", "title"])
    result.add(if g.chance(0.03): "\r\n" else: "\n")
  while depth > 0 and g.chance(0.95):
    dec depth
    result.add repeat("  ", depth) & "}\n"

const
  blockIds = ["a", "b", "c", "db", "id1", "root", "x", "Ünï", "blockArrowId", "B2", "e"]
  blockShapes = [("[", "]"), ("(", ")"), ("((", "))"), (">", "]"), ("{", "}"), ("{{", "}}"),
    ("([", "])"), ("[[", "]]"), ("[(", ")]"), ("(((", ")))"), ("[/", "/]"), ("[\\", "\\]"),
    ("[/", "\\]"), ("[\\", "/]")]
  blockLinks = ["-->", "---", "==>", "-.->", "--x", "--o", "<-->", "x--x", "o--o", "===", "-.-", "...->"]
  blockDirs = ["right", "left", "up", "down", "x", "y", " up ", "right, down"]
  blockStyles = ["fill:#969", "stroke:#333,stroke-width:4px", "fill:#f9f,color:red", "font-weight:bold",
    "fill:none", "color:#fff;fill:#000", "stroke-dasharray: 5 5", "font-size:20px", "font-style:italic"]

proc blockSource(g: var Gen): string =
  if g.chance(0.1): result.add "---\ntitle: " & g.pick(labels) & "\n" &
    (if g.chance(0.5): "config:\n  block:\n    padding: " & g.pick(["0", "4", "30", "300", "x"]) & "\n" else: "") & "---\n"
  if g.chance(0.05): result.add "%% comment\n"
  result.add(if g.chance(0.02): g.pick(["blocks", "Block", "block-betax"]) elif g.chance(0.5): "block" else: "block-beta")
  result.add "\n"
  var ids: seq[string]
  var depth = 0
  var opened = false
  proc id(g: var Gen): string =
    if ids.len > 0 and g.chance(0.3): g.pick(ids)
    else: g.pick(blockIds) & (if g.chance(0.5): $g.rng.rand(1 .. 30) else: "")
  proc node(g: var Gen): string =
    let name = g.id()
    ids.add name
    let r = g.rng.rand(1.0)
    if r < 0.45: name
    elif r < 0.9:
      let (a, b) = g.pick(blockShapes)
      name & a & "\"" & g.pick(labels) & "\"" & b
    else:
      var dirs = g.pick(blockDirs)
      if g.chance(0.2): dirs.add ", " & g.pick(blockDirs)
      name & "<[\"" & g.pick(labels) & "\"]>(" & dirs & ")"
  for i in 0 ..< g.rng.rand((if g.chance(0.03): 0 else: 1) .. 16):
    let indent = repeat("  ", depth + 1)
    let r = if opened and g.chance(0.95): g.rng.rand(0.44) else: g.rng.rand(1.0)
    opened = false
    if r < 0.45:
      var line = g.node()
      if g.chance(0.15): line.add ":" & $g.rng.rand(1 .. 4)
      for k in 0 ..< (if g.chance(0.3): g.rng.rand(1 .. 3) else: 0):
        if g.chance(0.25): line.add " -- \"" & g.pick(labels) & "\" " & g.pick(["-->", "---", "==>"]) & " "
        else: line.add " " & g.pick(blockLinks) & " "
        line.add g.node()
      if g.chance(0.2):
        line.add " " & g.node()
      result.add indent & line
    elif r < 0.55 and depth < 4:
      result.add indent & (if g.chance(0.6): "block" else: "block:" & g.node())
      inc depth
      opened = true
    elif r < 0.65 and depth > 0:
      dec depth
      result.add repeat("  ", depth + 1) & "end"
    elif r < 0.72: result.add indent & "columns " & g.pick(["1", "2", "3", "4", "auto", "0", "10"])
    elif r < 0.78: result.add indent & (if g.chance(0.5): "space" else: "space:" & $g.rng.rand(1 .. 4))
    elif r < 0.82: result.add indent & "classDef " & g.pick(["hot", "cold", "default"]) & " " & g.pick(blockStyles)
    elif r < 0.86 and ids.len > 0:
      result.add indent & "class " & g.pick(ids) & (if g.chance(0.3): "," & g.pick(ids) else: "") & " " &
        g.pick(["hot", "cold", "nope"])
    elif r < 0.9 and ids.len > 0:
      result.add indent & "style " & g.pick(ids) & " " & g.pick(blockStyles)
    elif r < 0.92 and ids.len > 1:
      result.add indent & g.pick(ids) & " " & g.pick(blockLinks) & " " & g.pick(ids)
    elif r >= 0.92 and r < 0.933: result.add indent & "accTitle: " & g.pick(labels)
    elif r >= 0.933 and r < 0.936: result.add indent & "accDescr: " & g.pick(labels)
    elif r >= 0.936 and r < 0.96: result.add indent & "%% " & g.pick(labels)
    elif r >= 0.96 and r < 0.99: result.add ""
    elif r >= 0.99: result.add indent & g.pick(["a[\"x\"", "end", "columns", "block:", "a --> ", "x(\"y\"]", "space:-1"])
    else: result.add indent & g.node()
    result.add(if g.chance(0.03): "\r\n" else: "\n")
  if opened and g.chance(0.95): result.add repeat("  ", depth + 1) & g.node() & "\n"
  while depth > 0 and g.chance(0.98):
    dec depth
    result.add repeat("  ", depth + 1) & "end\n"

proc options(g: var Gen): JsonNode =
  result = newJObject()
  if g.chance(0.3): result["fontSize"] = %g.pick([12, 14, 16, 18, 20, 11])
  if g.chance(0.2): result["padding"] = %g.pick([0, 4, 8, 16])
  if g.chance(0.3): result["maxWidth"] = %g.pick([200, 300, 320, 390, 500, 640, 100, 800, 1200])
  if g.chance(0.05): result["autoDirection"] = %g.chance(0.5)
  if g.chance(0.05): result["directionBreakpoint"] = %g.pick([0, 400, 1000])
  if g.chance(0.1): result["idPrefix"] = %g.pick(["x", "my-id", "a\"b"])
  if g.chance(0.1): result["responsive"] = %g.chance(0.5)
  if g.chance(0.05): result["monospace"] = %[g.pick(["files", "members", "attributes", "messages"])]
  if g.chance(0.05): result["fontFamily"] = %g.pick(["Inter", "\"Fira Sans\", sans-serif", "bad;font", "Times New Roman"])

proc main() =
  var kind = ""
  var count = 1000
  var seed = 1
  var show = 10
  var packageArg = ""
  var js = false
  var hosts = false   ## --hosts: every case gets the test icons and typesetter (tools/answers.nim)
  for k, key, val in getopt():
    case k
    of cmdLongOption, cmdShortOption:
      case key
      of "cases": count = parseInt(val)
      of "seed": seed = parseInt(val)
      of "show": show = parseInt(val)
      of "package": packageArg = val
      of "js": js = true
      of "hosts": hosts = true
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: kind = key
    of cmdEnd: discard
  if kind notin ["pie", "timeline", "journey", "info", "packet", "flowchart", "sequence", "radar", "treemap", "treeView", "swimlane", "class", "state", "ishikawa", "cynefin", "gitGraph", "er", "requirement", "usecase", "railroad", "gantt", "wardley", "architecture", "c4", "block", "agentflow", "mindmap", "kanban", "eventmodeling", "labels", "xychart"]: quit "ERROR fuzz knows only: pie, timeline, journey, info, packet, flowchart, sequence, radar, treemap, treeView, swimlane, class, state, ishikawa, cynefin, gitGraph, er, requirement, usecase, railroad, gantt, wardley, architecture, c4, block, agentflow, mindmap, kanban, eventmodeling, labels, xychart", 2
  let packageDir = packageDirFrom(packageArg)
  var g = Gen(rng: initRand(seed))
  var cases: seq[JsonNode]
  for i in 0 ..< count:
    let opts = g.options()
    opts["now"] = %1767225600000.0
    if hosts:
      opts["icons"] = %"test"
      opts["math"] = %"test"
    elif kind == "labels":
      if g.chance(0.7): opts["icons"] = %"test"
      if g.chance(0.7): opts["math"] = %"test"
    cases.add %*{"id": kind & "/" & $seed & "/" & $i, "source": (case kind
                                                          of "pie": g.pieSource()
                                                          of "timeline": g.timelineSource()
                                                          of "journey": g.journeySource()
                                                          of "info": g.infoSource()
                                                          of "packet": g.packetSource()
                                                          of "flowchart": g.flowchartSource()
                                                          of "sequence": g.sequenceSource()
                                                          of "state": g.stateSource()
                                                          of "swimlane": g.swimlaneSource()
                                                          of "class": g.classSource()
                                                          of "ishikawa": g.ishikawaSource()
                                                          of "cynefin": g.cynefinSource()
                                                          of "gitGraph": g.gitSource()
                                                          of "railroad": g.railroadSource()
                                                          of "gantt": g.ganttSource()
                                                          of "wardley": g.wardleySource()
                                                          of "architecture": g.architectureSource()
                                                          of "c4": g.c4Source()
                                                          of "block": g.blockSource()
                                                          of "radar": g.radarSource()
                                                          of "xychart": g.xychartSource()
                                                          of "treemap": g.treemapSource()
                                                          of "er": g.erSource()
                                                          of "requirement": g.requirementSource()
                                                          of "usecase": g.usecaseSource()
                                                          of "agentflow": g.agentflowSource()
                                                          of "labels": g.labelsSource()
                                                          of "treeView": g.treeViewSource()
                                                          of "mindmap": g.mindmapSource()
                                                          of "kanban": g.kanbanSource()
                                                          else: g.eventmodelingSource()), "options": opts}
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
  var peles: seq[JsonNode]
  for line in lines(outPath):
    if line.len > 0: peles.add parseJson(line)
  let fromJs = if js: jsAnswers(cases, "fuzz-" & kind & "-" & $seed) else: initTable[string, Answer]()
  var identical, different, shown, rendered = 0
  var failing = ""
  for i, c in cases:
    let a = peles[i]
    let want = if a["ok"].getBool: Answer(ok: true, svg: a["svg"].getStr)
               else: Answer(ok: false, code: a["code"].getStr, message: a["message"].getStr)
    if want.ok: inc rendered
    let got = if js: fromJs[c["id"].getStr] else: nimakiAnswer(c["source"].getStr, c["options"])
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
  # the summary the pages show: the last run of each type (of the C build)
  let dataPath = dataDir / "fuzz.json"
  var data = if fileExists(dataPath): parseFile(dataPath) else: %*{"about": "Written by tools/fuzz.nim: the last run for each diagram type. Do not edit by hand.", "types": {}}
  data["types"][kind] = %*{"seed": seed, "cases": cases.len, "identical": identical, "different": different,
                           "rendered": rendered, "errors": cases.len - rendered}
  if js:
    updateJsData("fuzz", kind, %*{"seed": seed, "cases": cases.len, "identical": identical, "different": different})
  else: writeFile dataPath, data.pretty & "\n"
  echo "fuzz: ", kind, (if js: " in JavaScript" else: ""), ", seed ", seed, ", ", cases.len, " cases: ", identical, " identical, ",
    different, " different", (if different > 0: " (" & failPath & ")" else: "")
  if different > 0: quit 1

when isMainModule:
  main()
