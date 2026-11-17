#!/bin/sh
# The pattern scale study: how many periods of each pattern a field holds,
# per layout and page format, and mock pages with the cell size set from
# the field (tools/pattern_scale.lua measures and renders; the default
# path of the engine is not changed).
#
#   tools/pattern-scale.sh OUT
#
# Bakes one page of text for each format in tools/scale_formats.lua into
# OUT/bake/<format>/ (spec-1.lua and text.pdf), then writes
#
#   OUT/scale.tsv               every pattern x layout x format today
#   OUT/render/<proposal>/...   the mock pages, today and per proposal
#   OUT/sheets/today.png        every pattern today, 160 x 90 beside A4
#   OUT/sheets/<proposal>.png   four patterns x three formats x left and
#                               surround, today beside the proposal
#
# PATTERN_SCALE_SHEETS_ONLY=1 lays out sheets from an earlier render. Run
# from the repository root; needs lualatex, pdftocairo and ImageMagick.
set -eu
OUT=${1:?usage: tools/pattern-scale.sh OUT}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
mkdir -p "$OUT/bake" "$OUT/render" "$OUT/sheets" "$OUT/tmp" "$OUT/tiles"
FORMATS=$(texlua tools/pattern_scale.lua formats)

# The text page of each format, with its layout dumped (FLORA_SPEC_DIR)
# and no flora drawn (\florapages{0}).
for f in $FORMATS; do
  d="$OUT/bake/$f"
  [ -f "$d/spec-1.lua" ] && continue
  mkdir -p "$d"
  texlua tools/pattern_scale.lua tex "$f" > "$d/text.tex"
  for _ in 1 2; do
    FLORA_SPEC_DIR="$d" lualatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
      -jobname=text "\def\florseed{3}\def\florapages{0}\input{$d/text.tex}" > "$d/text.out" \
      || { tail -20 "$d/text.log"; exit 1; }
  done
done
echo "bake: $OUT/bake"

texlua tools/pattern_scale.lua measure "$OUT/bake" "$OUT/scale.tsv"
echo "measure: $OUT/scale.tsv, $OUT/scale-proposals.tsv"
[ -n "${PATTERN_SCALE_SHEETS_ONLY:-}" ] || texlua tools/pattern_scale.lua render "$OUT/bake" "$OUT/render"

BOX=${PATTERN_SCALE_BOX:-300}
TAB=$(printf '\t')
# tile VARIANT FORMAT LAYOUT PATTERN: the page fitted into a BOX square,
# its text drawn as grey bars from the .text boxes beside it.
tile() {
  base="$OUT/render/$1/$2__$3__$4"
  t="$OUT/tiles/$1__$2__$3__$4.png"
  if [ ! -f "$t" ]; then
    pdftocairo -png -singlefile -scale-to "$BOX" "$base.pdf" "$OUT/tmp/t"
    draw=$(LC_ALL=C awk -v box="$BOX" 'NR == 1 { W = $1; H = $2; s = box / (W > H ? W : H); next }
      { printf "rectangle %.1f,%.1f %.1f,%.1f ", $1 * s, (H - $4) * s, $3 * s, (H - $2) * s }' "$base.text")
    magick "$OUT/tmp/t.png" -fill '#9a968e' -draw "$draw" "$t"
  fi
  echo "$t"
}
label_of() { awk -F "$TAB" -v k="$1" '$1 == k { print $2 }' "$OUT/render/labels.txt"; }
k_of() { awk -F "$TAB" -v v="$1" -v f="$2" -v l="$3" -v p="$4" '$1 == v && $2 == f && $3 == l && $4 == p { print $5 }' "$OUT/render/factors.tsv"; }

# Every pattern today: the 160 x 90 mm slide beside A4, layout left.
args=""
for p in $(awk -F "$TAB" 'NR > 1 && $1 == "today" && $2 == "a4" && $3 == "left" { print $4 }' "$OUT/render/factors.tsv"); do
  args="$args${args:+|}-label|$p  160 x 90|$(tile today slide169 left "$p")|-label|$p  A4|$(tile today a4 left "$p")"
done
IFS='|'
# shellcheck disable=SC2086
montage -font "$FONT" $args -tile 6x -geometry "${BOX}x${BOX}+6+6" -pointsize 13 -background '#d8d4cc' \
  -title "Every pattern today (scale=1, tsuki-mi, layout=left): 160 x 90 mm beside A4, each page fitted to the same box" "$OUT/sheets/today.png"
unset IFS

# A sheet per proposal: rows pattern x layout, columns format x (today, proposal).
for q in $(awk -F "$TAB" 'NR > 1 && $1 != "today" { print $1 }' "$OUT/render/factors.tsv" | sort -u); do
  args=""
  for p in khatam asanoha sikku_kolam celtic_knot; do
    for l in left surround; do
      for f in slide169 a4 a5; do
        k=$(k_of "$q" "$f" "$l" "$p")
        args="$args${args:+|}-label|$p $l $(label_of "$f")  today|$(tile today "$f" "$l" "$p")"
        args="$args|-label|$p $l $(label_of "$f")  $q  k=$k|$(tile "$q" "$f" "$l" "$p")"
      done
    done
  done
  IFS='|'
  # shellcheck disable=SC2086
  montage -font "$FONT" $args -tile 6x -geometry "${BOX}x${BOX}+6+6" -pointsize 12 -background '#d8d4cc' \
    -title "$(label_of "$q")  (today beside it; k = the factor on scale=1; tsuki-mi)" "$OUT/sheets/$q.png"
  unset IFS
done
echo "sheets: $OUT/sheets"
