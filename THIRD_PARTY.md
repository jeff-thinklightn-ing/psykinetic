# Third-party assets and tools

Everything in the game, or used to make it, that someone else made. No asset with a
non-commercial or regional restriction goes in (docs/roadmap.md). Each entry names its licence
and where its licence text is kept.

## Art slots

The 3D models and textures are art slots (`art/kit/slots.json`, decision 220): each records
where its art came from. The block below is written from it by `tools/art_status.gd`, which
also writes `docs/art_status.md`; `art_kit_test` fails while either is out of date.

<!-- art slots: written by tools/art_status.gd from art/kit/slots.json; edit there -->

| Source | Licence | Where | Slots drawn from it |
|--------|---------|-------|---------------------|
| [Castle Kit 2.0, Kenney](https://kenney.nl/assets/castle-kit) | CC0 1.0 (`art/kenney-castle/License.txt`) | `art/kenney-castle/Models/GLB format/` | none now |

Slots whose own art came from someone else: material.wall.castle (art-gen, own), floor.castle (art-gen, own), wall.castle.straight (art-gen, fitted by art-kit, own), wall.castle.straight_low (art-gen, fitted by art-kit, own), wall.castle.straight_tall (art-gen, fitted by art-kit, own), wall.castle.end (art-gen, fitted by art-kit, own), wall.castle.end_low (art-gen, fitted by art-kit, own), wall.castle.end_tall (art-gen, fitted by art-kit, own), wall.castle.corner (art-gen, fitted by art-kit, own), wall.castle.corner_low (art-gen, fitted by art-kit, own), wall.castle.corner_tall (art-gen, fitted by art-kit, own), wall.castle.t (art-gen, fitted by art-kit, own), wall.castle.t_low (art-gen, fitted by art-kit, own), wall.castle.t_tall (art-gen, fitted by art-kit, own), wall.castle.cross (art-gen, fitted by art-kit, own), wall.castle.cross_low (art-gen, fitted by art-kit, own), wall.castle.cross_tall (art-gen, fitted by art-kit, own), wall.castle.post (art-gen, fitted by art-kit, own), wall.castle.post_low (art-gen, fitted by art-kit, own), wall.castle.post_tall (art-gen, fitted by art-kit, own), wall.castle.window (art-gen, fitted by art-kit, own), wall.castle.straight_ruined (art-gen, fitted by art-kit, own), wall.castle.end_ruined (art-gen, fitted by art-kit, own), wall.castle.rubble (art-gen, fitted by art-kit, own), material.wall.wood (art-gen, own), material.roof.shingle (art-gen, procedural (no model), own), roof.shingle.ridge (art-gen, fitted by art-kit, own), roof.shingle.end (art-gen, fitted by art-kit, own), roof.shingle.broken (art-kit, own), floor.wood (art-gen, own), wall.wood.straight (art-gen, fitted by art-kit, own), wall.wood.end (art-gen, fitted by art-kit, own), wall.wood.corner (art-gen, fitted by art-kit, own), wall.wood.t (art-gen, fitted by art-kit, own), wall.wood.cross (art-gen, fitted by art-kit, own), wall.wood.post (art-gen, fitted by art-kit, own), wall.wood.window (art-gen, fitted by art-kit, own), wall.wood.straight_ruined (art-gen, fitted by art-kit, own), wall.wood.rubble (art-gen, fitted by art-kit, own), material.wall.stone (art-gen, own), floor.stone (art-gen, own), wall.stone.straight (art-gen, fitted by art-kit, own), wall.stone.end (art-gen, fitted by art-kit, own), wall.stone.corner (art-gen, fitted by art-kit, own), wall.stone.t (art-gen, fitted by art-kit, own), wall.stone.cross (art-gen, fitted by art-kit, own), wall.stone.post (art-gen, fitted by art-kit, own), wall.stone.straight_tall (art-gen, fitted by art-kit, own), wall.stone.end_tall (art-gen, fitted by art-kit, own), wall.stone.corner_tall (art-gen, fitted by art-kit, own), wall.stone.t_tall (art-gen, fitted by art-kit, own), wall.stone.cross_tall (art-gen, fitted by art-kit, own), wall.stone.post_tall (art-gen, fitted by art-kit, own), wall.stone.straight_low (art-gen, fitted by art-kit, own), wall.stone.end_low (art-gen, fitted by art-kit, own), wall.stone.post_low (art-gen, fitted by art-kit, own), wall.stone.window (art-gen, fitted by art-kit, own), wall.stone.straight_ruined (art-gen, fitted by art-kit, own), wall.stone.end_ruined (art-gen, fitted by art-kit, own), wall.stone.rubble (art-gen, fitted by art-kit, own), material.wall.cave (art-gen, own), floor.cave (art-gen, own), wall.cave.end (art-gen, fitted by art-kit, own), wall.cave.pillar (art-gen, fitted by art-kit, own), wall.cave.rubble (art-gen, fitted by art-kit, own), wall.castle.tower (art-gen, fitted by art-kit, own), wall.stone.tower (art-gen, fitted by art-kit, own), wall.wood.tower (art-gen, fitted by art-kit, own), door.single (art-kit, own), tree.broadleaf (art-gen, fitted by art-kit, own), tree.small (art-gen, fitted by art-kit (variant 1); art-kit by hand (2, 3), own), tree.pine (art-gen, fitted by art-kit, own), tree.pine_stand (art-kit, from tree.pine's art-gen variants, own), rock.small (art-gen, fitted by art-kit, own), scatter.tuft (art-gen, fitted by art-kit, own), scatter.flower (art-kit, by hand to art-gen's c4, own), scatter.stone (art-gen, fitted by art-kit, own), scatter.root (art-gen, fitted by art-kit, own), prop.crate (art-gen, fitted by art-kit, own), prop.chest (art-gen, fitted by art-kit, own), rock.boulder (art-gen, fitted by art-kit, own), prop.cart (art-gen, fitted by art-kit, own), building.hut (art-kit, by hand, own), building.house (art-gen, fitted by art-kit, own), building.shed (art-gen, fitted by art-kit, own), building.well (art-gen, fitted by art-kit, own), door.double (art-gen, fitted by art-kit, own), door.gate (art-gen, fitted by art-kit, own), door.portcullis (art-gen, fitted by art-kit, own), door.trapdoor (art-gen, fitted by art-kit, own), tree.dead (art-gen, fitted by art-kit, own), tree.stump (art-gen, cleaned up by art-kit, own), tree.log (art-gen, fitted by art-kit, own), plant.bush (art-gen, fitted by art-kit, own), plant.fern (art-gen, fitted by art-kit, own), scatter.reeds (art-kit, by hand to art-gen's c1, own), rock.large (art-gen, fitted by art-kit, own), prop.barrel (art-gen, fitted by art-kit, own), prop.torch (art-gen, fitted by art-kit, own), prop.lantern (art-gen, fitted by art-kit, own), prop.campfire (art-gen, fitted by art-kit, own), prop.fence (art-gen, fitted by art-kit, own), prop.fence_post (art-gen, fitted by art-kit, own), prop.stairs (art-gen, fitted by art-kit, own), prop.table (art-gen, fitted by art-kit, own), prop.bench (art-gen, fitted by art-kit, own), prop.bed (art-gen, fitted by art-kit, own), prop.sack (art-gen, fitted by art-kit, own), prop.grave (art-gen, fitted by art-kit, own), prop.anvil (art-gen, fitted by art-kit, own), prop.forge (art-gen, fitted by art-kit, own), prop.bookshelf (art-gen, fitted by art-kit, own), prop.market_stall (art-gen, fitted by art-kit, own), prop.signpost (art-gen, fitted by art-kit, own), prop.banner (art-gen, fitted by art-kit, own), prop.tent (art-gen, fitted by art-kit, own), prop.palisade (art-gen, fitted by art-kit, own), prop.cage (art-gen, fitted by art-kit, own), prop.bridge (art-gen, fitted by art-kit, own), prop.ladder (art-gen, fitted by art-kit, own), creature.deer (Quaternius (mesh, rig and clips), pc-character (fitted to the slot, recoloured onto the palette), CC0 1.0 (Quaternius, Ultimate Animated Animal Pack: Deer, docs/licenses/quaternius-cc0_2026-10-15.txt)), creature.stag (Quaternius (mesh, rig and clips), pc-character (fitted to the slot, recoloured onto the palette), CC0 1.0 (Quaternius, Ultimate Animated Animal Pack: Stag, docs/licenses/quaternius-cc0_2026-10-15.txt)), creature.wolf (Quaternius (mesh, rig and clips), pc-character (fitted to the slot, recoloured onto the palette), CC0 1.0 (Quaternius, Ultimate Animated Animal Pack: Wolf, docs/licenses/quaternius-cc0_2026-10-15.txt)), creature.boar (art-gen (mesh), pc-character (rig fit); rig and clips Quaternius, own (mesh); CC0 1.0 (the Quaternius Pig's rig and clips, docs/licenses/quaternius-cc0_2026-10-15.txt)), creature.rabbit (art-gen (mesh), pc-character (rig and clips), own), creature.orc (pc-character (tools/body_gen.py, body_build.py --parts), own), creature.kobold (pc-character (tools/body_gen.py, body_build.py --parts), own), ground.dirt (art-gen, procedural, own), ground.sand (art-gen, procedural, own), fx.arrow (art-kit, own), ground.needles (art-gen, procedural (no model), own), material.rock (art-gen, own), item.antlers (art-gen, fitted by art-kit, own), item.arrows (art-gen, procedural (no model); fitted by art-kit, own), item.arrows_barbed (art-gen, procedural (no model); fitted by art-kit, own), item.arrows_flame (art-gen, procedural (no model); fitted by art-kit, own), item.axe_head (art-gen, fitted by art-kit, own), item.bandaging_kit (art-gen, fitted by art-kit, own), item.bow (art-kit, by hand from art-gen's c2, own), item.cloth_bolt (art-gen, fitted by art-kit, own), item.coin_purse (art-gen, fitted by art-kit, own), item.dagger (art-gen, fitted by art-kit, own), item.food_sack (art-gen, fitted by art-kit, own), item.giant_axe (art-gen, fitted by art-kit, own), item.hammer (art-gen, fitted by art-kit, own), item.hide (art-gen, fitted by art-kit, own), item.knife (art-gen, fitted by art-kit, own), item.meat (art-gen, fitted by art-kit, own), item.nails (art-gen, fitted by art-kit, own), item.ore_sack (art-gen, fitted by art-kit, own), item.ration (art-gen, fitted by art-kit, own), item.shield (art-gen, fitted by art-kit, own), item.spear (art-gen, fitted by art-kit, own), item.sword (art-gen, fitted by art-kit, own), item.tusks (art-gen, fitted by art-kit, own), item.wood_bundle (art-gen, fitted by art-kit, own).

<!-- end of art slots -->

## Sound slots

The sounds are sound slots (`art/audio/slots.json`, decision 267): each records where its
takes came from. The block below is written from it by `tools/sound_status.gd`, which also
writes `docs/sound_status.md`; `sound_kit_test` fails while either is out of date. Kenney's
files are copied unchanged and renamed; `art/audio/sfx/SOURCES.txt` names each original.

<!-- sound slots: written by tools/sound_status.gd from art/audio/slots.json; edit there -->

| Source | Licence | Where | Slots played from it |
|--------|---------|-------|----------------------|
| [Freesound](https://freesound.org) | CC0 1.0 or CC BY (each take's own, in art/audio/takes.json) (`docs/licenses/freesound.md`) | outside the repo (the sound library's `takes/`), copied to `art/audio/external/` by `tools/sound_sync.ps1` | amb.bat, amb.drips, amb.forest_deep_day, amb.forest_deep_night, amb.owl, amb.rain_canopy, amb.town_night, sfx.arrow_hit_flesh, sfx.arrow_hit_stone, sfx.arrow_hit_wood, sfx.arrow_land, sfx.block_shield, sfx.block_weapon, sfx.boar_death, sfx.boar_rout, sfx.bodyfall, sfx.bow_creak, sfx.bow_draw, sfx.bow_loose, sfx.break_stone, sfx.chest_close, sfx.chest_open, sfx.deer_death, sfx.deer_rout, sfx.deer_snort, sfx.door_wood_bar, sfx.door_wood_break, sfx.door_wood_unbar, sfx.door_wood_unlock, sfx.footstep_sand_medium, sfx.footstep_stone_medium, sfx.footstep_water_medium, sfx.goblin_chatter, sfx.goblin_pain, sfx.goblin_rout, sfx.hit_blade_armor, sfx.hit_blunt_armor, sfx.hit_blunt_flesh, sfx.hit_fist_flesh, sfx.hit_stone, sfx.item_drop_heavy, sfx.item_drop_light, sfx.item_pickup_heavy, sfx.item_pickup_light, sfx.knockdown, sfx.rabbit_death, sfx.rabbit_rout, sfx.splash, sfx.throw, sfx.thrown_land_light, sfx.wolf_death, sfx.wolf_howl, ui.chat_ping, ui.click, ui.error, ui.hover, ui.notify, ui.panel_close, ui.panel_open, voice.death_female, voice.death_male, voice.effort_hurt_female, voice.effort_hurt_male, voice.effort_lift_female, voice.effort_lift_male, voice.effort_swing_female, voice.effort_swing_male |
| [Impact Sounds 1.0, Kenney](https://kenney.nl/assets/impact-sounds) | CC0 1.0 (`art/audio/sfx/LICENSE-kenney-impact-sounds.txt`) | `art/audio/sfx/` | sfx.break_wood, sfx.death_player, sfx.footstep, sfx.hit_flesh, sfx.knockback_body, sfx.knockback_body_soft, sfx.knockback_stone, sfx.knockback_wood |
| [RPG Audio, Kenney](https://kenney.nl/assets/rpg-audio) | CC0 1.0 (`art/audio/sfx/LICENSE-kenney-rpg-audio.txt`) | `art/audio/sfx/` | sfx.death_companion, sfx.pack_open |
| [#GameAudioGDC 2021 to 2023 bundle, Sonniss](https://sonniss.com/gameaudiogdc) | Sonniss #GameAudioGDC Bundle licence v2.0 (`docs/licenses/sonniss-gameaudiogdc_2026-10-14.txt`) | outside the repo (the sound library's `takes/`), copied to `art/audio/external/` by `tools/sound_sync.ps1` | amb.forest_night, amb.rain, amb.torch_fire, amb.town_day, music.dungeon_base, music.melody_dungeon, music.melody_town, music.melody_wilds, music.sting_danger, music.sting_death, music.sting_discovery, music.sting_victory, music.temple_base, music.tension_high, music.tension_low, music.town_base, music.town_night, music.wilds_base, music.wilds_night, sfx.boar_charge, sfx.cart_roll, sfx.door_wood_close, sfx.door_wood_lock, sfx.door_wood_open, sfx.door_wood_rattle, sfx.footstep_claws, sfx.footstep_dirt_medium, sfx.footstep_grass_medium, sfx.footstep_hooves, sfx.footstep_paws, sfx.goblin_alert, sfx.goblin_death, sfx.hit_blade_flesh, sfx.hit_wood, sfx.swing, sfx.swing_heavy, voice.effort_hurt_female |
| [#GameAudioGDC 2024 bundle, Sonniss](https://sonniss.com/gameaudiogdc) | Sonniss #GameAudioGDC Bundle licence v2.0 (`docs/licenses/sonniss-gameaudiogdc_2026-10-14.txt`) | outside the repo (the sound library's `takes/`), copied to `art/audio/external/` by `tools/sound_sync.ps1` | amb.dungeon, amb.field_wind, amb.forest_dawn, amb.forest_day, amb.forest_night, amb.storm, sfx.bandage, sfx.boar_charge, sfx.crate_break, sfx.thrown_land_heavy |

Slots whose own takes came from someone else: none.

Takes credited to their makers:

- `amb.bat` (amb.bat.ogg): cut from [freesound 437934: G12-02-Bats Chirping.wav (from 8.25 s for 3 s)](https://freesound.org/people/craigsmith/sounds/437934/) by craigsmith, CC0 1.0
- `amb.bat` (amb.bat.2.ogg): cut from [freesound 437934: G12-02-Bats Chirping.wav (from 0.75 s for 3 s)](https://freesound.org/people/craigsmith/sounds/437934/) by craigsmith, CC0 1.0
- `amb.bat` (amb.bat.3.ogg): cut from [freesound 320721: bat sounds (from 13.5 s for 3 s)](https://freesound.org/people/pillonoise/sounds/320721/) by pillonoise, CC0 1.0
- `amb.bat` (amb.bat.4.ogg): cut from [freesound 349225: Bat Wings (Fast)](https://freesound.org/people/Natty23/sounds/349225/) by Natty23, CC BY 4.0
- `amb.drips` (amb.drips.ogg): cut from [freesound 277466: the sound of a forest after rain / drops falling on ferns rear (from 30 s for 60 s)](https://freesound.org/people/CRAFTCREST.com/sounds/277466/) by CRAFTCREST.com, CC BY 4.0
- `amb.forest_deep_day` (amb.forest_deep_day.ogg): cut from [freesound 563571: Wind in forest with creaking tree (from 5 s for 60 s)](https://freesound.org/people/Cinetony/sounds/563571/) by Cinetony, CC0 1.0
- `amb.forest_deep_day` (amb.forest_deep_day.2.ogg): cut from [freesound 140047: A tree is creaking in the patagonian forest of Argentina in a deep creaky sound. (Argentina, Tierra del Fuego). (from 20 s for 60 s)](https://freesound.org/people/felix.blume/sounds/140047/) by felix.blume, CC0 1.0
- `amb.forest_deep_night` (amb.forest_deep_night.ogg): cut from [freesound 662095: amb_forest_night.wav (from 5 s for 60 s)](https://freesound.org/people/Dokuta_Gerovv/sounds/662095/) by Dokuta_Gerovv, CC0 1.0
- `amb.forest_deep_night` (amb.forest_deep_night.2.ogg): cut from [freesound 532301: Night Woods (from 30 s for 60 s)](https://freesound.org/people/widgetstudios/sounds/532301/) by widgetstudios, CC0 1.0
- `amb.owl` (amb.owl.ogg): cut from [freesound 465697: Owl Hoot](https://freesound.org/people/Breviceps/sounds/465697/) by Breviceps, CC0 1.0
- `amb.owl` (amb.owl.2.ogg): cut from [freesound 398734: owl.wav](https://freesound.org/people/Anthousai/sounds/398734/) by Anthousai, CC0 1.0
- `amb.owl` (amb.owl.3.ogg): cut from [freesound 558397: owl_hooting_000102_0145S3 002-070 000-002 037-044.wav](https://freesound.org/people/Gerent/sounds/558397/) by Gerent, CC0 1.0
- `amb.owl` (amb.owl.4.ogg): cut from [freesound 558398: owl_hooting_000102_0145S3 002-070 000-002 007-015.wav](https://freesound.org/people/Gerent/sounds/558398/) by Gerent, CC0 1.0
- `amb.rain_canopy` (amb.rain_canopy.ogg): cut from [freesound 242956: Rain Fall Through Trees (from 5 s for 60 s)](https://freesound.org/people/acollier123/sounds/242956/) by acollier123, CC0 1.0
- `amb.rain_canopy` (amb.rain_canopy.2.ogg): cut from [freesound 34073: AMBIENT - Rain on Forest Canopy - Light (LOOP).mp3](https://freesound.org/people/Arctura/sounds/34073/) by Arctura, CC BY 3.0
- `amb.town_night` (amb.town_night.ogg): cut from [freesound 450994: crickets night field diverse +distant village voices Putti, Uganda1 MS.wav (from 10 s for 60 s)](https://freesound.org/people/kyles/sounds/450994/) by kyles, CC0 1.0
- `sfx.arrow_hit_flesh` (sfx.arrow_hit_flesh.ogg): cut from [freesound 161098: arrow_damage.wav](https://freesound.org/people/braqoon/sounds/161098/) by braqoon, CC0 1.0
- `sfx.arrow_hit_flesh` (sfx.arrow_hit_flesh.2.ogg): cut from [freesound 205938: Arrow Impact](https://freesound.org/people/Twisted_Euphoria/sounds/205938/) by Twisted_Euphoria, CC0 1.0
- `sfx.arrow_hit_flesh` (sfx.arrow_hit_flesh.3.ogg): cut from [freesound 464839: Anime Sound Effect - Piercing impact / Stabbing (from 0 s for 0.8 s)](https://freesound.org/people/Breviceps/sounds/464839/) by Breviceps, CC0 1.0
- `sfx.arrow_hit_stone` (sfx.arrow_hit_stone.ogg): cut from [freesound 50772: arrow_clatter.ogg (from 0 s for 0.9 s)](https://freesound.org/people/smcameron/sounds/50772/) by smcameron, CC BY 4.0
- `sfx.arrow_hit_wood` (sfx.arrow_hit_wood.ogg): cut from [freesound 384914: Arrow Impact 1](https://freesound.org/people/Ali_6868/sounds/384914/) by Ali_6868, CC0 1.0
- `sfx.arrow_hit_wood` (sfx.arrow_hit_wood.2.ogg): cut from [freesound 384913: Arrow Impact 2](https://freesound.org/people/Ali_6868/sounds/384913/) by Ali_6868, CC0 1.0
- `sfx.arrow_hit_wood` (sfx.arrow_hit_wood.3.ogg): cut from [freesound 384911: Arrow Impact 4](https://freesound.org/people/Ali_6868/sounds/384911/) by Ali_6868, CC0 1.0
- `sfx.arrow_land` (sfx.arrow_land.ogg): cut from [freesound 773759: Small Sticks Drop (from 0 s for 0.6 s)](https://freesound.org/people/IENBA/sounds/773759/) by IENBA, CC0 1.0
- `sfx.arrow_land` (sfx.arrow_land.2.ogg): cut from [freesound 773759: Small Sticks Drop (from 1.5 s for 1.05 s)](https://freesound.org/people/IENBA/sounds/773759/) by IENBA, CC0 1.0
- `sfx.arrow_land` (sfx.arrow_land.3.ogg): cut from [freesound 773759: Small Sticks Drop (from 3.5 s for 0.65 s)](https://freesound.org/people/IENBA/sounds/773759/) by IENBA, CC0 1.0
- `sfx.block_shield` (sfx.block_shield.ogg): cut from [freesound 370203: shield guard](https://freesound.org/people/nekoninja/sounds/370203/) by nekoninja, CC0 1.0
- `sfx.block_weapon` (sfx.block_weapon.ogg): cut from [freesound 733887: Sword Impact](https://freesound.org/people/velcronator/sounds/733887/) by velcronator, CC0 1.0
- `sfx.boar_death` (sfx.boar_death.ogg): cut from [freesound 233177: Pig - Grunt and Squeal 4 - 96kHz.wav](https://freesound.org/people/JarredGibb/sounds/233177/) by JarredGibb, CC0 1.0
- `sfx.boar_rout` (sfx.boar_rout.ogg): cut from [freesound 233184: Pig - Multiple Snorts 1 - 96kHz.wav](https://freesound.org/people/JarredGibb/sounds/233184/) by JarredGibb, CC0 1.0
- `sfx.boar_rout` (sfx.boar_rout.2.ogg): cut from [freesound 620080: LONG_Pig_Grunt_01.flac](https://freesound.org/people/wwstudioswastaken/sounds/620080/) by wwstudioswastaken, CC0 1.0
- `sfx.bodyfall` (sfx.bodyfall.ogg): cut from [freesound 346694: Body fall_02.wav](https://freesound.org/people/deleted_user_2104797/sounds/346694/) by deleted_user_2104797, CC0 1.0
- `sfx.bow_creak` (sfx.bow_creak.ogg): cut from [freesound 559079: Foley_Leather_Stress_Mono.wav (from 2.54 s for 3.29 s)](https://freesound.org/people/Nox_Sound/sounds/559079/) by Nox_Sound, CC0 1.0
- `sfx.bow_creak` (sfx.bow_creak.2.ogg): cut from [freesound 676986: Stretch - Long](https://freesound.org/people/NearTheAtmoshphere/sounds/676986/) by NearTheAtmoshphere, CC0 1.0
- `sfx.bow_draw` (sfx.bow_draw.ogg): cut from [freesound 490556: Bow Drawn (from 0 s for 2.15 s)](https://freesound.org/people/Paveroux/sounds/490556/) by Paveroux, CC0 1.0
- `sfx.bow_draw` (sfx.bow_draw.2.ogg): cut from [freesound 649336: Bow_draw_slow01.wav](https://freesound.org/people/SonoFxAudio/sounds/649336/) by SonoFxAudio, CC BY 4.0
- `sfx.bow_draw` (sfx.bow_draw.3.ogg): cut from [freesound 649332: Bow_draw_fast01.wav](https://freesound.org/people/SonoFxAudio/sounds/649332/) by SonoFxAudio, CC BY 4.0
- `sfx.bow_loose` (sfx.bow_loose.ogg): cut from [freesound 384915: Bow Release (Bow and Arrow)](https://freesound.org/people/Ali_6868/sounds/384915/) by Ali_6868, CC0 1.0
- `sfx.bow_loose` (sfx.bow_loose.2.ogg): cut from [freesound 263675: Bow_release.wav](https://freesound.org/people/PorkMuncher/sounds/263675/) by PorkMuncher, CC0 1.0
- `sfx.bow_loose` (sfx.bow_loose.3.ogg): cut from [freesound 394178: Longbow Release 1.wav](https://freesound.org/people/saturdaysoundguy/sounds/394178/) by saturdaysoundguy, CC0 1.0
- `sfx.bow_loose` (sfx.bow_loose.4.ogg): cut from [freesound 394180: Arrow Loose and Flyby](https://freesound.org/people/saturdaysoundguy/sounds/394180/) by saturdaysoundguy, CC0 1.0
- `sfx.break_stone` (sfx.break_stone.ogg): cut from [freesound 389618: Rock Tumble 2.wav](https://freesound.org/people/_stubb/sounds/389618/) by _stubb, CC0 1.0
- `sfx.break_stone` (sfx.break_stone.2.ogg): cut from [freesound 426318: Rocks Falling.wav](https://freesound.org/people/MTJohnson/sounds/426318/) by MTJohnson, CC0 1.0
- `sfx.chest_close` (sfx.chest_close.ogg): cut from [freesound 573648: Wooden Chest Lid Close.wav](https://freesound.org/people/The_Frisbee_of_Peace/sounds/573648/) by The_Frisbee_of_Peace, CC0 1.0
- `sfx.chest_close` (sfx.chest_close.2.ogg): cut from [freesound 573649: Wooden Chest Lid Latches Close_02.wav](https://freesound.org/people/The_Frisbee_of_Peace/sounds/573649/) by The_Frisbee_of_Peace, CC0 1.0
- `sfx.chest_open` (sfx.chest_open.ogg): cut from [freesound 573654: Wooden Chest Open.wav](https://freesound.org/people/The_Frisbee_of_Peace/sounds/573654/) by The_Frisbee_of_Peace, CC0 1.0
- `sfx.chest_open` (sfx.chest_open.2.ogg): cut from [freesound 573653: Wooden Chest Lid Latches Open.wav](https://freesound.org/people/The_Frisbee_of_Peace/sounds/573653/) by The_Frisbee_of_Peace, CC0 1.0
- `sfx.deer_death` (sfx.deer_death.ogg): cut from [freesound 696777: Deer_chucker_call_s](https://freesound.org/people/ferventtorpor/sounds/696777/) by ferventtorpor, CC0 1.0
- `sfx.deer_rout` (sfx.deer_rout.ogg): cut from [freesound 106113: bushhit.wav](https://freesound.org/people/j1987/sounds/106113/) by j1987, CC0 1.0
- `sfx.deer_rout` (sfx.deer_rout.2.ogg): cut from [freesound 540278: tree shake.wav](https://freesound.org/people/zepurple/sounds/540278/) by zepurple, CC0 1.0
- `sfx.deer_rout` (sfx.deer_rout.3.ogg): cut from [freesound 190641: Rustling foilage 1.wav](https://freesound.org/people/GUS_MAN/sounds/190641/) by GUS_MAN, CC0 1.0
- `sfx.deer_snort` (sfx.deer_snort.ogg): cut from [freesound 475480: Horse(snort)_1.wav](https://freesound.org/people/o_ciz/sounds/475480/) by o_ciz, CC0 1.0
- `sfx.deer_snort` (sfx.deer_snort.2.ogg): cut from [freesound 475479: Horse(snort)_2.wav](https://freesound.org/people/o_ciz/sounds/475479/) by o_ciz, CC0 1.0
- `sfx.deer_snort` (sfx.deer_snort.3.ogg): cut from [freesound 397236: Horse Snort.wav (from 0.4 s for 0.55 s)](https://freesound.org/people/black_trillium/sounds/397236/) by black_trillium, CC0 1.0
- `sfx.door_wood_bar` (sfx.door_wood_bar.ogg): cut from [freesound 459641: slide_big_4.wav](https://freesound.org/people/blaukreuz/sounds/459641/) by blaukreuz, CC0 1.0
- `sfx.door_wood_break` (sfx.door_wood_break.ogg): cut from [freesound 160213: Kicking/Forcing/Breaking Wooden Door](https://freesound.org/people/qubodup/sounds/160213/) by qubodup, CC0 1.0
- `sfx.door_wood_break` (sfx.door_wood_break.2.ogg): cut from [freesound 723974: Wooden Door breaks](https://freesound.org/people/Saladsounds/sounds/723974/) by Saladsounds, CC0 1.0
- `sfx.door_wood_unbar` (sfx.door_wood_unbar.ogg): cut from [freesound 459643: slide_big_2.wav](https://freesound.org/people/blaukreuz/sounds/459643/) by blaukreuz, CC0 1.0
- `sfx.door_wood_unlock` (sfx.door_wood_unlock.ogg): cut from [freesound 448395: Metallic Bolt Lock 2](https://freesound.org/people/LordForklift/sounds/448395/) by LordForklift, CC0 1.0
- `sfx.footstep_sand_medium` (sfx.footstep_sand_medium.ogg): cut from [freesound 778548: Steps_Fine_Snow_Or_Sand_Strong_10](https://freesound.org/people/BlondPanda/sounds/778548/) by BlondPanda, CC0 1.0
- `sfx.footstep_sand_medium` (sfx.footstep_sand_medium.2.ogg): cut from [freesound 778545: Steps_Fine_Snow_Or_Sand_Strong_07](https://freesound.org/people/BlondPanda/sounds/778545/) by BlondPanda, CC0 1.0
- `sfx.footstep_sand_medium` (sfx.footstep_sand_medium.3.ogg): cut from [freesound 778547: Steps_Fine_Snow_Or_Sand_Strong_09](https://freesound.org/people/BlondPanda/sounds/778547/) by BlondPanda, CC0 1.0
- `sfx.footstep_sand_medium` (sfx.footstep_sand_medium.4.ogg): cut from [freesound 778546: Steps_Fine_Snow_Or_Sand_Strong_08](https://freesound.org/people/BlondPanda/sounds/778546/) by BlondPanda, CC0 1.0
- `sfx.footstep_sand_medium` (sfx.footstep_sand_medium.5.ogg): cut from [freesound 778543: Steps_Fine_Snow_Or_Sand_Strong_05](https://freesound.org/people/BlondPanda/sounds/778543/) by BlondPanda, CC0 1.0
- `sfx.footstep_stone_medium` (sfx.footstep_stone_medium.ogg): cut from [freesound 813622: Footsteps - Stone, Rock, Concrete, Cement (from 1.03 s for 0.5 s)](https://freesound.org/people/SecureSubset/sounds/813622/) by SecureSubset, CC0 1.0
- `sfx.footstep_stone_medium` (sfx.footstep_stone_medium.2.ogg): cut from [freesound 813622: Footsteps - Stone, Rock, Concrete, Cement (from 2.19 s for 0.5 s)](https://freesound.org/people/SecureSubset/sounds/813622/) by SecureSubset, CC0 1.0
- `sfx.footstep_stone_medium` (sfx.footstep_stone_medium.3.ogg): cut from [freesound 813622: Footsteps - Stone, Rock, Concrete, Cement (from 3.44 s for 0.5 s)](https://freesound.org/people/SecureSubset/sounds/813622/) by SecureSubset, CC0 1.0
- `sfx.footstep_stone_medium` (sfx.footstep_stone_medium.4.ogg): cut from [freesound 813622: Footsteps - Stone, Rock, Concrete, Cement (from 4.78 s for 0.5 s)](https://freesound.org/people/SecureSubset/sounds/813622/) by SecureSubset, CC0 1.0
- `sfx.footstep_stone_medium` (sfx.footstep_stone_medium.5.ogg): cut from [freesound 521590: Hiking Boot Footsteps on Stone (from 0.68 s for 0.45 s)](https://freesound.org/people/Fission9/sounds/521590/) by Fission9, CC0 1.0
- `sfx.footstep_stone_medium` (sfx.footstep_stone_medium.6.ogg): cut from [freesound 521590: Hiking Boot Footsteps on Stone (from 1.79 s for 0.45 s)](https://freesound.org/people/Fission9/sounds/521590/) by Fission9, CC0 1.0
- `sfx.footstep_water_medium` (sfx.footstep_water_medium.ogg): cut from [freesound 861369: Splashing Footsteps Shallow Water (from 0.72 s for 0.45 s)](https://freesound.org/people/ChristopherJngs/sounds/861369/) by ChristopherJngs, CC0 1.0
- `sfx.footstep_water_medium` (sfx.footstep_water_medium.2.ogg): cut from [freesound 861369: Splashing Footsteps Shallow Water (from 1.24 s for 0.45 s)](https://freesound.org/people/ChristopherJngs/sounds/861369/) by ChristopherJngs, CC0 1.0
- `sfx.footstep_water_medium` (sfx.footstep_water_medium.3.ogg): cut from [freesound 861369: Splashing Footsteps Shallow Water (from 1.8 s for 0.45 s)](https://freesound.org/people/ChristopherJngs/sounds/861369/) by ChristopherJngs, CC0 1.0
- `sfx.footstep_water_medium` (sfx.footstep_water_medium.4.ogg): cut from [freesound 861369: Splashing Footsteps Shallow Water (from 2.84 s for 0.45 s)](https://freesound.org/people/ChristopherJngs/sounds/861369/) by ChristopherJngs, CC0 1.0
- `sfx.goblin_chatter` (sfx.goblin_chatter.ogg): cut from [freesound 202096: Goblin Cackle.wav](https://freesound.org/people/spookymodem/sounds/202096/) by spookymodem, CC0 1.0
- `sfx.goblin_chatter` (sfx.goblin_chatter.2.ogg): cut from [freesound 442815: Goblin Snarl](https://freesound.org/people/qubodup/sounds/442815/) by qubodup, CC0 1.0
- `sfx.goblin_chatter` (sfx.goblin_chatter.3.ogg): cut from [freesound 442817: Goblin Growl](https://freesound.org/people/qubodup/sounds/442817/) by qubodup, CC0 1.0
- `sfx.goblin_pain` (sfx.goblin_pain.ogg): cut from [freesound 738437: Orc Grunt 1](https://freesound.org/people/qubodup/sounds/738437/) by qubodup, CC BY 4.0
- `sfx.goblin_pain` (sfx.goblin_pain.2.ogg): cut from [freesound 738439: Orc Grunt 3](https://freesound.org/people/qubodup/sounds/738439/) by qubodup, CC BY 4.0
- `sfx.goblin_rout` (sfx.goblin_rout.ogg): cut from [freesound 202100: Goblin Scream.wav](https://freesound.org/people/spookymodem/sounds/202100/) by spookymodem, CC0 1.0
- `sfx.goblin_rout` (sfx.goblin_rout.2.ogg): cut from [freesound 442816: Goblin Scream](https://freesound.org/people/qubodup/sounds/442816/) by qubodup, CC0 1.0
- `sfx.hit_blade_armor` (sfx.hit_blade_armor.ogg): cut from [freesound 420675: Cut Through Armor / Slice / Clang](https://freesound.org/people/SypherZent/sounds/420675/) by SypherZent, CC BY 4.0
- `sfx.hit_blunt_armor` (sfx.hit_blunt_armor.ogg): cut from [freesound 337838: med-metal-hit-02.wav](https://freesound.org/people/newagesoup/sounds/337838/) by newagesoup, CC0 1.0
- `sfx.hit_blunt_flesh` (sfx.hit_blunt_flesh.ogg): cut from [freesound 348242: PUNCH-BOXING-03.wav](https://freesound.org/people/newagesoup/sounds/348242/) by newagesoup, CC0 1.0
- `sfx.hit_fist_flesh` (sfx.hit_fist_flesh.ogg): cut from [freesound 493914: light punch](https://freesound.org/people/damnsatinist/sounds/493914/) by damnsatinist, CC BY 4.0
- `sfx.hit_stone` (sfx.hit_stone.ogg): cut from [freesound 431019: Stone hit](https://freesound.org/people/CamoMano/sounds/431019/) by CamoMano, CC0 1.0
- `sfx.hit_stone` (sfx.hit_stone.2.ogg): cut from [freesound 760567: Pickaxe3](https://freesound.org/people/NoisyRedFox/sounds/760567/) by NoisyRedFox, CC0 1.0
- `sfx.item_drop_heavy` (sfx.item_drop_heavy.ogg): cut from [freesound 271241: briefcaseDroppingFloor.wav](https://freesound.org/people/bertiehs/sounds/271241/) by bertiehs, CC0 1.0
- `sfx.item_drop_light` (sfx.item_drop_light.ogg): cut from [freesound 339363: drop07.wav](https://freesound.org/people/newagesoup/sounds/339363/) by newagesoup, CC0 1.0
- `sfx.item_drop_light` (sfx.item_drop_light.2.ogg): cut from [freesound 339364: drop06.wav](https://freesound.org/people/newagesoup/sounds/339364/) by newagesoup, CC0 1.0
- `sfx.item_pickup_heavy` (sfx.item_pickup_heavy.ogg): cut from [freesound 216629: Picking up small box with items inside](https://freesound.org/people/WiesenWiesel/sounds/216629/) by WiesenWiesel, CC BY 4.0
- `sfx.item_pickup_light` (sfx.item_pickup_light.ogg): cut from [freesound 822565: Picking Up A Small Item](https://freesound.org/people/qubodup/sounds/822565/) by qubodup, CC0 1.0
- `sfx.knockdown` (sfx.knockdown.ogg): cut from [freesound 346695: Body fall_01.wav](https://freesound.org/people/deleted_user_2104797/sounds/346695/) by deleted_user_2104797, CC0 1.0
- `sfx.rabbit_death` (sfx.rabbit_death.ogg): cut from [freesound 385850: Rabbit Squeaking 1 (from 0.08 s for 0.66 s)](https://freesound.org/people/kessir/sounds/385850/) by kessir, CC BY 4.0
- `sfx.rabbit_death` (sfx.rabbit_death.2.ogg): cut from [freesound 385850: Rabbit Squeaking 1 (from 2.21 s for 0.56 s)](https://freesound.org/people/kessir/sounds/385850/) by kessir, CC BY 4.0
- `sfx.rabbit_rout` (sfx.rabbit_rout.ogg): cut from [freesound 106114: bushmovement.wav](https://freesound.org/people/j1987/sounds/106114/) by j1987, CC0 1.0
- `sfx.rabbit_rout` (sfx.rabbit_rout.2.ogg): cut from [freesound 386007: Rabbit Thump on Soil (from 0 s for 0.95 s)](https://freesound.org/people/kessir/sounds/386007/) by kessir, CC0 1.0
- `sfx.splash` (sfx.splash.ogg): cut from [freesound 482953: splash_1.wav](https://freesound.org/people/genel/sounds/482953/) by genel, CC0 1.0
- `sfx.throw` (sfx.throw.ogg): cut from [freesound 346373: Throwing / Whip Effect](https://freesound.org/people/denao270/sounds/346373/) by denao270, CC0 1.0
- `sfx.thrown_land_light` (sfx.thrown_land_light.ogg): cut from [freesound 339362: drop08.wav](https://freesound.org/people/newagesoup/sounds/339362/) by newagesoup, CC0 1.0
- `sfx.wolf_death` (sfx.wolf_death.ogg): cut from [freesound 163280: DogYelp.wav](https://freesound.org/people/TobiasKosmos/sounds/163280/) by TobiasKosmos, CC BY 4.0
- `sfx.wolf_death` (sfx.wolf_death.2.ogg): cut from [freesound 735365: Small Dog Cry](https://freesound.org/people/haulaway/sounds/735365/) by haulaway, CC0 1.0
- `sfx.wolf_howl` (sfx.wolf_howl.ogg): cut from [freesound 712068: Giant Wolf Howl](https://freesound.org/people/NaturesTemper/sounds/712068/) by NaturesTemper, CC BY 4.0
- `ui.chat_ping` (ui.chat_ping.ogg): cut from [freesound 760369: Message Receive](https://freesound.org/people/Froey_/sounds/760369/) by Froey_, CC0 1.0
- `ui.click` (ui.click.ogg): cut from [freesound 448086: Normal click](https://freesound.org/people/Breviceps/sounds/448086/) by Breviceps, CC0 1.0
- `ui.click` (ui.click.2.ogg): cut from [freesound 253168: SFX UI Button Click](https://freesound.org/people/suntemple/sounds/253168/) by suntemple, CC0 1.0
- `ui.error` (ui.error.ogg): cut from [freesound 366103: Error Wooden](https://freesound.org/people/original_sound/sounds/366103/) by original_sound, CC BY 3.0
- `ui.hover` (ui.hover.ogg): cut from [freesound 488381: UIHover1.wav](https://freesound.org/people/wobesound/sounds/488381/) by wobesound, CC0 1.0
- `ui.notify` (ui.notify.ogg): cut from [freesound 750607: Notification Sound 1](https://freesound.org/people/deadrobotmusic/sounds/750607/) by deadrobotmusic, CC0 1.0
- `ui.panel_close` (ui.panel_close.ogg): cut from [freesound 484886: Book Close - 6](https://freesound.org/people/SpaceJoe/sounds/484886/) by SpaceJoe, CC0 1.0
- `ui.panel_open` (ui.panel_open.ogg): cut from [freesound 397548: Page Turn 01](https://freesound.org/people/LilMati/sounds/397548/) by LilMati, CC0 1.0
- `voice.death_female` (voice.death_female.ogg): cut from [freesound 845164: Woman Screaming (from 0 s for 2.2 s)](https://freesound.org/people/DanJFilms/sounds/845164/) by DanJFilms, CC0 1.0
- `voice.death_male` (voice.death_male.ogg): cut from [freesound 547181: Voice_AdultMale_DeathScream_04.wav](https://freesound.org/people/MrFossy/sounds/547181/) by MrFossy, CC0 1.0
- `voice.death_male` (voice.death_male.2.ogg): cut from [freesound 547188: Voice_AdultMale_DeathScream_05.wav](https://freesound.org/people/MrFossy/sounds/547188/) by MrFossy, CC0 1.0
- `voice.effort_hurt_female` (voice.effort_hurt_female.5.ogg): cut from [freesound 203976: female_hurt.wav](https://freesound.org/people/thatbennyguy/sounds/203976/) by thatbennyguy, CC0 1.0
- `voice.effort_hurt_female` (voice.effort_hurt_female.6.ogg): cut from [freesound 547344: Ouch !](https://freesound.org/people/Legnalegna55/sounds/547344/) by Legnalegna55, CC0 1.0
- `voice.effort_hurt_male` (voice.effort_hurt_male.ogg): cut from [freesound 547193: Voice_AdultMale_PainGrunts_14.wav](https://freesound.org/people/MrFossy/sounds/547193/) by MrFossy, CC0 1.0
- `voice.effort_hurt_male` (voice.effort_hurt_male.2.ogg): cut from [freesound 547198: Voice_AdultMale_PainGrunts_15.wav](https://freesound.org/people/MrFossy/sounds/547198/) by MrFossy, CC0 1.0
- `voice.effort_hurt_male` (voice.effort_hurt_male.3.ogg): cut from [freesound 547205: Voice_AdultMale_PainGrunts_07.wav](https://freesound.org/people/MrFossy/sounds/547205/) by MrFossy, CC0 1.0
- `voice.effort_lift_female` (voice.effort_lift_female.ogg): cut from [freesound 507730: EffortNoise.wav](https://freesound.org/people/Keskaowl/sounds/507730/) by Keskaowl, CC0 1.0
- `voice.effort_lift_male` (voice.effort_lift_male.ogg): cut from [freesound 557131: ManlyGrunt02.wav](https://freesound.org/people/melisandepope/sounds/557131/) by melisandepope, CC0 1.0
- `voice.effort_lift_male` (voice.effort_lift_male.2.ogg): cut from [freesound 557134: ManlySounds01.wav](https://freesound.org/people/melisandepope/sounds/557134/) by melisandepope, CC0 1.0
- `voice.effort_swing_female` (voice.effort_swing_female.ogg): cut from [freesound 242623: grunt.wav](https://freesound.org/people/Reitanna/sounds/242623/) by Reitanna, CC0 1.0
- `voice.effort_swing_female` (voice.effort_swing_female.2.ogg): cut from [freesound 242622: grunt2.wav](https://freesound.org/people/Reitanna/sounds/242622/) by Reitanna, CC0 1.0
- `voice.effort_swing_male` (voice.effort_swing_male.ogg): cut from [freesound 695378: Male Attack Grunt 1.wav](https://freesound.org/people/F.M.Audio/sounds/695378/) by F.M.Audio, CC BY 4.0
- `voice.effort_swing_male` (voice.effort_swing_male.2.ogg): cut from [freesound 695380: Male Attack Grunt 3.wav](https://freesound.org/people/F.M.Audio/sounds/695380/) by F.M.Audio, CC BY 4.0

<!-- end of sound slots -->

## Other assets

| Asset | By | Licence | Where | Notes |
|-------|----|---------|-------|-------|
| Universal Animation Library (Pro) | Quaternius | CC0 1.0 | `art/models/animations/LICENSE-quaternius-ual.txt` | the goblin's clips, retargeted, and the skeleton and clips of the human bodies; the clips pc-character authored on its skeleton (decision 399) are our own, under the pack's CC0 (`art/models/SOURCES.txt`) |
| Retro Textures Fantasy 1.0 | Kenney | CC0 1.0 | `art/kenney_retro-textures-fantasy/License.txt` | in the repo, not drawn by the game now |
| Alegreya (variable) and Alegreya Sans (Regular, Bold) fonts | Juan Pablo del Peral, Huerta Tipográfica | SIL Open Font License 1.1 (`art/fonts/OFL-Alegreya.txt`, `art/fonts/OFL-AlegreyaSans.txt`; sources and date in `art/fonts/SOURCES.txt`) | `art/fonts/` | the interface's faces (docs/ui_style.md, the shared theme `render/ui_theme.tres`, decision 401): unmodified, not renamed |
| Sonniss #GameAudioGDC bundles 2024 and 2021–23 | Sonniss | Sonniss GameAudioGDC Bundle licence v2.0, effective 2026-08-27: royalty-free, commercial use in our own projects; no redistributing the sounds as sounds, and no AI or machine-learning use | `docs/licenses/sonniss-gameaudiogdc_2026-10-14.txt` | a source library for the game's sounds; the files stay outside the repo (`N:\assets\sound`), and only what the game uses goes into it, inside the game |

## Tools used to make assets

| Tool | By | Licence | Used for |
|------|----|---------|----------|
| TRELLIS.2 | Microsoft | MIT | meshes from a concept image: the goblin (`art/models/SOURCES.txt`), slot candidates |
| DINOv3 image encoder | Meta | DINOv3 License | inside TRELLIS.2, for the goblin |
| BiRefNet | ZhengPeng7 | MIT | background removal for the goblin's concept image |
| Qwen-Image-2512 | Qwen (Alibaba) | Apache-2.0 | concept images for slot candidates (the art-gen session, run through ComfyUI) |
| Qwen2.5-VL-7B (text encoder) | Qwen (Alibaba) | Apache-2.0 | inside Qwen-Image-2512 |
| Qwen-Image ComfyUI repacks | Comfy-Org | Apache-2.0 | the model files ComfyUI loads |
| Qwen-Image-2512-Lightning LoRA | lightx2v | Apache-2.0 | faster sampling for the same |
| ComfyUI | Comfy-Org | GPL-3.0 (the program; what it makes is the maker's) | running the image models |
| Blender | Blender Foundation | GPL (the program; what it makes is the maker's) | modelling, painting, rigging; slot exports (`tools/blender/export_slot.py`) |
| Godot Engine | Godot contributors | MIT | the game |

**Not to be used:** Qwen-Image-2.1 (installed in `C:\ComfyUI`). Its licence, the Qwen Research
License, allows research and evaluation only, with no commercial use.

Slot candidates from the art-gen session (`C:\dev\art-gen`) land in
`N:\assets\candidates\<slot>\` with a `notes.md` naming the model files, LoRA, prompts, seeds and
licences. A candidate picked for a slot cites that note in the slot's `source` (its `notes`).

## Models (vetting)

Every model used to make assets is vetted before use (Jeff): what it is exactly, where it came
from, what its licence says on the day it was read, and whether it may be used. Approved means
nothing it makes is held back by its licence (no non-commercial, research-only or regional
limit). The licence text as read is kept in `docs/licenses/<model>_<YYYY-MM-DD>.txt`. The art-gen
session sends rows and licence texts through the coordinator, and art-kit commits them. A dash
marks something still to fill in, and a model with a dash in its verdict may not be used yet.

| Model | Version or file SHA-256 | Source | Licence | Read | Verdict | Why |
|-------|-------------------------|--------|---------|------|---------|-----|
| Qwen-Image-2512 | Comfy-Org/Qwen-Image_ComfyUI rev 1f12b17be14c89b026c51a91d67c32f84bb047bc, split_files/diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors SHA-256 5dc80554d5d83390046a2f4a94ece06afb7700bf7b0aaf8bde9769793875876b | https://huggingface.co/Qwen/Qwen-Image-2512 (card rev 25468b98e3276ca6700de15c6628e51b7de54a26); fp8 repack https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI | Apache-2.0; `docs/licenses/qwen-image-2512_2026-10-14.txt` | 2026-10-14 | approved | Apache-2.0: commercial use worldwide, no caps or field limits; the concept-image model |
| Qwen-Image VAE | Comfy-Org/Qwen-Image_ComfyUI rev 1f12b17be14c89b026c51a91d67c32f84bb047bc, split_files/vae/qwen_image_vae.safetensors SHA-256 a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f | https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI (from Qwen-Image, https://github.com/QwenLM/Qwen-Image) | Apache-2.0; `docs/licenses/qwen-image-2512_2026-10-14.txt` | 2026-10-14 | approved | Apache-2.0, part of Qwen-Image; decodes the concept images |
| Qwen2.5-VL-7B-Instruct | Comfy-Org/Qwen-Image_ComfyUI rev 1f12b17be14c89b026c51a91d67c32f84bb047bc, split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors SHA-256 cb5636d852a0ea6a9075ab1bef496c0db7aef13c02350571e388aea959c5c0b4 | https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct (card rev cc594898137f460bfe9f0759e9844b3ce807cfb5); fp8 repack https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI | Apache-2.0; `docs/licenses/qwen2.5-vl-7b-instruct_2026-10-14.txt` | 2026-10-14 | approved | Apache-2.0 (the 7B size); Qwen-Image's text encoder |
| Qwen-Image-2512-Lightning | lightx2v/Qwen-Image-2512-Lightning rev a52649c9d0f6e1a248bff13f0df33bb8a2abdb52, Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors SHA-256 b48fb1a8edd939354579c1cf0b403c92f28879b32dddbaaa91b9d424bfc72081 (4steps-V1.0-bf16, not used now: de0d236e54ecf2c43b32447d13478c6eae0d361b1fed48c69675b084fa240d87) | https://huggingface.co/lightx2v/Qwen-Image-2512-Lightning | Apache-2.0; `docs/licenses/qwen-image-2512-lightning_2026-10-14.txt` | 2026-10-14 | approved | Apache-2.0 speed LoRA (8 steps), the goblin's setting |
| Qwen-Image-2.1 | — | — | Qwen Research License | — | **banned** | research and evaluation only, no commercial use |
| TRELLIS.2-4B | microsoft/TRELLIS.2-4B rev af44b45f2e35a493886929c6d786e563ec68364d; ckpts SHA-256: ss_flow_img_dit_1_3B_64_bf16 ca01377c485bec418076d38ee80166d32dc776d744f2553b835cba1e97a7abf6, slat_flow_img2shape_dit_1_3B_512_bf16 ec5e0917ef9b7e25ad51dffc7d19687a42019871f94239f2fa7f86264c55b70f, slat_flow_img2shape_dit_1_3B_1024_bf16 07cd0596f634c5adc1890023d16023afc5eed02fb84b22bb23aff5bf0030fbbd, shape_dec_next_dc_f16c32_fp16 e3b718d3e43e4f8780e9a24ac6fff231811a67e3b058e336e10fe654c911d581 | https://huggingface.co/microsoft/TRELLIS.2-4B | MIT; `docs/licenses/trellis.2-4b_2026-10-14.txt` | 2026-10-14 | approved | MIT: code and weights, commercial use fine; shape checkpoints only, texture models not downloaded |
| TRELLIS-image-large (sparse-structure decoder) | microsoft/TRELLIS-image-large rev 25e0d31ffbebe4b5a97464dd851910efc3002d96, ckpts/ss_dec_conv3d_16l8_fp16.safetensors SHA-256 1c76d4a40519aa2d711cc263a8404105231ac26db31d946bed48b84fee79009a | https://huggingface.co/microsoft/TRELLIS-image-large | MIT; `docs/licenses/trellis-image-large_2026-10-14.txt` | 2026-10-14 | approved | MIT; the one TRELLIS v1 checkpoint TRELLIS.2 loads |
| DINOv3 ViT-L/16 (facebook/dinov3-vitl16-pretrain-lvd1689m) | rev ea8dc2863c51be0a264bab82070e3e8836b02d51; model.safetensors SHA-256 dcb2e45127cccbf1601e5f42fef165eea275c8e5213197e8dcf3f48822718179 | https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m | DINOv3 License (Meta, last updated 2025-08-19); `docs/licenses/dinov3_2026-10-14.txt` | 2026-10-14 | approved | commercial use worldwide, royalty-free, no caps; outputs (meshes) aren't "DINO Materials" and carry no terms; the use limits are real-world ITAR/military/weapons, not a fantasy game |
| BiRefNet | ZhengPeng7/BiRefNet rev e2bf8e4460fc8fa32bba5ea4d94b3233d367b0e4, model.safetensors SHA-256 9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154 | https://huggingface.co/ZhengPeng7/BiRefNet | MIT; `docs/licenses/birefnet_2026-10-14.txt` | 2026-10-14 | approved | MIT, weights and its remote model code; background removal in place of RMBG-2.0 (CC BY-NC, removed) |
| RMBG-2.0 | — | — | CC BY-NC | — | **banned** | non-commercial; was TRELLIS.2's background removal, removed for BiRefNet |
| Quaternius animals: Ultimate Animated Animal Pack (2021), and the Pig of an atlas-textured Quaternius set | the pack's Google Drive folder 1uJ3N5HfB7jKTseJUNQr3N4YaN0UuEtHk (License.txt, glTF), kept in `N:\assets\sources\quaternius\animals\`; the Pig from https://poly.pizza/m/u35l6uP5vj | https://quaternius.com/packs/ultimateanimatedanimals.html | CC0 1.0; `docs/licenses/quaternius-cc0_2026-10-15.txt` | 2026-10-15 | approved | CC0 public-domain dedication (the pack's own License.txt, its page, quaternius.com's FAQ and poly.pizza all say so): worldwide, any purpose including commercial, no attribution; the deer, stag and wolf (decision 319), the boar's rig and clips |

**DINOv3 needs the monthly re-check.** Its licence's §8 lets Meta change the terms at any time, and
continuing to use DINOv3 counts as agreeing to the change. Read it again each month against
`docs/licenses/dinov3_2026-10-14.txt`. If it has changed, save the new text as a new dated file and
review the verdict.
