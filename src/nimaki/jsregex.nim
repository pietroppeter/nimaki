## JavaScript's regular expressions, in Nim. Not a port of a file of Pele: Pele writes about
## five hundred regular expression literals, and this module lets the port write the same ones,
## character for character, with the same meaning (decision 0016).
##
## The engine is nitely's `regex` package (pure Nim, linear time, also under `nim js`). Its
## syntax is close to JavaScript's, but not its meaning, so a pattern is first translated, once,
## at compile time for a literal (`jsre"/\n\s+/g"`) and at run time for `newRegExp`:
##
## - `\s` is JavaScript's whitespace (the engine's has U+0085 and lacks U+FEFF); `\w`, `\d` and
##   `\b` are ASCII (the engine's are Unicode); `.` stops at `\r`, U+2028 and U+2029 too.
## - With the `i` flag an ASCII letter matches only its two cases (the engine would also match
##   U+017F and the Kelvin sign); a cased letter outside ASCII under `i` is refused.
## - With the `m` flag `^` and `$` also stop at `\r`, U+2028 and U+2029.
## - A `{` that is not a quantifier is a literal, as in JavaScript.
## - `[\ud800-\udbff][\udc00-\udfff]` (a surrogate pair) is one character outside the BMP; a
##   lone surrogate cannot be in a UTF-8 string, so a class drops it.
## - Backreferences, named groups and `\c` are refused: Pele does not use them.
##
## The match procs follow JavaScript: `exec` at a `lastIndex` (anchored for a sticky regex),
## `replace` with `$&`, `$1`, `` $` ``, `$'`, `$$` or a function, `split` with its captures,
## and an empty match steps over one character. Indexes are byte offsets (decision 0011).
##
## What stays different: JavaScript's regexes read UTF-16 code units, so a `.` or a negated
## class matches half of an emoji there and the whole emoji here; and a capture inside a
## repeated group keeps its last value here where JavaScript resets it. `docs/divergences.md`
## says where this could show.
import std/[strutils, unicode, tables]
import regex
import regex/[nfatype, nfamatch2]

type
  Engine = ref object
    re: Regex2
    translated: string

  JsRegExp* = object
    ## A regular expression with JavaScript's flags. It is translated when it is made (at compile
    ## time for `jsre`, so a literal can be a `const`) and compiled for the engine the first time
    ## it matches: a compiled regex is large, so the program carries only the patterns, and each
    ## run compiles only the ones it uses.
    source*: string        ## the pattern as Pele writes it
    flags*: string         ## the flags as Pele writes them (`g`, `i`, `m`, `y`, `u`)
    global*, sticky*: bool
    atStart*: bool         ## it can only match at 0: a leading `^`, no `m` flag, no `|` around it
    prefix*: string        ## text every match starts with, found with `find` before the engine runs
    translated*: string    ## the pattern in the engine's syntax
    slot: int
      ## Where its engine is: a `jsre` literal's place in `literals` plus one, or minus one less
      ## the place in `made` of a regex made at run time (0 for none).

  JsMatch* = object
    ## The result of `exec`: `found` is false when nothing matched. Group 0 is the whole match.
    index*: int            ## where the match starts, a byte offset (-1 when none)
    stop*: int             ## one past its end
    groups*: seq[string]   ## the text of each group; "" for a group that did not take part
    defined*: seq[bool]    ## whether each group took part (`undefined` in JavaScript otherwise)

  JsRegExpError* = object of ValueError

# ---------------------------------------------------------------------------------------------
# Translation

const
  maxRune = 0x10FFFF
  jsSpaces = [(0x09, 0x0D), (0x20, 0x20), (0xA0, 0xA0), (0x1680, 0x1680), (0x2000, 0x200A),
              (0x2028, 0x2029), (0x202F, 0x202F), (0x205F, 0x205F), (0x3000, 0x3000),
              (0xFEFF, 0xFEFF)]
  jsWord = [(0x30, 0x39), (0x41, 0x5A), (0x5F, 0x5F), (0x61, 0x7A)]
  jsDigit = [(0x30, 0x39)]
  lineEnds = [(0x0A, 0x0A), (0x0D, 0x0D), (0x2028, 0x2029)]

type Ranges = seq[(int, int)]

func normalize(rs: Ranges): Ranges =
  ## Sorted, merged ranges.
  var s = rs
  for i in 1 ..< s.len:          # insertion sort: classes are short
    var j = i
    while j > 0 and s[j - 1][0] > s[j][0]:
      swap(s[j - 1], s[j])
      dec j
  for r in s:
    if result.len > 0 and r[0] <= result[^1][1] + 1:
      result[^1][1] = max(result[^1][1], r[1])
    else:
      result.add r

func complement(rs: Ranges): Ranges =
  var next = 0
  for r in normalize(rs):
    if r[0] > next: result.add (next, r[0] - 1)
    next = r[1] + 1
  if next <= maxRune: result.add (next, maxRune)

func withoutSurrogates(rs: Ranges): Ranges =
  ## A UTF-8 string holds no surrogate, so a class need not either.
  for r in normalize(rs):
    if r[1] < 0xD800 or r[0] > 0xDFFF: result.add r
    else:
      if r[0] < 0xD800: result.add (r[0], 0xD7FF)
      if r[1] > 0xDFFF: result.add (0xE000, r[1])

func isAsciiLetter(c: int): bool = c in 0x41..0x5A or c in 0x61..0x7A

func hasCase(c: int): bool =
  ## Whether a code point outside ASCII has another case (so `i` would change it).
  let r = Rune(c)
  r.toUpper != r or r.toLower != r

func countIn(rs: Ranges, lo, hi: int): int =
  for r in rs:
    let a = max(r[0], lo)
    let b = min(r[1], hi)
    if a <= b: result += b - a + 1

func noCasedLetters(rs: Ranges): bool =
  ## No code point beyond ASCII (in the BMP) with another case.
  for r in rs:
    for c in max(r[0], 0x80) .. min(r[1], 0xFFFF):
      if c notin 0xD800..0xDFFF and hasCase(c): return false
  true

func caseClosed(rs: Ranges, pattern: string): Ranges =
  ## Under the `i` flag: add the other case of every ASCII letter (JavaScript's `i` without `u`
  ## never pairs an ASCII letter with one beyond ASCII). A cased letter beyond ASCII is refused,
  ## unless the class holds every cased letter beyond ASCII (as `\S` does), when `i` changes
  ## nothing there.
  let rs = normalize(rs)
  result = rs
  for r in rs:
    for (lo, hi) in [(0x41, 0x5A), (0x61, 0x7A)]:
      let a = max(r[0], lo)
      let b = min(r[1], hi)
      if a <= b: result.add (a xor 0x20, b xor 0x20)
  let outside = complement(rs)
  let ok = if countIn(rs, 0x80, 0xFFFF) <= countIn(outside, 0x80, 0xFFFF): noCasedLetters(rs)
           else: noCasedLetters(outside)
  if not ok:
    raise newException(JsRegExpError,
      "a case-insensitive class with letters outside ASCII: /" & pattern & "/")
  result = normalize(result)

func hex(c: int): string = "\\x{" & toHex(c, if c > 0xFFFF: 6 else: 4) & "}"

func classText(rs: Ranges, negated: bool, raws = ""): string =
  let rs = normalize(rs)
  if rs.len == 0 and raws == "":
    return if negated: "[\\x{0}-\\x{10FFFF}]" else: "[^\\x{0}-\\x{10FFFF}]"
  result = if negated: "[^" else: "["
  for r in rs:
    result.add hex(r[0])
    if r[1] > r[0]: result.add "-" & hex(r[1])
  result.add raws
  result.add "]"

func literalText(c: int, ignoreCase: bool, pattern: string): string =
  if ignoreCase and isAsciiLetter(c):
    return classText(@[(c, c), (c xor 0x20, c xor 0x20)], false)
  if ignoreCase and c >= 0x80 and c <= maxRune and c notin 0xD800..0xDFFF and hasCase(c):
    raise newException(JsRegExpError,
      "a case-insensitive letter outside ASCII: /" & pattern & "/")
  if c < 0x80 and char(c) in {'0'..'9', 'A'..'Z', 'a'..'z', '_', ' ', '"', '\'', ',', '<', '>',
                               '=', '!', ':', ';', '@', '%', '&', '~', '`', '/'}:
    $char(c)
  else:
    hex(c)

func parseHex(p: string, i: var int, n: int): int =
  ## `n` hex digits at `p[i]`, or -1 (then `i` does not move).
  if i + n > p.len: return -1
  var v = 0
  for k in 0 ..< n:
    let ch = p[i + k]
    let d = case ch
      of '0'..'9': ord(ch) - ord('0')
      of 'a'..'f': ord(ch) - ord('a') + 10
      of 'A'..'F': ord(ch) - ord('A') + 10
      else: return -1
    v = v * 16 + d
  i += n
  v

func readUnicodeEscape(p: string, i: var int, unicodeFlag: bool): int =
  ## After `\u`: four hex digits (a surrogate pair `😀` is one code point), or with
  ## the `u` flag `\u{...}`. -1 when it is not an escape (then `u` is a literal `u`).
  if unicodeFlag and i < p.len and p[i] == '{':
    let close = p.find('}', i)
    if close < 0: return -1
    let v = parseHexInt(p[i + 1 ..< close])
    i = close + 1
    return v
  let v = parseHex(p, i, 4)
  if v in 0xD800..0xDBFF and i + 6 <= p.len and p[i] == '\\' and p[i + 1] == 'u':
    var j = i + 2
    let lo = parseHex(p, j, 4)
    if lo in 0xDC00..0xDFFF:
      i = j
      return 0x10000 + (v - 0xD800) * 0x400 + (lo - 0xDC00)
  v

type Atom = object
  ## One thing an escape stands for: a character, or a set of characters (`ranges`, and
  ## `raw`: a Unicode category `\p{L}` in the engine's syntax, with the `u` flag).
  isSet: bool
  c: int
  ranges: Ranges
  raw: string

func setAtom(rs: openArray[(int, int)], negated = false): Atom =
  Atom(isSet: true, ranges: if negated: complement(@rs) else: @rs)

func readEscape(p: string, i: var int, inClass, unicodeFlag: bool, pattern: string): Atom =
  ## The escape after a `\` at `p[i - 1]`; `i` moves past it. Outside a class `\b` and `\B`
  ## are handled by the caller.
  let ch = p[i]
  inc i
  case ch
  of 'd': setAtom(jsDigit)
  of 'D': setAtom(jsDigit, true)
  of 'w': setAtom(jsWord)
  of 'W': setAtom(jsWord, true)
  of 's': setAtom(jsSpaces)
  of 'S': setAtom(jsSpaces, true)
  of 'n': Atom(c: 0x0A)
  of 'r': Atom(c: 0x0D)
  of 't': Atom(c: 0x09)
  of 'v': Atom(c: 0x0B)
  of 'f': Atom(c: 0x0C)
  of 'b': Atom(c: 0x08)        # in a class, `\b` is a backspace
  of '0':
    if i < p.len and p[i] in {'0'..'9'}:
      raise newException(JsRegExpError, "an octal escape: /" & pattern & "/")
    Atom(c: 0)
  of '1'..'9':
    if inClass: raise newException(JsRegExpError, "an octal escape: /" & pattern & "/")
    raise newException(JsRegExpError, "a backreference: /" & pattern & "/")
  of 'x':
    let v = parseHex(p, i, 2)
    if v < 0: Atom(c: ord('x')) else: Atom(c: v)
  of 'u':
    let v = readUnicodeEscape(p, i, unicodeFlag)
    if v < 0: Atom(c: ord('u')) else: Atom(c: v)
  of 'p', 'P':
    # \p{L}: a general category, which the engine knows by the same name. (Scripts and binary
    # properties it does not: Pele uses neither.)
    if not unicodeFlag or i >= p.len or p[i] != '{':
      raise newException(JsRegExpError, "\\p without the u flag: /" & pattern & "/")
    let close = p.find('}', i)
    let name = p[i + 1 ..< close]
    if name notin ["L", "Lu", "Ll", "Lt", "Lm", "Lo", "M", "Mn", "Mc", "Me", "N", "Nd", "Nl", "No",
                   "P", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po", "S", "Sm", "Sc", "Sk", "So",
                   "Z", "Zs", "Zl", "Zp", "C", "Cc", "Cf", "Co", "Cn"]:
      raise newException(JsRegExpError, "a Unicode property the port does not know: \\p{" & name &
        "} in /" & pattern & "/")
    i = close + 1
    Atom(isSet: true, raw: "\\" & ch & "{" & name & "}")
  of 'c', 'k':
    raise newException(JsRegExpError, "an escape the port does not know: \\" & ch & " in /" &
      pattern & "/")
  else:
    # An identity escape: `\/`, `\.`, `\-`... stands for the character (a whole code point).
    var r: Rune
    var j = i - 1
    fastRuneAt(p, j, r, true)
    i = j
    Atom(c: int(r))

func readClass(p: string, i: var int, unicodeFlag, ignoreCase: bool,
               pattern: string, raws: var string): (Ranges, bool) =
  ## A class `[...]` starting after its `[`; `i` moves past its `]`.
  var negated = false
  if i < p.len and p[i] == '^':
    negated = true
    inc i
  var rs: Ranges
  var pending = -1           # a character that may start a range `a-z`
  var afterDash = false
  proc addChar(rs: var Ranges, pending: var int, afterDash: var bool, c: int) =
    if afterDash and pending >= 0:
      if c < pending: raise newException(JsRegExpError, "a range out of order: /" & pattern & "/")
      rs.add (pending, c)
      pending = -1
      afterDash = false
    else:
      if pending >= 0: rs.add (pending, pending)
      pending = c
  while true:
    if i >= p.len: raise newException(JsRegExpError, "an unclosed class: /" & pattern & "/")
    let ch = p[i]
    if ch == ']':
      inc i
      break
    if ch == '-' and pending >= 0 and not afterDash and i + 1 < p.len and p[i + 1] != ']':
      afterDash = true
      inc i
      continue
    var atom: Atom
    if ch == '\\':
      inc i
      atom = readEscape(p, i, true, unicodeFlag, pattern)
    else:
      var r: Rune
      fastRuneAt(p, i, r, true)
      atom = Atom(c: int(r))
    if atom.isSet:
      if afterDash:     # `[a-\d]`: in JavaScript (Annex B) both ends and the `-` are literal
        rs.add (pending, pending)
        rs.add (ord('-'), ord('-'))
        pending = -1
        afterDash = false
      elif pending >= 0:
        rs.add (pending, pending)
        pending = -1
      rs.add atom.ranges
      raws.add atom.raw
    else:
      addChar(rs, pending, afterDash, atom.c)
  if pending >= 0: rs.add (pending, pending)
  if afterDash: rs.add (ord('-'), ord('-'))
  if ignoreCase:
    if raws != "":
      raise newException(JsRegExpError, "a Unicode category under the i flag: /" & pattern & "/")
    rs = caseClosed(rs, pattern)
  (rs, negated)

func isQuantifier(p: string, i: int): bool =
  ## Whether `{` at `p[i]` starts `{n}`, `{n,}` or `{n,m}`.
  var j = i + 1
  let start = j
  while j < p.len and p[j] in {'0'..'9'}: inc j
  if j == start: return false
  if j < p.len and p[j] == '}': return true
  if j >= p.len or p[j] != ',': return false
  inc j
  while j < p.len and p[j] in {'0'..'9'}: inc j
  j < p.len and p[j] == '}'

func isSurrogateClass(rs: Ranges, negated: bool, lo, hi: int): bool =
  not negated and rs.len == 1 and rs[0] == (lo, hi)

func repeated(x: string, least, most: int): string =
  ## `x{least,most}` (`most` -1 for no bound) in pieces of at most 100, the engine's limit: for
  ## a greedy repeat of one character or a group without captures, the same matches.
  var n = least
  while n > 0:
    let k = min(n, 100)
    result.add "(?:" & x & "){" & $k & "}"
    n -= k
  if most < 0:
    result.add "(?:" & x & ")*"
  else:
    var rest = most - least
    while rest > 0:
      let k = min(rest, 100)
      result.add "(?:" & x & "){0," & $k & "}"
      rest -= k

func translate*(pattern, flags: string): string =
  ## A JavaScript pattern in the syntax of the `regex` package, with the same meaning.
  let ignoreCase = 'i' in flags
  let multiline = 'm' in flags
  let dotAll = 's' in flags
  let unicodeFlag = 'u' in flags
  for f in flags:
    if f notin {'g', 'i', 'm', 'y', 'u', 's'}:
      raise newException(JsRegExpError, "a flag the port does not know: " & f)
  let p = pattern
  var i = 0
  var lastWasHighSurrogates = false   # the previous atom was `[\ud800-\udbff]`
  var atomStart = 0                   # where the last atom starts in `result`
  var groups: seq[int]                # where each open group starts in `result`
  while i < p.len:
    let ch = p[i]
    var highSurrogates = false
    if ch notin {'{', '}', ')', '|', '?', '*', '+'}: atomStart = result.len
    case ch
    of '\\':
      inc i
      if i >= p.len: raise newException(JsRegExpError, "a trailing \\: /" & pattern & "/")
      if p[i] in {'b', 'B'}:
        result.add if p[i] == 'b': "\\b" else: "\\B"   # ASCII, with the regexAscii flag
        inc i
      else:
        let atom = readEscape(p, i, false, unicodeFlag, pattern)
        if atom.raw != "": result.add atom.raw
        elif atom.isSet: result.add classText(withoutSurrogates(atom.ranges), false)
        else: result.add literalText(atom.c, ignoreCase, pattern)
    of '.':
      inc i
      result.add(if dotAll: "[\\x{0}-\\x{10FFFF}]"
                 else: classText(withoutSurrogates(complement(@lineEnds)), false))
    of '[':
      inc i
      var raws = ""
      let (rs, negated) = readClass(p, i, unicodeFlag, ignoreCase, pattern, raws)
      if raws != "":
        result.add classText(withoutSurrogates(rs), negated, raws)
      elif isSurrogateClass(rs, negated, 0xD800, 0xDBFF):
        highSurrogates = true            # wait for the low half
      elif lastWasHighSurrogates and isSurrogateClass(rs, negated, 0xDC00, 0xDFFF):
        result.add classText(@[(0x10000, maxRune)], false)
      else:
        let clean = if negated: withoutSurrogates(complement(rs)) else: withoutSurrogates(rs)
        result.add classText(clean, false)
    of '^':
      inc i
      result.add(if multiline: "(?:^|(?<=[\\r\\x{2028}\\x{2029}]))" else: "^")
    of '$':
      inc i
      result.add(if multiline: "(?:$|(?=[\\r\\x{2028}\\x{2029}]))" else: "$")
    of '(':
      if i + 2 < p.len and p[i + 1] == '?' and p[i + 2] == '<' and
          (i + 3 >= p.len or p[i + 3] notin {'=', '!'}):
        raise newException(JsRegExpError, "a named group: /" & pattern & "/")
      groups.add result.len
      result.add '('
      inc i
    of '{':
      if isQuantifier(p, i):
        let close = p.find('}', i)
        let counts = p[i + 1 ..< close].split(',')
        let least = parseInt(counts[0])
        let most = if counts.len == 1: least elif counts[1] == "": -1 else: parseInt(counts[1])
        if least <= 100 and most <= 100:
          result.add p[i .. close]
        else:
          let x = result[atomStart .. ^1]
          let lazy = close + 1 < p.len and p[close + 1] == '?'
          if lazy or x.find("(") >= 0 and x.replace("(?", "").find("(") >= 0:
            raise newException(JsRegExpError,
              "a repeat over 100 of a group with captures or a lazy one: /" & pattern & "/")
          result.setLen atomStart
          result.add repeated(x, least, most)
        i = close + 1
      else:
        result.add "\\{"
        inc i
    of '}', ']':
      result.add '\\'
      result.add ch
      inc i
    of ')':
      if groups.len > 0: atomStart = groups.pop()
      result.add ch
      inc i
    of '|', '?', '*', '+':
      result.add ch
      inc i
    else:
      var r: Rune
      fastRuneAt(p, i, r, true)
      result.add literalText(int(r), ignoreCase, pattern)
    if lastWasHighSurrogates and not (ch == '['):
      raise newException(JsRegExpError, "a lone surrogate class: /" & pattern & "/")
    lastWasHighSurrogates = highSurrogates
  if lastWasHighSurrogates:
    raise newException(JsRegExpError, "a lone surrogate class: /" & pattern & "/")
  if multiline: result = "(?m)" & result

func splitLiteral(lit: string): (string, string) =
  if lit.len < 2 or lit[0] != '/':
    raise newException(JsRegExpError, "a regex literal starts with /: " & lit)
  let close = lit.rfind('/')
  if close == 0: raise newException(JsRegExpError, "a regex literal ends with /flags: " & lit)
  (lit[1 ..< close], lit[close + 1 .. ^1])

var literals: seq[Engine]
  ## The engine of each `jsre` literal, made the first time the literal matches.
var dynamic: seq[Engine]
  ## The engine of each pattern made with `newRegExp`, once per pattern and flags: Pele makes
  ## some in a loop (`new RegExp(`[";]${prop}:...`)`), and JavaScript caches them as this does.
var dynamicIndex: Table[string, int]
var slots {.compileTime.} = 0

proc takeSlot(): int {.compileTime.} =
  inc slots
  slots

proc compiled(re: JsRegExp): Regex2 =
  try:
    re2(re.translated, {regexAscii})
  except RegexError as e:
    raise newException(JsRegExpError, "/" & re.source & "/" & re.flags & " -> " &
      re.translated & ": " & e.msg)

func topLevelBar(pattern: string): bool =
  ## Whether a `|` outside every group and class splits the pattern into alternatives.
  var depth = 0
  var i = 0
  var inClass = false
  while i < pattern.len:
    let c = pattern[i]
    if c == '\\': i += 2; continue
    if inClass:
      if c == ']': inClass = false
    elif c == '[': inClass = true
    elif c == '(': inc depth
    elif c == ')': dec depth
    elif c == '|' and depth == 0: return true
    inc i
  false

func onlyAtStart(pattern, flags: string): bool =
  ## Whether every match must start at 0: the pattern opens with `^`, there is no `m` flag, and
  ## no `|` outside a group could start an alternative without it. The engine's search would try
  ## every position of the text in vain.
  'm' notin flags and pattern.len > 0 and pattern[0] == '^' and not topLevelBar(pattern)

func literalPrefix(pattern, flags: string): string =
  ## The plain characters every match starts with (`var(--_` of `/var\(--_(r|tw|hw|w)\)/g`). The
  ## engine's search runs its automaton at every position of the text; finding the prefix first,
  ## then matching where it is, gives the same first match and skips the rest.
  if 'i' in flags or topLevelBar(pattern): return ""
  const plain = {'a'..'z', 'A'..'Z', '0'..'9', ' ', '-', '_', ':', ';', '"', '\'', '<', '>', '=',
                 ',', '#', '%', '&', '@', '!', '~', '`', '/'}
  var i = 0
  while i < pattern.len:
    var ch: char
    var next: int
    if pattern[i] == '\\' and i + 1 < pattern.len and pattern[i + 1] in {'(', ')', '[', ']', '{',
        '}', '.', '*', '+', '?', '|', '^', '$', '\\', '/', '-'}:
      ch = pattern[i + 1]
      next = i + 2
    elif pattern[i] in plain:
      ch = pattern[i]
      next = i + 1
    else: break
    if next < pattern.len and pattern[next] in {'?', '*', '{', '+'}:
      if pattern[next] == '+': result.add ch
      break
    result.add ch
    i = next

func made(pattern, flags, translated: string, slot: int): JsRegExp =
  JsRegExp(source: pattern, flags: flags, global: 'g' in flags, sticky: 'y' in flags,
           atStart: onlyAtStart(pattern, flags), prefix: literalPrefix(pattern, flags),
           translated: translated, slot: slot)

proc dynamicSlot(pattern, flags: string): JsRegExp =
  let key = flags & "/" & pattern
  let at = dynamicIndex.getOrDefault(key, -1)
  if at >= 0:
    let e = dynamic[at]
    return made(pattern, flags, e.translated, -1 - at)
  result = made(pattern, flags, translate(pattern, flags), -1 - dynamic.len)
  dynamic.add Engine(re: compiled(result), translated: result.translated)
  dynamicIndex[key] = dynamic.high

func newRegExp*(pattern: string, flags = ""): JsRegExp =
  ## `new RegExp(pattern, flags)`, translated and compiled at run time (once per pattern).
  {.cast(noSideEffect).}: result = dynamicSlot(pattern, flags)

func parseRegExpLiteral*(lit: string): JsRegExp =
  ## `/pattern/flags`, as written in JavaScript, translated at run time.
  let (pattern, flags) = splitLiteral(lit)
  newRegExp(pattern, flags)

func literal*(lit: string, slot: int): JsRegExp =
  ## A literal translated for `jsre` (at compile time), with its slot.
  let (pattern, flags) = splitLiteral(lit)
  made(pattern, flags, translate(pattern, flags), slot)

template jsre*(lit: static string): JsRegExp =
  ## A JavaScript regex literal, translated at compile time (a pattern the port cannot
  ## translate faithfully stops the build): `const RE = jsre"/\n\s+/g"` (a raw string: a
  ## backslash is itself; write `""` for a quote, or use `jsre"""..."""`).
  const re = literal(lit, takeSlot())
  re

func literal*(pattern, flags: string, slot: int): JsRegExp =
  made(pattern, flags, translate(pattern, flags), slot)

template jsre*(pattern, flags: static string): JsRegExp =
  ## `new RegExp(pattern, flags)` for a pattern known at compile time (built from constants, as
  ## Pele builds some with `String.raw`): translated at compile time, like a literal.
  const re = literal(pattern, flags, takeSlot())
  re

proc engineOf(re: JsRegExp): Engine =
  if re.slot < 0: return dynamic[-1 - re.slot]
  if re.slot > literals.len: literals.setLen(re.slot)
  result = literals[re.slot - 1]
  if result == nil:
    result = Engine(re: compiled(re))
    literals[re.slot - 1] = result

template withEngine(re: JsRegExp, r, body: untyped): untyped =
  ## `body`, with `r` the compiled regex of `re`. A literal is compiled the first time it
  ## matches (that only fills a cache: what the regex matches does not change).
  var e: Engine
  {.cast(noSideEffect).}: e = engineOf(re)
  template r: untyped {.inject.} = e.re
  body

func check*(re: JsRegExp): JsRegExp =
  ## Compiles `re` now (the tests do it for every pattern), and returns it.
  withEngine(re, r): discard r.isInitialized
  re

func escapeRegExp*(s: string): string =
  ## `s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')`: a text that a pattern matches literally.
  for c in s:
    if c in {'.', '*', '+', '?', '^', '$', '{', '}', '(', ')', '|', '[', ']', '\\'}:
      result.add '\\'
    result.add c

# ---------------------------------------------------------------------------------------------
# Matching

func isSet*(re: JsRegExp): bool {.inline.} =
  ## Whether `re` holds a regex (a field left at its default does not).
  re.slot != 0

func found*(m: JsMatch): bool {.inline.} = m.index >= 0

func `[]`*(m: JsMatch, i: int): string {.inline.} =
  ## The text of group `i` ("" when it did not take part, or when there is no such group).
  if i < m.groups.len: m.groups[i] else: ""

func has*(m: JsMatch, i: int): bool {.inline.} =
  ## Whether group `i` took part in the match (`m[i] !== undefined`).
  i < m.defined.len and m.defined[i]

func groupOr*(m: JsMatch, i: int, otherwise: string): string {.inline.} =
  ## `m?.[i] ?? otherwise`: group `i`, or `otherwise` when there was no match or the group did
  ## not take part.
  if m.has(i): m.groups[i] else: otherwise

func noMatch(): JsMatch = JsMatch(index: -1, stop: -1)

func toJsMatch(s: string, m: RegexMatch2): JsMatch =
  let b = m.boundaries
  result = JsMatch(index: b.a, stop: b.b + 1)
  result.groups = newSeq[string](m.captures.len + 1)
  result.defined = newSeq[bool](m.captures.len + 1)
  result.groups[0] = s[b.a .. b.b]
  result.defined[0] = true
  for k in 0 ..< m.captures.len:
    let g = m.captures[k]
    if g.a >= 0:
      result.groups[k + 1] = s[g.a .. g.b]
      result.defined[k + 1] = true

func matchHere(re: JsRegExp, s: string, at: int): JsMatch =
  ## The match that starts exactly at `at` (a sticky match), if any.
  var m: RegexMatch2
  if at > s.len: return noMatch()
  withEngine(re, r):
    result = if matchImpl(s, r.toRegex, m, at, {mfAnchored}): toJsMatch(s, m) else: noMatch()

func searchFrom(re: JsRegExp, s: string, at: int): JsMatch =
  ## The first match that starts at `at` or later.
  var m: RegexMatch2
  if at > s.len: return noMatch()
  if re.atStart: return (if at == 0: matchHere(re, s, 0) else: noMatch())
  if re.prefix.len > 0:
    var p = s.find(re.prefix, at)
    while p >= 0:
      let m = matchHere(re, s, p)
      if m.found: return m
      p = s.find(re.prefix, p + 1)
    return noMatch()
  withEngine(re, r):
    result = if find(s, r, m, at): toJsMatch(s, m) else: noMatch()

func exec*(re: JsRegExp, s: string, lastIndex = 0): JsMatch =
  ## `re.lastIndex = lastIndex; re.exec(s)`: anchored at `lastIndex` for a sticky regex, the
  ## first match from `lastIndex` on otherwise. Without `g` or `y`, JavaScript starts at 0: pass
  ## nothing. The next `lastIndex` of a `g` or `y` regex is `m.stop`.
  if re.sticky: matchHere(re, s, lastIndex) else: searchFrom(re, s, lastIndex)

func matchEnd*(re: JsRegExp, s: string, lastIndex = 0): int =
  ## Where the match of `exec(re, s, lastIndex)` ends (the next `lastIndex`), or -1: the same
  ## match, without reading its groups (what a lexer needs, and quicker).
  var m: RegexMatch2
  if lastIndex > s.len or (re.atStart and lastIndex > 0): return -1
  if re.prefix.len > 0 and not re.sticky and not re.atStart:
    var p = s.find(re.prefix, lastIndex)
    while p >= 0:
      withEngine(re, r):
        if matchImpl(s, r.toRegex, m, p, {mfAnchored, mfNoCaptures}): return m.boundaries.b + 1
      p = s.find(re.prefix, p + 1)
    return -1
  withEngine(re, r):
    result =
      if re.sticky or re.atStart:
        if matchImpl(s, r.toRegex, m, lastIndex, {mfAnchored, mfNoCaptures}): m.boundaries.b + 1
        else: -1
      elif find(s, r, m, lastIndex): m.boundaries.b + 1
      else: -1

func test*(re: JsRegExp, s: string, lastIndex = 0): bool =
  ## `re.test(s)`.
  matchEnd(re, s, lastIndex) >= 0

func search*(s: string, re: JsRegExp): int =
  ## `s.search(re)`: where the first match starts, or -1.
  exec(re, s).index

func nextIndex(s: string, i: int): int =
  ## One character on, after an empty match (JavaScript steps one code unit: here one code
  ## point, which differs only inside a character outside the BMP).
  if i >= s.len: return i + 1
  i + max(1, runeLenAt(s, i))

iterator matches*(re: JsRegExp, s: string): JsMatch =
  ## The matches of a `g` regex, as `s.matchAll(re)` (or a `while (m = re.exec(s))` loop) finds
  ## them; for a sticky regex they must follow each other from 0.
  if re.sticky or re.atStart or re.prefix.len > 0:
    var at = 0
    while at <= s.len:
      let m = exec(re, s, at)
      if not m.found: break
      yield m
      at = if m.stop == m.index: nextIndex(s, m.stop) else: m.stop
  else:
    # The engine's own walk over every match. Its `find` from a position runs on while matches
    # follow each other, to return only the first, so a loop of `find`s took time in the square
    # of the text (Pele's stress tests: 3,000 comment lines took seconds).
    withEngine(re, r):
      for m in findAll(s, r):
        yield toJsMatch(s, m)

func matchAll*(s: string, re: JsRegExp): seq[JsMatch] =
  ## `[...s.matchAll(re)]`.
  for m in re.matches(s): result.add m

func match*(s: string, re: JsRegExp): seq[string] =
  ## `s.match(re)` for a `g` regex: the text of every match (`null` is an empty seq). For a regex
  ## without `g`, `s.match(re)` is `re.exec(s)`: use `exec`.
  for m in re.matches(s): result.add m.groups[0]

func expand(by: string, s: string, m: JsMatch): string =
  ## A replacement string with JavaScript's `$` patterns.
  var i = 0
  let n = m.groups.len - 1
  while i < by.len:
    let c = by[i]
    if c == '$' and i + 1 < by.len:
      let d = by[i + 1]
      case d
      of '$': result.add '$'; i += 2; continue
      of '&': result.add m.groups[0]; i += 2; continue
      of '`': result.add s[0 ..< m.index]; i += 2; continue
      of '\'': result.add s[m.stop .. ^1]; i += 2; continue
      of '0'..'9':
        let one = ord(d) - ord('0')
        if i + 2 < by.len and by[i + 2] in {'0'..'9'}:
          let two = one * 10 + ord(by[i + 2]) - ord('0')
          if two >= 1 and two <= n:
            result.add m[two]; i += 3; continue
        if one >= 1 and one <= n:
          result.add m[one]; i += 2; continue
      else: discard
    result.add c
    inc i

template replaceWith*(s: string, re: JsRegExp, m, by: untyped): string =
  ## `s` with each match (every one with `g`, the first otherwise) replaced by `by`, an
  ## expression of the match `m`: `s.replace(re, (m) => by)` where a func must stay a func.
  var output = ""
  var last = 0
  if not re.global:
    let m = exec(re, s)
    if m.found:
      output = s[0 ..< m.index] & by & s[m.stop .. ^1]
    else:
      output = s
  else:
    for m in re.matches(s):
      output.add s[last ..< m.index]
      output.add by
      last = m.stop
    output.add s[last .. ^1]
  output

func replace*(s: string, re: JsRegExp, by: string): string =
  ## `s.replace(re, by)` (every match with `g`, the first otherwise), with `$&`, `$1`... in `by`.
  if '$' notin by: replaceWith(s, re, m, by)
  else: replaceWith(s, re, m, expand(by, s, m))

proc replace*(s: string, re: JsRegExp, by: proc (m: JsMatch): string): string =
  ## `s.replace(re, (match, p1, p2..., offset) => ...)`: the function gets the whole match.
  replaceWith(s, re, m, by(m))

func split*(s: string, re: JsRegExp, limit = -1): seq[string] =
  ## `s.split(re, limit)`, as the specification's `@@split` does it: a match anchored at each
  ## position, the captures put in between (a group that did not take part is "" here,
  ## `undefined` in JavaScript).
  let lim = if limit < 0: high(int) else: limit
  if lim == 0: return
  if s.len == 0:
    if not matchHere(re, s, 0).found: result.add s
    return
  var p = 0
  var q = 0
  while q < s.len:
    let m = matchHere(re, s, q)
    if not m.found or m.stop == p:
      q = nextIndex(s, q)
      continue
    result.add s[p ..< q]
    if result.len == lim: return
    p = m.stop
    for k in 1 ..< m.groups.len:
      result.add m.groups[k]
      if result.len == lim: return
    q = p
  result.add s[p .. ^1]
