#!/bin/sh
# One sheet per question of the edge and form study
# (tools/edge_variants.lua, rendered by tools/pattern_roles.lua into
# OUT/render): the alternatives side by side, labelled in words, each on
# the 160 x 90 mm slide, a row per colourway and backdrop.
#
#   tools/edge-sheets.sh OUT [MOCKS]
#
# OUT/bake holds the slide's slide.pdf (its text). MOCKS, if given, is a
# folder of the mock images; a sheet whose pattern has a mock starts with
# it. Writes OUT/sheets/<question>__<pattern>.png.
set -eu
OUT=${1:?usage: tools/edge-sheets.sh OUT [MOCKS]}
MOCKS=${2:-}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
DARK="#0a1014"
# RENDER and SHEETS (folders under OUT) default to render and sheets; with
# EDGE_SHEETS_LIB set only the functions are defined, for a later order's own
# sheet script to call.
RENDER=${RENDER:-render}
SHEETS=${SHEETS:-sheets}
mkdir -p "$OUT/$SHEETS" "$OUT/tmp" "$OUT/tiles"
[ -f "$OUT/bake/text-slide.png" ] || pdftocairo -png -singlefile -r 100 "$OUT/bake/slide.pdf" "$OUT/bake/text-slide"

# tile VARIANT BACKDROP PATTERN: the slide as the mixer shows it.
tile() {
  t="$OUT/tiles/$1__$2__$3.png"
  if [ ! -f "$t" ]; then
    if [ "$2" = dark ]; then
      pdftocairo -png -transp -singlefile -r 100 "$OUT/$RENDER/$1/$2/slide-$3.pdf" "$OUT/tmp/c"
      magick -size "$(magick identify -format '%wx%h' "$OUT/tmp/c.png")" "xc:$DARK" "$OUT/tmp/c.png" -compose over -composite \
        \( "$OUT/bake/text-slide.png" -negate \) -compose screen -composite "$t"
    else
      pdftocairo -png -singlefile -r 100 "$OUT/$RENDER/$1/$2/slide-$3.pdf" "$OUT/tmp/c"
      magick "$OUT/tmp/c.png" "$OUT/bake/text-slide.png" -compose multiply -composite "$t"
    fi
  fi
  echo "$t"
}

# sheet NAME PATTERN MOCK TITLE "colourway ..." "variant=label" ...
sheet() {
  name=$1; pat=$2; mock=$3; title=$4; cws=$5; shift 5
  args=""
  ncol=$#
  for cw in $cws; do
    for bd in light dark; do
      for vl in "$@"; do
        v=${vl%%=*}; label=${vl#*=}
        t=$(tile "${v}__$cw" "$bd" "$pat")
        args="$args${args:+|}-label|$label  ($cw, $bd)|$t"
      done
    done
  done
  IFS='|'
  # shellcheck disable=SC2086
  montage -font "$FONT" $args -tile "${ncol}x" -geometry 380x214+4+4 -pointsize 12 -background '#d8d4cc' "$OUT/tmp/grid.png"
  unset IFS
  if [ -n "$mock" ] && [ -n "$MOCKS" ] && [ -f "$MOCKS/$mock.webp" ]; then
    magick -font "$FONT" \( "$MOCKS/$mock.webp" -resize 300x300 -background '#d8d4cc' -gravity north -splice 0x22 -pointsize 14 -annotate +0+4 "mock $mock" \) "$OUT/tmp/grid.png" -background '#d8d4cc' -gravity north +append "$OUT/tmp/grid.png"
  fi
  magick -font "$FONT" "$OUT/tmp/grid.png" -background '#d8d4cc' -gravity northwest -splice 0x34 -pointsize 20 -annotate +8+6 "$title" "$OUT/$SHEETS/$name.png"
  echo "sheet: $OUT/$SHEETS/$name.png"
}

[ -n "${EDGE_SHEETS_LIB:-}" ] && return 0
for p in rosette_lattice sikku_kolam khatam asanoha; do
  case $p in rosette_lattice) m='f-14' ;; sikku_kolam) m='t-10' ;; khatam) m='y-03' ;; asanoha) m='t-11' ;; esac
  sheet "kant__$p" "$p" "$m" "$p: how the ground and fields end where the pattern ends (ground=on)" "tsuki-mi usu-zumi ember" \
    "edge-cells=Today: a square per cell" "edge-dark=A1 No ground on paper" "edge-panel=A2 A straight panel" \
    "edge-shape=A3 Ends along the motif" "edge-fade=A4 Fades out" "edge-discs=A5 Rounded edge (own proposal)"
done
sheet "enhet__sikku_kolam" sikku_kolam t-10 "sikku_kolam: what falls away at the edge" "tsuki-mi" \
  "unit-today=Today" "unit-units=Each loop with its dots" "unit-closed=Loops closed at the edge" "unit-symmetric=Closed, in symmetric panels"
sheet "enhet__celtic_knot" celtic_knot y-08 "celtic_knot: what falls away at the edge" "tsuki-mi" \
  "unit-today=Today" "unit-closed=Strands closed at the edge"
for p in hexagram_lattice greek_crosses penrose_rhombs khatam; do
  case $p in hexagram_lattice) m='y-02' ;; greek_crosses) m='y-04' ;; penrose_rhombs) m='t-05' ;; khatam) m='y-03' ;; esac
  sheet "form__$p" "$p" "$m" "$p: the form should carry, not the fill" "tsuki-mi ember" \
    "form-today=Today" "form-lighter=B1 Lighter fields"
done
