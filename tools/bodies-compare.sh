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
#
# It needs git, a git working tree (REF's tree comes from its history) and
# texlua; without them, or when REF is not a commit, it says so and stops
# (exit status 2) before painting anything. In tools/test-linux.sh's
# container, which has neither git nor the history, it refuses so.
set -eu
cd "$(dirname "$0")/.."
refuse() { echo "bodies-compare: $1" >&2; exit 2; }
ref=${1:?usage: tools/bodies-compare.sh REF [SUITE...]}
shift
command -v git > /dev/null || refuse "needs git, to unpack $ref's tree"
command -v texlua > /dev/null || refuse "needs texlua"
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || refuse "not in a git working tree; $ref's tree comes from its history"
git rev-parse --verify --quiet "$ref^{commit}" > /dev/null || refuse "$ref is not a commit"
[ $# -gt 0 ] || set -- bands slides progression protect
root=$(pwd)
out=build/bodies
rm -rf "$out" && mkdir -p "$out/ref"
# Through a file, so that git archive failing is not hidden by the pipe.
git archive -o "$out/ref.tar" "$ref"
tar -x -C "$out/ref" -f "$out/ref.tar"
rm "$out/ref.tar"
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
