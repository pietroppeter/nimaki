## port-of: src/diagrams/agentflow/types.ts
## port-status: draft
##
## As in the flowchart's types: a string that may be undefined and is never `""` when set is a
## `string` with `""` for undefined; an edge's length is `NO_LENGTH` when undefined. Pele's
## element mappings, diagnostics and semantic model are for tools that read the text, and
## nothing drawn reads them: the port leaves them out.
import std/[options, tables]
import ../../util/yaml

type
  LabelType* = string  ## 'text' | 'string' | 'markdown'

  FlowText* = object
    text*: string
    kind*: LabelType

  Loc* = object
    ## A source span as Jison reports it: lines start at 1, columns (UTF-16 code units) at 0.
    firstLine*, firstColumn*, lastLine*, lastColumn*: int

  AgentNode* = ref object
    id*: string
    text*: Option[string]
    labelType*: LabelType
    kind*: string              ## Pele's `type`, "" for undefined
    styles*: seq[string]
    classes*: seq[string]
    dir*: string               ## "" for undefined
    props*: Table[string, string]
    link*: string              ## "" for undefined
    linkTarget*: string
    metadata*: YamlValue       ## nil for undefined
    isConnector*: bool

  AgentEdge* = ref object
    start*: string
    stop*: string
    kind*: string              ## "" for undefined
    text*: string
    labelType*: LabelType
    stroke*: string            ## "" for undefined
    edgeSemantic*: string      ## "" for undefined
    length*: int               ## NO_LENGTH for undefined
    style*: seq[string]
    classes*: seq[string]
    id*: string
    isUserDefinedId*: bool
    interpolate*: string       ## "" for undefined
    animate*: YamlValue        ## nil for undefined
    animation*: YamlValue
    metadata*: YamlValue

  AgentClassDef* = ref object
    id*: string
    styles*: seq[string]
    textStyles*: seq[string]

  AgentSubgraph* = ref object
    id*: string
    nodes*: seq[string]
    title*: string
    classes*: seq[string]
    dir*: string               ## "" for undefined
    labelType*: LabelType
    metadata*: YamlValue       ## nil for undefined

  LinkInfo* = object
    kind*: string
    stroke*: string
    length*: int               ## NO_LENGTH for undefined
    edgeSemantic*: string      ## "" for undefined
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
