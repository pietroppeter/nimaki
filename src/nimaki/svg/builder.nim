## port-of: src/svg/builder.ts
## port-status: draft
import std/[strutils, math]
import ../text/[entities, measurer, label, icons]
import ../text/math as pmath
import ../js, ../jsregex

func isInvalidXml(c: int): bool =
  ## [\x00-\x08\x0b\x0c\x0e-\x1f\x7f\ud800-\udfff￾￿] (with the u flag: lone surrogates)
  (c >= 0 and c <= 8) or c == 0x0b or c == 0x0c or (c >= 0x0e and c <= 0x1f) or c == 0x7f or
    (c >= 0xd800 and c <= 0xdfff) or c == 0xfffe or c == 0xffff

func invalidAt(s: string, i: int): (bool, int) =
  ## Whether an invalid XML character starts at byte i, and its length. A byte that is not
  ## valid UTF-8 counts as one (JavaScript strings cannot hold one; a lone surrogate is the
  ## nearest thing, and it is dropped). This stays a scanner (decision 0015): Pele's regexes
  ## find lone surrogates, which here are bytes that are not UTF-8, and no regex over code points
  ## can match those.
  let (cp, size) = codePointAt(s, i)
  if cp == 0xFFFD and not s.continuesWith("�", i): return (true, size)
  (isInvalidXml(cp), size)

func hasInvalidXml*(text: string): bool =
  ## RE_INVALID_XML.test(text). Removing these characters in esc() can make validated values
  ## unsafe.
  var i = 0
  while i < text.len:
    let (bad, size) = invalidAt(text, i)
    if bad: return true
    i += size

func esc*(text: string): string =
  ## Escapes text for XML and drops invalid XML characters and DEL.
  var i = 0
  while i < text.len:
    let c = text[i]
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    else:
      let (bad, size) = invalidAt(text, i)
      if not bad: result.add text[i ..< i + size]
      i += size
      continue
    inc i

proc escText*(text: string): string =
  ## Escapes text that is only ever read as text: a tooltip, an accessible name, a `data-id`.
  ## Entity codes are turned into their characters first. A value that was checked before it
  ## is written, such as a style, a colour or a URL, must go through esc() instead, so that
  ## what was checked is what is written.
  esc(decodeEntities(text))

func fraction(i: int): string =
  ## The two decimals of a coordinate, by hundredths.
  if i == 0: "" elif i mod 10 == 0: "." & $(i div 10) elif i < 10: ".0" & $i else: "." & $i

func num*(value: float): string =
  let n = jsRound(value * 100)
  if n == 0: return "0"
  if n > 0:
    if n < 1e11:
      let k = int64(n)
      let q = k div 100
      return $q & fraction(int(k - q * 100))
  elif n > -1e11:
    let m = int64(-n)
    let q = m div 100
    return "-" & $q & fraction(int(m - q * 100))
  jsString(n / 100)

func spanStyle*(style: int): string

func sharedStyle*(label: Label): int

func textStyle*(attrs: string, shared: int): string

type MathLook = object
  attrs: string
  halo: string
  hasHalo: bool

proc mathLook(attrs: string): MathLook

proc mathSvg(math: MathMarkup, box: string, size: float, attrs: string): string

proc labelSvg*(label: Label, cx, cy: float, attrs: string, icons: IconResolver = nil): string =
  ## Writes a measured label as SVG text centered on (cx, cy).
  let lines = label.lines
  if lines.len == 0: return ""
  let lh = label.lineHeight
  let heights = label.heights
  let shift = label.size * 0.35
  var top = cy - label.height / 2

  if lines.len == 1 and lines[0].len == 1:
    let only = lines[0][0]
    if not only.hasIcon and only.math == nil and only.style == 0:
      return "<text" & attrs & " x=\"" & num(cx) & "\" y=\"" & num(top + lh / 2 + shift) &
        "\" text-anchor=\"middle\">" & esc(only.text) & "</text>"

  let shared = sharedStyle(label)
  let given = attrs
  var math: MathLook
  var hasLook = false
  let attrs = textStyle(attrs, shared)
  var body = ""
  var extra = ""
  for i in 0 ..< lines.len:
    let line = lines[i]
    let h = if heights.len > 0: heights[i] else: lh
    let mid = top + h / 2
    let y = mid + shift
    var placed = false
    for span in line:
      if span.hasIcon or span.math != nil: placed = true
    if placed:
      var x = cx - label.widths[i] / 2
      for span in line:
        if span.math != nil:
          let box = "x=\"" & num(x) & "\" y=\"" & num(mid - span.math.height / 2) & "\" width=\"" &
            num(span.math.width) & "\" height=\"" & num(span.math.height) & "\""
          if not hasLook:
            math = mathLook(given)
            hasLook = true
          extra.add(if not math.hasHalo: mathSvg(span.math, box, label.size, math.attrs)
                    else: "<rect " & box & " rx=\"2\" fill=\"" & math.halo & "\"/>")
        elif span.hasIcon:
          let side = label.size * 1.1
          let inner = if icons != nil: icons(span.icon) else: ""
          extra.add "<svg class=\"pele-icon\" data-icon=\"" & escText(span.icon) & "\" x=\"" & num(x) &
            "\" y=\"" & num(mid - side / 2) & "\" width=\"" & num(side) & "\" height=\"" & num(side) &
            "\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
            inner & "</svg>"
        elif span.text != "":
          body.add "<tspan x=\"" & num(x) & "\" y=\"" & num(y) & "\" text-anchor=\"start\"" &
            spanStyle(span.style and not shared) & ">" & esc(span.text) & "</tspan>"
        x += span.width
    else:
      for j in 0 ..< line.len:
        let span = line[j]
        let pos = if j == 0: " x=\"" & num(cx) & "\" y=\"" & num(y) & "\"" else: ""
        body.add "<tspan" & pos & spanStyle(span.style and not shared) & ">" & esc(span.text) & "</tspan>"
      if line.len == 0: body.add "<tspan x=\"" & num(cx) & "\" y=\"" & num(y) & "\"> </tspan>"
    top += h
  "<text" & attrs & " text-anchor=\"middle\" xml:space=\"preserve\">" & body & "</text>" & extra

const
  RE_FILL = jsre"""/ fill="([^"]*)"/"""
  RE_STROKE = jsre"""/ stroke="([^"]*)"/"""
  RE_STYLE = jsre"""/ style="([^"]*)"/"""
  RE_STYLE_FILL = jsre"/(?:^|;)\s*fill:([^;]*)/"
  RE_STYLE_OPACITY = jsre"/(?:^|;)\s*opacity:([^;]*)/"

proc mathLook(attrs: string): MathLook =
  ## Copy only color and opacity to preserve measured math dimensions. Use a solid patch for
  ## the cluster title's outline to hide edges behind math.
  let style = RE_STYLE.exec(attrs).groupOr(1, "")
  let fill = jsTrim(RE_STYLE_FILL.exec(style).groupOr(1, RE_FILL.exec(attrs).groupOr(1, "")))
  if fill == "none":
    return MathLook(attrs: "", halo: RE_STROKE.exec(attrs).groupOr(1, "none"), hasHalo: true)
  let opacity = RE_STYLE_OPACITY.exec(style)
  MathLook(attrs: (if fill == "": "" else: " color=\"" & fill & "\"") &
                  (if opacity.found and jsTrim(opacity[1]) != "": " opacity=\"" & jsTrim(opacity[1]) & "\"" else: ""))

proc mathSvg(math: MathMarkup, box: string, size: float, attrs: string): string =
  ## Resolver markup is trusted.
  if math.isSvg:
    return "<svg class=\"pele-math\" " & box & " overflow=\"visible\"" & attrs & ">" & math.markup & "</svg>"
  "<foreignObject class=\"pele-math\" " & box & " overflow=\"visible\"" & attrs & ">" &
    "<div xmlns=\"http://www.w3.org/1999/xhtml\" style=\"display:flex;align-items:center;justify-content:center;width:100%;height:100%;font-size:" &
    num(size) & "px;line-height:normal;white-space:nowrap\">" & math.markup & "</div>" &
    "</foreignObject>"

const
  BOLD_ATTR = " font-weight=\"var(--_w)\""
  ITALIC_ATTR = " font-style=\"italic\""
  UNDERLINE_ATTR = " text-decoration=\"underline\""
  MONO_ATTR = " font-family=\"var(--_fm)\""
  SUB_ATTR = " baseline-shift=\"sub\" font-size=\"smaller\""
  SUP_ATTR = " baseline-shift=\"super\" font-size=\"smaller\""

func spanStyle*(style: int): string =
  (if (style and Bold) != 0: BOLD_ATTR else: "") &
    (if (style and Italic) != 0: ITALIC_ATTR else: "") &
    (if (style and Mono) != 0: MONO_ATTR else: "") &
    (if (style and Underline) != 0: UNDERLINE_ATTR else: "") &
    (if (style and Sub) != 0: SUB_ATTR elif (style and Sup) != 0: SUP_ATTR else: "")

func sharedStyle*(label: Label): int =
  ## The emphasis every span of a label has. It is written once, on the text element, where a
  ## CSS rule for the label reaches it.
  var shared = Bold or Italic or Mono
  var any = false
  for line in label.lines:
    for span in line:
      if span.hasIcon or span.text == "": continue
      shared = shared and span.style
      any = true
  if any: shared else: 0

func textStyle*(attrs: string, shared: int): string =
  ## Adds that emphasis to a text element's attributes, unless they give a weight of their own.
  attrs &
    (if (shared and Bold) != 0 and " font-weight=\"" notin attrs: BOLD_ATTR else: "") &
    (if (shared and Italic) != 0 and " font-style=\"" notin attrs: ITALIC_ATTR else: "") &
    (if (shared and Mono) != 0 and " font-family=\"" notin attrs: MONO_ATTR else: "")
