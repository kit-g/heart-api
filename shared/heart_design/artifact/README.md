Heart is a workout log, the app Heart of Yours: an iOS and Android app, a website, and cards an
assistant shows when it reads someone's training. Every surface wears one of four presets, and
each preset is a light and a dark palette of the same eleven colors. A person picks the preset
in the app. Ink is the house style: the website, the blog and anything shown to someone who
hasn't picked wear it.

## The presets

| Preset  | Theme ids                       | Character                                                                 | Faces                                     |
|---------|---------------------------------|---------------------------------------------------------------------------|-------------------------------------------|
| Ink     | `ink-light`, `ink-dark`         | Paper and ink, cobalt accent, light-first. The house style.               | IBM Plex Sans; Literata for titles        |
| Forge   | `forge-light`, `forge-dark`     | Volt on green-black, dark-first.                                          | Onest; Unbounded for headlines            |
| Utility | `utility-light`, `utility-dark` | The calm tool: cool neutrals, forest green.                               | Golos Text for everything                 |
| Ember   | `ember-light`, `ember-dark`     | Heat: true orange on warm neutrals, amber in the dark.                    | Rubik for everything                      |

Use one preset per screen. Never mix two presets' colors in one view; the only place several
appear together is a preset picker or a showcase of the presets themselves.

## Color

- Build every screen from the eleven tokens: `ground`, `surface`, `fill`, `ink`, `muted`,
  `faint`, `border`, `accent`, `on-accent`, `accent-ink`, `destructive`. `on-destructive` is
  derived (`surface` in light, `on-accent` in dark). Never add a twelfth color.
- Light palettes are white-grounded. `ground` and `surface` are both white; `border` separates a
  card from the page. Never darken the ground to make contrast. `fill` is the one tone below the
  ground, for inputs, chips and quiet buttons.
- `accent` is a fill: primary buttons, completion marks, a selected chip. Text, lines and chart
  marks in the accent hue use `accent-ink`, which stays legible on `ground` (on a light ground it
  is darker than `accent`). Text on an `accent` fill is `on-accent`.
- Body text is `ink`; metadata and captions are `muted`; disabled and pending things are
  `faint`, which is never used for text that must be read.
- `destructive` is only for danger: deleting, discarding, errors. Every preset keeps it clear of
  its accent, so orange or green can never read as danger.
- `ink` and `muted` hold at least 7:1 and 4.5:1 on `ground` in all eight themes, and `accent-ink`
  holds 4.5:1. Keep them there when tuning a value.

## Type

- Each preset has a text face for everything that reads, a title face for page and dialog titles,
  and a display face for headlines and numbers worth a shout. Ink titles in Literata; Forge
  headlines in Unbounded, which runs wide, so its page title is smaller (26px against Ink's
  30px). Utility and Ember carry everything in one family.
- The faces come from Google Fonts. Always name a fallback: Georgia for Literata, the system
  sans for the rest.
- On cards: the title at 17px, 600 (`ink-card-title`); a hero stat at 17px, 700 in
  `accent-ink`; rows and notes at 13px (`ink-card-body`); the label under a stat at 10px, 1.5px
  letter-spacing, uppercase, in `muted` (`ink-card-label`). Numbers that line up use tabular
  figures.

## Shape

- Corners: `radius-control` (8px) on buttons, inputs and chips; `radius-card` (12px) on cards,
  sheets and dialogs. No pills.
- No shadows. A card is a `surface` with a 1px `border`; a hairline (`border`, 1px) divides a
  card's head from its list.

## Words

- Plain, humble, friendly and true. Say what the thing does; no hype, and no comparing Heart
  down to other apps.
- Health data stays on the phone, and the copy says so plainly: "your health data stays on your
  phone".
- An estimate says it is one: calories read "Calories, estimated", never as a measurement.
- Numbers come in the person's own units and locale; a workout's own words (its name, notes)
  are shown as they were typed.

## Iconography

The mark is a plain heart (`assets/Logos`): dark on light grounds, light on dark grounds, never
recolored, never outlined. No icon set is part of this system yet.

## Using it

The tokens live in `shared/heart_design/tokens.json` in the heart-api repository; the app, the
site, the blog and the assistant cards are generated from that file, and so is this system. On
the web, `tokens.css` sets Ink on `:root`; an element picks a preset with
`data-preset="forge|ink|utility|ember"` and pins its brightness with
`data-theme="light|dark"`.
