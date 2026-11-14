## port-of: src/diagrams/usecase/types.ts
## port-status: draft
##
## Optional strings are "" for undefined where Pele treats an empty string as absent too. The
## positions of each statement's parts (`statements`, `GraphStatement`, the `*Occurrence` types)
## are not ported: Pele keeps them on the model for editors, and nothing it draws reads them.
import std/tables
import json

type
  Span* = (int, int)
    ## Start and end offsets in the source, end exclusive.

  Stylable* = ref object of RootObj
    ## What `class` and `style` statements reach: an actor, use case, boundary, JSON node or edge.
    classes*: seq[string]
    styles*: seq[string]

  Actor* = ref object of Stylable
    id*, label*: string
    markdown*: bool        ## labelType 'markdown'
    kind*: string          ## type: normal, hollow, awesome or icon
    icon*: string          ## "" for undefined
    business*: bool
    stereotype*: string    ## "" for undefined
    parentId*: string      ## "" for undefined

  UseCase* = ref object of Stylable
    id*, label*: string
    markdown*: bool
    shape*: string         ## ellipse or rect
    business*: bool
    stereotype*: string
    parentId*: string

  SystemBoundary* = ref object of Stylable
    id*, label*: string
    markdown*: bool
    kind*: string          ## type: rect or package
    members*: seq[string]

  Relationship* = ref object of Stylable
    id*: string
    explicitId*: bool
    source*, target*: string
    kind*: string          ## type: association, include, extend or generalization
    arrowType*: int
    label*: string         ## "" for undefined
    labelMarkdown*: bool
    minlen*: int
    animate*: bool
    animation*: string     ## "" for undefined

  UsecaseNote* = ref object
    id*, target*, label*: string
    markdown*: bool

  UsecaseJsonNode* = ref object of Stylable
    id*: string
    value*: JsonValue
    propertyOrder*: Table[string, seq[string]]
      ## The keys of each object in the order they were written, by JSON Pointer.

  ClassDef* = ref object
    id*: string
    styles*: SharedStyles
      ## Pele copies the list for each id (`[...definition.styles]`), a copy of references; in
      ## nimaki the ids of one classDef share it, since nothing changes it later. Copies of Nim
      ## strings are copies of their text: 8,000 ids with 8,000 declarations each ran the
      ## JavaScript build out of memory.

  SharedStyles* = ref object
    items*: seq[string]

  UsecaseModel* = ref object of RootObj
    actors*: OrderedTable[string, Actor]
    useCases*: OrderedTable[string, UseCase]
    systemBoundaries*: OrderedTable[string, SystemBoundary]
    relationships*: seq[Relationship]
    notes*: OrderedTable[string, UsecaseNote]
    jsonNodes*: OrderedTable[string, UsecaseJsonNode]
    classDefs*: OrderedTable[string, ClassDef]
    direction*: string
    title*: string         ## "" for undefined
    accTitle*, accDescr*: string
    accDescription*: string
      ## The accessible description as written, before the indentation of its lines is dropped.
    source*: string
    headerSpan*: Span

const
  # Arrow
  SOLID_ARROW* = 0
  BACK_ARROW* = 1
  LINE_SOLID* = 2
  CIRCLE_ARROW* = 3
  CROSS_ARROW* = 4
  CIRCLE_ARROW_REVERSED* = 5
  CROSS_ARROW_REVERSED* = 6

proc emptyModel*(): UsecaseModel =
  UsecaseModel(direction: "LR")
