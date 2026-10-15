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

## Sound slots

The sounds are sound slots (`art/audio/slots.json`, decision 267): each records where its
takes came from. The block below is written from it by `tools/sound_status.gd`, which also
writes `docs/sound_status.md`; `sound_kit_test` fails while either is out of date. Kenney's
files are copied unchanged and renamed; `art/audio/sfx/SOURCES.txt` names each original.

<!-- sound slots: written by tools/sound_status.gd from art/audio/slots.json; edit there -->

| Source | Licence | Where | Slots played from it |
|--------|---------|-------|----------------------|
| [Impact Sounds 1.0, Kenney](https://kenney.nl/assets/impact-sounds) | CC0 1.0 (`art/audio/sfx/LICENSE-kenney-impact-sounds.txt`) | `art/audio/sfx/` | sfx.break_wood, sfx.death_player, sfx.footstep, sfx.goblin_death, sfx.hit_flesh, sfx.knockback_body, sfx.knockback_body_soft, sfx.knockback_stone, sfx.knockback_wood |
| [RPG Audio, Kenney](https://kenney.nl/assets/rpg-audio) | CC0 1.0 (`art/audio/sfx/LICENSE-kenney-rpg-audio.txt`) | `art/audio/sfx/` | sfx.chest_open, sfx.death_companion, sfx.door_wood_close, sfx.door_wood_open, sfx.pack_open, sfx.swing |
| [#GameAudioGDC 2021 to 2023 bundle, Sonniss](https://sonniss.com/gameaudiogdc) | Sonniss #GameAudioGDC Bundle licence v2.0 (`docs/licenses/sonniss-gameaudiogdc_2026-10-14.txt`) | outside the repo (the sound library's `takes/`), copied to `art/audio/external/` by `tools/sound_sync.ps1` | none now |
| [#GameAudioGDC 2024 bundle, Sonniss](https://sonniss.com/gameaudiogdc) | Sonniss #GameAudioGDC Bundle licence v2.0 (`docs/licenses/sonniss-gameaudiogdc_2026-10-14.txt`) | outside the repo (the sound library's `takes/`), copied to `art/audio/external/` by `tools/sound_sync.ps1` | none now |

Slots whose own takes came from someone else: none.

<!-- end of sound slots -->

## Other assets

| Asset | By | Licence | Where | Notes |
|-------|----|---------|-------|-------|
| Universal Animation Library (Pro) | Quaternius | CC0 1.0 | `art/models/animations/LICENSE-quaternius-ual.txt` | the goblin's clips, retargeted (`art/models/SOURCES.txt`) |
| Retro Textures Fantasy 1.0 | Kenney | CC0 1.0 | `art/kenney_retro-textures-fantasy/License.txt` | in the repo, not drawn by the game now |
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

**DINOv3 needs the monthly re-check.** Its licence's §8 lets Meta change the terms at any time, and
continuing to use DINOv3 counts as agreeing to the change. Read it again each month against
`docs/licenses/dinov3_2026-10-14.txt`. If it has changed, save the new text as a new dated file and
review the verdict.
