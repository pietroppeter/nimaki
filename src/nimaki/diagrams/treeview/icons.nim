## port-of: src/diagrams/treeview/icons.ts
## port-status: conformant
import std/[strutils, tables]

from std/unicode import nil
import ../../preprocess
import ../../util/yaml

const BUILTIN_PACK* = "mermaid-treeview"
  ## Mermaid's name for its built-in pack. Only `file` and `folder` are built in; every other
  ## icon name is offered to the host's icon resolver.

let GLYPHS*: Table[string, string] = {
  # Outlines on a 24 by 24 grid.
  "folder": "M3 6.5A1.5 1.5 0 0 1 4.5 5h4.6l2.4 2.5h8A1.5 1.5 0 0 1 21 9v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18z",
  "file": "M6.5 3h7L19 8.5v11a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6.5 3zM13.5 3v5.5H19",
}.toTable

type
  IconMap* = YamlValue
    ## `{ readonly [key: string]: unknown }`, nil for undefined.

  IconConfig* = object
    showIcons*: bool
    defaultIconPack*: string
    filenameIcons*, extensionIcons*: IconMap

func own(map: IconMap, key: string): string =
  ## The map's own string value for `key`, or "" for undefined.
  if map == nil or not map.fields.hasKey(key): return ""
  let value = map.fields[key]
  if value != nil and value.kind == yString: value.s else: ""

func lowerUnicode(s: string): string =
  ## `toLowerCase()`, for an extension (Unicode's simple mapping).
  unicode.toLower(s)

proc detectIcon*(name: string, config: IconConfig): string =
  ## A file's icon from the configured maps, or "" for none. A file name wins over an extension,
  ## and extensions match in lower case with or without the leading dot.
  let byName = own(config.filenameIcons, name)
  if byName != "": return byName
  let dot = name.rfind('.')
  if dot > 0:
    let ext = lowerUnicode(name[dot .. ^1])
    let withDot = own(config.extensionIcons, ext)
    # `??`: an empty string is a value and wins, but "" here stands for both
    if config.extensionIcons != nil and config.extensionIcons.fields.hasKey(ext) and
        config.extensionIcons.fields[ext] != nil and config.extensionIcons.fields[ext].kind == yString:
      return withDot
    return own(config.extensionIcons, ext[1 .. ^1])
  ""

proc qualifyIcon(icon, defaultIconPack: string): string =
  if ':' in icon: return icon
  if icon in GLYPHS or defaultIconPack == "": return BUILTIN_PACK & ":" & icon
  defaultIconPack & ":" & icon

proc getNodeIcon*(icon, name: string, directory: bool, config: IconConfig): string =
  ## The qualified icon name for a node, or "" when it shows none. An `icon()` annotation always
  ## wins; otherwise icons appear only with `showIcons`.
  if icon == "none": return ""
  if icon != "": return qualifyIcon(icon, config.defaultIconPack)
  if not config.showIcons: return ""
  if not directory:
    let detected = detectIcon(name, config)
    if detected == "none": return ""
    if detected != "": return qualifyIcon(detected, config.defaultIconPack)
  BUILTIN_PACK & ":" & (if directory: "folder" else: "file")

proc iconConfig*(config: Config): IconConfig =
  proc map(value: YamlValue): IconMap = (if value.isRecord: value else: nil)
  let c = map(config["treeView"])
  IconConfig(
    showIcons: truthy(c["showIcons"]),
    defaultIconPack: (let v = c["defaultIconPack"]; if v != nil and v.kind == yString: v.s else: ""),
    filenameIcons: map(c["filenameIcons"]),
    extensionIcons: map(c["extensionIcons"]))
