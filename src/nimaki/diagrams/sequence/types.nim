## port-of: src/diagrams/sequence/types.ts
## port-status: conformant
##
## `const enum LINETYPE` and `PLACEMENT` are `LINETYPE_name` and `PLACEMENT_name` constants. A
## message kind that is `undefined` is `NO_TYPE`. The statement list Mermaid's grammar builds
## (`SeqItem`: a statement, a string, or a list of items) is a variant `ref object`. JSON values
## of the actor menus are `JsonNode` of `std/json`.
import std/[options, tables, json]

export options, tables, json

const
  LINETYPE_SOLID* = 0
  LINETYPE_DOTTED* = 1
  LINETYPE_NOTE* = 2
  LINETYPE_SOLID_CROSS* = 3
  LINETYPE_DOTTED_CROSS* = 4
  LINETYPE_SOLID_OPEN* = 5
  LINETYPE_DOTTED_OPEN* = 6
  LINETYPE_LOOP_START* = 10
  LINETYPE_LOOP_END* = 11
  LINETYPE_ALT_START* = 12
  LINETYPE_ALT_ELSE* = 13
  LINETYPE_ALT_END* = 14
  LINETYPE_OPT_START* = 15
  LINETYPE_OPT_END* = 16
  LINETYPE_ACTIVE_START* = 17
  LINETYPE_ACTIVE_END* = 18
  LINETYPE_PAR_START* = 19
  LINETYPE_PAR_AND* = 20
  LINETYPE_PAR_END* = 21
  LINETYPE_RECT_START* = 22
  LINETYPE_RECT_END* = 23
  LINETYPE_SOLID_POINT* = 24
  LINETYPE_DOTTED_POINT* = 25
  LINETYPE_AUTONUMBER* = 26
  LINETYPE_CRITICAL_START* = 27
  LINETYPE_CRITICAL_OPTION* = 28
  LINETYPE_CRITICAL_END* = 29
  LINETYPE_BREAK_START* = 30
  LINETYPE_BREAK_END* = 31
  LINETYPE_PAR_OVER_START* = 32
  LINETYPE_BIDIRECTIONAL_SOLID* = 33
  LINETYPE_BIDIRECTIONAL_DOTTED* = 34
  LINETYPE_SOLID_TOP* = 41
  LINETYPE_SOLID_BOTTOM* = 42
  LINETYPE_STICK_TOP* = 43
  LINETYPE_STICK_BOTTOM* = 44
  LINETYPE_SOLID_ARROW_TOP_REVERSE* = 45
  LINETYPE_SOLID_ARROW_BOTTOM_REVERSE* = 46
  LINETYPE_STICK_ARROW_TOP_REVERSE* = 47
  LINETYPE_STICK_ARROW_BOTTOM_REVERSE* = 48
  LINETYPE_SOLID_TOP_DOTTED* = 51
  LINETYPE_SOLID_BOTTOM_DOTTED* = 52
  LINETYPE_STICK_TOP_DOTTED* = 53
  LINETYPE_STICK_BOTTOM_DOTTED* = 54
  LINETYPE_SOLID_ARROW_TOP_REVERSE_DOTTED* = 55
  LINETYPE_SOLID_ARROW_BOTTOM_REVERSE_DOTTED* = 56
  LINETYPE_STICK_ARROW_TOP_REVERSE_DOTTED* = 57
  LINETYPE_STICK_ARROW_BOTTOM_REVERSE_DOTTED* = 58
  LINETYPE_CENTRAL_CONNECTION* = 59
  LINETYPE_CENTRAL_CONNECTION_REVERSE* = 60
  LINETYPE_CENTRAL_CONNECTION_DUAL* = 61

const
  PLACEMENT_LEFTOF* = 0
  PLACEMENT_RIGHTOF* = 1
  PLACEMENT_OVER* = 2

const NO_TYPE* = -1
  ## A message, statement or note field `type?: number` that is undefined.

type
  SeqText* = object
    text*: string
    wrap*: Option[bool]

  SeqBoxData* = object
    text*: Option[string]
    color*: string
    wrap*: Option[bool]

  SeqBox* = ref object
    name*: Option[string]
    wrap*: bool
    fill*: string
    actorKeys*: seq[string]

  SeqActor* = ref object
    box*: SeqBox                       ## nil: in no box
    name*: string
    description*: string
    wrap*: bool
    prevActor*: string                 ## "" for undefined (an id is never empty)
    nextActor*: string
    links*: OrderedTable[string, JsonNode]
    properties*: OrderedTable[string, JsonNode]
    details*: Option[string]
      ## The id of the page element named by a `details` statement. Pele has no page to read it from.
    kind*: string                      ## Pele's `type`

  SeqNumbering* = object
    start*: float                      ## NaN for undefined
    step*: float                       ## NaN for undefined
    visible*: bool

  SeqMessage* = object
    id*: string
    start*: Option[string]             ## Pele's `from`
    to*: Option[string]
    message*: string                   ## the text, when `numbering` is false
    isNumbering*: bool                 ## `message` is a SeqNumbering (an autonumber statement)
    numbering*: SeqNumbering
    wrap*: bool
    kind*: int                         ## Pele's `type`; NO_TYPE for undefined
    activate*: bool
    placement*: int                    ## NO_TYPE for undefined
    centralConnection*: int

  SeqNote* = object
    actor*: seq[string]                ## one id, or two for a note over two participants
    placement*: int
    message*: string
    wrap*: bool

  SeqStatement* = ref object
    ## One entry of the statement list the parser hands to `apply`, as Mermaid's grammar builds it.
    ## The block statements keep their text (loopText, optText, altText, parText, criticalText,
    ## optionText, breakText, color) in `blockText`, which is what `apply` reads for each.
    kind*: string                      ## Pele's `type`
    actor*: string
    actors*: seq[string]               ## the two ids of a note
    draw*: string                      ## "" for undefined
    description*: Option[SeqText]
    config*: Option[string]
    signalType*: int                   ## NO_TYPE for undefined
    start*: string                     ## Pele's `from`
    to*: string
    msg*: SeqText
    activate*: bool
    centralConnection*: int
    placement*: int
    text*: SeqText
    boxData*: SeqBoxData
    boxText*: string
    blockText*: Option[SeqText]
    sequenceIndex*: float              ## NaN for undefined
    sequenceIndexStep*: float          ## NaN for undefined
    sequenceVisible*: bool

  SeqItemKind* = enum siStatement, siString, siList
  SeqItem* = ref object
    case kind*: SeqItemKind
    of siStatement: statement*: SeqStatement
    of siString: s*: string
    of siList: items*: seq[SeqItem]

func item*(s: SeqStatement): SeqItem = SeqItem(kind: siStatement, statement: s)
func item*(s: string): SeqItem = SeqItem(kind: siString, s: s)
func item*(items: seq[SeqItem]): SeqItem = SeqItem(kind: siList, items: items)
