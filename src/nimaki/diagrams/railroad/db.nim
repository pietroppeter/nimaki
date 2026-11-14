## port-of: src/diagrams/railroad/db.ts
## port-status: conformant
##
## Port notes: Pele's `RailroadDb` keeps a map from names to rules for `getRule`, which nothing
## in the drawing reads; here the model is the rule list alone.
import std/strutils except unescape
import ../../errors
import ../../js
import types, common, ir, ebnf, abnf, peg

func dropBreakSpaces(text: string): string =
  ## text.replace(/\n\s+/g, '\n')
  var i = 0
  while i < text.len:
    if text[i] == '\n':
      let j = spaces(text, i + 1)
      result.add '\n'
      i = j
      continue
    result.add text[i]
    inc i

proc notationOf*(source: string): (bool, Notation) =
  ## /^\s*railroad-(ebnf-|abnf-|peg-)?beta/i. Mermaid has a detector per keyword, each matching
  ## without regard to case.
  var i = spaces(source, 0)
  if not source.toLowerAscii.continuesWith("railroad-", i): return (false, "")
  i += 9
  let rest = source.toLowerAscii
  for (infix, notation) in [("ebnf-", "ebnf"), ("abnf-", "abnf"), ("peg-", "peg")]:
    if rest.continuesWith(infix & "beta", i): return (true, notation)
  if rest.continuesWith("beta", i): (true, "railroad") else: (false, "")

proc grammar(source: string, notation: Notation): (Grammar, seq[RailroadRule]) =
  case notation
  of "ebnf":
    let ast = parseEbnf(source)
    (ast, ebnfRules(ast))
  of "abnf":
    let ast = parseAbnf(source)
    (ast, abnfRules(ast))
  of "peg":
    let ast = parsePeg(source)
    (ast, pegRules(ast))
  else:
    let ast = parseIr(source)
    (ast, irRules(ast))

proc populate*(db: RailroadModel, source: string, notation: Notation) =
  ## Parses the text in one notation and loads the result into the model, as Mermaid's four parsers do.
  let (ast, rules) = grammar(source, notation)
  db.notation = notation
  if ast.accDescr != "": db.accDescr = dropBreakSpaces(ast.accDescr)
  if ast.accTitle != "": db.accTitle = jsTrimStart(ast.accTitle)
  if ast.title != "": db.title = ast.title
  for rule in rules: db.rules.add rule

proc parseRailroad*(source: string, title: string): RailroadModel =
  let (found, notation) = notationOf(source)
  if not found: raise newPeleError("No railroad diagram keyword found.", "syntax", "railroad")
  result = RailroadModel(notation: "railroad")
  if title != "": result.title = title
  populate(result, source, notation)
