## port-of: src/detect.ts
## port-status: draft
##
## Each detector `/^\s*word.../` is a prefix test after the leading `\s`; `tail` says what
## must follow the word (Pele's `\b`, `(?:\s|$)` and the like).
import std/strutils
import js

type
  Tail = enum
    tAny          ## nothing more
    tBoundary     ## \b: the word ends here
    tSpaceColonEnd ## (?:[\s:]|$)
    tSpaceEnd     ## (?:\s|$)

  Detector = tuple[diagramType, mermaidType: string, words: seq[string], tail: Tail, nocase: bool]

  Detected* = object
    diagramType*: string
    mermaidType*: string

const DETECTORS: seq[Detector] = @[
  # Mermaid's detectors, in the order Mermaid registers them. The first match wins.
  ("flowchart", "flowchart-elk", @["flowchart-elk"], tAny, false),
  ("mindmap", "mindmap", @["mindmap"], tAny, false),
  ("architecture", "architecture", @["architecture"], tAny, false),
  ("agentflow", "agentflow", @["agentflow-beta"], tBoundary, false),
  ("c4", "c4", @["C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment"], tAny, false),
  ("kanban", "kanban", @["kanban"], tAny, false),
  ("class", "classDiagram", @["classDiagram"], tAny, false),
  ("er", "er", @["erDiagram"], tAny, false),
  ("gantt", "gantt", @["gantt"], tAny, false),
  ("info", "info", @["info"], tAny, false),
  ("pie", "pie", @["pie"], tAny, false),
  ("requirement", "requirement", @["requirement"], tAny, false),
  ("sequence", "sequence", @["sequenceDiagram"], tAny, false),
  ("swimlane", "swimlane", @["swimlane-beta"], tBoundary, false),
  ("flowchart", "flowchart-v2", @["graph", "flowchart"], tAny, false),
  ("timeline", "timeline", @["timeline"], tAny, false),
  ("gitGraph", "gitGraph", @["gitGraph"], tAny, false),
  ("state", "stateDiagram", @["stateDiagram"], tAny, false),
  ("journey", "journey", @["journey"], tAny, false),
  ("quadrantChart", "quadrantChart", @["quadrantChart"], tAny, false),
  ("sankey", "sankey", @["sankey"], tAny, false),
  ("packet", "packet", @["packet"], tAny, false),
  ("xychart", "xychart", @["xychart"], tAny, false),
  ("block", "block", @["block"], tAny, false),
  ("eventmodeling", "eventmodeling", @["eventmodeling"], tAny, false),
  ("treeView", "treeView", @["treeView-beta"], tAny, false),
  ("radar", "radar", @["radar-beta"], tAny, false),
  ("ishikawa", "ishikawa", @["ishikawa-beta", "ishikawa"], tBoundary, true),
  ("treemap", "treemap", @["treemap"], tAny, false),
  ("railroad", "railroad", @["railroad-beta"], tAny, true),
  ("railroad", "railroadEbnf", @["railroad-ebnf-beta"], tAny, true),
  ("railroad", "railroadAbnf", @["railroad-abnf-beta"], tAny, true),
  ("railroad", "railroadPeg", @["railroad-peg-beta"], tAny, true),
  ("venn", "venn", @["venn-beta"], tAny, false),
  ("wardley", "wardley", @["wardley-beta"], tAny, true),
  ("cynefin", "cynefin", @["cynefin-beta"], tSpaceColonEnd, false),
  ("usecase", "usecase", @["usecase-beta"], tSpaceEnd, false),
]
  # `requirement(Diagram)?`, `sankey(-beta)?` and the like need no second word: the optional
  # part can only follow, and nothing is required after it.

func matchesAt(s: string, at: int, word: string, tail: Tail, nocase: bool): bool =
  if at + word.len > s.len: return false
  let part = s[at ..< at + word.len]
  if (if nocase: cmpIgnoreCase(part, word) != 0 else: part != word): return false
  let next = at + word.len
  case tail
  of tAny: true
  of tBoundary:
    # \b after a word character: the next is not one
    next >= s.len or not isWordChar(s[next])
  of tSpaceColonEnd: next >= s.len or s[next] == ':' or isJsSpaceAt(s, next)
  of tSpaceEnd: next >= s.len or isJsSpaceAt(s, next)

proc detectDiagram*(cleaned: string): (bool, Detected) =
  var at = 0
  while true:
    let n = spaceLenAt(cleaned, at)
    if n == 0: break
    at += n
  for d in DETECTORS:
    for word in d.words:
      if matchesAt(cleaned, at, word, d.tail, d.nocase):
        return (true, Detected(diagramType: d.diagramType, mermaidType: d.mermaidType))

proc detect*(cleaned: string): string =
  let (ok, found) = detectDiagram(cleaned)
  if ok: found.diagramType else: ""
