## port-of: src/diagrams/railroad/types.ts
## port-status: conformant
##
## Port notes: the union of node shapes is one object with a kind. A sequence's `elements`, a
## choice's `alternatives` and the `element` of an optional or a repetition are all `kids`, in
## the order Pele's `parts` lists them.

type
  NodeKind* = enum
    nkTerminal, nkNonterminal, nkSpecial, nkSequence, nkChoice, nkOptional, nkRepetition

  RailroadNode* = ref object
    kind*: NodeKind
    text*: string     ## a terminal's value, a non-terminal's name, a special's text
    kids*: seq[RailroadNode]
    min*: float
    max*: float       ## Inf when the count has no upper bound

  RailroadRule* = object
    name*: string
    definition*: RailroadNode

  Notation* = string  ## 'railroad' | 'ebnf' | 'abnf' | 'peg'

  RailroadModel* = ref object of RootObj
    notation*: Notation
    title*, accTitle*, accDescr*: string   ## "" for undefined
    rules*: seq[RailroadRule]
      ## Every rule in source order. A name defined twice appears twice.
