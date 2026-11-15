## port-of: src/svg/title.ts
## port-status: conformant
import std/math
import ../text/[label, measurer]
import ../text/math as pmath
import builder
import ../js

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
  # Field by field, and `content` handed over: a Titled built whole is copied into `result` in
  # nim js, `content` with it. The callers pass content they do not keep.
  if label.height == 0:
    result.width = width
    result.height = height
    handOver(result.content, content)
    return
  let shift = label.height + 12
  let full = max(width, ceil(label.width + 2 * pad))
  result.width = full
  result.height = ceil(height + shift)
  handOver(result.content, labelSvg(label, full / 2, pad + label.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g transform=\"translate(" & num((full - width) / 2) & "," & num(shift) & ")\">" & content & "</g>")
