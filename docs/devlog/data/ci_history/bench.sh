#!/bin/sh
# The 34 fuzzers as CI runs them (the lines of .github/workflows/pages.yml), timed four ways:
# one after another or four at a time, built as `nim r` builds them (debug) or with -d:release.
# Run from the repository's root after tools/setup.sh. Prints one line per way, in seconds.
# The fuzzers write their counts into docs/data/fuzz.json; the last line puts it back.
types=$(grep -o 'tools/fuzz.nim [A-Za-z0-9]* --cases:[0-9]*' .github/workflows/pages.yml | sed 's/tools\/fuzz.nim //')
nim c --hints:off -o:build/fuzz-debug tools/fuzz.nim >/dev/null 2>&1
nim c -d:release --hints:off -o:build/fuzz-release tools/fuzz.nim >/dev/null 2>&1
t() { s=$(date +%s.%N); "$@"; e=$(date +%s.%N); echo "$e - $s" | bc; }
one() { echo "$types" | while read a b; do $1 $a $b >/dev/null; done; }
four() { echo "$types" | xargs -P4 -L1 $1 >/dev/null; }
echo "debug sequential $(t one build/fuzz-debug)"
echo "release sequential $(t one build/fuzz-release)"
echo "debug parallel4 $(t four build/fuzz-debug)"
echo "release parallel4 $(t four build/fuzz-release)"
git checkout -q docs/data/fuzz.json
