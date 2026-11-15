## Counts, in Pele's source at the pin (tests left out), the lines that use each TypeScript idiom
## the post "What two ports teach" talks about, and writes idioms.tsv beside this file:
##
##   nim r docs/devlog/data/two_ports/count_idioms.nim
##
## Run it again only when the pin moves. It reads Pele in reference/pele or $PELE_REF.
import std/[os, strutils, re]

let repo = currentSourcePath().parentDir.parentDir.parentDir.parentDir.parentDir
let pele = getEnv("PELE_REF", repo / "reference" / "pele")
if not dirExists(pele / "src"): quit "ERROR no Pele checkout in " & pele, 1

# idiom, what the line holds (a regular expression of Nim's re), where it is ported
const idioms = [
  ("s.length", r"\.length\b", "UTF-16: `utf16Len` where the number shows"),
  ("charCodeAt, codePointAt", r"\.(charCodeAt|codePointAt)\(", "UTF-16: `codeAt`, `codeUnits`, `codePointAt`"),
  ("a regular expression literal", r"(^|[=(,:!&|?;\[{]|return)\s*/[^/*\s]([^/\n]|\\/)*/[dgimsuy]*", "`jsre` of `jsregex.nim`"),
  ("Math.round, toFixed", r"Math\.round\(|\.toFixed\(", "numbers: `jsRound`, `toFixed`"),
  ("a template string, `${x}`", r"\$\{", "`&`; a number in it through `jsString` or `num`"),
  ("Math.max, Math.min", r"Math\.(max|min)\(", "NaN: `jsMax`, `jsMin`"),
  ("new Map, new Set", r"new (Map|Set)\b", "order: `OrderedTable`, `OrderedSet`"),
  ("undefined, ??, ?.", r"\bundefined\b|\?\?|\?\.", "`Option`, `nil`, or a stand-in"),
  ("a spread, ...x", r"\.\.\.[A-Za-z_(\[]", "copy, then set fields; `{.spread.}` in a model"),
  ("an interface", r"^\s*(export\s+)?interface\s", "an `object` or a `ref object`"),
  ("a class", r"^\s*(export\s+)?(abstract\s+)?class\s", "a `ref object` and its procs"),
  ("a type that is a list of words", r"""^\s*(export\s+)?type\s+\w+\s*=\s*(\|\s*)?['"]""", "an `enum`"),
  ("an arrow function", r"=>", "a `proc`, a closure or a `template`"),
]

var counts = newSeq[int](idioms.len)
var files, total = 0
for path in walkDirRec(pele / "src"):
  if not path.endsWith(".ts") or path.endsWith(".test.ts") or path.endsWith(".d.ts"): continue
  inc files
  for line in lines(path):
    let t = line.strip
    if t.startsWith("//") or t.startsWith("*") or t.startsWith("/*") or t == "": continue
    inc total
    for i, (_, pattern, _) in idioms:
      if line.contains(re(pattern)): inc counts[i]

var tsv = ""
for i, (name, _, nim) in idioms: tsv.add name & "\t" & $counts[i] & "\t" & nim & "\n"
writeFile(currentSourcePath().parentDir / "idioms.tsv", tsv)
writeFile(currentSourcePath().parentDir / "lines.txt", $files & "\t" & $total & "\n")
echo "count_idioms: ", files, " files, ", total, " lines of code -> idioms.tsv"
