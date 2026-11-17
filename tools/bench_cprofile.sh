#!/bin/sh
# Where nimaki's C build spends its time (the page *Benchmark*, `docs/benchmark.nim`). It draws
# the whole corpus once under valgrind's callgrind, which counts the machine instructions each
# function runs (a slow but exact profiler: no sampling, no noise), then keeps the top 60 of two
# lists: by the function's own instructions (self), and by everything it calls too (inclusive).
# Paths are shortened to the file's name. Run from the root of nimaki (needs valgrind):
#
#   sh tools/bench_cprofile.sh [OUTDIR]      writes OUTDIR/c-self.txt and c-inclusive.txt
#                                            (default build/bench)
set -e
out=${1:-build/bench}
mkdir -p "$out" build/bench
nim c --hints:off -d:release --debugger:native -o:build/bench/bench-g tools/bench.nim
valgrind --tool=callgrind --callgrind-out-file=build/bench/cg-all.out build/bench/bench-g --engines:c --rounds:1 > /dev/null 2>&1
shorten() { sed -n '/PROGRAM TOTALS/,$p' | grep -E '^ *[0-9,]+ \(' | head -n 60 |
  sed -E 's#\(([ 0-9.]+)%\) +[^ ]*/([^/: ]+):#(\1%) \2:#; s# \[[^]]*\]$##' | cut -c1-200; }
callgrind_annotate build/bench/cg-all.out | shorten > "$out/c-self.txt"
callgrind_annotate --inclusive=yes build/bench/cg-all.out | shorten > "$out/c-inclusive.txt"
echo "cprofile: $(head -1 "$out/c-self.txt")"
