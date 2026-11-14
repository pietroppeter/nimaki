## port-of: src/text/math.ts
## port-status: conformant
import std/[tables, math]

type
  MathMarkup* = ref object
    ## Dimensions are in pixels. HTML requires the typesetter's CSS. `isSvg` tells which of
    ## Pele's two shapes it is: `{ svg, width, height }` or `{ html, width, height }`.
    isSvg*: bool
    markup*: string
    width*, height*: float

  MathResolver* = proc (tex: string, size: float): MathMarkup
    ## TeX excludes the $$ delimiters; font size is in pixels. nil for none.

var resolver: MathResolver
var found = initTable[string, MathMarkup]()

proc withMath*[T](math: MathResolver, run: proc (): T): T =
  let outer = resolver
  let outerFound = found
  resolver = math
  found = initTable[string, MathMarkup]()
  try:
    result = run()
  finally:
    resolver = outer
    found = outerFound

proc mathActive*(): bool = resolver != nil

func valid(size: float): bool = size.classify notin {fcNan, fcInf, fcNegInf} and size > 0

proc typeset*(tex: string, size: float): MathMarkup =
  if resolver == nil: return nil
  let key = $size & "\n" & tex
  if key in found: return found[key]
  let res = resolver(tex, size)
  let markup = if res != nil and valid(res.width) and valid(res.height): res else: nil
  found[key] = markup
  markup

proc withoutMath*[T](run: proc (): T): T =
  ## Match Mermaid: diagram titles stay plain text.
  if resolver == nil: return run()
  let outer = resolver
  resolver = nil
  try:
    result = run()
  finally:
    resolver = outer
