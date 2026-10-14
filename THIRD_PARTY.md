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
| [Castle Kit 2.0, Kenney](https://kenney.nl/assets/castle-kit) | CC0 1.0 (`art/kenney-castle/License.txt`) | `art/kenney-castle/Models/GLB format/` | door.single, rock.small, tree.broadleaf, tree.small, wall.post, wall.straight |

Slots whose own art came from someone else: none.

<!-- end of art slots -->

## Other assets

| Asset | By | Licence | Where | Notes |
|-------|----|---------|-------|-------|
| Impact Sounds 1.0 | Kenney | CC0 1.0 | `art/audio/sfx/LICENSE-kenney-impact-sounds.txt` | sound effects, copied unchanged; which file is which in `art/audio/sfx/SOURCES.txt` |
| RPG Audio | Kenney | CC0 1.0 | `art/audio/sfx/LICENSE-kenney-rpg-audio.txt` | as above |
| Universal Animation Library (Pro) | Quaternius | CC0 1.0 | `art/models/animations/LICENSE-quaternius-ual.txt` | the goblin's clips, retargeted (`art/models/SOURCES.txt`) |
| Retro Textures Fantasy 1.0 | Kenney | CC0 1.0 | `art/kenney_retro-textures-fantasy/License.txt` | in the repo, not drawn by the game now |

## Tools used to make assets

| Tool | By | Licence | Used for |
|------|----|---------|----------|
| TRELLIS.2 | Microsoft | MIT | the goblin's mesh, from a concept image (`art/models/SOURCES.txt`) |
| DINOv3 image encoder | Meta | DINOv3 License | inside TRELLIS.2, for the goblin |
| BiRefNet | ZhengPeng7 | MIT | background removal for the goblin's concept image |
| Blender | Blender Foundation | GPL (the program; what it makes is the maker's) | modelling, painting, rigging; slot exports (`tools/blender/export_slot.py`) |
| Godot Engine | Godot contributors | MIT | the game |
