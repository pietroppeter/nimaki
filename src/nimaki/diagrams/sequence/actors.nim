## port-of: src/diagrams/sequence/actors.ts
## port-status: draft
import std/sets
import ../../js
import ../../svg/[builder, theme]
import ../../text/[label, icons]

const
  PAD_X = 16.0
  PAD_Y = 10.0
  GLYPH = 34.0
  GLYPH_GAP = 4.0
  STACK = 5.0
  CAP = 6.0
  SHAPE = " fill=\"var(--_s)\" stroke=\"var(--_b)\""
  LINE = " fill=\"none\" stroke=\"var(--_b)\""

const KINDS = toHashSet(["participant", "actor", "boundary", "control", "entity", "database", "collections", "queue"])
const FIGURES = toHashSet(["actor", "boundary", "control", "entity", "database"])

type ActorSize* = object
  w*, h*: float

func actorKind*(kind: string): string =
  if kind in KINDS: kind else: "participant"

func isFigure*(kind: string): bool =
  ## A figure stands above its label. The other kinds hold the label inside.
  kind in FIGURES

func actorSize*(kind: string, label: Label, minW, minH: float, paddingX = PAD_X): ActorSize =
  if isFigure(kind):
    return ActorSize(w: max(40.0, label.width + 8), h: GLYPH + (if label.height > 0: GLYPH_GAP + label.height else: 0))
  let extra = if kind == "collections": STACK elif kind == "queue": 2 * CAP else: 0
  ActorSize(w: max(minW, label.width + 2 * paddingX) + extra,
            h: max(minH, label.height + 2 * PAD_Y) + (if kind == "collections": STACK else: 0))

func figure(kind: string, cx, top: float): string =
  let x = num(cx)
  template y(dy: float): string = num(top + dy)
  case kind
  of "actor":
    "<circle cx=\"" & x & "\" cy=\"" & y(7) & "\" r=\"6\"" & SHAPE & "/>" &
      "<path d=\"M" & x & "," & y(13) & "V" & y(24) & "M" & num(cx - 10) & "," & y(17) & "H" & num(cx + 10) &
      "M" & num(cx - 8) & "," & y(34) & "L" & x & "," & y(24) & "L" & num(cx + 8) & "," & y(34) & "\"" & LINE & "/>"
  of "boundary":
    "<path d=\"M" & num(cx - 19) & "," & y(6) & "V" & y(28) & "M" & num(cx - 19) & "," & y(17) & "H" &
      num(cx - 8) & "\"" & LINE & "/>" &
      "<circle cx=\"" & num(cx + 3) & "\" cy=\"" & y(17) & "\" r=\"11\"" & SHAPE & "/>"
  of "control":
    "<circle cx=\"" & x & "\" cy=\"" & y(21) & "\" r=\"11\"" & SHAPE & "/>" &
      "<path d=\"M" & num(cx + 5) & "," & y(5) & "L" & num(cx - 1) & "," & y(10) & "L" & num(cx + 5) & "," &
      y(15) & "\"" & LINE & "/>"
  of "entity":
    "<circle cx=\"" & x & "\" cy=\"" & y(15) & "\" r=\"11\"" & SHAPE & "/>" &
      "<path d=\"M" & num(cx - 11) & "," & y(30) & "H" & num(cx + 11) & "\"" & LINE & "/>"
  else:
    let l = num(cx - 14)
    let r = num(cx + 14)
    "<path d=\"M" & l & "," & y(7) & "V" & y(27) & "A14,5 0 0 0 " & r & "," & y(27) & "V" & y(7) &
      "A14,5 0 0 0 " & l & "," & y(7) & "Z\"" & SHAPE & "/>" &
      "<path d=\"M" & l & "," & y(7) & "A14,5 0 0 0 " & r & "," & y(7) & "\"" & LINE & "/>"

proc drawActor*(kind: string, cx, top: float, size: ActorSize, label: Label, icons: IconResolver,
                ink = ""): string =
  ## Draws a participant whose bounding box has its top center at (cx, top). `ink` is the fill
  ## attribute for a figure's label, which sits on whatever is behind the figure.
  let w = size.w
  let h = size.h
  const text = " class=\"pele-label\""
  if isFigure(kind):
    return figure(kind, cx, top) & labelSvg(label, cx, top + GLYPH + GLYPH_GAP + label.height / 2, text & ink, icons)
  let left = cx - w / 2
  if kind == "collections":
    let bw = w - STACK
    let bh = h - STACK
    let back = "<rect x=\"" & num(left + STACK) & "\" y=\"" & num(top) & "\" width=\"" & num(bw) & "\" height=\"" &
      num(bh) & "\"" & SHAPE & ROUNDED & "/>"
    let front = "<rect x=\"" & num(left) & "\" y=\"" & num(top + STACK) & "\" width=\"" & num(bw) & "\" height=\"" &
      num(bh) & "\"" & SHAPE & ROUNDED & "/>"
    return back & front & labelSvg(label, left + bw / 2, top + STACK + bh / 2, text, icons)
  if kind == "queue":
    let l = num(left + CAP)
    let r = num(left + w - CAP)
    let b = num(top + h)
    let ry = num(h / 2)
    return "<path d=\"M" & l & "," & num(top) & "H" & r & "A" & jsString(CAP) & "," & ry & " 0 0 1 " & r & "," & b &
      "H" & l & "A" & jsString(CAP) & "," & ry & " 0 0 1 " & l & "," & num(top) & "Z\"" & SHAPE & "/>" &
      "<path d=\"M" & r & "," & num(top) & "A" & jsString(CAP) & "," & ry & " 0 0 0 " & r & "," & b & "\"" & LINE & "/>" &
      labelSvg(label, cx - CAP / 2, top + h / 2, text, icons)
  "<rect x=\"" & num(left) & "\" y=\"" & num(top) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\"" &
    SHAPE & ROUNDED & "/>" & labelSvg(label, cx, top + h / 2, text, icons)
