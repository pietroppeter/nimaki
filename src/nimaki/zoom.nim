## port-of: src/zoom.ts
## port-status: conformant
##
## Zoom and pan of a drawing inside its own box: by pinching, by the wheel with Ctrl or ⌘ held,
## by dragging, by a double click, and from the keyboard. `frame` is plain arithmetic and is in
## both builds; the rest works on a page's elements and is in the JavaScript build only.
##
## Pele writes the zoom as one function whose local variables and inner functions are its state,
## and the port keeps that shape: `zoomWith` holds the same variables and the same inner procs,
## in the same order, and returns the same object. Values that come from the page (the element,
## its style, an event, the options) stay JavaScript values (`JsObject`), so that a fake element
## of a test is read as Pele reads it.

type
  Frame* = object
    ## The part of the drawing its box shows.
    x*, y*, width*, height*: float

func within(at, view, whole: float): float =
  # A drawing larger than the view stops at its own edges. A smaller one stays whole inside it.
  if view >= whole: min(max(at, whole - view), 0.0)
  else: min(max(at, 0.0), whole - view)

func frame*(natural, box: tuple[width, height: float], scale, x, y: float): Frame =
  ## The part of a drawing that shows in a box at a scale. Enlarging a drawing never changes the
  ## size of anything around it: the box shows less of the drawing, larger.
  let width = box.width / scale
  let height = box.height / scale
  Frame(x: within(x, width, natural.width), y: within(y, height, natural.height),
        width: width, height: height)

when defined(js):
  import dom, window

  const
    STEP = 1.25
    PAN = 48.0
    GAP = 4.0

  # The class `pele` lets a page's rule for `.pele` give the buttons the diagram's colors, and the
  # variables let it move them: they sit over the diagram, where a page may have things of its own.
  const BAR_STYLE =
    "--_bg:var(--pele-bg,#fff);--_fg:var(--pele-fg,#1f1f1f);--_b:var(--pele-border,#8a8a8a);" &
    "position:absolute;top:var(--pele-zoom-top,8px);right:var(--pele-zoom-right,8px);" &
    "bottom:var(--pele-zoom-bottom,auto);left:var(--pele-zoom-left,auto);display:flex;flex-direction:column;gap:2px;padding:2px;" &
    "width:auto;max-width:none;border:1px solid var(--_b);border-radius:var(--pele-radius,4px);background:var(--_bg);color:var(--_fg);line-height:0"
  const BUTTON_STYLE =
    "appearance:none;display:grid;place-items:center;width:24px;height:24px;margin:0;padding:0;border:0;" &
    "border-radius:calc(var(--pele-radius,4px) - 1px);background:transparent;color:inherit;font:inherit;cursor:var(--pele-zoom-cursor,pointer)"
  const ICONS = [
    ("zoomIn", "M5 12h14M12 5v14"),
    ("zoomOut", "M5 12h14"),
    # Lucide's rotate-ccw. Its license is in Pele's LICENSE file, and in NOTICE here.
    ("reset", "M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8M3 3v5h5"),
  ]
  const LABELS = [("zoomIn", "Zoom in"), ("zoomOut", "Zoom out"), ("reset", "Reset zoom")]

  type Size = tuple[width, height: float]

  proc frameJs*(natural, box: JsObject, scale, x, y: float): JsObject =
    ## `frame` with JavaScript objects in and out, for a page or a test.
    let f = frame((num(natural.width), num(natural.height)), (num(box.width), num(box.height)), scale, x, y)
    result = jsObj()
    result.x = f.x
    result.y = f.y
    result.width = f.width
    result.height = f.height

  proc zoomWith*(element, options: JsObject, observe: bool): JsObject =
    ## The zoom of the drawing in `element`. `observe` is false when the caller (a mounted
    ## diagram) watches the element's size itself and calls `resized`.
    var svg: JsObject = nil
    var natural: Size = (0.0, 0.0)
    var rest: Size = (0.0, 0.0)
    # The box an enlarged drawing is shown in: the room its element already has, padding and
    # all, where that is more than the drawing takes at rest, as in a panel of a fixed height.
    var box: Size = (0.0, 0.0)
    var roomy = false
    var bleed = cstring""
    var restStyle = (width: JsObject(nil), height: JsObject(nil), maxWidth: JsObject(nil),
                     margin: JsObject(nil), display: JsObject(nil))
    var cleared = false
    var clearedBefore, clearedAfter: (JsObject, JsObject)
    # The scale shown, or 0 while the drawing rests at the size that fits.
    var scale = 0.0
    var x = 0.0
    var y = 0.0
    var watched = 0.0

    proc view(): JsObject = windowOf(element)
    proc fit(): float =
      if natural.width > 0 and rest.width > 0: rest.width / natural.width else: 1.0
    proc most(): float = mathMax(fit(), numberOr(options.maxScale, 3))
    proc zoomable(): bool =
      not svg.isNullish and natural.width > 0 and (options.always.isTrue or fit() < 0.999)

    proc measure() =
      if svg.isNullish or scale != 0: return
      let at = svg.getBoundingClientRect()
      rest = (num(at.width), num(at.height))
      box = (mathMax(rest.width, num(element.clientWidth)), mathMax(rest.height, num(element.clientHeight)))
      roomy = box.width > rest.width + 1 or box.height > rest.height + 1
      if not roomy: box = rest
      # Padding keeps a drawing at rest off the element's edges. An enlarged one is a view, which
      # reaches them: margins of the opposite size carry it over the padding.
      let style = view().getComputedStyle(element)
      var sides: seq[string]
      for side in ["top", "right", "bottom", "left"]:
        sides.add $numStr(-floatOr0(style.getPropertyValue(cstring("padding-" & side)))) & "px"
      bleed = cstring(sides[0] & " " & sides[1] & " " & sides[2] & " " & sides[3])

    var bar: JsObject = nil
    var buttons = (zoomIn: JsObject(nil), zoomOut: JsObject(nil), reset: JsObject(nil))
    var positioned = false

    # Inner procs that call each other, as Pele's do, are declared first and given later.
    var show: proc (next: float, clientX, clientY: JsObject)
    var settle: proc ()
    var take: proc (on: bool)

    proc offer() =
      if options.controls.isFalse: return
      let can = zoomable()
      if bar.isNullish:
        if not can: return
        let doc = element.ownerDocument
        bar = doc.createElement("div")
        bar.className = cstring"pele pele-zoom"
        bar.setAttr("style", BAR_STYLE)
        for (name, icon) in ICONS:
          let button = doc.createElement("button")
          var label = JsObject(nil)
          if not options.labels.isNullish: label = options.labels[name]
          if label.isNullish:
            for (n, l) in LABELS:
              if n == name: label = toJs(cstring(l))
          button.`type` = cstring"button"
          button.className = cstring("pele-zoom-" & (if name == "zoomIn": "in" elif name == "zoomOut": "out" else: "reset"))
          button.setAttr("style", BUTTON_STYLE)
          button.setAttribute("aria-label", label)
          button.title = label
          button.innerHTML = cstring("<svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"" & icon & "\"/></svg>")
          let act =
            case name
            of "zoomIn": fn(proc () = show((if scale != 0: scale else: fit()) * STEP * STEP, nil, nil))
            of "zoomOut": fn(proc () = show((if scale != 0: scale else: fit()) / (STEP * STEP), nil, nil))
            else: fn(proc () = settle())
          button.addEventListener("click", act)
          case name
          of "zoomIn": buttons.zoomIn = button
          of "zoomOut": buttons.zoomOut = button
          else: buttons.reset = button
          bar.append(button)
      # The buttons are placed against the element, which has to be what they are measured from.
      if can and not positioned and view().getComputedStyle(element).position.to(cstring) == "static":
        element.style.position = cstring"relative"
        positioned = true
      if can and not same(bar.parentNode, element): element.append(bar)
      bar.hidden = not can
      bar.style.display = (if can: cstring"flex" else: cstring"none")
      proc dim(button: JsObject, off: bool) =
        if button.isNullish: return
        button.disabled = off
        button.style.opacity = (if off: cstring"0.35" else: cstring"")
        button.style.cursor = (if off: cstring"default" else: cstring"var(--pele-zoom-cursor,pointer)")
      dim(buttons.zoomIn, (if scale != 0: scale else: fit()) >= most() * 0.999)
      dim(buttons.zoomOut, scale == 0)
      if not buttons.reset.isNullish:
        buttons.reset.style.display = (if scale == 0: cstring"none" else: cstring"grid")

    proc ours(event: JsObject): bool =
      not bar.isNullish and instanceOfNode(view(), event.target) and bar.contains(event.target).to(bool)

    proc unclear() =
      if svg.isNullish or not cleared: return
      # Preserve later style changes made by the page.
      if same(svg.style.maxWidth, clearedAfter[0]): svg.style.maxWidth = clearedBefore[0]
      if same(svg.style.marginRight, clearedAfter[1]): svg.style.marginRight = clearedBefore[1]
      cleared = false

    proc restore() =
      if svg.isNullish: return
      unclear()
      svg.style.width = restStyle.width
      svg.style.height = restStyle.height
      svg.style.maxWidth = restStyle.maxWidth
      svg.style.margin = restStyle.margin
      svg.style.display = restStyle.display

    # Narrows a drawing whose text the buttons hide at rest. The right margin keeps centered and
    # right-aligned drawings clear of them too.
    proc clear() =
      if svg.isNullish or bar.isNullish or bar.hidden.truthy: return
      let at = bar.getBoundingClientRect()
      let texts = toArray(svg.querySelectorAll("text"))
      var hidden = false
      for i in 0 ..< texts.len:
        let r = texts[i].getBoundingClientRect()
        if num(r.right) > num(at.left) and num(r.left) < num(at.right) and
           num(r.bottom) > num(at.top) and num(r.top) < num(at.bottom):
          hidden = true
          break
      let drawing = svg.getBoundingClientRect()
      let finish = num(at.left) - GAP
      if not hidden or num(drawing.right) - finish >= num(drawing.width) / 2: return
      # Account for transforms and CSS zoom when setting styles.
      let outer = element.getBoundingClientRect()
      let k = if positive(element.offsetWidth): num(outer.width) / num(element.offsetWidth) else: 1.0
      let padding = floatOr0(view().getComputedStyle(element).paddingRight)
      let edge = num(outer.left) + (num(element.clientLeft) + num(element.clientWidth) - padding) * k
      clearedBefore = (svg.style.maxWidth, svg.style.marginRight)
      svg.style.maxWidth = cstring($numStr((finish - num(drawing.left)) / k) & "px")
      svg.style.marginRight = cstring($numStr(mathMax(edge - finish, 0) / k) & "px")
      clearedAfter = (svg.style.maxWidth, svg.style.marginRight)
      cleared = true
      if num(svg.getBoundingClientRect().right) > finish + 1: unclear()
      measure()

    settle = proc () =
      if svg.isNullish: return
      restore()
      scale = 0
      svg.setAttr("viewBox", cstring("0 0 " & $numStr(natural.width) & " " & $numStr(natural.height)))
      svg.style.cursor = cstring""
      svg.style.userSelect = cstring""
      measure()
      # One finger still scrolls the page. Two are left to the drawing.
      svg.style.touchAction = (if zoomable(): cstring"pan-y" else: cstring"")
      if zoomable(): svg.setAttr("tabindex", "0")
      else: svg.removeAttribute("tabindex")
      take(zoomable())
      offer()
      clear()

    proc place(toX, toY: float) =
      if svg.isNullish: return
      let shown = frame(natural, box, scale, toX, toY)
      x = shown.x
      y = shown.y
      svg.setAttr("viewBox", cstring($numStr(x) & " " & $numStr(y) & " " & $numStr(shown.width) & " " & $numStr(shown.height)))

    # Shows the drawing at a scale, keeping the point under (clientX, clientY) where it is.
    show = proc (next: float, clientX, clientY: JsObject) =
      if svg.isNullish: return
      if scale == 0: measure()
      if not zoomable(): return
      let start = if scale != 0: scale else: fit()
      let to = mathMin(mathMax(next, fit()), most())
      if to <= fit() * 1.001:
        settle()
        return
      let before = svg.getBoundingClientRect()
      let atX = if clientX.isNullish: num(before.left) + num(before.width) / 2 else: num(clientX)
      let atY = if clientY.isNullish: num(before.top) + num(before.height) / 2 else: num(clientY)
      let pointX = (if scale != 0: x else: 0.0) + (atX - num(before.left)) / start
      let pointY = (if scale != 0: y else: 0.0) + (atY - num(before.top)) / start
      scale = to
      var after = before
      if roomy:
        svg.style.maxWidth = cstring"none"
        svg.style.margin = bleed
        # An inline drawing sits on a line of text, with room under it for descenders. That room
        # is part of the box, so left in place it would make the element taller.
        svg.style.display = cstring"block"
        svg.style.width = cstring($numStr(box.width) & "px")
        svg.style.height = cstring($numStr(box.height) & "px")
        after = svg.getBoundingClientRect()
      place(pointX - (atX - num(after.left)) / scale, pointY - (atY - num(after.top)) / scale)
      svg.style.cursor = cstring"grab"
      svg.style.userSelect = cstring"none"
      svg.style.touchAction = cstring"none"
      offer()

    proc move(dx, dy: float) =
      if scale != 0: place(x - dx / scale, y - dy / scale)

    var observer: JsObject = nil
    var observed: JsObject = nil
    var resized: proc ()
    proc watch() =
      if not observe: return
      let next = view()
      if same(next, observed): return
      if not observer.isNullish: discard observer.disconnect()
      observed = next
      observer = if truthy(next.ResizeObserver): construct1(next.ResizeObserver, fn(proc () = resized())) else: nil
      if not observer.isNullish: observer.invoke("observe", element)

    resized = proc () =
      watch()
      let size = num(element.clientWidth) + num(element.clientHeight)
      if size == watched: return
      watched = size
      settle()

    proc refresh() =
      watch()
      if scale != 0: restore()
      else: unclear()
      let first = element.firstElementChild
      svg = if truthy(first) and first.localName.to(cstring) == "svg": first else: nil
      scale = 0
      if svg.isNullish:
        if not bar.isNullish: discard bar.remove()
        take(false)
        return
      natural = (numOr0(svg.getAttribute("width")), numOr0(svg.getAttribute("height")))
      restStyle = (width: svg.style.width, height: svg.style.height, maxWidth: svg.style.maxWidth,
                   margin: svg.style.margin, display: svg.style.display)
      settle()

    let pointers = newMap()
    var dragged = false
    var travelled = 0.0
    var pinch = 0.0

    proc point(event: JsObject): JsObject =
      result = jsObj()
      result.x = event.clientX
      result.y = event.clientY

    proc spread(): tuple[distance, x, y: float] =
      let both = toArray(pointers.values())
      let a = both[0]
      let b = both[1]
      (mathHypot(num(a.x) - num(b.x), num(a.y) - num(b.y)), (num(a.x) + num(b.x)) / 2, (num(a.y) + num(b.y)) / 2)

    # A pinch may not fire a click; reset before the page can stop pointerdown.
    proc onPress() =
      dragged = false

    proc onPointerDown(event: JsObject) =
      if not zoomable() or ours(event) or (event.pointerType.to(cstring) == "mouse" and num(event.button) != 0): return
      discard pointers.set(event.pointerId, point(event))
      travelled = 0
      if num(pointers.size) == 2: pinch = spread().distance
      if num(pointers.size) == 2 or scale != 0:
        element.optCall("setPointerCapture", event.pointerId)
        if not svg.isNullish: svg.style.cursor = cstring"grabbing"

    proc onPointerMove(event: JsObject) =
      let last = pointers.get(event.pointerId)
      if last.isNullish: return
      if num(pointers.size) == 2:
        let before = spread()
        discard pointers.set(event.pointerId, point(event))
        let now = spread()
        if pinch > 0 and now.distance > 0:
          show((if scale != 0: scale else: fit()) * (now.distance / before.distance), toJs(now.x), toJs(now.y))
        move(now.x - before.x, now.y - before.y)
        dragged = true
        return
      discard pointers.set(event.pointerId, point(event))
      if scale == 0: return
      travelled += mathAbs(num(event.clientX) - num(last.x)) + mathAbs(num(event.clientY) - num(last.y))
      if travelled > 4: dragged = true
      move(num(event.clientX) - num(last.x), num(event.clientY) - num(last.y))

    proc onPointerUp(event: JsObject) =
      if not pointers.invoke("delete", event.pointerId).to(bool): return
      pinch = 0
      if num(pointers.size) == 0 and not svg.isNullish and scale != 0: svg.style.cursor = cstring"grab"

    # A drag that ends over a link is not a click on it. Keyboard clicks have detail 0.
    proc onClick(event: JsObject) =
      if not dragged or num(event.detail) == 0: return
      dragged = false
      discard event.preventDefault()
      discard event.stopPropagation()

    proc onWheel(event: JsObject) =
      # Without the key, the wheel is the page's. With it, the browser would zoom the whole page.
      if not (truthy(event.ctrlKey) or truthy(event.metaKey)) or not zoomable(): return
      discard event.preventDefault()
      if scale == 0: measure()
      # A notch of a mouse wheel is a hundred or more. A pinch on a trackpad sends many small ones.
      let turn = mathMin(mathMax(-num(event.deltaY), -24), 24)
      show((if scale != 0: scale else: fit()) * pow2(turn * 0.02), event.clientX, event.clientY)

    proc onDoubleClick(event: JsObject) =
      if not zoomable() or ours(event): return
      discard event.preventDefault()
      if scale != 0: settle()
      else: show(mathMax(1, fit() * 2), event.clientX, event.clientY)

    proc onKeyDown(event: JsObject) =
      if not zoomable() or ours(event) or truthy(event.ctrlKey) or truthy(event.metaKey) or truthy(event.altKey): return
      let key = $event.key.str
      let at = if scale != 0: scale else: fit()
      if key == "+" or key == "=": show(at * STEP, nil, nil)
      elif key == "-": show(at / STEP, nil, nil)
      elif scale == 0: return
      elif key == "0" or key == "Escape": settle()
      elif key == "ArrowLeft": move(PAN, 0)
      elif key == "ArrowRight": move(-PAN, 0)
      elif key == "ArrowUp": move(0, PAN)
      elif key == "ArrowDown": move(0, -PAN)
      else: return
      discard event.preventDefault()

    # Browsers ring a focused SVG after a click too, where an HTML element is only ringed when
    # the focus came from the keyboard. The drawing is treated as HTML is. Safari before 15.4 does
    # not know :focus-visible and throws, and there the ring stays.
    proc onFocus(event: JsObject) =
      if svg.isNullish or not same(event.target, svg): return
      var visible = true
      try:
        visible = svg.matches(":focus-visible").to(bool)
      except:
        discard
      svg.style.outline = (if visible: cstring"" else: cstring"none")

    # Safari on a Mac reports a trackpad pinch this way and no other.
    var gesture = 0.0
    proc onGestureStart(event: JsObject) =
      if not zoomable(): return
      discard event.preventDefault()
      if scale == 0: measure()
      gesture = if scale != 0: scale else: fit()
    proc onGestureChange(event: JsObject) =
      if gesture == 0: return
      discard event.preventDefault()
      show(gesture * num(event.scale), event.clientX, event.clientY)
    proc onGestureEnd() =
      gesture = 0

    proc capture(): JsObject =
      result = jsObj()
      result.capture = true
    proc active(): JsObject =
      result = jsObj()
      result.passive = false
    let listeners = [
      (cstring"pointerdown", fn(onPress), capture()),
      (cstring"pointerdown", fn(onPointerDown), JsObject(nil)),
      (cstring"pointermove", fn(onPointerMove), JsObject(nil)),
      (cstring"pointerup", fn(onPointerUp), JsObject(nil)),
      (cstring"pointercancel", fn(onPointerUp), JsObject(nil)),
      (cstring"click", fn(onClick), capture()),
      (cstring"dblclick", fn(onDoubleClick), JsObject(nil)),
      (cstring"keydown", fn(onKeyDown), JsObject(nil)),
      (cstring"focusin", fn(onFocus), JsObject(nil)),
    ]
    for (kind, listener, how) in listeners: element.listen(kind, listener, if how.isNil: jsUndefined else: how)
    # Taken only while the drawing can be enlarged. A wheel listener that may stop the wheel makes
    # the browser wait for the page's script before it scrolls, so a drawing that fits adds none.
    let gestures = [
      (cstring"wheel", fn(onWheel), active()),
      (cstring"gesturestart", fn(onGestureStart), active()),
      (cstring"gesturechange", fn(onGestureChange), active()),
      (cstring"gestureend", fn(onGestureEnd), active()),
    ]
    var taking = false
    take = proc (on: bool) =
      if on == taking: return
      taking = on
      for (kind, listener, how) in gestures:
        if on: element.listen(kind, listener, how)
        else: element.unlisten(kind, listener, how)
      if not on: gesture = 0

    watched = num(element.clientWidth) + num(element.clientHeight)
    refresh()

    result = jsObj()
    result.defineGetter("scale", fn(proc (): float = (if scale != 0: scale else: fit())))
    result.defineGetter("fit", fn(proc (): float = fit()))
    result.zoomBy = fn(proc (factor: float) = show((if scale != 0: scale else: fit()) * factor, nil, nil))
    result.zoomTo = fn(proc (next: float) = show(next, nil, nil))
    result.reset = fn(proc () = settle())
    result.refresh = fn(refresh)
    result.resized = fn(proc () = resized())
    result.destroy = fn(proc () =
      settle()
      unclear()
      if not svg.isNullish:
        svg.style.touchAction = cstring""
        svg.removeAttribute("tabindex")
      if not bar.isNullish: discard bar.remove()
      if positioned: element.style.position = cstring""
      if not observer.isNullish: discard observer.disconnect()
      take(false)
      for (kind, listener, how) in listeners: element.unlisten(kind, listener, if how.isNil: jsUndefined else: how))

  proc enableZoom*(element: JsObject, options: JsObject = nil): JsObject =
    ## Lets the drawing in an element be enlarged and moved about inside its own box: by
    ## pinching, by the wheel with Ctrl or ⌘ held, by dragging, by a double click, and from the
    ## keyboard.
    zoomWith(element, if options.isNullish: jsObj() else: options, true)
