## port-of: src/detect.ts
## port-status: draft
import jsregex

type
  Detected* = object
    diagramType*: string
    mermaidType*: string

const DETECTORS = [
  # Mermaid's detectors, in the order Mermaid registers them. The first match wins.
  ("flowchart", "flowchart-elk", jsre"/^\s*flowchart-elk/"),
  ("mindmap", "mindmap", jsre"/^\s*mindmap/"),
  ("architecture", "architecture", jsre"/^\s*architecture/"),
  ("agentflow", "agentflow", jsre"/^\s*agentflow-beta\b/"),
  ("c4", "c4", jsre"/^\s*(?:C4Context|C4Container|C4Component|C4Dynamic|C4Deployment)/"),
  ("kanban", "kanban", jsre"/^\s*kanban/"),
  ("class", "classDiagram", jsre"/^\s*classDiagram/"),
  ("er", "er", jsre"/^\s*erDiagram/"),
  ("gantt", "gantt", jsre"/^\s*gantt/"),
  ("info", "info", jsre"/^\s*info/"),
  ("pie", "pie", jsre"/^\s*pie/"),
  ("requirement", "requirement", jsre"/^\s*requirement(Diagram)?/"),
  ("sequence", "sequence", jsre"/^\s*sequenceDiagram/"),
  ("swimlane", "swimlane", jsre"/^\s*swimlane-beta\b/"),
  ("flowchart", "flowchart-v2", jsre"/^\s*(graph|flowchart)/"),
  ("timeline", "timeline", jsre"/^\s*timeline/"),
  ("gitGraph", "gitGraph", jsre"/^\s*gitGraph/"),
  ("state", "stateDiagram", jsre"/^\s*stateDiagram/"),
  ("journey", "journey", jsre"/^\s*journey/"),
  ("quadrantChart", "quadrantChart", jsre"/^\s*quadrantChart/"),
  ("sankey", "sankey", jsre"/^\s*sankey(-beta)?/"),
  ("packet", "packet", jsre"/^\s*packet(-beta)?/"),
  ("xychart", "xychart", jsre"/^\s*xychart(-beta)?/"),
  ("block", "block", jsre"/^\s*block(-beta)?/"),
  ("eventmodeling", "eventmodeling", jsre"/^\s*eventmodeling/"),
  ("treeView", "treeView", jsre"/^\s*treeView-beta/"),
  ("radar", "radar", jsre"/^\s*radar-beta/"),
  ("ishikawa", "ishikawa", jsre"/^\s*ishikawa(-beta)?\b/i"),
  ("treemap", "treemap", jsre"/^\s*treemap/"),
  ("railroad", "railroad", jsre"/^\s*railroad-beta/i"),
  ("railroad", "railroadEbnf", jsre"/^\s*railroad-ebnf-beta/i"),
  ("railroad", "railroadAbnf", jsre"/^\s*railroad-abnf-beta/i"),
  ("railroad", "railroadPeg", jsre"/^\s*railroad-peg-beta/i"),
  ("venn", "venn", jsre"/^\s*venn-beta/"),
  ("wardley", "wardley", jsre"/^\s*wardley-beta/i"),
  ("cynefin", "cynefin", jsre"/^\s*cynefin-beta(?:[\s:]|$)/"),
  ("usecase", "usecase", jsre"/^\s*usecase-beta(?:\s|$)/"),
]

proc detectDiagram*(cleaned: string): (bool, Detected) =
  for (diagramType, mermaidType, re) in DETECTORS:
    if re.test(cleaned): return (true, Detected(diagramType: diagramType, mermaidType: mermaidType))

proc detect*(cleaned: string): string =
  let (ok, found) = detectDiagram(cleaned)
  if ok: found.diagramType else: ""
