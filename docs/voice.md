# The voice guide

Status: **draft for Jeff** (decision 748). How the world's people say things: wording,
register, dialect and rhythm of every line a player reads. What is *true* (history, places,
names, who knows what) is lore's (`docs/lore/`); a line that adds or changes a fact goes to
lore first. Every fixed line now in the game is listed in `docs/voice_inventory.md`
(`python -B tools/voice_inventory.py` regenerates it), and `python -B tools/voice_check.py`
reports the ones that break the rules below (report only).

Marks used below:

- **[Jeff]**: Jeff wrote or passed it word for word. Never reworded without asking him
  (through the coordinator).
- **[in game]**: in the game now, not yet checked against this guide by Jeff.
- **[draft]**: voice's guess. Open to change or cut.

---

## 1. The world's register

Lore's tone is *Gísla saga*: plain, grave, few words (`docs/lore/style.md`). For speech that
means:

- **Short sentences, whole sentences.** One thought each. Two or three sentences make a long
  speech; only a quest-giver's reveal runs longer, and it is still a chain of plain ones.
  Example [Jeff]: "Some of the Mound-breakers still dig. Put them all down, then come back to
  me."
- **Concrete over abstract.** Iron, gold, bones, a niche, cold air, a key. Not "the
  situation", "the threat", "resources".
- **Understated.** Feeling is left to the listener. Grief and fear show in what is said, not
  in names for them. Example [Jeff]: "Then you are strong enough." Not "Amazing, you did it!"
- **No exclamation marks**, with one exception kept as Jeff wrote it: the draugr's "Then I'll
  take it from you by force!" [Jeff]. A new line that wants one is usually better as two
  short sentences.
- **Ellipses** only for a pause that is part of the line, as Jeff gave the draugr
  ("...warrior, you have my respect." [Jeff]). Not for trailing off in ordinary speech.
- **Joining clauses**: a colon for "that is" and a semicolon between two halves are the
  house way, as the narration already does ("Locked fast. The big one, Brand the Ox, wears
  its key." [Jeff]; "The slab swings aside: a stair goes down into the dark." [in game]).
  No dashes in speech.
- **Contractions** are fine for townsfolk, robbers and companions ("I've nothing to bandage
  with."). Knights, the draugr and the priest speak them rarely; Jeff's own draugr line has
  one, and stays.
- **Spelling**: the game's own text spells the British way (neighbour, colour, favourite,
  honour) [in game]. Jeff's own words keep his spelling ("you have honored the pact").
- **Nobody knows they are in a story.** No modern words (okay, guys, awesome, team, stress,
  cool for good), no game words in speech (level, quest, spawn, respawn, loot, XP, boss,
  dungeon, player, NPC, game, companion, owner), and no words for what the world does not
  understand (lore's rule). The world's words for them:

  | Not | But |
  |---|---|
  | kill, defeat (of people) | put down [Jeff], fall, lay to rest |
  | respawn, resurrect | brought back, wake, rise, walk again |
  | dungeon, level | the barrow, below, the halls, the stone places |
  | boss | by name or kind: the draugr, Brand the Ox |
  | quest, mission | a task, a job, what was asked |
  | loot (as a verb) | take, carry off, plunder |
  | money, cash | gold; coin among traders |
  | player, companion | by name, or "you"; "the one who goes with you" |

## 2. The four kinds of text

Each has its own register. Keep them apart.

1. **Speech**: a person or creature talking, in their own voice (sections 3 and 4).
2. **Narration**: what the party log and a found thing tell. Present tense, third person
   for others, "you" for the reader, no feeling named. Examples [in game]: "The hall's door
   shuts behind you." "You find %s in a niche in the wall, shaking. He will not say what he
   saw, and makes his way up." Plaques and set dressing are narration in carved or written
   form [Jeff]: "Here rest the holy remains of <knight>, knight of Theus, until the altar
   calls them home." "The stair down is barred from below."
3. **Window titles** (deals, tasks, pleas): an imperative of two to five words, in the
   world's words. Examples: "Prove your strength" [Jeff], "Face the draugr", "Take the
   offering down", "Clear the camp", "Bring the medicine man" [in game]. The window's body
   is the asker's own speech.
   **Names in narration** (agreed with dungeon, 2026-10-31): a creature with no given name
   has two forms. In a sentence it is lower case with "the" ("Wren hits the draugr", "the
   grave robber"). As a label (a window title, the talk log's speaker) it is capitalised
   ("The draugr"), and so is a line that opens with it ("The draugr hits you."). Given names
   (Brand the Ox, Sir Edric the Steadfast) stay as they are in both.
4. **System text** (hints, server notices, settings): out of the world, so plain
   instructions that may name keys and clicks ("Click a townsperson to interact, or press
   %s" [in game]). Never mixed into speech or narration. Keep it short and calm, no jokes.

## 3. Fixed speakers

### Knights of Theus: the fallen knight

Who (lore): a holy knight of Theus from the days when knights were made, his bones held by
the draugr; a different knight each cycle.

- Sentences: measured, whole, a little formal; a command given plainly. Longest of anyone,
  because he gives the task, but each sentence is still simple.
- Uses: Theus, bones, remains, rest, strength, put down, the way below, the names of the
  halls. Names places as they are named (the First Hall, the Ossuary, the Hall of Fallen
  Souls).
- Never: thanks effusively, jokes, swears, explains how his spirit works.
- Address: "you"; names himself once ("I am [name], a knight of Theus"). No title for the
  player. His name carries its title, as lore's list of the fourteen has it: "Sir Edric the
  Steadfast" [Jeff]; with no name yet he is "the fallen knight".
- Oaths and greetings: none in the approved lines. **[draft]** "Theus keep you" as a parting,
  only if lore agrees the faithful say it.
- Examples [Jeff]:
  - "I am [name], a knight of Theus, and my bones lie beneath the temple, held by the
    draugr."
  - "Some of the Mound-breakers still dig. Put them all down, then come back to me."
  - "The way below is open to you. My remains wait in the Hall of Fallen Souls."

### Aldous, the priest

Who (lore): keeps the temple of Theus, takes alms; keeps the secret of where the gold goes.

- Sentences: short, kindly, a blessing in them; says less than he knows (he keeps a secret,
  so he never explains the barrow).
- Uses: peace, blessing, the altar, the remains, bless you, home.
- Never: the old gods or Psyke by name to a stranger (a secret, lore), money words beyond
  "gold" and "alms".
- Address: "you"; warm but not familiar.
- Greeting [in game, the priest's]: "Peace on you. What is it?"
- Examples [in game]: "%s is home at last. Bless you." "The blessing is on your amulet: it
  holds %d now." "You carry no blessing from below yet. Keep %s safe until you have stood
  before what waits there, then bring the remains to me."

### The draugr

Who (lore): one of the restless dead, empowered by Psyke; holds the Hall of Fallen Souls.

- Sentences: few and heavy. Questions and demands. A pause before the verdict ("...").
  Speaks of "my Hall", "my barrow", "your people".
- Uses: gold, stole, pact, thieves, warrior, respect, death, hall, barrow.
- Never: explains the puzzle (Jeff: "I don't want the draugr to explain everything in one
  sentence"), pleads, names Theus as his own, says more than two sentences at once.
- Address: by the player's name once, when they enter; "warrior" when they have earned it.
- Examples [Jeff]:
  - "Why have you entered my Hall, %s?"
  - "Return the gold your people stole from this place, when you do that you may leave."
  - "Thieves in my barrow, thieves in my hall. You are all the same to me."
  - "...you have honored the pact, I shall give you the power to cheat death"
  - "Then I'll take it from you by force!"
- Narration about him keeps him spare: "He rests." [in game]; "%s refuses the draugr. He
  laughs, and rises to strike." [in game].

### The Mound-breakers and other robbers

Who (lore): grave robbers in the barrow; named (Brand the Ox, Crake, Mott, Nabb, Wicket,
Fenn, Rook, Sedge, Tull); they dig for relics to sell.

- Sentences: the shortest of anyone. Taunts and jeers, two to six words, a question as a
  sneer.
- Uses: plain rough words, "you again", "the ground", "crawl", "run". Thieves' cant is
  welcome as long as it is plain English ("hole", "fresh meat").
- Never: long speeches, the knights' or priest's piety, oaths by Theus, modern slang
  ("gonna", "dude"), real swearing beyond the rough (decided case by case with Jeff).
- Address: "you", contemptuous; never the player's name.
- Examples [in game, npc's 716 lines]: "Fresh meat." "Lost, are you?" "You picked the wrong
  hole to crawl into." "Last time you ran." "You put me in the ground. It didn't take."
- **[draft]** Brand the Ox speaks least of all: one or two words, or none.

## 4. Townsfolk, vendors and companions

### Townsfolk by trade

- Sentences: one line, busy, a little curt; the trade shows in what they mind ("the iron's
  hot", "the pot's on", "mind the sheep"). The greeting ends in a short question that asks
  your business.
- Uses: "Aye", "What is it?", the tools and stuff of their work.
- Never: chatter about the world unprompted; flowery welcome; "Hello"/"Hi"/"Hey".
- Address: "you"; warmer by standing ("Good to see you." for a trusted one) [in game].
- Examples [in game, `levels/townsfolk.json`]: "What is it? The forge won't wait." "Aye? Make
  it quick, the iron's hot." "Quiet, you'll scare the game. What?" "Wipe your feet, there's
  blood about." "Sit; let me look at you." (the medicine man)
- Pleas (windows) speak as the asker, plainly, with the need and the place [in game]: "My %s
  %s has not come back from beyond the walls; if you find %s out there, walk %s home."
- **[draft]** The lawspeaker: the most careful speaker in town. Says what is set down and no
  more, in the past tense of a ruling ("The lawspeaker ruled on the quarrel between %s and
  %s: %s." [in game]).

### Vendors (Rolf)

Who: Rolf keeps the starter blades stall in the wilds (736).

- Sentences: a trader's patter, short and friendly, price first.
- Uses: blades, gold, apiece, take your pick, the road.
- Never: haggling talk the game doesn't do, words like "deal", "sale", "discount".
- Examples [in game]: "Blades for the road, one gold apiece. Take your pick." "Starting out?
  A gold buys you something to swing." "One gold each, and never sold dear. What'll it be?"

### Visitors (travellers, pedlars, pilgrims)

- As townsfolk, but from away: where they come from in the first line.
- Examples [in game]: "Just passing through, from %s." "Fine things from %s, if you've the
  coin."
- **For lore** (a fact question, not voice's to settle): the pilgrims and the road lines say
  "The gods keep you", "thank the gods" and "Gods keep you" [in game], but the temple and the
  town follow one god, Theus (`theus.one`, agreed). Whether a pilgrim to Umbrage's temple
  would say "Theus keep you" is lore's and Jeff's call; voice will reword once it is
  answered.

### Pip

Who (lore): a young man, Aldous's apprentice, who wants to become a squire though no one has
been knighted in ages; carries the temple's offering down in secret and is paid to keep
quiet. His speech is generated from his card; these are the style words for his prompt.

- **[draft]** Eager, a little too sure of himself, quick to speak of knights and courage;
  goes quiet and short when the barrow or the offering comes up ("I keep what I see to
  myself." is the shape of it, from the resident prompt's KEPT_LINE).
- **[draft]** Says "Sir" only of the old knights, by name, as the barrow's list has them
  ("Sir Edric the Steadfast" [Jeff]): nobody living is knighted. Speaks of Theus with a young
  believer's plainness.
- Never: tells the temple's secret, names the old gods.

### Wren and Nix

Who (lore): women, companions by choice; who each is comes from her rolled card (temper,
manner, speech: `levels/companion_traits.json` "speech"), so the guide fixes only the
register, not a dialect.

- All companions: one or two short sentences, spoken aloud, never a description of what
  they do, never the world's game words (the companions' VOICE_RULES already say this).
- The card's speech words are the dialect: "short, whole sentences", "a dry, wry way",
  "a blunt way, with no softening" [in game]. **[draft]** add "few words, and plain ones" to
  the shared world text so every card leans the saga way.
- Fixed lines spoken without the model are plain and practical [in game, drafts for Jeff]:
  "Not here. Not with them this close." "Give it a breath. We're still bleeding from that."
  "My hands are full."
- **[draft]** The falling companion's last words ("Go on... without me.", "Tell them I
  tried." [in game]) are closer to film than saga; a plainer set is a later review item.

## 5. How the review works

- Trees send voice new player-facing lines before they land; voice answers within the hour
  with them in voice, or "fine as is". The tree that owns the screen has the last word on
  length and fit.
- Lines marked [Jeff] are his: never reworded without asking him.
- Existing lines that break this guide are fixed a few at a time, each a small landing with
  the owning tree's yes.
- A line that changes what is true goes to lore first.
