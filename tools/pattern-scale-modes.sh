#!/bin/sh
# The pattern invariants at the size the field scale gives and at the scale
# key's 0.5, 0.75 and 1 with the field scale off
# (tools/pattern_scale_modes.lua), for the field scale's study.
#
#   tools/pattern-scale-modes.sh OUT [JOBS]
#
# Runs the parts of tests/test_pattern_matrix_N.lua (verbose),
# tests/test_pattern.lua, tests/test_pattern_protect.lua and the parts of
# tests/test_pattern_reach_N.lua in each mode, JOBS at a time (default 4), and writes OUT/<mode>__<test>.out with
# the exit code on its last line, and OUT/summary.tsv: mode, test, exit,
# the FAIL lines. Run from the repository root.
set -eu
OUT=${1:?usage: tools/pattern-scale-modes.sh OUT [JOBS]}
JOBS=${2:-4}
mkdir -p "$OUT"
jobs() {
  for m in field key0.5 key0.75 key1; do
    for t in test_pattern_matrix_1 test_pattern_matrix_2 test_pattern_matrix_3 test_pattern_matrix_4 test_pattern test_pattern_protect test_pattern_reach_1 test_pattern_reach_2 test_pattern_reach_3; do echo "$m $t"; done
  done
}
# shellcheck disable=SC2016 # the inner script expands its own arguments
jobs | xargs -P "$JOBS" -L 1 sh -c '
  o="$0/$1__$2.out"
  FLORA_MATRIX_VERBOSE=1 texlua tools/pattern_scale_modes.lua "$1" "tests/$2.lua" > "$o" 2>&1 && e=0 || e=$?
  echo "exit $e" >> "$o"' "$OUT"
printf 'mode\ttest\texit\tfails\n' > "$OUT/summary.tsv"
for f in "$OUT"/*__*.out; do
  b=$(basename "$f" .out)
  printf '%s\t%s\t%s\t%s\n' "${b%%__*}" "${b#*__}" "$(tail -1 "$f" | cut -d' ' -f2)" "$(grep -c '^FAIL' "$f" || true)" >> "$OUT/summary.tsv"
done
echo "modes: $OUT/summary.tsv"
