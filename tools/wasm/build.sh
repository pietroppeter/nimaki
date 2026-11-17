#!/bin/sh
# Compiles tools/wasm/nimaki_wasm.nim to build/wasm/nimaki.wasm with clang for wasm32-wasi
# (WASI's C library: `wasi-libc` on Debian and Ubuntu, or the wasi-sdk). Run from the root:
#   sh tools/wasm/build.sh [more nim flags, such as -d:danger]
set -e
mkdir -p build/wasm
nim c --hints:off -d:release "$@" \
  --cpu:wasm32 --os:linux --cc:clang --mm:orc --threads:off --exceptions:goto \
  -d:useMalloc -d:noSignalHandler --noMain:on --stackTrace:off --lineTrace:off \
  --passC:--target=wasm32-wasi --passL:--target=wasm32-wasi \
  --passL:-mexec-model=reactor --passL:-Wl,--export=nimakiInit,--export=nimakiAlloc,--export=nimakiFree,--export=nimakiRender,--export=nimakiResult,--export=nimakiResultLen --passL:-Wl,--strip-all \
  --nimcache:build/wasm/cache -o:build/wasm/nimaki.wasm tools/wasm/nimaki_wasm.nim
ls -l build/wasm/nimaki.wasm
