#!/bin/sh
# Contact sheets of every pattern in every role and palette
# (tools/pattern_audit.lua renders them).
#
#   tools/pattern-audit.sh OUT [ONLY]
#
# Bakes tex/lorem.tex's layouts into OUT/bake as `just site-bake` does for
# the mixer, renders each pattern page into OUT/render/<role>/<palette>/,
# lays each page under the example's text as the mixer shows it (multiplied
# on paper; on the dark backdrop the text turned light and screened over
# the ground) and writes, in OUT/sheets/:
#
#   <role>__<palette>.png      every pattern on that page, labelled
#   detail__<palette>.png      a 60 mm square of each pattern's field on the
#                              opening page, finer, to judge its drawing
#   parity.txt                 pixels that differ between the page built
#                              the mixer's way and the TeX way, per pattern
#
# ONLY is passed to pattern_audit.lua (roles, comma-separated). Needs
# lualatex (TinyTeX as in the justfile), pdftocairo and ImageMagick. Run
# from the repository root.
set -eu
OUT=${1:?usage: tools/pattern-audit.sh OUT [ONLY]}
ONLY=${2:-}
DPI=${PATTERN_AUDIT_DPI:-40}
DETAIL_DPI=${PATTERN_AUDIT_DETAIL_DPI:-150}
DARK="#0a1014" # color.lua's DARK_GROUND
# ImageMagick may know no fonts of its own; the labels need one.
FONT=${PATTERN_AUDIT_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}
mkdir -p "$OUT/bake" "$OUT/render" "$OUT/sheets" "$OUT/tmp"

if [ ! -f "$OUT/bake/spec-4.lua" ]; then
  for _ in 1 2; do
    FLORA_SPEC_DIR="$OUT/bake" lualatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT/bake" \
      -jobname=base "\def\florseed{3}\def\florapages{0}\input{tex/lorem.tex}" > "$OUT/bake/base.out" \
      || { tail -20 "$OUT/bake/base.log"; exit 1; }
  done
fi
# The text of each mixer page, at both resolutions.
for p in 1 2 3 4 6; do
  for d in "$DPI" "$DETAIL_DPI"; do
    [ -f "$OUT/bake/text-$p-$d.png" ] || pdftocairo -png -singlefile -r "$d" -f $p -l $p "$OUT/bake/base.pdf" "$OUT/bake/text-$p-$d"
  done
done

# PATTERN_AUDIT_SHEETS_ONLY=1 lays out sheets from an earlier render.
[ -n "${PATTERN_AUDIT_SHEETS_ONLY:-}" ] || texlua tools/pattern_audit.lua "$OUT/bake" "$OUT/render" "$ONLY"

page_of() {
  case "$1" in
    *-right|hero-*) echo 3 ;;
    *-centered) echo 6 ;;
    *-surround) echo 2 ;;
    *-title) echo 1 ;;
    *) echo 4 ;;
  esac
}

# compose PDF TEXT PALETTE OUT: the page as the mixer shows it.
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

for roledir in "$OUT"/render/*/; do
  role=$(basename "$roledir")
  case "$role" in parity-*) continue ;; esac
  if [ -n "$ONLY" ] && ! printf ',%s,' "$ONLY" | grep -q ",$role,"; then continue; fi
  page=$(page_of "$role")
  for paldir in "$roledir"*/; do
    pal=$(basename "$paldir")
    tiles=""
    for pdf in "$paldir"*.pdf; do
      name=$(basename "$pdf" .pdf)
      png="$OUT/tmp/$role-$pal-$name.png"
      compose "$pdf" "$OUT/bake/text-$page-$DPI.png" "$pal" "$png" "$DPI"
      tiles="$tiles -label $name $png"
    done
    # shellcheck disable=SC2086
    montage -font "$FONT" $tiles -tile 5x -geometry +6+6 -pointsize 13 -background '#d8d4cc' "$OUT/sheets/${role}__${pal}.png"
    echo "sheet: $OUT/sheets/${role}__${pal}.png"
  done
done

# Detail: a 60 mm square of the field in the left margin of the opening
# page (field-left), 15 mm in from the paper's left edge and 40 mm down.
if [ -d "$OUT/render/field-left" ]; then
  px=$(awk "BEGIN { print int(60 / 25.4 * $DETAIL_DPI) }")
  ox=$(awk "BEGIN { print int(4 / 25.4 * $DETAIL_DPI) }")
  oy=$(awk "BEGIN { print int(40 / 25.4 * $DETAIL_DPI) }")
  for paldir in "$OUT"/render/field-left/*/; do
    pal=$(basename "$paldir")
    tiles=""
    for pdf in "$paldir"*.pdf; do
      name=$(basename "$pdf" .pdf)
      png="$OUT/tmp/detail-$pal-$name.png"
      compose "$pdf" "$OUT/bake/text-4-$DETAIL_DPI.png" "$pal" "$OUT/tmp/full.png" "$DETAIL_DPI"
      magick "$OUT/tmp/full.png" -crop "${px}x${px}+${ox}+${oy}" +repage "$png"
      tiles="$tiles -label $name $png"
    done
    # shellcheck disable=SC2086
    montage -font "$FONT" $tiles -tile 5x -geometry +6+6 -pointsize 18 -background '#d8d4cc' "$OUT/sheets/detail__${pal}.png"
    echo "sheet: $OUT/sheets/detail__${pal}.png"
  done
fi

# Parity: the mixer's way against the TeX way, pixel for pixel.
if [ -d "$OUT/render/parity-mixer" ]; then
  : > "$OUT/sheets/parity.txt"
  for pdf in "$OUT"/render/parity-mixer/light/*.pdf; do
    name=$(basename "$pdf" .pdf)
    pdftocairo -png -singlefile -r 72 "$pdf" "$OUT/tmp/pm"
    pdftocairo -png -singlefile -r 72 "$OUT/render/parity-tex/light/$name.pdf" "$OUT/tmp/pt"
    d=$(magick compare -metric AE "$OUT/tmp/pm.png" "$OUT/tmp/pt.png" null: 2>&1 || true)
    printf '%s\t%s\n' "$name" "$d" >> "$OUT/sheets/parity.txt"
  done
  echo "parity: $OUT/sheets/parity.txt"
fi
