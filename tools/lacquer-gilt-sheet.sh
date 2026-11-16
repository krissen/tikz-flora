#!/bin/sh
# finish=lacquer as a document paints it: asanoha and sikku_kolam on a
# 160 x 90 mm page, compiled with LuaLaTeX and the package (the path a real
# document takes) under gilt=raster (the default) and gilt=vector, beside
# the sheet tool's render (tools/pattern_roles.lua, no gilding at all), in
# tsuki-mi and ember, light and dark; under each pattern, crops at eight
# pixels a point.
#
#   tools/lacquer-gilt-sheet.sh OUT RENDER
#
# RENDER holds tools/edge18_variants.lua's l18__<colourway> renders. Writes
# OUT/doc/*.tex and *.pdf and OUT/lacquer__gilt.png.
set -eu
OUT=${1:?usage: tools/lacquer-gilt-sheet.sh OUT RENDER}
RENDER=${2:?usage: tools/lacquer-gilt-sheet.sh OUT RENDER}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
BG='#d8d4cc'
DARK="#0a1014"
REPO=$(pwd)
mkdir -p "$OUT/doc" "$OUT/tmp"
export TEXINPUTS="$REPO/tex//:" LUAINPUTS="$REPO/lua//:"

page() { # PATTERN COLOURWAY BACKDROP GILT -> OUT/doc/<name>.pdf
  n="$1__$2__$3__$4"
  pc=""
  [ "$3" = dark ] && pc='\pagecolor[HTML]{0A1014}\color[HTML]{E6E3DA}'
  cat > "$OUT/doc/$n.tex" <<EOF
\documentclass[11pt]{article}
\usepackage[paperwidth=160mm,paperheight=90mm,left=10mm,right=62mm,top=12mm,bottom=12mm]{geometry}
\usepackage{xcolor}
\usepackage{tikzflora}
\pagestyle{empty}
\florasetup{layout=right, seed=3, pattern=$1, colourway=$2, finish=lacquer, backdrop=$3, gilt=$4}
\begin{document}
$pc\noindent{\Large\bfseries Geometri}\par\medskip
\noindent Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do
eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim
veniam, quis nostrud exercitation ullamco laboris.
\end{document}
EOF
  [ -f "$OUT/doc/$n.pdf" ] || (cd "$OUT/doc" && lualatex -interaction=nonstopmode -halt-on-error "$n.tex" > /dev/null) || { echo "lualatex failed: $n" >&2; exit 1; }
  echo "$OUT/doc/$n.pdf"
}

# tile PDF BACKDROP LABEL [CROP]: a labelled render; CROP is
# "x y w h" in pt from the page's top left, at 8 px a point.
tile() {
  if [ -n "${4:-}" ]; then
    set -- "$1" "$2" "$3" $4
    pdftocairo -png -singlefile -r 576 -x $(($4 * 8)) -y $(($5 * 8)) -W $(($6 * 8)) -H $(($7 * 8)) ${2:+-transp} "$1" "$OUT/tmp/t"
  else
    pdftocairo -png -singlefile -scale-to-y 220 -scale-to-x -1 -transp "$1" "$OUT/tmp/t"
  fi
  bg=white; [ "$2" = dark ] && bg=$DARK
  magick "$OUT/tmp/t.png" -background "$bg" -flatten -background "$BG" -font "$FONT" -pointsize 12 \
    -size "$(magick identify -format '%w' "$OUT/tmp/t.png")x" -gravity center caption:"$3" -append +repage "$OUT/tmp/tile.png"
  echo "$OUT/tmp/tile.png"
}

rows=""
n=0
for p in asanoha sikku_kolam; do
  for cw in tsuki-mi ember; do
    for bd in light dark; do
      set --
      i=0
      for col in tool raster vector; do
        case $col in
          tool) pdf="$RENDER/l18__$cw/$bd/slide-$p.pdf"; lab="sheet tool, no gilding" ;;
          *) pdf=$(page "$p" "$cw" "$bd" "$col"); lab="document, gilt=$col" ;;
        esac
        i=$((i + 1)); cp "$(tile "$pdf" "$bd" "$p, $lab ($cw, $bd)")" "$OUT/tmp/c$i.png"
        set -- "$@" "$OUT/tmp/c$i.png"
      done
      n=$((n + 1))
      magick "$@" -background "$BG" -gravity west -splice 6x0 -gravity north +append +repage "$OUT/tmp/r$n.png"
      rows="$rows $OUT/tmp/r$n.png"
    done
  done
  # Crops of the lines, tsuki-mi light and dark, raster and vector.
  set --
  i=0
  for bd in light dark; do
    for g in raster vector; do
      pdf=$(page "$p" tsuki-mi "$bd" "$g")
      i=$((i + 1)); cp "$(tile "$pdf" "$bd" "$p x8 crop, gilt=$g (tsuki-mi, $bd)" "330 60 36 36")" "$OUT/tmp/z$i.png"
      set -- "$@" "$OUT/tmp/z$i.png"
    done
  done
  n=$((n + 1))
  magick "$@" -background "$BG" -gravity west -splice 8x0 -gravity north +append +repage "$OUT/tmp/r$n.png"
  rows="$rows $OUT/tmp/r$n.png"
done
# shellcheck disable=SC2086
magick $rows -background "$BG" -gravity northwest -splice 0x6 -append +repage "$OUT/lacquer__gilt.png"
magick -font "$FONT" "$OUT/lacquer__gilt.png" -background "$BG" -gravity northwest -splice 0x30 -pointsize 18 \
  -annotate +8+6 "finish=lacquer as a document paints it (LuaLaTeX, the package), gilt=raster and gilt=vector, beside the sheet tool" +repage "$OUT/lacquer__gilt.png"
echo "sheet: $OUT/lacquer__gilt.png"
