## port-of: src/diagrams/requirement/db.ts
## port-status: conformant
import std/[strutils, tables]
import ../../errors
import ../../js
import types

const
  RT_REQUIREMENT* = "Requirement"  ## RequirementType.REQUIREMENT (a bare REQUIREMENT would be the type `Requirement` in Nim)
  FUNCTIONAL_REQUIREMENT* = "Functional Requirement"
  INTERFACE_REQUIREMENT* = "Interface Requirement"
  PERFORMANCE_REQUIREMENT* = "Performance Requirement"
  PHYSICAL_REQUIREMENT* = "Physical Requirement"
  DESIGN_CONSTRAINT* = "Design Constraint"
  LOW_RISK* = "Low"
  MED_RISK* = "Medium"
  HIGH_RISK* = "High"
  VERIFY_ANALYSIS* = "Analysis"
  VERIFY_DEMONSTRATION* = "Demonstration"
  VERIFY_INSPECTION* = "Inspection"
  VERIFY_TEST* = "Test"
  CONTAINS* = "contains"
  COPIES* = "copies"
  DERIVES* = "derives"
  SATISFIES* = "satisfies"
  VERIFIES* = "verifies"
  REFINES* = "refines"
  TRACES* = "traces"

# Applying a class copies its declarations onto each node, so a short text can ask for
# hundreds of millions of copies. Past this many the diagram is refused.
const MAX_STYLE_COPIES = 1_000_000

type RequirementDb* = ref object of RootObj
  direction*: string
  requirements*: OrderedTable[string, Requirement]
  elements*: OrderedTable[string, RequirementElement]
  relations*: seq[Relation]
  classes*: OrderedTable[string, RequirementClass]
  title*: string        ## "" for undefined
  accTitle*: string
  accDescr*: string
  # The grammar reports a body's fields before the requirement or element they belong to.
  newId, newText, newRisk, newVerifyMethod, newElementType, newDocRef: string
  styleCopies: int

proc newRequirementDb*(): RequirementDb = RequirementDb(direction: "TB")

proc copy(db: RequirementDb, target: var seq[string], styles: seq[string]) =
  db.styleCopies += styles.len
  if db.styleCopies > MAX_STYLE_COPIES:
    raise newPeleError("Requirement diagram applies too many style declarations.", "limit", "requirement")
  for style in styles: target.add style

proc setDirection*(db: RequirementDb, dir: string) = db.direction = dir

proc addRequirement*(db: RequirementDb, name, kind: string): Requirement =
  result = db.requirements.getOrDefault(name, nil)
  if result == nil:
    result = Requirement(name: name, kind: kind, requirementId: db.newId, text: db.newText, risk: db.newRisk,
                         verifyMethod: db.newVerifyMethod, classes: @["default"])
    db.requirements[name] = result
  db.newId = ""
  db.newText = ""
  db.newRisk = ""
  db.newVerifyMethod = ""

proc setNewReqId*(db: RequirementDb, id: string) = db.newId = id
proc setNewReqText*(db: RequirementDb, text: string) = db.newText = text
proc setNewReqRisk*(db: RequirementDb, risk: string) = db.newRisk = risk
proc setNewReqVerifyMethod*(db: RequirementDb, verifyMethod: string) = db.newVerifyMethod = verifyMethod

proc addElement*(db: RequirementDb, name: string): RequirementElement =
  result = db.elements.getOrDefault(name, nil)
  if result == nil:
    result = RequirementElement(name: name, kind: db.newElementType, docRef: db.newDocRef, classes: @["default"])
    db.elements[name] = result
  db.newElementType = ""
  db.newDocRef = ""

proc setNewElementType*(db: RequirementDb, kind: string) = db.newElementType = kind
proc setNewElementDocRef*(db: RequirementDb, docRef: string) = db.newDocRef = docRef

proc addRelationship*(db: RequirementDb, kind, src, dst: string) =
  db.relations.add Relation(kind: kind, src: src, dst: dst)

template withNode(db: RequirementDb, id: string, body: untyped) =
  ## this.requirements.get(id) ?? this.elements.get(id), as `styles` and `classes` of `it`
  let req {.inject.} = db.requirements.getOrDefault(id, nil)
  let elem {.inject.} = if req == nil: db.elements.getOrDefault(id, nil) else: nil
  body

proc setCssStyle*(db: RequirementDb, ids, styles: seq[string]) =
  for id in ids:
    db.withNode(id):
      # Mermaid stops at the first unknown id, leaving the rest of the list unstyled.
      if req == nil and elem == nil: return
      for s in styles:
        let parts = if ',' in s: s.split(',') else: @[s]
        if req != nil: db.copy(req.cssStyles, parts) else: db.copy(elem.cssStyles, parts)

proc setClass*(db: RequirementDb, ids, classNames: seq[string]) =
  for id in ids:
    db.withNode(id):
      if req == nil and elem == nil: continue
      for name in classNames:
        if req != nil: req.classes.add name else: elem.classes.add name
        let def = db.classes.getOrDefault(name, nil)
        if def != nil:
          if req != nil: db.copy(req.cssStyles, def.styles) else: db.copy(elem.cssStyles, def.styles)

proc defineClass*(db: RequirementDb, ids, style: seq[string]) =
  for id in ids:
    var styleClass = db.classes.getOrDefault(id, nil)
    if styleClass == nil:
      styleClass = RequirementClass(id: id)
      db.classes[id] = styleClass
    for s in style:
      if "color" in s: styleClass.textStyles.add s.replaceFirst("fill", "bgFill")
      styleClass.styles.add s
    var split: seq[string]
    for s in style:
      for part in s.split(','): split.add part
    for requirement in db.requirements.values:
      if id in requirement.classes: db.copy(requirement.cssStyles, split)
    for element in db.elements.values:
      if id in element.classes: db.copy(element.cssStyles, split)

proc setAccTitle*(db: RequirementDb, text: string) =
  db.accTitle = text.jsTrimStart  # text.replace(/^\s+/g, '')

proc setAccDescription*(db: RequirementDb, text: string) =
  # text.replace(/\n\s+/g, '\n')
  var s = ""
  var i = 0
  while i < text.len:
    if text[i] == '\n' and isJsSpaceAt(text, i + 1):
      s.add '\n'
      inc i
      while i < text.len and isJsSpaceAt(text, i): i += spaceLenAt(text, i)
    else:
      s.add text[i]
      inc i
  db.accDescr = s
