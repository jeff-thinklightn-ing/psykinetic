# Lore files

The world's facts in two forms: prose for people under `docs/lore/` (`primer.md`
first; `style.md` for names and how lore is written), and data for code under
`levels/lore/` (shipped with the server and the client, since `levels/*.json` is in
the export filter). The data is the source of truth; the prose describes it.
Decisions 257 (where lore lives, the entry format, shared ids) and 258 (knowledge
levels and the status gate). `tests/lore_test.gd` checks every rule below.

## Files

| File | Entries |
|------|---------|
| `levels/lore/world.json` | the land as a whole (type `world`) |
| `levels/lore/factions.json` | factions and peoples (`faction`, `people`) |
| `levels/lore/regions.json` | regions and the places in them (`region`, `place`) |
| `levels/lore/materials.json` | materials (`material`) |
| `levels/lore/creatures.json` | the land's beasts, wild and hunted (`creature`) |
| `levels/lore/people.json` | named people and named weapons (`person`, `weapon`) |
| `levels/lore/history.json` | things that happened (`event`) |
| `levels/lore/knowers.json` | who knows what: groups and characters (not entries; see below) |
| `levels/lore/names.json` | how things are named: name forms and thing words (not entries; see below) |

Each file is `{"_about": "...", "entries": [...]}`.

## An entry

```json
{
  "id": "goblins",
  "type": "faction",
  "name": "the goblins",
  "status": "draft",
  "source": "roadmap",
  "summary": "One sentence that is true.",
  "aka": [],
  "relations": [{"to": "town", "kind": "enemy"}],
  "tags": ["raiders"],
  "facts": [ ... ]
}
```

- `id`: lower_snake_case and unique across all the lore files. These ids are shared
  with other files. A `faction` id is a key of `levels/factions.json` (maps owns that
  file: colour, monsters, hostile_to; lore adds no fields to it). A new faction stays
  out of `agreed` until maps has added its key. A `region` id is what a level's
  `region` names, and a key of `levels/climates.json` (environment owns it and its
  weather numbers; a region that isn't `asked` needs a key there).
- `type`: world, faction, people, region, place, material, creature, person, weapon, event.
- `status`: `agreed` (Jeff said it, word for word, or it is already in the game;
  Dire plays and tests, and his ideas go to Jeff, who decides: Jeff, 2026-10-17),
  `draft` (written from what is decided but not yet confirmed), `asked` (an open
  question; `ask` names its code, e.g. `"A2"`). Code uses only `agreed`.
- `source`: who it comes from: `Jeff`, `Dire`, `roadmap`, `game` (already true in
  play), `lore` (written here), `proposal` (suggested in a session with Jeff, not
  yet taken up). A fact can carry its own `source`, which wins over its entry's.
  Where a fact's text is Jeff's, its knowledge level may still be lore's choice
  until confirmed.
- `summary`: one true sentence, never a line for anyone to say.
- `relations`: `{to, kind}`, with `to` naming another entry's id. Kinds: in (a place
  in a region), holds, enemy, feud, ally, from (a material or person's origin),
  member, carries, took, held_at.
- Optional by type:
  - `resource` on a material: one of `Stockpile.RESOURCES` (gold, ore, wood, cloth, food).
  - `worked` on a material: what it does when worked, in words, plus `effects`
    tags (sound, brittle, heavy, cursed...). Economy and items turn the tags into
    numbers; lore never sets numbers.
  - `item` on a weapon: an `items.json` id, once the item exists.
  - `level` on a place: a folder under `levels/`.
  - `place_kind` on a place: one of `Level.PLACE_KINDS`.

## A fact

```json
{"id": "goblins.took_smith", "text": "The goblins took the smith and his hammer.",
 "known": "common", "where": ["town_lands"], "tags": ["smith"]}
```

- `id`: the entry's id, a dot, then a name.
- `text`: one plain statement of what is true (or, for a rumour, what is said).
- `source` (optional): defaults to the entry's.
- `status` (optional): defaults to the entry's. A fact is used only when both it
  and its entry are `agreed`. An `asked` fact names its `ask`.
- `known`, the knowledge level:
  - `common`: anyone who lives in, or knows, a region in `where` (an empty `where`
    means everyone).
  - `rumour`: told as hearsay where `where` says. `true` (required) records whether
    it is so, so a false rumour can stand without the lore contradicting itself.
  - `secret`: known only to the ids in `knowers`.
  - `lived`: one person's own experience, known only to `knowers`, and spoken of as
    memory.
- `where`: region ids. `knowers`: knower ids. `tags`: free words.

## Knowers

`knowers.json` is `{"_about": "...", "knowers": [{"id", "name", "status", "where",
"tags"}]}`. A knower is a group (townsfolk, a scholar) or a character (a companion by
her name, the smith). What a knower knows:

- the `common` facts whose `where` meets the knower's `where`, or is empty;
- the `rumour` facts heard there, as hearsay;
- any `common` or `rumour` fact sharing a tag with the knower's `tags`, wherever it
  is known (a scholar's `history`);
- every `secret` or `lived` fact that lists the knower.

A prompt gets the facts a character knows as plain true statements (rumours marked
as hearsay), never as lines to say. How companions put them into a prompt is the
companions tree's business.

`Lore` (`sim/lore.gd`) reads the files and applies this (decision 289):
`Lore.known_by("wren")` gives `[{id, text, hearsay, memory, where, weight}]` for the
agreed facts she knows. A rumour's `true` is never handed out.
`Lore.known_by("wren", ["ore", "rot"])` keeps the facts on those topics: a
fact's or its entry's tag, the entry's id, or a whole word or phrase of the text
or the entry's name (any case, a plural "s" allowed).
`Lore.known_by(id, [], "draft")` previews drafts too, and asked facts never
count. A fact may give a `weight` (a number above 0, how much it matters beside
others when a prompt has room for only some). Without one it is
`Lore.DEFAULT_WEIGHT`. None is set until Jeff weighs them.
Fact text is a third-person statement: lore_test refuses I, we or you in a fact or
a summary. To see what a knower would know:

    godot --headless --path . --script tools/lore_known.gd -- townsfolk --draft --about=ore

## Names

`names.json` is `{"_about": "...", "forms": [...], "things": [...]}` (decision 366).
How a thing gets a name (a long-time holder, a deed) is items' business; the words
are lore's.

- A form is `{"id", "how", "form", "status", "source"}`. `how` is holder, deed or
  maker. `form` is the name with slots filled in later: `{holder}`, `{thing}`,
  `{deed}`, `{maker}` and no others, e.g. `"{holder}'s {thing}"`. No quotes, no I
  or you.
- A thing word is `{"id", "for", "words", "status", "source"}`: lore's word for a
  thing where it differs from the item's own, `for` naming an item id or a tag.
- Only `agreed` ones count, as with facts. Until F1 is answered the only form is
  the holder form from `style.md`, as a draft, and no bynames are invented.

`Lore.name_forms(how, least)` gives the forms that count. `Lore.thing_word(item_id,
tags, least)` gives lore's word, or `""`. Items stores a name as `{form, holder,
made_step}` and shows it with `Lore.render_name(name, item_id, tags, noun)`: the
form filled in, `{thing}` being lore's word for the item now or else `noun`, so a
reforged thing keeps its name with its new word ("Wren's spear"). A stored form
renders whatever its status now: a name given stays given.

## Roles

`roles.json` (decision 376) says how people speak of the world, by Jeff's rule
(`style.md`): `{"_about", "professions": [...], "types": [...], "default_type",
"townsfolk"}`.

- A **profession** is `{"id", "name", "binding", "status", "source", "profile"}`.
  `id` is a trade id shared with economy (`levels/economy.json`'s official jobs and
  buildings, `items.json`'s `made.by`), or one with no job yet. `binding` is Jeff's
  word: `official` (speaks only lore facts: priests, guards, the town's officials,
  the medicine man) or `free`.
- A **personality type** (thief, bard, scoundrel, scholar, merchant, and `steady`,
  the default) is hidden: never shown in a label, which names only the profession
  ("Name [profession]", Jeff). It has the same fields, `binding` optional.
- A **profile** is `{"domain": [tags or entry ids], "superstition", "creativity",
  "intellect", "integrity", "status", "source"}`, each stat `low`, `mid` or `high`.
  A profession sets every stat, a type only those it changes. The top-level
  `townsfolk` is the profile for a trade not listed.
- A person's profile is the profession's stats with the type's over them where it
  sets them, and both domains. Its binding derives from the stats: creativity low
  and integrity high is official, creativity high or integrity low is free, and
  anything else is townsfolk. So a thieving smith is free, with a smith's domain.
  A profession or type whose profile doesn't count yet stands on its `binding`.
  lore_test checks every profile makes its binding.
- Listing one says how such a person speaks, not that one exists. A person entry
  may name its `role`.

`Lore.binding(trade, type)` gives the binding. `Lore.profile(trade, type)` gives
`{domain, binding, words: {stat: word}}` and each stat as a number (low 2, mid 5,
high 8), or `{}` when no profile counts yet. `Lore.types()` lists the types that
count, to roll from. `Lore.knower_for(trade)` gives the knower to ask `known_by`
for: the trade's own (`priest`, `guard`, `medicine_man`), else `townsfolk`;
`Lore.known_by(knower, about, least, type)` adds the type's domain. What a
resident hears and believes is that resident's, kept by companions, never a fact
here.
