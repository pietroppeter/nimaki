## port-of: src/text/icons.ts
## port-status: draft
##
## The host's icons for the render in progress. A label leaves room for an icon only when the
## host has one by that name, and layout has to know that before anything is drawn.
import std/tables

type IconResolver* = proc (name: string): string
  ## Returns the icon's SVG markup, or "" when the host has none (Pele's null and undefined).

var resolver: IconResolver
var found = initTable[string, string]()

proc withIcons*[T](icons: IconResolver, run: proc (): T): T =
  let outer = resolver
  let outerFound = found
  resolver = icons
  found = initTable[string, string]()
  try:
    result = run()
  finally:
    resolver = outer
    found = outerFound

proc iconMarkup*(name: string): string =
  if resolver == nil: return ""
  if name in found: return found[name]
  result = resolver(name)
  found[name] = result
