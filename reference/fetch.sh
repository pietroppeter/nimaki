#!/usr/bin/env bash
# Fetch the pinned Pele: its source (the specification we port from) and its published npm
# package (the oracle we test against, run in Node). Both land in reference/, which git ignores.
# Safe to run again: it only fetches what is missing.
#
#   reference/fetch.sh            source and package
#   reference/fetch.sh source     only the source checkout   -> reference/pele/
#   reference/fetch.sh package    only the npm package       -> reference/npm/package/
#   reference/fetch.sh diagrammari  the pinned diagrammari (not in "all") -> reference/diagrammari/
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source <(grep -E '^[A-Z_]+=' "$here/PIN")
what="${1:-all}"

if [[ "$what" == all || "$what" == source ]]; then
  if [[ "$(git -C "$here/pele" rev-parse HEAD 2>/dev/null || true)" != "$COMMIT" ]]; then
    rm -rf "$here/pele"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$REPO" "$here/pele"
    got="$(git -C "$here/pele" rev-parse HEAD)"
    [[ "$got" == "$COMMIT" ]] || { echo "pin mismatch: $TAG is $got, expected $COMMIT" >&2; exit 1; }
  fi
  echo "source: $here/pele at $TAG ($COMMIT)"
fi

if [[ "$what" == all || "$what" == package ]]; then
  if [[ ! -f "$here/npm/package/dist/pele.js" ]]; then
    rm -rf "$here/npm" && mkdir -p "$here/npm"
    tarball="$(cd "$here/npm" && npm pack --silent "$NPM")"
    # npm pack checks nothing by itself: compare with the integrity recorded in PIN
    got="sha512-$(openssl dgst -sha512 -binary "$here/npm/$tarball" | base64 -w0)"
    [[ "$got" == "$NPM_INTEGRITY" ]] || { echo "integrity mismatch for $NPM: $got" >&2; exit 1; }
    tar -xzf "$here/npm/$tarball" -C "$here/npm"
  fi
  echo "package: $here/npm/package ($NPM)"
fi

# diagrammari, only on request: its Mermaid text is the second corpus (tools/corpus_diagrammari.nim)
if [[ "$what" == diagrammari ]]; then
  dREPO="$(grep -E '^REPO=' "$here/DIAGRAMMARI" | cut -d= -f2-)"
  dCOMMIT="$(grep -E '^COMMIT=' "$here/DIAGRAMMARI" | cut -d= -f2-)"
  if [[ "$(git -C "$here/diagrammari" rev-parse HEAD 2>/dev/null || true)" != "$dCOMMIT" ]]; then
    rm -rf "$here/diagrammari" && git init --quiet "$here/diagrammari"
    git -C "$here/diagrammari" fetch --quiet --depth 1 "$dREPO" "$dCOMMIT"
    git -c advice.detachedHead=false -C "$here/diagrammari" checkout --quiet FETCH_HEAD
  fi
  echo "diagrammari: $here/diagrammari at $dCOMMIT"
fi
