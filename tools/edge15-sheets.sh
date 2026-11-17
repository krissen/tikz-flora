#!/bin/sh
# ORDER #15's sheets (tools/edge15_variants.lua rendered into OUT/render15),
# one question each, into OUT/sheets15: the knot field at the paper's edge
# with magnified crops; the ground as cells and as one panel; the star
# patterns' defaults and keys; gold on a ground; tsuki-mi's contour on the
# dark backdrop. The text block is drawn as grey bars where the layout puts
# it (pattern_roles.lua's .text).
#
#   tools/edge15-sheets.sh OUT MOCKS
set -eu
OUT=${1:?usage: tools/edge15-sheets.sh OUT MOCKS}
MOCKS=${2:?usage: tools/edge15-sheets.sh OUT MOCKS}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
R="$OUT/render15"
SH="$OUT/sheets15"
T="$OUT/tmp15"
BG='#d8d4cc'
DARK="#0a1014"
mkdir -p "$SH" "$T" "$OUT/tiles15"

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
  t="$OUT/tiles15/$1__$2__$3__$4.png"
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
  pdftocairo -png $opt -singlefile -r 288 -x "$(px "$4")" -y "$(px "$5")" -W "$(px "$6")" -H "$(px "$7")" "$pdf" "$T/z"
  shade "$T/z.png" "$2"
  draw=$(bars "$R/$1/$2/$3.text" "$k" 0 "$4" "$5")
  magick "$T/z.png" -fill "$(barcolour "$2")" -draw "${draw:-point 0,0}" -background "$BG" -font "$FONT" -pointsize 13 \
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

# --- flata__kant: (i) bleed and (ii) inset, every layout, and magnified crops.
rows=""
n=0
for size in slide page; do
  for cw in tsuki-mi ember; do
    for bd in light dark; do
      set --
      for layout in left right centered surround; do
        for m in bleed inset; do
          case $m in bleed) ml="(i) runs off the paper" ;; inset) ml="(ii) closes inside it" ;; esac
          f=celtic_knot; [ $size = slide ] && f=slide-celtic_knot
          set -- "$@" "k15-$m-${layout}__$cw|$bd|$f|$layout: $ml ($cw, $bd)"
        done
      done
      h=150; [ $size = page ] && h=300
      n=$((n + 1)); row "$T/k$n.png" "$h" "$@"
      rows="$rows $T/k$n.png"
    done
  done
done
# The magnified crops: the paper's bottom left corner on the A4 page under
# layout left, and the tongue the field puts out beside the page's
# shortest line under surround (from the moved text's boxes).
read -r tx ty tw th <<EOF2
$(awk 'NR == 1 { W = $1; H = $2; next }
  { w = $3 - $1; if (best == "" || w < bw) { best = NR; bw = w; x1 = $3; y = $2 } }
  END { printf "%d %d %d %d\n", x1 - 30, H - y - 70, 140, 120 }' "$R/k15-bleed-surround__tsuki-mi/light/celtic_knot.text")
EOF2
zrows=""
for bd in light dark; do
  set --
  for m in bleed inset; do
    case $m in bleed) ml="(i)" ;; inset) ml="(ii)" ;; esac
    cp "$(zoom "k15-$m-left__tsuki-mi" "$bd" celtic_knot 0 725 120 120 "$ml corner, A4 left, x4 ($bd)")" "$T/z-$m-c.png"
    cp "$(zoom "k15-$m-surround__tsuki-mi" "$bd" celtic_knot "$tx" "$ty" "$tw" "$th" "$ml tongue at the short line, A4 surround, x4 ($bd)")" "$T/z-$m-t.png"
    set -- "$@" "$T/z-$m-c.png" "$T/z-$m-t.png"
  done
  magick "$@" -background "$BG" -gravity west -splice 8x0 -gravity north +append +repage "$T/zr-$bd.png"
  zrows="$zrows $T/zr-$bd.png"
done
# shellcheck disable=SC2086
stack "$T/kgrid.png" $rows $zrows
magick "$MOCKS/y-08.webp" -resize 260x260 -background "$BG" -gravity north -splice 0x22 -font "$FONT" -pointsize 14 -annotate +0+4 "mock y-08 (reference)" +repage "$T/kmock.png"
magick "$T/kmock.png" "$T/kgrid.png" -background "$BG" -gravity north +append +repage "$SH/flata__kant.png"
title "$SH/flata__kant.png" "The knot field as one panel: (i) running off the paper's edge, (ii) closing just inside it; 160 x 90 mm, then A4, then crops at four times the A4 scale"
echo "sheet: $SH/flata__kant.png"

# --- grund__on: the ground as a piece under every cell, and as one panel.
rows=""
n=0
for p in sikku_kolam asanoha rosette_lattice; do
  set --
  for cw in tsuki-mi ember; do
    for bd in light dark; do
      set -- "$@" "g15-cells__$cw|$bd|slide-$p|$p ground=cells ($cw, $bd)" "g15-panel__$cw|$bd|slide-$p|$p ground=panel ($cw, $bd)"
    done
  done
  n=$((n + 1)); row "$T/g$n.png" 150 "$@"
  rows="$rows $T/g$n.png"
done
# shellcheck disable=SC2086
stack "$SH/grund__on.png" $rows
title "$SH/grund__on.png" "What ground=on could mean: a piece of ground under every cell (cells, as the base had it) or one panel (panel, as now)"
echo "sheet: $SH/grund__on.png"

# --- stjarnor: the new defaults and the keys.
set --
for cw in tsuki-mi ember; do
  for bd in light dark; do
    set -- "$@" "s15-default__$cw|$bd|slide-khatam|khatam default ($cw, $bd)" "s15-split__$cw|$bd|slide-khatam|starfill=split" \
      "s15-paper__$cw|$bd|slide-khatam|gapfill=paper"
  done
done
row "$T/sk.png" 150 "$@"
set --
for cw in tsuki-mi ember; do
  for bd in light dark; do
    set -- "$@" "s15-default__$cw|$bd|slide-hexagram_lattice|hexagram default ($cw, $bd)" "s15-paper__$cw|$bd|slide-hexagram_lattice|gapfill=paper" \
      "s15-rows__$cw|$bd|slide-hexagram_lattice|alternate=rows" "s15-three__$cw|$bd|slide-hexagram_lattice|alternate=three"
  done
done
row "$T/sh.png" 150 "$@"
stack "$SH/stjarnor.png" "$T/sk.png" "$T/sh.png"
title "$SH/stjarnor.png" "khatam and hexagram_lattice: the new defaults and the keys starfill, gapfill and alternate"
echo "sheet: $SH/stjarnor.png"

# --- farg__guld: gold on a ground.
set --
for p in asanoha seigaiha kikko; do
  for cw in tsuki-mi ember; do
    for bd in light dark; do
      set -- "$@" "e15-gold__$cw|$bd|slide-$p|$p ($cw, $bd)"
    done
  done
done
row "$T/fg.png" 150 "$@"
magick "$MOCKS/t-11.webp" -resize 200x200 -background "$BG" -gravity north -splice 0x22 -font "$FONT" -pointsize 14 -annotate +0+4 "mock t-11" +repage "$T/fm.png"
magick "$T/fm.png" "$T/fg.png" -background "$BG" -gravity north +append +repage "$SH/farg__guld.png"
title "$SH/farg__guld.png" "Proposed finish=lacquer: ground=panel, bands=line, bandwidth=0.5, band gold (not built); seigaiha and kikko have no ground to lay"
echo "sheet: $SH/farg__guld.png"

# --- tsukimi__kontur: the contour on the dark backdrop at three strengths.
# KONTUR holds "variant|label" for each, the label with its measured
# lightness difference (OKLab L, band against the second field, as shown).
set --
for p in khatam hexagram_lattice; do
  for kv in ${KONTUR:?KONTUR is unset}; do
    v=${kv%%|*}; label=$(echo "${kv#*|}" | tr '_' ' ')
    set -- "$@" "$v|dark|slide-$p|$p, $label"
  done
done
row "$T/tk.png" 180 "$@"
zl=""
for p in khatam hexagram_lattice; do
  for kv in $KONTUR; do
    v=${kv%%|*}; label=$(echo "${kv#*|}" | tr '_' ' ')
    cp "$(zoom "$v" dark "slide-$p" 380 60 60 60 "$p x4, $label")" "$T/tz-$p-${v%%__*}.png"
    zl="$zl $T/tz-$p-${v%%__*}.png"
  done
done
# shellcheck disable=SC2086
magick $zl -background "$BG" -gravity west -splice 8x0 -gravity north +append +repage "$T/tzr.png"
stack "$SH/tsukimi__kontur.png" "$T/tk.png" "$T/tzr.png"
title "$SH/tsukimi__kontur.png" "tsuki-mi on the dark backdrop: today's contour against the blue-green field, and two stronger ones (khatam, hexagram_lattice; crops at four times)"
echo "sheet: $SH/tsukimi__kontur.png"
