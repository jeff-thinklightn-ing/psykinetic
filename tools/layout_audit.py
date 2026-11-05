"""Layout sense's plan sheets (decision 806): reads a level's layout.png (cells
at even pixels, wall/door edges at odd ones) and its config, measures 806's
rules (sim/layout_sense.gd is the game's check; this draws them for people),
and draws an annotated plan per level. Reads the tree, writes only <out_dir>.

  python -B tools/layout_audit.py <out_dir> <name> <layout.png> <config.json> [ways] [template level.json]
  python -B tools/layout_audit.py --all <dump_dir> <out_dir>

--all audits every <level>_g<n>_layout.png tools/layout_dump.tscn wrote, its
config beside it, levels/<level>/level.json for its anchors, the way width
from WAYS. Rooms are found by shape, as layout_sense does without named rooms.
"""
import json, sys, os
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

LEGEND = {"void": "#000000", "stone": "#9a9a9a", "grass": "#4f9a3c", "dirt": "#8a6440", "water": "#2f6fd0",
          "ford": "#6fa8e0", "tall_grass": "#a8c850", "slope": "#c8b878", "rock": "#6e6a64", "fire": "#ff6a00",
          "wall": "#3c2a22", "door": "#c88a3c", "stair": "#e8d44a", "start": "#00ffff", "monster_imp": "#ff3030",
          "monster_brute": "#a00000", "monster_sneak": "#ff80a0", "crate": "#f0b070", "boulder": "#5a5a78",
          "cart": "#7a3cb4", "chest": "#8c4a1c", "seam": "#b87333", "torch": "#ffe000", "lantern": "#fff0b0",
          "lamp_cold": "#40e0d0", "link": "#ff00ff"}
LIGHTS = {"torch", "lantern", "lamp_cold"}
NOT_FLOOR = {"void", "wall", "door", "water", "rock", None}
LIGHT_DECOR = ("lamp", "torch", "sconce", "brazier", "candle", "lantern")


def hexrgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16) << 16) | (int(h[2:4], 16) << 8) | int(h[4:6], 16)


def load(layout_path, config):
    legend = dict(LEGEND)
    legend.update({k: v for k, v in (config.get("legend") or {}).items() if isinstance(v, str)})
    by = {hexrgb(v): k for k, v in legend.items()}
    img = np.array(Image.open(layout_path).convert("RGBA"))
    H, W = img.shape[:2]
    rgb = (img[..., 0].astype(np.int64) << 16) | (img[..., 1].astype(np.int64) << 8) | img[..., 2]
    mean = np.empty((H, W), dtype=object)
    for y in range(H):
        for x in range(W):
            mean[y, x] = by.get(int(rgb[y, x])) if img[y, x, 3] >= 128 else "void"
    return mean


def grid(mean):
    """The walkable pixel grid: cells, open edges between floor cells, and
    corners open on all sides. Doors are walkable and listed."""
    H, W = mean.shape
    walk = np.zeros((H, W), bool)
    door = np.zeros((H, W), bool)
    cell = lambda py, px: 0 <= py < H and 0 <= px < W and mean[py, px] not in NOT_FLOOR
    for py in range(0, H, 2):
        for px in range(0, W, 2):
            walk[py, px] = cell(py, px)
    for py in range(H):
        for px in range(W):
            if py % 2 == 0 and px % 2 == 1:
                a, b = (py, px - 1), (py, px + 1)
            elif py % 2 == 1 and px % 2 == 0:
                a, b = (py - 1, px), (py + 1, px)
            else:
                continue
            if cell(*a) and cell(*b):
                m = mean[py, px]
                if m == "door":
                    walk[py, px] = door[py, px] = True
                elif m != "wall":
                    walk[py, px] = True
    for py in range(1, H, 2):
        for px in range(1, W, 2):
            if all(0 <= py + dy < H and 0 <= px + dx < W and walk[py + dy, px + dx] and not door[py + dy, px + dx]
                   for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                walk[py, px] = True
    return walk, door


def things(mean, config):
    """[(px, py, kind, label)] in pixel coordinates: kind purpose | monster | light | dressing."""
    out = []
    H, W = mean.shape
    for py in range(0, H, 2):
        for px in range(0, W, 2):
            m = mean[py, px]
            if m is None or m in NOT_FLOOR or m in ("stone", "grass", "dirt", "stair", "slope", "fire", "ford", "tall_grass"):
                continue
            if m in LIGHTS:
                out.append((px, py, "light", m))
            elif m.startswith("monster_"):
                out.append((px, py, "monster", m[8:]))
            elif m == "start":
                out.append((px, py, "start", m))
            elif m == "link":
                out.append((px, py, "link", m))
            else:
                out.append((px, py, "purpose", m))
    at = lambda v: (int(v[0]) * 2, int(v[1]) * 2)
    for e in config.get("entities") or []:
        if isinstance(e, dict) and "at" in e:
            if e.get("named") or str(e.get("kind", "")).startswith("monster"):
                out.append((*at(e["at"]), "monster", str(e.get("named", "named"))))
            else:
                out.append((*at(e["at"]), "purpose", str(e.get("name") or e.get("art") or "entity")))
    for b in config.get("buildings") or []:
        if isinstance(b, dict) and "at" in b:
            out.append((*at(b["at"]), "purpose", str(b.get("slot", "building")).replace("building.", "")))
    for row in config.get("niches") or []:
        out.append((*at(row), "purpose", "niche"))
    for row in config.get("decor") or []:
        name = str(row[4]) if len(row) > 4 else "decor"
        out.append((*at(row), "light" if any(w in name for w in LIGHT_DECOR) else "dressing", name))
    places = config.get("places") or {}
    for k, p in (places.items() if isinstance(places, dict) else []):
        if isinstance(p, dict) and isinstance(p.get("at"), list) and len(p["at"]) == 2:
            out.append((*at(p["at"]), "purpose", "place:" + k))
    for l in config.get("links") or []:
        if isinstance(l, dict) and "at" in l:
            out.append((*at(l["at"]), "link", str(l.get("to_map"))))
    for s in config.get("starts") or []:
        out.append((*at(s), "start", "start"))
    return out


def thin(mask):
    """Zhang-Suen thinning."""
    m = mask.copy().astype(np.uint8)
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            p = np.pad(m, 1)
            P2, P3, P4, P5 = p[:-2, 1:-1], p[:-2, 2:], p[1:-1, 2:], p[2:, 2:]
            P6, P7, P8, P9 = p[2:, 1:-1], p[2:, :-2], p[1:-1, :-2], p[:-2, :-2]
            seq = [P2, P3, P4, P5, P6, P7, P8, P9, P2]
            B = sum(seq[:8])
            A = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                c = (P2 * P4 * P6 == 0) & (P4 * P6 * P8 == 0)
            else:
                c = (P2 * P4 * P8 == 0) & (P2 * P6 * P8 == 0)
            rm = (m == 1) & (B >= 2) & (B <= 6) & (A == 1) & c
            if rm.any():
                m[rm] = 0
                changed = True
    return m.astype(bool)


def bfs(walk, start):
    H, W = walk.shape
    dist = np.full((H, W), -1, np.int32)
    prev = {}
    q = deque([start])
    dist[start] = 0
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and walk[ny, nx] and dist[ny, nx] < 0:
                dist[ny, nx] = dist[y, x] + 1
                prev[(ny, nx)] = (y, x)
                q.append((ny, nx))
    return dist, prev


def audit(name, layout_path, config, cw, regen_config=None, pillared=False):
    mean = load(layout_path, config)
    walk, door = grid(mean)
    H, W = walk.shape
    k = 2 * (cw + 1) - 1
    # Pillars (rock islands of 3 x 3 cells or less inside floor) count as the
    # hall's floor for finding rooms.
    rl0, rn0 = ndi.label(~walk)
    pillars = np.zeros_like(walk)
    sizes = ndi.sum(np.ones_like(rl0), rl0, range(1, rn0 + 1))
    edge = set(np.unique(np.concatenate([rl0[0], rl0[-1], rl0[:, 0], rl0[:, -1]])).tolist())
    for i, sz in enumerate(sizes, 1):
        if pillared and sz <= 49 and i not in edge:
            pillars |= rl0 == i
    solid = walk | pillars
    opened = ndi.binary_opening(solid, structure=np.ones((k, k), bool)) & walk
    lab, n = ndi.label(opened)
    room = np.zeros_like(lab)
    rooms = []
    for i in range(1, n + 1):
        cells = int(((lab == i)[::2, ::2]).sum())
        if cells >= max(24, (cw + 1) ** 2 + 4):
            rooms.append(i)
    rid = {}
    for j, i in enumerate(rooms, 1):
        room[lab == i] = j
        rid[j] = i
    corr = walk & (room == 0)
    clab, cn = ndi.label(corr)
    # Slivers the opening left at a room's rounded corner join that room.
    for c in range(1, cn + 1):
        m = clab == c
        if int(m[::2, ::2].sum()) < 4:
            near = room[ndi.binary_dilation(m)]
            near = near[near > 0]
            if near.size:
                room[m] = np.bincount(near).argmax()
                clab[m] = 0
    corr = walk & (room == 0)
    clab, cn = ndi.label(corr)
    R = room.max()
    # Nodes: ("R", i) and ("C", j); edges by 4-adjacency.
    node = np.zeros((H, W), np.int64)
    node[room > 0] = room[room > 0]
    node[clab > 0] = 1000 + clab[clab > 0]
    adj = {}
    for (a, b) in ((node[:, :-1], node[:, 1:]), (node[:-1, :], node[1:, :])):
        mk = (a > 0) & (b > 0) & (a != b)
        for u, v in set(zip(a[mk].tolist(), b[mk].tolist())):
            adj.setdefault(u, set()).add(v)
            adj.setdefault(v, set()).add(u)
    th = things(mean, config)
    content = {}
    for (px, py, kind, label) in th:
        if 0 <= py < H and 0 <= px < W:
            u = node[py, px]
            if u == 0:  # On a wall (a niche, a wall decor): the floor beside it.
                for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (0, 2), (0, -2), (2, 0), (-2, 0)):
                    if 0 <= py + dy < H and 0 <= px + dx < W and node[py + dy, px + dx]:
                        u = node[py + dy, px + dx]
                        break
            if u:
                content.setdefault(u, []).append((kind, label))
    faults = []

    def centre(mask):
        ys, xs = np.nonzero(mask)
        return (int(xs.mean()), int(ys.mean()))

    def has(u, kinds):
        return any(k in kinds for k, _ in content.get(u, []))

    # Rule: a room has a purpose (something besides monsters, lights, dressing).
    purposeless = []
    for r in range(1, R + 1):
        if not has(r, ("purpose", "link", "start")):
            purposeless.append(r)
            what = "monsters only" if has(r, ("monster",)) else "empty"
            faults.append(("purpose", centre(room == r), "room with no purpose (%s)" % what))
    # Rule: a corridor never wraps a room. (a) a corridor ring round a room;
    # (b) a corridor running along two or more of a room's sides.
    wraps = 0
    for c in range(1, cn + 1):
        m = clab == c
        filled = ndi.binary_fill_holes(m)
        hole = filled & ~m
        inside = set(np.unique(room[hole]).tolist()) - {0}
        for r in inside:
            wraps += 1
            faults.append(("wrap", centre(room == r), "corridor rings this room"))
    for r in range(1, R + 1):
        ys, xs = np.nonzero(room == r)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        for c in range(1, cn + 1):
            m = clab == c
            sides = 0
            band = 4
            for sl, length in (((slice(max(0, y0 - band), y0), slice(x0, x1 + 1)), x1 - x0 + 1),
                               ((slice(y1 + 1, y1 + 1 + band), slice(x0, x1 + 1)), x1 - x0 + 1),
                               ((slice(y0, y1 + 1), slice(max(0, x0 - band), x0)), y1 - y0 + 1),
                               ((slice(y0, y1 + 1), slice(x1 + 1, x1 + 1 + band)), y1 - y0 + 1)):
                cover = m[sl].any(axis=0 if sl[0].start is not None and sl[1].stop - sl[1].start == length else 1)
                if cover.sum() >= 0.6 * length and length >= 8:
                    sides += 1
            if sides >= 2 and not any(f[0] == "wrap" and f[1] == centre(room == r) for f in faults):
                wraps += 1
                faults.append(("wrap", centre(room == r), "corridor runs along %d sides" % sides))
    # Rule: a dead end only when it holds something. Skeleton tips of the
    # corridors, not at a room, a link or a start.
    stub_comp = set()
    for c in range(1, cn + 1):
        u = 1000 + c
        if len(adj.get(u, ())) <= 1:
            m = clab == c
            stub_comp.add(c)
            x, y = centre(m)
            if has(u, ("purpose", "link", "start")):
                faults.append(("deadend_ok", (x, y), "stub holding something"))
            elif has(u, ("monster",)):
                faults.append(("deadend_mon", (x, y), "stub holding only a monster"))
            else:
                faults.append(("deadend", (x, y), "stub off a room, holding nothing"))
    sk = thin(corr)
    nb = ndi.convolve(sk.astype(np.uint8), np.ones((3, 3), np.uint8), mode="constant") - sk
    tips = np.argwhere(sk & (nb == 1))
    near_room = ndi.binary_dilation(room > 0, iterations=6)
    dead = []
    for (y, x) in tips:
        if near_room[y, x] or clab[y, x] in stub_comp:
            continue
        # The spur's own floor: corridor cells within 6 pixels of the tip.
        yy, xx = np.ogrid[:H, :W]
        zone = corr & ((yy - y) ** 2 + (xx - x) ** 2 <= 49)
        held = [lab_ for (px, py, kind, lab_) in th if zone[min(py, H - 1), min(px, W - 1)] and kind in ("purpose", "link", "start")]
        if any(abs(y - d[0]) <= 4 and abs(x - d[1]) <= 4 for d in dead):
            continue
        dead.append((y, x))
        mons = [lab_ for (px, py, kind, lab_) in th if zone[min(py, H - 1), min(px, W - 1)] and kind == "monster"]
        if held:
            faults.append(("deadend_ok", (int(x), int(y)), "dead end holding " + held[0]))
        elif mons:
            faults.append(("deadend_mon", (int(x), int(y)), "dead end holding only a monster (%s)" % mons[0]))
        else:
            faults.append(("deadend", (int(x), int(y)), "dead end holding nothing"))
    # Rule: every door leads to a room or a through-route.
    dl, dn = ndi.label(door)
    stub_doors = 0
    for d in range(1, dn + 1):
        ys, xs = np.nonzero(dl == d)
        sides = set()
        for y, x in zip(ys, xs):
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and node[ny, nx] and not door[ny, nx]:
                    sides.add(int(node[ny, nx]))
        for u in sides:
            if u >= 1000 and len(adj.get(u, ())) <= 1 and not has(u, ("purpose", "link", "start")):
                stub_doors += 1
                faults.append(("door", (int(xs.mean()), int(ys.mean())), "door to a stub"))
            if u < 1000 and len(adj.get(u, ())) <= 1 and not has(u, ("purpose", "link", "start")):
                stub_doors += 1
                faults.append(("door", (int(xs.mean()), int(ys.mean())), "door to an empty closet"))
    # Loops: rock islands enclosed by floor. A pillar inside one room is not one.
    rock = ~walk
    rl, rn = ndi.label(rock)
    border = set(np.unique(np.concatenate([rl[0], rl[-1], rl[:, 0], rl[:, -1]])).tolist())
    loops = {"through_rooms": 0, "corridor_only": 0}
    for i in range(1, rn + 1):
        if i in border:
            continue
        m = rl == i
        if int(m.sum()) < 9 or pillars[m].all():
            continue  # A wall stub between doors, a pillar.
        ring = ndi.binary_dilation(m, iterations=2) & walk
        rs = set(np.unique(room[ring]).tolist()) - {0}
        if len(rs) == 1 and not (clab[ring] > 0).any():
            continue  # Pillars in a hall.
        if len(rs) >= 2:
            loops["through_rooms"] += 1
        else:
            loops["corridor_only"] += 1
            faults.append(("loop", centre(m), "loop through corridors only, round rock"))
    # The spine: entrance to heart.
    starts = [(py, px) for (px, py, kind, _) in th if kind == "start"]
    start = starts[0] if starts else tuple(np.argwhere(walk)[0])
    dist, prev = bfs(walk, start)
    heart = None
    anchors = (regen_config or {}).get("anchors") or []
    best = -1
    for a in anchors:
        x, y, w, h = a["rect"]
        cy, cx = (y + h // 2) * 2, (x + w // 2) * 2
        sub = dist[y * 2:(y + h) * 2, x * 2:(x + w) * 2]
        if (sub >= 0).any() and sub.max() > best:
            best = int(sub.max())
            pos = np.argwhere(sub == sub.max())[0]
            heart = (y * 2 + pos[0], x * 2 + pos[1], a["name"])
    if heart is None:
        pos = np.unravel_index(np.argmax(dist), dist.shape)
        heart = (pos[0], pos[1], "farthest floor")
    path = []
    cur = (heart[0], heart[1])
    while cur in prev:
        path.append(cur)
        cur = prev[cur]
    path.append(cur)
    spine_nodes = set(int(node[p]) for p in path if node[p])
    spine_rooms = sorted(u for u in spine_nodes if u < 1000)
    # Room graph: rooms joined directly or through one corridor.
    rg = {r: set() for r in range(1, R + 1)}
    for u, vs in adj.items():
        if u < 1000:
            for v in vs:
                if v < 1000:
                    rg[u].add(v)
                else:
                    for w2 in adj.get(v, ()):
                        if w2 < 1000 and w2 != u:
                            rg[u].add(w2)
    depth = {r: None for r in rg}
    q = deque()
    for r in spine_rooms:
        depth[r] = 0
        q.append(r)
    # Corridor nodes on the spine count as spine too.
    for c in (u for u in spine_nodes if u >= 1000):
        for r in adj.get(c, ()):
            if r < 1000 and depth.get(r) is None:
                depth[r] = 1
                q.append(r)
    while q:
        r = q.popleft()
        for v in rg[r]:
            if depth[v] is None:
                depth[v] = depth[r] + 1
                q.append(v)
    straight = ((heart[0] - start[0]) ** 2 + (heart[1] - start[1]) ** 2) ** 0.5 / 2
    plen = (len(path) - 1) / 2
    off = [r for r, d in depth.items() if d is None or d > 1]
    off_mask = np.isin(room, off) if off else np.zeros_like(walk)
    cells_floor = int(walk[::2, ::2].sum())
    corr_cells = int(corr[::2, ::2].sum())
    metrics = {
        "level": name, "floor_cells": cells_floor, "rooms": int(R), "corridor_share": round(corr_cells / max(1, cells_floor), 2),
        "rooms_without_purpose": len(purposeless), "corridor_wraps": wraps,
        "dead_ends_empty": sum(1 for f in faults if f[0] == "deadend"),
        "dead_ends_holding": sum(1 for f in faults if f[0] == "deadend_ok"),
        "dead_ends_monster_only": sum(1 for f in faults if f[0] == "deadend_mon"),
        "doors": int(dn), "doors_to_stubs": stub_doors,
        "loops_through_rooms": loops["through_rooms"], "loops_corridor_only": loops["corridor_only"],
        "spine_heart": heart[2], "spine_length": round(plen, 1), "spine_straight": round(straight, 1),
        "spine_detour": round(plen / max(1.0, straight), 2), "rooms_on_spine": len(spine_rooms),
        "rooms_more_than_one_off_spine": len(off),
    }
    return dict(mean=mean, walk=walk, door=door, room=room, corr=corr, th=th, faults=faults, path=path, off=off_mask,
                start=start, heart=heart, metrics=metrics)


COLOURS = {"purpose": (230, 60, 60), "wrap": (255, 140, 0), "deadend": (220, 0, 220), "deadend_ok": (90, 170, 90), "deadend_mon": (200, 90, 160),
           "door": (255, 0, 0), "loop": (0, 170, 220), "offspine": (150, 120, 255)}
SHORT = {"purpose": "P", "wrap": "W", "deadend": "D", "deadend_ok": "d", "deadend_mon": "M", "door": "X", "loop": "L", "offspine": "S"}


def draw(a, out_png, title):
    S = 5
    walk, room, corr, door = a["walk"], a["room"], a["corr"], a["door"]
    H, W = walk.shape
    base = np.zeros((H, W, 3), np.uint8)
    base[:] = (28, 26, 24)
    base[corr] = (120, 120, 120)
    base[room > 0] = (214, 198, 160)
    base[a["off"]] = (196, 184, 224)
    base[door] = (200, 138, 60)
    img = Image.fromarray(base).resize((W * S, H * S), Image.NEAREST)
    pad = 360
    listed = len([f for f in a["faults"] if f[0] != "deadend_ok"])
    canvas = Image.new("RGB", (W * S + pad, max(H * S, 340 + 15 * listed) + 50), (245, 243, 238))
    canvas.paste(img, (0, 40))
    d = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("arial.ttf", 15)
        small = ImageFont.truetype("arial.ttf", 12)
        big = ImageFont.truetype("arialbd.ttf", 18)
    except OSError:
        font = small = big = ImageFont.load_default()
    d.text((8, 10), title, fill=(20, 20, 20), font=big)
    # The spine.
    pts = [(x * S + S // 2, y * S + S // 2 + 40) for (y, x) in a["path"]]
    if len(pts) > 1:
        d.line(pts, fill=(40, 90, 230), width=3)
    for (px, py, kind, label) in a["th"]:
        c = {"purpose": (40, 40, 40), "monster": (190, 30, 30), "light": (250, 220, 40), "dressing": (150, 130, 100),
             "link": (255, 0, 255), "start": (0, 220, 220)}[kind]
        r = 3 if kind in ("light", "dressing") else 4
        cx, cy = px * S + S // 2, py * S + S // 2 + 40
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c)
    numbered = [f for f in a["faults"] if f[0] != "deadend_ok"]
    for i, (kind, (x, y), what) in enumerate(numbered, 1):
        cx, cy = x * S + S // 2, y * S + S // 2 + 40
        c = COLOURS[kind]
        d.ellipse((cx - 11, cy - 11, cx + 11, cy + 11), outline=c, width=3)
        d.text((cx + 12, cy - 9), "%s%d" % (SHORT[kind], i), fill=c, font=font)
    for (kind, (x, y), what) in a["faults"]:
        if kind == "deadend_ok":
            cx, cy = x * S + S // 2, y * S + S // 2 + 40
            d.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), outline=COLOURS[kind], width=2)
    # Side panel.
    X = W * S + 14
    y = 44
    m = a["metrics"]
    lines = [
        "floor %d cells, %d rooms, corridors %d%%" % (m["floor_cells"], m["rooms"], m["corridor_share"] * 100),
        "P rooms with no purpose: %d" % m["rooms_without_purpose"],
        "W corridors wrapping a room: %d" % m["corridor_wraps"],
        "X doors to a stub or empty closet: %d of %d" % (m["doors_to_stubs"], m["doors"]),
        "D dead ends holding nothing: %d" % m["dead_ends_empty"],
        "M dead ends holding only a monster: %d" % m["dead_ends_monster_only"],
        "d dead ends holding something (green): %d" % m["dead_ends_holding"],
        "L loops through corridors only: %d" % m["loops_corridor_only"],
        "  loops through rooms: %d" % m["loops_through_rooms"],
        "rooms 2+ steps off the spine (lilac): %d" % m["rooms_more_than_one_off_spine"],
        "spine to %s: %.0f cells walked," % (m["spine_heart"], m["spine_length"]),
        "  %.0f straight (x%.1f)" % (m["spine_straight"], m["spine_detour"]),
        "", "key: tan room, grey corridor, orange door,",
        "blue line spine (start to heart),", "black dot purpose, red monster,",
        "yellow light, brown dressing,", "cyan start, magenta link",
    ]
    for line in lines:
        d.text((X, y), line, fill=(20, 20, 20), font=small)
        y += 17
    y += 8
    for i, (kind, _, what) in enumerate(numbered, 1):
        if y > canvas.height - 18:
            d.text((X, y), "... %d more" % (len(numbered) - i + 1), fill=(90, 90, 90), font=small)
            break
        d.text((X, y), "%s%d %s" % (SHORT[kind], i, what), fill=COLOURS[kind], font=small)
        y += 15
    canvas.save(out_png)


WAYS = {"barrow": 3, "barrow_deep": 3, "castle_halls": 5, "hollowfell": 4}


def run(out, name, layout, config_path, cw, template):
    config = json.load(open(config_path, encoding="utf-8"))
    regen = json.load(open(template, encoding="utf-8")).get("regenerate") if template else config.get("regenerate")
    a = audit(name, layout, config, cw, regen, pillared=(regen or {}).get("style") == "dwarven")
    os.makedirs(out, exist_ok=True)
    draw(a, os.path.join(out, name + ".png"), name)
    json.dump(a["metrics"], open(os.path.join(out, name + ".json"), "w"), indent=1)
    print(json.dumps(a["metrics"]))


if __name__ == "__main__" and sys.argv[1] == "--all":
    import glob, re
    dump, out = sys.argv[2:4]
    for layout in sorted(glob.glob(os.path.join(dump, "*_g*_layout.png"))):
        stem = os.path.basename(layout)[:-len("_layout.png")]
        level = re.sub(r"_g\d+$", "", stem)
        run(out, stem, layout, os.path.join(dump, stem + "_config.json"), WAYS.get(level, 3),
            os.path.join("levels", level, "level.json"))
elif __name__ == "__main__":
    out, name, layout, config_path = sys.argv[1:5]
    cw = int(sys.argv[5]) if len(sys.argv) > 5 else 3
    template = sys.argv[6] if len(sys.argv) > 6 else None
    config = json.load(open(config_path, encoding="utf-8"))
    regen = json.load(open(template, encoding="utf-8")).get("regenerate") if template else config.get("regenerate")
    a = audit(name, layout, config, cw, regen, pillared=(regen or {}).get("style") == "dwarven")
    os.makedirs(out, exist_ok=True)
    draw(a, os.path.join(out, name + ".png"), name)
    json.dump(a["metrics"], open(os.path.join(out, name + ".json"), "w"), indent=1)
    print(json.dumps(a["metrics"]))
