## port-of: src/diagrams/usecase/types.ts
## port-status: conformant
##
## Optional strings are "" for undefined where Pele treats an empty string as absent too. The
## positions of each statement's parts (`statements`) are kept as Pele keeps them, for editors:
## nothing that is drawn reads them.
import std/[options, tables]
import json
import ../../model

type
  Span* = (int, int)
    ## Start and end offsets in the source, end exclusive.

  LabelType* = enum ltText = "text", ltMarkdown = "markdown"

  Stylable* = ref object of RootObj
    ## What `class` and `style` statements reach: an actor, use case, boundary, JSON node or edge.
    classes*: seq[string]
    styles*: seq[string]

  Actor* = ref object of Stylable
    id*, label*: string
    labelType*: LabelType
    kind*: string          ## type: normal, hollow, awesome or icon
    icon* {.undefinedIfEmpty.}: string
    business*: bool
    stereotype* {.undefinedIfEmpty.}: string
    parentId* {.undefinedIfEmpty.}: string

  UseCase* = ref object of Stylable
    id*, label*: string
    labelType*: LabelType
    shape*: string         ## ellipse or rect
    business*: bool
    stereotype* {.undefinedIfEmpty.}: string
    parentId* {.undefinedIfEmpty.}: string

  SystemBoundary* = ref object of Stylable
    id*, label*: string
    labelType*: LabelType
    kind*: string          ## type: rect or package
    members*: seq[string]

  Relationship* = ref object of Stylable
    id*: string
    explicitId*: bool
    source*, target*: string
    kind*: string          ## type: association, include, extend or generalization
    arrowType*: int
    label* {.undefinedIfEmpty.}: string
    labelType*: Option[LabelType]   ## none when there is no label
    minlen*: int
    animate*: bool
    animation* {.undefinedIfEmpty.}: string

  UsecaseNote* = ref object
    id*, target*, label*: string
    labelType*: LabelType

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

  MetadataOccurrence* = object
    key*: string
    span*, keySpan*, valueSpan*: Span

  NodeOccurrence* = object
    id*: string
    span*, idSpan*: Span
    labelSpan*: Option[Span]
    defines*: Option[bool]           ## some(true) or none, as Pele sets it only when true
    stereotypeSpan*: Option[Span]
    metadata*: Option[seq[MetadataOccurrence]]
    classSpans*: Option[seq[Span]]

  EdgeOccurrence* = object
    id*: string
    span*: Span
    labelSpan*, idSpan*: Option[Span]
    metadata*: Option[seq[MetadataOccurrence]]

  GraphStatement* = ref object
    ## One statement of the source with the positions of its parts, as in Mermaid's use case AST.
    statementKind*: string
      ## Pele's `kind` (node, edge, group, note, json, metadata, edgeMetadata...): `kind` is the
      ## port's name for Pele's `type`, so src/nimaki/modeljson.nim names this one back.
    span*: Span
    nodes*: Option[seq[NodeOccurrence]]
    edges*: Option[seq[EdgeOccurrence]]
    group*: Option[string]
    idSpan*, titleSpan*, endSpan*: Option[Span]
    `ref`*: Option[string]
    refSpan*: Option[Span]
    children*: Option[seq[GraphStatement]]
    metadata*: Option[seq[MetadataOccurrence]]
    classSpans*: Option[seq[Span]]

  UsecaseModel* = ref object of RootObj
    actors*: OrderedTable[string, Actor]
    useCases*: OrderedTable[string, UseCase]
    systemBoundaries*: OrderedTable[string, SystemBoundary]
    relationships*: seq[Relationship]
    notes*: OrderedTable[string, UsecaseNote]
    jsonNodes*: OrderedTable[string, UsecaseJsonNode]
    classDefs*: OrderedTable[string, ClassDef]
    direction*: string
    title* {.undefinedIfEmpty.}: string
    accTitle*, accDescr*: string
    accDescription*: string
      ## The accessible description as written, before the indentation of its lines is dropped.
    source*: string
    headerSpan*: Span
    statements*: seq[GraphStatement]

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
