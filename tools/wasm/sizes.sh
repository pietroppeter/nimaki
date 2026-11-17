#!/bin/sh
# How big the WebAssembly build is: tools/wasm/build.sh with -d:danger --opt:size, for every type
# and for a few selections (-d:nimakiTypes, as tools/webbuild.nim makes the JavaScript files),
# raw and gzipped, as JSON lines on stdout. Run from the root of nimaki.
set -e
for types in all none flowchart flowchart,sequence,pie,timeline; do
  sh tools/wasm/build.sh -d:danger --opt:size -d:nimakiTypes=$types > /dev/null 2>&1
  echo "{\"types\": \"$types\", \"raw\": $(wc -c < build/wasm/nimaki.wasm), \"gzip\": $(gzip -9c build/wasm/nimaki.wasm | wc -c)}"
done
