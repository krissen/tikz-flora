# Proposed PR: Support external layout integrations and per-page engine tuning

Status: preparation only; do not open until beamer-floral confirms release readiness.

## Draft description

External presentation integrations need control over the text boundaries,
frame-title clearance and plant scale. This adds integration hooks used by
beamer-floral, including body/margin header modes, reserved rectangles,
background bands and validated per-page tune overrides.

An optional Lua `prepare_spec` callback lets adapters replace geometry and
logical seeds after measurement, before diagnostic export and rendering.
Physical page filtering and diagnostic filenames remain unchanged. This is
the engine hook for the adapter-owned overlay work, not a complete overlay
implementation. Callback ordering, export and default behavior have dedicated
regression coverage.

The renderer fits hero blooms into narrow margins, supports running-head
clipping and lowers surround crowns below an inset. Test tooling is shared
between local runs and CI; tuner export excludes internal helpers.

Existing documents retain physical-page seed and one-shot settings semantics.
Visual changes to hero fitting, stem taper and surround composition require
review against the existing article examples as well as presentations.

## Release gates

- Resolve the overlay-stability design with floral: logical frame identity,
  stable geometry and explicit frame-setting lifetime. Preserve article page
  semantics. No new API is agreed yet.
- Complete engine, TeX, distribution and preview checks; record results.
- Floral verifies its final pinned engine revision in CI and isolated
  distribution, including overlay and handout coverage, and confirms readiness.
- Refresh the upstream comparison and revise this description for the final
  implementation before opening the PR.

## Review findings

- README previously omitted the integration interfaces; now documented.
- Reserved rectangles previously painted white over coloured backgrounds.
  They now intersect exclusion clips around the flora only; overlapping
  reservations remain excluded and background bands are preserved.
- New tune parsing/recursive merging/restoration need focused regression
  coverage, beyond existing layout and tuner tests.
- Individual ornament rendering for bullets/dividers remains future work.

## Local validation

- Fast tests and new settings regressions pass; settings tests are included
  in the shared fast group used by CI and the pre-push hook.
- TeX measurement integration passes on TeX Live 2025.
- Reference preview, seed 3/page 2: zero differing pixels at 110 dpi,
  using the existing 1% comparison tolerance.
- Isolated ZIP extraction compiles with TEXINPUTS and FLORA_TUNE unset:
  seven-page example with coverage output. `just` is unavailable locally,
  so the package was assembled using the same recipe inputs in Python.
- Every engine test group passed, including visitor, scene ops and bake.
  The long-running runner exited 2 after the tests because its source was
  edited during execution to add settings to FAST. The final script passes
  `sh -n` and its fast group exits successfully. Repeat the full runner on
  the frozen release revision before opening the PR.

Coordination: tikz owns the engine; floral owns Beamer integration,
distribution and announcement. Direct session messages are available;
`latex/floral-review` is the shared channel reference.
