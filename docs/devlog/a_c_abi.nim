## devlog: 13 Nov 2026 N | A C ABI | nimaki is now also a shared library that any language able to call C can load, and from Python it draws every ported case of the corpus as Pele does.
## kind: tooling
import std/[strformat, strutils, json]
import nimib
import ../blocks, ../site
import nimaki/capi

nbInit
nb.usePost()

let run = parseFile(docsDir / "data" / "cabi.json")
let megabytes = formatFloat(run["bytes"].getInt / 1_000_000, ffDecimal, 1)
let msPie = formatFloat(run["msPerPie"].getFloat, ffDecimal, 2)

nbText: &"""
## The findings, first

- **nimaki is a library other languages can load.** `src/nimaki/capi.nim`, compiled with
  `--app:lib`, gives a shared library (`libnimaki.so` on Linux) with three C functions:
  `nimaki_render`, `nimaki_free` and `nimaki_pele_version`. A request and its answer are JSON
  text, with the same names as the answers of Pele in Node that diagrammari reads today.
- **From Python, the same SVG as Pele.** A smoke test in Python (`tests/cabi/smoke.py`, through
  `ctypes`, no package installed) sends all {run["cases"].getInt.thousands} cases of the corpus to the
  library and to Pele in Node: **{run["identical"].getInt.thousands} identical, {run["different"].getInt}
  different**, {run["unsupported"].getInt} of types not ported yet. Pie, the roadmap's test, is among them,
  with and without options.
- **Fast, with no JavaScript engine.** A pie takes {msPie} ms, request and answer included
  ({run["platform"].getStr}, Python {run["python"].getStr}). The library is {megabytes} MB.
- **One crash on the way:** a call from a Python thread crashed the first library. Threads Nim did
  not start have no heap of Nim's own allocator; built with `-d:useMalloc`, the library uses C's,
  and 64 calls from eight threads give one SVG.
- **Checked on every pull request:** `nim r tools/cabi.nim` builds the library and runs the smoke
  test, and CI runs it.
"""

nbText: """
## What a C ABI is

A *library* is code meant to be used by other programs, not run on its own. A *shared library*
is a file of machine code (`.so` on Linux, `.dylib` on macOS, `.dll` on Windows) that a program
loads while it runs, then calls as if the code were its own.

To call a function in such a file, the two sides must agree on details no source code shows:
which registers or stack slots hold the arguments, who cleans up, how a string is laid out in
memory. That agreement is an *ABI*, an application binary interface. Every language can speak
C's: Python (`ctypes`), Rust, Go, Java, Julia, Swift, and C itself. So a library that offers
plain C functions can be loaded from all of them.

Nim compiles to C, so writing one is short: a proc marked `exportc` (keep its name), `dynlib`
(make it visible outside the library) and `cdecl` (C's calling convention).

```nim
proc nimaki_render(request: cstring): cstring {.exportc, dynlib, cdecl.}
```

What crosses is kept simple on purpose: one string in, one string out, both JSON. A diagram is
text, its options are a small record, the answer is an SVG and a few numbers, so JSON costs
little, and no host has to learn a Nim type. The library allocates the answer and gives it to
the caller, who hands it back to `nimaki_free` when done, so the memory is freed by the
allocator that made it.

## A request and its answer

The Nim behind `nimaki_render` is `answer`, a proc from JSON to JSON. Called here, in the
program that builds this page:
"""

nbCode:
  let a = answer(%*{"source": "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n",
                    "options": {"idPrefix": "post-"}})
  echo a["ok"], " ", a["type"], " ", a["width"], " x ", a["height"]
  echo a["svg"].getStr[0 ..< 72], "..."

nbText: """
An error is an answer too, with Pele's code and the place in the text, so a host never has to
catch anything:
"""

nbCode:
  let e = answer(%*{"source": "pie\n  \"Dogs\" 386\n"})
  echo e["code"], " at line ", e["line"], ": ", e["message"].getStr

nbText: """
From Python, the smoke test loads the library with `ctypes` and wraps the two calls:

```python
import ctypes, json
lib = ctypes.CDLL("build/cabi/libnimaki.so")
lib.nimaki_render.argtypes = [ctypes.c_char_p]
lib.nimaki_render.restype = ctypes.c_void_p   # a pointer, to give it back
lib.nimaki_free.argtypes = [ctypes.c_void_p]

def render(source, **options):
    p = lib.nimaki_render(json.dumps({"source": source, "options": options}).encode())
    try:
        return json.loads(ctypes.string_at(p).decode())
    finally:
        lib.nimaki_free(p)

render('pie\n  "Dogs" : 386\n  "Cats" : 85\n')["svg"]   # '<svg xmlns=...'
```

The options are Pele's, by their names: `fontSize`, `fontFamily`, `padding`, `maxWidth`,
`idPrefix`, `responsive`, `autoDirection`, `limit`, `config` and the rest (the list is at the top
of `capi.nim`, and in the header `capi.h` for C).
"""

nbNote """
Pele's `render(text, options)` returns `{ svg, width, height, type, mermaidType, links }`, or
throws an error with `code`, `line`, `column` and `snippet`. diagrammari's Node runner sends
exactly those fields back as one JSON line (`src/mari/pele.nim` at diagrammari's pinned commit).
The library's answer uses the same names, so a host written for one reads the other.
""", nkPele, "The same answer as Pele's"

nbText: """
## The crash: threads Nim did not start

The first library passed the pie and every corpus case, then crashed the smoke test when it drew
from Python threads (`concurrent.futures`, eight at once: `ctypes` releases Python's lock while a
C function runs, so a host can draw in parallel). One call from one extra thread was enough.

Nim's own allocator keeps a heap for each thread, set up when Nim starts the thread. A thread
started by Python is unknown to it, so its first allocation found no heap. Built with
`-d:useMalloc`, Nim allocates with C's `malloc`, which every thread can use; the 64 calls from
eight threads then give one SVG, as they should.

Drawing itself is not made parallel: nimaki keeps a little state in globals while it draws (the
palette of the diagram, the icon and math resolvers), so every call takes one lock, and threads
take turns.
"""

nbNote """
- `capi.nim` builds the library; `tools/cabi.nim` builds it with `-d:useMalloc` and runs the smoke
  test. Neither is imported by `src/nimaki.nim`, so the JavaScript build is unchanged.
- The text is measured as in Node, with Pele's `metricsMeasurer`: the SVG is the one Pele draws in
  Node, not in a browser.
- `preprocess.fromJson` (JSON to the YAML values of frontmatter) is now exported, for the
  `config` option.
""", nkNim, "In the port"

nbNote &"""
- Python {run["python"].getStr} on {run["platform"].getStr}, through `ctypes`: {run["cases"].getInt.thousands} cases (the
  corpus, diagrammari's cases, and the pies again with six options), {run["identical"].getInt.thousands} identical
  to Pele in Node, {run["different"].getInt} different; errors identical too, code and message.
- A request that is not JSON, or has no `source`, gets an answer with code `request`.
- 64 draws from eight Python threads, one SVG.
""", nkDone, "Checked"

nbNote """
- Only Linux x86-64. macOS and Windows were not built; the tool names their files
  (`libnimaki.dylib`, `nimaki.dll`).
- No wheel, no Python package: the smoke test loads the file directly.
- Icons and math, which Pele takes as callbacks, cannot be passed yet; nor a text measurer of the
  host's.
- The library was not made smaller ({megabytes} MB, stripped); nothing was tried.
""".fmt, nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **A host can draw without a JavaScript engine.** diagrammari's Python proof of concept runs Pele
  in QuickJS, compiled into its own library, which answers in the same JSON shape; this library
  could take its place for the types nimaki draws. How, and what is still missing, is the next
  step on the roadmap, *A proposal for diagrammari*, not started.
- **The ABI is a contract.** Its three functions, and the names in the JSON, should change only
  with a new decision record.

## Sources

- The code of this step: [`src/nimaki/capi.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/capi.nim),
  [`src/nimaki/capi.h`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/capi.h),
  [`tools/cabi.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/cabi.nim),
  [`tests/cabi/smoke.py`](https://github.com/pietroppeter/nimaki/blob/main/tests/cabi/smoke.py).
- diagrammari at its pinned commit (`reference/DIAGRAMMARI`): `src/mari/pele.nim` (the Node runner
  and its answer), `experiments/python/nim/capi.nim` and `qjs.nim` (its C ABI and QuickJS), and
  `experiments/python/README.md`, read in the checkout `reference/fetch.sh diagrammari` makes.
- Python's [`ctypes`](https://docs.python.org/3/library/ctypes.html). What `-d:useMalloc` does was
  found by the crash and the build that fixed it, not read in Nim's documentation.
"""

nbSave
