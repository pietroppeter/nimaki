## Compares Nim's standard library with V8 on the number operations Pele uses.
##
##   node v8.mjs /tmp/v8.json && nim r compare.nim /tmp/v8.json
##
## Writes results.json next to this file: for each Math function, on how many of the seeded
## inputs Nim's answer differs from V8's in at least one bit, and on how many the difference
## survives scaling by 120 (a radius) and rounding to hundredths, as Pele's num() writes it. The post *How Pele is built* reads it.
import std/[json, math, os, strutils]

proc fromBits(h: string): float = cast[float](fromHex[uint64](h))

let v8 = parseJson(readFile(paramStr(1)))
const names = ["sin", "cos", "atan2", "hypot", "pow", "log10", "sqrt"]
var differ, shows: array[names.len, int]
var n = 0

proc jsRound(x: float): float =
  ## Math.round: the nearest integer, ties toward +infinity.
  result = floor(x)
  if x - result >= 0.5: result += 1

proc hundredths(x: float): float =
  ## What Pele's num() writes, as a number: a coordinate rounded to two decimals. A 1-ulp
  ## difference shows in the SVG only when it moves x * 100 across a half.
  jsRound(x * 120 * 100)
for row in v8["libm"]:
  let p = row.getStr.split(' ')
  let a = fromBits(p[0])
  let b = fromBits(p[1])
  let nim = [sin(a), cos(a), arctan2(a, b), hypot(a, b), pow(abs(b), a / 10), log10(abs(b) + 1), sqrt(abs(b))]
  for i, x in nim:
    if x != fromBits(p[2 + i]): inc differ[i]
    if hundredths(x) != hundredths(fromBits(p[2 + i])): inc shows[i]
  inc n
var libm = newJArray()
for i, name in names: libm.add %*{"function": name, "inputs": n, "differ": differ[i], "showsInSvg": shows[i]}
writeFile(currentSourcePath.parentDir / "results.json",
  pretty(%*{"node": v8["node"], "nim": NimVersion, "libm": libm, "cases": v8["cases"]}) & "\n")
echo "wrote results.json"
