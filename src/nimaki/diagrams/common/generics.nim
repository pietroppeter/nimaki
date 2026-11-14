## port-of: src/diagrams/common/generics.ts
## port-status: conformant
import std/strutils
import ../../jsregex

func tildes(text: string): int = text.count('~')

func pairTildes(text: string): string =
  ## Pairs tildes from the outside in: the first with the last, the second with the one before it.
  let count = tildes(text)
  if count <= 1: return text
  let lead = count mod 2 != 0 and text.startsWith('~')
  result = text
  var at: seq[int]
  for i in (if lead: 1 else: 0) ..< result.len:
    if result[i] == '~': at.add i
  var lo = 0
  var hi = at.len - 1
  while lo < hi:
    result[at[lo]] = '<'
    result[at[hi]] = '>'
    inc lo
    dec hi

func parseGenericTypes*(input: string): string =
  ## Turns `List~int~` into `List<int>`, with the quirks of Mermaid's parseGenericTypes around commas.
  if '~' notin input: return input
  let sets = input.split(jsre"/(,)/")
  var output: seq[string]
  var i = 0
  while i < sets.len:
    var s = sets[i]
    if s == "," and i > 0 and i + 1 < sets.len and tildes(sets[i - 1]) == 1 and tildes(sets[i + 1]) == 1:
      s = sets[i - 1] & "," & sets[i + 1]
      inc i
      discard output.pop()
    output.add pairTildes(s)
    inc i
  output.join("")
