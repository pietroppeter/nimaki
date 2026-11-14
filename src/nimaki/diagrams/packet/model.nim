## port-of: src/diagrams/packet/model.ts
## port-status: conformant
import std/options
from std/math import floor
import ../../errors
import ../../js
import ../../preprocess
import ../../util/yaml
import parser
import ../../jsregex

type
  PacketLabel* = ref object
    ## Shared by the pieces of one field, as a JavaScript string is: a field split over 10,000
    ## rows would otherwise copy its label 10,000 times, which the JavaScript build cannot hold.
    ## (A ref object: nim js gets `ref string` wrong.)
    text*: string

  PacketBlock* = object
    start*: float
    stop*: float
    bits*: float
      ## As Mermaid counts it: one less than the width for the pieces of a field split across rows.
    label*: PacketLabel

  PacketModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    bitsPerRow*: float
    rows*: seq[seq[PacketBlock]]

const MAX_ROWS = 10_000

proc packetOption*(config: Config, key: string, fallback, min, max: float): float =
  let value = config["packet"][key]
  if value != nil and value.kind == yNumber and value.n >= min: jsMin(value.n, max) else: fallback

proc invalid(message: string): ref PeleError =
  newPeleError(message, "semantic", ErrorInfo(diagramType: "packet"))

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc buildPacket*(ast: PacketAst, config: Config, title: string): PacketModel =
  let bitsPerRow = floor(packetOption(config, "bitsPerRow", 32, 1, 4096))
  var rows: seq[seq[PacketBlock]]
  var lastBit = -1.0
  var word: seq[PacketBlock]
  var row = 1.0

  for blk in ast.blocks:
    let label = PacketLabel(text: blk.label)
    var start = blk.start
    var stop = blk.stop
    var bits = blk.bits
    if start.isSome and stop.isSome and stop.get < start.get:
      raise invalid("Packet block " & jsString(start.get) & " - " & jsString(stop.get) &
                    " is invalid. End must be greater than start.")
    if start.isNone: start = some(lastBit + 1)
    if start.get != lastBit + 1:
      raise invalid("Packet block " & jsString(start.get) & " - " & jsString(stop.get(start.get)) &
                    " is not contiguous. It should start from " & jsString(lastBit + 1) & ".")
    if bits == some(0.0):
      raise invalid("Packet block " & jsString(start.get) & " is invalid. Cannot have a zero bit field.")
    if stop.isNone: stop = some(start.get + bits.get(1) - 1)
    if bits.isNone: bits = some(stop.get - start.get + 1)
    var s = start.get
    let e = stop.get
    var b = bits.get
    lastBit = e

    while float(word.len) <= bitsPerRow + 1 and rows.len < MAX_ROWS:
      let rowEnd = row * bitsPerRow - 1
      if e <= rowEnd:
        word.add PacketBlock(start: s, stop: e, bits: b, label: label)
        if e == rowEnd:
          rows.add word
          word = @[]
          row += 1
        break
      word.add PacketBlock(start: s, stop: rowEnd, bits: rowEnd - s, label: label)
      rows.add word
      word = @[]
      row += 1
      s = rowEnd + 1
      b = e - s
  if word.len > 0: rows.add word

  PacketModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": ast.accTitle.replace(jsre"/^\s+/g", "") else: "",
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "",
    bitsPerRow: bitsPerRow,
    rows: rows)
