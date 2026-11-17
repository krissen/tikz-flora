#!/bin/sh
# ORDER #18's sheets (tools/edge18_variants.lua rendered into OUT/render18),
# one question each, into OUT/sheets18: every value of ground, with
# magnified crops of where the ground ends; celtic_knot's field panel under
# ends=closed and ends=bleed, with a magnified corner; finish=lacquer in
# three colourways beside the mock. The text block is drawn as grey bars
# where the layout puts it (pattern_roles.lua's .text).
#
#   tools/edge18-sheets.sh OUT MOCKS
set -eu
OUT=${1:?usage: tools/edge18-sheets.sh OUT MOCKS}
MOCKS=${2:?usage: tools/edge18-sheets.sh OUT MOCKS}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
R="$OUT/render18"
SH="$OUT/sheets18"
T="$OUT/tmp18"
BG='#d8d4cc'
DARK="#0a1014"
mkdir -p "$SH" "$T" "$OUT/tiles18"

# bars TEXTFILE SCALE PAGEH [X0 Y0]: magick -draw rectangles for the text
# block's boxes, SCALE px per pt, the crop's corner at (X0, Y0) pt from the
# page's top left.
bars() {
  [ -f "$1" ] || return 0
  awk -v k="$2" -v cx="${4:-0}" -v cy="${5:-0}" 'NR == 1 { H = $2; next }
    { printf "rectangle %d,%d %d,%d ", ($1 - cx) * k, (H - $4 - cy) * k, ($3 - cx) * k, (H - $2 - cy) * k }' "$1"
}

# shade PNG BACKDROP: the dark backdrop under a transparent render.
shade() {
  if [ "$2" = dark ]; then
    magick -size "$(magick identify -format '%wx%h' "$1")" "xc:$DARK" "$1" -compose over -composite "$1"
  fi
}
barcolour() { if [ "$1" = dark ]; then echo '#3a4148'; else echo '#c4c8cc'; fi; }

# ltile VARIANT BACKDROP FILE HEIGHT LABEL -> a labelled tile's path.
ltile() {
  t="$OUT/tiles18/$1__$2__$3__$4.png"
  if [ ! -f "$t" ]; then
    pdf="$R/$1/$2/$3.pdf"
    if [ "$2" = dark ]; then pdftocairo -png -transp -singlefile -scale-to-y "$4" -scale-to-x -1 "$pdf" "$T/c"
    else pdftocairo -png -singlefile -scale-to-y "$4" -scale-to-x -1 "$pdf" "$T/c"; fi
    shade "$T/c.png" "$2"
    k=$(awk -v h="$4" 'NR == 1 { print h / $2 }' "$R/$1/$2/$3.text" 2>/dev/null || echo 0)
    draw=$(bars "$R/$1/$2/$3.text" "$k")
    magick "$T/c.png" -fill "$(barcolour "$2")" -draw "${draw:-point 0,0}" "$t"
  fi
  magick "$t" -background "$BG" -font "$FONT" -pointsize 12 -size "$(magick identify -format '%w' "$t")x" -gravity center caption:"$5" -append +repage "$T/lt.png"
  echo "$T/lt.png"
}

# zoom VARIANT BACKDROP FILE X0 Y0 W H LABEL: the page's crop (pt, from its
# top left) at 4 px per pt, about four times the A4 tiles' scale.
zoom() {
  pdf="$R/$1/$2/$3.pdf"
  k=4
  opt=""; [ "$2" = dark ] && opt="-transp"
  px() { awk -v a="$1" -v k="$k" 'BEGIN { printf "%d", a * k }'; }
  # shellcheck disable=SC2086
  pdftocairo -png $opt -singlefile -r 288 -x "$(px "$4")" -y "$(px "$5")" -W "$(px "$6")" -H "$(px "$7")" "$pdf" "$T/z"
  shade "$T/z.png" "$2"
  draw=$(bars "$R/$1/$2/$3.text" "$k" 0 "$4" "$5")
  magick "$T/z.png" -fill "$(barcolour "$2")" -draw "${draw:-point 0,0}" -fill black -background "$BG" -font "$FONT" -pointsize 13 \
    -size "$(magick identify -format '%w' "$T/z.png")x" -gravity center caption:"$8" -append +repage "$T/zt.png"
  echo "$T/zt.png"
}

# row OUTPNG HEIGHT "variant|backdrop|file|label" ...
row() {
  out=$1; h=$2; shift 2
  i=0; list=""
  for spec in "$@"; do
    v=${spec%%|*}; rest=${spec#*|}; bd=${rest%%|*}; rest=${rest#*|}; f=${rest%%|*}; label=${rest#*|}
    i=$((i + 1)); cp "$(ltile "$v" "$bd" "$f" "$h" "$label")" "$T/r$i.png"
    list="$list $T/r$i.png"
  done
  # shellcheck disable=SC2086
  magick $list -background "$BG" -gravity west -splice 6x0 -gravity north +append +repage "$out"
}
stack() { out=$1; shift; magick "$@" -background "$BG" -gravity northwest -splice 0x6 -append +repage "$out"; }
title() { magick -font "$FONT" "$1" -background "$BG" -gravity northwest -splice 0x30 -pointsize 18 -annotate +8+6 "$2" +repage "$1"; }

# --- grund__alla: every value of ground, light and dark, with crops.
about() {
  case $1 in
    auto) echo "auto: no ground on paper, one panel on a dark page" ;;
    off) echo "off: no ground" ;;
    panel) echo "panel: one panel, a straight edge toward the text" ;;
    motif) echo "motif: the ground ends along the motif" ;;
    round) echo "round: a rounded edge round the cells" ;;
    cells) echo "cells: a piece of ground under every cell" ;;
  esac
}
rows=""
n=0
for p in sikku_kolam asanoha rosette_lattice; do
  for bd in light dark; do
    set --
    for g in auto off panel motif round cells; do set -- "$@" "g18-${g}__tsuki-mi|$bd|slide-$p|$p, $(about $g) ($bd)"; done
    n=$((n + 1)); row "$T/g$n.png" 170 "$@"
    rows="$rows $T/g$n.png"
  done
  # The crops: where the ground ends toward the text, light side, x4.
  set --
  for g in auto off panel motif round cells; do
    cp "$(zoom "g18-${g}__tsuki-mi" light "slide-$p" 282 70 64 64 "$p x4, $g")" "$T/gz-$p-$g.png"
    set -- "$@" "$T/gz-$p-$g.png"
  done
  magick "$@" -background "$BG" -gravity west -splice 8x0 -gravity north +append +repage "$T/gz-$p.png"
  rows="$rows $T/gz-$p.png"
done
# shellcheck disable=SC2086
stack "$SH/grund__alla.png" $rows
title "$SH/grund__alla.png" "Every value of ground on the patterns that have one (tsuki-mi, 160 x 90 mm, edge=dissolve); under each pattern, where the ground ends, at four times"
echo "sheet: $SH/grund__alla.png"

# --- flata__standard: celtic_knot under ends=closed and ends=bleed.
rows=""
n=0
for size in slide page; do
  for bd in light dark; do
    set --
    for layout in left right centered surround; do
      for e in closed bleed; do
        case $e in closed) el="ends=closed (default): closes inside the paper" ;; bleed) el="ends=bleed: runs off the paper" ;; esac
        f=celtic_knot; [ $size = slide ] && f=slide-celtic_knot
        set -- "$@" "f18-$e-${layout}__tsuki-mi|$bd|$f|$layout, $el ($bd)"
      done
    done
    h=150; [ $size = page ] && h=300
    n=$((n + 1)); row "$T/f$n.png" "$h" "$@"
    rows="$rows $T/f$n.png"
  done
done
set --
for bd in light dark; do
  for e in closed bleed; do
    cp "$(zoom "f18-$e-left__tsuki-mi" "$bd" celtic_knot 0 725 120 120 "ends=$e, the A4 page's corner, x4 ($bd)")" "$T/fz-$e-$bd.png"
    set -- "$@" "$T/fz-$e-$bd.png"
  done
done
magick "$@" -background "$BG" -gravity west -splice 8x0 -gravity north +append +repage "$T/fz.png"
# shellcheck disable=SC2086
stack "$T/fgrid.png" $rows "$T/fz.png"
magick "$MOCKS/y-08.webp" -resize 260x260 -background "$BG" -gravity north -splice 0x22 -font "$FONT" -pointsize 14 -annotate +0+4 "mock y-08 (reference)" +repage "$T/fmock.png"
magick "$T/fmock.png" "$T/fgrid.png" -background "$BG" -gravity north +append +repage "$SH/flata__standard.png"
title "$SH/flata__standard.png" "celtic_knot as it now is (ends=closed) and with ends=bleed, four layouts, 160 x 90 mm and A4 (tsuki-mi), and the A4 corner at four times"
echo "sheet: $SH/flata__standard.png"

# --- lacquer: finish=lacquer in three colourways.
rows=""
n=0
for cw in tsuki-mi ember usu-zumi; do
  set --
  for p in sikku_kolam asanoha; do
    for bd in light dark; do set -- "$@" "l18__$cw|$bd|slide-$p|$p, finish=lacquer ($cw, $bd)"; done
  done
  n=$((n + 1)); row "$T/l$n.png" 170 "$@"
  rows="$rows $T/l$n.png"
done
# shellcheck disable=SC2086
stack "$T/lgrid.png" $rows
magick "$MOCKS/t-11.webp" -resize 260x260 -background "$BG" -gravity north -splice 0x22 -font "$FONT" -pointsize 14 -annotate +0+4 "mock t-11" +repage "$T/lmock.png"
magick "$T/lmock.png" "$T/lgrid.png" -background "$BG" -gravity north +append +repage "$SH/lacquer.png"
title "$SH/lacquer.png" "finish=lacquer: gold line work on the ground laid as one panel, in tsuki-mi, ember and usu-zumi"
echo "sheet: $SH/lacquer.png"
