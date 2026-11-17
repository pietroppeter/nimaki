## port-of: src/text/math.ts
## port-status: conformant
import std/[tables, math]
import ../js

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
var found = newTable[string, MathMarkup]()   # a ref: saving and restoring it copies nothing (nim js copies a Table)

proc withMath*[T](math: MathResolver, run: proc (): T): T =
  let outer = resolver
  let outerFound = found
  resolver = math
  found = if math == nil: nil else: newTable[string, MathMarkup]()   # only read when there is a resolver
  try:
    handOver(result, run())
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
  if resolver == nil:
    handOver(result, run())
    return
  let outer = resolver
  resolver = nil
  try:
    handOver(result, run())
  finally:
    resolver = outer
