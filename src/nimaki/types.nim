## port-of: src/types.ts
## port-status: conformant
##
## JavaScript's optional fields are `Option[T]` where Pele tells `undefined` from a value the
## type can hold; a nil proc is an absent function.
import std/options
import text/[measurer, icons]
import text/math as pmath
import preprocess

export options, IconResolver, MathResolver, MathMarkup

type
  RenderOptions* = object
    measurer*: TextMeasurer           ## `width` nil: Pele's default
    fontFamily*: string               ## the fonts labels are measured in ("" for undefined)
    fontFamilyMono*: string
    monospace*: seq[string]           ## 'members' | 'attributes' | 'files' | 'messages'
    fontSize*: Option[float]
    idPrefix*: Option[string]
    responsive*: Option[bool]
    maxWidth*: Option[float]          ## the width the host has for the diagram, in pixels
    autoDirection*: Option[bool]
    directionBreakpoint*: Option[float]
    padding*: Option[float]
    limit*: Option[int]
    outputLimit*: Option[int]
    maxEdges*: Option[int]            ## the most edges a flowchart may have
    linkSchemes*: Option[seq[string]]
    imageSchemes*: Option[seq[string]]
    links*: Option[bool]
    images*: Option[bool]
    linkRel*: Option[string]
    icons*: IconResolver
    math*: MathResolver
    config*: Config                   ## nil for undefined
    now*: Option[float]
      ## The time gantt charts treat as now, in milliseconds since 1970 (UTC); none for the
      ## current time. As in Pele, any finite number is a time, 0 included.

  LinkInfo* = object
    id*, href*: string
    internal*: bool

  Rendered* = object
    svg*: string
    width*, height*: float
    links*: seq[LinkInfo]

  RenderResult* = object
    diagramType*: string              ## Pele's `type`
    mermaidType*: string
    svg*: string
    width*, height*: float
    links*: seq[LinkInfo]

  ParseLimits* = object
    maxEdges*: int

  Diagram* = object
    ## What a diagram type provides. `source` has been through preprocessing and entity
    ## encoding and ends with a newline, as Mermaid's parsers expect. The model is a `ref`
    ## object of the type's own, passed as RootRef.
    diagramType*: string
    section*: string                  ## "" when it is the type's own name
    keepComments*: bool
    math*: bool
    parse*: proc (source: string, config: Config, title: string, lineOffset: int,
                  limits: ParseLimits): RootRef
    render*: proc (model: RootRef, config: Config, options: RenderOptions): Rendered

proc measurerOf*(options: RenderOptions): TextMeasurer =
  ## options.measurer ?? defaultMeasurer(options.fontFamily, options.fontFamilyMono)
  if options.measurer.width != nil: options.measurer
  else: defaultMeasurer(options.fontFamily, options.fontFamilyMono)
