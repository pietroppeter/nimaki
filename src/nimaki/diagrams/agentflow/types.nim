## port-of: src/diagrams/agentflow/types.ts
## port-status: conformant
##
## As in the flowchart's types: a string that may be undefined and is never `""` when set is a
## `string` with `""` for undefined; an edge's length is `NO_LENGTH` when undefined. Pele's
## element mappings and diagnostics are for tools that read the text, and nothing drawn reads
## them; they are kept, as Pele's model has them. The semantic model is `semanticModel` in db.nim.
import std/[options, tables]
import ../../util/yaml
import ../../model

type
  LabelType* = string  ## 'text' | 'string' | 'markdown'

  FlowText* = object
    text*: string
    kind*: LabelType

  Loc* = object
    ## A source span as Jison reports it: lines start at 1, columns (UTF-16 code units) at 0.
    firstLine*, firstColumn*, lastLine*, lastColumn*: int

  ElementPosition* = ref object
    startLine*, startColumn*, endLine*, endColumn*: int
    startIndex*, endIndex*: int    ## always 0: Mermaid builds its parser without ranges

  ElementMapping* = ref object
    ## Where a statement sits in the source.
    id*: string
    kind*: string                  ## type: vertex, edge, subgraph, connector or attachment
    position*: ElementPosition

  Diagnostic* = ref object
    id*: string                    ## SHAPE_UNSUPPORTED, SHAPE_REMOVED, CONTAINMENT_VIOLATION...
    severity*: string              ## warning or error
    message*: string
    nodeId* {.undefinedIfEmpty.}: string
    edgeId* {.undefinedIfEmpty.}: string
    position*: ElementPosition     ## nil for undefined

  MappingSet* = object
    ## Pele's `Set` of mappings, held as a list: a set of references would hash their addresses,
    ## which the JavaScript build does not have.
    items*: seq[ElementMapping]

  AgentNode* = ref object
    id*: string
    text*: Option[string]
    labelType*: LabelType
    kind* {.undefinedIfEmpty.}: string              ## Pele's `type`, "" for undefined
    styles*: seq[string]
    classes*: seq[string]
    dir* {.undefinedIfEmpty.}: string               ## "" for undefined
    props*: Option[Table[string, string]]   ## none for a connector that no statement names as a node
    link* {.undefinedIfEmpty.}: string              ## "" for undefined
    linkTarget* {.undefinedIfEmpty.}: string
    metadata*: YamlValue       ## nil for undefined
    isConnector*: Option[bool]   ## some(true) for a connector, none otherwise

  AgentEdge* = ref object
    start*: string
    stop*: string
    kind* {.undefinedIfEmpty.}: string              ## "" for undefined
    text*: string
    labelType*: LabelType
    stroke* {.undefinedIfEmpty.}: string            ## "" for undefined
    edgeSemantic* {.undefinedIfEmpty.}: string      ## "" for undefined
    length*: int               ## NO_LENGTH for undefined
    style*: Option[seq[string]]   ## none until a linkStyle sets it
    classes*: seq[string]
    id*: string
    isUserDefinedId*: bool
    interpolate* {.undefinedIfEmpty.}: string       ## "" for undefined
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
    dir* {.undefinedIfEmpty.}: string               ## "" for undefined
    labelType*: LabelType
    kind*: string              ## type: always flow
    metadata*: YamlValue       ## nil for undefined

  LinkInfo* = object
    kind*: string
    stroke*: string
    length*: int               ## NO_LENGTH for undefined
    edgeSemantic* {.undefinedIfEmpty.}: string      ## "" for undefined
    text*: Option[FlowText]
    id* {.undefinedIfEmpty.}: string                ## "" for undefined

  DocKind* = enum dkString, dkList, dkDir
  DocItem* = object
    ## `string | string[] | { stmt: 'dir'; value: string }`
    case kind*: DocKind
    of dkString: s*: string
    of dkList: items*: seq[string]
    of dkDir: value*: string

const NO_LENGTH* = int.low
