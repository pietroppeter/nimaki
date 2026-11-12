## nimaki: Pele, the Mermaid renderer, in Nim. `render(text, options)` is the entry point, as
## `render` of Pele's `src/core.ts` is.
##
## Today this is the shape of the API and nothing behind it: every diagram type raises a
## `PeleError` with code `unsupported`, which `tools/difftest.nim` counts as not ported yet.
## The step that ports `src/core.ts` (`api` on the roadmap) replaces this file with the port,
## and each diagram type, as it is ported, registers itself here.

type
  PeleError* = object of CatchableError
    ## An error Pele would throw: `code` is one of Pele's codes (`syntax`, `semantic`, `limit`,
    ## ...), or `unsupported` for what nimaki does not draw yet.
    code*: string
    diagramType*: string

  RenderOptions* = object
    ## The options difftest passes to both sides. More of Pele's `RenderOptions` arrive with
    ## the port of `src/types.ts`.
    now*: float   ## the time gantt treats as now, in milliseconds since 1970 (UTC)

  RenderResult* = object
    diagramType*: string   ## Pele's `type`
    svg*: string
    width*, height*: float

proc newPeleError*(message, code: string, diagramType = ""): ref PeleError =
  (ref PeleError)(msg: message, code: code, diagramType: diagramType)

proc render*(text: string, options = RenderOptions()): RenderResult =
  ## Draws Mermaid `text` as SVG, or raises `PeleError`.
  raise newPeleError("nimaki does not draw any diagram type yet", "unsupported")
