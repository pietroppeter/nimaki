## port-of: src/svg/root.ts
## port-status: draft
import std/[strutils, sets, options]
import ../types
import builder, palette, theme
import ../js

const WEIGHTS = [("tw", "title"), ("hw", "heading"), ("w", "bold")]
  ## The weights of bold text, each set only in a diagram that has such text.

type Accessible* = object
  accTitle*, accDescr*: string   ## "" for undefined

func usedNames(content: string): HashSet[string] =
  ## the names matched by /var\(--_(r|tw|hw|w)\)/g, up to four
  var p = content.find("var(--_")
  while p != -1:
    let at = p + 7
    for name in ["r", "tw", "hw", "w"]:
      if content.continuesWith(name & ")", at):
        result.incl name
        break
    if result.len == 4: break
    p = content.find("var(--_", at)

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
  let used = usedNames(content)
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
