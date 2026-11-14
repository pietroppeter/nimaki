## parse() and render(model) (src/nimaki/core.nim), as Pele exports them: on every input of the
## corpus, drawing the model that parse() returned gives what render(text) gives (the same SVG,
## or the same error), drawing it twice gives the same SVG twice, and the model carries the
## diagram's type and Mermaid type.
import std/[unittest, json, os, options]
import nimaki
import ../tools/common

const fixedNow = 1767225600000.0

proc answer(run: proc (): RenderResult): string =
  try: run().svg
  except PeleError as e: "ERROR " & e.code & ": " & e.msg

suite "parse, then render":
  let cases = parseFile(repoDir / "corpus" / "cases.json")["cases"]
  let options = RenderOptions(now: fixedNow)

  test "render(parse(text)) is render(text), on every corpus input":
    var same, parsed = 0
    for c in cases:
      let text = c["source"].getStr
      let direct = answer(proc (): RenderResult = render(text, options))
      var model: ParsedModel
      let viaModel = answer(proc (): RenderResult =
        model = parse(text, options)
        render(model, options))
      check direct == viaModel
      if direct == viaModel: inc same
      if model != nil:
        inc parsed
        check model.diagramType == detectType(text)
        check model.mermaidType.len > 0
        # Drawing never changes the model: a second drawing is the first.
        check answer(proc (): RenderResult = render(model, options)) == viaModel
    check same == cases.len
    echo "  ", same, " of ", cases.len, " inputs; ", parsed, " parsed to a model"

  test "the options read while parsing":
    let text = "pie\n  \"a\" : 1\n  \"b\" : 2\n"
    expect PeleError:
      discard parse(text, RenderOptions(limit: some(5)))
    let model = parse(text)
    check model.diagramType == "pie" and model.mermaidType == "pie"
    # A limit given to render() is not read again for a model, as in Pele.
    check render(model, RenderOptions(limit: some(5))).svg == render(text).svg
