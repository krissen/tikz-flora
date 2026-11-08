# Upstream update and Beamer integration

Reviewed upstream/main through `7066c8e` (35 commits after `6885979`).
The generic progression API and Beamer's logical-frame model remain appropriate.

## Changes that affect the integration

- **Page cache:** ordinary TeX pages now cache their finished PDF. A Beamer
  adapter must still prepare one logical frame from the union of measured
  overlays, with its stable seed and settings. The engine therefore bypasses
  the ordinary page cache when `render_page` is supplied. Background bands and
  reservations retain their shared wrapper. Cross-run caching of Beamer frames
  should be explicit in the adapter, using its converged geometry and identity.
- **Gold is raster by default:** upstream computes gold relief inside Lua,
  including soft-mask image XObjects. Growth Forms now own those images along
  with their pattern/opacity resources; uncached ordinary painting uses native
  Forms too, avoiding competing page XObject dictionaries. This is independent
  of the optional external Python/Poppler animation cache. `gilt=vector` remains
  available if a theme wants vector-only gold or continuity with an earlier look.
- **Frozen settings:** the adapter should include `gilt`, `gilt_dpi`, `gilt_env`,
  `gilt_look` and `backdrop` in its logical-frame settings/signature and its
  consistency checks. A change between overlays must not silently reuse the
  first overlay's appearance. `colourway` is parsed into existing palette
  settings; its resolved values should participate in that same signature.
- **New geometry and decoration:** frames can use nonlinear maps and draw
  furniture before/after their plants. Progression now records both furniture
  layers and uses the frame's mapping function. Page-space vertical header
  limits remain outer clips for curved frames.
- **Progress notification:** `spec.progress` reports computation progress.
  It is not a growth stage or a replacement for the elapsed-time animation clock.

## Features worth exposing in beamer-floral

1. `backdrop=dark` or a dark hex colour for dark slides, with matching Beamer
   background and text colours. It repaints inks for the backdrop and retains
   the metal colour. Test contrast and links before enabling a dark preset.
2. `colourway` for complete seasonal palettes (spring, summer, autumn, winter)
   and ember/plum/rose alternatives. Keep these as opt-in theme settings.
3. `gilt`, `giltdpi`, `giltenv` and `giltlook` for choosing and tuning the new
   ornament relief. Measure compile cost/PDF size at slide scale before choosing
   Beamer-specific defaults.
4. New title layouts `flank`, `wreath`, `bouquet` and `scrollwork`, as explicit
   title/section-frame choices. They need slide-aspect-ratio and text-protection
   checks; they should not become ordinary content-frame defaults automatically.
5. `floraletters` engraved title lettering. Its ink extent is measured, so it
   can participate in protected title geometry. Check text selection/accessibility
   before replacing regular Beamer titles with outlined lettering.

The npm/TypeScript web engine and site's WebGL/scroll garden are separate web
workflows. They do not require a change to the LuaLaTeX/Beamer architecture.
