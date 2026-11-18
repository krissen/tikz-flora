#!/bin/sh
# The floor study of the field scale: how dark each pattern's field reads,
# and whether the panel patterns still lay their panels, as the cell size
# falls and rises (tools/pattern_scale.lua sweep renders the pages).
#
#   tools/pattern-scale-floor.sh OUT VARIANT "KEYS" [FACTORS]
#
# OUT is as for tools/pattern-scale.sh (OUT/bake must hold the baked
# formats). VARIANT names the run, KEYS are key=value pairs for the sweep
# (see pattern_scale.lua; "" for the engine as it is, enabled=false for
# the absolute size, as_field=true to make k the field factor). FACTORS
# are the scale factors (default 0.3 to 2.5). Writes
# OUT/floor/<VARIANT>.tsv:
#
#   variant format layout pattern k drawn darkness coverage
#
# k is the factor asked for, drawn the one the page was drawn at (the
# cells' size over the pattern's own): with the engine's field scale on and
# no as_field, k times the page's field factor.
# darkness is the field's mean ink, 1 - its lightness over the paper's,
# at 150 dpi (a page seen at about its size on a screen or in print);
# coverage the share of its pixels painted at all. The field is the strip
# beside the text (left), or every pixel outside the text block (others).
set -eu
OUT=${1:?usage: tools/pattern-scale-floor.sh OUT VARIANT KEYS [FACTORS]}
V=${2:?usage}
KEYS=${3:-}
FACTORS=${4:-0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 1 1.25 1.5 2 2.5}
DPI=150
T="$OUT/tmp/floor-$V"
mkdir -p "$OUT/floor" "$T"
JOB="$OUT/floor/$V.job"
: > "$JOB"
PATTERNS=$(texlua tools/pattern_scale.lua patterns)
for k in $FACTORS; do
  for p in $PATTERNS; do echo "$V slide169 left $p $k $KEYS" >> "$JOB"; done
  for f in slide169 a4 a5; do
    for p in asanoha celtic_knot sikku_kolam; do echo "$V $f surround $p $k $KEYS" >> "$JOB"; done
  done
  for p in asanoha celtic_knot sikku_kolam; do echo "$V slide43 centered $p $k $KEYS" >> "$JOB"; done
done
texlua tools/pattern_scale.lua sweep "$OUT/bake" "$OUT/floor/render" "$JOB"

TSV="$OUT/floor/$V.tsv"
printf 'variant\tformat\tlayout\tpattern\tk\tdrawn\tdarkness\tcoverage\n' > "$TSV"
while read -r v f l p k _; do
  base="$OUT/floor/render/$v/${f}__${l}__${p}__$k"
  [ -f "$base.pdf" ] || continue
  pdftocairo -png -singlefile -gray -r $DPI "$base.pdf" "$T/fl"
  # The field's mask, white where the field is: the strip left of the text
  # (less the gap) for left, outside the text block otherwise.
  geo=$(LC_ALL=C awk -v d=$DPI -v l="$l" 'NR == 1 { W = $1; H = $2; s = d / 72; x0 = 1e9; y0 = 1e9; x1 = 0; y1 = 0; next }
    { if ($1 < x0) x0 = $1; if ($2 < y0) y0 = $2; if ($3 > x1) x1 = $3; if ($4 > y1) y1 = $4 }
    END { g = 6
      if (l == "left") printf "rectangle 0,0 %d,%d", (x0 - g) * s, H * s
      else printf "rectangle 0,0 %d,%d rectangle %d,%d %d,%d", W * s, H * s, (x0 - g) * s, (H - y1 - g) * s, (x1 + g) * s, (H - y0 + g) * s }' "$base.text")
  wh=$(magick identify -format '%wx%h' "$T/fl.png")
  if [ "$l" = left ]; then
    magick -size "$wh" xc:black -fill white -draw "$geo" "$T/mask.png"
  else
    r1=${geo%% rectangle *}; r2="rectangle ${geo#* rectangle }"
    magick -size "$wh" xc:black -fill white -draw "$r1" -fill black -draw "$r2" "$T/mask.png"
  fi
  # The paper is the page's lightest grey; ink is darkness against it.
  m=$(magick "$T/fl.png" -format '%[fx:maxima]' info:)
  magick "$T/fl.png" -fx "1 - u / $m" "$T/ink.png"
  md=$(magick "$T/ink.png" "$T/mask.png" -compose multiply -composite -format '%[fx:mean]' info:)
  mm=$(magick "$T/mask.png" -format '%[fx:mean]' info:)
  mc=$(magick "$T/ink.png" -threshold 4% "$T/mask.png" -compose multiply -composite -format '%[fx:mean]' info:)
  stats=$(LC_ALL=C awk -v a="$md" -v b="$mm" -v c="$mc" 'BEGIN { printf "%.4f\t%.4f", a / b, c / b }')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$f" "$l" "$p" "$k" "$(cat "$base.drawn")" "$stats" >> "$TSV"
done < "$JOB"
echo "floor: $TSV"
