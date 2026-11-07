#!/bin/sh
# Runs the engine's tests under texlua. One list for the justfile, the
# pre-push hook and CI.
#   tools/test.sh fast        tests that finish in seconds (pre-push)
#   tools/test.sh <name>...   the named tests, e.g. mix layout
#   tools/test.sh             every test, ~12 min
set -e
cd "$(dirname "$0")/.."
FAST="core grow leaf plant settings reserve prepare_spec render_page inline headpiece"
case "$1" in
  fast) set -- $FAST bake ;;
  "") set -- $(ls tests/test_*.lua | sed 's|tests/test_||; s|\.lua$||') bake ;;
esac
for t in "$@"; do
  if [ "$t" = bake ]; then
    "${FLORA_PYTHON:-python3}" -I tests/test_bake.py
  else
    texlua "tests/test_$t.lua"
  fi
done
