## port-of: src/diagrams/common/icon.ts
## port-status: conformant
import ../../svg/builder
import ../../text/icons

proc iconSvg*(name: string, x, y, side: float, icons: IconResolver): string =
  ## A square for a named icon, in the form labels use. The host's resolver supplies the drawing,
  ## if any.
  "<svg class=\"pele-icon\" data-icon=\"" & escText(name) & "\" x=\"" & num(x) & "\" y=\"" & num(y) &
    "\" width=\"" & num(side) & "\" height=\"" & num(side) &
    "\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
    (if icons != nil: icons(name) else: "") & "</svg>"
