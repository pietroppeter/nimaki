## port-of: src/diagrams/state/types.ts
## port-status: conformant
##
## Pele's `Stmt` union is one `ref object` with a `stmt` tag, as the statements are shared and
## changed in place (the parser fills a composite's document after adding it; the translator
## renames `[*]`). `type` is `kind` (the porting guide's names table).
import std/options

type
  StmtKind* = enum
    skText          ## a statement Mermaid leaves as its text (`hide empty description`, `scale`...)
    skState, skRelation, skClassDef, skStyle, skApplyClass, skDir, skClick
    skRoot          ## the document root of Mermaid's docTranslator

  DescrKind* = enum
    dkNone          ## undefined (or '', which Pele treats alike)
    dkText          ## a string
    dkList          ## a string[]

  StateNote* = object
    position*: string
    text*: string

  Stmt* = ref object
    stmt*: StmtKind
    text*: string                ## skText
    id*: string                  ## skState, skClassDef, skStyle, skApplyClass, skRoot
    kind*: string                ## skState `type` ("" for undefined)
    descr*: DescrKind            ## skState `description`
    description*: string         ##   when dkText
    descriptionList*: seq[string]  ##   when dkList
    descriptions*: seq[string]
    hasDoc*: bool
    doc*: seq[Stmt]              ## skState, skRoot
    hasNote*: bool
    note*: StateNote
    start*: Option[bool]
    hasClasses*: bool
    classes*: seq[string]
    styles*: seq[string]
    textStyles*: seq[string]
    state1*, state2*: Stmt       ## skRelation
    relDescription*: Option[string]
    classesText*: string         ## skClassDef `classes`
    styleClass*: string          ## skStyle, skApplyClass
    value*: string               ## skDir
    clickId*: Stmt               ## skClick `id` (a state statement)
    url*, tooltip*: string

  StateRelation* = object
    id1*, id2*: string
    relationTitle*: string

  StateClassDef* = ref object
    id*: string
    styles*: seq[string]
    textStyles*: seq[string]

  StateLink* = object
    url*: string
    tooltip*: string

func textStmt*(s: string): Stmt = Stmt(stmt: skText, text: s)

func copyStmt*(s: Stmt): Stmt =
  ## `{ ...s }`
  result = Stmt()
  result[] = s[]
