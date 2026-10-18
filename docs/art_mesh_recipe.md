# Art mesh recipe: concept image to game mesh

The one way a creature or character mesh is made from a concept image, from now on. It is the goblin's recipe
(`art/models/characters/goblin.blend`, 2026-10-09), the mesh that reads best in game, written down and scripted.
Jeff, 2026-10-18: "poly count isn't the issue then its the step from image to 3d mesh thats gone terribly wrong".

Tools live in art-gen (`C:\dev\art-gen`); meshes go to `N:\assets\candidates\<slot>\mesh\`.
Licences: Qwen-Image-2512 + Lightning LoRA (Apache-2.0), TRELLIS.2-4B (MIT), DINOv3 (DINOv3 License),
BiRefNet (MIT), Blender (GPL, the tool). No TRELLIS texture model, no nvdiffrast, no RMBG-2.0.

## What the goblin did, and what went wrong since

| Step | Goblin (2026-10-09) | Human bases (2026-10-17, rejected) |
|---|---|---|
| Concept | Qwen-Image-2512 + Lightning LoRA, 8 steps, cfg 1, 1328 px; one figure, front, T-pose, plain white, a one-line prompt | base model, 40 steps, cfg 4, negative prompt; a long anatomical T-pose prompt with "untextured, vertex colours" style |
| Mesh | TRELLIS.2 1024_cascade, seed 42, fill_holes, CuMesh simplify to 4000 | the same TRELLIS step, simplified to 5000 and 20000 |
| Into cleanup | 3 loose parts (3815 + 18 + 14 faces) | 124 to 1389 loose parts, never cleaned |
| Cleanup | loose parts deleted, faces round 5 single-point joins cut out, holes filled and triangulated, normals out: one watertight mesh, 3780 tris, 1.2 m, shape unchanged; no voxel or quad remesh | none |
| Colour | 5 (later 7) flat part materials assigned per face by height and facing, stray triangles fixed by hand; later baked to a 2048 sheet and painted by hand (Jeff) | TRELLIS.2's texture model, or a front-view vertex projection: soft, blurry colour on a faceted mesh |

The TRELLIS step was the same both times. The differences are the concept going in and everything after. The
humans' sampler settings (base model, cfg 4) are the ones step 2 below now uses; what failed there was the long
anatomical prompt, no cleanup and the TRELLIS texture, not the sampler.

## The recipe

1. **Pick the design** from a style sheet (front and three-quarter pairs, many prompts: `artgen.py concepts ... --view p<i>
   --template template_sheet.txt --base`). These are for choosing, not for meshing.
2. **Concept for meshing**: the style sheet's own look, base Qwen-Image-2512 at cfg 4, 40 steps, with the negative
   prompt and the faceted template (`--base --template template_sheet.txt`), cropped to one figure and padded square
   (the picked tile's front figure, or its three-quarter one if it reads better). Big flat facets, few thin parts.
   This replaces "the goblin's concept recipe" (accepted 2026-10-18). What decides the mesh is how faceted and simple
   the concept is, not the sampler (tested 2026-10-18 on orc p2 and kobold p1):
   - The picked style-sheet tile, cropped to its front figure (or the three-quarter one if it reads better) and padded
     square, meshed well: 1.6k to 5.4k loose slivers at 10k, cleaned to one watertight body.
   - The goblin's own concept recipe (`--view goblin --template template_goblin.txt`: Lightning LoRA, 8 steps, cfg 1,
     one figure, front, T-pose, white, a one-line prompt) drew these designs painterly rather than faceted, and their
     meshes were triangle soups (4k to 8.7k loose parts of 10k) that cleanup could not save. Use it only for simple
     subjects like the goblin's; keep chains, fur shards, spines and hair tufts out of the prompt either way.
3. **Mesh**: TRELLIS.2 1024_cascade, seed 42, through the gate (`heavy_job.py run art-gen trellis_mesh`) and
   `trellis.lock`; `shape_batch.py` (fill_holes, then CuMesh simplify to the slot's budget, scaled to the slot's height).
   Check the front faces +z (glTF): `shape_batch.fit` may turn a creature a quarter for a long tail; turn it back.
4. **Clean** (the goblin's hand cleanup, scripted): `blender -b --factory-startup -P goblin_clean.py -- <in.glb> <out.glb>`.
   Drops loose islands under 1% of the faces, cuts out single-point joins and edges on more than two faces, fills
   every hole (a fan where holes_fill can't), triangulates, normals out, and checks watertight. On the goblin's own
   4000f mesh it gives 3702 tris watertight (the hand cleanup: 3780). Hand fixes only where it reports something left.
5. **Colour**: `blender -b --factory-startup -P paint_bake.py -- <clean.glb> <stem> <front_cutout.png> [<tq_cutout.png>]
   [--parts N]`, using TRELLIS's own cutouts (`<stem>_cutout.png`, the views it read). Writes two versions:
   - `<stem>_flat.glb`: every face one flat part colour (the goblin's part materials). Parts are k-means of the
     faces' projected colours by hue (the concept's facet shading is dropped), blurred over neighbours so they come
     out as regions, shadows taken as unseen, small patches absorbed, the back taking the part of the face in front.
   - `<stem>_paint.glb`: a first paint, the concept views projected onto the UV sheet, each texel kept only where it
     belongs to its face's part (so borders stay on face edges, crisp), else the part colour.
   Jeff can hand-paint over the winner (`<stem>_paint.png` or `_flat.png`, one 1024 sheet, Smart UV Project).
6. **Sheet**: turntable renders of flat and paint side by side for Jeff; then to pc-character to rig.

Not in the recipe: voxel or quad remesh (Quadriflow refuses TRELLIS meshes and the goblin never needed it),
TRELLIS.2's texture model (soft colour), long anatomical prompts, two-figure sheets fed to TRELLIS uncropped.
