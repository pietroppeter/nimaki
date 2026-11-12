## Measures a Pele checkout for the post *How Pele is built*.
##
##   nim r docs/devlog/data/how_pele_is_built/measure.nim [path/to/pele]
##
## The checkout is the first argument, else `$PELE_REF`, else `reference/pele`. It must be a
## git clone (the history and the release tags are read too). Writes `components.json` and
## `history.json` next to this file. Lines are all lines, blank and comments included (as `wc -l`
## counts them), so the totals match the numbers quoted in the project brief.
import std/[algorithm, json, os, osproc, sequtils, strutils, tables]

const here = currentSourcePath.parentDir

let pele =
  if paramCount() >= 1: paramStr(1)
  elif existsEnv("PELE_REF"): getEnv("PELE_REF")
  else: here / ".." / ".." / ".." / ".." / "reference" / "pele"

proc git(args: varargs[string]): string =
  let (output, code) = execCmdEx("git -C " & quoteShell(pele) & " " & args.mapIt(quoteShell(it)).join(" "))
  if code != 0: quit "ERROR git " & args.join(" ") & " failed:\n" & output
  output

proc lineCount(path: string): int =
  for _ in lines(path): inc result

proc tsFiles(dir: string): seq[string] =
  if dirExists(dir):
    for f in walkDirRec(dir):
      if f.endsWith(".ts"): result.add f
  result.sort()

# --- What a file does, from its name -------------------------------------------------------

proc role(file: string): string =
  ## parse: from text to a model; layout: where things go; render: SVG out; entry: the glue.
  case file.extractFilename.changeFileExt("")
  of "lexer", "tokens", "parser", "db", "model", "graph", "types", "members", "json", "dates",
     "abnf", "ebnf", "peg", "ir", "common", "builder", "diagnostics", "caseless", "scan",
     "generics", "accDescr", "literal-label":
    "parse"
  of "layout", "route", "fit", "fit-width", "fit-text":
    "layout"
  of "index":
    "entry"
  else:
    "render"

# --- Constructs that need care in a port from TypeScript ------------------------------------

proc regexLiterals(src: string): int =
  ## Counts regular expression literals with a small scanner: a `/` that starts an operand
  ## (after `(,=:[!&|?{};` or `return`) and is not a comment, up to the closing `/` outside a
  ## character class. Good enough to compare files; not a JavaScript parser.
  for line in src.splitLines:
    let t = line.strip
    if t.startsWith("//") or t.startsWith("*") or t.startsWith("/*"): continue
    var i = 0
    while i < line.len:
      let c = line[i]
      if c in {'"', '\'', '`'}:
        # skip a string on the same line
        inc i
        while i < line.len and line[i] != c:
          if line[i] == '\\': inc i
          inc i
        inc i
        continue
      if c == '/' and i + 1 < line.len and line[i+1] notin {'/', '*'}:
        var j = i - 1
        while j >= 0 and line[j] == ' ': dec j
        let before = line[0 .. j]
        if j < 0 or line[j] in {'(', ',', '=', ':', '[', '!', '&', '|', '?', '{', '}', ';'} or
            before.endsWith("return"):
          var k = i + 1
          var inClass = false
          while k < line.len:
            if line[k] == '\\': inc k
            elif line[k] == '[': inClass = true
            elif line[k] == ']': inClass = false
            elif line[k] == '/' and not inClass: break
            inc k
          if k < line.len:
            inc result
            i = k + 1
            continue
      inc i

const traps = {
  "utf16": @["charCodeAt(", "codePointAt(", "fromCharCode(", "fromCodePoint("],
  "numberText": @["toFixed(", "toPrecision(", "toString(", "parseFloat(", "parseInt(", "Number("],
  "libm": @["Math.sin(", "Math.cos(", "Math.atan2(", "Math.hypot(", "Math.acos(", "Math.asin(",
            "Math.pow(", "Math.log10(", "Math.log2(", "Math.exp("],
  "round": @["Math.round("],
  "sort": @[".sort("],
  "date": @["new Date", "Date.now"],
  "sticky": @["/y,", "/y;", "/y)", "/gy", "/yu", "/uy", "'y')", "\"y\")"],
}

proc trapCounts(files: seq[string]): JsonNode =
  result = newJObject()
  var regex = 0
  var counts = initOrderedTable[string, int]()
  for (name, _) in traps: counts[name] = 0
  for f in files:
    let src = readFile(f)
    regex += regexLiterals(src)
    for (name, needles) in traps:
      for needle in needles: counts[name] += src.count(needle)
  result["regex"] = %regex
  for name, n in counts: result[name] = %n

# --- Parser family ---------------------------------------------------------------------------

proc parserFamily(files: seq[string]): string =
  ## jison: a lexer with start conditions modelled on Mermaid's Jison grammar (`lexer.ts`).
  ## langium: the shared ordered-token tokenizer (`common/tokens.ts`), as Mermaid's Langium
  ## grammars are lexed by Chevrotain. own: neither.
  var langium, jison = false
  for f in files:
    let name = f.extractFilename
    if name == "lexer.ts": jison = true
    if "common/tokens" in readFile(f): langium = true
  if jison: "jison" elif langium: "langium" else: "own"

proc sharedImports(files: seq[string]): seq[string] =
  for f in files:
    for line in lines(f):
      if not line.startsWith("import"): continue
      for dir in ["layout/", "svg/", "text/", "util/", "diagrams/common/", "../common/", "../flowchart/"]:
        let at = line.find("'../../" & dir)
        let at2 = line.find("'" & dir)
        if at >= 0 or (at2 >= 0 and dir.startsWith("../")):
          let start = line.find('\'') + 1
          var path = line[start ..< line.find('\'', start)]
          path = path.replace("../../", "").replace("../", "diagrams/").replace(".js", "")
          if path notin result: result.add path
  result.sort()

# --- The measure -----------------------------------------------------------------------------

proc firstCommit(path: string): JsonNode =
  let log = git("log", "--reverse", "--format=%h %ad", "--date=short", "--", path).strip.splitLines
  if log.len == 0 or log[0] == "": return newJNull()
  let parts = log[0].split(' ')
  %*{"commit": parts[0], "date": parts[1], "commits": log.len}

proc measure(): JsonNode =
  let head = git("rev-parse", "HEAD").strip
  let tag = git("describe", "--tags", "--exact-match", "HEAD").strip
  let date = git("log", "-1", "--format=%ad", "--date=short").strip
  var types = newJArray()
  for kind, dir in walkDir(pele / "src" / "diagrams"):
    if kind != pcDir: continue
    let name = dir.extractFilename
    let files = tsFiles(dir)
    var roles = %*{"parse": 0, "layout": 0, "render": 0, "entry": 0}
    var fileRows = newJArray()
    for f in files:
      let n = lineCount(f)
      let r = role(f)
      roles[r] = %(roles[r].getInt + n)
      fileRows.add %*{"file": f.relativePath(pele), "role": r, "lines": n}
    var testLines = 0
    for d in [pele / "tests" / "compat" / name, pele / "tests" / name]:
      if dirExists(d):
        for f in walkDirRec(d):
          if f.endsWith(".ts") or f.endsWith(".js"): testLines += lineCount(f)
    let corpus = pele / "tests" / "corpus" / (name & "-docs.json")
    types.add %*{
      "type": name,
      "lines": files.mapIt(lineCount(it)).foldl(a + b, 0),
      "roles": roles,
      "parser": if name == "common": "shared" else: parserFamily(files),
      "uses": sharedImports(files),
      "traps": trapCounts(files),
      "testLines": testLines,
      "docExamples": (if fileExists(corpus): parseJson(readFile(corpus)).len else: 0),
      "added": firstCommit("src/diagrams/" & name),
      "files": fileRows,
    }
  types.elems.sort(proc (a, b: JsonNode): int = cmp(b["lines"].getInt, a["lines"].getInt))
  var core = newJArray()
  for part in ["layout", "svg", "text", "util", "entries"]:
    for f in tsFiles(pele / "src" / part):
      core.add %*{"file": f.relativePath(pele), "part": part, "lines": lineCount(f),
                  "traps": trapCounts(@[f])}
  for (dir, part) in [("src", "top"), ("src/diagrams", "registry")]:
    for kind, f in walkDir(pele / dir):
      if kind == pcFile and f.endsWith(".ts"):
        core.add %*{"file": f.relativePath(pele), "part": part, "lines": lineCount(f),
                    "traps": trapCounts(@[f])}
  core.elems.sort(proc (a, b: JsonNode): int = cmp(a["file"].getStr, b["file"].getStr))
  %*{"about": "Pele measured by measure.nim at the pin. Lines are all lines (wc -l).",
     "pin": {"tag": tag, "commit": head, "date": date},
     "types": types, "core": core}

proc releases(): JsonNode =
  ## Lines of src/ and of src/layout/ at every release tag, oldest first.
  result = newJArray()
  let tags = git("tag", "--sort=creatordate").strip.splitLines.filterIt(it.len > 0 and it[0].isDigit)
  for tag in tags:
    var total, layout = 0
    for row in git("grep", "-c", "", tag, "--", "src/*.ts").strip.splitLines:
      # tag:path:count
      let parts = row.rsplit(':', maxsplit = 1)
      let n = parseInt(parts[1])
      total += n
      if ":src/layout/" in parts[0]: layout += n
    let date = git("log", "-1", "--format=%ad", "--date=short", tag).strip
    result.add %*{"tag": tag, "date": date, "src": total, "layout": layout}

proc history(): JsonNode =
  ## The releases, and the commits: how many, over which days, and by the area their subject
  ## names (`Layout: ...`, `Sequence: ...`; a subject with no area counts as `(none)`).
  let log = git("log", "--format=%ad|%s", "--date=short").strip.splitLines
  var areas = initCountTable[string]()
  var days = initCountTable[string]()
  for row in log:
    let parts = row.split('|', maxsplit = 1)
    days.inc parts[0]
    let colon = parts[1].find(": ")
    let area = if colon > 0 and parts[1][0 ..< colon].allIt(it.isAlphaNumeric or it == ' '): parts[1][0 ..< colon] else: "(none)"
    areas.inc area
  areas.sort()
  var areaRows = newJArray()
  for area, n in areas: areaRows.add %*{"area": area, "commits": n}
  var dayRows = newJArray()
  var dayList = toSeq(days.keys)
  dayList.sort()
  for d in dayList: dayRows.add %*{"date": d, "commits": days[d]}
  %*{"commits": log.len, "days": dayRows, "areas": areaRows, "releases": releases()}

when isMainModule:
  if not dirExists(pele / ".git"): quit "ERROR no Pele git checkout at " & pele
  if git("rev-parse", "--is-shallow-repository").strip == "true":
    quit "ERROR " & pele & " is a shallow clone; the history needs a full one: git -C " & pele & " fetch --unshallow --tags"
  writeFile(here / "components.json", measure().pretty & "\n")
  writeFile(here / "history.json", history().pretty & "\n")
  echo "wrote components.json and history.json from ", pele
