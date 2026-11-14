## port-of: src/diagrams/packet/render.ts
## port-status: conformant
import std/[options, tables]
from std/math import ceil, floor, `mod`
import ../../jsmath
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[entities, label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/[fit_width, literal_label, fit_text]
import model

proc draw(model: PacketModel, config: Config, options: RenderOptions, down: bool): Rendered

proc renderPacket*(model: PacketModel, config: Config, options: RenderOptions): Rendered =
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

proc draw(model: PacketModel, config: Config, options: RenderOptions, down: bool): Rendered =
  let size = options.fontSize.get(16)
  let labelSize = jsRound(size * 0.875)
  let bitSize = jsRound(size * 0.625)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let packet = config["packet"]   # nil stands for Pele's `?? {}`
  let rowHeight = packetOption(config, "rowHeight", 32, 1, 400)
  var bitWidth = packetOption(config, "bitWidth", 32, 1, 400)
  let paddingX = packetOption(config, "paddingX", 5, 0, 400)
  let paddingY = packetOption(config, "paddingY", 5, 0, 400)
  let showBitsValue = packet["showBits"]
  let showBits = not (showBitsValue != nil and showBitsValue.kind == yBool and not showBitsValue.b)
  let order = packet["bitOrder"]
  let descending = order != nil and order.kind == yString and order.s == "descending"
  var bitsPerRow = model.bitsPerRow
  var rows = model.rows
  if down:
    let count = jsMax(1, floor((options.maxWidth.get(320) - 2 * pad) / jsMin(bitWidth, 18)))
    # A byte is the shortest row. Below that every label is one character to a line, and a long
    # packet is a row to a bit.
    bitsPerRow = jsMin(bitsPerRow, jsMax(8, pow(2.0, floor(log2(count)))))
    var last = 0.0
    if model.rows.len > 0 and model.rows[^1].len > 0: last = model.rows[^1][^1].stop
    if ceil((last + 1) / bitsPerRow) > 10000: bitsPerRow = model.bitsPerRow
    bitWidth = jsMin(bitWidth, jsMax(18, (options.maxWidth.get(320) - 2 * pad) / bitsPerRow))
    # The model has split each field at its own rows. Its pieces are joined again first, so that
    # a field is only split where one of the new rows ends. A piece counts one bit short.
    func piece(blk: PacketBlock): bool = blk.bits == blk.stop - blk.start
    var whole: seq[PacketBlock]
    for row in model.rows:
      for blk in row:
        if whole.len > 0 and piece(whole[^1]) and piece(blk) and (whole[^1].label == blk.label or whole[^1].label.text == blk.label.text) and
           blk.start == whole[^1].stop + 1 and blk.start mod model.bitsPerRow == 0:
          whole[^1].stop = blk.stop
          whole[^1].bits = whole[^1].stop - whole[^1].start
        else:
          whole.add blk
    rows = @[]
    for blk in whole:
      var start = blk.start
      while start <= blk.stop:
        let stop = jsMin(blk.stop, (floor(start / bitsPerRow) + 1) * bitsPerRow - 1)
        let index = int(floor(start / bitsPerRow))
        if rows.len <= index: rows.setLen(index + 1)
        var piece = blk
        piece.start = start
        piece.stop = stop
        rows[index].add piece
        start = stop + 1
  # Pele keys a Map by block; here a label per block, in the same rows.
  var labels: seq[seq[Label]]
  if down:
    for row in rows:
      var ls: seq[Label]
      for blk in row:
        let room = jsMax(1, (blk.stop - blk.start + 1) * bitWidth - jsMin(paddingX, bitWidth - 1) - 6)
        ls.add literalLabel(jsTrim(decodeEntities(blk.label.text)), measurer, labelSize, room)
      labels.add ls
  # Bit numbers sit above each row and need room of their own.
  let numbers = if showBits: bitSize + 4 else: 0.0
  var rowHeights: seq[float]
  for r, row in rows:
    var height = rowHeight
    if down:
      for k in 0 ..< row.len: height = jsMax(height, labels[r][k].height + 10)
    rowHeights.add height
  var tops: seq[float]
  var rowsHeight = 0.0
  for height in rowHeights:
    tops.add rowsHeight
    rowsHeight += numbers + height + paddingY
  if rows.len > 0: rowsHeight -= paddingY

  let gap = jsMin(paddingX, bitWidth - 1)
  let width = if rows.len > 0: bitsPerRow * bitWidth - gap else: 0.0
  let title = layoutLabel(model.title, false, measurer, size, (if down: titleRoom(options) else: 4000), Bold)
  let titleHeight = if title.height > 0: title.height + (if rowsHeight > 0: 12 else: 0) else: 0.0

  # The pieces of a field split across rows share its label, so each width is fitted once.
  # Pele's Map is keyed by the label's text; here by the field's own label, which its pieces share
  # and which follow each other, so no long label is hashed. The fitted text is the same either way.
  var fitsOf: PacketLabel
  var fits = initTable[float, (bool, Fitted)]()
  proc fit(label: PacketLabel, max: float): (bool, Fitted) =
    if label != fitsOf:
      fitsOf = label
      fits.clear()
    if max notin fits:
      fits[max] = fitText(jsTrim(decodeEntities(label.text)), max, labelSize, jsRound(size * 0.5), measurer)
    fits[max]

  let left = pad + jsMax(0, (title.width - width) / 2)
  var fields = ""
  var bits = ""
  for index, row in rows:
    let y = pad + tops[index] + numbers
    let rowHeight = rowHeights[index]
    for k, blk in row:
      let count = blk.stop - blk.start + 1
      let first = blk.start mod bitsPerRow
      let x = left + (if descending: bitsPerRow - first - count else: first) * bitWidth
      let w = count * bitWidth - gap
      fields.add "<g class=\"pele-node\" data-id=\"" & jsString(blk.start) & "-" & jsString(blk.stop) & "\">" &
        "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(w) & "\" height=\"" & num(rowHeight) &
        "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & ROUNDED & "/>"
      if down:
        fields.add labelSvg(labels[index][k], x + w / 2, y + rowHeight / 2, "")
      else:
        let (ok, text) = fit(blk.label, w - 6)
        if ok and text.size <= rowHeight:
          fields.add "<text x=\"" & num(x + w / 2) & "\" y=\"" & num(y + rowHeight / 2 + text.size * 0.35) & "\"" &
            (if text.size == labelSize: "" else: " font-size=\"" & num(text.size) & "\"") &
            ">" & esc(text.text) & "</text>"
      fields.add "</g>"
      if not showBits: continue
      let leading = if descending: blk.stop else: blk.start
      let trailing = if descending: blk.start else: blk.stop
      if count == 1:
        bits.add "<text x=\"" & num(x + w / 2) & "\" y=\"" & num(y - 4) & "\" text-anchor=\"middle\">" & jsString(leading) & "</text>"
      else:
        bits.add "<text x=\"" & num(x) & "\" y=\"" & num(y - 4) & "\">" & jsString(leading) & "</text>" &
          "<text x=\"" & num(x + w) & "\" y=\"" & num(y - 4) & "\" text-anchor=\"end\">" & jsString(trailing) & "</text>"

  let totalWidth = ceil(jsMax(width, title.width) + 2 * pad)
  let totalHeight = ceil(rowsHeight + titleHeight + 2 * pad)
  let content =
    (if fields != "": "<g class=\"pele-packet-fields\" font-size=\"" & jsString(labelSize) & "\" text-anchor=\"middle\">" & fields & "</g>" else: "") &
    (if bits != "": "<g class=\"pele-packet-bits\" font-size=\"" & jsString(bitSize) & "\" fill=\"var(--_m)\">" & bits & "</g>" else: "") &
    # Mermaid puts a packet's title under it.
    labelSvg(title, totalWidth / 2, totalHeight - pad - title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"")

  Rendered(
    svg: svgDocument("packet", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight)
