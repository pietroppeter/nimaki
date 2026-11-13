## port-of: src/diagrams/c4/lexer.ts
## port-status: draft
##
## Positions are byte offsets. `charCodeAt` becomes `cu`, which reads the character at a byte
## offset (-1 past the end, as NaN is nothing); a step past a whitespace character takes its
## bytes.
import std/[strutils, tables]
import ../../js
import ../../util/chars
import tokens

type Tokens* = object
  ## Token text is src[starts[i] ..< ends[i]].
  types*, starts*, ends*: seq[int]

const
  # const enum S
  S_INITIAL = 0
  S_struct = 1
  S_attribute = 2
  S_string = 3
  S_string_kv = 4
  S_string_kv_key = 5
  S_string_kv_value = 6
  S_acc = 7
  S_acc_descr_multiline = 8

let KEYWORDS = {
  "C4Context": T_C4_CONTEXT, "C4Container": T_C4_CONTAINER, "C4Component": T_C4_COMPONENT,
  "C4Dynamic": T_C4_DYNAMIC, "C4Deployment": T_C4_DEPLOYMENT,
  "Person": T_PERSON, "Person_Ext": T_PERSON_EXT,
  "System": T_SYSTEM, "SystemDb": T_SYSTEM_DB, "SystemQueue": T_SYSTEM_QUEUE,
  "System_Ext": T_SYSTEM_EXT, "SystemDb_Ext": T_SYSTEM_EXT_DB, "SystemQueue_Ext": T_SYSTEM_EXT_QUEUE,
  "Container": T_CONTAINER, "ContainerDb": T_CONTAINER_DB, "ContainerQueue": T_CONTAINER_QUEUE,
  "Container_Ext": T_CONTAINER_EXT, "ContainerDb_Ext": T_CONTAINER_EXT_DB,
  "ContainerQueue_Ext": T_CONTAINER_EXT_QUEUE,
  "Component": T_COMPONENT, "ComponentDb": T_COMPONENT_DB, "ComponentQueue": T_COMPONENT_QUEUE,
  "Component_Ext": T_COMPONENT_EXT, "ComponentDb_Ext": T_COMPONENT_EXT_DB,
  "ComponentQueue_Ext": T_COMPONENT_EXT_QUEUE,
  "Enterprise_Boundary": T_ENTERPRISE_BOUNDARY, "System_Boundary": T_SYSTEM_BOUNDARY,
  "Boundary": T_BOUNDARY, "Container_Boundary": T_CONTAINER_BOUNDARY,
  "Deployment_Node": T_NODE, "Node": T_NODE, "Node_L": T_NODE_L, "Node_R": T_NODE_R,
  "Rel": T_REL, "BiRel": T_BIREL, "Rel_Up": T_REL_U, "Rel_U": T_REL_U, "Rel_Down": T_REL_D,
  "Rel_D": T_REL_D, "Rel_Left": T_REL_L, "Rel_L": T_REL_L, "Rel_Right": T_REL_R, "Rel_R": T_REL_R,
  "Rel_Back": T_REL_B, "RelIndex": T_REL_INDEX,
  "UpdateElementStyle": T_UPDATE_EL_STYLE, "UpdateRelStyle": T_UPDATE_REL_STYLE,
  "UpdateLayoutConfig": T_UPDATE_LAYOUT_CONFIG,
}.toTable

const DIRECTIONS = ["TB", "BT", "RL", "LR"]

func cu(src: string, i: int): int =
  ## charCodeAt: the character at byte i (a character past U+FFFF reads as its high surrogate).
  if i < 0 or i >= src.len: return -1
  let cp = codePointAt(src, i).rune
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func sizeAt(src: string, i: int): int =
  if i >= src.len: 1 else: codePointAt(src, i).size

func lineEndFrom(src: string, p: int): int =
  ## The first line terminator (\n, \r, U+2028, U+2029) at or after p, or the end.
  var i = p
  while i < src.len:
    if src[i] in {'\n', '\r'}: return i
    if src.continuesWith(" ", i) or src.continuesWith(" ", i): return i
    inc i
  src.len

func matchDirection(src: string, p, lineEnd: int, word: string): int =
  ## /.*direction\s+WORD[^\n]*/y at p: `.*` is greedy, so the last `direction` of the line that
  ## is followed by spaces and the word is the one taken.
  var found = -1
  var o = src.find("direction", p)
  while o != -1 and o < lineEnd:
    var q = o + 9
    let start = q
    while q < src.len and isSpace(cu(src, q)): q += sizeAt(src, q)
    if q > start and src.continuesWith(word, q): found = q + word.len
    o = src.find("direction", o + 1)
  if found < 0: return -1
  let nl = src.find('\n', found)
  if nl == -1: src.len else: nl

func matchBareTitle(src: string, p: int): int =
  ## /title[^\S\r\n]*(?=[\r\n]|$)\s*/y
  if not src.continuesWith("title", p): return -1
  var q = p + 5
  while q < src.len and src[q] notin {'\r', '\n'} and isSpace(cu(src, q)): q += sizeAt(src, q)
  if q < src.len and src[q] notin {'\r', '\n'}: return -1
  while q < src.len and isSpace(cu(src, q)): q += sizeAt(src, q)
  q

proc tokenize*(src: string): Tokens =
  ## Follows the lexer Jison compiles from c4Diagram.jison: its rule order, its start conditions,
  ## and what it returns once the input runs out in each of them.
  let n = src.len
  var types, starts, ends: seq[int]
  var state = S_INITIAL
  var accValue = T_acc_title_value
  var p = 0
  var done = false
  var dirNext = -2
  var lineEnd = -1
  var dirFailed = 0

  template emit(kind, s, e: int) =
    let e0 = e
    types.add kind
    starts.add s
    ends.add e0
    p = e0
  proc skipWs(q0: int): int =
    var q = q0
    while q < n and isSpace(cu(src, q)): q += sizeAt(src, q)
    q
  proc upTo(ch: char, start: int): int =
    let q = src.find(ch, start)
    if q == -1: n else: q
  proc statementEnd(word: string): int =
    ## `word\s[^#\n;]+`: where it ends, or -1.
    var q = p + word.len
    if not src.continuesWith(word, p) or not isSpace(cu(src, q)): return -1
    q += sizeAt(src, q)
    let start = q
    while q < n and src[q] notin {'#', '\n', ';'}: inc q
    if q == start: -1 else: q

  while true:
    # Jison notes the end of input one call before it reports it, so a rule that matches
    # nothing gets one last turn.
    if done:
      emit(T_STOP, n, n)
      break
    if p >= n: done = true
    let c = cu(src, p)

    if state == S_INITIAL:
      if p >= n:
        emit(T_EOF, n, n)
        continue
      if dirNext != -1 and p >= dirFailed:
        if dirNext < p: dirNext = src.find("direction", p)
        if dirNext != -1:
          if lineEnd < p: lineEnd = lineEndFrom(src, p)
          if dirNext < lineEnd:
            var matched = false
            for i in 0 ..< 4:
              let stop = matchDirection(src, p, lineEnd, DIRECTIONS[i])
              if stop >= 0:
                emit(T_direction_tb + i, p, stop)
                matched = true
                break
            if matched: continue
            # No direction statement starts anywhere in the rest of this line either.
            dirFailed = lineEnd
      if c == ord('t'):
        let stop = matchBareTitle(src, p)
        if stop >= 0:
          p = stop
          continue
        let e = statementEnd("title")
        if e >= 0:
          emit(T_title, p, e)
          continue
      if c == ord('a'):
        let e = statementEnd("accDescription")
        if e >= 0:
          emit(T_accDescription, p, e)
          continue
        let title = src.continuesWith("accTitle", p)
        if title or src.continuesWith("accDescr", p):
          let q = skipWs(p + 8)
          let d = cu(src, q)
          if d == ord(':'):
            emit((if title: T_acc_title else: T_acc_descr), p, skipWs(q + 1))
            accValue = if title: T_acc_title_value else: T_acc_descr_value
            state = S_acc
            continue
          if d == ord('{') and not title:
            p = skipWs(q + 1)
            state = S_acc_descr_multiline
            continue
      if c == ord('%') and cu(src, p + 1) == ord('%'):
        # A comment takes the line breaks after it, so no NEWLINE follows.
        var q = upTo('\n', p + 2)
        while q < n and src[q] in {'\n', '\r'}: inc q
        p = q
        continue
      if isSpace(c):
        var q = p
        var last = -1
        while q < n:
          let d = cu(src, q)
          if not isSpace(d): break
          if d == 10: last = q
          q += sizeAt(src, q)
        if last != -1: emit(T_NEWLINE, p, last + 1)
        else: p = q
        continue
      if c == ord('{'):
        emit(T_LBRACE, p, p + 1)
        continue
      if c == ord('}'):
        emit(T_RBRACE, p, p + 1)
        continue
      if isWord(c):
        var q = p + 1
        while q < n and isWord(cu(src, q)): inc q
        let kind = if q - p <= 19: KEYWORDS.getOrDefault(src[p ..< q], -1) else: -1
        if kind != -1:
          if kind > T_C4_DEPLOYMENT: state = S_struct
          emit(kind, p, q)
          continue
      emit(T_ERROR, p, p)
      break

    if state == S_struct:
      if p >= n:
        emit(T_EOF_IN_STRUCT, n, n)
      elif c == ord('('):
        var q = p + 1
        while cu(src, q) == 32: inc q
        if cu(src, q) == ord(','): emit(T_ATTRIBUTE_EMPTY, p, q + 1)
        else: inc p
        state = S_attribute
      elif c == ord(')'):
        inc p
        state = S_INITIAL
      else:
        emit(T_ERROR, p, p)
        break
      continue

    if state == S_attribute:
      if p >= n: continue
      if c == ord(')'):
        inc p
        state = S_INITIAL
      elif c == ord(','):
        if cu(src, p + 1) == ord(','): emit(T_ATTRIBUTE_EMPTY, p, p + 2)
        else: inc p
      else:
        var q = p
        while cu(src, q) == 32: inc q
        let d = cu(src, q)
        if d == ord('"'):
          if cu(src, q + 1) == ord('"'):
            emit(T_ATTRIBUTE_EMPTY, p, q + 2)
          else:
            p = q + 1
            state = S_string
        elif d == ord('$'):
          p = q + 1
          state = S_string_kv
        else:
          # An unquoted value runs to the next comma, through closing parentheses and line breaks.
          emit(T_STR, p, upTo(',', p))
      continue

    if state == S_string:
      if c == ord('"'):
        inc p
        state = S_attribute
      else:
        emit(T_STR, p, upTo('"', p))
      continue

    if state == S_string_kv:
      emit(T_STR_KEY, p, upTo('=', p))
      state = S_string_kv_key
      continue

    if state == S_string_kv_key:
      if p >= n: continue
      var q = p + 1
      if c == ord('='):
        while cu(src, q) == 32: inc q
      if c != ord('=') or cu(src, q) != ord('"'):
        emit(T_ERROR, p, p)
        break
      p = q + 1
      state = S_string_kv_value
      continue

    if state == S_string_kv_value:
      if p >= n: continue
      if c == ord('"'):
        inc p
        state = S_attribute
      else:
        emit(T_STR_VALUE, p, upTo('"', p))
      continue

    if state == S_acc:
      emit(accValue, p, upTo('\n', p))
      state = S_INITIAL
      continue

    if c == ord('}'):
      inc p
      state = S_INITIAL
    else:
      emit(T_acc_descr_multiline_value, p, upTo('}', p))

  Tokens(types: types, starts: starts, ends: ends)
