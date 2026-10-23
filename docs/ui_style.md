# Psykinetic UI style

How the game's screens and panels look, so ones made months apart by different trees sit
together. The `ui` tree owns this page and the shared theme (`render/ui_theme.tres`,
`UiTheme`); each screen's owner (CLAUDE.md) owns what it does. Jeff's charter for the
interface (docs/roadmap.md, `ui` row): as diegetic as possible, readable at a glance,
consistent everywhere, scalable for different screens.

## Principles

- **No bars.** Health, stamina and mana are never drawn as bars or numbers on the HUD for
  their own sake: the body shows them (its stance, its wounds), the light and the sound
  do the rest. A screen exists only where the game needs one (a pack, a shop, a map, the
  options). This is Jeff's rule: ask him before breaking it.
- **The world stays in view.** Panels are small, sit at the edges, and are translucent
  enough that the room shows through. Nothing but the first-run screen covers the world.
- **One voice.** Every screen takes its fonts, colours, spacing and panel style from the
  shared theme; a panel never sets its own. A colour that means something (a named item, a
  party line, a refusal) is a theme colour with that name, used for that and nothing else.
- **Readable at a glance.** Text over the world has a dark outline, never a box. Text in a
  panel is bone on dark. Body text is 38 canvas units (19 px at 1080p; the Alegreya faces
  have a small x-height, so they need more than the engine's font did) and nothing a
  player must read is below 30.
- **The same on every screen.** Sizes are in the HUD's canvas units (3840 x 2160; the window
  stretch scales it, so a unit is half a pixel at 1080p). The theme's scale (step 6) will
  multiply them for small screens and large text.

## Fonts

Two faces, both Alegreya by Juan Pablo del Peral, Huerta Tipográfica (SIL Open Font
Licence 1.1; `art/fonts/`, recorded in THIRD_PARTY.md):

| Face | Use |
|------|-----|
| **Alegreya** (serif) | titles, headings, names (people, places, named things), speech bubbles, the map's labels: what the world says |
| **Alegreya Sans** | everything else: body text, control labels, hints, the HUD line, chat, numbers |

Why: a calligraphic serif reads at small sizes, suits the saga tone (grim, fated, loyal)
without looking like a scroll, and its angular strokes sit with the faceted art; its
matched sans keeps the controls plain. Bold for a name that must be found (the compass's N,
a speaker), never for whole sentences. No italics, no small caps, no third face.

Type scale, in canvas units:

| Role | Size | Face |
|------|------|------|
| title (a screen's name) | 56 | Alegreya, bold |
| heading (a section, a panel's title) | 44 | Alegreya |
| hud (the one line over the world, outlined) | 44 | Alegreya Sans |
| body (controls, lines, hints) | 38 | Alegreya Sans |
| caption (an icon's name, a unit, a note) | 30 | Alegreya Sans |
| small (a slot's R and L, a map label) | 24 | Alegreya Sans |
| speech (bubbles, laid out at 64 px a tile) | 17 then scaled with the zoom | Alegreya |

## Colours

Every colour is a swatch of the art palette (docs/art_style.md, `art/kit/palette.png`), so
the interface is made of the same stone, wood, leather and brass as the world. Named in
the theme (type `Psykinetic`) and read by code through `UiTheme.color(name)`.

| Name | Swatch | Use |
|------|--------|-----|
| `backing` | earth darkest `#2c2418` at 0.86 | a panel's fill |
| `backing_deep` | `#1e1812` (earth darkest, darker) at 0.95 | a slot, a text field: an inset |
| `edge` | leather `#7a6e58` at 0.9 | a panel's and a slot's border |
| `text` | bone `#f4efe6` at 0.95 | words |
| `text_dim` | cloth `#c2b8a0` at 0.9 | a note, a unit, a disabled control, a time |
| `brass` | bronze `#c79a55` | a key in the hints, a hand slot's edge, the focused control, a price, gold |
| `brass_bright` | flame `#ffd27a` | a named thing (items, decision 365), a speaker's name |
| `rust` | ember `#e8792e` | a thing kept from its namer (decision 370), a refusal's or a failure's words (red text is hard to read on the backing) |
| `alarm` | banner red `#b8322a` | a mark, never words: the compass's N |
| `party` | magic teal `#3fb8a8` | party chat (it crosses zones) |
| `aloud` | bone `#f4efe6` | a line said aloud |
| `friend` | foliage `#8fa857` | a companion's or a resident's mark |
| `water` | water shallow `#5f8a8c` | the maps' water |
| `outline` | `#1a1410` at 0.9 | the outline of text over the world |

Nothing near pure black or white (the art rule): the darkest is `#1a1410`, the lightest bone.
Colour-blind safety (step 6): nothing is told by hue alone; a named thing is also gilded
in its name, a party line is also marked.

## Spacing and panels

Base unit 8. Panel padding 24; between rows 12; between sections 24; a slot 132 square with
10 between; a corner radius of 6 (a chamfer's worth, not a pill); borders 2, a hand slot's
3. A panel keeps 40 from the screen's edge. Panels and their places:

| Where | What |
|-------|------|
| top left | the HUD line (the player's state in words, never a number but HP for now; outlined text, no box), the controls list under it (H), the debug text (F3) |
| top right | the compass, the place you stand in to its left; under it the corner map |
| bottom right | the pack, with the open chest or companion above it; the gold over its corner; a shop to its left |
| bottom left | the talk box: what was said, fading unless pinned (Tab), the chat box inside it |
| top middle | builder mode's status and box |
| middle | the options (O), the big map (M), her card page (C), the town sheet (N), the game menu (Esc; the game never pauses), the connect screen and the main menu |

Controls: a button is a flat `edge`-bordered box in `backing_deep` that goes `brass` at the
border when hovered or focused; a slider's track is `edge`, its grabber `brass`; a text
field is `backing_deep` with an `edge` border, `brass` while it has focus; a drop-down is a
button. Tooltips are a panel in caption text. UI sounds are sound's (UiSounds hooks every
button and slider; decision 395): a panel adds none of its own.

## What a screen may do with the theme

A panel sets no font, size, colour or style of its own: it uses the theme's types (`Label`,
`Button`, `PanelContainer`...) and its named variations (`Title`, `Heading`, `Caption`,
`Small`, `Hud`, `Outlined`, `Inset`, `HandSlot`...). A link is a `LinkButton` (brass); a `ScrollContainer` is an inset with a brass scroll bar. Something drawn by hand (the compass, the maps, the speech
bubbles) reads its colours and fonts from `UiTheme`. A new meaning needs a new named colour
here first.

## Screens today (the audit of 2026-10-17)

Before shots in `docs/ui/shots/before/`, after shots (decision 401, the theme) beside
them in `after/` (1280 x 720, the 3D view, the castle). What was found, screen by screen,
and the inconsistencies the theme settles:

- **HUD line** (`main.tscn` `HUD/Label`): the engine's default font at the default theme
  scale (48 units), white, no outline, so it fades over bright stone. Its tick count and
  "host" are debug text in a player's eye line. *Theme: body size, outlined; what it shows is
  Main's (the tick and mode are to move into F3's debug text in step 2, with the owner).*
- **Hints** (H, `render/hint_panel.gd`): 30-unit text, keys in a warm yellow, on a cool
  near-black box, radius 16. The closest to the style; its colours are its own constants.
- **Options** (O, `render/options_panel.gd`): styled "as the pack panel" by copying its
  constants; 26-unit text (the smallest in the game), the engine's default slider and
  drop-down (grey, round grabber) against the dark box. Sections are headings dimmed by
  modulate.
- **Pack and chest** (I, E, `render/pack_panel.gd`): cool near-black backing, radius 16,
  slots with a warm grey edge, hands in brass with R and L; 26-unit text, 20 captions. The
  owner's colours for named and kept things stay as meanings but move onto palette swatches.
  *Step 3 (decision 427): a themed tip on hover (`ItemTip`) and the carried weight.*
- **Shop** (`render/shop_panel.gd`, beside the pack): copies the pack's constants; the
  engine's default Button for Buy. Not shot: it needs a counter in reach (the wilds' shop
  chest is not a `Chest.shop` at a host's start); its look is the pack's.
- **Gold** (over the pack): its own small box with 26-unit brass text.
- **Talk log** (Tab, `render/talk_panel.gd`): a square-cornered black box at 0.7, default
  48-unit text (the biggest in the game after titles), a clock time on every line, three
  line colours of its own (yellow, blue, green). *Step 3 (decision 427) made it one box
  with the chat box, fading unless pinned; shots in `docs/ui/shots/step3/`.*
- **Chat box** (Enter): the engine's default LineEdit, grey on grey, 48-unit text, a
  placeholder a sentence long.
- **Speech bubbles** (`render/speech_bubbles.gd`): dark rounded bubble, light text, a tail;
  its own colours; fits the style but not the palette.
- **Compass** (`render/compass.gd`): dark disc, bone ring, N in red: fits; its own colours.
- **Corner map and big map** (M, `render/minimap.gd`, maps' decision 321): not drawn in
  any shot. Main built the HUD before the level loaded and the map was only rebuilt on a
  zone change or a live reload, so a host's first zone never reached it; maps fixed it the
  same day (Main._ready rebuilds it). Its colours were its own, with the palette for the
  ground.
- **Builder mode** (B, `builder/builder_ui.gd`): 28-unit outlined light-blue status text,
  the engine's default LineEdit, both top-middle; the box's placeholder is a sentence.
  Since 537: an Outlined coordinates line under them ("212, 207      you 210, 205") and
  light-blue Label3D codes over each building ("H3 house"), the tool's own colour, outside
  the colour sets; the cursor hint names a building when nothing else claims the cursor.
- **Debug text** (F3): default 48-unit white text, no outline.
- **First-run screen** (then `net/setup_screen.gd`, now `render/connect_screen.gd`, ConnectScreen): a dark backdrop, the engine's default
  Label, LineEdit and Button; a 66-unit title; the panel has no visible box. Connection
  state and update progress were HUD-line text. *Step 2 (decision 418) replaced it with the
  connect screen, and added the main menu and the pause: shots in `docs/ui/shots/step2/`.*
- **Names over heads** and alert marks (`!`, `?`) are Client3D's world labels (pc-character
  and enemy-ai), not the HUD. A `Label3D` with no font of its own draws in the project
  theme's default face, so they came out in Alegreya Sans with the theme; the outline rule
  comes in step 3 with their owners.
- **The level editor and the world map view** (`editor/`): tools, not the game; left out of
  the theme until the game's screens are done.

Across screens: five text sizes between 20 and 66 for the same kind of text; two blacks
(cool near-black, pure black); corner radii 16, 8 and 0; four separate copies of "the
pack's constants"; and the engine's grey controls wherever a panel did not style one.
