## port-of: src/diagrams/er/types.ts
## port-status: conformant
##
## `type` is `kind` (the porting guide's names table). Cardinality and Identification stay
## strings, as Pele's string unions are.
import std/tables

type
  Cardinality* = string     ## 'ZERO_OR_ONE' | 'ZERO_OR_MORE' | 'ONE_OR_MORE' | 'ONLY_ONE' | 'MD_PARENT'
  Identification* = string  ## 'NON_IDENTIFYING' | 'IDENTIFYING'

  ErAttribute* = object
    kind*: string
    name*: string
    keys*: seq[string]
    comment*: string

  ParsedAttribute* = object
    ## What the parser hands over for one attribute; keys and comment are present only when written.
    kind*: string
    name*: string
    hasKeys*: bool
    keys*: seq[string]
    hasComment*: bool
    comment*: string

  ErEntity* = ref object
    id*: string
    label*: string
    alias*: string
    attributes*: seq[ErAttribute]
    cssClasses*: string
    cssStyles*: seq[string]

  RelSpec* = object
    ## cardB sits at entityA's end of the line and cardA at entityB's, as in Mermaid.
    cardA*: Cardinality
    relType*: Identification
    cardB*: Cardinality

  ErRelationship* = object
    ## entityA and entityB hold an entity's id, or a subgraph's id when the name was a subgraph at the time.
    entityA*: string
    roleA*: string
    entityB*: string
    relSpec*: RelSpec

  ErClassDef* = ref object
    id*: string
    styles*: seq[string]
    textStyles*: seq[string]

  ErSubgraph* = ref object
    id*: string
    nodes*: seq[string]
    title*: string
    classes*: seq[string]
    cssStyles*: seq[string]
    dir*: string            ## "" for undefined
    labelType*: string      ## 'text' | 'string' | 'markdown'

  DocItem* = object
    ## string | { stmt: 'dir'; value: string }
    isDir*: bool
    text*: string           ## the string, or the direction's value

func docText*(s: string): DocItem = DocItem(text: s)
func docDir*(value: string): DocItem = DocItem(isDir: true, text: value)

export tables
