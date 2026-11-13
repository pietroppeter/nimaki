## Builds nimaki's C ABI (src/nimaki/capi.nim) as a shared library and runs its smoke test, in
## Python through ctypes (tests/cabi/smoke.py): a pie, the errors, threads, and every case of the
## corpus against Pele run in Node.
##
##   nim r tools/cabi.nim            build build/cabi/libnimaki.so (.dylib, nimaki.dll), then test
##   nim r tools/cabi.nim --build    build only
##
## The library is built with `-d:useMalloc`: Python calls it from threads that Nim did not start,
## and those have no heap of Nim's own allocator (the post *A C ABI* tells how that showed).
import std/[os, osproc, strutils]
import common

const flags = "--app:lib -d:release -d:useMalloc -d:strip --hints:off --warnings:off"

proc libName(): string =
  when defined(windows): "nimaki.dll"
  elif defined(macosx): "libnimaki.dylib"
  else: "libnimaki.so"

when isMainModule:
  let buildOnly = "--build" in commandLineParams()
  let lib = buildDir / "cabi" / libName()
  createDir lib.parentDir
  let compile = "nim c " & flags & " -o:" & quoteShell(lib) & " " & quoteShell(repoDir / "src" / "nimaki" / "capi.nim")
  if execShellCmd(compile) != 0: quit "ERROR the library did not build: " & compile, 1
  echo "cabi: built ", lib.relativePath(repoDir), ", ", formatSize(getFileSize(lib))
  if buildOnly: quit 0
  let python = findExe("python3")
  if python.len == 0: quit "ERROR python3 not found: the smoke test runs in it", 2
  quit execShellCmd(quoteShell(python) & " " & quoteShell(repoDir / "tests" / "cabi" / "smoke.py") & " " & quoteShell(lib))
