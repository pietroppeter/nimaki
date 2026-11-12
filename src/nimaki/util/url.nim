## port-of: src/util/url.ts
## port-status: draft
##
## Port notes: the regular expressions are scanners, each with its pattern in a comment.
## `decodeURIComponent` and `new URL()` are written here: the URL parser covers what a link in
## a diagram needs (the WHATWG rules for http and https: scheme and host in lower case, default
## ports dropped, dot segments resolved, the percent-encode sets of path, query and fragment,
## IPv4 hosts) but not internationalized domain names, which it keeps as they are written.
import std/[strutils, options]
from std/math import trunc, pow, `mod`
import ../js
import ../svg/builder
import ../text/entities
import ../types

const BLANK = "about:blank"

func isCtrl(cp: int): bool =
  ## /[\u0000-\u001F\u007F-\u009F -‍﻿\uD800-\uDFFF￾￿]/u
  (cp >= 0 and cp <= 0x1f) or (cp >= 0x7f and cp <= 0x9f) or (cp >= 0x2000 and cp <= 0x200d) or
    cp == 0xfeff or (cp >= 0xd800 and cp <= 0xdfff) or cp == 0xfffe or cp == 0xffff

func ctrlAt(s: string, i: int): (bool, int) =
  ## Whether a character of RE_CTRL starts at byte i, and its length. A byte that is not valid
  ## UTF-8 counts as one (the nearest thing to a lone surrogate).
  let (cp, size) = codePointAt(s, i)
  if cp == 0xFFFD and not s.continuesWith("�", i): return (true, size)
  (isCtrl(cp), size)

func removeCtrl(s: string): string =
  var i = 0
  while i < s.len:
    let (bad, size) = ctrlAt(s, i)
    if not bad: result.add s[i ..< i + size]
    i += size

func hasCtrl(s: string): bool =
  var i = 0
  while i < s.len:
    let (bad, size) = ctrlAt(s, i)
    if bad: return true
    i += size

func isWordByte(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func wordRun(s: string, i: int): int =
  var j = i
  while j < s.len and isWordByte(s[j]): inc j
  j

func numberOfWord(w: string): float =
  ## Number(w) for a run of \w characters.
  if w == "Infinity": return Inf
  if w.len > 2 and w[0] == '0' and w[1] in {'x', 'X', 'o', 'O', 'b', 'B'}:
    let base = case w[1]
      of 'x', 'X': 16
      of 'o', 'O': 8
      else: 2
    var v = 0.0
    for c in w[2 .. ^1]:
      let d = if c in {'0'..'9'}: ord(c) - 48
              elif c in {'a'..'f'}: ord(c) - 87
              elif c in {'A'..'F'}: ord(c) - 55
              else: 99
      if d >= base: return NaN
      v = v * float(base) + float(d)
    return v
  # Decimal digits, with an optional exponent.
  var i = 0
  while i < w.len and w[i] in {'0'..'9'}: inc i
  if i == 0: return NaN
  if i < w.len:
    if w[i] notin {'e', 'E'} or i + 1 >= w.len: return NaN
    for c in w[i + 1 .. ^1]:
      if c notin {'0'..'9'}: return NaN
  try: parseFloat(w) except ValueError: NaN

func fromCharCodeOf(v: float): string =
  ## String.fromCharCode(v)
  var code = 0
  if not (v != v) and v != Inf and v != -Inf:
    let t = trunc(v)
    var m = t mod 65536.0
    if m < 0: m += 65536.0
    code = int(m)
  if code >= 0xd800 and code <= 0xdfff: "\xff" # a lone surrogate: invalid, as RE_CTRL sees it
  else: fromCodePoint(code)

func replaceEntities(s: string): string =
  ## s.replace(/&#(\w+)(^\w|;)?/g, (_m, dec) => String.fromCharCode(dec))
  var i = 0
  while i < s.len:
    if s[i] == '&' and i + 1 < s.len and s[i + 1] == '#':
      let stop = wordRun(s, i + 2)
      if stop > i + 2:
        result.add fromCharCodeOf(numberOfWord(s[i + 2 ..< stop]))
        i = if stop < s.len and s[stop] == ';': stop + 1 else: stop
        continue
    result.add s[i]
    inc i

func hasEntity(s: string): bool =
  var at = s.find("&#")
  while at != -1:
    if wordRun(s, at + 2) > at + 2: return true
    at = s.find("&#", at + 1)
  false

func ctrlEntityAt(s: string, i: int): int =
  ## /&(newline|tab);/gi: the length of a match at i, or 0
  if s[i] != '&': return 0
  for word in ["newline", "tab"]:
    let stop = i + 1 + word.len
    if stop < s.len and cmpIgnoreCase(s[i + 1 ..< stop], word) == 0 and s[stop] == ';': return word.len + 2
  0

func removeCtrlEntities(s: string): string =
  var i = 0
  while i < s.len:
    let n = ctrlEntityAt(s, i)
    if n > 0:
      i += n
      continue
    result.add s[i]
    inc i

func hasCtrlEntity(s: string): bool =
  for i in 0 ..< s.len:
    if ctrlEntityAt(s, i) > 0: return true
  false

func wsEscapeAt(s: string, i: int): int =
  ## /(\\|%5[cC])((%(6[eE]|72|74))|[nrt])/g: the length of a match at i, or 0
  var j: int
  if s[i] == '\\': j = i + 1
  elif s.continuesWith("%5", i) and i + 2 < s.len and s[i + 2] in {'c', 'C'}: j = i + 3
  else: return 0
  if j + 2 < s.len and s[j] == '%' and
     ((s[j + 1] == '6' and s[j + 2] in {'e', 'E'}) or (s[j + 1] == '7' and s[j + 2] in {'2', '4'})):
    return j + 3 - i
  if j < s.len and s[j] in {'n', 'r', 't'}: return j + 1 - i
  0

func removeWsEscapes(s: string): string =
  var i = 0
  while i < s.len:
    let n = wsEscapeAt(s, i)
    if n > 0:
      i += n
      continue
    result.add s[i]
    inc i

func hasWsEscape(s: string): bool =
  for i in 0 ..< s.len:
    if wsEscapeAt(s, i) > 0: return true
  false

func hexValue(c: char): int =
  case c
  of '0'..'9': ord(c) - 48
  of 'a'..'f': ord(c) - 87
  of 'A'..'F': ord(c) - 55
  else: -1

func validUtf8(s: string): bool =
  var i = 0
  while i < s.len:
    let (cp, size) = codePointAt(s, i)
    if cp == 0xFFFD and not s.continuesWith("�", i): return false
    i += size
  true

func decode(uri: string): string =
  ## decodeURIComponent(uri), or `uri` when that throws.
  var bytes = ""
  var i = 0
  while i < uri.len:
    if uri[i] == '%':
      if i + 2 >= uri.len: return uri
      let a = hexValue(uri[i + 1])
      let b = hexValue(uri[i + 2])
      if a < 0 or b < 0: return uri
      bytes.add char(a * 16 + b)
      i += 3
    else:
      bytes.add uri[i]
      inc i
  if not validUtf8(bytes): return uri
  bytes

proc unwrap(url: string, percent: bool): Option[string] =
  ## Removes the control characters, entity codes and escapes that could hide a scheme, and with
  ## `percent`, percent escapes too. None for a URL wrapped too many times to be a real one.
  var output = if percent: decode(jsTrim(url)) else: jsTrim(url)
  var rounds = 0
  while true:
    inc rounds
    if rounds > 32: return none(string)
    output = jsTrim(removeWsEscapes(removeCtrl(removeCtrlEntities(replaceEntities(removeCtrl(output))))))
    if percent: output = decode(output)
    if not (hasCtrl(output) or hasEntity(output) or hasCtrlEntity(output) or hasWsEscape(output)): break
  some(output)

func isLineTerminator(s: string, i: int): (bool, int) =
  let (cp, size) = codePointAt(s, i)
  (cp == 10 or cp == 13 or cp == 0x2028 or cp == 0x2029, size)

func schemeMatch(s: string): (bool, string) =
  ## s.match(/^.+(:|&colon;)/gim)?.[0]: on the first line that has one, from the line's start to
  ## its last `:` or `&colon;` after at least one character.
  var start = 0
  while start <= s.len:
    # The end of this line.
    var stop = start
    while stop < s.len:
      let (term, _) = isLineTerminator(s, stop)
      if term: break
      stop += codePointAt(s, stop)[1]
    # Greedy `.+` backtracks from the end of the line: the colon that starts last wins.
    var lastEnd = -1
    var q = start + 1
    while q < stop:
      if s[q] == ':': lastEnd = q + 1
      elif q + 7 <= stop and cmpIgnoreCase(s[q ..< q + 7], "&colon;") == 0: lastEnd = q + 7
      inc q
    if lastEnd >= 0: return (true, s[start ..< lastEnd])
    if stop >= s.len: break
    start = stop + isLineTerminator(s, stop)[1]
  (false, "")

func invalidProtocol(s: string): bool =
  ## /^([^\w]*)(javascript|data|vbscript)/im
  var starts = @[0]
  var i = 0
  while i < s.len:
    let (term, size) = isLineTerminator(s, i)
    if term: starts.add i + size
    i += size
  for start in starts:
    var j = start
    while j < s.len and not isWordByte(s[j]): inc j
    for word in ["javascript", "data", "vbscript"]:
      if s.continuesWith(word, j) or (j < s.len and cmpIgnoreCase(s[j ..< min(s.len, j + word.len)], word) == 0):
        return true
  false

# ---------------------------------------------------------------------------------------------
# new URL(s).toString() for http and https

func percentEncode(s: string, keep: proc (c: char): bool {.noSideEffect.}): string =
  for c in s:
    if ord(c) <= 0x20 or ord(c) >= 0x7f or not keep(c):
      result.add "%" & toHex(ord(c), 2)
    else:
      result.add c

func pathKeep(c: char): bool = c notin {'"', '#', '<', '>', '?', '`', '{', '}'}
func queryKeep(c: char): bool = c notin {'"', '#', '<', '>', '\''}
func fragmentKeep(c: char): bool = c notin {'"', '<', '>', '`'}
func userinfoKeep(c: char): bool =
  c notin {'"', '#', '<', '>', '?', '`', '{', '}', '/', ':', ';', '=', '@', '[', '\\', ']', '^', '|'}

func parseIpv4Number(s: string): (bool, float) =
  if s == "": return (false, 0)
  var input = s
  var radix = 10
  if input.len >= 2 and input[0] == '0' and input[1] in {'x', 'X'}:
    input = input[2 .. ^1]
    radix = 16
  elif input.len >= 2 and input[0] == '0':
    input = input[1 .. ^1]
    radix = 8
  if input == "": return (true, 0)
  var v = 0.0
  for c in input:
    let d = hexValue(c)
    if d < 0 or d >= radix: return (false, 0)
    v = v * float(radix) + float(d)
  (true, v)

func endsInNumber(host: string): bool =
  var parts = host.split('.')
  if parts.len > 0 and parts[^1] == "":
    if parts.len == 1: return false
    parts.setLen(parts.len - 1)
  let last = parts[^1]
  if last != "" and allCharsInSet(last, {'0'..'9'}): return true
  parseIpv4Number(last)[0]

func ipv4(host: string): (bool, string) =
  var parts = host.split('.')
  if parts[^1] == "" and parts.len > 1: parts.setLen(parts.len - 1)
  if parts.len > 4: return (false, "")
  var numbers: seq[float]
  for p in parts:
    let (ok, n) = parseIpv4Number(p)
    if not ok: return (false, "")
    numbers.add n
  for i in 0 ..< numbers.len - 1:
    if numbers[i] > 255: return (false, "")
  if numbers[^1] >= pow(256.0, float(5 - numbers.len)): return (false, "")
  var v = numbers[^1]
  for i in 0 ..< numbers.len - 1: v += numbers[i] * pow(256.0, float(3 - i))
  var output: seq[string]
  var n = int(v)
  for i in 0 ..< 4:
    output.insert($(n mod 256), 0)
    n = n div 256
  (true, output.join("."))

proc parseHttpUrl(input: string): Option[string] =
  ## new URL(input).toString() for an input whose scheme is http or https (lower case already).
  let colon = input.find(':')
  let scheme = input[0 ..< colon].toLowerAscii
  var rest = input[colon + 1 .. ^1]
  # Tabs and newlines are removed; the special scheme ignores any slashes before the authority.
  rest = rest.multiReplace(("\t", ""), ("\n", ""), ("\r", ""))
  var i = 0
  while i < rest.len and rest[i] in {'/', '\\'}: inc i
  rest = rest[i .. ^1]
  var authEnd = 0
  while authEnd < rest.len and rest[authEnd] notin {'/', '\\', '?', '#'}: inc authEnd
  var authority = rest[0 ..< authEnd]
  var tail = rest[authEnd .. ^1]
  var userinfo = ""
  let at = authority.rfind('@')
  if at >= 0:
    let info = authority[0 ..< at]
    authority = authority[at + 1 .. ^1]
    let c = info.find(':')
    let user = if c >= 0: info[0 ..< c] else: info
    let pass = if c >= 0: info[c + 1 .. ^1] else: ""
    userinfo = percentEncode(user, userinfoKeep)
    if pass != "": userinfo.add ":" & percentEncode(pass, userinfoKeep)
  var host = authority
  var port = ""
  if not host.startsWith("["):
    let c = host.rfind(':')
    if c >= 0:
      port = host[c + 1 .. ^1]
      host = host[0 ..< c]
  if host == "": return none(string)
  if port != "":
    if not allCharsInSet(port, {'0'..'9'}): return none(string)
    let p = parseInt(port)
    if p > 65535: return none(string)
    port = $p
    if (scheme == "http" and p == 80) or (scheme == "https" and p == 443): port = ""
  if not host.startsWith("["):
    host = decode(host).toLowerAscii
    for c in host:
      if c in {'\0', '\t', '\n', '\r', ' ', '#', '%', '/', ':', '<', '>', '?', '@', '[', '\\', ']', '^', '|'} or
         ord(c) < 0x20 or ord(c) == 0x7f:
        return none(string)
    if endsInNumber(host):
      let (ok, v4) = ipv4(host)
      if not ok: return none(string)
      host = v4
  # Path, query, fragment.
  var path = tail
  var query = ""
  var hasQuery = false
  var fragment = ""
  var hasFragment = false
  let hash = path.find('#')
  if hash >= 0:
    fragment = path[hash + 1 .. ^1]
    hasFragment = true
    path = path[0 ..< hash]
  let q = path.find('?')
  if q >= 0:
    query = path[q + 1 .. ^1]
    hasQuery = true
    path = path[0 ..< q]
  path = path.replace('\\', '/')
  var segments: seq[string]
  if path.len > 0:
    let parts = path[1 .. ^1].split('/')
    for k, part in parts:
      let lower = part.toLowerAscii
      let single = lower == "." or lower == "%2e"
      let double = lower in ["..", ".%2e", "%2e.", "%2e%2e"]
      if double:
        if segments.len > 0: segments.setLen(segments.len - 1)
        if k == parts.len - 1: segments.add ""
      elif single:
        if k == parts.len - 1: segments.add ""
      else:
        segments.add percentEncode(part, pathKeep)
  var serialized = scheme & "://"
  if userinfo != "": serialized.add userinfo & "@"
  serialized.add host
  if port != "": serialized.add ":" & port
  serialized.add "/" & segments.join("/")
  if hasQuery: serialized.add "?" & percentEncode(query, queryKeep)
  if hasFragment: serialized.add "#" & percentEncode(fragment, fragmentKeep)
  some(serialized)

proc sanitizeUrl*(url: string): string =
  ## Refuses what @braintree/sanitize-url refuses, the check Mermaid applies to click targets.
  ## Unlike it, keeps percent escapes, so `file=A%26B` still names the note `A&B`.
  if url == "": return BLANK
  let decodedOpt = unwrap(url, true)
  let keptOpt = unwrap(url, false)
  if decodedOpt.isNone or keptOpt.isNone or decodedOpt.get == "" or keptOpt.get == "": return BLANK
  let decoded = decodedOpt.get
  let kept = keptOpt.get
  if decoded[0] == '.' or decoded[0] == '/': return kept

  let (hasScheme, scheme) = schemeMatch(jsTrimStart(decoded))
  if not hasScheme: return kept

  let protocol = jsTrim(scheme.toLowerAscii)
  if invalidProtocol(protocol): return BLANK

  let normalized = jsTrimStart(kept).replace('\\', '/')
  if protocol == "mailto:" or "://" in protocol: return normalized

  if protocol == "http:" or protocol == "https:":
    let parsed = parseHttpUrl(normalized)
    if parsed.isNone: return BLANK
    return parsed.get
  normalized

proc safeUrl*(url: string): string =
  ## A URL as written in a diagram: entity codes are read first, so they cannot hide a scheme.
  sanitizeUrl(decodeEntities(url))

const
  LINK_SCHEMES = @["http", "https", "mailto", "tel"]
  IMAGE_SCHEMES = @["http", "https"]

proc allowed(url: string, schemes: seq[string]): bool =
  ## Stricter than Mermaid, which lets any scheme but three through: a diagram in a shared note
  ## could otherwise open a local file, a network share, or another application.
  # /^[\\/]{2}/
  if url.len >= 2 and url[0] in {'\\', '/'} and url[1] in {'\\', '/'}: return false
  # /^([a-z][a-z0-9+.-]*):/i
  if url.len == 0 or url[0] notin {'a'..'z', 'A'..'Z'}: return true
  var j = 1
  while j < url.len and url[j] in {'a'..'z', 'A'..'Z', '0'..'9', '+', '.', '-'}: inc j
  if j >= url.len or url[j] != ':': return true
  url[0 ..< j].toLowerAscii in schemes

proc allow(url: string, schemes: seq[string]): Option[string] =
  ## The decoded URL is checked too, for an app that decodes the href before opening it.
  let decoded = unwrap(url, true)
  if decoded.isSome and allowed(url, schemes) and allowed(decoded.get, schemes): some(url) else: none(string)

proc linkUrl*(url: string, options: RenderOptions): Option[string] =
  ## Both take a URL that sanitizeUrl has passed, and keep it only when it is relative or its
  ## scheme is one the host allows. One that is refused is left out of the drawing: written as
  ## `about:blank`, a link would still take the page it is in somewhere when clicked.
  if options.links == some(false): none(string) else: allow(url, options.linkSchemes.get(LINK_SCHEMES))

proc imageUrl*(url: string, options: RenderOptions): Option[string] =
  if options.images == some(false): none(string) else: allow(url, options.imageSchemes.get(IMAGE_SCHEMES))

proc internalLink*(name: string, options: RenderOptions): bool =
  ## The href keeps the original name, so sanitizing alone is not enough.
  let url = sanitizeUrl(name)
  if url == BLANK or linkUrl(url, options).isNone: return false
  # Match character removal by esc() and the browser.
  var seen = ""
  var i = 0
  while i < name.len:
    let (cp, size) = codePointAt(name, i)
    let bad = (cp == 0xFFFD and not name.continuesWith("�", i)) or
      (cp >= 0 and cp <= 8) or cp == 0x0b or cp == 0x0c or (cp >= 0x0e and cp <= 0x1f) or cp == 0x7f or
      cp == 0xfffe or cp == 0xffff
    if not bad and cp != 9 and cp != 10 and cp != 13: seen.add name[i ..< i + size]
    i += size
  var k = 0
  while k < seen.len and ord(seen[k]) <= 0x20: inc k
  linkUrl(seen[k .. ^1], options).isSome

proc relAttr*(options: RenderOptions): string =
  let rel = options.linkRel.get("noopener")
  if rel != "": " rel=\"" & esc(rel) & "\"" else: ""

proc linked*(body, url, id: string, links: var seq[LinkInfo], options: RenderOptions, attrs = ""): string =
  let href = linkUrl(url, options)
  if href.isNone: return body
  links.add LinkInfo(id: id, href: href.get, internal: false)
  "<a href=\"" & esc(href.get) & "\"" & attrs & relAttr(options) & ">" & body & "</a>"
