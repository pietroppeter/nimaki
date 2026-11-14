## port-of: src/diagrams/ishikawa/db.ts
## port-status: conformant
import std/options
import types

type
  Entry = object
    level: int
    node: IshikawaNode

  IshikawaDb* = ref object of IshikawaModel
    stack: seq[Entry]
      ## The line of ancestors of the last node, each with its level.
    baseLevel: Option[int]

proc addNode*(db: IshikawaDb, rawLevel: int, text: string) =
  ## The first line is the effect. Every later line is a cause, nested by its indentation relative
  ## to the first cause, so the effect itself may be indented more than the causes.
  let node = IshikawaNode(text: text)
  if db.root == nil:
    db.root = node
    db.stack = @[Entry(level: 0, node: node)]
    return
  if db.baseLevel.isNone: db.baseLevel = some(rawLevel)
  let level = max(rawLevel - db.baseLevel.get + 1, 1)
  while db.stack.len > 1 and db.stack[^1].level >= level: discard db.stack.pop()
  db.stack[^1].node.children.add node
  db.stack.add Entry(level: level, node: node)
