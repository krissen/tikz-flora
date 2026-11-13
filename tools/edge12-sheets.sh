#!/bin/sh
# ORDER #12's sheets, one per question: on top the mock and the
# alternatives at the same crop and scale (tools/mock_match.lua's squares
# in SQ/<colourway>/<name>.pdf), then each alternative on the 160 x 90 mm
# slide (tools/edge12_variants.lua rendered into OUT/render12).
#
#   tools/edge12-sheets.sh OUT MOCKS SQ
set -eu
OUT=${1:?usage: tools/edge12-sheets.sh OUT MOCKS SQ}
MOCKS=${2:?usage: tools/edge12-sheets.sh OUT MOCKS SQ}
SQ=${3:?usage: tools/edge12-sheets.sh OUT MOCKS SQ}
RENDER=render12 SHEETS=sheets12 EDGE_SHEETS_LIB=1
. tools/edge-sheets.sh
BG='#d8d4cc'

# square OUTPNG LABEL SOURCE: a 300 px square, labelled under it. SOURCE
# is mock:<name>[:<crop>] for a mock image, or <colourway>/<name> for a
# square of tools/mock_match.lua.
square() {
  case $3 in
    mock:*)
      spec=${3#mock:}; m=${spec%%:*}; crop=${spec#"$m"}; crop=${crop#:}
      if [ -n "$crop" ]; then magick "$MOCKS/$m.webp" -crop "$crop" +repage -resize 300x300! "$OUT/tmp/sq.png"
      else magick "$MOCKS/$m.webp" -resize 300x300! "$OUT/tmp/sq.png"; fi ;;
    *) pdftocairo -png -singlefile -scale-to 300 "$SQ/$3.pdf" "$OUT/tmp/sqp"
      magick "$OUT/tmp/sqp.png" -background white -flatten "$OUT/tmp/sq.png" ;;
  esac
  magick "$OUT/tmp/sq.png" +repage -background "$BG" -font "$FONT" -pointsize 14 -size 300x -gravity center caption:"$2" -append +repage "$1"
}

# squares NAME TITLE "label=source" ...: one row of squares (the source
# after the last =), appended
# above OUT/SHEETS/NAME.png.
squares() {
  name=$1; title=$2; shift 2
  i=0; list=""
  for ls in "$@"; do
    i=$((i + 1)); square "$OUT/tmp/sq$i.png" "${ls%=*}" "${ls##*=}"
    list="$list $OUT/tmp/sq$i.png"
  done
  # shellcheck disable=SC2086
  magick $list -background "$BG" -gravity west -splice 8x0 -gravity north +append +repage "$OUT/tmp/row.png"
  magick -font "$FONT" "$OUT/tmp/row.png" -background "$BG" -gravity northwest -splice 0x30 -pointsize 18 -annotate +8+6 "$title" "$OUT/tmp/row.png"
  magick "$OUT/tmp/row.png" "$OUT/$SHEETS/$name.png" -background "$BG" -gravity northwest -append +repage "$OUT/$SHEETS/$name.png"
}

# A. khatam
sheet "kant__khatam2" khatam "" "khatam: on the slide, how each ends where the pattern ends" "tsuki-mi ember" \
  "k12-today=(b) Today: stars alone on a square lattice" "k12-two=(c) Stars and crosses, the star in two tones" \
  "k12-one=(d) The star in one field, the cross in the other" "k12-paper=(d) The star in one field, the cross the paper" \
  "k12-dot=(e) As d, with the dot in the cross"
squares "kant__khatam2" "khatam: same crop and scale as y-03 (6.15 periods across)" \
  "(a) mock y-03=mock:y-03" "(b) Today=tsuki-mi/y-03" "(c) Star in two tones=tsuki-mi/y-03__two" \
  "(d) Star one field, cross the other=tsuki-mi/y-03__one" "(d) Star one field, cross paper=tsuki-mi/y-03__paper" \
  "(e) As d, dot in the cross=tsuki-mi/y-03__dot" \
  "(c) ember=ember/y-03__two" "(d) ember=ember/y-03__one" "(e) ember=ember/y-03__dot"

# B. hexagram
sheet "form__hexagram2" hexagram_lattice "" "hexagram_lattice: every star one colour, on the slide" "tsuki-mi ember" \
  "h12-star-thin=(a) Star field A, gaps field B, thin lines" "h12-plain=(b) Star field A, gaps the paper" \
  "h12-rows=(c) Stars in A and B by rows, gaps the paper" "h12-three=(c) Stars in A, B and accent, none touching alike" \
  "h12-lines=(d) Outlined stars, no fill (finish=lines)"
# Each row goes above the last, so ember's is made first.
squares "form__hexagram2" "" \
  "(a) ember=ember/y-02__big-star-thin" "(b) ember=ember/y-02__big-plain" "(c) rows, ember=ember/y-02__big-rows" \
  "(c) three, ember=ember/y-02__big-three" "(d) ember=ember/y-02__big-lines"
squares "form__hexagram2" "hexagram_lattice: a large crop, three periods across (tsuki-mi above, ember below); the two at the right are references only" \
  "(a) Star A, gaps B, thin lines=tsuki-mi/y-02__big-star-thin" "(b) Star A, gaps paper=tsuki-mi/y-02__big-plain" \
  "(c) A and B by rows=tsuki-mi/y-02__big-rows" "(c) A, B and accent=tsuki-mi/y-02__big-three" \
  "(d) Outlines (finish=lines)=tsuki-mi/y-02__big-lines" \
  "REJECTED: mock y-02=mock:y-02:123x123+0+0" "REJECTED: today=tsuki-mi/y-02__big"

# C. the knot panels
for p in celtic_knot celtic_panels; do
  case $p in celtic_knot) m=y-08 ;; celtic_panels) m=y-06 ;; esac
  sheet "flata__$p" "$p" "" "$p: closed panels on the slide" "tsuki-mi ember" \
    "c12-today=Today (rejected)" "c12-one=New: one panel per field" "c12-several=New: square panels of 7 units, a unit apart"
  # The choice shows on a whole page: the A4 page's margin field.
  for v in c12-one c12-several; do
    pdftocairo -png -singlefile -scale-to 620 "$OUT/$RENDER/${v}__tsuki-mi/light/$p.pdf" "$OUT/tmp/pg-$v"
  done
  magick -font "$FONT" \( "$OUT/tmp/pg-c12-one.png" -background "$BG" -gravity north -splice 0x22 -pointsize 14 -annotate +0+4 "One panel per field (A4 page, tsuki-mi)" \) \
    \( "$OUT/tmp/pg-c12-several.png" -background "$BG" -gravity north -splice 0x22 -pointsize 14 -annotate +0+4 "Square panels of 7 units, a unit apart (A4 page)" \) \
    -gravity west -splice 8x0 -gravity north +append "$OUT/$SHEETS/flata__$p.png" -background "$BG" -gravity northwest +append +repage "$OUT/$SHEETS/flata__$p.png"
  squares "flata__$p" "$p: same crop and scale as $m (9 units across)" \
    "mock $m=mock:$m" "Today (rejected)=tsuki-mi/${m}__panel" "New: one closed panel=tsuki-mi/${m}__one" "New, ember=ember/${m}__one"
done

# D. the heroes
sheet "hero__nya" stars_8_4 "" "The new turned-circles hero beside the guilloche it is not" "tsuki-mi ember" \
  "d12-guilloche=hero=guilloche (kept)" "d12-turned=hero=turned_circles (new)"
sheet "hero__nya2" overlapping_circles "" "The new circle-disc hero beside the pattern it is not" "tsuki-mi ember" \
  "d12-circles=pattern=overlapping_circles (kept)" "d12-disc=hero=circle_disc (new), over the pattern"
magick "$OUT/$SHEETS/hero__nya.png" "$OUT/$SHEETS/hero__nya2.png" -background "$BG" -gravity northwest -append +repage "$OUT/$SHEETS/hero__nya.png"
rm -f "$OUT/$SHEETS/hero__nya2.png"
squares "hero__nya" "The two new heroes beside their mocks and beside what they are not to be taken for (tsuki-mi)" \
  "mock t-09=mock:t-09" "New: hero=turned_circles=tsuki-mi/t-09__new" "Kept: hero=guilloche=tsuki-mi/t-09" \
  "mock t-01=mock:t-01" "New: hero=circle_disc=tsuki-mi/t-01__new" "Kept: pattern=overlapping_circles=tsuki-mi/t-01"

# E. asanoha
sheet "farg__asanoha" asanoha "" "asanoha on a ground in thin gold lines, on the slide" "tsuki-mi ember" \
  "e12-today=Today" "e12-gold=ground=panel, bands=line, bandwidth=0.5, band gold"
squares "farg__asanoha" "asanoha: same crop and scale as t-11; ember's ground is the nearest to the mock's (OKLab distance 0.029)" \
  "mock t-11=mock:t-11" "Today, tsuki-mi=tsuki-mi/t-11" "Gold on a ground, tsuki-mi=tsuki-mi/t-11__gold" "Gold on a ground, ember=ember/t-11__gold"
ls "$OUT/$SHEETS"
