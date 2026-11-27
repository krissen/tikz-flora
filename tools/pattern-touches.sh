#!/bin/sh
# Sheets of the pattern touches (lua/flora/pattern_touches.lua's settings
# glint, herogilding, deviant and stray): the variants of
# tools/pattern_variants.lua that carry a `set`, rendered by
# tools/pattern_roles.lua, each sheet one labelled image per question.
#
#   tools/pattern-touches.sh OUT SET
#
# SET is one of:
#   gold       where the gold lies, per pattern: today's field, then
#              glint=on, core, cells, knobs and herogilding=on side by side, the
#              field and the hero, on paper and on the dark backdrop
#   deviant    one cell turned and in another colour, per pattern: three
#              seeds, each the whole 16:9 page and a close-up, off and on
#   stray      one cell come loose with a dotted path back, as deviant
#   perimeter  the keys in a 12 mm band round the paper, per pattern: a
#              corner and a side in close-up, off and each key on
#   inventory  inventory.tsv: what each pattern takes, one pattern a row
#
# Writes OUT/sheets/<set>__<pattern>.png. Under each tile: the gold's share
# of the field's ink (pixels at 50 dpi whose alpha is over a half, the gold
# painted again as pure magenta, probe/*.pdf) and the places the touches
# laid. OUT/render/SET/touches.tsv has each page's numbers and log. OUT/bake
# holds the baked layouts (tools/pattern-bake.sh). PATTERN_TOUCHES_SHEETS_ONLY=1
# lays out sheets from an earlier render. Needs lualatex, pdftocairo and
# ImageMagick. Run from the repository root.
set -eu
LC_ALL=C
export LC_ALL
OUT=${1:?usage: tools/pattern-touches.sh OUT SET}
SET=${2:?usage: tools/pattern-touches.sh OUT SET}
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
DARK="#0a1014"
DD=150
SD=300
R="$OUT/render/$SET"
T="$OUT/tmp"
case "$SET" in gold | deviant | stray | perimeter | inventory) ;; *) echo "unknown set $SET" >&2; exit 2 ;; esac
mkdir -p "$R" "$OUT/sheets" "$T"
tools/pattern-bake.sh "$OUT"

if [ -z "${PATTERN_TOUCHES_SHEETS_ONLY:-}" ]; then
  rm -rf "${R:?}"
  mkdir -p "$R"
  : > "$R/roles.tsv"
  printf 'variant\tbackdrop\tpattern\tseed\tplaces\tspacing_mm\twidth_mm\theight_mm\tfocus_x_mm\tfocus_y_mm\tdeviants\tloose\troles\tlog\n' > "$R/touches.tsv"
  texlua tools/pattern_roles.lua "$OUT/bake" "$R" tools/pattern_variants.lua "set:$SET"
fi

for p in 3 4; do
  [ -f "$OUT/bake/text-$p-$DD.png" ] || pdftocairo -png -singlefile -r $DD -f $p -l $p "$OUT/bake/base.pdf" "$OUT/bake/text-$p-$DD"
done
for d in 100 "$SD"; do
  [ -f "$OUT/bake/text-slide-$d.png" ] || pdftocairo -png -singlefile -r $d "$OUT/bake/slide.pdf" "$OUT/bake/text-slide-$d"
done

# compose PDF TEXT BACKDROP OUT DPI: the page as the mixer shows it.
compose() {
  if [ "$3" = dark ]; then
    pdftocairo -png -transp -singlefile -r "$5" "$1" "$T/c"
    magick -size "$(magick identify -format '%wx%h' "$T/c.png")" "xc:$DARK" "$T/c.png" -compose over -composite \
      \( "$2" -negate \) -compose screen -composite "$4"
  else
    pdftocairo -png -singlefile -r "$5" "$1" "$T/c"
    magick "$T/c.png" "$2" -compose multiply -composite "$4"
  fi
}

# measure PROBE.pdf: prints the ink's share of the page in percent and sets
# GOLD to the gold's share of the ink.
measure() {
  pdftocairo -png -transp -singlefile -r 50 "$1" "$T/p"
  magick "$T/p.png" -alpha extract -threshold 50% "$T/ink.png"
  magick "$T/p.png" -alpha off -fuzz 25% -fill red -opaque '#ff00ff' -fuzz 0% -fill black +opaque red -fill white -opaque red -colorspace Gray "$T/mag.png"
  frac=$(magick "$T/ink.png" -format '%[fx:mean]' info:)
  g=$(magick "$T/ink.png" "$T/mag.png" -compose multiply -composite -format '%[fx:mean]' info:)
  GOLD=$(awk -v i="$frac" -v g="$g" 'BEGIN { if (i > 0) printf "%.1f", 100 * g / i; else print "0.0" }')
  awk -v i="$frac" 'BEGIN { printf "%.1f\n", 100 * i }'
}

# share PROBE.pdf: the gold's share of the ink, in percent. The ink is the
# pixels more than half opaque; the gold those of them that are magenta.
share() {
  measure "$1" > /dev/null
  echo "$GOLD"
}

# tsv VARIANT BACKDROP NAME COLUMN: a field of touches.tsv.
tsv() {
  awk -F'\t' -v v="$1" -v b="$2" -v n="$3" -v c="$4" '$1 == v && $2 == b && $3 == n { print $c }' "$R/touches.tsv"
}

# caption IN OUT TEXT: the tile with its label under it.
caption() {
  magick "$1" -gravity south -background '#d8d4cc' -splice 0x40 -font "$FONT" -pointsize 13 -fill '#101010' -annotate +0+3 "$3" "$2"
}

# The mixer's page 4 field (a 60 mm square, 4 mm in and 40 mm down) and
# page 3's hero (the 70 mm square at the top right), at DD dpi.
px=$(awk "BEGIN { print int(60 / 25.4 * $DD) }")
ox=$(awk "BEGIN { print int(4 / 25.4 * $DD) }")
oy=$(awk "BEGIN { print int(40 / 25.4 * $DD) }")
hx=$(awk "BEGIN { print int((210 - 70) / 25.4 * $DD) }")
hp=$(awk "BEGIN { print int(70 / 25.4 * $DD) }")

# The patterns of a variant: its field pages, no hero or slide.
patterns_of() {
  # The names are the tool's own renders, plain ASCII.
  # shellcheck disable=SC2012
  ls "$R/$1/light" | sed 's/\.pdf$//' | grep -v -e '^slide-' -e '^hero-' -e '^probe$'
}

sheet_gold() {
  for pat in $(patterns_of gold-off); do
    rows=""
    for bd in light dark; do
      for kind in field hero; do
        row=""
        for g in off on core cells knobs hero; do
          v="gold-$g"
          t="$T/tile-$kind-$bd-$g.png"
          if [ "$kind" = field ]; then
            compose "$R/$v/$bd/$pat.pdf" "$OUT/bake/text-4-$DD.png" "$bd" "$T/full.png" $DD
            magick "$T/full.png" -crop "${px}x${px}+${ox}+${oy}" +repage -resize 300x300 "$t"
            page=$pat
          else
            compose "$R/$v/$bd/hero-rosette-$pat.pdf" "$OUT/bake/text-3-$DD.png" "$bd" "$T/full.png" $DD
            magick "$T/full.png" -crop "${hp}x${hp}+${hx}+0" +repage -resize 300x300 "$t"
            page=hero-rosette-$pat
          fi
          places=$(tsv "$v" "$bd" "$page" 5)
          s=$(share "$R/$v/light/probe/$page.pdf")
          label=$g
          case "$g" in
            off) label="today" ;; on) label="glint=on" ;; hero) label="herogilding=on" ;; *) label="glint=$g" ;;
          esac
          [ "$kind" = hero ] && label="$label, hero"
          caption "$t" "$T/cap-$kind-$bd-$g.png" "$label\\ngold ${s}% of the ink, ${places:--} places"
          row="$row $T/cap-$kind-$bd-$g.png"
        done
        # shellcheck disable=SC2086
        magick $row +append "$T/row-$kind-$bd.png"
        rows="$rows $T/row-$kind-$bd.png"
      done
    done
    # shellcheck disable=SC2086
    magick $rows -append -gravity northwest -background '#d8d4cc' -splice 0x34 -font "$FONT" -pointsize 20 -annotate +8+6 "$pat: where the gold lies (paper above, dark backdrop below; the field, then the hero)" "$OUT/sheets/gold__$pat.png"
    echo "sheet: $OUT/sheets/gold__$pat.png"
  done
}

# One variant's slide in whole (100 dpi) and a close-up of mm square about
# the first deviant or stray plate of the "on" row (300 dpi).
sheet_one() {
  key=$1
  mm=$2
  for pat in $(patterns_of "$key-on-11"); do
    rows=""
    for seed in 11 12 13; do
      on="$key-on-$seed"
      off="$key-off-$seed"
      W=$(tsv "$on" light "slide-$pat" 7)
      H=$(tsv "$on" light "slide-$pat" 8)
      fx=$(tsv "$on" light "slide-$pat" 9)
      fy=$(tsv "$on" light "slide-$pat" 10)
      row=""
      # The page off, on and, for deviant, with three.
      whole="$off $on"
      [ "$key" = deviant ] && whole="$whole $key-3-$seed"
      for v in $whole; do
        compose "$R/$v/light/slide-$pat.pdf" "$OUT/bake/text-slide-100.png" light "$T/s.png" 100
        magick "$T/s.png" -resize 560x "$T/whole.png"
        if [ "$v" = "$off" ]; then
          caption "$T/whole.png" "$T/w-$v.png" "seed $seed, off"
        else
          cnt=$(tsv "$v" light "slide-$pat" 11)
          st=$(tsv "$v" light "slide-$pat" 12)
          lg=$(tsv "$v" light "slide-$pat" 14 | cut -c1-70)
          caption "$T/whole.png" "$T/w-$v.png" "seed $seed, ${v%-*}: $cnt turned, $st stray  $lg"
        fi
        row="$row $T/w-$v.png"
      done
      if [ -n "$fx" ]; then
        cx=$(awk -v f="$fx" -v m="$mm" -v w="$W" -v d=$SD 'BEGIN { x = f - m / 2; if (x < 0) x = 0; if (x > w - m) x = w - m; print int(x / 25.4 * d) }')
        cy=$(awk -v f="$fy" -v m="$mm" -v h="$H" -v d=$SD 'BEGIN { y = h - f - m / 2; if (y < 0) y = 0; if (y > h - m) y = h - m; print int(y / 25.4 * d) }')
        cp=$(awk -v m="$mm" -v d=$SD 'BEGIN { print int(m / 25.4 * d) }')
        for v in "$off" "$on"; do
          compose "$R/$v/light/slide-$pat.pdf" "$OUT/bake/text-slide-$SD.png" light "$T/s.png" $SD
          magick "$T/s.png" -crop "${cp}x${cp}+${cx}+${cy}" +repage -resize 400x400 "$T/close.png"
          caption "$T/close.png" "$T/c-$v.png" "close-up, ${mm} mm, $( [ "$v" = "$on" ] && echo on || echo off )"
          row="$row $T/c-$v.png"
        done
      fi
      # shellcheck disable=SC2086
      magick $row +append "$T/row-$seed.png"
      rows="$rows $T/row-$seed.png"
    done
    # shellcheck disable=SC2086
    magick $rows -append -gravity northwest -background '#d8d4cc' -splice 0x34 -font "$FONT" -pointsize 20 -annotate +8+6 "$pat: $key, three seeds (the 16:9 page, then a close-up)" "$OUT/sheets/${key}__$pat.png"
    echo "sheet: $OUT/sheets/${key}__$pat.png"
  done
}

sheet_perimeter() {
  cm=60
  cp=$(awk "BEGIN { print int($cm / 25.4 * $DD) }")
  for pat in $(patterns_of perimeter-off); do
    corner=""
    side=""
    for k in off glint knobs cells deviant deviant3 stray; do
      v="perimeter-$k"
      compose "$R/$v/light/$pat.pdf" "$OUT/bake/text-4-$DD.png" light "$T/full.png" $DD
      places=$(tsv "$v" light "$pat" 5)
      devs=$(tsv "$v" light "$pat" 11)
      stray=$(tsv "$v" light "$pat" 12)
      s=$(share "$R/$v/light/probe/$pat.pdf")
      note="gold ${s}% of the ink, ${places:--} places"
      [ "$k" = deviant ] && note="$devs turned (on)"
      [ "$k" = deviant3 ] && note="$devs turned (3)"
      [ "$k" = stray ] && note="$stray stray"
      # The corner at the top left; the side, the left side's middle, or
      # for deviant and stray the cm mm round the first one's place.
      magick "$T/full.png" -crop "${cp}x${cp}+0+0" +repage -resize 300x300 "$T/c.png"
      caption "$T/c.png" "$T/pc-$k.png" "$k, corner\\n$note"
      fx=$(tsv "$v" light "$pat" 9)
      fy=$(tsv "$v" light "$pat" 10)
      H=$(tsv "$v" light "$pat" 8)
      W=$(tsv "$v" light "$pat" 7)
      label="side"
      if [ -n "$fx" ]; then
        label="close-up at the one"
        cx=$(awk -v f="$fx" -v m="$cm" -v w="$W" -v d=$DD 'BEGIN { x = f - m / 2; if (x < 0) x = 0; if (x > w - m) x = w - m; print int(x / 25.4 * d) }')
        cy=$(awk -v f="$fy" -v m="$cm" -v h="$H" -v d=$DD 'BEGIN { y = h - f - m / 2; if (y < 0) y = 0; if (y > h - m) y = h - m; print int(y / 25.4 * d) }')
      else
        cx=0
        cy=$(awk -v h="$H" -v m="$cm" -v d=$DD 'BEGIN { print int((h - m) / 2 / 25.4 * d) }')
      fi
      magick "$T/full.png" -crop "${cp}x${cp}+${cx}+${cy}" +repage -resize 300x300 "$T/s.png"
      caption "$T/s.png" "$T/ps-$k.png" "$k, $label\\n$note"
      corner="$corner $T/pc-$k.png"
      side="$side $T/ps-$k.png"
    done
    # shellcheck disable=SC2086
    magick $corner +append "$T/prow1.png"
    # shellcheck disable=SC2086
    magick $side +append "$T/prow2.png"
    magick "$T/prow1.png" "$T/prow2.png" -append -gravity northwest -background '#d8d4cc' -splice 0x34 -font "$FONT" -pointsize 20 -annotate +8+6 "$pat: a 12 mm perimeter band, a corner and a side" "$OUT/sheets/perimeter__$pat.png"
    echo "sheet: $OUT/sheets/perimeter__$pat.png"
  done
}

# The table of what each pattern takes: its roles, the field's ink and the
# gold's share of it (today and with the core gold), and the places each key
# lays, from the inventory variants (one pattern a row).
sheet_inventory() {
  f="$OUT/sheets/inventory.tsv"
  printf 'pattern\troles\tink_pct_of_page\tgold_pct_today\tgold_pct_core\tplaces_core\tplaces_cells\tplaces_knobs\tplaces_on\tdeviants\tloose\tlog\n' > "$f"
  for pat in $(patterns_of inventory-off); do
    pp="$R/inventory-off/light/probe/$pat.pdf"
    measure "$pp" > "$T/ink.txt"
    ink=$(cat "$T/ink.txt")
    today=$GOLD
    measure "$R/inventory-core/light/probe/$pat.pdf" > /dev/null
    core=$GOLD
    log=$( { for k in on core cells knobs deviant stray; do tsv "inventory-$k" light "$pat" 14; done; } | grep . | tr '\n' ' ' | cut -c1-200)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pat" "$(tsv inventory-off light "$pat" 13)" "$ink" "$today" "$core" \
      "$(tsv inventory-core light "$pat" 5)" "$(tsv inventory-cells light "$pat" 5)" "$(tsv inventory-knobs light "$pat" 5)" \
      "$(tsv inventory-on light "$pat" 5)" "$(tsv inventory-deviant light "$pat" 11)" "$(tsv inventory-stray light "$pat" 12)" "$log" >> "$f"
  done
  echo "table: $f"
}

case "$SET" in
  inventory) sheet_inventory ;;
  gold) sheet_gold ;;
  deviant) sheet_one deviant 40 ;;
  stray) sheet_one stray 56 ;;
  perimeter) sheet_perimeter ;;
esac
