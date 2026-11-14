## port-of: src/diagrams/sequence/db.ts
## port-status: draft
##
## `JSON.parse` of the actor menus is `jsonParse` of `js.nim`, which is as strict as JavaScript's
## (`std/json`'s `parseJson` also reads comments and trailing commas). Values are `JsonNode`.
import std/[options, strutils, tables, json]
from std/unicode import runes, `$`
import ../../errors
import ../../js
import ../../util/yaml
import colors, types
import ../../jsregex

type
  SeqDbOptions* = object
    wrap*: Option[bool]
      ## The top-level `wrap` setting, which the `%%{wrap}%%` directive also sets.
    sequenceWrap*: Option[bool]
      ## `sequence.wrap`.

  SeqDb* = ref object of RootObj
    actors*: OrderedTable[string, SeqActor]
    createdActors*: Table[string, int]
    destroyedActors*: Table[string, int]
    boxes*: seq[SeqBox]
    messages*: seq[SeqMessage]
    notes*: seq[SeqNote]
    title*: string                 ## "" for undefined
    accTitle*: string
    accDescr*: string
    prevActor: string
    currentBox: SeqBox
    lastCreated: string
    lastDestroyed: string
    wrapEnabled: Option[bool]
    sequenceWrap: bool
    active: Table[string, int]

const RE_WRAP = jsre"/^:?wrap:/"
const RE_NOWRAP = jsre"/^:?nowrap:/"
const RE_WRAP_PREFIX = jsre"/^:?(?:no)?wrap:/"
const RE_BOX_FUNCTION = jsre"/^(?:rgba?|hsla?)\s*\(/"
const RE_LINE_TERMINATOR = jsre"/[\r\u2028\u2029]/"
const RE_WORD = jsre"/^\w*/"

proc fail(message: string) {.noreturn.} =
  raise newPeleError(message, "semantic", "sequence")

proc extractWrap(raw: string): SeqText =
  let text = jsTrim(raw)
  let wrap = if RE_WRAP.test(text): some(true) elif RE_NOWRAP.test(text): some(false) else: none(bool)
  SeqText(text: jsTrim(if wrap.isNone: text else: text.replace(RE_WRAP_PREFIX, "")), wrap: wrap)

# Splits a box line into a leading color and the rest, as Mermaid's
# /^((?:rgba?|hsla?)\s*\(.*\)|\w*)(.*)$/ does. `.` stops at a line terminator, so a line that
# holds one outside the gap before the parenthesis does not match at all.
proc splitBox(str: string): Option[(string, string)] =
  let fn = RE_BOX_FUNCTION.exec(str)
  if fn.found:
    let close = str.rfind(')')
    if close >= fn.stop:
      if RE_LINE_TERMINATOR.test(str[fn.stop .. ^1]): return none((string, string))
      return some((str[0 .. close], str[close + 1 .. ^1]))
  if RE_LINE_TERMINATOR.test(str): return none((string, string))
  let word = RE_WORD.exec(str)[0]
  some((word, str[word.len .. ^1]))

proc newSeqDb*(options = SeqDbOptions()): SeqDb =
  SeqDb(wrapEnabled: options.wrap, sequenceWrap: options.sequenceWrap.get(false))

proc autoWrap*(db: SeqDb): bool = db.wrapEnabled.get(db.sequenceWrap)

proc setAccTitle*(db: SeqDb, text: string) =
  db.accTitle = jsTrimStart(text)

proc setAccDescription*(db: SeqDb, text: string) =
  db.accDescr = text.replace(jsre"/\n\s+/g", "\n")

proc setDiagramTitle*(db: SeqDb, text: string) =
  db.title = text

proc parseMessage*(db: SeqDb, str: string): SeqText = extractWrap(str)

proc parseBoxData*(db: SeqDb, str: string): SeqBoxData =
  let match = splitBox(str)
  var color = if match.isSome and match.get[0] != "": jsTrim(match.get[0]) else: "transparent"
  var title = if match.isSome and match.get[1] != "": some(jsTrim(match.get[1])) else: none(string)
  if not isCssColor(color):
    color = "transparent"
    title = some(jsTrim(str))
  if title.isNone: return SeqBoxData(text: none(string), color: color, wrap: none(bool))
  let parsed = extractWrap(title.get)
  SeqBoxData(text: (if parsed.text != "": some(parsed.text) else: none(string)), color: color,
             wrap: parsed.wrap)

proc addBox*(db: SeqDb, data: SeqBoxData) =
  db.currentBox = SeqBox(name: data.text, wrap: data.wrap.get(db.autoWrap()), fill: data.color)
  db.boxes.add db.currentBox

func boxName(box: SeqBox): string =
  if box.name.isSome: box.name.get else: "undefined"

proc addActor*(db: SeqDb, id, name: string, description0: Option[SeqText], kind0: Option[string],
               metadata: Option[string]) =
  var description = description0
  var kind = kind0
  var assignedBox = db.currentBox
  var doc: YamlValue = nil
  if metadata.isSome:
    let meta = metadata.get
    var parsed: YamlValue
    try:
      parsed = parseYaml(if '\n' in meta: meta & "\n" else: "{\n" & meta & "\n}")
    except YamlError as error:
      raise newPeleError("Config of participant \"" & id & "\" is not valid YAML. " & error.msg, "syntax",
                         "sequence")
    if isRecord(parsed): doc = parsed
  let docType = doc[ "type"]
  let docAlias = doc["alias"]
  if docType != nil and docType.kind != yNull: kind = some(jsStr(docType))
  if truthy(docAlias) and (description.isNone or description.get.text == name):
    description = some(SeqText(text: jsStr(docAlias),
                               wrap: (if description.isSome: description.get.wrap else: none(bool))))

  let old = db.actors.getOrDefault(id, nil)
  if old != nil:
    if db.currentBox != nil and old.box != nil and db.currentBox != old.box:
      fail("A same participant should only be defined in one Box: " & old.name & " can't be in '" &
           boxName(old.box) & "' and in '" & boxName(db.currentBox) & "' at the same time.")
    assignedBox = if old.box != nil: old.box else: db.currentBox
    old.box = assignedBox
    if name == old.name and description.isNone: return
  # A participant that is only mentioned in a message has no kind and takes its name as its label.
  if description.isNone or kind.isNone: description = some(SeqText(text: name))

  db.actors[id] = SeqActor(
    box: assignedBox,
    name: name,
    description: description.get.text,
    wrap: description.get.wrap.get(db.autoWrap()),
    prevActor: db.prevActor,
    kind: kind.get("participant"))
  if db.prevActor != "":
    let prev = db.actors.getOrDefault(db.prevActor, nil)
    if prev != nil: prev.nextActor = id
  if db.currentBox != nil: db.currentBox.actorKeys.add id
  db.prevActor = id

proc addSignal*(db: SeqDb, start, to: Option[string], message: Option[SeqText], kind: int,
                activate = false, centralConnection = 0): bool {.discardable.} =
  # Mermaid recounts every earlier message here. A running count per participant says the same.
  if kind == LINETYPE_ACTIVE_END:
    let count = if start.isSome: db.active.getOrDefault(start.get, 0) else: 0
    if count < 1: fail("Trying to inactivate an inactive participant (" & start.get("undefined") & ")")
    db.active[start.get] = count - 1
  elif kind == LINETYPE_ACTIVE_START and start.isSome:
    db.active[start.get] = db.active.getOrDefault(start.get, 0) + 1
  db.messages.add SeqMessage(
    id: jsString(db.messages.len),
    start: start,
    to: to,
    message: (if message.isSome: message.get.text else: ""),
    wrap: (if message.isSome and message.get.wrap.isSome: message.get.wrap.get else: db.autoWrap()),
    kind: kind,
    activate: activate,
    placement: NO_TYPE,
    centralConnection: centralConnection)
  true

proc addNote*(db: SeqDb, pair: seq[string], placement: int, message: SeqText) =
  let wrap = message.wrap.get(db.autoWrap())
  db.notes.add SeqNote(actor: pair, placement: placement, message: message.text, wrap: wrap)
  db.messages.add SeqMessage(
    id: jsString(db.messages.len),
    start: some(pair[0]),
    to: some(pair[1]),
    message: message.text,
    wrap: wrap,
    kind: LINETYPE_NOTE,
    placement: placement)

proc entries(value: JsonNode): seq[(string, JsonNode)] =
  if value == nil: return
  case value.kind
  of JString:
    var i = 0
    for r in value.str.runes:
      result.add (jsString(i), newJString($r))
      inc i
  of JObject:
    for k, v in value.fields: result.add (k, v)
  of JArray:
    for i, v in value.elems: result.add (jsString(i), v)
  else: discard

proc parseMenu(text: string): (bool, JsonNode) =
  try:
    (true, jsonParse(text))
  except CatchableError:
    (false, nil)

# Mermaid logs and ignores menu text that is not valid JSON. It also undoes the `&amp;` and
# `&equals;` its sanitizer writes; Pele has no sanitizer, and a `;` cannot occur in the text.
proc addLinks*(db: SeqDb, actorId: string, text: SeqText) =
  let actor = db.actors.getOrDefault(actorId, nil)
  if actor == nil: return
  let (ok, parsed) = parseMenu(text.text)
  if not ok: return
  for (key, value) in entries(parsed): actor.links[key] = value

proc addALink*(db: SeqDb, actorId: string, text: SeqText) =
  let actor = db.actors.getOrDefault(actorId, nil)
  if actor == nil: return
  let sep = text.text.find('@')
  # slice(0, sep - 1) and slice(sep + 1); without an `@`, slice(0, -2) and the whole text.
  let stop = if sep >= 1: sep - 1 elif sep == 0: 0 else: max(0, text.text.len - 2)
  actor.links[jsTrim(text.text[0 ..< stop])] = newJString(jsTrim(text.text[sep + 1 .. ^1]))

proc addProperties*(db: SeqDb, actorId: string, text: SeqText) =
  let actor = db.actors.getOrDefault(actorId, nil)
  if actor == nil: return
  let (ok, parsed) = parseMenu(text.text)
  if not ok: return
  for (key, value) in entries(parsed): actor.properties[key] = value

# Mermaid reads the properties and links from a page element with this id. Pele keeps the id.
proc addDetails*(db: SeqDb, actorId: string, text: SeqText) =
  let actor = db.actors.getOrDefault(actorId, nil)
  if actor != nil: actor.details = some(text.text)

proc applyOne(db: SeqDb, param: SeqStatement) =
  let actor = param.actor
  case param.kind
  of "sequenceIndex":
    db.messages.add SeqMessage(
      id: jsString(db.messages.len),
      isNumbering: true,
      numbering: SeqNumbering(start: param.sequenceIndex, step: param.sequenceIndexStep,
                              visible: param.sequenceVisible),
      wrap: false,
      kind: param.signalType,
      placement: NO_TYPE)
  of "addParticipant":
    db.addActor(actor, actor, param.description,
                (if param.draw != "": some(param.draw) else: none(string)), param.config)
  of "createParticipant":
    if actor in db.actors:
      fail("It is not possible to have actors with the same id, even if one is destroyed before the next is created. Use 'AS' aliases to simulate the behavior")
    db.lastCreated = actor
    db.addActor(actor, actor, param.description,
                (if param.draw != "": some(param.draw) else: none(string)), param.config)
    db.createdActors[actor] = db.messages.len
  of "destroyParticipant":
    db.lastDestroyed = actor
    db.destroyedActors[actor] = db.messages.len
  of "activeStart", "activeEnd", "centralConnection", "centralConnectionReverse":
    db.addSignal(some(actor), none(string), none(SeqText), param.signalType)
  of "addNote":
    db.addNote(param.actors, param.placement, param.text)
  of "addLinks":
    db.addLinks(actor, param.text)
  of "addALink":
    db.addALink(actor, param.text)
  of "addProperties":
    db.addProperties(actor, param.text)
  of "addDetails":
    db.addDetails(actor, param.text)
  of "addMessage":
    if db.lastCreated != "":
      if param.to != db.lastCreated:
        fail("The created participant " & db.lastCreated & " does not have an associated creating message after its declaration. Please check the sequence diagram.")
      db.lastCreated = ""
    elif db.lastDestroyed != "":
      if param.to != db.lastDestroyed and param.start != db.lastDestroyed:
        fail("The destroyed participant " & db.lastDestroyed & " does not have an associated destroying message after its declaration. Please check the sequence diagram.")
      db.lastDestroyed = ""
    db.addSignal(some(param.start), some(param.to), some(param.msg), param.signalType, param.activate,
                 param.centralConnection)
  of "boxStart":
    db.addBox(param.boxData)
  of "boxEnd":
    db.currentBox = nil
  of "loopStart", "rectStart", "optStart", "altStart", "else", "parStart", "and", "criticalStart",
     "option", "breakStart":
    db.addSignal(none(string), none(string), param.blockText, param.signalType)
  of "loopEnd", "rectEnd", "optEnd", "altEnd", "parEnd", "criticalEnd", "breakEnd":
    db.addSignal(none(string), none(string), none(SeqText), param.signalType)
  else: discard

# Mermaid walks the nested statement lists by recursion; an explicit stack takes any depth.
proc apply*(db: SeqDb, root: SeqItem) =
  var lists: seq[SeqItem]
  var at: seq[int]
  var item = root
  while true:
    if item != nil:
      case item.kind
      of siList:
        lists.add item
        at.add 0
      of siStatement:
        db.applyOne(item.statement)
      of siString: discard
    let depth = lists.len - 1
    if depth < 0: return
    let list = lists[depth]
    if at[depth] < list.items.len:
      item = list.items[at[depth]]
      inc at[depth]
    else:
      discard lists.pop()
      discard at.pop()
      item = nil
