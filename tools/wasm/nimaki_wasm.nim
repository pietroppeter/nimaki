## nimaki_wasm: nimaki's C build compiled to WebAssembly (an experiment; post *Faster, in three
## ways*). It exports a few functions to the JavaScript that loads it:
##
## - `nimakiAlloc(n)`: n bytes in the module's memory, where the caller writes the source as UTF-8;
## - `nimakiRender(p, n, now)`: draws the source at p; 0 when it drew, 1 when nimaki raised;
## - `nimakiResult()`, `nimakiResultLen()`: where the SVG (or the error's message) is, as UTF-8;
## - `nimakiFree(p)`: gives the source's bytes back.
##
## tools/wasm/build.sh compiles it with clang for wasm32-wasi; tools/wasm/run.mjs loads it in Node.
import nimaki

var output: string

proc NimMain() {.importc.}

proc nimakiInit() {.exportc.} = NimMain()

proc nimakiAlloc(n: int32): pointer {.exportc.} = alloc(n)
proc nimakiFree(p: pointer) {.exportc.} = dealloc(p)

proc nimakiRender(p: ptr UncheckedArray[char], n: int32, now: float): int32 {.exportc.} =
  var source = newString(n)
  if n > 0: copyMem(source[0].addr, p, n)
  try:
    output = render(source, RenderOptions(now: some(now))).svg
    0
  except CatchableError as e:
    output = e.msg
    1

proc nimakiResult(): pointer {.exportc.} = (if output.len > 0: output[0].addr else: nil)
proc nimakiResultLen(): int32 {.exportc.} = int32(output.len)
