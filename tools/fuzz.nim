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
##
## The last run of each type is summed up in docs/data/fuzz.json, which the pages read. Each
## failing case is written whole to build/fuzz/<type>-<seed>.jsonl, so it can be replayed.
import std/[os, osproc, strutils, json, random, parseopt, options, sequtils]
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

proc toOptions(j: JsonNode): RenderOptions =
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
  if kind notin ["pie", "timeline", "journey", "info", "packet", "flowchart", "sequence", "radar", "treemap", "treeView", "swimlane", "class", "state", "er", "requirement", "gitGraph", "usecase", "railroad"]: quit "ERROR fuzz knows only: pie, timeline, journey, info, packet, flowchart, sequence, radar, treemap, treeView, swimlane, class, state, er, requirement, gitGraph, usecase, railroad", 2
  let packageDir = packageDirFrom(packageArg)
  var g = Gen(rng: initRand(seed))
  var cases: seq[JsonNode]
  for i in 0 ..< count:
    let opts = g.options()
    opts["now"] = %1767225600000.0
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
                                                          of "gitGraph": g.gitSource()
                                                          of "railroad": g.railroadSource()
                                                          of "radar": g.radarSource()
                                                          of "treemap": g.treemapSource()
                                                          of "er": g.erSource()
                                                          of "requirement": g.requirementSource()
                                                          of "usecase": g.usecaseSource()
                                                          else: g.treeViewSource()), "options": opts}
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
