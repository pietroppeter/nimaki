## port-of: src/svg/title.ts
## port-status: conformant
import std/math
import ../text/[label, measurer]
import ../text/math as pmath
import builder

proc titleLabel*(title: string, measurer: TextMeasurer, size, maxWidth: float): Label =
  ## Mermaid draws diagram titles as text, whatever they hold. `title` "" for undefined.
  withoutMath(proc (): Label = layoutLabel(title, false, measurer, size, maxWidth, Bold))

type Titled* = object
  width*, height*: float
  content*: string

proc withTitle*(title: string, measurer: TextMeasurer, size, pad, width, height: float,
                content: string): Titled =
  ## Puts a diagram title above content that was laid out without one.
  let label = titleLabel(title, measurer, size, 4000)
  if label.height == 0: return Titled(width: width, height: height, content: content)
  let shift = label.height + 12
  let full = max(width, ceil(label.width + 2 * pad))
  Titled(width: full, height: ceil(height + shift),
         content: labelSvg(label, full / 2, pad + label.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
           "<g transform=\"translate(" & num((full - width) / 2) & "," & num(shift) & ")\">" & content & "</g>")
