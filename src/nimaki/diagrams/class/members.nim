## port-of: src/diagrams/class/members.ts
## port-status: draft
import std/strutils
import ../../js
import ../../util/chars
import ../common/generics

type
  Visibility* = string ## '#' | '+' | '~' | '-' | ''

  ClassMember* = ref object
    id*: string
    memberType*: string  ## 'method' | 'attribute'
    visibility*: Visibility
    classifier*: string
    parameters*: string
    returnType*: string

func isVisibility(ch: string): bool = ch == "#" or ch == "+" or ch == "~" or ch == "-"

func cu(s: string, i: int): int =
  ## charCodeAt, for the characters that matter here: an ASCII byte is itself; any other
  ## character reads as its code point, which is never a line end, a parenthesis or a space
  ## when it is past U+FFFF (JavaScript reads its first surrogate).
  if i < 0 or i >= s.len: return -1
  if ord(s[i]) < 0x80: return ord(s[i])
  let cp = codePointAt(s, i).rune
  if cp >= 0x10000: 0xD800 else: cp

proc parseMethod(m: ClassMember, input: string): bool =
  ## The same split as Mermaid's /([#+~-])?(.+)\((.*)\)([\s$*])?(.*)([$*])?/, found in one pass:
  ## the first line with an opening parenthesis after its first character and a closing one later.
  let n = input.len
  var start = 0
  while start < n:
    var stop = start
    while stop < n and not isLineEnd(cu(input, stop)): inc stop
    var close = stop - 1
    while close > start and input[close] != ')': dec close
    var open = close - 1
    while open > start and input[open] != '(': dec open
    if open > start:
      let first = $input[start]
      let visible = isVisibility(first) and open > start + 1
      if visible: m.visibility = first
      m.id = input[(if visible: start + 1 else: start) ..< open]
      m.parameters = jsTrim(input[open + 1 ..< close])
      var rest = close + 1
      var classifier = ""
      if rest < n:
        let c = cu(input, rest)
        if c == ord('$') or c == ord('*') or isSpace(c):
          classifier = if isSpace(c): "" else: $input[rest]
          rest += (if c < 0x80: 1 else: codePointAt(input, rest).size)
      var e = rest
      while e < n and not isLineEnd(cu(input, e)): inc e
      m.returnType = jsTrim(input[rest ..< e])
      if classifier == "":
        if m.returnType.len > 0 and m.returnType[^1] in {'$', '*'}:
          classifier = $m.returnType[^1]
          m.returnType = m.returnType[0 ..< ^1]
      m.classifier = classifier
      return true
    start = stop + 1
  m.memberType = "attribute"
  false

proc parseAttribute(m: ClassMember, input: string) =
  if input.len > 0 and isVisibility($input[0]): m.visibility = $input[0]
  if input.len > 0 and input[^1] in {'$', '*'}: m.classifier = $input[^1]
  let a = if m.visibility == "": 0 else: 1
  let b = if m.classifier == "": input.len else: input.len - 1
  # substring swaps its ends when the first is past the second
  m.id = input[min(a, b) ..< max(a, b)]

proc newClassMember*(input: string, memberType: string): ClassMember =
  result = ClassMember(memberType: memberType)
  # Mermaid throws a TypeError for a method with no opening parenthesis, such as `run)`.
  # It is kept here as an attribute, so it is shown as written.
  if memberType != "method" or not result.parseMethod(input): result.parseAttribute(input)
  result.id = if result.id.startsWith(' '): " " & jsTrim(result.id) else: jsTrim(result.id)

proc parseClassifier*(m: ClassMember): string =
  if m.classifier == "*": "font-style:italic;"
  elif m.classifier == "$": "text-decoration:underline;"
  else: ""

proc getDisplayDetails*(m: ClassMember): tuple[displayText, cssStyle: string] =
  var displayText = m.visibility & parseGenericTypes(m.id)
  if m.memberType == "method":
    displayText.add "(" & parseGenericTypes(jsTrim(m.parameters)) & ")"
    if m.returnType != "": displayText.add " : " & parseGenericTypes(m.returnType)
  (jsTrim(displayText), m.parseClassifier())
