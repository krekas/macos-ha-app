# HAApp design system

Apple's look, one accent. Tokens live in `Sources/HAApp/UI/`. Views use
tokens, never raw colors, radii, or durations.

## Theme.swift: accent

- Default `ThemeStore.defaultID = "system"`: the app follows the Mac's accent.
- Brand: `Theme.homeAssistant` (#18BCF2), set as `ThemeStore.brand`. It shows
  while the Mac's accent is Multicolor, and people can pick it in
  Settings > Appearance ("Home Assistant").
- It is a bright blue, so `darkText: true`. Text on an accent fill is
  `Palette.onAccent` (dark ink here), never fixed white.
- `.tint` / `Palette.accent`: fills, toggles, selection, symbols for "on".
- `Palette.accentText`: accent-colored text (deep #0674A6 in light mode,
  light #7DD8F8 in dark mode, stronger shades under Increase Contrast).
  Borderless buttons draw their title in the tint, so give them
  `.tint(Palette.accentText)` (see the menu footer).
- Use brand color sparingly: the icon, "on" states, one hero element.
- Every custom color has light, dark, and two Increase Contrast values
  (`Color(light:dark:highContrastLight:highContrastDark:)`).
- Never copy a semantic color (`.separator` as text, a label color as a fill).

## Grid.swift: spacing

- `Space.xs 4`, `sm 8`, `md 12`, `lg 16`, `xl 20`, `xxl 24`, `section 32`,
  `margin 20`. Every padding and spacing is a `Space` token.
- Mark custom pages and cards with `.gridArea` and `.gridProbe`.
  See the `layout-grid` skill.

## Surfaces.swift: fills and lines

- System materials and `.background` first.
- `Surfaces.hairline`: outline around a swatch or small drawn shape.
- `Surfaces.accentWash`: tint behind accent text, like a tag or value chip.
- `Surfaces.knobShadow`: the shadow under a drawn knob.
- `Surfaces.warning`: unavailable and stale entities (S-008), errors.
- A neutral custom surface is a little translucent; a colored state is opaque.

## Radius.swift: corners

- `xs 6` chips, `sm 8` controls and small fills, `row 10` row hover and
  selection fills, `md 12` cards and previews, `lg 18` widgets, `xl 26`
  floating glass.
- Build shapes with `Radius.shape(Radius.md)` (continuous corners).
- Inner corners are concentric: inner radius = outer radius - inset.

## Layout.swift: fixed sizes

- `menuWidth 320`, `menuMaxHeight 560` (scrolls past it),
  `menuEmptyHeight 200`, `symbolColumn 20` (item symbols, so names line up),
  `settingsWidth 520` (every Settings tab).
- Everything else sizes to its content.

## Motion.swift: animation

- Every animation goes through `Motion`. Reduce Motion is handled there:
  movement becomes a short fade or nothing (`nil`).
- `hover` hover fills. `quick` a light or switch flipping. `ui` row state,
  sections opening. `select` selection moving through a list. `appear` /
  `dismiss` panels and popovers (dismiss is faster). `numberRoll` sensor
  values. `listChange` rows added, removed, reordered. `pulse` the
  "connecting" loop; stop it when `nil`.
- Sensor values: animate the number with `.contentTransition(.numericText())`;
  units ("°C", "W", "%") never animate.
- Search results and switchers do not animate. Speed wins.
- Hover never moves a selection. Only a click or a key does.
- Never animate a view's first layout. Overlays wait one frame, then animate
  opacity, scale, and a few points of travel.

## Controls

- Apple's controls and system button styles (`.borderedProminent`,
  `.borderless`). One primary button per page or card.
- Style with `ButtonStyle` and `ToggleStyle`; never rebuild a control from
  shapes (it loses keyboard, focus, and VoiceOver).
- Custom fonts only for headings; none today. Body stays in the system font.
- Liquid Glass only on floating controls. Leave room around glass for its
  shadow (about 3 times the shadow radius).
- Add a `Components.swift` (hover button style, `.hoverFill`) and an
  `Overlay.swift` (one panel builder) when a story first needs them, and a
  section here for each.
