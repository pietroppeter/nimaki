## port-of: src/svg/root.ts
## port-status: draft
import std/[sets, options]
import ../types
import builder, palette, theme
import ../js, ../jsregex

const WEIGHTS = [("tw", "title"), ("hw", "heading"), ("w", "bold")]
  ## The weights of bold text, each set only in a diagram that has such text.

type Accessible* = object
  accTitle*, accDescr*: string   ## "" for undefined

const RE_USED = jsre"/var\(--_(r|tw|hw|w)\)/g"

proc svgDocument*(kind: string, width, height: float, fontSize: float, options: RenderOptions,
                  acc: Accessible, content: string): string =
  let prefix = esc(options.idPrefix.get("pele"))
  var head = ""
  var aria = ""
  if acc.accTitle != "":
    head.add "<title id=\"" & prefix & "-title\">" & escText(acc.accTitle) & "</title>"
    aria.add " aria-labelledby=\"" & prefix & "-title\""
  if acc.accDescr != "":
    head.add "<desc id=\"" & prefix & "-desc\">" & escText(acc.accDescr) & "</desc>"
    aria.add " aria-describedby=\"" & prefix & "-desc\""
  let fit = if options.responsive == some(false): "" else: "max-width:100%;height:auto;"
  var used: HashSet[string]
  for m in RE_USED.matches(content):
    used.incl m[1]
    if used.len == 4: break
  var weights = if "r" in used: ";--_r:" & RADIUS else: ""
  for (alias, name) in WEIGHTS:
    if alias in used: weights.add ";--_" & alias & ":var(--pele-" & name & "-weight,bold)"
  "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"pele pele-" & kind & "\" viewBox=\"0 0 " &
    jsString(width) & " " & jsString(height) & "\" width=\"" & jsString(width) & "\" height=\"" &
    jsString(height) &
    "\" style=\"" & fit & ROOT_STYLE & weights &
    esc(fontStyle(fontSize, options.fontFamily, options.fontFamilyMono)) & paletteStyle() &
    "\" fill=\"var(--_fg)\" role=\"graphics-document document\" aria-roledescription=\"" & kind &
    "\"" & aria & ">" & head & content & "</svg>"
