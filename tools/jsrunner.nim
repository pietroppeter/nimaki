## jsrunner: nimaki compiled to JavaScript, run in Node, for `--js` in tools/difftest.nim and
## tools/fuzz.nim (they compile and run it through `jsAnswers` in tools/answers.nim).
##
## Reads cases in the oracle's format (one JSON object per line: id, source, options) from the
## file named by the first argument, and writes one answer per line, in the oracle's format, to
## the file named by the second:
##
##   nim js -d:nodejs -d:danger -o:build/js/jsrunner.js tools/jsrunner.nim
##   TZ=UTC node build/js/jsrunner.js cases.jsonl answers.jsonl
import std/[json, strutils]
import verdict, answers
import nimaki/js

when not defined(js):
  {.error: "jsrunner is compiled with nim js".}

proc readFileSync(path, encoding: cstring): cstring {.importjs: "require('fs').readFileSync(#, #)".}
proc writeFileSync(path, data, encoding: cstring) {.importjs: "require('fs').writeFileSync(#, #, #)".}
proc argv(i: int): cstring {.importjs: "process.argv[#]".}
# A lone surrogate written as a JSON escape: writing the string as UTF-8 would make it U+FFFD.
proc escapeLoneSurrogates(s: cstring): cstring {.importjs: """#.replace(
  /[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g,
  (u) => '\\u' + u.charCodeAt(0).toString(16))""".}

proc main() =
  let input = $readFileSync(argv(2), "utf8")
  var output = ""
  for line in input.splitLines:
    if line.strip.len == 0: continue
    let c = parseJson(line)
    var answer: Answer
    try:
      answer = nimakiAnswer(c["source"].getStr, c{"options"})
    except:   # a JavaScript error (a TypeError...), no Nim exception: a bug of the JS build
      answer = Answer(ok: false, code: "js-error", message: getCurrentExceptionMsg())
    output.add $toJson(c["id"].getStr, answer) & "\n"
  writeFileSync(argv(3), escapeLoneSurrogates(toJsString(output)), "utf8")

main()
