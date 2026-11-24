#!/bin/sh
# Whether the engine paints byte for byte what REF painted
# (tools/bodies.lua; docs/testing.md).
#
#   tools/bodies-compare.sh REF [SUITE...]
#
# REF is a commit (b3fbda1, main, HEAD~1). Its tree is unpacked with git
# archive into a directory of this run's own under build/; the working tree
# is the other side, uncommitted changes included. tools/bodies.lua and its slide fixtures
# are this tree's for both, so the two sides paint the same pages. Both
# sides run at once. Writes ref.txt and new.txt there, prints the lines that
# differ and fails when any do; the directory (build/bodies.XXXXXX, one for
# each run, so that two runs at once do not share it) is kept when they do,
# or when a side failed to paint, and removed otherwise. SUITE defaults to
# bands slides progression protect.
#
# It needs git, a git working tree (REF's tree comes from its history) and
# texlua; without them, or when REF is not a commit, it says so and stops
# (exit status 2) before painting anything. In tools/test-linux.sh's
# container, which has neither git nor the history, it refuses so.
set -eu
cd "$(dirname "$0")/.."
refuse() { echo "bodies-compare: $1" >&2; exit 2; }
[ $# -ge 1 ] && [ -n "$1" ] || refuse "usage: tools/bodies-compare.sh REF [SUITE...]"
ref=$1
shift
command -v git > /dev/null || refuse "needs git, to unpack $ref's tree"
command -v texlua > /dev/null || refuse "needs texlua"
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || refuse "not in a git working tree; $ref's tree comes from its history"
git rev-parse --verify --quiet "$ref^{commit}" > /dev/null || refuse "$ref is not a commit"
[ $# -gt 0 ] || set -- bands slides progression protect
# The suites tools/bodies.lua knows; it too refuses another, but only after
# the suites before it have run.
for suite in "$@"; do
  case "$suite" in
    bands|slides|progression|protect) ;;
    *) refuse "no suite '$suite' (bands, slides, progression, protect)" ;;
  esac
done
root=$(pwd)
mkdir -p build 2> /dev/null || refuse "cannot make build/; nothing was painted"
out=$(mktemp -d build/bodies.XXXXXX 2> /dev/null) || refuse "cannot make a directory under build/; nothing was painted"
keep=
trap '[ -n "$keep" ] || rm -rf "$out" || true' EXIT
mkdir "$out/ref"
# Through a file, so that git archive failing is not hidden by the pipe.
git archive -o "$out/ref.tar" "$ref"
tar -x -C "$out/ref" -f "$out/ref.tar"
rm "$out/ref.tar"
# A signal to this shell is sent on to both paints, which are then waited
# for; and neither is left running when the other fails. A trap's action
# must not end with a command whose failure set -e acts on (the paint may
# be gone).
refpid=
newpid=
got=
trap 'got=130; kill "$refpid" "$newpid" 2> /dev/null || true' INT
trap 'got=143; kill "$refpid" "$newpid" 2> /dev/null || true' TERM
trap 'got=129; kill "$refpid" "$newpid" 2> /dev/null || true' HUP
(cd "$out/ref" && exec texlua "$root/tools/bodies.lua" --fixtures "$root/tests/fixtures/slides" "$@") > "$out/ref.txt" &
refpid=$!
texlua tools/bodies.lua "$@" > "$out/new.txt" &
newpid=$!
keep=1
refrc=0
newrc=0
# The other paint may have ended already: that is no failure here.
wait "$refpid" || { refrc=$?; kill "$newpid" 2> /dev/null || true; }
wait "$newpid" || newrc=$?
while kill -0 "$refpid" 2> /dev/null || kill -0 "$newpid" 2> /dev/null; do wait 2> /dev/null || true; done
[ -z "$got" ] || { keep=; exit "$got"; }
[ "$refrc" -eq 0 ] || { echo "bodies-compare: $ref failed to paint (see $out)"; exit 1; }
[ "$newrc" -eq 0 ] || { echo "bodies-compare: the working tree failed to paint (see $out)"; exit 1; }
n=$(wc -l < "$out/new.txt" | tr -d ' ')
if cmp -s "$out/ref.txt" "$out/new.txt"; then
  echo "bodies-compare: $n identical to $ref ($*)"
  keep=
else
  diff "$out/ref.txt" "$out/new.txt" | head -40
  echo "bodies-compare: $(diff "$out/ref.txt" "$out/new.txt" | grep -c '^>') of $n differ from $ref (see $out)"
  exit 1
fi
