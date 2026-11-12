## port-of: src/core.ts
## port-status: draft
##
## `mount` and `enableZoom` belong to the browser and are not ported. A diagram type Pele draws
## that nimaki has not ported yet raises a PeleError with code `unsupported`, which difftest
## counts as not ported.
import std/[tables, options]
import detect, errors, preprocess, types, js
import text/[entities, icons]
import text/math as pmath
import svg/palette
import util/yaml

var diagrams = initTable[string, Diagram]()

proc register*(list: varargs[Diagram]) =
  ## Makes diagram types available to render() and parse().
  for diagram in list: diagrams[diagram.diagramType] = diagram

proc registered*(kind: string): bool = kind in diagrams

const DEFAULT_LIMIT = 50000
  ## Mermaid's default maxTextSize.
const DEFAULT_OUTPUT_LIMIT = 4_000_000
  ## Mermaid has no limit on its output. A source within the limit can still describe a drawing
  ## of many megabytes, which would stall the page it is put into.
const DEFAULT_MAX_EDGES = 5000
  ## Mermaid stops at 500. Pele draws 5,000 edges in tens of milliseconds, and `A & B --> C & D`
  ## multiplies: without a limit, a few kilobytes of source ask for millions of edges.

proc guarded[T](run: proc (): T): T =
  ## Deep nesting can exhaust the stack in a few recursive spots. Report it as a limit, not a
  ## crash.
  try:
    result = run()
  except JsRangeError:
    raise newPeleError("Diagram is nested too deeply.", "limit")

proc tagErrors[T](found: Detected, run: proc (): T): T =
  try:
    result = run()
  except JsRangeError:
    raise newPeleError("Diagram is nested too deeply.", "limit",
                       ErrorInfo(diagramType: found.diagramType, mermaidType: found.mermaidType))
  except PeleError as error:
    if error.diagramType == "": error.diagramType = found.diagramType
    if error.mermaidType == "": error.mermaidType = found.mermaidType
    error.msg = writtenCodes(error.msg)
    error.snippet = writtenCodes(error.snippet)
    raise

type Parsed = object
  found: Detected
  diagram: Diagram
  model: RootRef
  config: Config

proc inSource(text: string, keepComments: bool): proc (at: int): (string, int) =
  ## Record preprocessing edits only when a source position is needed.
  var steps: Steps = nil
  var source = ""
  result = proc (at: int): (string, int) =
    if steps == nil:
      steps = new seq[seq[Edit]]
      let pre = preprocess(text, steps)
      discard encodeEntities(if keepComments: pre.withComments else: cleanupComments(pre.withComments, steps), steps)
      # Match the line break appended for parsing.
      source = normalizeLineBreaks(text) & "\n"
    (source, inputOffset(steps[], at))

proc parseSource(text: string, limit: int, maxEdges: int, extra: Config): Parsed =
  if utf16Len(text) > limit:
    raise newPeleError("Diagram source is longer than the limit of " & $limit & " characters.", "limit")
  let pre = preprocess(text)
  let (ok, found) = detectDiagram(pre.text)
  if not ok:
    raise newPeleError("No diagram type detected for the given text.", "unsupported-diagram")
  if found.diagramType notin diagrams:
    raise newPeleError("nimaki does not draw " & found.diagramType & " yet.", "unsupported",
                       ErrorInfo(diagramType: found.diagramType, mermaidType: found.mermaidType))
  let diagram = diagrams[found.diagramType]
  var config = pre.config
  if extra != nil and isRecord(extra):
    config = ymap()
    for k, v in extra.fields: config.fields[k] = v
    for k, v in pre.config.fields: config.fields[k] = v
  let keepComments = diagram.keepComments
  let parsed = encodeEntities(if keepComments: pre.withComments else: pre.text) & "\n"
  let cfg = config
  let model = tagErrors(found, proc (): RootRef =
    locatingIn(Origin(parsed: parsed, find: inSource(text, keepComments)), proc (): RootRef =
      diagram.parse(parsed, cfg, pre.title, pre.lineOffset, ParseLimits(maxEdges: maxEdges))))
  Parsed(found: found, diagram: diagram, model: model, config: config)

proc detectType*(text: string): string =
  ## The diagram type, or "" for none.
  detect(preprocess(text).text)

proc supports*(text: string): bool =
  try:
    let kind = detectType(text)
    kind != "" and kind in diagrams
  except CatchableError:
    false

proc render*(source: string, options = RenderOptions()): RenderResult =
  ## Draws Mermaid `source` as SVG, or raises PeleError.
  guarded(proc (): RenderResult =
    let parsed = parseSource(source, options.limit.get(DEFAULT_LIMIT),
                             options.maxEdges.get(DEFAULT_MAX_EDGES), options.config)
    let kind = parsed.found.diagramType
    let diagram = parsed.diagram
    let section = parsed.config[if diagram.section != "": diagram.section else: kind]
    let useMaxWidth = section["useMaxWidth"]
    let fixed = isRecord(section) and useMaxWidth != nil and useMaxWidth.kind == yBool and not useMaxWidth.b
    var opts = options
    if opts.responsive.isNone: opts.responsive = some(not fixed)
    # The host's icon resolver and the ids in `links` see names as the author meant them, with
    # entity codes turned into their characters, as `data-icon` and `data-id` in the SVG do.
    let resolve = options.icons
    if resolve != nil:
      opts.icons = proc (name: string): string = resolve(decodeEntities(name))
    let model = parsed.model
    let config = parsed.config
    var rendered = tagErrors(parsed.found, proc (): Rendered =
      withPalette(palette(kind, config), proc (): Rendered =
        withMath(if diagram.math: options.math else: nil, proc (): Rendered =
          withIcons(opts.icons, proc (): Rendered = diagram.render(model, config, opts)))))
    let outputLimit = options.outputLimit.get(DEFAULT_OUTPUT_LIMIT)
    if utf16Len(rendered.svg) > outputLimit:
      raise newPeleError("Diagram output is longer than the limit of " & $outputLimit & " characters.",
                         "limit", ErrorInfo(diagramType: kind, mermaidType: parsed.found.mermaidType))
    for link in rendered.links.mitems: link.id = decodeEntities(link.id)
    RenderResult(diagramType: kind, mermaidType: parsed.found.mermaidType, svg: rendered.svg,
                 width: rendered.width, height: rendered.height, links: rendered.links))
