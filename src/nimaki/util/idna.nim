## How `new URL()` writes a host outside ASCII: IDNA (UTS #46, the Unicode rules for
## internationalized domain names), with the options the URL standard gives them. Not a port of a
## file of Pele: Pele calls `new URL()`, which Node implements with ada (MIT, Copyright 2023 Yagiz
## Nizipli and Daniel Lemire). This is a port of ada 2.9.2's `src/ada_idna.cpp` (`to_ascii`,
## `map`, `is_label_valid`, Punycode), the version of the oracle's Node, with its own small
## departures from the standard kept, since the oracle has them: a joiner that passes its rule ends
## the checks of its label, and a label is checked right to left only when it holds a character
## written right to left. The tables are ada's, in `idna_data.nim` (by `tools/idna_data.nim`).
## Unicode normalization (NFC) reads unicodedb's tables: they are of a later Unicode than ada's, and
## Unicode promises that normalizing text of an earlier version gives the same result.
##
## A host is mapped code point by code point (upper case to lower case, a full-width letter to its
## ASCII one, a no-break space to a space...), normalized, cut into labels at each dot, checked,
## and each label outside ASCII is written as `xn--` and its Punycode.
import std/[options, strutils, unicode, algorithm]
import unicodedb/[compositions, decompositions, properties]
import ../js
import idna_data

func toCodePoints(s: string): seq[int] =
  var i = 0
  while i < s.len:
    let (cp, size) = codePointAt(s, i)
    result.add cp
    i += size

func isAscii(cps: openArray[int]): bool =
  for cp in cps:
    if cp >= 0x80: return false
  true

func contains(a: openArray[int32], cp: int): bool = binarySearch(a, int32(cp)) >= 0

# ---------------------------------------------------------------------------------------------
# NFC: `String.prototype.normalize("NFC")`

const
  SBase = 0xAC00
  LBase = 0x1100
  VBase = 0x1161
  TBase = 0x11A7
  LCount = 19
  VCount = 21
  TCount = 28
  NCount = VCount * TCount
  SCount = LCount * NCount

proc decomposeInto(cp: int, output: var seq[int]) =
  if cp >= SBase and cp < SBase + SCount:
    let s = cp - SBase
    output.add LBase + s div NCount
    output.add VBase + (s mod NCount) div TCount
    if s mod TCount != 0: output.add TBase + s mod TCount
    return
  var found = false
  for d in canonicalDecomposition(Rune(cp)):
    found = true
    decomposeInto(int(d), output)
  if not found: output.add cp

proc ccc(cp: int): int = combining(Rune(cp))

proc nfc*(cps: seq[int]): seq[int] =
  ## The canonical decomposition, put in canonical order, then composed again.
  var d: seq[int]
  for cp in cps: decomposeInto(cp, d)
  # Canonical order: each run of combining marks sorted by class, keeping the order of equals.
  var i = 0
  while i < d.len:
    if ccc(d[i]) == 0:
      inc i
      continue
    var j = i
    while j < d.len and ccc(d[j]) != 0: inc j
    for a in i + 1 ..< j:
      var b = a
      while b > i and ccc(d[b - 1]) > ccc(d[b]):
        swap(d[b - 1], d[b])
        dec b
    i = j
  if d.len == 0: return d
  # Composition: each mark joins the last starter it is not blocked from.
  result = @[d[0]]
  var starter = if ccc(d[0]) == 0: 0 else: -1
  var lastClass = if starter == 0: -1 else: 256
  for k in 1 ..< d.len:
    let cp = d[k]
    let c = ccc(cp)
    if starter >= 0 and (lastClass < c or (lastClass == -1)):
      let s = result[starter]
      var composed = -1
      if s >= LBase and s < LBase + LCount and cp >= VBase and cp < VBase + VCount and lastClass == -1:
        composed = SBase + ((s - LBase) * VCount + (cp - VBase)) * TCount
      elif s >= SBase and s < SBase + SCount and (s - SBase) mod TCount == 0 and
           cp > TBase and cp < TBase + TCount and lastClass == -1:
        composed = s + (cp - TBase)
      else:
        var r: Rune
        if composition(r, Rune(s), Rune(cp)): composed = int(r)
      if composed >= 0:
        result[starter] = composed
        continue
    if c == 0:
      starter = result.len
      lastClass = -1
    else:
      lastClass = c
    result.add cp

# ---------------------------------------------------------------------------------------------
# Punycode (RFC 3492), as ada writes it

const
  base = 36
  tMin = 1
  tMax = 26
  skew = 38
  damp = 700
  initialBias = 72
  initialN = 128
  maxInt = 0x7FFFFFFF

func adapt(delta0, n: int, firstTime: bool): int =
  var d = if firstTime: delta0 div damp else: delta0 div 2
  d += d div n
  var k = 0
  while d > ((base - tMin) * tMax) div 2:
    d = d div (base - tMin)
    k += base
  k + ((base - tMin + 1) * d) div (d + skew)

func digitToChar(d: int): char =
  if d < 26: char(d + 97) else: char(d + 22)

func charToDigit(c: char): int =
  if c in {'a'..'z'}: ord(c) - ord('a')
  elif c in {'0'..'9'}: ord(c) - ord('0') + 26
  else: -1

func punycodeToCodePoints*(input: string): Option[seq[int]] =
  ## ada's punycode_to_utf32: none where it fails.
  var output: seq[int]
  var n = initialN
  var i = 0
  var bias = initialBias
  var rest = input
  let endOfAscii = input.rfind('-')
  if endOfAscii >= 0:
    for c in input[0 ..< endOfAscii]:
      if ord(c) >= 0x80: return none(seq[int])
      output.add ord(c)
    rest = input[endOfAscii + 1 .. ^1]
  var p = 0
  while p < rest.len:
    let oldi = i
    var w = 1
    var k = base
    while true:
      if p >= rest.len: return none(seq[int])
      let digit = charToDigit(rest[p])
      inc p
      if digit < 0: return none(seq[int])
      if digit > (maxInt - i) div w: return none(seq[int])
      i += digit * w
      let t = if k <= bias: tMin elif k >= bias + tMax: tMax else: k - bias
      if digit < t: break
      if w > maxInt div (base - t): return none(seq[int])
      w *= base - t
      k += base
    bias = adapt(i - oldi, output.len + 1, oldi == 0)
    if i div (output.len + 1) > maxInt - n: return none(seq[int])
    n += i div (output.len + 1)
    i = i mod (output.len + 1)
    if n < 0x80: return none(seq[int])
    output.insert(n, i)
    inc i
  some(output)

func codePointsToPunycode*(input: openArray[int]): Option[string] =
  ## ada's utf32_to_punycode: none where it fails.
  var output = ""
  var n = initialN
  var d = 0
  var bias = initialBias
  var h = 0
  for c in input:
    if c < 0x80:
      inc h
      output.add char(c)
    if c > 0x10FFFF or (c >= 0xD880 and c < 0xE000): return none(string)
  let b = h
  if b > 0: output.add '-'
  while h < input.len:
    var m = 0x10FFFF
    for c in input:
      if c >= n and c < m: m = c
    if (m - n) > (maxInt - d) div (h + 1): return none(string)
    d += (m - n) * (h + 1)
    n = m
    for c in input:
      if c < n:
        if d == maxInt: return none(string)
        inc d
      if c == n:
        var q = d
        var k = base
        while true:
          let t = if k <= bias: tMin elif k >= bias + tMax: tMax else: k - bias
          if q < t: break
          output.add digitToChar(t + (q - t) mod (base - t))
          q = (q - t) div (base - t)
          k += base
        output.add digitToChar(q)
        bias = adapt(d, h + 1, h == b)
        d = 0
        inc h
    inc d
    inc n
  some(output)

# ---------------------------------------------------------------------------------------------
# Mapping and checks

func rangeIndex(cp: int): int =
  ## ada's find_range_index: the row whose range holds `cp`.
  var lo = 0
  var hi = idnaTable.high
  while lo <= hi:
    let mid = (lo + hi) shr 1
    let v = int(idnaTable[mid][0])
    if v < cp: lo = mid + 1
    elif v > cp: hi = mid - 1
    else: return mid
  if lo == 0: 0 else: lo - 1

func map*(input: openArray[int]): Option[seq[int]] =
  ## ada's map: each code point ignored, kept, or replaced by its mapping; none for one that is
  ## disallowed.
  var answer: seq[int]
  for x in input:
    let descriptor = idnaTable[rangeIndex(x)][1]
    case descriptor and 0xff
    of 0: discard
    of 1: answer.add x
    of 2: return none(seq[int])
    else:
      let count = int(descriptor shr 24)
      let index = int((descriptor shr 8) and 0xffff)
      for k in index ..< index + count: answer.add int(idnaMappings[k])
  some(answer)

func direction(cp: int): IdnaDirection =
  var lo = 0
  var hi = idnaDirections.high
  # the first row whose last code point is at least cp (std::lower_bound)
  var found = idnaDirections.len
  while lo <= hi:
    let mid = (lo + hi) shr 1
    if int(idnaDirections[mid][1]) < cp: lo = mid + 1
    else:
      found = mid
      hi = mid - 1
  if found == idnaDirections.len: return dNONE
  if cp >= int(idnaDirections[found][0]): idnaDirections[found][2] else: dNONE

func validLabel*(label: openArray[int]): bool =
  ## ada's is_label_valid.
  if label.len == 0: return true
  if label[0] in idnaCombining: return false
  for i, c in label:
    if c == 0x200C:
      if i > 0 and label[i - 1] in idnaVirama: return true
      if i == 0 or i + 1 >= label.len: return false
      var before, after = false
      for k in 0 ..< i:
        if label[k] in idnaJoiningL or label[k] in idnaJoiningD: before = true
      for k in i + 1 ..< label.len:
        if label[k] in idnaJoiningR or label[k] in idnaJoiningD: after = true
      return before and after
    elif c == 0x200D:
      if i > 0 and label[i - 1] in idnaVirama: return true
      return false
  var lastNonNsm = -1
  for i in countdown(label.high, 0):
    if direction(label[i]) != dNSM:
      lastNonNsm = i
      break
  if lastNonNsm < 0: return false
  var rtl = false
  for c in label:
    if direction(c) in {dR, dAL, dAN}: rtl = true
  if not rtl: return true
  if direction(label[0]) == dL:
    # ada stops before the last character that is not a mark, so it never checks that one
    for i in 0 ..< lastNonNsm:
      if direction(label[i]) notin {dL, dEN, dES, dCS, dET, dON, dBN, dNSM}: return false
    return true
  var hasAn, hasEn = false
  for i in 0 .. lastNonNsm:
    let d = direction(label[i])
    if d == dEN:
      hasEn = true
      if hasAn: return false
    if d == dAN:
      hasAn = true
      if hasEn: return false
    if d notin {dR, dAL, dAN, dEN, dES, dCS, dET, dON, dBN, dNSM}: return false
    if i == lastNonNsm and d notin {dR, dAL, dAN, dEN}: return false
  true

func startsWithXn(label: openArray[int]): bool =
  label.len >= 4 and label[0] == ord('x') and label[1] == ord('n') and label[2] == ord('-') and
    label[3] == ord('-')

proc punycodeLabelValid(ascii: string): bool =
  ## An `xn--` label: its Punycode must decode to a label that mapping and normalization leave as
  ## it is, not empty, and valid.
  let decoded = punycodeToCodePoints(ascii)
  if decoded.isNone: return false
  let postMap = map(decoded.get)
  if postMap.isNone or postMap.get != decoded.get: return false
  if nfc(postMap.get) != postMap.get: return false
  postMap.get.len > 0 and validLabel(postMap.get)

proc domainToAscii*(domain: string): Option[string] =
  ## ada's to_ascii: the host as `new URL()` writes it, or none where it fails.
  var labels: seq[seq[int]]
  let all = toCodePoints(domain)
  if isAscii(all):
    labels = @[newSeq[int]()]
    for c in domain.toLowerAscii:
      if c == '.': labels.add newSeq[int]()
      else: labels[^1].add ord(c)
  else:
    let mapped = map(all)
    if mapped.isNone: return none(string)
    labels = @[newSeq[int]()]
    for c in nfc(mapped.get):
      if c == ord('.'): labels.add newSeq[int]()
      else: labels[^1].add c
  var output = ""
  for k, label in labels:
    if k > 0: output.add '.'
    if label.len == 0: continue
    if startsWithXn(label):
      if not isAscii(label): return none(string)
      var ascii = ""
      for c in label: ascii.add char(c)
      output.add ascii
      if not punycodeLabelValid(ascii[4 .. ^1]): return none(string)
    elif isAscii(label):
      for c in label: output.add char(c)
    else:
      if not validLabel(label): return none(string)
      let p = codePointsToPunycode(label)
      if p.isNone: return none(string)
      output.add "xn--" & p.get
  if output == "": return none(string)
  some(output)
