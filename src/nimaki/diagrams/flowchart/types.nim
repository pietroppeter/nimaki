## port-of: src/diagrams/flowchart/types.ts
## port-status: draft
##
## A field that may be `undefined` and is never `""` when set is a `string` with `""` for
## undefined; a number that may be undefined is NaN, or `NO_LENGTH` for an edge's length.
import std/[options, tables]
import ../../util/yaml

type
  LabelType* = string  ## 'text' | 'string' | 'markdown'

  FlowText* = object
    text*: string
    `type`*: LabelType

  FlowNode* = ref object
    id*: string
    text*: Option[string]
    labelType*: LabelType
    `type`*: string            ## "" for undefined
    styles*: seq[string]
    classes*: seq[string]
    dir*: string               ## "" for undefined
    props*: Table[string, string]
    link*: string              ## "" for undefined
    linkTarget*: string
    icon*: string
    form*: string
    pos*: string
    img*: string
    constraint*: string
    assetWidth*: float         ## NaN for undefined
    assetHeight*: float

  FlowEdge* = ref object
    start*: string
    `end`*: string
    `type`*: string            ## "" for undefined
    text*: string
    labelType*: LabelType
    stroke*: string            ## "" for undefined
    length*: int               ## NO_LENGTH for undefined
    style*: seq[string]        ## empty for undefined (Pele only pushes from it)
    classes*: seq[string]
    id*: string
    isUserDefinedId*: bool
    interpolate*: string       ## "" for undefined
    animate*: YamlValue        ## nil for undefined
    animation*: YamlValue

  FlowClassDef* = ref object
    id*: string
    styles*: seq[string]
    textStyles*: seq[string]

  FlowSubgraph* = ref object
    id*: string
    nodes*: seq[string]
    title*: string
    classes*: seq[string]
    dir*: string               ## "" for undefined
    labelType*: LabelType
    metadata*: YamlValue       ## a record, or nil for undefined

  FlowLinkInfo* = object
    ## Pele's `LinkInfo` of `types.ts` (renamed: the core's `LinkInfo` is a link in the SVG).
    `type`*: string
    stroke*: string
    length*: int               ## NO_LENGTH for undefined
    text*: Option[FlowText]
    id*: string                ## "" for undefined

  DocKind* = enum dkString, dkList, dkDir
  DocItem* = object
    ## `string | string[] | { stmt: 'dir'; value: string }`
    case kind*: DocKind
    of dkString: s*: string
    of dkList: items*: seq[string]
    of dkDir: value*: string

const NO_LENGTH* = int.low
