## port-of: src/diagrams/treemap/format.ts
## port-status: conformant
import std/strutils
import ../../js

# The parts of d3-format's specifier that treemap values use: an optional `$`, `,` for thousands
# separators, a precision, and a type of `f`, `%`, `d`, `e` or none. Fill, alignment and width are
# read and ignored. Anything else falls back to the default, `,`.

type Spec = object
  sign, dollar, comma, precision, tilde, kind: string   ## the groups of RE_SPEC; "" for undefined
  hasPrecision: bool

func restOfSpec(s: string, at: int, m: var Spec): bool =
  ## The part of RE_SPEC after fill and alignment:
  ## ([-+( ])?(\$)?0?\d*(,)?(?:\.(\d+))?(~)?([a-zA-Z%])?$
  var i = at
  m = Spec()
  if i < s.len and s[i] in {'-', '+', '(', ' '}:
    m.sign = s[i .. i]
    inc i
  if i < s.len and s[i] == '$':
    m.dollar = "$"
    inc i
  while i < s.len and s[i] in Digits: inc i
  if i < s.len and s[i] == ',':
    m.comma = ","
    inc i
  if i + 1 < s.len and s[i] == '.' and s[i + 1] in Digits:
    var j = i + 1
    while j < s.len and s[j] in Digits: inc j
    m.precision = s[i + 1 ..< j]
    m.hasPrecision = true
    i = j
  if i < s.len and s[i] == '~':
    m.tilde = "~"
    inc i
  if i < s.len and s[i] in {'a'..'z', 'A'..'Z', '%'}:
    m.kind = s[i .. i]
    inc i
  i == s.len

func matchSpec(s: string, m: var Spec): bool =
  ## RE_SPEC: /^(?:.?[<>=^])?([-+( ])?(\$)?0?\d*(,)?(?:\.(\d+))?(~)?([a-zA-Z%])?$/, trying the
  ## fill and alignment in the order the regular expression does.
  const ALIGN = {'<', '>', '=', '^'}
  if s.len > 0:
    let (cp, size) = codePointAt(s, 0)
    let one = cp < 0x10000 and not (cp == 10 or cp == 13 or cp == 0x2028 or cp == 0x2029)
    if one and size < s.len and s[size] in ALIGN and restOfSpec(s, size + 1, m): return true
    if s[0] in ALIGN and restOfSpec(s, 1, m): return true
  restOfSpec(s, 0, m)

func group(digits: string): string =
  var i = digits.len
  while i > 0:
    let part = digits[max(0, i - 3) ..< i]
    result = part & (if result != "": "," & result else: "")
    i -= 3

func dropTrailingZeros(body: string): string =
  ## body.replace(/\.?0+$/, '')
  var j = body.len
  while j > 0 and body[j - 1] == '0': dec j
  if j == body.len: return body
  if j > 0 and body[j - 1] == '.': dec j
  body[0 ..< j]

proc formatter*(spec: string): proc (value: float): string =
  var m: Spec
  # Mermaid documents `$0,0` for a dollar amount with thousands separators.
  if not matchSpec(if spec == "$0,0": "$," else: spec, m): discard matchSpec(",", m)
  let plus = m.sign == "+"
  let comma = m.comma != ""
  let hasPrecision = m.hasPrecision
  let precision = if hasPrecision: int(jsMin(jsNumber(m.precision), 20)) else: 0
  let kind = m.kind
  let tilde = m.tilde != ""
  let dollar = m.dollar

  result = proc (value: float): string =
    let abs = abs(value)
    var body: string
    var suffix = ""
    if kind == "f": body = toFixed(abs, if hasPrecision: precision else: 6)
    elif kind == "%":
      body = toFixed(abs * 100, if hasPrecision: precision else: 6)
      suffix = "%"
    elif kind == "d": body = toFixed(jsRound(abs), 0)
    elif kind == "e": body = toExponential(abs, if hasPrecision: precision else: 6)
    else: body = jsString(jsToNumber(toPrecision(abs, max(1, if hasPrecision: precision else: 12))))

    if tilde and '.' in body and 'e' notin body: body = dropTrailingZeros(body)
    if comma and 'e' notin body:
      let dot = body.find('.')
      body = if dot == -1: group(body) else: group(body[0 ..< dot]) & body[dot .. ^1]
    (if value < 0: "-" elif plus: "+" else: "") & dollar & body & suffix
