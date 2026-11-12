#!/bin/sh
# Sheets of the pattern colour-role variants (tools/pattern_variants.lua,
# rendered by tools/pattern_roles.lua), with the mocks beside them.
#
#   tools/pattern-roles.sh OUT MOCKS [BEFORE]
#
# OUT/bake holds the baked layouts: tex/lorem.tex's spec-N.lua and
# base.pdf (as tools/pattern-audit.sh bakes them) and a 160 x 90 mm slide's
# spec-slide.lua and slide.pdf. MOCKS is a folder of the mock images
# (t-03.webp, ...). BEFORE (default 36edc60) is the commit whose patterns
# are the reference V0: its lua/ is exported to OUT/before and rendered by
# this tree's tools. Writes OUT/sheets/:
#
#   compare__<pattern>.png   the mock (where one exists), then a 60 mm
#                            square of the field per variant (rows) and
#                            palette and backdrop (columns); the greys below
#   compare__hero-<name>.png the same for each hero, its corner
#   detail__<V>__<palette>-<backdrop>.png, page__...  every pattern
#   slide__V2__<palette>-<backdrop>.png                every pattern on the slide
#
# PATTERN_ROLES_SHEETS_ONLY=1 lays out sheets from an earlier render. Run
# from the repository root.
set -eu
OUT=${1:?usage: tools/pattern-roles.sh OUT MOCKS [BEFORE]}
MOCKS=${2:?usage: tools/pattern-roles.sh OUT MOCKS [BEFORE]}
BEFORE=${3:-36edc60}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
DARK="#0a1014"
DPI=40
DD=150
ROOT=$(pwd)
mkdir -p "$OUT/render" "$OUT/sheets" "$OUT/tmp" "$OUT/tiles"

if [ -z "${PATTERN_ROLES_SHEETS_ONLY:-}" ]; then
  rm -f "$OUT/render/roles.tsv"
  printf 'variant\tpalette\tbackdrop\tpattern\tground\tsurface\tband\tcore\ta\tb\taccent\tground\tband/surface\ta/surface\tb/surface\ta/b\tband/a\tcore/band\taccent/surface\n' > "$OUT/render/roles.tsv"
  rm -rf "$OUT/before" && mkdir -p "$OUT/before"
  git archive "$BEFORE" lua | tar -x -C "$OUT/before"
  before=$(awk '/before = true/ { match($0, /name = "[^"]*"/); print substr($0, RSTART + 8, RLENGTH - 9) }' tools/pattern_variants.lua | paste -sd, -)
  after=$(awk '/name = "/ && !/before = true/ { match($0, /name = "[^"]*"/); print substr($0, RSTART + 8, RLENGTH - 9) }' tools/pattern_variants.lua | paste -sd, -)
  (cd "$OUT/before" && texlua "$ROOT/tools/pattern_roles.lua" "$OUT/bake" "$OUT/render" "$ROOT/tools/pattern_variants.lua" "$before")
  texlua tools/pattern_roles.lua "$OUT/bake" "$OUT/render" tools/pattern_variants.lua "$after"
fi

for p in 3 4; do
  for d in $DPI $DD; do
    [ -f "$OUT/bake/text-$p-$d.png" ] || pdftocairo -png -singlefile -r $d -f $p -l $p "$OUT/bake/base.pdf" "$OUT/bake/text-$p-$d"
  done
done
[ -f "$OUT/bake/text-slide.png" ] || pdftocairo -png -singlefile -r 100 "$OUT/bake/slide.pdf" "$OUT/bake/text-slide"

# compose PDF TEXT BACKDROP OUT DPI
compose() {
  if [ "$3" = dark ]; then
    pdftocairo -png -transp -singlefile -r "$5" "$1" "$OUT/tmp/c"
    magick -size "$(magick identify -format '%wx%h' "$OUT/tmp/c.png")" "xc:$DARK" "$OUT/tmp/c.png" -compose over -composite \
      \( "$2" -negate \) -compose screen -composite "$4"
  else
    pdftocairo -png -singlefile -r "$5" "$1" "$OUT/tmp/c"
    magick "$OUT/tmp/c.png" "$2" -compose multiply -composite "$4"
  fi
}

px=$(awk "BEGIN { print int(60 / 25.4 * $DD) }")
ox=$(awk "BEGIN { print int(4 / 25.4 * $DD) }")
oy=$(awk "BEGIN { print int(40 / 25.4 * $DD) }")
# The hero's corner on the right page: the top right 70 mm square.
hx=$(awk "BEGIN { print int((210 - 70) / 25.4 * $DD) }")
hp=$(awk "BEGIN { print int(70 / 25.4 * $DD) }")

for vdir in "$OUT"/render/*/; do
  v=$(basename "$vdir")
  for cdir in "$vdir"*/; do
    c=$(basename "$cdir"); bd=${c##*-}
    dtiles=""; ptiles=""; stiles=""
    for pdf in "$cdir"*.pdf; do
      n=$(basename "$pdf" .pdf)
      case "$n" in
        hero-*)
          compose "$pdf" "$OUT/bake/text-3-$DD.png" "$bd" "$OUT/tmp/full.png" $DD
          magick "$OUT/tmp/full.png" -crop "${hp}x${hp}+${hx}+0" +repage -resize 420x420 "$OUT/tiles/${v}__${c}__${n}.png" ;;
        slide-*)
          compose "$pdf" "$OUT/bake/text-slide.png" "$bd" "$OUT/tiles/${v}__${c}__${n}.png" 100
          stiles="$stiles -label ${n#slide-} $OUT/tiles/${v}__${c}__${n}.png" ;;
        *)
          compose "$pdf" "$OUT/bake/text-4-$DD.png" "$bd" "$OUT/tmp/full.png" $DD
          magick "$OUT/tmp/full.png" -crop "${px}x${px}+${ox}+${oy}" +repage -resize 420x420 "$OUT/tiles/${v}__${c}__${n}.png"
          dtiles="$dtiles -label $n $OUT/tiles/${v}__${c}__${n}.png"
          compose "$pdf" "$OUT/bake/text-4-$DPI.png" "$bd" "$OUT/tmp/page.png" $DPI
          cp "$OUT/tmp/page.png" "$OUT/tiles/page__${v}__${c}__${n}.png"
          ptiles="$ptiles -label $n $OUT/tiles/page__${v}__${c}__${n}.png" ;;
      esac
    done
    # shellcheck disable=SC2086
    montage -font "$FONT" $dtiles -tile 5x -geometry +5+5 -pointsize 16 -background '#d8d4cc' -title "$v $c" "$OUT/sheets/detail__${v}__$c.png"
    # shellcheck disable=SC2086
    montage -font "$FONT" $ptiles -tile 8x -geometry +4+4 -pointsize 12 -background '#d8d4cc' -title "$v $c" "$OUT/sheets/page__${v}__$c.png"
    # shellcheck disable=SC2086
    [ -n "$stiles" ] && montage -font "$FONT" $stiles -tile 3x -geometry +5+5 -pointsize 14 -background '#d8d4cc' -title "$v $c (160 x 90 mm)" "$OUT/sheets/slide__${v}__$c.png"
  done
done

# The mock each pattern or hero is compared with, if any.
mock_of() {
  case "$1" in
    stars_8_4) echo t-03 ;; asanoha) echo t-11 ;; penrose_rhombs) echo t-05 ;; truchet) echo t-06 ;;
    sikku_kolam) echo t-10 ;; overlapping_circles) echo t-01 ;; hexagram_lattice) echo y-02 ;;
    khatam) echo y-03 ;; greek_crosses) echo y-04 ;; celtic_knot) echo y-08 ;; celtic_panels) echo y-06 ;;
    rosette_lattice) echo f-14 ;; hero-rosette) echo t-08 ;; hero-phyllotaxis) echo t-07 ;;
    hero-rose) echo t-13 ;; hero-guilloche) echo t-09 ;; *) echo "" ;;
  esac
}

names=$(ls "$OUT/render/V0f/ember-light" | sed 's/\.pdf$//' | grep -v '^slide-')
COLS="ember-light ember-dark original-light original-dark autumn-light autumn-dark"
for n in $names; do
  rows=""
  for v in V0 V0f V1a V1b V2 V2g; do
    [ -d "$OUT/render/$v" ] || continue
    t=""
    for c in $COLS; do t="$t -label ${v}_${c} $OUT/tiles/${v}__${c}__${n}.png"; done
    # shellcheck disable=SC2086
    montage -font "$FONT" $t -tile 6x -geometry 220x220+3+3 -pointsize 11 -background '#d8d4cc' "$OUT/tmp/row-$v.png"
    rows="$rows $OUT/tmp/row-$v.png"
  done
  g=""
  for v in V3a V3b V3c V4; do
    [ -d "$OUT/render/$v" ] || continue
    for c in $(ls "$OUT/render/$v"); do g="$g -label ${v}_${c} $OUT/tiles/${v}__${c}__${n}.png"; done
  done
  # shellcheck disable=SC2086
  magick $rows -append "$OUT/tmp/grid.png"
  # shellcheck disable=SC2086
  [ -n "$g" ] && montage -font "$FONT" $g -tile 8x -geometry 165x165+3+3 -pointsize 10 -background '#d8d4cc' "$OUT/tmp/grey.png" && magick "$OUT/tmp/grid.png" "$OUT/tmp/grey.png" -background '#d8d4cc' -gravity west -append "$OUT/tmp/grid.png"
  m=$(mock_of "$n")
  if [ -n "$m" ] && [ -f "$MOCKS/$m.webp" ]; then
    magick -font "$FONT" \( "$MOCKS/$m.webp" -resize 440x440 -background '#d8d4cc' -gravity north -splice 0x24 -pointsize 16 -annotate +0+4 "mock $m" \) "$OUT/tmp/grid.png" -background '#d8d4cc' -gravity north +append \
      -gravity northwest -splice 0x30 -pointsize 20 -annotate +8+4 "$n" "$OUT/sheets/compare__$n.png"
  else
    magick -font "$FONT" "$OUT/tmp/grid.png" -background '#d8d4cc' -gravity northwest -splice 0x30 -pointsize 20 -annotate +8+4 "$n (no mock)" "$OUT/sheets/compare__$n.png"
  fi
  echo "sheet: $OUT/sheets/compare__$n.png"
done
