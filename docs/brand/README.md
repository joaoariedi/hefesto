# Hefesto — logo & brand notes

Chosen mark (Aug 2026): **the struck anvil** — a stylised anvil face with a
bolt of current driven through it and a spark thrown upward. Hephaestus recast
for the new fire: the old god shaped bronze with flame and hammer, this one
shapes machines with electricity. The patron fits more literally than it first
appears — in *Iliad* 18 Hephaestus forges automata "with intelligence in their
hearts", which makes him the first builder of thinking machines in the Western
canon.

## Files (delivered as SVG, transparent backgrounds, no font deps)

- `hefesto-icon-light.svg` / `hefesto-icon-dark.svg` / `hefesto-icon-mono.svg` —
  512×512 icon
- `hefesto-banner-light.svg` / `hefesto-banner-dark.svg` — 1280×320 README
  lockup: icon + "Hefesto" wordmark (converted to paths) + tagline
  "A development harness for Claude Code"

All five are built from SVG primitives only — no `<text>`, no `@font-face`, no
`<image>`, no `<script>`, no filters — so GitHub's SVG sanitiser leaves them
intact. Light and dark cuts are geometrically identical and differ only in fill
values, so a palette change is one find-and-replace per file.

## Palette

- Light mode: graphite ink `#2b2f36`, electric cyan accent `#06b6d4`, ember
  `#f97316`, muted tagline `#667085`
- Dark mode (GitHub `#0d1117`): silver ink `#c9d1d9`, lifted cyan `#38bdf8`,
  lifted ember `#fb923c`, muted `#8b949e`
- Mono: single-color `#2b2f36` (recolor freely; silhouette carries the mark)

Cyan carries the concept; ember is secondary and the first thing to drop if a
cut looks busy. Below roughly 48px the ember dot becomes an indistinct speck
while still costing a colour.

## README usage

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/hefesto-banner-dark.svg">
  <img src="docs/brand/hefesto-banner-light.svg" alt="Hefesto" width="800">
</picture>
```

## Regenerating

`hefesto-logo-prompt.txt` is the original brief used to generate the mark —
start there if the logo is ever redesigned or extended (new lockups, merch,
social cards), so variants stay on-concept. It carries the concept, the chosen
mark and its alternates, the palette, the design guidelines, and the
copy-paste generation prompt.

Read **section 9, "Tested and rejected"**, before regenerating. It records what
rendering disproved rather than what reasoning predicted — most importantly
that three concentric arcs radiating from one origin read as the Wi-Fi glyph,
An earlier draft of the brief recommended them and the first generated cuts
carried them at radii 36/68/100; they were removed from all five files on
2026-08-19. Do not reintroduce them in any variant.

The current cuts were generated in a browser session from that brief, not by a
script — there is no `gen_*.py` to re-run. Hand-editing the SVGs is practical:
each icon is under 800 bytes and uses nothing but `path`, `polygon`, `circle`
and `line`.
