## port-of: src/mount.ts
## port-status: conformant
##
## A diagram put in an element of a page and kept fitted to it: drawn again when the element
## changes width or the fonts finish loading, with the last good drawing kept, dimmed, under an
## error. For the JavaScript build only.
##
## As in zoom.nim, Pele's one function with its local state stays one proc with the same
## variables and inner procs, and what comes from the page or the host (the element, the
## options, the engine's models and results) stays a JavaScript value. The engine is an object
## with `parse(text, options)` and `render(model, options)`: nimaki's own, in web.nim, or one a
## test gives.
when defined(js):
  import dom, window, zoom
  import text/measurer

  # The fonts CSS gives the diagram. A variable may be set on the drawing itself, which the
  # element that holds it does not inherit, so a drawing that is there is the one asked.
  type Fonts = tuple[family, mono: JsObject]   ## undefined where none is set

  proc nonEmptyOrUndefined(s: cstring): JsObject =
    if s.len == 0: jsUndefined else: toJs(s)

  proc fontsFor(style, drawing: JsObject): Fonts =
    let own = if drawing.isNullish: style else: windowOf(drawing).getComputedStyle(drawing)
    var family = nonEmptyOrUndefined(jsTrimmed(own.getPropertyValue("--pele-font")))
    if family.isUndefined and truthy(style.fontFamily): family = style.fontFamily
    (family: family, mono: nonEmptyOrUndefined(jsTrimmed(own.getPropertyValue("--pele-font-mono"))))

  proc sameFonts(a, b: Fonts): bool = same(a.family, b.family) and same(a.mono, b.mono)

  proc fontSets(element: JsObject): seq[JsObject] {.importjs: """((element) => {
    const sets = new Set([element.ownerDocument?.fonts, globalThis.document?.fonts]);
    return [...sets].filter((fonts) => fonts !== undefined);
  })(#)""".}
    ## The fonts a diagram is drawn with: those of the element's document, which its CSS names,
    ## and those of the script's, which measures with its canvas.

  # Fonts that are still loading, as one promise for each set however many diagrams wait on it.
  # Widths measured before they load are those of a fallback, so they are forgotten once then.
  let settling = newWeakMap()

  proc settled(fonts: JsObject): JsObject =
    var done = settling.get(fonts)
    if done.isNullish:
      done = fonts.ready.then(fn(proc () =
        settling.invoke("delete", fonts)
        forgetTextWidths()))
      discard settling.set(fonts, done)
    done

  proc promiseAll(list: seq[JsObject]): JsObject {.importjs: "Promise.all(#)".}

  # Tells a diagram that fonts it was drawn while waiting for have loaded. The wait holds it
  # weakly, as it does the element, so that one the page drops while fonts load can be collected.
  let onFontsLoaded = newWeakMap()

  proc afterFonts(loading: seq[JsObject], diagram: JsObject) =
    var promises: seq[JsObject]
    for fonts in loading: promises.add settled(fonts)
    discard promiseAll(promises).then(fn(proc () =
      let handle = diagram.deref()
      if not handle.isNullish:
        let f = onFontsLoaded.get(handle)
        if not f.isNullish: discard call0(f)))

  let mounts = newWeakMap()
  var mounted = 0
  # Another copy of Pele on the page counts its own diagrams.
  let copy = randomId()

  # An error over a drawing takes no room: it is pulled up over the drawing's bottom edge by its
  # own height. One with no drawing above it is shown whole, in the monospace its caret lines up in.
  const OVER_STYLE =
    "position:relative;height:1.3em;margin-top:-1.3em;line-height:1.3;font-size:0.8em;" &
    "color:var(--pele-error,#e45756);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"
  const ALONE_STYLE =
    "margin:0;font-size:0.8em;font-family:var(--pele-font-mono,monospace);" &
    "color:var(--pele-error,#e45756);white-space:pre-wrap;"

  proc summary(message: cstring): cstring {.importjs: """((message) => {
    const lines = message.split('\n').filter((line) => line.trim() !== '');
    return lines.length > 1 ? lines[0] + ' ' + lines[lines.length - 1] : (lines[0] ?? '');
  })(#)""".}
    ## A parse error's first line says where it is, and its last line what is wrong.

  proc renderOptions(rest: JsObject, idPrefix: cstring, fonts: Fonts): JsObject =
    ## `{ ...rest, idPrefix: rest.idPrefix ?? idPrefix, fontFamily: rest.fontFamily ?? fonts.family,
    ## fontFamilyMono: rest.fontFamilyMono ?? fonts.mono, maxWidth: undefined }`
    result = copyOf(rest)
    result.idPrefix = orElse(rest.idPrefix, toJs(idPrefix))
    result.fontFamily = orElse(rest.fontFamily, fonts.family)
    result.fontFamilyMono = orElse(rest.fontFamilyMono, fonts.mono)
    result.maxWidth = jsUndefined

  proc withMaxWidth(base: JsObject, width: float): JsObject =
    result = copyOf(base)
    result.maxWidth = width

  proc mountWith*(engine, element: JsObject, text: cstring, options: JsObject = nil): JsObject =
    ## Puts a diagram in an element and keeps it fitted to the element's width. The element
    ## should be one whose width does not depend on what it holds, such as a block.
    block:
      let before = mounts.get(element)
      if not before.isNullish: before.invoke("destroy")

    var source = text
    var settings = if options.isNullish: jsObj() else: options
    var model: JsObject = jsUndefined
    # The model of what is shown, drawn again for a change of width or fonts while the text last
    # given cannot be drawn.
    var drawnModel: JsObject = jsUndefined
    # Whether the model is that of the text last given, with the options given with it.
    var current = false
    var error: JsObject = jsUndefined
    var natural: JsObject = jsUndefined
    var shown: JsObject = jsUndefined
    # Ids in one drawing must not be those of another in the same page.
    inc mounted
    let idPrefix = cstring("pele-" & $copy & "-" & $mounted)
    var fonts: Fonts = (jsUndefined, jsUndefined)
    # Whether the width there is can change how this diagram is drawn. Not known until asked.
    var adapts: JsObject = jsUndefined
    var drawnFor = -1.0
    var stale = false
    var waiting = false
    var destroyed = false
    var handle: JsObject

    proc fit(style: JsObject, fresh: bool): JsObject =
      let rest = without(settings, "onRender", "onError", "sanitize")
      let base = renderOptions(rest, idPrefix, fonts)
      if fresh:
        natural = engine.render(model, base)
        adapts = jsUndefined
      let available = if settings.maxWidth.isNullish: room(element, style) else: num(settings.maxWidth)
      drawnFor = available
      if available > 0 and available < num(natural.width):
        # Drawn for no room at all, a diagram that the width can change comes out differently.
        if adapts.isNullish:
          adapts = toJs(not same(engine.render(model, withMaxWidth(base, 1)).svg, natural.svg))
        if adapts.isTrue: return engine.render(model, withMaxWidth(base, available))
      natural

    proc put(svg: JsObject) =
      if truthy(settings.sanitize): discard element.replaceChildren(call1(settings.sanitize, svg))
      else: element.innerHTML = svg

    # Shows the error, if there is one, over the drawing or in its place. The drawing is dimmed.
    var errorElement: JsObject = nil
    proc mark() =
      let drawing = if shown.isNullish: JsObject(nil) else: firstChild(element)
      if not drawing.isNullish and truthy(drawing.style):
        drawing.style.opacity = (if error.isUndefined: cstring"" else: cstring"0.4")
      if error.isUndefined:
        if not errorElement.isNullish: discard errorElement.remove()
        errorElement = nil
        return
      let doc = element.ownerDocument
      if not truthy(doc): return
      if errorElement.isNullish: errorElement = doc.createElement("div")
      errorElement.className = cstring"pele pele-error"
      let message = errorMessage(error)
      if not drawing.isNullish:
        errorElement.textContent = summary(message)
        errorElement.title = message
        errorElement.setAttr("style", OVER_STYLE)
        if not same(errorElement.parentNode, element): discard element.append(errorElement)
      else:
        errorElement.textContent = message
        discard errorElement.removeAttribute("title")
        errorElement.setAttr("style", ALONE_STYLE)
        discard element.replaceChildren(errorElement)

    proc fail(failure: JsObject) =
      error = failure
      mark()
      if truthy(settings.onError): discard call1(settings.onError, failure)

    proc awaitFonts() =
      if waiting or destroyed: return
      var loading: seq[JsObject]
      for fonts in fontSets(element):
        if fonts.status.to(cstring) == "loading": loading.add fonts
      if loading.len == 0: return
      waiting = true
      afterFonts(loading, newWeakRef(handle))

    var refresh: proc ()
    proc fontsLoaded() =
      waiting = false
      stale = true
      refresh()

    # Made after the first drawing, and again when the option changes.
    var zoomer: JsObject = nil
    var zooming: JsObject = toJs(false)

    # A quiet draw leaves the element alone when it would show the same thing.
    proc draw(fresh: bool, quiet: bool) =
      let style = windowOf(element).getComputedStyle(element)
      let drawing = firstChild(element)
      let before = (fonts, natural, adapts, drawnFor, stale)
      var next: JsObject
      try:
        if fresh:
          fonts = fontsFor(style, drawing)
          stale = element.isConnected.isFalse
        next = fit(style, fresh)
        if quiet and not shown.isNullish and same(next.svg, shown.svg):
          if fresh: drawnModel = model
          if current and not error.isUndefined:
            error = jsUndefined
            mark()
          return
        put(next.svg)
      except:
        # The element is as it was, and so is what it was drawn for.
        (fonts, natural, adapts, drawnFor, stale) = before
        raise
      if fresh: drawnModel = model
      if fresh and drawing.isNullish and not firstChild(element).isNullish:
        let seen = fontsFor(style, firstChild(element))
        if not sameFonts(seen, fonts):
          let first = (fonts, natural, adapts, drawnFor)
          fonts = seen
          try:
            let second = fit(style, true)
            put(second.svg)
            next = second
          except:
            # What was drawn for the element's own font is in the element, and stays, whether
            # the drawing or the host's sanitizer failed.
            (fonts, natural, adapts, drawnFor) = first
      # From here the drawing is the one shown. Nothing above throws once the element has changed.
      shown = next
      if current: error = jsUndefined
      mark()
      if not zoomer.isNullish: zoomer.invoke("refresh")
      awaitFonts()
      if truthy(settings.onRender): discard call1(settings.onRender, next)

    proc zoom() =
      let wanted = orElse(settings.zoom, toJs(cstring"auto"))
      if same(wanted, zooming): return
      if not zoomer.isNullish: zoomer.invoke("destroy")
      zooming = wanted
      # The diagram's observer tells the zoom when the element's size changes.
      if wanted.isFalse: zoomer = nil
      else:
        var how: JsObject
        if wanted.isObject: how = wanted
        else:
          how = jsObj()
          how.always = wanted.isTrue
        zoomer = zoomWith(element, how, false)

    proc hidden(): bool = element.isConnected.isFalse or not positive(element.clientWidth)
    # One out of the document is drawn as a guess, so that it shows the text when it is put back
    # before the observer can see it, at the size it had. A hidden one in the document waits.
    proc waits(): bool = not element.isConnected.isFalse and not positive(element.clientWidth)

    # Observed from the window the element is in now, which changes if a host moves it to
    # another: an observer reports only on its own window's frames.
    var view: JsObject = nil
    var observer: JsObject = nil
    var frame: JsObject = jsUndefined
    proc cancelFrame() =
      if not frame.isUndefined and not view.isNullish: discard view.cancelAnimationFrame(frame)
      frame = jsUndefined
    proc watch() =
      let next = windowOf(element)
      if same(next, view): return
      if not observer.isNullish: discard observer.disconnect()
      cancelFrame()
      view = next
      observer =
        if truthy(next.ResizeObserver):
          construct1(next.ResizeObserver, fn(proc () =
            if not frame.isUndefined: return
            if not truthy(next.requestAnimationFrame):
              refresh()
              return
            frame = next.requestAnimationFrame(fn(proc () =
              frame = jsUndefined
              refresh()))))
        else: nil
      if not observer.isNullish: discard observer.observe(element)

    refresh = proc () =
      if destroyed: return
      watch()
      if model.isNullish or hidden(): return
      let style = windowOf(element).getComputedStyle(element)
      let now = fontsFor(style, firstChild(element))
      try:
        if stale or not sameFonts(now, fonts):
          draw(true, true)
        elif not adapts.isFalse and settings.maxWidth.isUndefined:
          let available = room(element, style)
          # An element that wraps the drawing follows its width, which is not a change of room.
          if available != drawnFor and (shown.isNullish or available != num(shown.width)):
            draw(false, true)
      except:
        let failure = caughtError()
        # What is shown stays, and is not drawn again until something else changes. A drawing of
        # text since replaced keeps the error of the text that replaced it.
        stale = false
        if current: error = failure
        # Text given while the element was hidden could not be drawn. What is shown is drawn
        # again for a change of width or fonts, and the error stays until other text is given.
        if not same(model, drawnModel):
          model = drawnModel
          current = false
        mark()
        if truthy(settings.onError): discard call1(settings.onError, failure)
      if not zoomer.isNullish: zoomer.invoke("resized")
      awaitFonts()

    proc update(next: cstring, nextOptions: JsObject) =
      let reparse =
        not current or next != source or
        not same(nextOptions.limit, settings.limit) or
        not same(nextOptions.maxEdges, settings.maxEdges) or
        not same(nextOptions.config, settings.config)
      # The options stand whether or not the text can be drawn.
      source = next
      settings = nextOptions
      var nextModel = model
      if reparse:
        try:
          nextModel = engine.parse(next, nextOptions)
        except:
          # The last text that could be parsed is drawn for a change of width or fonts, or once
          # a hidden element is shown.
          current = false
          fail(caughtError())
          zoom()
          return
      let was = shown
      model = nextModel
      current = true
      if waits():
        stale = true
        zoom()
        return
      try:
        draw(true, false)
      except:
        let failure = caughtError()
        # If the element has the new drawing, it was the host's onRender that threw, and the
        # update stands. Otherwise the element is as it was.
        if not same(shown, was):
          zoom()
          jsThrow(failure)
        model = drawnModel
        current = false
        fail(failure)
      zoom()

    handle = jsObj()
    handle.defineGetter("result", fn(proc (): JsObject = shown))
    handle.defineGetter("source", fn(proc (): cstring = source))
    handle.defineGetter("error", fn(proc (): JsObject = error))
    handle.defineGetter("zoom", fn(proc (): JsObject = (if zoomer.isNullish: jsUndefined else: zoomer)))
    handle.update = fn(proc (next: cstring, nextOptions: JsObject) =
      update(next, if nextOptions.isUndefined: settings else: nextOptions))
    handle.refresh = fn(proc () = refresh())
    handle.destroy = fn(proc () =
      destroyed = true
      if not observer.isNullish: discard observer.disconnect()
      observer = nil
      cancelFrame()
      view = nil
      if not zoomer.isNullish: zoomer.invoke("destroy")
      onFontsLoaded.invoke("delete", handle)
      if same(mounts.get(element), handle): mounts.invoke("delete", element))
    discard onFontsLoaded.set(handle, fn(fontsLoaded))
    try:
      model = engine.parse(text, settings)
      current = true
      draw(true, false)
    except:
      let failure = caughtError()
      # A drawing in place means the host's onRender threw.
      if not shown.isNullish: jsThrow(failure)
      model = drawnModel
      current = false
      fail(failure)
    zoom()
    watch()
    discard mounts.set(element, handle)
    handle
