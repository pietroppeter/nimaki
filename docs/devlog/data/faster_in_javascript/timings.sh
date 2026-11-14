#!/bin/sh
# Times the stress tests of tests.tsv one at a time on a JavaScript build of the bridge, after
# `nim r tools/peletests.nim` has prepared build/peletests/:
#   sh docs/devlog/data/faster_in_javascript/timings.sh build/peletests/bridge.js out.json
# The post compares two runs: the bridge built from main before the step, and after it.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
bridge=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
out=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
report=$(mktemp)
cd "$repo/build/peletests/pele" || exit 2
echo "[" > "$out"; first=1
while IFS='	' read -r key file name; do
  TZ=UTC NIMAKI_SHIM="$repo/tools/peletests/index.mjs" NIMAKI_SETUP="$repo/tools/peletests/setup.mjs" \
    NIMAKI_BRIDGE="$bridge" npx vitest run -c vitest.nimaki.config.mjs "$file" -t "$name" \
    --reporter=json --outputFile="$report" > /dev/null 2>&1
  row=$(node -e "const j = require('$report');
    for (const f of j.testResults) for (const a of f.assertionResults)
      if (a.status !== 'skipped') { console.log(JSON.stringify({ file: '$file', test: a.fullName,
        ms: Math.round(a.duration), status: a.status })); process.exit(); }")
  [ $first = 1 ] || echo "," >> "$out"; first=0; echo "$row" >> "$out"
done < "$here/tests.tsv"
echo "]" >> "$out"
rm -f "$report"
