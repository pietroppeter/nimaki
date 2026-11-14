## port-of: src/diagrams/info/render.ts
## port-status: conformant
import std/options
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, root]
import ../../text/[label, measurer]
import ../../types
import ../../js
import model

const version = "1.13.0"
  ## Pele reads its version from its package.json. The port draws Pele's version at the pin, so
  ## the SVG stays identical to the one it is checked against.

proc renderInfo*(model: InfoModel, config: Config, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let title = layoutLabel(model.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 8 else: 0
  let text = layoutLabel("Pele v" & version, false, measurer, size, 4000)

  let width = ceil(jsMax(title.width, text.width) + 2 * pad)
  let height = ceil(titleHeight + text.height + 2 * pad)
  let content =
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    labelSvg(text, width / 2, pad + titleHeight + text.height / 2, " class=\"pele-version\" fill=\"var(--_m)\"")

  Rendered(svg: svgDocument("info", width, height, size, options,
                            Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
           width: width, height: height)
