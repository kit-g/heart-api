#!/usr/bin/env bash
# Generates the /me spec at <base-ref> and at this checkout, and writes what
# changed between them as markdown (scripts/spec_diff.py). Nothing at all when
# they agree. Run on its own to see what a branch changes:
#
#   scripts/spec_diff.sh origin/main
#
# Assumes this checkout's dependencies are in place; the base gets its own
# worktree, and a base that can't generate a spec is reported, not fatal.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <base-ref>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$(mktemp -d)"
cleanup() { git -C "$ROOT" worktree remove --force "$BASE" 2>/dev/null || rm -rf "$BASE"; }
trap cleanup EXIT

# where this branch left the base, so what the base gained since says nothing
git -C "$ROOT" worktree add --quiet --detach "$BASE" "$(git -C "$ROOT" merge-base "$1" HEAD)"

make -C "$ROOT" openapi >/dev/null 2>&1
if ! make -C "$BASE" cards openapi >/dev/null 2>&1; then
  echo "The base's \`/me\` spec couldn't be generated, so there's nothing to compare with."
  exit 0
fi

python3 "$ROOT/scripts/spec_diff.py" "$BASE/api/openapi/me.json" "$ROOT/api/openapi/me.json"
