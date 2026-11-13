#!/bin/sh
# ORDER #10's sheets (tools/edge10_variants.lua rendered into OUT/render10):
# before and after the ground, ends and panels keys, hexagram's star, and
# how khatam's field ends, one question per sheet.
#
#   tools/edge10-sheets.sh OUT MOCKS
set -eu
OUT=${1:?usage: tools/edge10-sheets.sh OUT MOCKS}
MOCKS=${2:?usage: tools/edge10-sheets.sh OUT MOCKS}
RENDER=render10 SHEETS=sheets10 EDGE_SHEETS_LIB=1
. tools/edge-sheets.sh
for p in rosette_lattice sikku_kolam asanoha celtic_knot celtic_panels; do
  case $p in rosette_lattice) m=f-14 ;; sikku_kolam) m=t-10 ;; asanoha) m=t-11 ;; celtic_knot) m=y-08 ;; celtic_panels) m=y-06 ;; esac
  sheet "fore-efter__$p" "$p" "$m" "$p: before (ground in cells, lines cut) and after (the new defaults)" "tsuki-mi ember" \
    "before=Before: ground=cells, ends=cut, panels=off" "after=After: the defaults (ground=auto, ends and panels auto)"
done
sheet "form__hexagram" hexagram_lattice y-02 "hexagram_lattice: how the star is built" "tsuki-mi ember" \
  "hex-today=Today: up triangle field A, down triangle over it field B" "hex-star=Whole star in field A, gaps in field B" \
  "hex-interlace=Two triangles woven as bands, star filled" "hex-weave=Two triangles woven as bands, no fill" \
  "hex-mock=First reading of y-02: whole star" "hex-outline=Whole star in field A on the paper (own proposal)" \
  "hex-measured=As y-02 measures: down triangle on top, thin lines"
sheet "kant__khatam" khatam y-03 "khatam: how its field ends where the pattern ends" "tsuki-mi ember" \
  "khatam2-cells=Today: a square per star" "khatam2-shape=Ends along the stars' outline" "khatam2-panel=A straight panel" \
  "khatam2-inner=Only between stars with neighbours all round" "khatam2-fade=Fades out over the outer stars (own proposal)" \
  "khatam3-mock=As y-03: field between kept stars" \
  "khatam3-mock-any=As y-03: field round every star"
