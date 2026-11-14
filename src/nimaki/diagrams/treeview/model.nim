## port-of: src/diagrams/treeview/model.ts
## port-status: draft
import std/[strutils, tables]
import ../../errors
import ../../js
import box_drawing, parser
import ../../jsregex

type
  NodeType* = string   ## "file" | "directory"

  TreeNode* = ref object
    id*: int
    level*: int
    name*: string
    nodeType*: NodeType
    icon*: string
      ## An icon name as written (`pack:name`, `file`, `folder`), or `none` to hide the icon;
      ## "" for undefined.
    cssClass*: string      ## "" for undefined
    description*: string   ## "" for undefined
    children*: seq[TreeNode]

  TreeViewModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    root*: TreeNode
      ## A directory named `/` at level -1 that holds the top-level entries.
    count*: int

  TreeViewDb* = ref object
    ## Mermaid's treeView database: nodes arrive in source order with their indentation.
    count*: int
    root*: TreeNode
    stack: seq[TreeNode]

proc newTreeViewDb*(): TreeViewDb =
  let root = TreeNode(id: 0, level: -1, name: "/", nodeType: "directory")
  TreeViewDb(count: 1, root: root, stack: @[root])

proc addNode*(db: TreeViewDb, level: int, name: string, nodeType: NodeType,
              cssClass, icon, description: string) =
  while level <= db.stack[^1].level: discard db.stack.pop()
  let node = TreeNode(id: db.count, level: level, name: name, nodeType: nodeType, icon: icon,
                      cssClass: cssClass, description: description)
  inc db.count
  db.stack[^1].children.add node
  db.stack.add node

proc populate*(ast: TreeViewAst, db: TreeViewDb) =
  for node in ast.nodes:
    let level = node.indent
    var name = node.name
    let isDirectory = name.endsWith('/')
    if isDirectory: name = name[0 ..< name.len - 1]
    db.addNode(
      level,
      name,
      if isDirectory: "directory" else: "file",
      node.classAnnotation,
      if node.hasIconAnnotation: (if node.iconAnnotation != "": node.iconAnnotation else: "none") else: "",
      node.descAnnotation)

func replaceFirst(s, sub, by: string): string =
  ## s.replace(sub, () => by): the first occurrence only.
  let at = s.find(sub)
  if at < 0: s else: s[0 ..< at] & by & s[at + sub.len .. ^1]

proc readTreeView*(source: string): TreeViewAst =
  ## Reads the source to a syntax tree, accepting box-drawing input. Errors name lines of the
  ## original text.
  let pre = preprocessBoxDrawing(source)
  try:
    result = parseTreeView(pre.text)
  except PeleError as error:
    # The parser already located errors in unchanged text.
    if pre.text == source: raise
    if error.line notin pre.lineMap: raise
    let line = pre.lineMap[error.line]
    # Columns count UTF-16 code units, as JavaScript's indices do.
    let at = if error.column > 0:
               (if error.line in pre.columns: pre.columns[error.line](error.column - 1)
                else: error.column - 1)
             else: 0
    let first = lineStart(source, line)
    let written = locate(source, unitOffset(source, first, at))
    let message = error.msg
    let head = if '\n' in message: message.find('\n') else: message.len
    let rest = message[head .. ^1]
    let remapped = remapErrorLines(message[0 ..< head], {error.line: written.line}.toTable) &
                   (if error.snippet != "": rest.replaceFirst(error.snippet, written.snippet) else: rest)
    raise newPeleError(remapped, error.code, ErrorInfo(
      diagramType: error.diagramType,
      line: written.line,
      column: if error.column > 0: written.column else: 0,
      snippet: if error.snippet != "": written.snippet else: ""))

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc buildTreeView*(ast: TreeViewAst, title: string): TreeViewModel =
  let db = newTreeViewDb()
  populate(ast, db)
  TreeViewModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": jsTrimStart(ast.accTitle) else: "",   # replace(/^\s+/g, '')
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "",
    root: db.root,
    count: db.count)
