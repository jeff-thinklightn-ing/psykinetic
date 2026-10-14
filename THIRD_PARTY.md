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
`D:\assets\candidates\<slot>\` with a `notes.md` naming the model files, LoRA, prompts, seeds and
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
| Qwen-Image-2512 | — | — | Apache-2.0 | — | approved | Apache-2.0 allows commercial use; concept images for slot candidates |
| Qwen2.5-VL-7B (text encoder) | — | — | Apache-2.0 | — | approved | Apache-2.0; part of Qwen-Image-2512 |
| Qwen-Image ComfyUI repacks (Comfy-Org) | — | — | Apache-2.0 | — | approved | repackaged weights of the above, same licence |
| Qwen-Image-2512-Lightning LoRA (lightx2v) | — | — | Apache-2.0 | — | approved | Apache-2.0; faster sampling only |
| Qwen-Image-2.1 | — | — | Qwen Research License | — | **banned** | research and evaluation only, no commercial use |
| TRELLIS.2 (Microsoft) | — | — | MIT | — | approved | MIT; meshes from concept images (the goblin, slot candidates) |
| DINOv3 ViT-L/16 (facebook/dinov3-vitl16-pretrain-lvd1689m) | rev ea8dc2863c51be0a264bab82070e3e8836b02d51; model.safetensors SHA-256 dcb2e45127cccbf1601e5f42fef165eea275c8e5213197e8dcf3f48822718179 | https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m | DINOv3 License (Meta, last updated 2025-08-19); `docs/licenses/dinov3_2026-10-14.txt` | 2026-10-14 | approved | commercial use worldwide, royalty-free, no caps; outputs (meshes) aren't "DINO Materials" and carry no terms; the use limits are real-world ITAR/military/weapons, not a fantasy game |
| BiRefNet (ZhengPeng7) | — | — | MIT | — | approved | MIT; background removal for concept images |

**DINOv3 needs the monthly re-check.** Its licence's §8 lets Meta change the terms at any time, and
continuing to use DINOv3 counts as agreeing to the change. Read it again each month against
`docs/licenses/dinov3_2026-10-14.txt`. If it has changed, save the new text as a new dated file and
review the verdict.
