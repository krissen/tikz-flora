#!/bin/sh
# Sheets of the pattern variants (tools/pattern_variants.lua, rendered by
# tools/pattern_roles.lua) beside the mocks, and the band probe drawn by
# PDF and by the web renderers (tools/band_probe.lua,
# site/tools/band-probe.mjs).
#
#   tools/pattern-roles.sh OUT MOCKS [BEFORE]
#
# OUT/bake holds the baked layouts: tex/lorem.tex's spec-N.lua and
# base.pdf (as tools/pattern-audit.sh bakes them) and a 160 x 90 mm
# slide's spec-slide.lua and slide.pdf. MOCKS is a folder of the mock
# images (t-03.webp, ...). BEFORE, if given, is a folder of earlier tiles
# named <colourway>-<backdrop>__<pattern>.png, shown as the first row of
# each comparison. Writes OUT/sheets/:
#
#   compare__<pattern>.png   the mock (where one exists), then a 60 mm
#                            square of the field before (BEFORE), now, and
#                            now as lines, for ember, original and autumn
#                            on paper and on the dark backdrop
#   detail__<variant>__<backdrop>.png, slide__...   every pattern
#   lines-widths.png          the lines finish's band characters and widths
#   bands.png                 straps of rising width, and stars_8_4's page,
#                             as PDF and as the web renderers draw them
#
# PATTERN_ROLES_SHEETS_ONLY=1 lays out sheets from an earlier render. Run
# from the repository root.
set -eu
OUT=${1:?usage: tools/pattern-roles.sh OUT MOCKS [BEFORE]}
MOCKS=${2:?usage: tools/pattern-roles.sh OUT MOCKS [BEFORE]}
BEFORE=${3:-}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
DARK="#0a1014"
DD=150
mkdir -p "$OUT/render" "$OUT/sheets" "$OUT/tmp" "$OUT/tiles" "$OUT/band"

if [ -z "${PATTERN_ROLES_SHEETS_ONLY:-}" ]; then
  rm -f "$OUT/render/roles.tsv"
  printf 'variant\tbackdrop\tpattern\tas_is\tground\tsurface\tband\tcore\ta\tb\taccent\tground\tband/surface\ta/surface\tb/surface\ta/b\tband/a\tcore/band\taccent/surface\n' > "$OUT/render/roles.tsv"
  texlua tools/pattern_roles.lua "$OUT/bake" "$OUT/render" tools/pattern_variants.lua
  texlua tools/band_probe.lua "$OUT/band" "$OUT/bake/spec-4.lua"
  node site/tools/band-probe.mjs "$OUT/band/probe.json" "$OUT/band" 0.912 1.824
  node site/tools/band-probe.mjs "$OUT/band/page.json" "$OUT/band" 0.912 1.824
fi

for p in 3 4; do
  [ -f "$OUT/bake/text-$p-$DD.png" ] || pdftocairo -png -singlefile -r $DD -f $p -l $p "$OUT/bake/base.pdf" "$OUT/bake/text-$p-$DD"
done
[ -f "$OUT/bake/text-slide.png" ] || pdftocairo -png -singlefile -r 100 "$OUT/bake/slide.pdf" "$OUT/bake/text-slide"

# compose PDF TEXT BACKDROP OUT DPI: the page as the mixer shows it.
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
hx=$(awk "BEGIN { print int((210 - 70) / 25.4 * $DD) }")
hp=$(awk "BEGIN { print int(70 / 25.4 * $DD) }")

for vdir in "$OUT"/render/*/; do
  v=$(basename "$vdir")
  for bdir in "$vdir"*/; do
    bd=$(basename "$bdir")
    dtiles=""; stiles=""
    for pdf in "$bdir"*.pdf; do
      n=$(basename "$pdf" .pdf)
      t="$OUT/tiles/${v}__${bd}__${n}.png"
      case "$n" in
        hero-*)
          compose "$pdf" "$OUT/bake/text-3-$DD.png" "$bd" "$OUT/tmp/full.png" $DD
          magick "$OUT/tmp/full.png" -crop "${hp}x${hp}+${hx}+0" +repage -resize 420x420 "$t"
          dtiles="$dtiles -label $n $t" ;;
        slide-*)
          compose "$pdf" "$OUT/bake/text-slide.png" "$bd" "$t" 100
          stiles="$stiles -label ${n#slide-} $t" ;;
        *)
          compose "$pdf" "$OUT/bake/text-4-$DD.png" "$bd" "$OUT/tmp/full.png" $DD
          magick "$OUT/tmp/full.png" -crop "${px}x${px}+${ox}+${oy}" +repage -resize 420x420 "$t"
          dtiles="$dtiles -label $n $t" ;;
      esac
    done
    # shellcheck disable=SC2086
    montage -font "$FONT" $dtiles -tile 5x -geometry +5+5 -pointsize 16 -background '#d8d4cc' -title "$v $bd" "$OUT/sheets/detail__${v}__$bd.png"
    if [ -n "$stiles" ]; then
      # shellcheck disable=SC2086
      montage -font "$FONT" $stiles -tile 3x -geometry +5+5 -pointsize 14 -background '#d8d4cc' -title "$v $bd (160 x 90 mm)" "$OUT/sheets/slide__${v}__$bd.png"
    fi
  done
done

mock_of() {
  case "$1" in
    stars_8_4) echo t-03 ;; asanoha) echo t-11 ;; penrose_rhombs) echo t-05 ;; truchet) echo t-06 ;;
    sikku_kolam) echo t-10 ;; overlapping_circles) echo t-01 ;; hexagram_lattice) echo y-02 ;;
    khatam) echo y-03 ;; greek_crosses) echo y-04 ;; celtic_knot) echo y-08 ;; celtic_panels) echo y-06 ;;
    rosette_lattice) echo f-14 ;; hero-rosette) echo t-08 ;; hero-phyllotaxis) echo t-07 ;;
    hero-rose) echo t-13 ;; hero-guilloche) echo t-09 ;; *) echo "" ;;
  esac
}

# A row of tiles: label prefix, then tile paths.
row() {
  out=$1; shift
  # shellcheck disable=SC2068
  montage -font "$FONT" $@ -tile 6x -geometry 220x220+3+3 -pointsize 11 -background '#d8d4cc' "$out"
}

names=$(ls "$OUT/render/original/light" | sed 's/\.pdf$//' | grep -v '^slide-')
for n in $names; do
  rows=""
  if [ -n "$BEFORE" ]; then
    t=""
    for cw in ember original autumn; do for bd in light dark; do
      f="$BEFORE/${cw}-${bd}__$n.png"; [ -f "$f" ] && t="$t -label before_${cw}_${bd} $f"
    done; done
    if [ -n "$t" ]; then row "$OUT/tmp/row-before.png" $t; rows="$rows $OUT/tmp/row-before.png"; fi
  fi
  for kind in "" -lines; do
    t=""
    for cw in ember original autumn; do for bd in light dark; do
      t="$t -label now${kind}_${cw}_${bd} $OUT/tiles/${cw}${kind}__${bd}__$n.png"
    done; done
    row "$OUT/tmp/row-now$kind.png" $t
    rows="$rows $OUT/tmp/row-now$kind.png"
  done
  # shellcheck disable=SC2086
  magick $rows -append "$OUT/tmp/grid.png"
  m=$(mock_of "$n")
  if [ -n "$m" ] && [ -f "$MOCKS/$m.webp" ]; then
    magick -font "$FONT" \( "$MOCKS/$m.webp" -resize 440x440 -background '#d8d4cc' -gravity north -splice 0x24 -pointsize 16 -annotate +0+4 "mock $m" \) "$OUT/tmp/grid.png" -background '#d8d4cc' -gravity north +append \
      -gravity northwest -splice 0x30 -pointsize 20 -annotate +8+4 "$n" "$OUT/sheets/compare__$n.png"
  else
    magick -font "$FONT" "$OUT/tmp/grid.png" -background '#d8d4cc' -gravity northwest -splice 0x30 -pointsize 20 -annotate +8+4 "$n (no mock)" "$OUT/sheets/compare__$n.png"
  fi
done

# The lines finish's characters and widths.
t=""
for n in $names; do
  for v in lines-line lines-line-1.5 lines-strap lines-strap-1.5; do t="$t -label ${n}_${v} $OUT/tiles/${v}__light__$n.png"; done
done
# shellcheck disable=SC2086
montage -font "$FONT" $t -tile 8x -geometry 200x200+3+3 -pointsize 10 -background '#d8d4cc' -title "lines: bands=line and strap, bandwidth 1 and 1.5" "$OUT/sheets/lines-widths.png"

# The band probe and stars_8_4's page, as PDF and as the web draws them.
cd "$OUT/band"
for s in 0.912 1.824; do
  for f in probe page; do
    w=$(magick identify -format '%w' "$f-webgl-$s.png"); h=$(magick identify -format '%h' "$f-webgl-$s.png")
    pdftocairo -png -singlefile -scale-to-x "$w" -scale-to-y "$h" "$f.pdf" "$f-pdf-$s"
  done
done
for f in probe page; do
  for s in 0.912 1.824; do
    for r in pdf webgl canvas2d; do
      # The web pictures are transparent where nothing is painted; the
      # mixer shows them over the paper.
      magick "$f-$r-$s.png" -background '#f9f8f4' -flatten "$f-$r-$s.png"
      if [ $f = probe ]; then
        magick "$f-$r-$s.png" -filter point -resize "$(awk "BEGIN{print int(400/$s)}")%" "$OUT/tmp/b.png"
      else
        # The page's top left field, 60 x 60 bp, enlarged as the probe is.
        cw=$(awk "BEGIN{print int(60*$s)}"); cx=$(awk "BEGIN{print int(10*$s)}"); cy=$(awk "BEGIN{print int(110*$s)}")
        magick "$f-$r-$s.png" -crop "${cw}x${cw}+${cx}+${cy}" +repage -filter point -resize "$(awk "BEGIN{print int(400/$s)}")%" "$OUT/tmp/b.png"
      fi
      magick "$OUT/tmp/b.png" -font "$FONT" -gravity north -background '#ddd' -splice 0x20 -pointsize 14 -annotate +0+2 "$f  $r  $s px/bp" "$OUT/tmp/b-$f-$r-$s.png"
    done
    magick "$OUT/tmp/b-$f-pdf-$s.png" "$OUT/tmp/b-$f-webgl-$s.png" "$OUT/tmp/b-$f-canvas2d-$s.png" +append "$OUT/tmp/b-$f-$s.png"
  done
done
magick "$OUT/tmp/b-probe-0.912.png" "$OUT/tmp/b-probe-1.824.png" "$OUT/tmp/b-page-0.912.png" "$OUT/tmp/b-page-1.824.png" -background '#d8d4cc' -append "$OUT/sheets/bands.png"
echo "sheets: $OUT/sheets"
