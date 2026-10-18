# Changelog

Newest first. Worktrees add their bullets under `## Unreleased`. To cut a release the
release session leaves that heading where it is, empty, and puts `## vX.Y.Z` under it
above the bullets; `tools/release_client.ps1` uses the `## vX.Y.Z` section as the release
notes (decision 324).

## Unreleased

- A left click on a resident, a companion or another player no longer attacks them: you walk over and talk (the conversation panel, or the chat addressed to a companion). Shift+click attacks one; monsters stay click-to-attack. The cursor says "LMB  talk" over a friend (decision 454).
- Over things on the ground, such as a deer's meat and hide, the cursor shows "F  pick up" when playing on a server again (decision 454).
- Options gained an Interface size (the whole interface smaller or larger), a Text size (the words alone, up to half again), and a Colours choice: Distinct keeps the game's meaning colours apart for red-green colour blindness (friends blue, the party pale, a warning magenta); it shows in full from your next start. Esc opens the game menu, titled with where you are, with Close, Options, Leave and Quit: the world goes on while it is open, as it always did; nothing calls it a pause.
- Each town has a lawspeaker now, unseen as yet, who keeps the town's memory
  straight: once a day he weighs the tales several people have come to hold
  (Old Marta by the east field, the boy who was sick all winter), takes some
  up as what the town remembers, squares others with what is known ("the boy
  is mending"), and leaves the rest as talk; the townsfolk tell you what the
  town remembers as memory, never as fact. Off unless the server turns him on.
- Deer in the wilds are deer now, not grey boxes: they walk, bound away,
  graze, look up and fall.
- The town starts keeping its own stories: when a bard or a tale-teller among
  the townsfolk speaks of a neighbour, an ailment, a quarrel, the town
  remembers who said it and to whom, and the tale spreads at the well with
  its teller's name. Nothing is forgotten, and nothing of the wide world is
  made up; who rules on what the town will hold true comes next.
- People jog in longer strides again, about 1.65 m a step, without the glide.
  A woman's gaits are paced to her own legs. A shield is carried face out on
  the arm.
- Press M twice for the world map: every area as a box with its places, the ways between them, your own area edged in brass with the place you stand in marked, and your party named where they are; the wheel zooms, a drag pans, Esc or M closes it. Who holds what and what you have seen come as the server learns to tell you.
- The temple in the wilds has its counter now, at the back behind the doors: hand the priest a thing and an offering there, and come back to it for what waits.
- The server now tells your game what you have seen of the world, who holds the places you know, and where the rest of the party is, for the world map. What you have seen is kept with your character on the server.
- No more "fetch six wood" errands from the townsfolk: a shortage is something
  they talk about, and if you bank what the store was short of, the town pays
  you then and there and says so. The same for every favour: bring someone's
  kin home or clear the camp that raided the town and the thanks and the
  coin come whether or not anyone asked you first.
- A new town starts with food in its store to last until its first harvest. Townsfolk with no gold eat the store's plain food instead of borrowing for the cook's meals, and the town pays its officials as it should.
- Your companion remembers what passes between you: the things you give her
  and she gives you, the gear that takes her name, the named thing you kept
  from her, and who brought her back at the temple when she fell.
- The town's people remember what you did for them, and to them: a promise
  kept, kin brought home, a debt covered, a word carried, a gift pressed into
  their hands, a raid you stood through with them, a promise let lapse. It
  shows in how they greet you, what they offer you, and what they tell the
  neighbours at the well; and it fades, slowly, with time.
- People and goblins hold what's in their hands: a sword in the fist, a
  shield on the arm, a dagger, an axe, a bow, swung with every blow. Until
  each has its own art it shows as a plain grey shape. A carried lantern
  hangs at your belt.
- At the temple's counter or the smith's, a screen beside your pack shows what can be done to what you carry (a blessing, a reforge), what it costs, what of yours is being worked and when it will be ready, and what waits for you to collect.
- Towns can farm: a field worked by a farmer is sown in spring, grows through summer with the rain (a drought or a storm can ruin it), is harvested in autumn, and gives a few roots in winter. A good harvest feeds a small town through the year; a bad one means hungry months. A farmer comes by rescue, or to a town whose field has stood a few days with nobody to work it.
- Townsfolk eat once a day, not three times. Their rent now goes into the town's bank, where it is lent back out, instead of vanishing. Goblin camps, wolves and the town's hunter hunt more gently, so the deer and rabbits of the wilds last instead of being hunted out within a season.
- Choose how you look: the Character section of the options (O) now picks
  your build, height, hair and its colour, beard and skin beside a turning
  preview of you, or "Surprise me" for someone new. It shows from your next
  join.

- Credits: a sound's title no longer ends in its file's ".wav"; the list is built when the options are first opened, never on the server.
## v0.1.150

- This release changes what the server and client send each other, so update the
  client to keep playing (the launcher's update does it). New in it: people made by
  the character generator, so every townsperson looks different; a main menu, a
  connect screen and one shared look for every panel, with tooltips on what you
  carry; townsfolk with cards of their own, daily routines, gossip at the well, and
  offers when you speak to them; the temple brings the fallen back and blesses
  cursed things; arrow bundles swapped and mended, the shield bash and heavy
  weapons' wind-up, with weapons that keep their kills and grudges;
  pines along the border and the broadleaf tree; the rabbit; camps that fall when
  cleared, with their captives rescued; hungry camps raiding for food; meat, hides
  and leather; wells and roof repair; the Blood Rot and its orc and kobold allies.
- Talk to the town's people face to face: press E on someone (or just speak near them) and a panel at the left shows who you are talking to, what you have said to each other, and what they offer, with a button to take them up on it (work, wares, a plea), and three quick asks (what they sell, any work, the news). The world stays in view; they keep answering in speech. The main menu's server line says "status unknown" when the server does not answer, which older servers never do.
- Companions weigh what they hear as townsfolk do: how sharp or superstitious
  each is decides whether she believes a tale, she repeats it as "Jeff told
  me...", and while she rests in town she trades gossip at the well.
- A companion resting in town trades talk at the well and the inn like anyone:
  what she believes reaches the neighbours, and what they saw reaches her.
- Big levels draw much faster: on a large dungeon with eight players together, a frame takes about 11 ms where it took 30. The game no longer checks every creature and door on the level each frame. Client only.
- Two more kinds of townsfolk walk the town, unmarked: a scholar, who knows
  more of the old stories, tells them when asked and passes them on at the
  well, and a merchant, who buys cheaper and sells dearer among the
  neighbours, will sell you anything at the counter, and has an ear for talk
  of prices.
- The Credits in the options now name who made the art too: Kenney's Castle Kit and Quaternius's animal rig and animations, each with its licence and a link.
- Each companion now has a look of her own (build, height, age, hair, beard),
  kept with who she is, for the new character bodies to draw; Wren, Nix and
  Pip each have a fixed one.
- Speak to one of the town's people and they have something for you: a thing
  of their own making at the counter, a job the town needs done (kin brought
  home from a raiders' camp, the camp cleared, wood fetched to the store, paid
  from the town's coffer), the newest thing they have heard, or a plea (a hand
  with a debt, a word carried to a neighbour they have fallen out with). Take
  one on and they remember your promise; keep it, or it lapses in a week.
- The tanner's leather goes into the town's store, so the fletcher can mend arrows and the tanner make bucklers with it, instead of sitting in the shop.
- Each of the town's people carries their look with them now (build, age,
  hair, beard, a hood or hat, the trade's apron), ready for the character
  models when they come; nothing changes on screen yet.
- Clearing a raider camp takes it: kill its defenders and hold it for ten seconds, and it falls, freeing whoever it held. Its monsters stay gone until the raiders take it back, and a raid party coming home to it scatters.
- Some townsfolk are shrewd merchants: they pay a little less for what they buy in town and get a little more for what they make, at the other townsfolk's expense, never the town's.
- The game can ask a server whether it is up, its version and how many are playing before you join, so the menu can show it.
- The options end with Credits: who made the sounds (Freesound, Kenney, Sonniss), and a button that lists each sound's maker, licence and page (decision 406).
- This release changes what the server and client send each other: update the game before joining. The shop and temple counters can now show what can be done to the things you carry, and what it costs. The town's smith can reforge a named weapon into another, keeping its name and history, for some of the town's ore and wood and a fee; you collect it from the counter when it's done.
- Companions know when they are inside a building, and whose home it is; can
  look round inside one for you; step out of your way when asked or bumped;
  follow you indoors instead of standing in the doorway; and hold a door
  only when something hostile is coming for you inside. Asked for something
  they can't do, they say so.
- Hover a thing in your pack or an open chest to read what it is: its name (a named thing's in brass), what it does, its strength, its condition and marks, what it has felled, and its story. The pack says what you carry weighs. What is said shows in one box at the bottom left and fades after a few seconds unless you pin it with Tab; Tab inside the chat box swaps between speaking aloud and the party. The compass names where you stand. A short hint by the cursor says what a key does on what it points at ("E  open"); the full controls list is off by default now, H shows it.
- Hand a thing to the priest at the temple counter with an offering of gold, and it is blessed for you. It waits at the temple until you come back for it, however long that takes, and only you can take it.
- A named weapon can be reforged by the smith into another weapon taking no more hands, for half the metal and time of a new one. It keeps its name (Wren's dagger becomes Wren's sword), its history, its marks and its kills; its strength stays if it suits the new weapon. (The forge counter where you'll ask for it is coming.)
- When the server is newer, the game now downloads the update itself with a progress bar on the connect screen (and a Cancel), rather than closing without a word while it updates.
- view_test's "an imp's swing is higher than a player's" no longer fails now and then: Sfx keeps each player's slot and its pitch before the ±7% jitter (meta), and the check compares those, skipping a voice beside the swing.
- Townsfolk talk among themselves now: at the well, the inn, the square or the
  temple, what one believes or saw passes to a neighbour standing there, kin
  first and never across a grudge, and comes back to you as "At the well, Tam
  told me the mine is cursed". A lie told to one of them can walk through the
  town; what a neighbour saw with her own eyes is believed, a rumour less so
  by the sharp.
- A blessing lifts a curse: a named weapon you found and kept from its namer, once blessed, is rightly yours, and no ill gathers on it. Give it away and the blessing goes with it; have it taken from you and the blessing is lost. (The temple's counter, where you'll have things blessed, is coming.)
- Taking a goblin camp frees the people it holds: townsfolk carried off in raids go home to their work, and the camp's other prisoners join the town with their trades, often the hunters, tanners and fletchers it lacks. A fletcher now mends arrow bundles; until the town has one, the carpenter does.
- The goblins are the Blood Rot now, with the orcs (brutes) and kobolds (sneaks) as their allies: they share ground and raid together, and the town's log names the Blood Rot.
- With raids on, a raider camp that has hunted out the game around it grows hungry: it raids more often, and its raiders come for food rather than people.

- Townsfolk keep hours now: the well at dawn, the forge or kitchen through the
  day, the inn at midday and in the evening where the town has one, home at
  night, each on their own clock, later out in winter and earlier home, a
  morning at the temple every so often; and the medicine man is at his hut in
  the wilds when you walk up. Ask one where they are and they say.
- A weapon's tooltip tells its story: who carried it longest and for how long, who it is named for or who made it, whom it was kept from and what it has avenged. Weapons and their strengths now come with a few words on what they do.
- A town's well fills from its spring and the rain, and its people draw from it. A big town can run its well dry in a dry spell, and then its cook works at half speed until it rains. The town's carpenter mends roofs broken by storms, one at a time, for some wood.
- The town's carpenter mends worn bundles of arrows left in the store, using a piece of leather and some wood. The same bundle comes back whole, with its name and history.
- Leather has uses: the carpenter can mend a worn bundle of arrows back to full with a piece of leather and some wood, and the tanner makes a leather buckler, lighter and cheaper to hold up than the round shield but covering only straight ahead, letting a little through and breaking sooner.
- The game starts at a main menu now (Play, Options, Quit) when you run the downloaded client, and joining happens on one screen that says what it is doing in plain words: connecting, checking the version, the server restarting, or what went wrong, with Retry and Change server. Esc opens a pause panel (Resume, Options, Leave, Quit; the world goes on while you are away). Options gained Window (fullscreen or windowed), Resolution, and a Controls section (click to move or WASD, and whether the controls list shows). The line at the top left shows only your state now; "host" and the tick moved into F3.
- Each of the town's people has a life of their own now: where they were born,
  how they came to the town, kin among the neighbours, maybe a grudge, and what
  they remember of what happened here (a raid that took a neighbour, one who came
  home, a loan, raiders at the walls). Ask them and they tell you from it.
- Weapons can earn a bane or a vengeance. One that fells 25 of a kind becomes their bane: that kind dreads whoever holds it, but notices them from further off. One held by someone who falls to a creature holds a grudge against that kind: its blows stagger them, but they come for its bearer first, until five of them have fallen to it. The pack and the party log say which.
- Townsfolk, companions and players are all people now, each their own:
  heavy or lean, tall or short, young or old, broad or narrow, in their own
  skin and hair, cropped, bound up, long or bald, some bearded, some in a
  hood or a hat, some in aprons, the old sometimes stooped. New
  bodies, made by our own tool. Client only.
- Your companion now knows when she or you are bleeding or burning, and
  while one of you bleeds, bandaging comes first among what she offers.
- Weapons keep count of what they've felled, by kind, whoever held them: hover a slot in your pack to see "felled 14: 9 imps, 4 wolves, 1 brute" under its name.
- People strike with what they hold: a sword swings, an axe falls overhead, a dagger stabs, a spear thrusts, and bare hands punch. Each blow is timed so it lands as the hit does. Bodies far from the middle of the view, or out of it, move less often, which keeps crowds cheap. Client only.
- Companions know that brutes are orcs and sneaks are kobolds, allied to the Blood
  Rot's goblins (the imps), and why they fight for them.
- The giant axe winds up before it falls: an attack takes almost a second to land, and nothing blocks it when it does. A raised shield breaks under it, and the one struck is knocked down. Stepping away or being stunned before it lands gives the swing up, and if your target has moved out of reach it hits only air. Brutes' wind-ups now visibly stop when they give one up.
- Monsters know their bane: a weapon that has become the bane of their kind is dreaded by every one of them, however bold, and they spot and hear its bearer from half as far again. A weapon holding a grudge against a kind draws that kind to its bearer first.
- Monsters handed a giant axe wind it up too, and stand still until it falls. Wind one up at a monster and it reacts: a cautious or cowardly one steps out of reach and waits for the swing to pass, one with a shield bashes you to break it, and a bold one stands and takes it.
- The interface has one look now: a shared theme (warm dark panels edged in leather, bone text, brass for keys, hands, prices and focus, the Alegreya faces) that every screen takes its fonts, colours and panel style from, with a style guide for the trees that build screens; the first-run screen, options, pack and chest, shop, talk log, chat, hints, compass and speech bubbles all wear it. The talk log reads as speech (the speaker's name, then the words); hover a line for when it was said.
- Companions know their town is a town, know the beasts lore knows when you
  ask ("what is a stag?"), and no longer remember "not knowing" someone as a
  fact about themselves.
- Shield bash: with your shield raised (right button held), the left button bashes with it instead of swinging. It shoves the one in front (light ones further), staggers them briefly and knocks a raised guard open for a moment, so your next blow lands. No damage; it costs a little stamina and can't be repeated for 2 seconds.
- Monsters with shields bash too: hold your shield up against one and it bashes your guard open, then strikes. It never bashes someone with no guard up, and one cornered as it flees bashes you to stagger you.
- The forest round outdoor maps has real broadleaf trees: round, lumpy olive crowns on brown trunks in place of the old teal tiered trees with orange bases, so they turn colour in autumn and catch snow on top in winter.
- A goblin camp that has hunted its land bare raids for food: it carries off more of the town's food and meat, but takes no one.
- Goblin camps hunt the herds around them, so game grows thin near a camp, and a rescued hunter brings the town meat, hides and the odd pair of antlers. Neither ever hunts a herd out, nor the animals you are stalking. Wolves that run out of prey dwindle.
- A thing someone has carried long enough takes their name, such as "Wren's dagger".
- Taking up a bundle of arrows while you hold a bow and a bundle swaps them: yours is put down where the new one lay, and the party log names both with their condition, so you can keep the better one and have it mended.
- Meat and hides you bring home now build the town. The store keeps meat, hides and leather apart from its food; the cook roasts meat into a better meal than a ration, and townsfolk eat meat when the food runs out. A rescued tanner gets the town to build a tannery and turns hides into leather for the shop. Raiders take meat as they take food, never hides or leather.
- Rabbits in the wilds are rabbits now, not grey boxes: they hop, bolt,
  nibble, sit up to listen, flinch and fall.
- Townsfolk remember what they hear. Tell one something and, depending on how
  sharp or superstitious they are, they may believe it and pass it on as
  hearsay ("Talos told me..."); priests and guards speak only of what is
  known, and a few townsfolk are not as honest as they look.
- More sounds from Freesound (each credited in THIRD_PARTY.md): women's grunts, cries and
  death screams for female characters, a grunt when anyone lifts something heavy, a door
  bursting, a throw's whoosh, blows on stone, a deer's last call, and a small thing landing.

- Townsfolk have hidden natures now, most of them steady, a few of them
  thieves, bards or scoundrels, rolled once when they join the town and never
  shown. A thief lifts a thing from the town's store now and then, one piece
  of cloth, ore, wood or food, never the last few of anything and never
  gold; the store's ledger says only that something is missing.
- The temple's entrance is one wide double door; each leaf still opens on
  its own.
- People run in shorter, quicker strides that match their legs.
- Doors are wider and taller, sized for the new bodies (an opening 0.8 m wide and 2.4 m tall), and drawn as a plank door instead of the old castle-kit door.
- Past the edge of outdoor maps the forest is now crowded pine stands whose crowns merge into one canopy.
- The music in the open country is a soft wind drone now, not an organ-like pad, and a
  new place is marked by chimes. The pad plays beside and inside the temple instead.

- When you fall, you are brought back at the nearest temple or healer's hut with someone there: after about a minute the priest or the medicine man brings you back at full health, and the party log says who did it. Companions and townsfolk who fall come back the same way. Where there is neither, you come back as before. The wilds town's temple now has its priest, paid by the town like the guard, and the healer's hut in the wilds has its medicine man.
- The odd gaps between the border's pine stands hold single pines now, not broadleaf trees.
- The forest floor under the border's pine stands gets ready for a texture of fallen needles and cones in place of its flat brown; it shows once the art is in.
- The ground gets ready for real grass, dirt, stone and sand textures; each shows once its art is picked. Where the land meets a pine forest, its edge now fades into the forest's needles.
- Animals come into view from a distance instead of appearing beside you, a hunted deer or rabbit can escape off the edge of the map into the next area, and wolves keep to their den by day and range far by night.
- The minimap and the big map (M) show when you host a game, not only when
  you join one.
- Companions know the land's beasts and monsters: what deer, stags, rabbits,
  boar and wolves are and do, what a hunter takes from each, and the imp, brute
  and sneak as goblins, instead of saying they don't know what a stag is.
## v0.1.149

- This release changes what the server and client send each other, so update the
  client to keep playing (the launcher's update does it). New in it: human bodies,
  male or female, chosen in the Options panel (O); anti-aliasing (SMAA by default,
  under Video); seasons with snow where it is cold; the temple and the healer's hut
  in the wilds; roofs, which storms can break; gear that takes its holder's name;
  arrows in bundles; music; and many new sounds. Details below.
- A companion who goes by "they" now has a body of her own, one or the other,
  the same every time, instead of always the woman's.
- Wildlife lives in the world now: herds of deer, rabbits, boar and wolves roam the wilds, breed and are thinned by wolves even with nobody about, and appear near you as you come. What you hunt down is gone from the herd.
- The menus have sounds: buttons click when pressed and tick under the pointer, a volume
  slider clicks as you let it go, the options panel and the pack sound as they open and
  shut, someone else's chat pings, a party message chimes, and a shop's refusal buzzes.
  Their loudness is the UI slider (O).

- Your companion follows at your heel, a step or two behind the way you face,
  instead of closing in ahead of you, so you no longer walk into her.
- Your companion knows where she is (the open land or old stone halls, and
  the place's name), the town she rests in between trips and her trade
  there, and what the town's lore says she knows; and she sees other
  players, companions and townsfolk as friends, by name.
- Townsfolk are named with their profession in brackets over their head, "Bram
  [smith]", and the party log names them the same way when raiders carry one off.
- Players and companions are people now, not capsules: a man or a woman in a tunic
  in your colour, trousers and boots, walking, running, fighting and falling with
  the same moves as the goblins.
- Options (O) has a Character section: choose a male or female body. It shows from
  your next join. Companions have their own (Pip a man, Wren and Nix women). The
  client must be updated with the server.
- The 3D view's edges are smooth: anti-aliasing (SMAA) is on by default. Options (O) has a new Video section to choose Off, FXAA, SMAA or MSAA 4x; `antialias=` in settings.cfg keeps the choice. Client only.
- The land keeps the seasons: grass dries toward straw out of season and browns in autumn, broadleaf trees turn gold, orange or rust in autumn and fade in winter, pines and the border's stands stay green, and in winter snow lies on the ground and on the tops of trees, never on slopes or a building's floor.
- A building with taller walls than a house's, as the temple's, has them drawn up to its roof, its door with wall over it.
- Storms can break roofs: a full storm breaks about one roof in four, open
  to the rain and the sky until someone mends it.
- A damaged building's roof is broken in places: rain and daylight come in through the holes. The client must be updated with the server.
- Fights and handling things sound like it now: a sword, a hammer and bare fists each hit
  differently, two-handed weapons swing heavier, blows land on shields and blades, a
  knocked-down body thumps, and the fallen hit the ground. People grunt with effort and
  pain, and goblins yelp when struck and mutter while idle. Things put down, picked up and
  thrown clink or thud by their weight, a chest's lid shuts, doors creak under blows and
  splinter, a key turns in a locked door, and a body shoved into water splashes.

- The wilds town has a temple beside its square. Out by the south edge of the forest stands a healer's hut, with a path from the town.

- Coming back to a zone after a long time away no longer brings every dead
  monster back at once round you: they return one at a time, about every 6
  seconds, the farthest from you first, and none within 12 tiles of you for
  the first moments after you arrive.
  the first 10 seconds after you arrive.
- Arrows come in a bundle held in the hand your bow isn't in. The bow is one-handed now, and it draws only with a bundle in the other hand. Shooting never uses the bundle up, but blunt hits on you (a hammer, being knocked into something, a knockdown) wear it down, 1 of 10 each, and at 0 you can't shoot until the fletcher mends it. Flame arrows set what they hit burning, and barbed arrows make it bleed until bandaged. Burning and bleeding bodies show it in their name's colour.
- Builder mode can roof a room you walled yourself or an open shelter on
  posts, such as a market stall or a woodshed, and the proposal outlines
  the new roof.
- Music: soft layers of drones, pads and a sparse melody that come and go in phrases, each
  place its own (a town, the open country, dungeons and caves), with night versions. When
  something hostile is near and hunting or fighting you, a tension layer rises and the rest
  steps back, then eases off once it's over. Short cues mark a new place, the first sign of
  danger, a goblin's rout and your death. Turn it down or off with the Music slider (O).

- A named thing taken by someone other than its namer, and not handed over by them, is kept from its namer: "ill-starred", its slot rust-coloured, and ill luck gathers while it is held, until it is back in its namer's hands. What ill luck does waits on Jeff; for now it is only counted and shown.
- The forest round outdoor maps gets ready for crowded stands of bare-trunked pines over a floor of needles past its first row of trees, as in Jeff's reference photo; they show once their art is in, and until then the forest looks as before.
- An experiment, off unless switched on at the server console: a companion's
  voice can be given by Claude (Haiku or Sonnet) instead of the box's model,
  falling back to it on any failure, with what each line cost logged.
- A weapon, shield or tool you carry for a long time, and fight with, takes your name for life ("Wren's dagger") and one strength from how you used it: steady, quick, set, quiet, heavy or dread. Never more damage. Names show on the pack slot's hover and in the party log. Lore's name form still waits on Jeff's yes, so nothing is named in play yet.
- Sounds for 44 more slots from Freesound, 77 takes (free licences, each credited in THIRD_PARTY.md):
  deer snorts, wolf howls and yelps, boar grunts and squeals, rabbits and deer crashing
  through brush, goblin chatter, screams and pain, men's grunts and death cries, footsteps
  on stone, sand and shallow water, wooden chests, dropped and picked-up items, a splash,
  shield and weapon blocks, blows on armour, punches, body falls, door bars and bolts,
  falling stone, a town at night, and the menu's clicks, page turns and chimes. Some aren't
  heard in play yet, until the actions that make them are hooked up.
- The game's folder now holds THIRD_PARTY.md, the credits: who made the
  sounds, art and tools the game uses, and their licences.
- Seasons: spring, summer, autumn and winter turn on the world clock, a
  week of days each. Winter days are shorter and the sun hangs lower, so
  nights are longer for everyone; grass dries and turns in autumn, and in
  the cold rain falls as snow and lies on the grass. Falling snow hides
  you a little, like light rain.
- Server console: `season <name>` and `season_days <n>` (also `--season`,
  `--season-days`).


## v0.1.148

- Update the client to see the new Hills map, the boars and the stumps:
  the server is new too, but an older client still joins (no protocol
  change).
- Stumps in the forest: now and then a tree at the forest's edge has been
  felled, and stumps lie among the trees. Fallen logs and dead trees will
  join them when their art is made.
- Boars in the wilds are drawn as boars now, not stand-in shapes: they
  walk, run, graze, lift their heads when they hear you, headbutt, flinch
  when struck and fall when killed. Deer, stags, wolves and rabbits follow
  as their art lands.
- The Hills, a new outdoor map west of the wilds (a link on the wilds' west
  edge): a valley with a stream (a ford and a stone crossing), rolling rises
  and a dry gully, a knoll crowned with trees, and a plateau with a sheer
  cliff, a flight of stairs standing out from it, and terraces up its south
  side.
- Spoken to, a resident also knows what they owe the town's bank, and
  whether they are working that debt off by hauling.
- Builder mode can shape the ground's height: raise or lower cells, make a
  hill with stairs up its sides, or put stairs onto a ledge. The proposal's
  ghost shows the new heights, lighter the higher, and Claude is told when
  something is left stranded on a ledge with no way up.
- The level editor can paint heights. `H` raises the cells under a brush a
  level (right click lowers, Shift+click sets a level, Alt+click picks one
  up); `S` drags out a stair or a flight of them; the area panel raises,
  lowers or levels an area, or makes a hill in it. Each cell is tinted and
  numbered by its level, with cliffs and the way each stair climbs drawn,
  and the status line shows the level under the cursor. `height.png` is
  now saved whenever a height changed.

## v0.1.147

- The town's gold is now a bank: a resident short of gold borrows from it
  (10% interest, up to 30 owed), pays it back from what they earn, and one
  who owes too much works it off as town labour. The town feeds people for
  free only when the bank can't lend. Rent is 1 gold a day.
- Spoken to, a resident now knows how they've been getting by: what they
  last bought or sold and from or to whom, a fee paid or earned, whether
  the town fed them free or they went without (and since when), and how
  many of the town are on its dole.
- A town starts with 150 gold spread evenly over its residents' purses; its
  treasury starts empty and lives on taxes and on what its materials sell
  for, and pays only official jobs (guards, haulers) and the building and
  repairs it orders. Makers earn from what they sell. Residents spend their
  own gold: meals from the shop (or the store's food), a bed at the inn,
  mending from the carpenter and tool work from the smith. The town feeds anyone
  with no gold, and its kitchen then works for food first; the party log
  says how many are on the dole. Rent falls due once a day.
- Monsters and other players no longer hop forward over a laggy connection: a
  step that arrives late plays out a little faster instead of jumping, and a
  server hiccup freezes the view for a moment instead of snapping it back.
- What raiders carry off from a town is kept at their camp, not lost.
- Your character no longer snaps when the server puts them somewhere else: they
  slide there quickly instead. A walk you start after being knocked back starts
  from where you are drawn, without a hop back first.
- Monsters can pick up a weapon left lying beside them, and fight with it.
  What a monster carries now makes it heavier to shove.

## v0.1.146

- Spears reach two cells, through an empty one. Stand still a moment and the
  spear is braced: a charging boar or brute that runs onto it is stopped,
  hurt and thrown back by its own weight.
- The giant axe is slow but sweeps the three cells in front of you, and knocks
  everyone it hits off their feet for a moment: lying, they can't act and are
  easily shoved.
- Shields block: raised with the right button, a shield takes blows and arrows
  from the front for stamina. A brute's heavy blow, or running out of
  stamina, breaks your guard and staggers you. A sword parries half a blow
  from straight ahead.
- Companions speak only for themselves: no more putting words in your mouth
  or telling you what kind of person you are.

## v0.1.145

- Weapons change the blow: a war hammer knocks foes back where a fist would
  not, a dagger is quick and strikes twice as hard from behind, a giant axe is
  slow. Monsters can be given weapons too.
- Companions bring up the hour and the weather when you ask about them (or
  in a storm), not in every other line.
- The camera no longer jumps when the game corrects where your character is
  drawn: it glides over the gap in a few frames, and still follows a
  knockback exactly.
- Bows shoot: draw with the right button and let go, and the arrow hits the
  first creature on the line toward the cursor, up to 8 cells. A longer draw
  hits harder. Stepping while drawn starts the draw again. Bows need no arrows.
- Talk to the town's residents: stand beside one (or say their name) and
  they answer, about their work, what the town is short of and what the
  shop has. They keep quiet while raiders are about.
- Loot tables: a level or the builder can name a table for a chest or a monster.
  A chest is stocked from it when the level is built, and a monster carries
  its share and drops it where it falls. No real level uses one yet.

## v0.1.144

- New things for hunters: a cut of meat (banks as food), a raw hide, a pair of
  antlers and a pair of tusks, ready for the animals to drop.
- Companions leave deer, stags, rabbits and boar alone unless you say "Get
  them!" with one in front of you. They keep still and quiet while you
  stalk, warn you of wolves at night, and remember the game you bring down.
- Raiders can carry off a companion who stays in town while nobody is there.
  A companion taken in a raid is held at the raiders' camp; rescue her and
  she waits in the town for her player.
- Monsters work out their way faster, most where they first move after players
  arrive: the server's tick with 9 players nearby is about a fifth shorter.
- Controls: the right button now does what your off hand holds. With a shield it
  blocks while held; with a bow it draws, and letting go shoots at the cursor
  (what a block or an arrow does in a fight comes with combat). With empty
  hands it still shoves and tosses. Opening chests, crates, carts, doors and
  your companion's pack moves to E; hold E to bandage.
- The town's residents are people you can see: each goes about their day
  by the clock, at their workshop, at home or in the square, with their
  name and trade over their head, and hides indoors when raiders come.

## v0.1.143

- You can see the weather outdoors: rain falls (and stops at roofs), fog
  rolls in along the ground, clouds cast drifting shadows and grey the
  sky, and the wind leans fires, torch flames and grass.
- Server: `--weather=<kind>` starts the world in that weather.
- Companions know the weather when outdoors: rain, fog, wind, a storm or a clear
  sky.
- A deer or stag that hears you lifts its head with a quiet snort: freeze
  before it sees you.
- You can see where a road leads: from the end of the wilds' castle road
  the castle's wall and gate stand beyond a band of trees, and from the
  castle the road south runs on into the wilds.
- The forest goes on past the edge of outdoor maps: dense treetops as far
  as the view reaches, so panning near an edge no longer shows a void
  under the map.
- Wild animals have their own steps: hooves for deer, stags and boar,
  soft paws for rabbits, clawed paws for wolves; a boar squeals as it
  turns to charge.
- Raiders can travel the land now: a raider camp sends groups at a town,
  which walk the roads and raid it, carrying off food and people to the
  camp; in an area where you are, they arrive as real raiders you can
  fight. Off for now, until there are camps to raid from.
- Cave walls are ready for maps that ask for them: rough rock, thick at
  the foot, with ragged tops, and a rock floor.
- A damaged building's walls are broken in places too, not only its roof.
- A town's wall shows how far the town has built it: a tumbled bank of
  rubble at first (it still stops you), then a wooden palisade, then stone,
  then stone with towers at its corners and gates; broken in places after a
  raid.
- Homes are built of wood: timber walls a little thinner and not quite
  straight, and plank floors inside. Maps can say which set their walls and
  floors are drawn in (castle, wood, stone or cave); every map today keeps
  its castle walls.

- A companion beaten down by raiders is carried off, not killed. They are held
  until freed, and then wait for you in the town that freed them. Companions who
  saw it remember it.
- A map: a small one in the top right corner follows you, and M opens the
  whole area, with the town, the start, the roads out and your companion
  on it. The mouse wheel zooms it.
## v0.1.142

- Seven weapons exist as things you can carry: hammer, sword, shield, giant
  axe, spear, dagger and bow, each with what it will do in a fight
  (knockback, block, knockdown, reach, backstab, range). The smith makes
  them. They don't fight differently yet.
- The world has a sound of its own: outdoors a dawn chorus, birds by
  day, crickets and owls by night, wind, rain and storms as the weather
  turns, a market's bustle near a town's buildings, a cave's hush
  underground, and the crackle of a fire or torch as you come near. It
  all fades from one to the next as you move, as the day turns and as the
  weather changes; under a roof the outside is quieter and muffled.
- Rain and wind now cover sounds for you as they do for monsters.
- A goblin that spots you and calls its pack is heard calling (a brute
  lower, an imp higher), and a smashed crate or cart sounds like one.
- The town's smith makes knives, axe heads and nails from ore, and its
  cook makes travel rations from food, for the shop.
- A town in the wilds, by the pond and the shack: a stone square with a
  well, the town's store (its depot and shop counter), a forge and a
  kitchen, three homes, lanes between them, and a dirt road north to the
  castle. New players start in the square.
- Companions know the hour (dawn, dusk, the middle of the night) and whether
  they are outdoors, indoors, in a cave or deep in a dungeon.
- Builder mode knows the town's store: Claude stamps one (yard, depot, shop counter)
  when asked, and you and Claude are told when a change leaves it wrong (a counter
  outside the store, a store with no depot).
- Food: a travel ration, eaten from the pack (right-click), makes you
  heavier and harder to shove for three minutes; the top of the screen
  shows it and the time left. Buffs never stack and never take you below
  what you were.
- Right-click a thing in your pack to use it: a coin purse opens into
  your gold. Keys open their locked doors when you carry them (none in the
  world yet). Things you put down or throw land with a thud that monsters
  hear, louder for heavy ones.
- Companions can bandage: ask yours to bandage you, or they see to their own
  wounds, with a bandaging kit and no danger near. Companions no longer heal
  on their own; like you, they mend when bandaged.
- First real recorded sounds in place of stand-ins: swings, doors opening
  and shutting, footsteps on grass and on dirt, and a goblin's death.
  More are ready for when the game makes them (bandaging, a sword cut, a
  blow on wood, a crate smashed, a goblin calling its pack).
- A forge, kitchen or inn that a map shows standing, the starter town's or one
  you tie to a town in builder mode, now counts as built for that town at
  once: its workers start work there instead of waiting for it to be built.
- Builder mode: accepting a change no longer sends players across the map. Someone
  standing where a pond went in steps out to the nearest shore, and players near
  monsters stay where they were.
- Builder mode can make a building serve a town (a forge, kitchen or inn, tied to
  the town's store) and wall a town in, with gates. A new area beyond an edge is lit
  like the level it leads from (outdoors, a cave, a dungeon).
- Turning the camera in the wilds is smooth again: it was re-fading every
  tree on the map each frame (14 fps while turning, now as fast as standing
  still).
- Monsters have tempers. Bold ones fight to the end and chase you farther;
  cautious ones hang back until a friend is at you and call for help when
  they spot you; cowards call, hang back longer and run early. A badly hurt
  monster breaks and runs ("~" over its name), and its running can set
  off the cowards and the wounded around it, while the bold ones fight on.
- Monsters that hear a call for help come after whoever the caller is
  fighting, opening doors to get there.
- Changes what the server sends (a monster can now be running): the server
  must be updated with this release.
- Your pack and chests show each thing's picture, drawn from its model,
  with its name under it.
- Weather outdoors: clear spells, overcast, rain, fog, wind and storms
  come and go on the world clock, each region by its own climate (the
  Blood Rot's land is foggier). For now this changes play, not the look:
  fog and rain shorten how far monsters see (a lantern still shows),
  rain and wind cover footsteps and other noise, and clouds dim the day.
  Rain, fog banks and wind on screen come next. Rooms, caves and
  dungeons are untouched.
- Server console: `weather <kind> [<minutes>] [<region>]` sets the
  weather for a while; `weather auto` hands it back to the climate.
- Levels can say which region they are in (`"region"`, a lore region).
- A town's buildings show their state: after a raid a damaged forge, inn or
  kitchen has a caved-in roof, and it stands whole again once the carpenter
  has repaired it. Its inside still works. Needs the server updated.
- The server no longer freezes for over half a second when someone enters
  the wilds for the first time or accepts a builder change there: reading
  a big level is about five times faster, and an accept no longer re-reads
  every level in the world (650 ms to about 180 ms).
- A light blow no longer knocks its target back: a punch hurts, and only
  a heavy hit (or a shove) sends someone sliding. Imps and brutes no longer
  push you about with every hit, and your punches no longer bounce an imp
  away from you.
- Builder mode can make a town's store: ask for one and you get an open
  yard with its depot (what you put in is banked) and its shop counter,
  and the ground they stand on becomes the town's store. You can also
  turn any chest into a depot or a shop counter, and builder mode warns
  when one stands outside the town's store or a store has no depot.
- You hear what monsters hear: a sound carries exactly as far as a monster
  standing where you are would hear it (a footstep 2 to 4 cells by the
  body, a fight 5, a door 6, a shout 20), fading as it goes and silent
  beyond. Through a wall or a shut door it carries half as far, muffled.
  Footsteps sound of the ground and the size of who walks (stand-ins for
  now).
- O opens the options: volume sliders for master, effects, voices,
  ambience and interface, remembered in settings.cfg.
- Walking into your companion in a narrow corridor no longer bounces you
  back: with no room to step aside, they swap places with you.
- Companions remember: what they have seen with you (a friend falling, a
  brute brought down, a close call) and what they have told you about
  themselves become part of who they are. Play along with a story about
  their past and it stays true from then on. What they claim about the
  wider world stays their belief, not fact.
- Every companion is now someone of their own: where they were born, their
  family, their trade, what they like to eat and do, what they fear, how
  they talk, and how the two of you met, rolled when they join you, with
  a name. Their character is written from that once, and they speak from
  it. Pip, Wren and Nix stay as they were named (Wren and Nix are women;
  Pip is a young man who wants to become a squire) with the rest of their
  story rolled, and rest in the town between your trips.
- Behind the scenes, towns can now be raided. Raiders who reach a town
  are fought by its walls and residents. Whatever gets past takes food
  and may carry a resident off, and can damage a building, which a
  carpenter then repairs. Raiders never take gold, materials or the
  town's progress, and anyone carried off waits to be rescued. No
  raiders set out yet.
- Big outdoor maps like the wilds load in about half the time (about 3 s
  instead of 6 to 7 on a fast machine).
- Behind the scenes, the game can now use sounds from licensed sound
  libraries that may not be shared publicly: they are kept on our own
  storage and added to the game when a release is built.
- Day and night outdoors: the sun rises in the east and sets in the west
  on the world clock, a day every 90 minutes, with warm gold dawns and
  dusks and blue moonlight at night. The clock stops while the server is
  down, like the rest of the world.
- Night is darker for monsters too: out in the open at night, without a
  light, a goblin facing you only glimpses you and comes to look. A torch,
  a fire or your lantern shows you as before. Inside buildings, light
  doesn't change with the hour.
- Server console: `hour <h>` and `day_minutes <m>` set the time of day and
  the day's length (also `--hour`, `--day-minutes`).
- Levels can say what kind of place they are (`"zone"`: outdoors, indoors,
  cave or dungeon); `"outdoor": true` still works.
- Indoors, caves and dungeons each have their own darkness: rooms are dim
  but you can be seen, in caves you're only glimpsed, and in dungeons a
  goblin can't see you at all unless you carry a light. Torches, fires and
  lanterns now light a clear pool on the ground, at night outdoors too, so
  you can tell where you'd be seen.

## v0.1.141

- A companion left in a town works there while you are away: tell her to
  stay on the town's stockpile ground before you travel on, or log off
  while she stands there, and she works her trade (Pip as a carpenter,
  Wren as a cook, Nix as a smith) until you come back for her.
- Behind the scenes, the world now has a written record of its facts
  (the town, the Blood Rot and their mine, the fallen star, the tower),
  each saying who would know it: common talk, rumour, secret, or
  something only one person lived through. Nothing here is confirmed
  yet, so companions don't use it until it is.
- Companions see when a door is locked, and don't offer to open one
  they have no key for.
- Companions with no player near enough to hear them stay quiet instead
  of calling the voice model (a few percent of its calls).
- You now have your own gold, shown above your pack. You keep it when you
  die. Towns can have shops: beside a shop counter you see what the town's
  workers have made, priced by how much the town needs it, and buy it
  with your gold. Put something the town is short of into the counter and
  it pays you for it. A share of every sale goes to the town, and the
  rest to the resident who made the thing. No town has a shop counter yet.
- Companions can hand you what they carry, and fetch something from a
  chest they can see and bring it to you ("I'll get you the bandages
  from the chest").
- Behind the scenes, every sound now has a name and a place: a list of
  91 sounds the game plays or soon will (footsteps by ground and body,
  hits by weapon, doors, chests, items, goblins, voices, menus, ambience),
  each playing today's sound where there is one. A sound not made yet
  plays a short blip instead, so gaps are easy to hear.
- Companions can do what you ask, and now say they will only when they
  can: open or shut a door they can see, look in a chest and tell you
  what is in it, or go and look at a dark or hidden spot nearby and come
  back to tell you what they saw. "I'll check the chest" with no chest
  in sight is no longer said. A monster coming near, a new order from
  you or taking too long calls them back.
- When the server is updated, everyone is told a minute ahead in the party
  chat, and the game reconnects by itself once the server is back,
  putting you where you stood (it keeps trying for 3 minutes).
- If the server has been updated past your game, the game updates itself
  and starts again, instead of just saying it is out of date. If a newer
  game is out but yours still plays, you're told so once.
- Builder mode and the level editor can lay buildings: a hut, a house and a
  shed, each a walled room with a door, stamped whole and turned as you
  like. They're grey stand-ins for now.
- Buildings have roofs, and a building's roof lifts away while you or your
  companion are inside it, so you see the room (its shade stays). It comes
  back a moment after you step out, and the building's walls on the
  camera's side go see-through while you're in. Seen from outside, a roof
  that hides you fades like a wall. A building's walls are whole and level,
  never ruined like the castle's.
- Wells: the well piece in builder mode and the editor now has a proper
  well on its water, its rim and little roof, instead of a bare pond.
- A client and the server no longer need to be the very same build to
  play together: only what they send each other has to match. A release
  that changes only how the game looks no longer needs the server updated,
  and the server no longer turns away such a client. When they don't
  match, you're told which side is behind: "client out of date" (update
  through launch.bat) or "server out of date" (the server is due an
  update). This release itself still needs the server updated.
- Two hands: your pack has two hand slots (R and L) beside its four. Some
  things take both hands; what you carry adds to your weight, so a loaded
  player is harder to shove.
- Put things down (G), pick them up (F) and throw them at the cursor (T).
  Light things fly across a room; a heavy sack goes a cell or two and
  staggers whoever it hits. Things on the ground stay there, saved with
  the world.
- Companions talk less and repeat themselves less. A line is not said
  again in other words, or with a curly apostrophe; a line another
  companion just said is not said again.
- They speak when something new happens (the first of a kind of monster,
  something big, the end of a fight that mattered), not for every imp that
  falls, and they no longer read back what just happened ("The imp is
  dead.") unless you ask.
- They speak to you, not about you: no more "Jeff is hurt" to Jeff.
- No more one- and two-word fragments ("Cylinder. West.") unless they
  are answering you or calling out a warning.
- About a third fewer calls to the companions' voice model
  (269 of 880 on the last week's logs), so the box's model has more room
  for the lines that matter.
- Companions see only what is lit and in their line of sight, and know of
  a death only if they saw it (no more news of a fight behind a wall).
- Companions hear fighting and doors they cannot see, and may tell you
  ("I hear fighting to the west").
- Crates and carts carry things: a crate holds 4, a cart 8. Right-click
  one beside you to open it; drag to toss it as before. A loaded cart is
  heavier to push, and a broken crate spills what it held.
- The ground has life on it: grass tufts, wildflowers, small stones, roots
  where the forest begins and reeds along the water, scattered naturally
  rather than in rows. Forests grow in clumps of trees of different sizes,
  and the land fades into the forest floor instead of ending in a stepped
  edge.
- The land's colours are softer and earthier: olive grass, brown earth,
  grey stone and muted water, from the game's shared art palette, so the
  ground sits with the rest of the art.

- Doors matter to monsters. Imps and sneaks open doors, but while looking
  for you only if they heard or saw something behind it: shut a door and
  keep quiet, and a monster that lost you will come to the door, listen
  and go away. A word or a fight behind the door brings it in. Brutes
  can't open doors at all; they break them down instead.
- Doors can be locked; a locked door opens only for someone with its key
  (no keys or locked doors in the game yet).
- Changes what the server sends (a door's lock): the server must be
  updated with this release.
- Young trees grow among the old along the forest's edge, so it no longer
  lines up cell by cell.

- You no longer heal on your own: bandage yourself or an ally out of
  combat (hold right-click). With a bandaging kit, hold the right mouse
  button on yourself or on an ally beside you for two seconds; once
  bandaged they mend 10 hp over the next while, even as you walk away.
  Getting hurt stops it. The kit isn't used up.

## v0.1.140

- The server no longer writes a log line for every door a monster opens
  or every blow that fails to shift someone: much less work in big fights.
- A little smoother with many players: monsters far from anyone stop
  looking about for someone to fight until someone comes near.
- Stairs are smooth ramps instead of steps, and the ground beside them
  slopes up with them. Ledges are rocky cliff faces instead of flat
  boxes, and the foot of each drop is shaded, so raised ground stands out.
- Characters, the cursor outline, the click ripple and builder previews
  follow the slope of a ramp.
- The town has a stockpile: a shared store of gold, ore, wood, cloth, food
  and gear. Whatever a player puts into a stockpile's depot chest is banked
  for the town at once, as long as the town holds that ground; picking
  loot up out in the world doesn't count until it's brought home. There is
  no town map yet, so no depot appears in the game's levels so far.
- The camera zooms out a little less far (to 1.1, from 1.4), and every
  monster you can see acts at full pace.
- Smoother server with many players on a big map: monsters far off
  everyone's screen stroll about more simply, and the server spends less
  time on monsters that are not due to act.
- Ponds and lakes are one body of water each, with a soft, irregular
  shoreline and foam instead of blue squares. They are slightly clear,
  deeper toward the middle, and ripple gently. Where water meets land is
  still exactly where you can and can't walk.
- Every item in the world is now one of a kind and remembers its story:
  where it came from, who has carried it and for how long, and who gave
  it to whom. Nothing shows it yet; it is kept from now on. Your packs
  and chests carry over as they were.
- Companions can hand things over and take them back, as players do.
- Behind the scenes: a door or other piece with its own moving part, made
  for the game, no longer logs a warning as it is drawn.
- Walls are continuous stonework instead of rows of identical blocks:
  their height rises and falls along a wall, tops are broken off here and
  there, and long walls sometimes have a collapsed stretch, a bank of
  rubble you still can't get through.
- Monsters are more or less alert, and show it: "?" over a monster's name
  means it heard or glimpsed something and is going to look; "!" means it
  is after you. Lose one and it searches where it last saw you and the
  way you were going, looks round, then gives up and goes back to its
  post. Run far enough from where it took up the chase and it gives up
  even with you in sight.
- Fighting draws nearby monsters (five steps away; through a wall they
  only come to look). A blow from one it can't see sends it after them.
- Changes what the server sends (how alert a monster is): the server must
  be updated with this release.

## v0.1.139

Client and server.

- Up to 16 players on a server (it was 4).
- Each player is now sent only what is near them (about 36 to 44 cells
  round them, further than you can see or hear), not everything on the
  map. On a big map with 9 players the server sends about a fifteenth as
  much while people join and a little over half as much after, and its
  tick is faster.
- Joining a big map no longer freezes the server for a second or drops
  players mid-join.
- A door you come back to no longer plays its swing sound if someone
  opened or shut it while you were away.

The server must be updated to v0.1.139 too, as it refuses any other version.

## v0.1.138

Client only.

- Behind the scenes: everything the 3D view draws is now a named art slot,
  so the game's own models can replace the borrowed ones one at a time.
  Nothing looks different yet.
- For checking sizes: `art_placeholders=1` in settings.cfg draws every slot
  as a plain grey box, and `art_labels=1` puts its name over it.

## v0.1.137

Client and server.

- Fewer stalls when players arrive somewhere busy: monsters that notice
  someone nearby start strolling about a moment apart, not all at once.

The server must be updated to v0.1.137 too, as it refuses any other version.

## v0.1.136

Client and server.

- Monsters see and hear. A monster sees in a cone in front of it, so you
  can slip past one that faces away. In the dark it sees only what is lit:
  press L to cover your lantern (and again to light it). A covered lantern
  is seen only from right beside you, or by someone else's light.
- Monsters hear footsteps, fighting, doors and speech. One that hears
  something turns to look. Words in capitals carry much farther; whisper
  with /w (heard only two steps away, by people and monsters alike).
- Monsters with no kind still see all round, as before.

The server must be updated to v0.1.136 too, as it refuses any other version.

## v0.1.135

Client and server.

- Big maps run far smoother on your screen: monsters out of sight no
  longer keep animating unseen. A large map went from about 14 frames a
  second to a steady 60 on the test machine.

The server must be updated to v0.1.135 too, as it refuses any other version.

## v0.1.134

Client and server.

- Fixed: a brute winding up a blow at a player who died or left meanwhile
  made the server log an error; it now swings at the air.

The server must be updated to v0.1.134 too, as it refuses any other version.

## v0.1.133

Client only.

- The ground no longer looks like tiles: grass, dirt and stone run into
  each other along ragged, natural edges, with no seams between cells.
  Stone floors are cobbled, dirt paths are brown, and the light from
  torches and fires fades smoothly instead of in squares.
- Fire on the ground is a flickering, ragged patch instead of a yellow
  square.

## v0.1.132

Client and server.

- Smoother server with many players on a big map: monsters strolling
  about walk straight to where they are going when they can, and monsters
  that cannot get through a crowd round someone stop trying every moment.

The server must be updated to v0.1.132 too, as it refuses any other version.

## v0.1.131

Client and server.

- Smoother server with many players spread over a big map: monsters off
  everyone's screen, with nobody to fight, think less often. Monsters in a
  fight still act every moment, wherever they are.

The server must be updated to v0.1.131 too, as it refuses any other version.

## v0.1.130

Client and server.

- Monsters walking back to their posts while nobody is near no longer
  cross ground another faction holds: they go round it, or wait at its
  edge.

The server must be updated to v0.1.130 too, as it refuses any other version.

## v0.1.129

Client and server.

- Monsters find their way about two to three times faster on the server:
  smoother with several players on a big map. They walk the same ways as
  before.

The server must be updated to v0.1.129 too, as it refuses any other version.

## v0.1.128

Client and server.

- Much smoother server with several players on a big map, apart from each
  other: monsters crowding round someone, or a crowd of them noticing
  players arriving, no longer stall the server for a moment.

The server must be updated to v0.1.128 too, as it refuses any other version.

## v0.1.127

Client and server.

- Monsters far from everyone, or in places nobody is, now really walk
  back to their posts after a fight, at their own pace, instead of
  appearing there.
- The world keeps its own clock across server restarts: it picks up where
  it stopped, and waits while the server is down.
- Steadier server on big maps: the world's slow background work is spread
  over many ticks so no single tick takes long.

The server must be updated to v0.1.127 too, as it refuses any other version.

## v0.1.126

Client and server.

- Builder mode can make somewhere new: pick an area on the edge of the
  map and ask for a new area beyond it ("somewhere new to the east", "the
  woods past here"). The new level is outlined in orange past the edge;
  kept, a path leads out to the edge, and walking off it takes you into the
  new level, a first draft of fields and groves ringed by forest, ready to
  build in. Ctrl+Z takes it all back (not while anyone is in it).

The server must be updated to v0.1.126 too, as it refuses any other version.

## v0.1.125

Client and server.

- Smoother on big maps when monsters walk through doors: working out the
  light and heat a door lets through is about four times quicker.

The server must be updated to v0.1.125 too, as it refuses any other version.

## v0.1.124

Client and server.

- Builder mode, for the people allowed to build (the host's own player;
  on the server, the players the server names): press B, drag out an
  area, and say what should be there ("a pond", "a goblin camp guarding a
  chest"). Claude proposes it as a see-through ghost over the area, with a
  line on what it made and what it cost. Enter keeps it, words in the box
  change it ("bigger", "move it north"), Esc throws it away, Ctrl+Z takes
  back the last change. Everyone in the area sees the change at once, and
  so does anyone who comes later.
- Keeping a change rebuilds the area: everyone stays where they are, but
  monsters and chests come back as the map has them.

The server must be updated to v0.1.124 too, as it refuses any other version.

## v0.1.123

Client and server.

- Big maps run smoother on the server: monsters far from every player
  think less often, and those farther still are moved on by a slow world
  tick instead of every tick. A monster left away from its post after a
  fight goes back to it while nobody is around, even in a zone nobody is
  in.
- The network log line for a correction now says how far off you were.

The server must be updated to v0.1.123 too, as it refuses any other version.

## v0.1.122

Client and server.

- Maps can now join edge to edge: walk into the side of one map where it
  meets the next and you step straight onto that map's matching edge, at
  the same place along it, your companion with you. No map uses it yet;
  new areas built off the wilds will.

The server must be updated to v0.1.122 too, as it refuses any other version.

## v0.1.121

Client and server.

- No change in play. Under the hood, one map of every area and the ways
  between them, checked as the game is built: a link with no way back, a
  missing arrival point or an area nobody can reach is caught before it
  ships. The groundwork for walking straight off one map onto the next.

The server must be updated to v0.1.121 too, as it refuses any other version.

## v0.1.120

Client and server.

- The Wilds: walk south from the castle, past the foot of its road, into
  open country, a big map of fields, groves and ponds ringed by forest. A
  path leads to a farmstead (two houses, fenced fields, a well, a chest in
  each house), and on to a goblin camp in the north-east, three imps round
  their fire.

The server must be updated to v0.1.120 too, as it refuses any other version.

## v0.1.119

Client and server.

- A faded wall is one clean see-through layer: no light seams where two
  wall pieces meet, no inside faces showing through, and no flicker as
  you or the camera move.

The server must be updated to v0.1.119 too, as it refuses any other version.

## v0.1.118

Client and server.

- Less rubber-banding when you walk or fight among monsters: the server now
  follows the way your client shows, and your character is pulled back far
  less often, and not as far, when monsters get in the way. Clicking a
  monster no longer sometimes walks you a step and pulls you back.

The server must be updated to v0.1.118 too, as it refuses any other version.

## v0.1.117

Client and server.

- Big maps run smoothly: a frame on a 256x256 map takes about a sixth of
  what it did. Doors, creatures and crates off screen cost next to nothing,
  and the server no longer checks every creature's visibility each frame.

The server must be updated to v0.1.117 too, as it refuses any other version.

## v0.1.116

Client and server.

- Big maps start faster again: the old 2D map is no longer drawn behind
  the 3D view (or on the server), a 256x256 map in 1.6 s, from 4.3.
- Only lights near what is on screen cast shadows.

The server must be updated to v0.1.116 too, as it refuses any other version.

## v0.1.115

Client.

- Maps load much faster: the 3D view of a big map builds about forty
  times faster (a 256x256 map in about a second, from 49 s), and a game
  you host builds its map once instead of twice.
- Opening a door no longer stalls a big map for a moment while the floor
  is shaded again: only the floor whose light changed is redrawn.

The server must be updated to v0.1.115 too, as it refuses any other version.

## v0.1.114

Server.

- The server copes with far more monsters on a map: what they cost it now
  grows with their number, not faster. A map with 3000 creatures ticks
  over ten times faster than before (the first step towards bigger maps).

The server must be updated to v0.1.114 too, as it refuses any other version.

## v0.1.113

Client and server.

- A wall behind you no longer fades when you stand next to it: walls fade
  only where they actually hide you or your companion from the camera (a
  whole wall at once, as before). A wall you step out from behind stays
  see-through a moment, so walking along one does not flicker.

The server must be updated to v0.1.113 too, as it refuses any other version.

## v0.1.112

Server.

- Your companion's AI was timing out (she fell back on her stock lines):
  the server's AI was set up on the wrong port. It now runs on the
  server's own graphics card.
- When she joins you, she asks the AI model to load straight away, so her
  first answer after a server restart no longer times out while it loads.

The server must be updated to v0.1.112 too, as it refuses any other version.

## v0.1.111

Server and client.

- Less lag with monsters about: the server's tick spiked whenever a monster
  went through a door or searched far for a way to you, and when your
  companion described what she sees; those are now several times cheaper
  (the castle's tick, worst case 19 ms to 8 locally).
- The outline on the monster your next click would attack is a little
  thicker, and off-white.

The server must be updated to v0.1.111 too, as it refuses any other version.

## v0.1.110

Client.

- The monster your next click would attack now gets a thin white outline,
  instead of the red ring and glow; the model itself looks as it always
  does.
- A monster that died while marked no longer keeps its tint.

The server must be updated to v0.1.110 too, as it refuses any other version.

## v0.1.109

Client.

- The monster your next click would attack is marked with a red ring at its
  feet and a red glow, and the floor square hides, so you can see whether a
  click will hit or walk.

The server must be updated to v0.1.109 too, as it refuses any other version.

## v0.1.108

Client.

- Clicking a monster is easier: a click just off its body, or behind your
  own character, now attacks it instead of walking you round it to the
  ground behind.
- Holding the left button to walk and bringing the cursor onto a monster
  attacks it.

The server must be updated to v0.1.108 too, as it refuses any other version.

## v0.1.107

Client.

- The middle-drag swirl that turned the camera is gone; A/D turn it, as
  before.
- A middle drag still pans the view, and now springs back onto you when you
  let go.
- A middle click no longer does anything (it used to recentre and reset the
  zoom).

The server must be updated to v0.1.107 too, as it refuses any other version.

## v0.1.106

Client.

- Swirl the middle mouse button round to turn the camera: clockwise turns it
  clockwise, anticlockwise the other way, settling on the nearest view when
  you let go, as A/D do. A straight middle drag still pans, and a middle
  click recentres the view on you.

The server must be updated to v0.1.106 too, as it refuses any other version.

## v0.1.105

Server.

- Fixed the server freezing when the first player logged in after it had
  run for hours with nobody on, which dropped them and kept everyone out
  until it was restarted.

The server must be updated to v0.1.105 too, as it refuses any other version.

## v0.1.104

Client.

- Idle goblins do more than look about: they mutter, take a swig, kneel and
  fiddle at the ground, stoop and crouch, each in its own time, so a group
  never moves in step.
- A goblin set to gather round a point can sit down on the ground there,
  and gets up when it has to move.

The server must be updated to v0.1.104 too, as it refuses any other version.

## v0.1.103

Level editor.

- A select tool (V): click a monster, turn its facing with Q / E or the
  wheel over it, and set how it idles in the panel on the right: guard,
  wander (and how far), patrol (click waypoints; loop or back and forth),
  gather (click the point), none, or its kind's own.
- Every monster shows its facing as an arrow; patrol routes and gather
  points are drawn on the grid.
- Ctrl+S writes these into level.json; monsters keep their names.

The server must be updated to v0.1.103 too, as it refuses any other version.

## v0.1.102

Server.

- Monsters no longer stand still waiting for you: imps wander about, brutes
  stand guard and glance around, sneaks patrol a short loop. They walk
  slower than when they chase.
- After a fight, a monster walks back to where it was and carries on.
- Levels can set each monster's facing and how it idles (guard, wander,
  patrol a route, gather round a point) in level.json; the level editor
  will set these next.
- The server no longer logs errors when a fight happens in one zone while
  a player is in another.

The server must be updated to v0.1.102 too, as it refuses any other version.

## v0.1.101

Client.

- Goblins are no longer one dull matte: their skin and leather have a sheen,
  their eyes are glossy, and their hood and cloth stay rough.
- Their eyes are yellow.

The server must be updated to v0.1.101 too, as it refuses any other version.

## v0.1.100

Client.

- Drag with the middle mouse button to pan the camera (click controls);
  a middle click brings it back to you, along with the zoom.

The server must be updated to v0.1.100 too, as it refuses any other version.

## v0.1.99

Client.

- Goblins have white eyes, a dark brow and mouth under the hood, and more of
  their face showing.

The server must be updated to v0.1.99 too, as it refuses any other version.

## v0.1.98

Server.

- Wren, badly hurt and retreating, no longer sprints back and forth between
  two spots: she picks a place well away from the monsters and keeps going
  there unless it stops being safe.

The server must be updated to v0.1.98 too, as it refuses any other version.

## v0.1.97

Server.

- Monsters spread out around you instead of lining up behind each other.
- Each fights its own way: some are quicker or slower, some hesitate, some
  hang back until others have joined in, and they no longer move in step.
- Imps dart in, hit, and back off while they recover.
- Brutes are slower but charge the last few tiles, and wind up a heavy
  two-damage swing: step away in time and it misses; shove them and it
  never lands.
- Sneaks are quick and fragile, and circle to your side or back; a hit
  from behind does extra damage.

The server must be updated to v0.1.97 too, as it refuses any other version.

## v0.1.96

- No two goblins alike: each is its own size (heavier ones are bigger),
  walks at its own stride, and they no longer breathe and step in time.
- They throw jabs, crosses and kicks, flinch in different ways, and die in
  one of two ways.
- A goblin left alone looks around now and then; a badly hurt or winded one
  stands tired.
- Brutes and sneaks are goblins too now, instead of capsules.

## v0.1.95

Network. Server.

- Others (Wren, goblins, other players) move smoothly on a client: no more
  stalls and little jumps when packets arrive late or bunched. They are
  drawn 150 ms in the past instead of 200 ms.
- Knockback looks the same on every client as on the host, at its proper
  (slower) speed.
- When you shove something while standing still, it flies back the moment
  you click, instead of a third of a second later.
- F3 shows your worst position correction; the server's admin console has a
  new `net` command (tick time, bandwidth, everyone's ping).
- An old display_delay line in settings.cfg is dropped; display_delay_ms
  can be set by hand.

The server must be updated to v0.1.95 too, as it refuses any other version.

## v0.1.94

3D view.

- Goblins run (jog, or sprint if they are fast enough) instead of walking
  at a run's speed, so their feet keep up with them instead of sliding
  along the ground.

## v0.1.93

3D and 2D views. Server.

- A push throws its target at half the speed it did, so you can see it
  fly back.

The server must be updated to v0.1.93 too, as it refuses any other version.

## v0.1.92

3D view. Server.

- Pushed goblins (and anything else knocked back) now always double over
  at the end of the push, even if they hit nothing, and are stunned for a
  moment before they can act or walk back.

The server must be updated to v0.1.92 too, as it refuses any other version.

## v0.1.91

3D and 2D views. Server.

- Knockback now works properly when you play on a server, not only when
  hosting: goblins backpedal facing you for the whole push, double over
  when they hit a wall or door, roll when tossed, and walk back facing you.
  Before, on a client, they could flip round, slide backwards without the
  backpedal, or never double over.

The server must be updated to v0.1.91 too, as it refuses any other version.

## v0.1.90

3D view.

- A goblin that comes straight back at you after being pushed walks back
  facing you, instead of turning round and backpedalling toward you.

## v0.1.89

3D view.

- A wall in front of you fades along its whole length, up to where it
  turns or another wall meets it, not just the piece by you.
- In a corner, the walls at your back no longer fade.

## v0.1.88

2D and 3D views.

- A knocked-back body no longer spins round to face where it is flung:
  it keeps its facing.
- A goblin knocked from behind or the side turns to face whence it came
  and back again afterwards, instead of snapping round.

## v0.1.87

3D view. Server.

- Goblins react to being knocked about:
  - pushed back (hit or shoved), they backpedal, facing you;
  - tossed, they roll over backwards and land;
  - slammed into a wall or a door, they double over.

The server must be updated to v0.1.87 too, as it refuses any other version.

## v0.1.86

3D view.

- Stone floors are grey. They were drawn with the kit's grass tile, which
  is why grey stone looked mint everywhere.
- Outdoors, the ambient light is neutral; it came from the sky, whose lower
  half is forest green, and tinted the whole castle green.
- Water shows in the castle: the forest floor lay above it and hid it,
  which is why it looked black. Water has a bed under it now.
- Walls (and doorways, posts and trees) fade only when they stand between
  the camera and you or your companion, and solid again once they don't,
  as the camera turns, tilts or follows you. The rest stay solid.

## v0.1.85

Companions. Server.

- A name in the middle of a line ("Hold, Cylinder, they're close.") now
  counts as speaking to that person, so the once-a-minute rule for other
  players holds there too; your own name in the middle comes off.
- When she calls someone by name, "I" and names after it keep their
  capitals ("Cylinder, I see it.", not "Cylinder, i see it.").
- She never says "A moment passes." aloud.
- Pip talks in short, whole sentences, not a few words.

The server must be updated to v0.1.85 too, as it refuses any other version.

## v0.1.84

Companions. Server.

- Your companion talks to **you**: no more "Jeff, ..." at the start of
  every line, or a bare name tacked on the end (she still calls your name
  from across the room).
- She leaves other players alone: she answers them when they speak to her
  by name, and otherwise only warns them once a minute when they're in
  danger.
- Your words go to your own companion; someone else's answers only if you
  say her name.
- She doesn't repeat herself: nothing she said in her last few lines, not
  even a one-word fragment. And always one reply at a time.
- She mentions her lantern and bandages only when you ask what she's
  carrying.
- Nix talks in short, whole sentences now, not single words, and never
  narrates what he's doing.
- A companion's last words are in her transcript.

The server must be updated to v0.1.84 too, as it refuses any other version.

## v0.1.83

Monsters.

- Fixed: goblins faced away from where they were going, so they walked
  backwards and fought facing away. They face forward now.

The server must be updated to v0.1.83 too, as it refuses any other version.

## v0.1.82

Monsters.

- **Imps are goblins** now, in place of red capsules: they stand idle,
  walk, punch when they attack, flinch when they're hit, and fall when
  they die. Brutes and sneaks are still capsules for now.

The server must be updated to v0.1.82 too, as it refuses any other version.

## v0.1.81

Maps. Server.

- **Outdoors**: the Castle is now outdoors, in daylight under a sky, with
  a forest all around its edge instead of the black void and outer walls.
  The forest edge blocks you the same way the walls did. The castle's own
  walls are still walls.
- Your companion knows when she's outdoors.

The server must be updated to v0.1.81 too, as it refuses any other version.

## v0.1.80

Maps. Server.

- **The Castle**, a new map. From the test room, walk to the far end of
  the long corridor in the south-east corner and step onto the link there.
  The castle's own link, beside where you arrive, brings you back.

The server must be updated to v0.1.80 too, as it refuses any other version.

## v0.1.79

Level editor. Server.

- **A level editor**: run the project with `--edit=<map>` to paint
  `levels/<map>/layout.png` on a grid, or start a new map. Pick ground,
  water, fire, stairs, monsters, crates, chests, torches, starts and links
  from the palette (or number keys) and paint them; with wall, door or
  clear picked, click or drag along the lines between cells. Right click
  erases, Ctrl+S saves, Ctrl+Z undoes. See docs/levels.md.
- A map saved in the editor plays straight away when you run the project
  with `--map=<map>`.

The server must be updated to v0.1.79 too, as it refuses any other version.

## v0.1.78

Companions. Server.

- Fixed: after you left and came back, a right click on your companion
  shoved her instead of opening her pack, because she no longer counted as
  yours. She does now.

The server must be updated to v0.1.78 too, as it refuses any other version.

## v0.1.77

Packs. Server.

- No more jingle when you put something in a pack: it's just leather now,
  and a little louder.

The server must be updated to v0.1.77 too, as it refuses any other version.

## v0.1.76

Packs and chests. Server.

- Moving an item sounds like where it goes: a thud into a chest, leather
  into a pack.

The server must be updated to v0.1.76 too, as it refuses any other version.

## v0.1.75

Packs and chests. Server.

- New sounds: a chest opens with a soft thud (no more creak), a pack opens
  with a leather rustle, and moving an item makes the chest's thud.

The server must be updated to v0.1.75 too, as it refuses any other version.

## v0.1.74

Packs and chests. Server.

- Right click an open chest (or your companion, with her pack open) to
  close it again.
- New sounds: opening a pack now makes the soft thud, and moving an item
  makes the chest's creak.

The server must be updated to v0.1.74 too, as it refuses any other version.

## v0.1.73

Packs and chests. Companions. Server.

- **Right click** a chest to open it (from further off you walk over
  first). A left click on a chest now just walks you to it.
- **Your pack**: what was "slots" is now your pack, titled with your name
  ("Jeff's Pack"). I still shows and hides it.
- **Your companion's pack**: right click your companion to open hers
  ("Wren's Pack") and drag things between your packs. Only you can get at
  it, and she knows what she's carrying.
- **Sounds**: a chest creaks open, a pack rustles open, and an item
  clunks as it lands.

The server must be updated to v0.1.73 too, as it refuses any other version.

## v0.1.72

Server.

- The test room's new chest is there straight away on a server that was
  running before it was added, rather than turning up a minute later only
  once nobody was near the start.

The server must be updated to v0.1.72 too, as it refuses any other version.

## v0.1.71

Slots and chests. Server.

- **Slots**: you have 4, shown at the bottom right; I shows and hides them.
- **Chests**: click a chest when you're beside it to open it (click one
  from further off and you walk over first). Drag things between the
  chest and your slots. Everyone sees the same chest.
- The test room has a chest beside the start with a **bandaging kit** in
  it. It does nothing yet.
- What's in chests and in your slots is kept across restarts, deaths and
  trips between maps.

The server must be updated to v0.1.71 too, as it refuses any other version.

## v0.1.70

Companions. Server.

- A server can give companions' voices a model of their own, on another
  machine (`PSYKINETIC_VOICE_URL`, `PSYKINETIC_VOICE_MODEL`), while their
  quick decisions stay where they are.
- Asked about something she hasn't seen, she is reminded that a flat "no"
  would claim she knows.

The server must be updated to v0.1.70 too, as it refuses any other version.

## v0.1.69

Companions. Server.

- **Questions don't change what she does**: only something you actually ask
  her to do (stay close, hold, attack, guard, fall back) changes her
  stance. Questions, remarks and things she can't do with her hands don't.
- Asked about something she hasn't seen, she is left to find out what you
  mean in her own words.

The server must be updated to v0.1.69 too, as it refuses any other version.

## v0.1.68

Companions. Server.

- Ask about something she hasn't seen and she asks back ("What door?")
  instead of telling you there isn't one.

The server must be updated to v0.1.68 too, as it refuses any other version.

## v0.1.67

Companions. Server and client.

- **She knows what she has seen**: ask about a door, fire, water or a
  crate and she answers from what she can see, what she saw earlier, or
  what she can feel; if she hasn't seen one, she says so instead of making
  it up.
- **Talks to you, not about you**: she calls you "you", never repeats your
  instructions back or describes herself, and says distances as "close by",
  "a few paces", "some way off".
- **Names matter**: a line naming someone else isn't for her; a line
  naming no one, she answers only if she has something useful.
- The controls list has a darker backing, easier to read.

The server must be updated to v0.1.67 too, as it refuses any other version.

## v0.1.66

Companions. Server.

- **Companions hear everyone nearby**: what any player (or companion) says
  within earshot reaches every companion there, who knows who said it.
- **She knows when it isn't for her**: talk to the other player and your
  companion keeps quiet; say her name, or speak to her with no one else
  around, and she answers.
- She knows who else is around, and where.
- A fallen player still hears what is said nearby.

The server must be updated to v0.1.66 too, as it refuses any other version.

## v0.1.65

Chat. Server and client.

- **Speech carries, but not far**: what you say, and what companions say,
  is heard only by players on the same map within about ten steps. Your
  companion hears you only from that close too.
- **Party chat**: start a line with `/p` to reach every player on the
  server, on any map. It shows in green in the talk panel, and companions
  never hear it.

The server must be updated to v0.1.65 too, as it refuses any other version.

## v0.1.64

HUD. Client.

- **A proper compass**: bigger, with a ring of ticks that turns with the
  camera and N, E, S, W that stay upright (N in red).
- **Controls list**: the controls are now a tidy list down the left side.
  Press H to hide or show it; the game remembers.
- The top line shows just who you are, your HP and the tick.

The server must be updated to v0.1.64 too, as it refuses any other version.

## v0.1.63

Companions. Server.

- **Quick phrases always work**: 1 With me!, 2 Stay back!, 3 Get them!,
  4 Fall back! change what your companion does at once, and she still
  answers you.
- **Calm, she follows**: with nothing hostile near and nothing asked of
  her, she keeps with you; she only weighs up what to do in a fight.
- She only holds a spot when you ask her to.
- **Smoother following**: she lets you get a couple of steps ahead, then
  catches up, instead of stepping at your heel.

The server must be updated to v0.1.63 too, as it refuses any other version.

## v0.1.62

Zones. Server and client.

- **Many maps at once**: every map is its own place on the server, with
  its own monsters and things, and stays as you left it.
- **Links take you, not everyone**: step on a link and you and your
  companion go to the other map; the others stay where they are. The test
  room has a link in its top-left corner to the sample map, and back.
- You see only the map you are on. A map nobody is on sleeps until
  someone arrives.
- The server remembers which map you were on, and puts you back there.

The server must be updated to v0.1.62 too, as it refuses any other version.

## v0.1.61

Light, heat and directions. Server and client.

- **Heat and light**: fires, torches, lanterns and the lantern everyone
  carries give off light and heat that fall off with distance and stop at
  walls and closed doors. Standing in fire, or hemmed in by it, burns. In
  3D the floor glows warm around fires, and dark levels get darker away
  from the lights.
- **Compass**: every map has a north. A small compass on the screen shows
  it, turning with the camera; F3 shows which way the camera faces.
- **Companions speak in compass directions**: "the fire is two paces to
  the north", never "to my left". She also says when she feels heat, or
  when it's dark past a door.
- Levels can set their light (`ambient`) and north, and hang lanterns.

The server must be updated to v0.1.61 too, as it refuses any other version.

## v0.1.60

Companions. Server.

- **She answers when asked**: a question to a companion always gets words
  back, never silence; "..." is only for moments nobody spoke to her.
- **Sharper sense of what is around her**: she is told what she can see as
  a short list, each thing with how far it is and where (beside you,
  between you and Jeff, behind Jeff, up on the ledge): monsters, anything
  within two paces, and whatever you just asked about.
- **Perception is a setting**: `--perception=list|grid|both` (or
  `perception` on the console) can give her a small map of what she sees
  instead of, or as well as, the list. The list stays the default; see
  docs/perception_eval.md for how the three compare.

The server must be updated to v0.1.60 too, as it refuses any other version.

## v0.1.59

Companions. Server.

- A companion stops going on about the same fire or crate: she mentions
  her surroundings when something there is new, or when you ask about them,
  and knows what she has already talked about.
- While you are down she still knows your name (the transcript no longer
  calls you "the one you travel with").
- Rebuilt transcripts no longer repeat the stretch around a fall.

The server must be updated to v0.1.59 too, as it refuses any other version.

## v0.1.58

Server.

- Rebuilt transcripts no longer repeat stretches of the conversation, and
  their times run in order.

The server must be updated to v0.1.58 too, as it refuses any other version.

## v0.1.57

Companions. Server.

- **Monsters by kind**: companions now speak of "an imp" or "the brute",
  never "Imp2".
- **Fewer kill calls**: a companion comments on a monster's death only if
  it was a brute or bigger, it fell next to you, or it was the last one
  of the fight. An ally falling always gets a word.
- **Transcripts rebuilt**: the server can rebuild past conversations from
  its log, your lines included (`transcript rebuild` on the console).

The server must be updated to v0.1.57 too, as it refuses any other version.

## v0.1.56

Server.

- The console finds a companion's transcript by name in any case, even while
  she is not in the world.

The server must be updated to v0.1.56 too, as it refuses any other version.

## v0.1.55

Companions. Server.

- **Transcripts**: the server keeps a day-by-day text record of everything
  said to each companion and by her, with what happened in between, for
  30 days.
- **She sees what is around her**: fire, water, doors, crates, boulders,
  carts, ledges and torches nearby, and she can say where they are ("Fire
  is burning two paces to your left").
- She says so when she doesn't know what something is.

The server must be updated to v0.1.55 too, as it refuses any other version.

## v0.1.54

Packaging. Client.

- The client no longer carries development scratch files it never used.

The server must be updated to v0.1.54 too, as it refuses any other version.

## v0.1.53

Levels from pixel maps. Server and client.

- **Maps are pictures now**: a level is a folder with a painted map, an
  optional height map and a short settings file. The test room is the same
  room as before, now drawn this way.
- **New ground**: grass, dirt, water, stairs, torches, carts, and brutes and
  sneaks besides imps.
- **Heights**: raised ground with cliffs, climbed by stairs. Shove someone
  off a ledge and they fall and get hurt; nobody can be pushed up a step.
  From higher ground you see over lower walls.
- **Level links**: step onto one and the whole party goes to the next map.
- A sample level shows all of it.

The server must be updated to v0.1.53 too, as it refuses any other version.

## v0.1.52

Healing and instructions. Server.

- **You heal out of combat** now too, at your companion's rate: a point a
  second after five calm seconds.
- **Only real requests stick**: your companion takes your words as an
  instruction only when she understands them as asking something of her;
  a warning or a shout is just talk.
- Her sense of the world now includes the land outside the old stone
  places.

The server must be updated to v0.1.52 too, as it refuses any other version.

## v0.1.51

Companion voice, rewritten. Server.

- **She talks like someone in the dungeon with you**: her voice is told
  only her world and what is happening, never about a game, and sees your
  recent exchange as a conversation.
- She answers when you talk to her, keeps quiet when there is nothing to
  say, and only changes what she is doing when you have asked her to.
- Long lines end at a sentence instead of being cut off mid-word.

The server must be updated to v0.1.51 too, as it refuses any other version.

## v0.1.50

Companion fixes. Server.

- **Death and respawn**: your companion reacts to your death when it
  happens, and to your return as a separate moment.
- **"In danger"** now means a monster within 2 cells; low HP with nothing
  near is "badly hurt".
- **Instructions lapse** when either of you drops below 30% HP.
- **Her voice** only changes her stance when you are the one talking.
- **R reset** also brings you back to full HP and stamina.

The server must be updated to v0.1.50 too, as it refuses any other version.

## v0.1.49

Companion voice. Server.

- **She talks about what is happening**: her voice knows her stance, what
  she is doing and what just happened.
- **Characters**: each companion's personality is a paragraph, written per
  companion (Pip and Wren first).
- **Fewer repeats**: she remembers her last 20 lines across sessions and
  does not say them again; her lines are livelier.
- **When you are in real danger** (below 30% HP) your last instruction
  lapses, she decides afresh, and if she changes course she tells you why.

The server must be updated to v0.1.49 too, as it refuses any other version.

## v0.1.48

Companions: hands and voice. Server and client.

- **She acts at once**: a scripted tactical layer runs her every tick from
  a stance (stay close, hold, press, guard, pull back); her mind only
  picks the stance when the fight changes, in a few hundred ms.
- **She speaks for herself, separately**: when you talk to her, someone
  dies, someone's HP crosses a threshold, or after a fight goes quiet.
  When you tell her something, her answer can change her stance.
- **Retreating means getting out of danger**: she steps clear of the
  monsters, near you if she can, and fights back when cornered.
- **She heals** out of combat, a point a second; a reset heals her fully.
- **No parroting**: quick phrases reach her as what you mean, and she never
  says your words or her own last lines back.
- She is told who she is and who you are, by name.
- The test runner fails a scene that hangs instead of waiting forever.

The server must be updated to v0.1.48 too, as it refuses any other version.

## v0.1.47

Companions keep their heads in a fight; speech bubbles. Server and client.

- **Speech bubbles** for everyone: a small dark bubble over the speaker,
  wrapped, readable through walls, scaled with the zoom; a new line
  replaces the speaker's last, and two speakers' bubbles move apart.
- **No dithering mid-fight**: in a fight your companion is only asked
  again when the fight changes (a new monster next to either of you, an
  HP threshold, her target dead), and never leaves a live target in reach
  for a routine rethink.
- **She does what you ask**: an instruction (typed or a quick phrase)
  stands for a minute or until you say another, and she goes against it
  only to save a life, saying why.
- **She talks less**: only when spoken to, at a death, or when someone's
  HP crosses a threshold, and she does not repeat herself.
- **Reflex**: badly hurt with a monster next to her, she always retreats.
- Her mind now gets the situation in plain sentences first.

The server must be updated to v0.1.47 too, as it refuses any other version.

## v0.1.46

Quick phrases; companions are companions. Server and client.

- **Keys 1-4 say quick phrases** instead of giving orders: "With me!",
  "Stay back!", "Get them!", "Fall back!". They go exactly as typed chat
  does: over your head, to every player, into the party log, and to your
  companion as something you said. Edit them in settings.cfg
  (`phrase1=` ... `phrase4=`). The HUD shows them.
- **Typed chat** now shows over the speaker's head too.
- **The old orders are gone**: what your companion does about what you
  say is up to her.
- **No more "owner"**: her mind is told your name and that you travel
  together by choice; the console lists companions as "Wren, with Jeff".

The server must be updated to v0.1.46 too, as it refuses any other version.

## v0.1.45

Companion mind follow-ups. Server.

- **Fewer second thoughts in a fight**: a blow on her or her owner asks
  her mind again at most once per 30 ticks, and only if the fight changed
  (a new monster next to either of you, either's hp crossing 50% or 30%,
  her target gone). Otherwise her decision holds.
- **A shorter, sharper context**: only objects within 2 cells, monsters
  within 4 or coming for her or her owner, six entries at most, nearest
  first; repeated log lines collapse ("Brute hit Player for 1 ×6.").
- **The mind log rotates** at 5 MB, keeping one older file.

The server must be updated to v0.1.45 too, as it refuses any other version.

## v0.1.44

Companion mind, talking, speech history, housekeeping. Server and client.

- **Talk to your companion**: Enter opens a line (Esc cancels). It goes to
  every player as chat and to the party log, and your companion answers
  and decides on it at once. At most 200 characters, one line per 2 s.
- **Tab** shows the last 20 things said this session: speech, last words
  and chat, with who and when.
- **Every speech line** goes to the server log and the party log; a
  companion's last words are always said.
- **Companion decisions hold**: a language-model mind's choice stands until
  its next, instead of the scripted mind's answer cutting in between.
- **Reflexes**: below 30% hp with a monster next to her, a companion only
  retreats, steps aside or holds, whatever her mind says.
- **She knows about the fight**: the hp of everyone near her and the
  recent blows on her and her owner are in what her mind is told, and the
  reason she is asked (it was always blank before). Players are named as
  the party log names them.
- **Mind log**: every decision, with the full prompt and raw reply, one
  JSON line each, to /var/lib/psykinetic/mind.log on the server
  (`--mind-log=`; `--mind-why` asks for a reason too). Console: `mind log
  on|off`, `mind last <name>`.
- **Sounds** now come from art/audio/sfx/, files named for what they do;
  the audio packs are no longer in the repo or the client.
- `tools/ship.ps1` stops and lists untracked files unless given
  `-IncludeUntracked`.

The server must be updated to v0.1.44 too, as it refuses any other version.

## v0.1.43

Mouse wheel zoom. Client (the server only for the version).

- The mouse wheel zooms the 3D camera in small eased steps, between 0.8×
  and 1.4× of the usual size, centred on your character, in both schemes.
  It stays where you leave it and is saved.
- A middle click (no drag) puts the zoom back to 1×.
- Nothing else about the camera changes.

The server must be updated to v0.1.43 too, as it refuses any other version.

## v0.1.42

Camera: free turn, lock on a diamond. Client (the server only for the version).

- **A/D** (click scheme) turn the 3D camera freely, all the way round.
  Let go and it locks on the next diagonal view the way you were turning,
  or goes back if you turned less than 10°, and stays there. That view is
  saved again.
- **WASD scheme:** the sideways middle drag does the same.
- **W/S** tilt while held and spring back to 50°. No zoom; Q/E do nothing.
- The camera no longer turns by itself to follow your character.

The server must be updated to v0.1.42 too, as it refuses any other version.

## v0.1.41

The camera follows the character. Client (the server only for the version).

- **Click scheme:** the 3D camera turns by itself to the diagonal view
  that puts the way you are walking toward the top of the screen. It
  waits until you have kept a new heading for 0.7 s, turns over a second,
  never turns while you stand still, and never twice within 1.5 s.
- **A/D** look round up to a quarter turn either way and spring back when
  let go. **W/S** tilt and spring back, as before.
- Your character is always the middle of the screen.
- The camera's view is no longer saved.
- **WASD scheme:** the middle-drag turn is no longer limited to a quarter
  turn; otherwise unchanged.

The server must be updated to v0.1.41 too, as it refuses any other version.

## v0.1.40

Camera simplification. Client (the server only for the version).

- **A/D** (click scheme) turn the 3D camera up to a quarter turn either
  side of its home view and settle on one of the three diagonal views in
  that range. The WASD scheme's middle drag is held to the same range.
- **W/S** (click scheme) tilt while held and spring back to 50° when let go.
- **Zoom is gone**; Q/E and the middle click do nothing in the click scheme.
- A saved view outside the range comes back as the nearest one in it; the
  old saved tilt and zoom are dropped.

The server must be updated to v0.1.40 too, as it refuses any other version.

## v0.1.39

Click scheme camera keys swapped. Client (the server only for the version).

- **W/S** tilt the 3D camera (W toward top-down, S toward level).
- **Q/E** zoom (Q out, E in).
- Everything else is as it was.

The server must be updated to v0.1.39 too, as it refuses any other version.

## v0.1.38

Combat readability (3D view). Server and client.

- **HP bars** over creatures, longer for more max hp, green, amber below
  half, red below a quarter. They show while a creature is hurt or has
  been fighting in the last 4 s, and fade out otherwise; hold Alt to see
  them all. `hp_bars=0` in `settings.cfg` turns them off.
- **Deaths**: the body tips onto its side with a little bounce, flashes,
  drops its lantern, lies for 8 s and sinks into the floor. Corpses never
  block anything. A companion says a last line. When you die the camera
  pulls back and the colour drains until you are back.
- **Sounds**, placed where they happen: swings, blows, impacts against
  walls, wood and bodies, crates breaking, deaths, doors, and quiet
  footsteps, all from Kenney's CC0 Impact Sounds and RPG Audio packs.
  `master_volume=` and `sfx_volume=` (0 to 1) in `settings.cfg`.
- Lines you add to `settings.cfg` by hand are kept when the game rewrites it.

The server must be updated to v0.1.38 too, as it refuses any other version.

## v0.1.37

Click scheme camera keys, remapped. Client (the server only for the version).

- **W/S** zoom in and out on your character while held (1.5× a second),
  between 0.6× and 2×, slowing into either end. The zoom stays where you
  leave it and is saved.
- **Q/E** tilt the camera while held (E up toward top-down, Q down),
  between 40° and 85°, sticky and saved. Tilting no longer zooms out on
  its own.
- **A/D** turn as before.
- **A middle click** resets both tilt and zoom over 250 ms.
- The Q/E 90° step and "look left/right" are gone.
- The WASD scheme is unchanged.

The server must be updated to v0.1.37 too, as it refuses any other version.

## v0.1.36

Q/E relative to the character. Client (the server only for the version).

- In the click scheme Q now means "look to my left" and E "look to my
  right", left and right of where your character is heading (the way it
  is walking, or last moved). The camera steps 90° to the diagonal view
  that brings that side toward the top of the screen, so at a corner the
  passage on that side comes into view, whatever view you started from.
- A/D still turn the camera in the screen's sense, for free sweeping.

The server must be updated to v0.1.36 too, as it refuses any other version.

## v0.1.35

A/D feel; Q/E back. Client (the server only for the version).

- **Q/E** step 90° to the next diagonal view again in the click scheme
  (400 ms), alongside A/D.
- **A/D** turn at 180° a second while held.
- **Letting go of A/D** carries on to the next diagonal view the way you
  were turning if you went more than 10° past the last one, and goes back
  otherwise. The settle starts at the speed you were turning and slows to
  a stop, so the camera never halts and starts again on release.
- The WASD scheme is unchanged; its up/down middle drag still springs back.

The server must be updated to v0.1.35 too, as it refuses any other version.

## v0.1.34

Click scheme camera on WASD. Client (the server only for the version).

- **W/S** tilt the 3D camera while held, between 40° and 85° (near
  top-down), slowing into either end. It stays where you leave it and is
  saved; the camera pulls back a little as it tilts up.
- **A/D** turn the camera while held; let go and it eases onto the
  nearest diagonal view over 250 ms (the saved view is always one of
  those).
- **A middle click** levels the tilt back to 50°.
- Q/E and middle-button drags do nothing in the click scheme now.
- The WASD scheme is unchanged.

The server must be updated to v0.1.34 too, as it refuses any other version.

## v0.1.33

Pitch peek. Client (the server only for the version).

- Hold the middle button and drag up or down to tilt the 3D camera from
  its usual 50° toward top-down (85°), further the further you drag (all
  of it over 300 px), while it pulls back a little to show more round you.
  Let go and it springs back over 250 ms. The camera's turn never changes.
- The click scheme's sideways middle-drag peek is gone; Q/E still turn.
- In the WASD scheme a middle drag turns the camera if it first moves
  sideways and tilts it if it first moves up or down.
- Near walls stay see-through while tilted. F3 shows the pitch.

The server must be updated to v0.1.33 too, as it refuses any other version.

## v0.1.32

Peek in the click scheme. Client (the server only for the version).

- Hold the middle button and drag sideways to turn the 3D camera up to
  45° either way from the view it rests on; let go and it springs back to
  that view over 200 ms. The saved view never changes. Q/E still step
  between views, even mid-peek.
- The WASD scheme is unchanged.

The server must be updated to v0.1.32 too, as it refuses any other version.

## v0.1.31

The 3D camera rests only on diagonal views. Client (the server only for
the version).

- The four resting yaws are the diamond views: the default and each 90°
  from it.
- Q/E step 90° from one to the next in one smooth 400 ms ease, through
  the axis-aligned view without stopping there.
- In the WASD scheme a middle drag still turns freely while held, and on
  release settles on the nearest diamond.
- The saved yaw is always a diamond; an axis yaw saved by an older build
  is read as the nearest diamond.

The server must be updated to v0.1.31 too, as it refuses any other version.

## v0.1.30

Deploys. Tooling only; no game change.

- `deploy.sh` removes untracked `.uid` and `.import` files before it
  pulls, and runs the headless import after the pull, never before. The
  v0.1.29 deploy stopped on a `.uid` the box had generated itself.
- `ship.ps1` cleans the same way before its own pull on the box, and
  before committing imports headless and refuses a script that has no
  `.uid`, so each `.uid` goes in with its script.

The server must be updated to v0.1.30 too, as it refuses any other version.

## v0.1.29

Control schemes as complete packages. Client (the server only for the
version).

- **Click is the default again** (`controls=click`, or no line): click
  and hold-to-move, Q/E turn the 3D camera a step, the verbs land on what
  you click. WASD and the middle button do nothing, and the camera just
  follows you, with no lean toward the cursor.
- **WASD** (`controls=wasd`): WASD walks relative to the camera, the mouse
  aims, a middle-button drag turns the 3D camera freely and settles on the
  nearest 45° step when you let go (eased over 250 ms). Q/E do nothing.
- **The camera never turns under a held movement key**: a drag made while
  you walk applies when you let go of the keys.
- **The WASD lean** now comes from where the cursor is on the screen: past
  a dead zone of 15% round the middle it leans up to 3 cells toward that
  side, settling in about 300 ms. The camera moving cannot change it.
- **The hover and the click always agree**: the cell under the cursor is
  picked once a frame after the camera has moved, and a click goes to the
  cell the square showed.
- The HUD shows only the active scheme's controls.

The server must be updated to v0.1.29 too, as it refuses any other version.

## v0.1.28

Controls pass. Server and client.

- **Two control schemes.** `controls=wasd` (the default) or
  `controls=click` in `settings.cfg`; `--controls=` overrides it for a run.
- **WASD** walks relative to the camera (W is up the screen at the current
  yaw), eight directions from key combinations; letting go stops on the
  cell being entered. Clicking a far cell walks there until a key is
  pressed.
- **The mouse aims** in WASD: standing still you face the cursor; a left
  click attacks whoever is next to you that way, or swings at air; a
  right click grabs whoever is next to you that way, and a drag tosses. A
  click on a sprite still goes to that sprite.
- **Continuous motion.** The player walks at 4 cells a second, steadily,
  with no pause at cell boundaries; monsters and companions are drawn the
  same way. A refused step eases to a stop. Facing turns smoothly (about
  100 ms) toward where you are going, or toward the cursor.
- **The camera leads toward the cursor**, up to 3 cells, and settles back
  on you when the cursor comes back near you. The middle-button peek and
  nudge are gone: Q/E is the only camera rotation.
- **Bumping your companion** makes her step aside at once (YIELD), or say
  there is no room; it goes in the party log. A language-model mind gets
  one decision window to do it before the scripted answer applies.
  Clicking her walks into her rather than attacking her.
- **3D:** the hover is a square cell outline; the toss aim is an arrow on
  the floor; speech shows for 4 seconds from the speech message itself;
  lanterns are warm white; creatures have a nose that shows their facing
  and lunge when they swing.
- **Mispredicts fixed.** A move order sent while a step was showing could
  reach the server before it had taken that step, and the server would set
  off from the tile before and go another way. Steering with the button
  held did this constantly in 3D, where the following camera gives a new
  target every few frames. Orders now carry the steps already shown and
  the server walks those first: a steered walk with 50-200 ms of delay
  went from about two mispredictions in ten seconds to none, and a WASD
  walk round a corner shows none at 0, 120 and 200 ms.
- A companion no longer steps aside onto fire.

The server must be updated to v0.1.28 too, as it refuses any other version.

## v0.1.27

The 3D view is the default. Client.

- A client now starts in the 3D view. `--renderer=2d`, or a line
  `renderer=2d` in `settings.cfg`, picks the 2D view; anything else, or
  nothing, is 3D.
- `renderer=` in `settings.cfg` is now honoured (it was ignored, and wiped
  when the file was rewritten on a resize). The command line overrides it
  for that run without changing the file.

The server must be updated to v0.1.27 too, as it refuses any other version.

## v0.1.26

Docs only; no code change.

- docs/decisions.md records each of v0.1.25's architectural choices on its
  own: the authority polls the network itself (37), the server relay is
  off (38), server sends go peer by peer through `Net.sendable_peers`
  (39), departures come from `Net.peer_left` (40).

The server must be updated to v0.1.26 too, as it refuses any other version.

## v0.1.25

The max-channels flake. Server and client.

- A peer whose ENet link is closing is dropped from the multiplayer
  before the frame's replication pass, and the server relay is off, so
  nothing is sent into a closing link any more: `Unable to send packet on
  channel 0, max channels: 0` is gone from the network test (six clean
  runs where it failed two or three in six).

The server must be updated to v0.1.25 too, as it refuses any other version.

## v0.1.24

Kit walls back; two-wide corridors.

- 3D: walls, posts, doorway, gate and floor are the Kenney kit's own
  pieces again at the kit's proportions, scaled in height only; the
  flat-colour boxes stay available for interior walls later. Everything
  else from step 2 as it was.
- Map: corridors are two cells wide. The west corridor keeps a single-cell
  dead end at (1..2, 8) as the one chokepoint; the links down to the
  passage and the cells inside the door are two wide, with (3, 13)
  walled on its north so the door is still the only way in.

The server must be updated to v0.1.24 too, as it refuses any other version.

## v0.1.23

3D client, step 2. Client only; `--renderer=3d`.

- Kit mapping: flat stone floor in the 2D floor's green-grey; walls as
  plain boxes in the kit's stone at the kit's 0.5 thickness centred on the
  edge, 3 tall; posts at 0.5; the kit's gate leaf scaled to a doorway of
  jambs and lintel; sun down to 0.1.
- Near/far walls as in 2D: the camera-facing side of walkable cells at
  0.3 alpha, recomputed when the camera yaw changes.
- Orbit: Q/E turn the camera 45° about the player, tweened; a middle
  drag nudges up to 45° and springs back; the yaw persists in
  settings.cfg.
- Picking by ray: entity and door colliders first (Area3Ds, no physics
  bodies), then the floor plane, snapped to the nearest walkable cell.
  Hover ring and click ripple as flat rings on the floor.
- Left click move/attack, right drag shove, hold-to-move, keys 1–4, R, F3,
  F11: the same commands the 2D client sends.
- Speech lines as Label3D above the speaker.
- `--test-yaw=<deg>` test hook.

The server must be updated to v0.1.23 too, as it refuses any other version.

## v0.1.22

3D client, step 1: the room. Client only; opt in with `--renderer=3d`.

- A 3D view of the same client: the test room built from the Kenney
  Castle Kit (floor pieces, narrow wall segments on the edges at 3 units,
  corner posts where walls meet or end, the kit's doorway and door leaf,
  fire as an emissive quad with a light), entities as tinted primitives
  at the scale table with Label3D names, lanterns on players and
  companions, a fixed orthographic camera at 50° matching the 2D diamond.
- The default view is unchanged; the renderer is Forward+ explicitly.
- The kit (CC0) ships in `art/kenney-castle/`.

The server must be updated to v0.1.22 too, as it refuses any other version.

## v0.1.21

Peek rotation prototype. Client only.

- The projection takes an azimuth, −45..45°: 0 is the 2:1 diamond view,
  ±45 the axis-aligned view. Floor, walls, doors, ripples, the hover cell
  and every sprite anchor follow it; sprites stay upright and sort by
  projected depth. Near/far walls are classified from the azimuth.
- Middle-button drag turns the view, the full range over about 400 px,
  eased near the limits; release swings it back over 200 ms.
- F3 shows the angle. `--test-azimuth=<deg>` test hook.

The server must be updated to v0.1.21 too, as it refuses any other version.

## v0.1.20

Translucent near walls. Client only.

- Every wall is full height; the occlusion windows and the stub rule are
  gone.
- Walls on the south or east edge of a walkable cell (facing the camera)
  draw at `Main.NEAR_WALL_ALPHA` (0.3); walls on north or west edges draw
  opaque. Interior partitions follow the cell they are the south or east
  edge of.
- Near walls draw as one layer with a single alpha, so where they overlap
  on screen they never stack toward opaque.
- A 1 px darker line along every wall top and up every corner, at the
  wall's alpha.
- Door posts follow the edge they stand on; the panel stays opaque.

The server must be updated to v0.1.20 too, as it refuses any other version.

## v0.1.19

Occlusion windows. Client only.

- Every wall stands full height; the stub rule is gone.
- A creature (player, companion, monster) behind a wall face shows
  through a soft circular window in it, a tile across, centred on its
  sprite: the face fades to 25% at the centre and back to opaque at the
  edge, animating in and out over 150 ms as the creature passes. A
  shader per face, up to eight windows each.
- Doors are unchanged.

The server must be updated to v0.1.19 too, as it refuses any other version.

## v0.1.18

Window and resolution. Client only.

- The project is laid out at a 3840×2160 base viewport (canvas_items
  stretch, expand, hidpi): one to one on a 4K monitor, half-scale at
  1080p. The world and the UI look as before.
- First launch is a resizable 1920×1080 window. F11 toggles borderless
  fullscreen at the monitor's native resolution.
- The windowed size and the mode are kept in settings.cfg (window_width,
  window_height, window_mode) and restored on the next launch.
- Entity name and speech captions are rasterised sharp at the camera zoom.
- `--test-fullscreen=<seconds>` test hook.

The server must be updated to v0.1.18 too, as it refuses any other version.

## v0.1.17

Movement feedback. Client only.

- A move click ripples at the target cell: a ring on the floor, a step
  lighter than the floor, grows from 4 px to a tile across over 250 ms
  and fades. One per click; holding the button retargets as the cursor
  crosses cells, each new cell with its own ripple. The hover highlight
  stays on the cell under the cursor.
- A click off the floor (void, past a wall) goes to the nearest walkable
  cell within three tiles of the click point and ripples there; further
  out it is ignored.
- A click on an entity sprite targets that entity with either button,
  whatever cell is under the pixels.
- `--test-click=<seconds>` test hook.

The server must be updated to v0.1.17 too, as it refuses any other version.

## v0.1.16

Quiet walls. Client only.

- Every wall face is one flat neutral grey (`Main.WALL_VALUE`, 0.18),
  darker than the floor and a few steps above the void, the same whichever
  way it faces: no lit side, no gradient, no blue tint.
- No lit top strip and no end faces; the top of a wall is where the face
  ends. Corners get a 1 px line one step darker than the face.
- No shaded floor beside walls: the floor is one surface up to the wall
  base and stays the brightest thing on screen.
- Stubs follow the same rules at their height. Doors are unchanged.

The server must be updated to v0.1.16 too, as it refuses any other version.

## v0.1.15

Low walls wherever floor is behind them. Client only.

- A wall is a stub whenever a full-height one would hide floor: any
  walkable cell straight behind it within six cells counts, void cells
  between skipped. The walls on the near side of the old thick wall rows,
  which stood full and hid the room behind them, are stubs now. Only walls
  with nothing behind them stand full.

## v0.1.14

- stub rule: south/east edges of walkable cells are stubs

## v0.1.13

Wall tops that join, doors with height. Client only.

- Wall top strips are 4 px ribbons that miter at corners, run through at
  a T with the joining wall butting in, and end square at a free end with
  a short end face. Stubs get the same at their height.
- Doors stand at full wall height between two jamb posts, with a panel
  that swings; a closed door reads as a door, not a plank.
- Outside the map is near-black instead of wall grey.
- The path preview is gone; the hover highlight stays.
- A half-wall off the chamber's north wall, between (5, 1) and (6, 1).

The server must be updated to v0.1.13 too, as it refuses any other version.

## v0.1.12

Walls and picking: thin walls, low near walls, ground-plane clicks, a
path preview. Client only.

- Walls are drawn on the cell boundary with no footprint: a face and a lit
  top strip. Floor draws fully to the base of its walls.
- Walls in front of a floor cell (its south and east edges) are low stubs;
  walls behind stand full height. The fade-to-black ring and the see-through
  wall effect are gone.
- Clicks and hover resolve to the floor cell under the cursor on the
  ground plane; walls, doors and tall sprites never intercept a move. The
  hover highlight shows the target cell even behind a tall wall. A right
  click still picks a sprite to shove, and a door face to open or close
  it from beside it.
- A faint dotted path from you to the hovered cell, through any door on
  the way; it disappears on click.

The server must be updated to v0.1.12 too, as it refuses any other version.

## v0.1.11

Walls on edges, and a door.

- Walls are now the edges between cells, not cells of their own: corridors
  are one cell wide with walls on their sides, the passage two cells with
  walls on the outside. Moving, pushing, sight and melee all respect the
  edge between you and where you are going; diagonals cannot cut a wall
  corner. A body pushed against a wall edge stops there and takes impact as
  before.
- One door, on the south exit of the chamber. Click it from beside it to
  open or close it, or just walk through: creatures open doors on their
  way, monsters included, unless someone stands in the doorway. A crate
  cannot pass a closed door. A door takes impact like a wall and, being
  wood, breaks once its hp is spent.
- Walls are drawn as thin tall faces on the cell boundary with posts at
  ends, corners and door jambs; a face over your own cell fades while it
  covers you. Doors swing open.

The server must be updated to v0.1.11 too; the map format changed.

## v0.1.10

Scale and space pass, placeholder art only.

- Everything drawn has a size in tile heights, from one table: characters
  1.5, walls 3, crates 0.8, barrels 0.9, the boulder 1.2.
- Walls are continuous blocks with a top face; straight runs, corners and
  end caps come from their neighbours. A wall that would hide something
  turns translucent while it does. The floor in front of a wall is shaded.
- The map is 48Ã—36. The room you know is one chamber in it; two corridors
  lead off it, east and south, and bend out of view.
- The camera follows your player with a little lag, and everything beyond
  about 12 tiles fades to black.
- Nothing else: no lighting, no tileset, no sprites.

The server must be updated to v0.1.10 too (the map is server data).

## v0.1.9

No more rubber-banding into a crate that cannot move.

- Clicking a crate that is against a wall (or heavier than you can push,
  or backed by other crates with nowhere to go) made your capsule bounce
  between you and the crate for as long as the order stood. The client now
  applies the same push rule as the server before showing a step, so the
  walk stops beside the crate. The server was never moving you, which is
  why nothing else reacted.
- When the server has given a move order up (a refused step into the
  destination, or no reply at all), the client stops predicting it instead
  of guessing again.

This is a client-only fix, but the server must still be updated to v0.1.9
to accept the client.

## v0.1.8

Anyone can reset the room.

- Press R to rebuild the room from the map: monsters, crates and the
  boulder back in place, dead companions back beside their owners, players
  where they stood. It used to work only when hosting, never on the
  dedicated server. The server logs who did it.
- This is on while the game is being tested; a server started with
  `--no-player-reset` keeps resets to its console.

The server must be updated to v0.1.8 too.

## v0.1.7

Companions come back where their owner is.

- A companion brought back by `reset` was put on its owner's last saved
  tile even when the owner was moved to a safe start tile, which could
  leave it alone among the monsters, out of sight. It now always appears
  beside its owner. The same goes for a living companion whose saved tile
  has a monster within 5 tiles.
- `reset` now says which companions it brought back, or that none were
  dead.

The server must be updated to v0.1.7 too.

## v0.1.6

Smooth movement for everything you do not control, and a way to get a dead
companion back.

- Monsters, companions and other players moved in hops on a client: half a
  tile slid, the rest jumped, then a pause; companions and players simply
  jumped from tile to tile. They now slide evenly, as on a host.
- A companion that died was gone for good. Rebuilding the room (`reset` on
  the server console, or R on a host) now brings dead companions back, at
  full health, beside their owners.

The server must be updated to v0.1.6 too: it refuses clients of any other
version.

## v0.1.5

Fixes a server looking different from a fresh room after an update.

- A server that restored its saved world kept the looks of the build that
  saved it: white crates and a square boulder, where a fresh room had tan
  crates and a round one. Level entities now take their shape, colour, size
  and mass from the current map on every start, and only their position and
  health from the saved world.
- Crates and the boulder saved by an old build keep their place in the
  level, so a second copy no longer respawns on their original tile.

## v0.1.4

Fixes the client closing a few seconds after connecting.

- A client and server built from different code now refuse each other with
  a "build mismatch" message instead of the client crashing. The 0.1.3
  client did exactly that against a newer server.
- Player names show over their capsules, like companions' names.
- Coming back or respawning never puts you next to a monster: if one is
  within 5 tiles you appear on the safest start tile instead. For the first
  3 seconds, or until you move or attack, monsters leave you alone and your
  capsule is drawn faded.
- Companions: the join log now says what happened to yours (new, waiting for
  you, or died earlier). The language-model mind talks to Ollama's native
  endpoint with reasoning off.
- Entities are built from one generic scene, so new kinds of things can be
  added on the server without a client update.
- The boulder is now round.

## v0.1.0

First playable build.

- Isometric grid sim at 10 Hz: eight-direction movement, walking pushes,
  force pushes with impact damage, stun on collision, fire tiles, stamina
  that fades knockback as it runs down.
- Click to walk or attack, right click to shove, drag to toss in a chosen
  direction, including over your own head.
- Multiplayer over ENet with a dedicated Linux server, client-side
  prediction, join tokens, and a world snapshot that survives restarts.
- Self-updating Windows client: `launch.bat` checks GitHub for a newer
  release before starting the game.
