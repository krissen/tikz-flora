#!/bin/sh
# A labelled sheet of pages a sweep rendered (tools/pattern_scale.lua
# sweep), in the order a labels file lists them.
#
#   tools/pattern-scale-sheet.sh RENDER LABELS COLS TITLE OUT.png [BOX] [CROP]
#
# RENDER is the sweep's output folder; each line of LABELS is
#   variant format layout pattern k label...
# naming RENDER/<variant>/<format>__<layout>__<pattern>__<k>.pdf, drawn
# with its text as grey bars (the .text beside it) and fitted into a BOX
# square (default 300), COLS to a row. CROP, if given as WxH+X+Y in mm
# from the page's top left, shows that part of each page instead,
# enlarged to the box: for judging lines at about their printed size.
set -eu
RENDER=${1:?usage: tools/pattern-scale-sheet.sh RENDER LABELS COLS TITLE OUT.png [BOX] [CROP]}
LABELS=${2:?usage}
COLS=${3:?usage}
TITLE=${4:?usage}
OUT=${5:?usage}
BOX=${6:-300}
CROP=${7:-}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
args=""
i=0
while read -r v f l p k label; do
  [ -n "$v" ] || continue
  base="$RENDER/$v/${f}__${l}__${p}__$k"
  i=$((i + 1))
  t="$TMP/t$i.png"
  if [ -n "$CROP" ]; then
    # The crop at 300 dpi, then fitted to the box.
    pdftocairo -png -singlefile -r 300 "$base.pdf" "$TMP/p"
    draw=$(LC_ALL=C awk 'NR == 1 { W = $1; H = $2; s = 300 / 72; next }
      { printf "rectangle %.1f,%.1f %.1f,%.1f ", $1 * s, (H - $4) * s, $3 * s, (H - $2) * s }' "$base.text")
    c=$(LC_ALL=C echo "$CROP" | awk -F '[x+]' '{ s = 300 / 25.4; printf "%dx%d+%d+%d", $1 * s, $2 * s, $3 * s, $4 * s }')
    magick "$TMP/p.png" -fill '#9a968e' -draw "$draw" -crop "$c" +repage -resize "${BOX}x${BOX}" "$t"
  else
    pdftocairo -png -singlefile -scale-to "$BOX" "$base.pdf" "$TMP/p"
    draw=$(LC_ALL=C awk -v box="$BOX" 'NR == 1 { W = $1; H = $2; s = box / (W > H ? W : H); next }
      { printf "rectangle %.1f,%.1f %.1f,%.1f ", $1 * s, (H - $4) * s, $3 * s, (H - $2) * s }' "$base.text")
    magick "$TMP/p.png" -fill '#9a968e' -draw "$draw" "$t"
  fi
  args="$args${args:+|}-label|$p, $l, $f\n$label|$t"
done < "$LABELS"
IFS='|'
# shellcheck disable=SC2086
montage -font "$FONT" $args -tile "${COLS}x" -geometry "${BOX}x${BOX}+6+6" -pointsize 11 -background '#d8d4cc' -title "$TITLE" "$OUT"
unset IFS
echo "sheet: $OUT"
