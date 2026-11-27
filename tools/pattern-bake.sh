#!/bin/sh
# The baked layouts the pattern sheets read (tools/pattern_roles.lua,
# tools/pattern-touches.sh), in OUT/bake: tex/lorem.tex's spec-N.lua and
# base.pdf, as `just site-bake` bakes them for the mixer, and the 16:9
# slide's spec-slide.lua and slide.pdf (tools/pattern-slide.tex, 160 x 90
# mm). Files already there are kept. Run from the repository root.
#
#   tools/pattern-bake.sh OUT
set -eu
OUT=${1:?usage: tools/pattern-bake.sh OUT}
B="$OUT/bake"
mkdir -p "$B"
TEXINPUTS="./tex//:${TEXINPUTS:-}"
export TEXINPUTS
if [ ! -f "$B/spec-4.lua" ]; then
  for _ in 1 2; do
    FLORA_SPEC_DIR="$B" lualatex -interaction=nonstopmode -halt-on-error -output-directory="$B" \
      -jobname=base "\def\florseed{3}\def\florapages{0}\input{tex/lorem.tex}" > "$B/base.out" \
      || { tail -20 "$B/base.log"; exit 1; }
  done
fi
if [ ! -f "$B/spec-slide.lua" ]; then
  mkdir -p "$OUT/tmp/slide"
  FLORA_SPEC_DIR="$OUT/tmp/slide" lualatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT/tmp/slide" \
    -jobname=slide "\\def\\florapages{0}\\input{tools/pattern-slide.tex}" > "$OUT/tmp/slide/slide.out" \
    || { tail -20 "$OUT/tmp/slide/slide.log"; exit 1; }
  cp "$OUT/tmp/slide/spec-1.lua" "$B/spec-slide.lua"
  cp "$OUT/tmp/slide/slide.pdf" "$B/slide.pdf"
fi
