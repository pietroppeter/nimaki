## port-of: src/window.ts
## port-status: conformant
##
## The window an element is in, and the room it has. For the JavaScript build only.
when defined(js):
  import dom

  proc windowOf*(element: JsObject): JsObject =
    ## The window an element is in, which is not the script's own when the element is in a
    ## popup. Styles and resizes are asked of that window: another window's answers can be late
    ## or absent.
    if not element.ownerDocument.isNullish:
      let w = element.ownerDocument.defaultView
      if not w.isNullish: return w
    globalThisObject()

  proc room*(element, style: JsObject): float =
    ## The width inside an element's padding, or 0 when it has none yet.
    let width = num(element.clientWidth) - floatOr0(style.paddingLeft) - floatOr0(style.paddingRight)
    if width > 0: width else: 0.0
