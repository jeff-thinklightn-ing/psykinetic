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
| `levels/lore/people.json` | named people and named weapons (`person`, `weapon`) |
| `levels/lore/history.json` | things that happened (`event`) |
| `levels/lore/knowers.json` | who knows what: groups and characters (not entries; see below) |

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
  out of `agreed` until maps has added its key.
- `type`: world, faction, people, region, place, material, person, weapon, event.
- `status`: `agreed` (Jeff or Dire decided it, or it is already in the game),
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

`Lore` (`sim/lore.gd`) reads the files and applies this: `Lore.known_by("wren")`
gives `[{id, text, hearsay, memory}]` for the agreed facts she knows. A rumour's
`true` is never handed out. `Lore.known_by(id, "draft")` previews drafts too, and
asked facts never count. To see what a knower would know:

    godot --headless --path . --script tools/lore_known.gd -- townsfolk --draft
