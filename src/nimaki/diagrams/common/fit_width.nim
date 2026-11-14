## port-of: src/diagrams/common/fit-width.ts
## port-status: conformant
import std/options
import ../../types

proc available(options: RenderOptions): (bool, float) =
  ## options.maxWidth, when it is a positive number
  if options.maxWidth.isSome and options.maxWidth.get > 0: (true, options.maxWidth.get)
  else: (false, 0.0)

proc fitWidth*(options: RenderOptions, natural, least: float,
               draw: proc (plot: float, narrow: bool): Rendered): Rendered =
  ## Draws a chart whose plot can be any width so that the whole diagram fits the width the
  ## host has. What surrounds the plot (labels, a legend) is only known once it is drawn, so the
  ## plot gives up the overflow and is drawn again. `narrow` tells the chart that it did not fit
  ## at its own width, for a chart that then arranges itself differently.
  result = draw(natural, false)
  let (has, avail) = available(options)
  if not has or result.width <= avail: return
  let floor = min(least, natural)
  var plot = natural
  result = draw(plot, true)
  var round = 0
  while round < 3 and result.width > avail and plot > floor:
    plot = max(floor, plot - (result.width - avail))
    result = draw(plot, true)
    inc round

proc titleRoom*(options: RenderOptions): float =
  ## The width a title may take before it wraps.
  let (has, avail) = available(options)
  if has: max(80.0, avail - 2 * options.padding.get(8)) else: 4000

proc capWidth*(options: RenderOptions, natural, least: float, around = 0.0): float =
  ## For a chart that is drawn to a set width: its own, or the host's when that is smaller.
  ## `around` is what the chart adds outside that width.
  let (has, avail) = available(options)
  if not has: return natural
  max(min(least, natural), min(natural, avail - around))

const BREAKPOINT = 640.0

proc turnToFit*(options: RenderOptions, draw: proc (down: bool): Rendered): Rendered =
  ## For a diagram that can run across or down: draws it across, and down instead when the host
  ## allows it, the width it has is under the breakpoint, across does not fit, and down is
  ## narrower.
  let across = draw(false)
  let (has, avail) = available(options)
  if options.autoDirection == some(false) or not has or across.width <= avail: return across
  let breakpoint = options.directionBreakpoint
  if avail >= (if breakpoint.isSome and breakpoint.get > 0: breakpoint.get else: BREAKPOINT): return across
  let down = draw(true)
  if down.width < across.width: down else: across

func runsAcross*(direction: string): bool = direction == "LR" or direction == "RL"

proc tighten*(options: RenderOptions, draw: proc (tight: bool): Rendered): Rendered =
  ## Draws a diagram with room to spare, and tightly instead when that does not fit the width
  ## the host has and tight is narrower.
  let loose = draw(false)
  let (has, avail) = available(options)
  if not has or loose.width <= avail: return loose
  let tight = draw(true)
  if tight.width < loose.width: tight else: loose
