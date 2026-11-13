## port-of: src/diagrams/sequence/parser.ts
## port-status: draft
##
## Pele's `SeqBuilder` interface (the calls Mermaid's grammar makes on its `yy` object) is the
## `SeqDb` itself. A frame's finished sections are pairs of a statement list and the divider text
## that ended it.
import std/options
import ../../errors
import ../../js
import db, lexer, tokens, types

const SIGNAL = block:
  var s: array[T_STICK_ARROW_BOTTOM_REVERSE_DOTTED + 1, int]
  for k in s.mitems: k = -1
  s[T_SOLID_OPEN_ARROW] = LINETYPE_SOLID_OPEN
  s[T_DOTTED_OPEN_ARROW] = LINETYPE_DOTTED_OPEN
  s[T_SOLID_ARROW] = LINETYPE_SOLID
  s[T_DOTTED_ARROW] = LINETYPE_DOTTED
  s[T_BIDIRECTIONAL_SOLID_ARROW] = LINETYPE_BIDIRECTIONAL_SOLID
  s[T_BIDIRECTIONAL_DOTTED_ARROW] = LINETYPE_BIDIRECTIONAL_DOTTED
  s[T_SOLID_CROSS] = LINETYPE_SOLID_CROSS
  s[T_DOTTED_CROSS] = LINETYPE_DOTTED_CROSS
  s[T_SOLID_POINT] = LINETYPE_SOLID_POINT
  s[T_DOTTED_POINT] = LINETYPE_DOTTED_POINT
  s[T_SOLID_ARROW_TOP] = LINETYPE_SOLID_TOP
  s[T_SOLID_ARROW_BOTTOM] = LINETYPE_SOLID_BOTTOM
  s[T_STICK_ARROW_TOP] = LINETYPE_STICK_TOP
  s[T_STICK_ARROW_BOTTOM] = LINETYPE_STICK_BOTTOM
  s[T_SOLID_ARROW_TOP_DOTTED] = LINETYPE_SOLID_TOP_DOTTED
  s[T_SOLID_ARROW_BOTTOM_DOTTED] = LINETYPE_SOLID_BOTTOM_DOTTED
  s[T_STICK_ARROW_TOP_DOTTED] = LINETYPE_STICK_TOP_DOTTED
  s[T_STICK_ARROW_BOTTOM_DOTTED] = LINETYPE_STICK_BOTTOM_DOTTED
  s[T_SOLID_ARROW_TOP_REVERSE] = LINETYPE_SOLID_ARROW_TOP_REVERSE
  s[T_SOLID_ARROW_BOTTOM_REVERSE] = LINETYPE_SOLID_ARROW_BOTTOM_REVERSE
  s[T_STICK_ARROW_TOP_REVERSE] = LINETYPE_STICK_ARROW_TOP_REVERSE
  s[T_STICK_ARROW_BOTTOM_REVERSE] = LINETYPE_STICK_ARROW_BOTTOM_REVERSE
  s[T_SOLID_ARROW_TOP_REVERSE_DOTTED] = LINETYPE_SOLID_ARROW_TOP_REVERSE_DOTTED
  s[T_SOLID_ARROW_BOTTOM_REVERSE_DOTTED] = LINETYPE_SOLID_ARROW_BOTTOM_REVERSE_DOTTED
  s[T_STICK_ARROW_TOP_REVERSE_DOTTED] = LINETYPE_STICK_ARROW_TOP_REVERSE_DOTTED
  s[T_STICK_ARROW_BOTTOM_REVERSE_DOTTED] = LINETYPE_STICK_ARROW_BOTTOM_REVERSE_DOTTED
  s

const
  K_Top = 0
  K_Box = 1
  K_Loop = 2
  K_Rect = 3
  K_Opt = 4
  K_Break = 5
  K_Alt = 6
  K_Par = 7
  K_Critical = 8

type Frame = ref object
  kind: int
  text: string
  startType: int
  list: seq[SeqItem]
    ## The current section's statements. Slot 0 of a block's first section is kept for its start entry.
  sections: seq[(seq[SeqItem], string)]
    ## Finished sections, each with the divider text that ended it.

const BLOCK = block:
  var b: array[T_STICK_ARROW_BOTTOM_REVERSE_DOTTED + 1, int]
  for k in b.mitems: k = -1
  b[T_loop] = K_Loop
  b[T_rect] = K_Rect
  b[T_opt] = K_Opt
  b[T_break] = K_Break
  b[T_alt] = K_Alt
  b[T_par] = K_Par
  b[T_par_over] = K_Par
  b[T_critical] = K_Critical
  b[T_box] = K_Box
  b

const SIGNAL_TOKENS = "'SOLID_OPEN_ARROW', 'DOTTED_OPEN_ARROW', 'SOLID_ARROW', 'DOTTED_ARROW', 'SOLID_CROSS', 'DOTTED_CROSS', 'SOLID_POINT', 'DOTTED_POINT'"

func stmt(kind: string, signalType = NO_TYPE): SeqStatement =
  SeqStatement(kind: kind, signalType: signalType, placement: NO_TYPE, sequenceIndex: NaN,
               sequenceIndexStep: NaN)

proc parseSequence*(src: string, db: SeqDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  var i = 0

  proc fail(expected: string) {.noreturn.} =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("sequence", src, starts[i], "", true)
    raise syntaxError("sequence", src, starts[i], "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")
  proc expect(kind: int): string =
    if types[i] != kind: fail("'" & TOKEN_NAMES[kind] & "'")
    result = texts[i]
    inc i
  proc actor(): SeqStatement =
    let t = types[i]
    if t != T_ACTOR and t != T_link: fail("'ACTOR'")
    result = stmt("addParticipant")
    result.actor = texts[i]
    inc i
  proc text2(): SeqText = db.parseMessage(jsTrim(expect(T_TXT))[1 .. ^1])

  proc participant(): SeqStatement =
    let t = types[i]
    inc i
    if t == T_destroy:
      let node = actor()
      discard expect(T_NEWLINE)
      node.kind = "destroyParticipant"
      return node
    let node = actor()
    if types[i] == T_CONFIG_START and types[i - 1] == T_ACTOR:
      inc i
      let content = expect(T_CONFIG_CONTENT)
      discard expect(T_CONFIG_END)
      node.config = some(jsTrim(content))
    node.draw = if t == T_participant: "participant" else: "actor"
    if types[i] == T_AS:
      inc i
      let alias = expect(T_restOfLine)
      discard expect(T_NEWLINE)
      node.description = some(db.parseMessage(alias))
    elif types[i] == T_NEWLINE:
      inc i
    else:
      fail("'AS', 'NEWLINE'")
    node

  proc signal(start: SeqStatement): SeqItem =
    var centralFrom = false
    if types[i] == T_CENTRAL:
      centralFrom = true
      inc i
    let signalType = if types[i] < SIGNAL.len: SIGNAL[types[i]] else: -1
    if signalType < 0: fail(SIGNAL_TOKENS)
    inc i
    let mark = types[i]
    if mark == T_CENTRAL or (not centralFrom and (mark == T_PLUS or mark == T_MINUS)): inc i
    let to = actor()
    let msg = text2()
    let message = stmt("addMessage", signalType)
    message.start = start.actor
    message.to = to.actor
    message.msg = msg
    var output = @[item(start), item(to), item(message)]
    if centralFrom:
      let dual = mark == T_CENTRAL
      message.activate = dual
      message.centralConnection = if dual: LINETYPE_CENTRAL_CONNECTION_DUAL else: LINETYPE_CENTRAL_CONNECTION_REVERSE
      if dual:
        let c = stmt("centralConnection", LINETYPE_CENTRAL_CONNECTION)
        c.actor = to.actor
        output.add item(c)
      let r = stmt("centralConnectionReverse", LINETYPE_CENTRAL_CONNECTION_REVERSE)
      r.actor = start.actor
      output.add item(r)
    elif mark == T_PLUS:
      message.activate = true
      let s = stmt("activeStart", LINETYPE_ACTIVE_START)
      s.actor = to.actor
      output.add item(s)
    elif mark == T_MINUS:
      let s = stmt("activeEnd", LINETYPE_ACTIVE_END)
      s.actor = start.actor
      output.add item(s)
    elif mark == T_CENTRAL:
      message.activate = true
      message.centralConnection = LINETYPE_CENTRAL_CONNECTION
      let c = stmt("centralConnection", LINETYPE_CENTRAL_CONNECTION)
      c.actor = to.actor
      output.add item(c)
    item(output)

  proc menu(kind: string): SeqItem =
    inc i
    let who = actor()
    let s = stmt(kind)
    s.actor = who.actor
    s.text = text2()
    item(@[item(who), item(s)])

  proc note(): SeqItem =
    inc i
    let t = types[i]
    if t == T_over:
      inc i
      let first = actor()
      var who = item(first)
      var ids = @[first.actor, first.actor]
      if types[i] == T_COMMA:
        inc i
        let second = actor()
        who = item(@[item(first), item(second)])
        ids = @[first.actor, second.actor]
      let s = stmt("addNote")
      s.placement = PLACEMENT_OVER
      s.actors = ids
      s.text = text2()
      return item(@[who, item(s)])
    if t != T_left_of and t != T_right_of: fail("'over', 'left_of', 'right_of'")
    inc i
    let who = actor()
    let s = stmt("addNote")
    s.placement = if t == T_left_of: PLACEMENT_LEFTOF else: PLACEMENT_RIGHTOF
    s.actor = who.actor
    s.actors = @[who.actor, who.actor]
    s.text = text2()
    item(@[item(who), item(s)])

  proc autonumber(): SeqStatement =
    inc i
    let node = stmt("sequenceIndex", LINETYPE_AUTONUMBER)
    node.sequenceVisible = true
    if types[i] == T_NUM:
      node.sequenceIndex = jsNumber(texts[i])
      inc i
      if types[i] == T_NUM:
        node.sequenceIndexStep = jsNumber(texts[i])
        inc i
      else:
        node.sequenceIndexStep = 1
    elif types[i] == T_off:
      inc i
      node.sequenceVisible = false
    if types[i] != T_NEWLINE: fail("'NEWLINE', 'NUM', 'off'")
    inc i
    node

  # Folds the sections of an alt, par, or critical block from the last one back, as the grammar's
  # right recursion does, so the texts reach the model builder in the same order.
  proc fold(frame: Frame, divider: string, signalType: int): seq[SeqItem] =
    var list = frame.list
    for k in countdown(frame.sections.len - 1, 0):
      let head = stmt(divider, signalType)
      head.blockText = some(db.parseMessage(frame.sections[k][1]))
      list = frame.sections[k][0] & @[item(head), item(list)]
    list

  proc close(frame: Frame): seq[SeqItem] =
    let text = frame.text
    var list = frame.list
    template start(kind: string, signalType: int, label: Option[SeqText]): SeqItem =
      let s = stmt(kind, signalType)
      s.blockText = label
      item(s)
    case frame.kind
    of K_Box:
      let s = stmt("boxStart")
      s.boxData = db.parseBoxData(text)
      list[0] = item(s)
      let e = stmt("boxEnd")
      e.boxText = text
      list.add item(e)
    of K_Loop:
      list[0] = start("loopStart", LINETYPE_LOOP_START, some(db.parseMessage(text)))
      list.add start("loopEnd", LINETYPE_LOOP_END, none(SeqText))
    of K_Rect:
      list[0] = start("rectStart", LINETYPE_RECT_START, some(db.parseMessage(text)))
      list.add start("rectEnd", LINETYPE_RECT_END, some(db.parseMessage(text)))
    of K_Opt:
      list[0] = start("optStart", LINETYPE_OPT_START, some(db.parseMessage(text)))
      list.add start("optEnd", LINETYPE_OPT_END, some(db.parseMessage(text)))
    of K_Break:
      list[0] = start("breakStart", LINETYPE_BREAK_START, some(db.parseMessage(text)))
      list.add start("breakEnd", LINETYPE_BREAK_END, some(db.parseMessage(text)))
    of K_Alt:
      list = fold(frame, "else", LINETYPE_ALT_ELSE)
      list[0] = start("altStart", LINETYPE_ALT_START, some(db.parseMessage(text)))
      list.add start("altEnd", LINETYPE_ALT_END, none(SeqText))
    of K_Par:
      list = fold(frame, "and", LINETYPE_PAR_AND)
      list[0] = start("parStart", frame.startType, some(db.parseMessage(text)))
      list.add start("parEnd", LINETYPE_PAR_END, none(SeqText))
    else:
      list = fold(frame, "option", LINETYPE_CRITICAL_OPTION)
      list[0] = start("criticalStart", LINETYPE_CRITICAL_START, some(db.parseMessage(text)))
      list.add start("criticalEnd", LINETYPE_CRITICAL_END, none(SeqText))
    list

  while types[i] == T_NEWLINE: inc i
  discard expect(T_SD)

  var stack: seq[Frame]
  var frame = Frame(kind: K_Top)

  while true:
    let t = types[i]
    if frame.kind == K_Box:
      if t == T_participant or t == T_participant_actor or t == T_destroy:
        frame.list.add item(participant())
      elif t == T_NEWLINE:
        frame.list.add item(newSeq[SeqItem]())
        inc i
      elif t == T_end:
        inc i
        let done = close(frame)
        frame = stack.pop()
        frame.list.add item(done)
      else:
        fail("'end', 'NEWLINE', 'participant', 'participant_actor', 'destroy'")
      continue
    case t
    of T_NEWLINE, T_INVALID:
      frame.list.add item(newSeq[SeqItem]())
      inc i
    of T_participant, T_participant_actor, T_destroy:
      frame.list.add item(participant())
    of T_create:
      inc i
      let next = types[i]
      if next != T_participant and next != T_participant_actor and next != T_destroy:
        fail("'participant', 'participant_actor', 'destroy'")
      let node = participant()
      node.kind = "createParticipant"
      frame.list.add item(node)
    of T_ACTOR:
      frame.list.add signal(actor())
      discard expect(T_NEWLINE)
    of T_link:
      let next = types[i + 1]
      frame.list.add(if next == T_ACTOR or next == T_link: menu("addALink") else: signal(actor()))
      discard expect(T_NEWLINE)
    of T_links:
      frame.list.add menu("addLinks")
      discard expect(T_NEWLINE)
    of T_properties:
      frame.list.add menu("addProperties")
      discard expect(T_NEWLINE)
    of T_details:
      frame.list.add menu("addDetails")
      discard expect(T_NEWLINE)
    of T_note:
      frame.list.add note()
      discard expect(T_NEWLINE)
    of T_autonumber:
      frame.list.add item(autonumber())
    of T_activate, T_deactivate:
      inc i
      let who = actor()
      discard expect(T_NEWLINE)
      let s = if t == T_activate: stmt("activeStart", LINETYPE_ACTIVE_START)
              else: stmt("activeEnd", LINETYPE_ACTIVE_END)
      s.actor = who.actor
      frame.list.add item(s)
    of T_title, T_legacy_title:
      let title = substringFrom(texts[i], if t == T_title: 6 else: 7)
      inc i
      db.setDiagramTitle(title)
      frame.list.add item(title)
    of T_acc_title:
      inc i
      let value = jsTrim(expect(T_acc_title_value))
      db.setAccTitle(value)
      frame.list.add item(value)
    of T_acc_descr:
      inc i
      let value = jsTrim(expect(T_acc_descr_value))
      db.setAccDescription(value)
      frame.list.add item(value)
    of T_acc_descr_multiline_value:
      let value = jsTrim(texts[i])
      inc i
      db.setAccDescription(value)
      frame.list.add item(value)
    of T_loop, T_rect, T_opt, T_break, T_alt, T_par, T_par_over, T_critical, T_box:
      inc i
      let text = expect(T_restOfLine)
      stack.add frame
      frame = Frame(kind: BLOCK[t], text: text,
                    startType: (if t == T_par_over: LINETYPE_PAR_OVER_START else: LINETYPE_PAR_START),
                    list: @[item(newSeq[SeqItem]())])
    of T_else, T_and, T_option:
      let kind = frame.kind
      if kind != (if t == T_else: K_Alt elif t == T_and: K_Par else: K_Critical): fail("'end'")
      inc i
      let text = expect(T_restOfLine)
      frame.sections.add (frame.list, text)
      frame.list = @[]
    of T_end:
      if frame.kind == K_Top: fail("'NEWLINE', 'EOF'")
      inc i
      let done = close(frame)
      frame = stack.pop()
      frame.list.add item(done)
    of T_STOP:
      if frame.kind != K_Top: fail("'end'")
      db.apply(item(frame.list))
      return
    else:
      fail("'NEWLINE', 'ACTOR', 'participant', 'note', 'end'")
