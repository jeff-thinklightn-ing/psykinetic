# Proposal: the lawspeaker and town memory

Status: **proposal**. From a lore session with Jeff, 2026-10-17. For the npc tree,
with lore and companions affected. Nothing here is decided until Jeff says so.

Marked throughout:

- **[Jeff]**: Jeff said it in the session (paraphrased unless quoted).
- **[proposal]**: suggested in the session, open to change or cut.

## Summary

Residents may tell small stories about the town's life. What they say is kept,
spreads through gossip, and is ruled on by the town's **lawspeaker**, who walks the
town, talks to people, and keeps the town's memory consistent with itself and with
lore. When the town keeps talking about someone who would live there, that person
can move in. The town's story gets written as it is lived.

> "its like the story gets written as it goes... i actually kinda like it" (Jeff)
>
> "Whatever we can do to make it seem like a living world" (Jeff)

## Why

Before gossip landed, the cook, asked for news, invented "Old Marta" and a sick
son. After gossip, she repeats only what she has heard, naming who told her. The
second is correct under the speech rule, but the first had life in it. The
problem with Old Marta was never that she was invented. It was that she vanished:
asked again, the cook might say something else. This proposal keeps the life and
fixes the vanishing.

Test for any feature here: *would this have happened if no player were watching?*

## In the world

- **[Jeff]** Each town has a lawspeaker.
- **[Jeff]** The lawspeaker goes and talks to the people, and keeps everything
  straight.
- **[proposal]** The role is the saga lawspeaker: the man who holds the law in
  memory and recites it at the assembly. Here he also holds what the town
  remembers. People bring disputes and conflicting stories to him, and what he
  says is what the town remembers from then on.
- **[proposal]** He makes rounds through town, a few people a day. Players can see
  him at someone's door; the next day, the talk has shifted.
- **[proposal]** He speaks lore as fact and town memory as memory ("the town
  remembers the miller went south"). He never presents his rulings as lore.
- Touches lore questions A3 and A4: a lawspeaker means saga law and an assembly.
  Who leads the town day to day stays open.

## Three kinds of truth

| Tier | What it is | Who can change it |
|---|---|---|
| Belief | What one resident has said or believes. Hers, not the town's. | The resident; gossip spreads it |
| Town memory | What the town as a whole remembers. | The lawspeaker's rulings |
| Lore | The world's facts (`levels/lore/`). Bedrock. | Jeff only |

- **[proposal]** Lore always outranks town memory, and town memory outranks one
  person's belief.
- **[proposal]** Conflicts are reconciled, not deleted. When town memory clashes
  with lore or with itself, the lawspeaker finds an in-world explanation (she moved
  away; it was only Marta's talk; the boy got better) and that becomes the memory.
- This matches the summary's existing rule: a falsehood a resident believes is that
  resident's own, never lore.

## The flow

1. A resident says something new about the town's life (Old Marta and her sick son
   Timmy). It is recorded as her belief, with who said it, to whom, and when.
2. Gossip carries it, kin first, each teller naming their source (already on main).
3. Beliefs that spread and hold become **candidates** for town memory.
4. On his rounds, the lawspeaker reviews candidates and the people who hold them,
   and rules on each.
5. Plain code applies the ruling. The town's talk follows the new memory.

### Rulings

- **Accept**: it becomes town memory.
- **Reconcile**: it clashes with lore or town memory; he gives the in-world
  explanation, which becomes town memory instead.
- **Leave as belief**: not taken up; stays one person's (or a few people's) talk.
- **Move in**: someone the town remembers as living there is ready to arrive (below).
- **Propose to lore**: good enough to be bedrock. Goes to a list for Jeff, never
  straight into lore.

## Moving in

- **[Jeff]** When someone speaks of Old Marta and her sick son Timmy, they could
  then silently move into town.
- **[proposal]** Conditions before anyone arrives:
  - The talk says they live in or near the town. People described as dead, far
    away, or contrary to lore (a knight, when no one has been knighted in ages) stay
    talk only.
  - It has spread and held. One mention is gossip; someone still talked about after
    it spreads is real enough to arrive.
  - The town has room: housing and stockpile, the same growth that takes in rescued
    captives, so invented people never crowd out rescued ones.
- **[proposal]** What the talk says becomes their card (Marta is old, has a son, he
  is sick). The rest is rolled, as for companions, and then grows from what they
  live through.
- **[proposal]** They arrive as if they were always there. The town remembers them.
- **[proposal]** What they bring can become work for the town: a sick boy is a
  reason to go to the medicine man's hut or the temple. No one wrote that errand.

## How it runs

- **[Jeff]** The lawspeaker is perhaps a higher-powered API (a stronger model than
  the residents').
- **[proposal]** Many cheap voices, one careful mind. Residents' small models handle
  the volume of talk. The lawspeaker's model handles judgment, which is rare.
- **[proposal]** His rounds are the cadence of the calls. A few residents per round,
  on the world's slow tick, so cost is bounded by how fast one man walks the town.
- **[proposal]** He reads structured records (town memory, gossip trail, the
  candidates, the lore facts that bear on them), not raw transcripts.
- **[proposal]** He returns structured rulings, and code applies them. He advises;
  he never edits the world directly.
- **[proposal]** The town runs without him. If the API is down or slow, gossip keeps
  flowing and candidates wait for his next round.

### Data sketch

Shapes only, to show the idea; the npc tree owns the real ones.

```json
{"id": "tm.marta", "tier": "belief", "text": "Old Marta lives by the east field.",
 "said_by": "cook", "heard_by": ["tam"], "first_said": 1042, "spread": 3,
 "tags": ["marta", "person"]}
```

```json
{"candidate": "tm.timmy_sick", "ruling": "reconcile",
 "memory": "Timmy was sick through the winter and is mending.",
 "because": "conflicts with tm.timmy_well, said by the priest"}
```

## Guardrails

- **[proposal]** The lawspeaker never writes lore. Only Jeff does. His rulings are
  town memory, even when they are good.
- **[proposal]** No one in town, the lawspeaker included, invents world facts:
  factions, history, places, gods, the land and town names, or anything lore has
  marked asked. Small life is free; the world is not.
- **[proposal]** Reconcile, never erase. Town memory keeps its history.
- **[proposal]** Players' words: if the lawspeaker reads what players said to
  residents, that text goes to an outside API. Fine for Jeff and Dire; state it
  plainly to anyone else before a public release.

## Changes to existing rules

- **Speech rule (decision needed).** Today: "towns people don't fabricate." This
  proposal lets townsfolk tell of small life (neighbours, kin, ailments, chores,
  quarrels), recorded as their own belief. Options:
  - a) all townsfolk may;
  - b) only the creative end of the trait scale may;
  - c) unchanged, and only bards and scoundrels seed town memory.
  Officials, priests and guards stay bound to lore and town memory either way.
- **Officials and the lawspeaker.** Officials speak only lore facts. The lawspeaker
  is the most official person in town, so the rule becomes: lore as fact, town
  memory as memory.

## Phasing (suggested)

1. **Town memory log.** Record residents' new statements as beliefs with their
   source. Gossip reads and writes it.
2. **Rulings offline.** The lawspeaker's model runs over the log in a batch and
   returns rulings; code applies them. No in-world presence yet.
3. **Rounds.** He walks the town; reviews happen on his visits.
4. **Moving in.** Remembered people arrive when the conditions hold.
5. **Promotion list.** Candidates for lore go to a list for Jeff.

## Open questions for Jeff

1. The speech rule: a, b or c above?
2. One lawspeaker per town: does the starter town's have a name and a face (E2-style
   card), or is he rolled like everyone else?
3. Can players speak to him and bring him disputes, or is he someone you only see
   making his rounds?
4. Can remembered people leave or die by town memory alone (Timmy does not mend),
   or only through the world (raids, sickness the sim models)?
5. Which model for the lawspeaker, and is the outside-API note acceptable for now?
