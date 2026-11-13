## corpus_diagrammari: a second corpus for the referee, the Mermaid text that diagrammari writes.
##
## diagrammari (`import mari`, https://github.com/pietroppeter/diagrammari) makes diagrams in Nim
## and has Pele draw them. It is nimaki's first user, so what it writes is what nimaki must draw
## first. This tool reads a checkout of diagrammari at the commit in reference/DIAGRAMMARI and
## collects its Mermaid text, without running any of its code:
##
## - the examples of its specs (`openspec/specs/*/spec.md`): a ```nim block followed by a ```text
##   block with what it prints, checked by diagrammari's own CI. When that text is a diagram,
##   it is what diagrammari's builders write;
## - every ```mermaid fence of its Markdown files;
## - every string literal given to `diagram`, `mermaid` or `nbDiagram` in its Nim files, with the
##   indentation removed as `diagram` removes it. Literals built with `&` or `fmt` are skipped.
##
## A text is a case when nimaki's `detectType` (Pele's, ported) finds a diagram type in it. Each
## distinct text is one case. The cases go to corpus/diagrammari.json, in the format of
## corpus/cases.json, and tools/difftest.nim runs them together with Pele's.
##
##   nim r tools/corpus_diagrammari.nim                 # from reference/diagrammari
##   nim r tools/corpus_diagrammari.nim --ref:PATH      # or $DIAGRAMMARI_REF
##
## Rebuilt only when reference/DIAGRAMMARI moves (`reference/fetch.sh diagrammari` fetches it).
import std/[os, strutils, json, tables, algorithm, parseopt, sets]
import common
import nimaki

type
  Found = object
    source, origin: string   ## the text, and where it was found (path:line)

proc readDiagrammariPin(): Table[string, string] =
  for line in lines(repoDir / "reference" / "DIAGRAMMARI"):
    if line.len == 0 or line.startsWith("#"): continue
    let kv = line.split('=', maxsplit = 1)
    if kv.len == 2: result[kv[0]] = kv[1]

func asDiagram*(source: string): string =
  ## What diagrammari's `diagram(source)` keeps (src/mari/core.nim): the indentation common to
  ## all lines removed, trailing white space and leading new lines stripped.
  var common = high(int)
  for l in source.splitLines:
    if l.strip.len > 0: common = min(common, l.len - l.strip(trailing = false).len)
  if common == high(int): common = 0
  var lines: seq[string]
  for l in source.splitLines: lines.add (if l.len >= common: l[common .. ^1] else: l.strip)
  lines.join("\n").strip(leading = false).strip(trailing = false, chars = {'\n'})

proc fences(lines: seq[string], open: string, after = ""): seq[(int, string)] =
  ## The bodies of the fences that open with `open` (alone on a line), with their line numbers.
  ## With `after`, only a fence whose previous non-blank fence was `after` counts.
  var i = 0
  var lastFence = ""
  while i < lines.len:
    let l = lines[i].strip
    if l.startsWith("```") and l.len > 3:
      let fence = l
      let start = i
      var body: seq[string]
      inc i
      while i < lines.len and lines[i].strip != "```":
        body.add lines[i]
        inc i
      if fence == open and (after.len == 0 or lastFence == after):
        result.add (start + 1, body.join("\n"))
      lastFence = fence
    inc i

func printsADiagram*(code: string): bool =
  ## An example prints a diagram's text when it has one `echo`, of a name (`echo f`) or of a
  ## builder's chain (`echo sequence().message(...)`), not of a field or a test (`echo d.kind`).
  var echoes: seq[string]
  for l in code.splitLines:
    if l.strip.startsWith("echo "): echoes.add l.strip[5 .. ^1].strip
  if echoes.len != 1: return false
  let arg = echoes[0]
  if arg.len > 0 and arg.allCharsInSet(IdentChars): return true
  for builder in ["flowchart(", "sequence(", "pie(", "timeline(", "diagram("]:
    if arg.startsWith(builder) and arg.endsWith(")"): return true

proc specOutputs(path, rel: string): seq[Found] =
  ## The ```text outputs of the ```nim examples of a spec that print a diagram.
  let lines = readFile(path).splitLines
  let code = fences(lines, "```nim")
  for (line, body) in fences(lines, "```text", after = "```nim"):
    var example = ""
    for (l, b) in code:
      if l < line: example = b
    if printsADiagram(example):
      result.add Found(source: body.strip(leading = false), origin: rel & ":" & $line)

proc mermaidFences(path, rel: string): seq[Found] =
  for (line, body) in fences(readFile(path).splitLines, "```mermaid"):
    result.add Found(source: asDiagram(body), origin: rel & ":" & $line)

proc unescapeNim(s: string): string =
  ## A Nim string literal's escapes: the ones Mermaid text uses.
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      case s[i + 1]
      of 'n': result.add '\n'
      of 't': result.add '\t'
      of '"': result.add '"'
      of '\\': result.add '\\'
      of '\'': result.add '\''
      else: result.add s[i .. i + 1]
      i += 2
    else:
      result.add s[i]
      inc i

proc literals(path, rel: string): seq[Found] =
  ## The string literals given to `diagram`, `mermaid` and `nbDiagram`.
  let text = readFile(path)
  for callee in ["nbDiagram", "diagram", "mermaid"]:
    var at = 0
    while true:
      at = text.find(callee, at)
      if at < 0: break
      let before = if at > 0: text[at - 1] else: ' '
      var p = at + callee.len
      at = p
      if before in IdentChars or before == '.' or (p < text.len and text[p] in IdentChars): continue
      while p < text.len and text[p] in {' ', '('}: inc p
      if p < text.len and text[p] in {'&'}: continue     # built with strformat: not a fixed text
      if text.continuesWith("fmt", p): continue
      let line = text[0 ..< at].count('\n') + 1
      if text.continuesWith("\"\"\"", p):
        let stop = text.find("\"\"\"", p + 3)
        if stop < 0: continue
        var body = text[p + 3 ..< stop]
        if body.startsWith("\n"): body = body[1 .. ^1]   # Nim drops the new line after """
        result.add Found(source: asDiagram(body), origin: rel & ":" & $line)
      elif p < text.len and text[p] == '"':
        var q = p + 1
        while q < text.len and text[q] != '"' and text[q] != '\n':
          if text[q] == '\\': inc q
          inc q
        if q < text.len and text[q] == '"':
          result.add Found(source: asDiagram(unescapeNim(text[p + 1 ..< q])), origin: rel & ":" & $line)

proc main() =
  var refArg: string
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "ref": refArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: quit "ERROR unexpected argument " & key, 2
    of cmdEnd: discard
  let pin = readDiagrammariPin()
  let dir = if refArg.len > 0: refArg else: getEnv("DIAGRAMMARI_REF", repoDir / "reference" / "diagrammari")
  if not fileExists(dir / "src" / "mari.nim"):
    quit "ERROR no diagrammari checkout at " & dir & " (pass --ref:PATH, set DIAGRAMMARI_REF, or run reference/fetch.sh diagrammari)", 2

  var found: seq[Found]
  var files: seq[string]
  for path in walkDirRec(dir, relative = true, skipSpecial = true):
    let p = path.unixPath
    if p.startsWith(".git/") or p.startsWith("deps/") or "/vendor/" in p or "node_modules" in p: continue
    files.add p
  files.sort
  for p in files:
    let full = dir / p
    if p.startsWith("openspec/specs/") and p.endsWith("/spec.md"): found.add specOutputs(full, p)
    if p.endsWith(".md"): found.add mermaidFences(full, p)
    if p.endsWith(".nim"): found.add literals(full, p)

  var seen: HashSet[string]
  var cases = newJArray()
  var byType: OrderedTable[string, int]
  var perFile: CountTable[string]
  var skipped = 0
  for f in found:
    let t = detectType(f.source)
    if t.len == 0 or f.source.strip.len == 0:
      inc skipped
      continue
    if f.source in seen: continue
    seen.incl f.source
    let file = f.origin.split(':')[0]
    perFile.inc file
    cases.add %*{"id": "diagrammari/" & f.origin, "type": t, "from": f.origin, "source": f.source}
    byType[t] = byType.getOrDefault(t) + 1
  byType.sort(proc (a, b: (string, int)): int = cmp(a[0], b[0]))
  var types = newJObject()
  for t, n in byType: types[t] = %n
  let commit = pin.getOrDefault("COMMIT")
  if (let head = dir / ".git" / "HEAD"; fileExists(head)) and readFile(head).strip != commit:
    echo "ERROR the checkout at ", dir, " is not at the pinned commit ", commit
  createDir repoDir / "corpus"
  writeFile repoDir / "corpus" / "diagrammari.json", (%*{
    "about": "The Mermaid text of diagrammari, built by tools/corpus_diagrammari.nim from diagrammari at the pin (reference/DIAGRAMMARI). Do not edit by hand.",
    "repo": pin.getOrDefault("REPO"), "commit": commit, "count": cases.len, "byType": types,
    "cases": cases}).pretty & "\n"
  for t, n in byType: echo "  ", t.alignLeft(14), align($n, 4)
  echo "corpus: diagrammari ", commit[0 ..< min(7, commit.len)], ", ", cases.len, " cases of ", byType.len,
    " types, from ", perFile.len, " files (", found.len, " texts read, ", skipped, " not a diagram, ",
    found.len - skipped - cases.len, " repeated)"

when isMainModule:
  main()
