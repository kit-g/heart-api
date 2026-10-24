# heart_design

Heart's design tokens: four presets (Forge, Ink, Utility, Ember), each with a light and a dark
palette of eleven colors, its faces and headline, plus the control and card radii.

`tokens.json` is the one source of truth. Everything else is generated from it:

| Output                         | For                                                                                   |
|--------------------------------|---------------------------------------------------------------------------------------|
| `lib/src/presets.g.dart`       | the app (`Preset`, `Palette`, `controlRadius`, `cardRadius`) and `tokensCss` for the MCP cards |
| `../../site/assets/tokens.css` | the site and the blog                                                                  |

The Heart Design System artifact, which replaces the Claude Design project, is built from the
same file: `dart run tool/design_system.dart OUT_DIR [REF]` writes its `tokens.json` beside the
pages kept in `artifact/` (its README, the logos' notes, the cover), ready to publish to it. The
logos are uploads the artifact already holds.

Change a token in `tokens.json`, run `make design` from the repo root, and commit the generated
files with it. The tests fail when they are stale, and they check that every palette keeps its
text legible on its ground (WCAG AA for muted and accentInk).

## The rules

- Light palettes are white-grounded: surfaces stay white, borders do the separating, and `fill`
  is the only tone below the ground.
- The accent is a fill. Text and lines in the accent hue use `accentInk`.
- No shadows. 8px controls, 12px cards, no pills.
- No twelfth color: a surface that seems to need one uses the eleven it has.

## Using it

The app pulls this package from git, like `heart_models`:

```yaml
heart_design:
  git:
    url: https://github.com/kit-g/heart-api.git
    path: shared/heart_design
```

Colors are ARGB integers, what a Flutter `Color` takes; the package itself has no Flutter
dependency. Versioning follows the repo's rules for shared packages: bump `version` and prepend
to `CHANGELOG.md` in the same PR, and keep changes additive.

On the web, `tokens.css` sets Ink on `:root`. An element picks another preset with
`data-preset="forge|ink|utility|ember"`, and `data-theme="light|dark"` on `:root` or on that
element pins its brightness instead of following the OS.
