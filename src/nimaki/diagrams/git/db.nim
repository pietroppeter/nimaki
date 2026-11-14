## port-of: src/diagrams/git/db.ts
## port-status: draft
##
## Port notes: Pele's `GitDbParseProvider` (the calls Mermaid's parser makes on its database) is
## a set of closures in `buildGit`, called directly. A branch head that is `null` is "" (a commit
## id is never empty), and an optional number is a float with NO_TYPE for undefined.
import std/[algorithm, strutils, tables]
import ../../errors
import ../../js
import ../../preprocess
import ../../util/yaml
import parser
import ../../jsregex

const
  NORMAL* = 0
  REVERSE* = 1
  HIGHLIGHT* = 2
  MERGE* = 3
  CHERRY_PICK* = 4
  NO_TYPE* = -1   ## undefined, for customType

type
  GitDirection* = string ## 'LR' | 'TB' | 'BT'

  GitCommit* = ref object
    id*: string
    message*: string
    seq*: int
    kind*: int             ## Pele's `type`
    tags*: seq[string]
    parents*: seq[string]
    branch*: string
    customType*: int       ## NO_TYPE for undefined
    customId*: bool

  GitModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    direction*: GitDirection
    commits*: OrderedTable[string, GitCommit]
      ## Keyed by commit id, in the order the ids first appeared.
    branches*: OrderedTable[string, string]
      ## The id of each branch's latest commit, or "" while the branch has none.
    lanes*: seq[string]
      ## Branch names in drawing order: by `order`, then by creation.
    currentBranch*: string
    head*: GitCommit
    warnings*: seq[string]

proc fail(message: string) {.noreturn.} =
  raise newPeleError(message, "semantic", "gitGraph")

func typeCode(name: CommitTypeName): int =
  if name == "REVERSE": REVERSE elif name == "HIGHLIGHT": HIGHLIGHT else: NORMAL

func collapseIndents(text: string): string =
  text.replace(jsre"/\n\s+/g", "\n")

proc buildGit*(ast: GitGraphAst, config: Config, title: string): GitModel =
  let git = config["gitGraph"]
  let mainOpt = git["mainBranchName"]
  let mainName = if mainOpt != nil and mainOpt.kind == yString: mainOpt.s else: "main"
  let orderOpt = git["mainBranchOrder"]
  let mainOrder = if orderOpt != nil and orderOpt.kind == yNumber: orderOpt.n else: 0.0

  var commits = initOrderedTable[string, GitCommit]()
  var branches = initOrderedTable[string, string]()
  branches[mainName] = ""
  var orders = initOrderedTable[string, float]()
  orders[mainName] = mainOrder
  var warnings: seq[string]
  var head: GitCommit = nil
  var current = mainName
  var direction: GitDirection = "LR"
  var seq = 0

  # Mermaid appends seven random hex digits to the sequence number. These digits are derived
  # from the sequence number instead, so the same text always gives the same ids.
  proc nextId(): string =
    var salt = uint32(seq + 1)
    while true:
      let id = $seq & "-" & toHex(salt * 0x9e3779b1'u32, 8).toLowerAscii[0 ..< 7]
      if id notin commits: return id
      salt += 0x9e3779b1'u32

  proc add(commit: GitCommit) =
    head = commit
    commits[commit.id] = commit
    branches[current] = commit.id

  proc checkout(branch: string) =
    if branch notin branches:
      fail("Trying to checkout branch which is not yet created. (Help try using \"branch " & branch & "\")")
    current = branch
    let id = branches[branch]
    head = if id != "": commits.getOrDefault(id, nil) else: nil

  if ast.dir != "": direction = ast.dir
  for statement in ast.statements:
    case statement.kind
    of sCommit:
      let commit = GitCommit(
        id: (if statement.id != "": statement.id else: nextId()),
        message: statement.message,
        seq: seq,
        kind: (if statement.commitType != "": typeCode(statement.commitType) else: NORMAL),
        tags: statement.tags,
        parents: (if head == nil: @[] else: @[head.id]),
        branch: current,
        customType: NO_TYPE)
      inc seq
      if commit.id in commits: warnings.add "Commit ID " & commit.id & " already exists"
      add(commit)
    of sBranch:
      let name = statement.name
      if name in branches:
        fail("Trying to create an existing branch. (Help: Either use a new name if you want create a new branch or try using \"checkout " & name & "\")")
      branches[name] = if head != nil: head.id else: ""
      orders[name] = if statement.hasOrder: statement.order else: 0.0
      checkout(name)
    of sMerge:
      let other = statement.name
      let customId = statement.id
      let kind = if statement.commitType != "": typeCode(statement.commitType) else: NO_TYPE
      let currentHead = branches.getOrDefault(current, "")
      let otherHead = branches.getOrDefault(other, "")
      let currentCommit = if currentHead != "": commits.getOrDefault(currentHead, nil) else: nil
      let otherCommit = if otherHead != "": commits.getOrDefault(otherHead, nil) else: nil
      if currentCommit != nil and otherCommit != nil and currentCommit.branch == other:
        fail("Cannot merge branch '" & other & "' into itself.")
      if current == other: fail("Incorrect usage of \"merge\". Cannot merge a branch to itself")
      if currentCommit == nil: fail("Incorrect usage of \"merge\". Current branch (" & current & ")has no commits")
      if other notin branches: fail("Incorrect usage of \"merge\". Branch to be merged (" & other & ") does not exist")
      if otherCommit == nil: fail("Incorrect usage of \"merge\". Branch to be merged (" & other & ") has no commits")
      if currentCommit == otherCommit: fail("Incorrect usage of \"merge\". Both branches have same head")
      if customId != "" and customId in commits:
        fail("Incorrect usage of \"merge\". Commit with id:" & customId & " already exists, use different custom id")
      let commit = GitCommit(
        id: (if customId != "": customId else: nextId()),
        message: "merged branch " & other & " into " & current,
        seq: seq,
        parents: (if head == nil: @[] else: @[head.id, otherHead]),
        branch: current,
        kind: MERGE,
        customType: kind,
        customId: customId != "",
        tags: statement.tags)
      inc seq
      add(commit)
    of sCheckout:
      checkout(statement.name)
    of sCherryPicking:
      let sourceId = statement.id
      let parent = statement.parent
      let source = if sourceId != "": commits.getOrDefault(sourceId, nil) else: nil
      if source == nil: fail("Incorrect usage of \"cherryPick\". Source commit id should exist and provided")
      if parent != "" and parent notin source.parents:
        fail("Invalid operation: The specified parent commit is not an immediate parent of the cherry-picked commit.")
      if source.kind == MERGE and parent == "":
        fail("Incorrect usage of cherry-pick: If the source commit is a merge commit, an immediate parent commit must be specified.")
      if source.branch == current: fail("Incorrect usage of \"cherryPick\". Source commit is already on current branch")
      let currentHead = branches.getOrDefault(current, "")
      if currentHead == "" or currentHead notin commits:
        fail("Incorrect usage of \"cherry-pick\". Current branch (" & current & ")has no commits")
      var tags: seq[string]
      if statement.tags.len > 0:
        for t in statement.tags:
          if t != "": tags.add t
      else:
        tags = @["cherry-pick:" & source.id & (if source.kind == MERGE: "|parent:" & parent else: "")]
      let commit = GitCommit(
        id: nextId(),
        message: "cherry-picked " & source.message & " into " & current,
        seq: seq,
        parents: (if head == nil: @[] else: @[head.id, source.id]),
        branch: current,
        kind: CHERRY_PICK,
        customType: NO_TYPE,
        tags: tags)
      inc seq
      add(commit)

  # A branch made without an order sorts by creation among those of order zero, as in Mermaid.
  var ordered: seq[(string, float)]
  for name, order in orders: ordered.add (name, order)
  ordered.sort(proc (a, b: (string, float)): int =
    let d = a[1] - b[1]
    if d < 0: -1 elif d > 0: 1 else: 0)
  var lanes: seq[string]
  for (name, _) in ordered: lanes.add name

  GitModel(
    title: (if ast.title != "": ast.title else: title),
    accTitle: (if ast.accTitle != "": jsTrimStart(ast.accTitle) else: ""),
    accDescr: (if ast.accDescr != "": collapseIndents(ast.accDescr) else: ""),
    direction: direction,
    commits: commits,
    branches: branches,
    lanes: lanes,
    currentBranch: current,
    head: head,
    warnings: warnings)
