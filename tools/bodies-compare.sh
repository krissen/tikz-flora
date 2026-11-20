#!/bin/sh
# Whether the engine paints byte for byte what REF painted
# (tools/bodies.lua; docs/testing.md).
#
#   tools/bodies-compare.sh REF [SUITE...]
#
# REF is a commit (b3fbda1, main, HEAD~1). Its tree is unpacked under
# build/bodies/ref with git archive; the working tree is the other side,
# uncommitted changes included. tools/bodies.lua and its slide fixtures
# are this tree's for both, so the two sides paint the same pages. Both
# sides run at once. Writes build/bodies/ref.txt and build/bodies/new.txt,
# prints the lines that differ and fails when any do. SUITE defaults to
# bands slides progression protect.
set -eu
cd "$(dirname "$0")/.."
ref=${1:?usage: tools/bodies-compare.sh REF [SUITE...]}
shift
[ $# -gt 0 ] || set -- bands slides progression protect
root=$(pwd)
out=build/bodies
rm -rf "$out" && mkdir -p "$out/ref"
git archive "$ref" | tar -x -C "$out/ref"
(cd "$out/ref" && texlua "$root/tools/bodies.lua" --fixtures "$root/tests/fixtures/slides" "$@") > "$out/ref.txt" &
refpid=$!
texlua tools/bodies.lua "$@" > "$out/new.txt" &
newpid=$!
wait "$refpid" || { echo "bodies-compare: $ref failed to paint"; exit 1; }
wait "$newpid" || { echo "bodies-compare: the working tree failed to paint"; exit 1; }
n=$(wc -l < "$out/new.txt" | tr -d ' ')
if cmp -s "$out/ref.txt" "$out/new.txt"; then
  echo "bodies-compare: $n identical to $ref ($*)"
else
  diff "$out/ref.txt" "$out/new.txt" | head -40
  echo "bodies-compare: $(diff "$out/ref.txt" "$out/new.txt" | grep -c '^>') of $n differ from $ref"
  exit 1
fi
