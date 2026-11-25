#!/bin/sh
# Whether the engine paints byte for byte what REF painted
# (tools/bodies.lua; docs/testing.md).
#
#   tools/bodies-compare.sh [--expect FILE] REF [SUITE...]
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
#
# With --expect FILE a change that is meant to paint some pages anew is
# compared: each line of FILE (but blank ones and those starting with #)
# is an extended regular expression for the pages expected to differ,
# matched against "SUITE NAME" (the line's first two fields, a space
# between). It ends with status 0 when exactly the pages some line matches
# differ and every other page is identical, and with 1 when a page differs
# that no line matches or one that a line matches is identical, naming
# them; the directory is kept then.
set -eu
refuse() { echo "bodies-compare: $1" >&2; exit 2; }
expect=
if [ "${1-}" = --expect ]; then
  [ $# -ge 2 ] && [ -n "$2" ] || refuse "--expect needs a file"
  case $2 in /*) expect=$2 ;; *) expect=$(pwd)/$2 ;; esac
  [ -f "$expect" ] && [ -r "$expect" ] || refuse "--expect: no file $2"
  shift 2
fi
cd "$(dirname "$0")/.."
[ $# -ge 1 ] && [ -n "$1" ] || refuse "usage: tools/bodies-compare.sh [--expect FILE] REF [SUITE...]"
ref=$1
shift
command -v git > /dev/null || refuse "needs git, to unpack $ref's tree"
command -v texlua > /dev/null || refuse "needs texlua"
PY=${FLORA_PYTHON:-python3}
command -v "$PY" > /dev/null || refuse "needs $PY (FLORA_PYTHON), which runs the two paints at once and stops them"
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
# The two paints run at once through tools/toolproc.py, which waits for both,
# stops the other when one fails, and stops both when it is signalled; this
# shell only passes a signal on to it, and reads the two statuses it prints.
child=
got=
# shellcheck disable=SC2329
on_signal() {
  got=$1
  [ -z "$child" ] || kill "$child" 2> /dev/null || true
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP
keep=1
"$PY" -I tools/toolproc.py run-all \
  "$out/ref" "$out/ref.txt" texlua "$root/tools/bodies.lua" --fixtures "$root/tests/fixtures/slides" "$@" \
  :: . "$out/new.txt" texlua tools/bodies.lua "$@" > "$out/status" &
child=$!
[ -z "$got" ] || kill "$child" 2> /dev/null || true
wait "$child" || true
while kill -0 "$child" 2> /dev/null; do wait "$child" 2> /dev/null || true; done
[ -z "$got" ] || { keep=; exit "$got"; }
# One line each: the status and "ok", "failed" (it failed itself) or "stopped"
# (it was stopped because the other failed, and did not fail).
{ read -r _ refhow && read -r _ newhow; } < "$out/status" || { echo "bodies-compare: the paints could not be run (see $out)"; exit 1; }
if [ "$refhow" = failed ] || [ "$newhow" = failed ]; then
  [ "$refhow" != failed ] || echo "bodies-compare: $ref failed to paint (see $out)"
  [ "$newhow" != failed ] || echo "bodies-compare: the working tree failed to paint (see $out)"
  exit 1
fi
n=$(wc -l < "$out/new.txt" | tr -d ' ')
if [ -n "$expect" ]; then
  # Page by page: the two sides paint the same pages in the same order.
  # Prints every page that breaks the expectation, then the counts.
  if paste "$out/ref.txt" "$out/new.txt" | awk -F '\t' -v want="$expect" '
    BEGIN { while ((getline l < want) > 0) if (l !~ /^[ \t]*(#|$)/) pat[++np] = l }
    {
      if ($1 != $4 || $2 != $5) { print "bodies-compare: page " NR " is " $1 " " $2 " in one tree and " $4 " " $5 " in the other"; bad++; next }
      page = $1 " " $2; meant = 0
      for (i = 1; i <= np; i++) if (page ~ pat[i]) { meant = 1; break }
      if ($3 != $6 && !meant) { print "bodies-compare: differs, not expected: " page; bad++ }
      else if ($3 == $6 && meant) { print "bodies-compare: expected to differ, identical: " page; bad++ }
      else if (meant) diff++; else same++
    }
    END { printf "bodies-compare: %d identical, %d differ as expected", same, diff; if (bad) printf ", %d against the expectation", bad; print ""; exit bad ? 1 : 0 }'; then
    echo "bodies-compare: $n pages against $ref ($*): as expected"
    keep=
  else
    echo "bodies-compare: not as expected (see $out)"
    exit 1
  fi
elif cmp -s "$out/ref.txt" "$out/new.txt"; then
  echo "bodies-compare: $n identical to $ref ($*)"
  keep=
else
  diff "$out/ref.txt" "$out/new.txt" | head -40
  echo "bodies-compare: $(diff "$out/ref.txt" "$out/new.txt" | grep -c '^>') of $n differ from $ref (see $out)"
  exit 1
fi
