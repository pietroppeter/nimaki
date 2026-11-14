## port-of: src/diagrams/git/parser.ts
## port-status: draft
import ../common/tokens
import ../../js
import ../../jsregex

const
  # const enum T: the index of each token type in GIT_TOKENS
  T_cherryPick = 0
  T_gitGraphColon = 1
  T_highlight = 2
  T_gitGraph = 3
  T_checkout = 4
  T_reverse = 5
  T_parent = 6
  T_commit = 7
  T_normal = 8
  T_branch = 9
  T_order = 10
  T_switch = 11
  T_type = 12
  T_merge = 13
  T_msg = 14
  T_tag = 15
  T_id = 16
  T_lr = 17
  T_tb = 18
  T_bt = 19
  T_colon = 20
  T_accDescr = 21
  T_accTitle = 22
  T_title = 23
  T_int = 24
  T_string = 25
  T_newline = 26
  T_reference = 31

func isRefChar(c: char): bool = isWordChar(c) or c in {'-', '.', '/'}

func matchReference(s: string, p: int): int =
  ## /\w([-\./\w]*[-\w])?/y
  if p >= s.len or not isWordChar(s[p]): return -1
  var e = p + 1
  while e < s.len and isRefChar(s[e]): inc e
  while e > p + 1 and s[e - 1] in {'.', '/'}: dec e
  e

func matchInt(s: string, p: int): int =
  ## /0|[1-9][0-9]*(?!\.)/y: a 0 alone, or a run of digits not followed by a dot (the run
  ## gives back its last digit when a dot follows).
  if p >= s.len: return -1
  if s[p] == '0': return p + 1
  if s[p] notin {'1'..'9'}: return -1
  var e = p + 1
  while e < s.len and s[e] in {'0'..'9'}: inc e
  if e < s.len and s[e] == '.':
    if e - 1 > p: e - 1 else: -1
  else: e

let REFERENCE = TokenType(name: "REFERENCE", matcher: matchReference)
let NAME = @[REFERENCE]

proc word(name: string): TokenType =
  ## A keyword that is the start of a longer name is part of that name: `commits` is a branch.
  TokenType(name: name, literal: name, longer: NAME)
proc mark(text: string): TokenType = TokenType(name: text, literal: text)

proc copyOf(t: TokenType): TokenType =
  result = TokenType()
  result[] = t[]

let GIT_TOKENS*: seq[TokenType] = block:
  let gitGraph = copyOf(keyword("gitGraph"))
  gitGraph.longer = NAME
  # Without a closing brace the block form scans to the end of the text, and a brace is not a
  # token on its own, so the first failure is final.
  let accDescr = copyOf(ACC_DESCR)
  accDescr.opener = jsre"/[\t ]*accDescr\s*{/y"
  @[
    word("cherry-pick"),
    mark("gitGraph:"),
    word("HIGHLIGHT"),
    gitGraph,
    word("checkout"),
    word("REVERSE"),
    mark("parent:"),
    word("commit"),
    word("NORMAL"),
    word("branch"),
    mark("order:"),
    word("switch"),
    mark("type:"),
    word("merge"),
    mark("msg:"),
    mark("tag:"),
    mark("id:"),
    word("LR"),
    word("TB"),
    word("BT"),
    mark(":"),
    accDescr,
    ACC_TITLE,
    titleBefore(r"[-./\w]*[-\w]"),
    TokenType(name: "INT", matcher: matchInt, first: "0123456789", hasFirst: true),
    STRING,
    NEWLINE,
    WHITESPACE,
    YAML,
    DIRECTIVE,
    SINGLE_LINE_COMMENT,
    REFERENCE,
  ]

type
  CommitTypeName* = string ## 'NORMAL' | 'REVERSE' | 'HIGHLIGHT', "" for undefined

  StatementKind* = enum
    sCommit, sBranch, sMerge, sCheckout, sCherryPicking

  StatementAst* = object
    kind*: StatementKind
    id*: string            ## Commit, Merge, CherryPicking
    hasId*: bool
    message*: string       ## Commit
    hasMessage*: bool
    tags*: seq[string]
    commitType*: CommitTypeName
    name*: string          ## Branch; the branch of Merge and Checkout
    order*: float          ## Branch
    hasOrder*: bool
    parent*: string        ## CherryPicking
    hasParent*: bool

  GitGraphAst* = object
    dir*: string           ## "" for undefined
    title*, accTitle*, accDescr*: string   ## "" for undefined
    hasTitle*, hasAccTitle*, hasAccDescr*: bool
    statements*: seq[StatementAst]

proc parseGit*(src: string): GitGraphAst =
  let r = newReader(tokenize(src, GIT_TOKENS, "gitGraph"), GIT_TOKENS, "gitGraph")
  var ast = GitGraphAst()

  proc endOfLine() =
    if r.kind == -1: return
    if r.kind != T_newline: r.fail("a line break or the end of input")
    while r.kind == T_newline: inc r.i
  proc name(): string =
    if r.kind == T_reference: return r.take()
    if r.kind == T_string: return stringValue(r.take())
    r.fail("a branch name")
  proc str(): string = stringValue(r.expect(T_string))
  proc commitType(): CommitTypeName =
    if r.kind != T_normal and r.kind != T_reverse and r.kind != T_highlight:
      r.fail("NORMAL, REVERSE, or HIGHLIGHT")
    r.take()

  while r.kind == T_newline: inc r.i
  if not r.accept(T_gitGraphColon):
    discard r.expect(T_gitGraph)
    let next = if r.i + 1 < r.kinds.len: r.kinds[r.i + 1] else: -2
    if (r.kind == T_lr or r.kind == T_tb or r.kind == T_bt) and next == T_colon:
      ast.dir = r.take()
      inc r.i
    else:
      discard r.accept(T_colon)

  while r.kind != -1:
    case r.kind
    of T_newline:
      inc r.i
    of T_accDescr:
      ast.accDescr = accDescrValue(r.take())
      ast.hasAccDescr = true
      endOfLine()
    of T_accTitle:
      ast.accTitle = accTitleValue(r.take())
      ast.hasAccTitle = true
      endOfLine()
    of T_title:
      ast.title = titleValue(r.take())
      ast.hasTitle = true
      endOfLine()
    of T_commit:
      inc r.i
      var node = StatementAst(kind: sCommit)
      while true:
        if r.accept(T_id):
          node.id = str()
          node.hasId = true
        elif r.accept(T_tag): node.tags.add str()
        elif r.accept(T_type): node.commitType = commitType()
        elif r.accept(T_msg) or r.kinds[r.i] == T_string:
          node.message = str()
          node.hasMessage = true
        else: break
      endOfLine()
      ast.statements.add node
    of T_branch:
      inc r.i
      var node = StatementAst(kind: sBranch, name: name())
      if r.accept(T_order):
        node.order = jsNumber(r.expect(T_int))
        node.hasOrder = true
      endOfLine()
      ast.statements.add node
    of T_merge:
      inc r.i
      var node = StatementAst(kind: sMerge, name: name())
      while true:
        if r.accept(T_id):
          node.id = str()
          node.hasId = true
        elif r.accept(T_tag): node.tags.add str()
        elif r.accept(T_type): node.commitType = commitType()
        else: break
      endOfLine()
      ast.statements.add node
    of T_checkout, T_switch:
      inc r.i
      let node = StatementAst(kind: sCheckout, name: name())
      endOfLine()
      ast.statements.add node
    of T_cherryPick:
      inc r.i
      var node = StatementAst(kind: sCherryPicking)
      while true:
        if r.accept(T_id):
          node.id = str()
          node.hasId = true
        elif r.accept(T_tag): node.tags.add str()
        elif r.accept(T_parent):
          node.parent = str()
          node.hasParent = true
        else: break
      endOfLine()
      ast.statements.add node
    else:
      r.fail("a statement, a title, or a line break")
  ast
