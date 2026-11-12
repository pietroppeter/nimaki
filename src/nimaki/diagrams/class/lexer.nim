## port-of: src/diagrams/class/lexer.ts
## port-status: draft
##
## Port notes: positions are byte offsets into the UTF-8 source. `cu(i)` reads the character at
## byte `i` as `charCodeAt` does where it matters: an ASCII byte is itself, any other character
## its code point, and one outside the Basic Multilingual Plane its high surrogate (neither a
## letter nor a space, so the lexer stops there as Pele's does). Where the TypeScript steps one
## code unit past a character that may not be ASCII, the port steps past the whole character.
import std/strutils
import ../../js
import ../../util/[chars, unicode]
import tokens

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

const
  S_INITIAL = 0
  S_string = 1
  S_bqstring = 2
  S_generic = 3
  S_callbackName = 4
  S_callbackArgs = 5
  S_accTitle = 6
  S_accDescr = 7
  S_accDescrMultiline = 8
  S_cls = 9
  S_classBody = 10
  S_namespace = 11
  S_namespaceBody = 12

const AT_END = [
  ## The token each state gives at the end of input, before the parser sees the end itself.
  T_EOF, T_STR, T_EOF, T_GENERICTYPE, T_CALLBACK_NAME, T_CALLBACK_ARGS, T_acc_title_value,
  T_acc_descr_value, T_acc_descr_multiline_value, T_EOF, T_EOF_IN_STRUCT, T_EOF, T_EOF_IN_STRUCT]

const DIRECTIONS = ["TB", "BT", "RL", "LR"]

func cu(src: string, i: int): int =
  if i < 0 or i >= src.len: return -1
  let b = ord(src[i])
  if b < 0x80: return b
  let (cp, _) = codePointAt(src, i)
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func charLen(src: string, i: int): int =
  ## The bytes of the character at i (as one step of the TypeScript's `++`).
  if i >= src.len: 1 elif ord(src[i]) < 0x80: 1 else: codePointAt(src, i)[1]

func spacesFrom(src: string, i: int): int =
  ## The end of a run of `\s` starting at i.
  var j = i
  while j < src.len and isSpace(cu(src, j)): j += charLen(src, j)
  j

func lineEndFrom(src: string, p: int): int =
  ## RE_LINE_END = /[\n\r  ]/g from p: the first line terminator, or the end.
  var j = p
  while j < src.len:
    if isLineEnd(cu(src, j)): return j
    j += charLen(src, j)
  src.len

func directionEnd(src: string, p, lineEnd, which: int): int =
  ## /.*direction\s+TB[^\n]*/y (or BT, RL, LR) at p: the end of the match, or -1. The greedy
  ## `.*` cannot pass a line terminator, so `direction` starts before the line ends, and the last
  ## start that works is the one matched; `[^\n]*` then runs to the next line feed.
  var at = src.rfind("direction", 0, lineEnd - 1)
  while at >= p:
    let s = at + "direction".len
    let t = spacesFrom(src, s)
    if t > s and src.continuesWith(DIRECTIONS[which], t):
      let e = src.find('\n', t + 2)
      return if e == -1: src.len else: e
    at = if at > 0: src.rfind("direction", 0, at - 1) else: -1
  -1

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0
  var dirNext = src.find("direction")
  var lineEnd = -1
  var dirFailed = 0

  proc emit(kind, s, e: int): bool =
    types.add kind
    texts.add src[s ..< e]
    starts.add s
    p = e
    true
  proc push(s: int) =
    stack.add state
    state = s
  proc pop() =
    if stack.len > 0: state = stack.pop()
  proc kw(word: string): bool = src.continuesWith(word, p) and not isWord(cu(src, p + word.len))
  proc until(ch: char): int =
    let e = src.find(ch, p)
    if e == -1: n else: e

  # A run of whitespace is a NEWLINE up to its last line feed; the rest is skipped.
  proc space(leaves: bool) =
    var q = p
    var k = -1
    while q < n and isSpace(cu(src, q)):
      if src[q] == '\n': k = q
      q += charLen(src, q)
    if k < 0:
      p = q
      return
    if leaves: pop()
    discard emit(T_NEWLINE, p, k + 1)

  # The keywords that every state recognizes, even inside generics and backtick names.
  proc keyword(c: int): bool =
    case c
    of 99:
      if kw("cssClass"): return emit(T_CSSCLASS, p, p + 8)
      if kw("callback"): return emit(T_CALLBACK, p, p + 8)
      if kw("click"): return emit(T_CLICK, p, p + 5)
    of 108:
      if kw("link"): return emit(T_LINK, p, p + 4)
    of 110:
      if kw("note for"): return emit(T_NOTE_FOR, p, p + 8)
      if kw("note"): return emit(T_NOTE, p, p + 4)
    of 60:
      if cu(src, p + 1) == 60: return emit(T_ANNOTATION_START, p, p + 2)
    of 62:
      if cu(src, p + 1) == 62: return emit(T_ANNOTATION_END, p, p + 2)
    of 104:
      if kw("href"): return emit(T_HREF, p, p + 4)
    else: discard
    false

  proc common(c: int): bool =
    if keyword(c): return true
    let d = cu(src, p + 1)
    case c
    of 34:
      push(S_string)
      inc p
      return true
    of 126:
      push(S_generic)
      inc p
      return true
    of 96:
      push(S_bqstring)
      inc p
      return true
    of 95:
      if kw("_self"): return emit(T_LINK_TARGET, p, p + 5)
      if kw("_blank"): return emit(T_LINK_TARGET, p, p + 6)
      if kw("_parent"): return emit(T_LINK_TARGET, p, p + 7)
      if kw("_top"): return emit(T_LINK_TARGET, p, p + 4)
    of 60:
      return if d == 124: emit(T_EXTENSION, p, p + 2) else: emit(T_DEPENDENCY, p, p + 1)
    of 124:
      return d == 62 and emit(T_EXTENSION, p, p + 2)
    of 62:
      return emit(T_DEPENDENCY, p, p + 1)
    of 42:
      return emit(T_COMPOSITION, p, p + 1)
    of 111:
      if not isWord(d): return emit(T_AGGREGATION, p, p + 1)
    of 40:
      return d == 41 and emit(T_LOLLIPOP, p, p + 2)
    of 45:
      return if d == 45: emit(T_LINE, p, p + 2) else: emit(T_MINUS, p, p + 1)
    of 46:
      return if d == 46: emit(T_DOTTED_LINE, p, p + 2) else: emit(T_DOT, p, p + 1)
    of 58:
      var q = p + 1
      while q < n:
        let ch = src[q]
        if ch == ':' or ch == '\n' or ch == ';': break
        inc q
      if q > p + 1: return emit(T_LABEL, p, q)
      return d == 58 and cu(src, p + 2) == 58 and emit(T_STYLE_SEPARATOR, p, p + 3)
    of 43:
      return emit(T_PLUS, p, p + 1)
    of 37:
      return emit(T_PCT, p, p + 1)
    of 61:
      return emit(T_EQUALS, p, p + 1)
    of 91:
      return emit(T_SQS, p, p + 1)
    of 93:
      return emit(T_SQE, p, p + 1)
    of 33, 35, 36, 38, 39, 44, 63, 92, 47:
      return emit(T_PUNCTUATION, p, p + 1)
    else: discard
    if isWord(c):
      var q = p + 1
      while isWord(cu(src, q)): inc q
      return emit(T_ALPHA, p, q)
    isUnicodeLetter(c) and emit(T_UNICODE_TEXT, p, p + charLen(src, p))

  proc direction(): bool =
    if dirNext == -1 or p < dirFailed: return false
    if dirNext < p: dirNext = src.find("direction", p)
    if dirNext == -1: return false
    if lineEnd < p: lineEnd = lineEndFrom(src, p)
    if dirNext >= lineEnd: return false
    for i in 0 ..< 4:
      let e = directionEnd(src, p, lineEnd, i)
      if e >= 0: return emit(T_direction_tb + i, p, e)
    # No direction statement starts anywhere in the rest of this line either.
    dirFailed = lineEnd
    false

  proc initial(c: int): bool =
    if direction(): return true
    if isSpace(c):
      space(false)
      return true
    case c
    of 37:
      if cu(src, p + 1) == 37:
        var e = until('\n')
        while e < n and (src[e] == '\n' or src[e] == '\r'): inc e
        p = e
        return true
    of 97:
      let title = src.continuesWith("accTitle", p)
      if title or src.continuesWith("accDescr", p):
        let q = spacesFrom(src, p + 8)
        let d = cu(src, q)
        if d == 58:
          discard emit(if title: T_acc_title else: T_acc_descr, p, spacesFrom(src, q + 1))
          push(if title: S_accTitle else: S_accDescr)
          return true
        if d == 123 and not title:
          p = spacesFrom(src, q + 1)
          push(S_accDescrMultiline)
          return true
    of 99:
      if kw("classDiagram-v2"): return emit(T_CLASS_DIAGRAM, p, p + 15)
      if kw("classDiagram"): return emit(T_CLASS_DIAGRAM, p, p + 12)
      if src.continuesWith("call", p) and isSpace(cu(src, p + 4)):
        p = spacesFrom(src, p + 4)
        push(S_callbackName)
        return true
      if kw("classDef"): return emit(T_CLASSDEF, p, p + 8)
      if kw("class"):
        push(S_cls)
        return emit(T_CLASS, p, p + 5)
    of 91:
      if src.continuesWith("*]", p + 1): return emit(T_EDGE_STATE, p, p + 3)
    of 115:
      if kw("style"): return emit(T_STYLE, p, p + 5)
    of 110:
      if kw("namespace"):
        push(S_namespace)
        return emit(T_NAMESPACE, p, p + 9)
    of 44:
      return emit(T_COMMA, p, p + 1)
    of 35:
      return emit(T_BRKT, p, p + 1)
    else: discard
    common(c) or (c == 58 and emit(T_COLON, p, p + 1))

  while true:
    if p >= n:
      types.add AT_END[state]
      texts.add ""
      starts.add n
      break
    let c = cu(src, p)
    var ok = true
    case state
    of S_INITIAL:
      ok = initial(c)
    of S_cls:
      if isSpace(c):
        space(true)
      elif c == 125:
        pop()
        pop()
        discard emit(T_STRUCT_STOP, p, p + 1)
      elif c == 123:
        push(S_classBody)
        discard emit(T_STRUCT_START, p, p + 1)
      else:
        ok = common(c)
    of S_classBody:
      if c == 34:
        push(S_string)
        inc p
      elif c == 125:
        pop()
        discard emit(T_STRUCT_STOP, p, p + 1)
      elif c == 91 and src.continuesWith("*]", p + 1):
        discard emit(T_EDGE_STATE, p, p + 3)
      elif c == 123:
        discard emit(T_OPEN_IN_STRUCT, p, p + 1)
      elif c == 10:
        inc p
      else:
        var q = p + 1
        while q < n:
          let ch = src[q]
          if ch == '{' or ch == '}' or ch == '\n': break
          inc q
        discard emit(T_MEMBER, p, q)
    of S_namespace:
      if isSpace(c):
        space(true)
      elif c == 123:
        push(S_namespaceBody)
        discard emit(T_STRUCT_START, p, p + 1)
      elif c == 125:
        # The brace is read again in the state the namespace was opened from.
        pop()
      elif c == 110 and kw("namespace"):
        push(S_namespace)
        discard emit(T_NAMESPACE, p, p + 9)
      else:
        ok = common(c)
    of S_namespaceBody:
      if isSpace(c):
        space(false)
      elif c == 125:
        pop()
        discard emit(T_STRUCT_STOP, p, p + 1)
      elif c == 110 and kw("namespace"):
        push(S_namespace)
        discard emit(T_NAMESPACE, p, p + 9)
      elif c == 91 and src.continuesWith("*]", p + 1):
        discard emit(T_EDGE_STATE, p, p + 3)
      elif c == 99 and kw("class"):
        push(S_cls)
        discard emit(T_CLASS, p, p + 5)
      else:
        ok = common(c)
    of S_string:
      if c == 34:
        pop()
        inc p
      else:
        discard emit(T_STR, p, until('"'))
    of S_generic:
      if c == 34:
        push(S_string)
        inc p
      elif keyword(c):
        discard
      elif c == 126:
        pop()
        inc p
      else:
        discard emit(T_GENERICTYPE, p, until('~'))
    of S_bqstring:
      if c == 34:
        push(S_string)
        inc p
      elif keyword(c):
        discard
      elif c == 126:
        push(S_generic)
        inc p
      elif c == 96:
        pop()
        inc p
      else:
        discard emit(T_BQUOTE_STR, p, until('`'))
    of S_callbackName:
      if c == 40:
        let q = spacesFrom(src, p + 1)
        pop()
        if cu(src, q) == 41:
          p = q + 1
        else:
          push(S_callbackArgs)
          inc p
      else:
        discard emit(T_CALLBACK_NAME, p, until('('))
    of S_callbackArgs:
      if c == 41:
        pop()
        inc p
      else:
        discard emit(T_CALLBACK_ARGS, p, until(')'))
    of S_accTitle, S_accDescr:
      discard emit(if state == S_accTitle: T_acc_title_value else: T_acc_descr_value, p, until('\n'))
      pop()
    of S_accDescrMultiline:
      if c == 125:
        pop()
        inc p
      else:
        discard emit(T_acc_descr_multiline_value, p, until('}'))
    else: discard

    if not ok:
      types.add T_ERROR
      texts.add ""
      starts.add p
      return Tokens(types: types, texts: texts, starts: starts)

  types.add T_STOP
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)
