#!/bin/sh
# ORDER #13's sheets (tools/edge13_variants.lua rendered into OUT/render13):
# the knot field running off the paper or closing inside it, in every
# layout, on the slide and the A4 page; khatam's and hexagram's defaults and
# keys; asanoha, seigaiha and kikko in gold on a ground. The text block is
# drawn as grey bars where the layout puts it (pattern_roles.lua's .text).
#
#   tools/edge13-sheets.sh OUT MOCKS
set -eu
OUT=${1:?usage: tools/edge13-sheets.sh OUT MOCKS}
MOCKS=${2:?usage: tools/edge13-sheets.sh OUT MOCKS}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
R="$OUT/render13"
SH="$OUT/sheets13"
BG='#d8d4cc'
DARK="#0a1014"
mkdir -p "$SH" "$OUT/tmp13" "$OUT/tiles13"

# ltile VARIANT BACKDROP FILE HEIGHT LABEL: FILE (a page's or slide's base
# name in R/VARIANT/BACKDROP) HEIGHT px high, the text as bars, labelled.
ltile() {
  t="$OUT/tiles13/$1__$2__$3__$4.png"
  if [ ! -f "$t" ]; then
    pdf="$R/$1/$2/$3.pdf"
    if [ "$2" = dark ]; then
      pdftocairo -png -transp -singlefile -scale-to-y "$4" -scale-to-x -1 "$pdf" "$OUT/tmp13/c"
      magick -size "$(magick identify -format '%wx%h' "$OUT/tmp13/c.png")" "xc:$DARK" "$OUT/tmp13/c.png" -compose over -composite "$OUT/tmp13/c.png"
      bar='#3a4148'
    else
      pdftocairo -png -singlefile -scale-to-y "$4" -scale-to-x -1 "$pdf" "$OUT/tmp13/c"
      bar='#c4c8cc'
    fi
    draw=""
    if [ -f "$R/$1/$2/$3.text" ]; then
      draw=$(awk -v h="$4" 'NR == 1 { k = h / $2; H = $2; next }
        { printf "rectangle %d,%d %d,%d ", $1 * k, (H - $4) * k, $3 * k, (H - $2) * k }' "$R/$1/$2/$3.text")
    fi
    magick "$OUT/tmp13/c.png" -fill "$bar" -draw "$draw" "$t"
  fi
  magick "$t" -background "$BG" -font "$FONT" -pointsize 12 -gravity center label:"$5" -append +repage "$OUT/tmp13/lt.png"
  echo "$OUT/tmp13/lt.png"
}

# row OUTPNG HEIGHT "variant|backdrop|file|label" ...: one row of tiles.
row() {
  out=$1; h=$2; shift 2
  i=0; list=""
  for spec in "$@"; do
    v=${spec%%|*}; rest=${spec#*|}; bd=${rest%%|*}; rest=${rest#*|}; f=${rest%%|*}; label=${rest#*|}
    i=$((i + 1)); cp "$(ltile "$v" "$bd" "$f" "$h" "$label")" "$OUT/tmp13/r$i.png"
    list="$list $OUT/tmp13/r$i.png"
  done
  # shellcheck disable=SC2086
  magick $list -background "$BG" -gravity west -splice 6x0 -gravity north +append +repage "$out"
}

title() { magick -font "$FONT" "$1" -background "$BG" -gravity northwest -splice 0x30 -pointsize 18 -annotate +8+6 "$2" +repage "$1"; }

# --- flata__kant: (i) bleed and (ii) inset, every layout.
rows=""
n=0
for size in slide page; do
  for cw in tsuki-mi ember; do
    for bd in light dark; do
      args=""
      set --
      for layout in left right centered surround; do
        for m in bleed inset; do
          case $m in bleed) ml="(i) runs off the paper" ;; inset) ml="(ii) closes inside it" ;; esac
          f=celtic_knot; [ $size = slide ] && f=slide-celtic_knot
          set -- "$@" "k13-$m-${layout}__$cw|$bd|$f|$layout: $ml ($cw, $bd)"
        done
      done
      h=150; [ $size = page ] && h=300
      n=$((n + 1)); row "$OUT/tmp13/k$n.png" "$h" "$@"
      rows="$rows $OUT/tmp13/k$n.png"
    done
  done
done
# shellcheck disable=SC2086
magick $rows -background "$BG" -gravity northwest -splice 0x6 -append +repage "$OUT/tmp13/kgrid.png"
magick "$MOCKS/y-08.webp" -resize 260x260 -background "$BG" -gravity north -splice 0x22 -font "$FONT" -pointsize 14 -annotate +0+4 "mock y-08 (reference)" +repage "$OUT/tmp13/kmock.png"
magick "$OUT/tmp13/kmock.png" "$OUT/tmp13/kgrid.png" -background "$BG" -gravity north +append +repage "$SH/flata__kant.png"
title "$SH/flata__kant.png" "The knot field as one panel: (i) running off the paper's edge, (ii) closing just inside it; layouts left, right, centered, surround; 160 x 90 mm above, A4 below"
echo "sheet: $SH/flata__kant.png"

# --- stjarnor: the new defaults and the keys.
set --
for cw in tsuki-mi ember; do
  for bd in light dark; do
    set -- "$@" "s13-default__$cw|$bd|slide-khatam|khatam default ($cw, $bd)" "s13-split__$cw|$bd|slide-khatam|starfill=split" \
      "s13-paper__$cw|$bd|slide-khatam|gapfill=paper"
  done
done
row "$OUT/tmp13/sk.png" 150 "$@"
set --
for cw in tsuki-mi ember; do
  for bd in light dark; do
    set -- "$@" "s13-default__$cw|$bd|slide-hexagram_lattice|hexagram default ($cw, $bd)" "s13-paper__$cw|$bd|slide-hexagram_lattice|gapfill=paper" \
      "s13-rows__$cw|$bd|slide-hexagram_lattice|alternate=rows" "s13-three__$cw|$bd|slide-hexagram_lattice|alternate=three"
  done
done
row "$OUT/tmp13/sh.png" 150 "$@"
magick "$OUT/tmp13/sk.png" "$OUT/tmp13/sh.png" -background "$BG" -gravity northwest -splice 0x8 -append +repage "$SH/stjarnor.png"
title "$SH/stjarnor.png" "khatam and hexagram_lattice: the new defaults and the keys starfill, gapfill and alternate"
echo "sheet: $SH/stjarnor.png"

# --- farg: gold on a ground, the proposed finish.
set --
for p in asanoha seigaiha kikko; do
  for cw in tsuki-mi ember; do
    set -- "$@" "e13-gold__$cw|light|slide-$p|$p ($cw)"
  done
done
row "$OUT/tmp13/fg.png" 150 "$@"
magick "$MOCKS/t-11.webp" -resize 200x200 -background "$BG" -gravity north -splice 0x22 -font "$FONT" -pointsize 14 -annotate +0+4 "mock t-11" +repage "$OUT/tmp13/fm.png"
magick "$OUT/tmp13/fm.png" "$OUT/tmp13/fg.png" -background "$BG" -gravity north +append +repage "$SH/farg__guld.png"
title "$SH/farg__guld.png" "Proposed finish=lacquer: ground=panel, bands=line, bandwidth=0.5, band gold, as one value (not built)"
echo "sheet: $SH/farg__guld.png"
