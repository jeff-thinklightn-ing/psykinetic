"""Grow a pine stand year by year and bake each tree's shape (decision 467).

Jeff (2026-10-17): "the idea for the trees was to build a sim outside the
game to model how trees look in a forest.. not necessarily in game." An
offline tool: seeded, the same output for the same input. It reads where
trees may stand (a level's walkable cells, less its path and clearings, or a
stand-in), grows a stand from a crop of seedlings for --years, and writes
each standing tree's shape to trees.json for the client to draw.

The model, on 1 m cells (the game's scale, so pines top out near 13 m):
- A light grid of 0.5 m voxels, 14 m high. Every live branch lays needles
  (leaf) along its outer part into the voxels it passes. The light at a
  voxel is the sky seen through the leaf above it, overhead and along four
  45-degree slants, each step through a voxel passing exp(-K * leaf).
  Crowns shade what is below them; the map wraps, as the forest goes on
  past its edge.
- Each year a tree's leader grows by the light at its top, slower as it
  nears HMAX; each WHORL_GAP of new height starts a whorl of 4 to 6 buds.
- A branch lengthens by the light at its tip, up to LMAX, and stops where
  another tree's needles fill the voxel ahead. A branch whose middle sees
  under DIE_LIGHT for DIE_YEARS years dies; a dead branch drops after
  DROP_YEARS. So crowns lift as they close, and trunks go bare below.
- A tree's vigour is the light its leaf catches over the leaf it has. Under
  VIG_MIN (or under TOP_MIN at its top) it has a bad year; WEAK_YEARS of
  them in a row and it dies, stands as a snag for SNAG_YEARS, then falls.
- Seedlings come up each year where the ground's light passes
  RECRUIT_LIGHT, once trees are old enough to bear cones.

Nothing is placed or tuned by hand afterwards: what the run grew is what
is written. Usage:
  python tools/forest_grow.py --level levels/forest
  python tools/forest_grow.py --standin 96 --out <folder> [--snapshots 20,50,100]
"""

import argparse
import json
import math
import os
import time

import numpy as np

VOXEL = 0.5
HIGH = 14.0
# Leaf: per metre of branch, laid along its outer part; light falls by
# exp(-K * leaf) through a voxel.
LEAF = 1.0
K = 0.9
SKY = [((0, 0), 0.4), ((1, 0), 0.15), ((-1, 0), 0.15), ((0, 1), 0.15), ((0, -1), 0.15)]
# Growth, per year in full light.
HEIGHT_RATE = 0.38
HMAX = 13.0
BRANCH_RATE = 0.13
LMAX = 2.4
DROOP = 0.22
WHORL_GAP = 0.42
# Dying.
DIE_LIGHT = 0.14
DIE_YEARS = 3
DROP_YEARS = 6
VIG_MIN = 0.16
# Upkeep: a tree whose leaf catches less light in a year than UPKEEP times
# its height to the UPKEEP_POWER (its wood to keep alive) has a bad year. Each tree grows at its own pace
# (a lognormal factor of spread PACE), as seedlings do.
UPKEEP = 0.8
UPKEEP_POWER = 1.5
PACE = 0.2
TOP_MIN = 0.12
WEAK_YEARS = 5
SNAG_YEARS = (10, 25)
CROWD = 0.25
# Seeding: the first crop, and seedlings after.
SEED_DENSITY = 0.6
CONE_AGE = 15
RECRUIT = 0.004
RECRUIT_LIGHT = 0.3
# A tree at least this tall stands on its cell as a trunk (void).
TRUNK_HEIGHT = 3.0


class Stand:
    def __init__(self, allowed, seed):
        self.allowed = allowed  # [w, h] bool: where a tree may stand
        self.w, self.h = allowed.shape
        self.rng = np.random.default_rng(seed)
        self.nx = int(self.w / VOXEL)
        self.nz = int(self.h / VOXEL)
        self.ny = int(HIGH / VOXEL)
        self.year = 0
        # Trees, as columns.
        self.tx = np.zeros(0)
        self.tz = np.zeros(0)
        self.th = np.zeros(0)
        self.tr = np.zeros(0)
        self.age = np.zeros(0, dtype=int)
        self.alive = np.zeros(0, dtype=bool)
        self.weak = np.zeros(0, dtype=int)
        self.snag = np.zeros(0, dtype=int)
        self.last_whorl = np.zeros(0)
        self.lean = np.zeros((0, 2))
        self.pace = np.zeros(0)
        # Branches, as columns.
        self.bt = np.zeros(0, dtype=int)
        self.by = np.zeros(0)
        self.ba = np.zeros(0)
        self.bl = np.zeros(0)
        self.blive = np.zeros(0, dtype=bool)
        self.blow = np.zeros(0, dtype=int)
        self.bdead = np.zeros(0, dtype=int)
        self.light = np.ones((self.ny, self.nx, self.nz))
        self.fallen = 0
        cells = np.argwhere(allowed)
        counts = self.rng.poisson(SEED_DENSITY, len(cells))
        at = np.repeat(cells, counts, axis=0) + self.rng.random((counts.sum(), 2))
        self._add_trees(at, self.rng.uniform(0.1, 0.4, len(at)))

    def _add_trees(self, at, height):
        n = len(at)
        self.tx = np.concatenate([self.tx, at[:, 0]])
        self.tz = np.concatenate([self.tz, at[:, 1]])
        self.th = np.concatenate([self.th, height])
        self.tr = np.concatenate([self.tr, np.full(n, 0.01)])
        self.age = np.concatenate([self.age, np.zeros(n, dtype=int)])
        self.alive = np.concatenate([self.alive, np.ones(n, dtype=bool)])
        self.weak = np.concatenate([self.weak, np.zeros(n, dtype=int)])
        self.snag = np.concatenate([self.snag, np.zeros(n, dtype=int)])
        self.last_whorl = np.concatenate([self.last_whorl, height])
        self.lean = np.concatenate([self.lean, self.rng.uniform(-0.02, 0.02, (n, 2))])
        self.pace = np.concatenate([self.pace, self.rng.lognormal(0.0, PACE, n)])

    def _voxel(self, x, y, z):
        ix = np.floor(x / VOXEL).astype(int) % self.nx
        iz = np.floor(z / VOXEL).astype(int) % self.nz
        iy = np.clip(np.floor(y / VOXEL).astype(int), 0, self.ny - 1)
        return iy, ix, iz

    def _tips(self, f):
        """Points a fraction f along each branch."""
        x = self.tx[self.bt] + self.lean[self.bt, 0] * self.by + np.cos(self.ba) * self.bl * f
        z = self.tz[self.bt] + self.lean[self.bt, 1] * self.by + np.sin(self.ba) * self.bl * f
        y = self.by - DROOP * self.bl * f
        return x, y, z

    def _shade(self):
        """Lay the live branches' leaf into the grid and work out the light."""
        leaf = np.zeros((self.ny, self.nx, self.nz))
        owner = np.full((self.ny, self.nx, self.nz), -1, dtype=int)
        live = self.blive & self.alive[self.bt]
        for f in (0.4, 0.7, 1.0):
            x, y, z = self._tips(f)
            iy, ix, iz = self._voxel(x[live], y[live], z[live])
            np.add.at(leaf, (iy, ix, iz), LEAF * self.bl[live] / 3.0)
            owner[iy, ix, iz] = self.bt[live]
        # The leader's tuft.
        tall = self.alive & (self.th > 0.6)
        iy, ix, iz = self._voxel(self.tx[tall], self.th[tall] - 0.3, self.tz[tall])
        np.add.at(leaf, (iy, ix, iz), 0.15)
        owner[iy, ix, iz] = np.nonzero(tall)[0]
        through = np.exp(-K * leaf)
        light = np.zeros_like(leaf)
        for (sx, sz), weight in SKY:
            seen = np.ones((self.nx, self.nz))
            for y in range(self.ny - 1, -1, -1):
                light[y] += weight * seen
                seen = np.roll(seen * through[y], (sx, sz), axis=(0, 1))
        self.leaf, self.owner, self.light = leaf, owner, light

    def step(self):
        self._shade()
        n = len(self.tx)
        # Branches: light at the middle and the tip.
        x, y, z = self._tips(0.6)
        mid = self.light[self._voxel(x, y, z)]
        x, y, z = self._tips(1.0)
        tip = self.light[self._voxel(x, y, z)]
        ahead = self._voxel(x + np.cos(self.ba) * 0.3, y - 0.05, z + np.sin(self.ba) * 0.3)
        crowded = (self.owner[ahead] != self.bt) & (self.owner[ahead] >= 0) & (self.leaf[ahead] > CROWD)
        live = self.blive & self.alive[self.bt]
        # Vigour: the light the leaf catches over the leaf.
        leaf = np.where(live, self.bl, 0.0)
        caught = np.bincount(self.bt, weights=leaf * mid, minlength=n)
        held = np.bincount(self.bt, weights=leaf, minlength=n)
        iy, ix, iz = self._voxel(self.tx, self.th, self.tz)
        top = self.light[iy, ix, iz]
        vigour = np.where(held > 0.05, caught / np.maximum(held, 1e-6), top)
        grow = live & ~crowded
        self.bl = np.where(grow, np.minimum(self.bl + BRANCH_RATE * tip * np.minimum(vigour[self.bt] * 2.0, 1.0), LMAX), self.bl)
        self.blow = np.where(live & (mid < DIE_LIGHT), self.blow + 1, np.where(live, 0, self.blow))
        dying = live & (self.blow >= DIE_YEARS)
        self.blive = self.blive & ~dying
        self.bdead = np.where(~self.blive | ~self.alive[self.bt], self.bdead + 1, 0)
        # Trees: the leader, the trunk, a new whorl.
        a = self.alive
        dh = HEIGHT_RATE * self.pace * np.power(top, 0.8) * np.clip(1.0 - self.th / HMAX, 0.0, 1.0)
        self.th = np.where(a, self.th + dh, self.th)
        self.tr = np.where(a, self.tr + 0.0005 + 0.0005 * np.sqrt(caught), self.tr)
        self.age = self.age + 1
        bud = np.nonzero(a & (self.th - self.last_whorl >= WHORL_GAP) & (self.th > 0.6))[0]
        if len(bud):
            arms = self.rng.integers(4, 7, len(bud))
            trees = np.repeat(bud, arms)
            spin = np.repeat(self.rng.random(len(bud)) * math.tau, arms)
            index = np.concatenate([np.arange(k) for k in arms])
            angle = spin + math.tau * index / np.repeat(arms, arms) + self.rng.uniform(-0.25, 0.25, len(trees))
            self._add_branches(trees, self.th[trees] - 0.15, angle)
            self.last_whorl[bud] = self.th[bud]
        # A bad year, and death after WEAK_YEARS of them.
        bad = a & ((vigour < VIG_MIN) | (top < TOP_MIN) | ((self.th > 1.0) & (LEAF * caught < UPKEEP * np.power(self.th, UPKEEP_POWER))))
        self.weak = np.where(bad, self.weak + 1, np.where(a, 0, self.weak))
        dies = a & (self.weak >= WEAK_YEARS)
        self.alive = a & ~dies
        self.snag = np.where(dies, self.rng.integers(*SNAG_YEARS, n), np.where(~self.alive, self.snag - 1, self.snag))
        # Seedlings, where the ground is light enough and cones fall.
        if (self.alive & (self.age >= CONE_AGE)).any():
            count = self.rng.poisson(RECRUIT * self.allowed.sum())
            at = self.rng.random((count, 2)) * [self.w, self.h]
            cell = at.astype(int)
            ok = self.allowed[cell[:, 0], cell[:, 1]]
            iy, ix, iz = self._voxel(at[:, 0], np.full(count, 0.6), at[:, 1])
            ok &= self.light[iy, ix, iz] > RECRUIT_LIGHT
            if ok.any():
                self._add_trees(at[ok], np.full(ok.sum(), 0.15))
        self._prune()
        self.year += 1

    def _add_branches(self, trees, y, angle):
        n = len(trees)
        self.bt = np.concatenate([self.bt, trees])
        self.by = np.concatenate([self.by, y])
        self.ba = np.concatenate([self.ba, angle])
        self.bl = np.concatenate([self.bl, np.full(n, 0.12)])
        self.blive = np.concatenate([self.blive, np.ones(n, dtype=bool)])
        self.blow = np.concatenate([self.blow, np.zeros(n, dtype=int)])
        self.bdead = np.concatenate([self.bdead, np.zeros(n, dtype=int)])

    def _prune(self):
        """Dropped branches and fallen snags (and small dead trees) go."""
        fallen = ~self.alive & ((self.snag <= 0) | (self.th < 1.0))
        self.fallen += int((fallen & (self.th >= TRUNK_HEIGHT)).sum())
        keep_tree = ~fallen
        keep = keep_tree[self.bt] & (self.blive | (self.bdead <= DROP_YEARS))
        renumber = np.cumsum(keep_tree) - 1
        for name in ("bt", "by", "ba", "bl", "blive", "blow", "bdead"):
            setattr(self, name, getattr(self, name)[keep])
        self.bt = renumber[self.bt]
        for name in ("tx", "tz", "th", "tr", "age", "alive", "weak", "snag", "last_whorl", "lean", "pace"):
            setattr(self, name, getattr(self, name)[keep_tree])

    def stats(self):
        a = self.alive
        trunks = (self.th >= TRUNK_HEIGHT)
        live_trunks = a & trunks
        out = {
            "year": self.year,
            "live": int(a.sum()),
            "trunks": int(live_trunks.sum()),
            "snags": int((~a & trunks).sum()),
            "under_3m": int((a & ~trunks).sum()),
            "fallen": self.fallen,
            "tallest": round(float(self.th[a].max()) if a.any() else 0.0, 1),
            "mean_trunk_height": round(float(self.th[live_trunks].mean()) if live_trunks.any() else 0.0, 1),
        }
        if live_trunks.sum() > 1:
            pts = np.stack([self.tx[live_trunks], self.tz[live_trunks]], 1)
            near = []
            for p in pts:
                d = np.hypot(*(pts - p).T)
                d = d[d > 0]
                near.append(d.min())
            out["trunk_spacing"] = round(float(np.mean(near)), 2)
            # The lowest live branch on each live trunk: where its crown starts.
            live = self.blive & self.alive[self.bt] & live_trunks[self.bt]
            base = np.full(len(self.tx), np.inf)
            np.minimum.at(base, self.bt[live], self.by[live])
            out["crown_base"] = round(float(np.mean(base[live_trunks & np.isfinite(base)])), 1)
        ground = self.light[1][self.allowed.repeat(2, 0).repeat(2, 1)]
        out["ground_dark"] = round(float((ground < 0.3).mean()), 2)
        return out

    def trees(self):
        """Every tree at least TRUNK_HEIGHT tall, and the undergrowth, for the drawer."""
        out = []
        order = np.argsort(self.bt, kind="stable")
        starts = np.searchsorted(self.bt[order], np.arange(len(self.tx)))
        ends = np.searchsorted(self.bt[order], np.arange(len(self.tx)), side="right")
        for t in range(len(self.tx)):
            if not self.alive[t] and self.th[t] < TRUNK_HEIGHT:
                continue
            whorls = {}
            dead = []
            for k in order[starts[t]:ends[t]]:
                y = round(float(self.by[k]), 2)
                branch = [round(float(self.ba[k]) % math.tau, 2), round(float(self.bl[k]), 2)]
                if self.blive[k] and self.alive[t]:
                    whorls.setdefault(y, []).append(branch)
                else:
                    dead.append([y] + branch)
            out.append({
                "at": [round(float(self.tx[t]), 2), round(float(self.tz[t]), 2)],
                "height": round(float(self.th[t]), 2),
                "radius": round(float(self.tr[t]), 3),
                "lean": [round(float(v), 3) for v in self.lean[t]],
                "age": int(self.age[t]),
                "state": "live" if self.alive[t] else "snag",
                "whorls": [{"y": y, "branches": b} for y, b in sorted(whorls.items())],
                "dead": dead,
            })
        return out


def standin(size, seed):
    """A stand-in for the forest level: a winding path through four
    clearings, kept clear, as the forest prototype lays it."""
    rng = np.random.default_rng(seed)
    keep = np.zeros((size, size), dtype=bool)
    path = np.zeros((size, size), dtype=bool)
    count = max(4, size // 24)
    points = [(0.0, size * 0.5)]
    clearings = []
    for i in range(count):
        x = (i + 0.6) * size / (count + 0.2)
        y = size * 0.5 + rng.uniform(-0.28, 0.28) * size
        clearings.append({"centre": [round(x, 1), round(y, 1)], "radius": round(float(rng.uniform(3.0, 5.0)), 1)})
        points.append((x, y))
    points.append((size - 1.0, size * 0.5))
    gx, gy = np.meshgrid(np.arange(size) + 0.5, np.arange(size) + 0.5, indexing="ij")
    for i in range(len(points) - 1):
        a, b = np.array(points[i]), np.array(points[i + 1])
        side = np.array([-(b - a)[1], (b - a)[0]]) / np.linalg.norm(b - a)
        for t in np.linspace(0.0, 1.0, int(np.linalg.norm(b - a) * 2) + 1):
            at = a + (b - a) * t + side * math.sin(t * math.pi * 2 + i) * 2.5 * math.sin(t * math.pi)
            d = np.hypot(gx - at[0], gy - at[1])
            path |= d <= 1.1
            keep |= d <= 2.2
    for c in clearings:
        d = np.hypot(gx - c["centre"][0], gy - c["centre"][1])
        keep |= d <= c["radius"] + 0.9
    keep[0, :] = keep[-1, :] = keep[:, 0] = keep[:, -1] = True
    return ~keep, path, clearings


def from_level(folder):
    """Where trees may stand in a level: grass or dirt cells off its path
    (dirt is the path) and outside its clearings."""
    from PIL import Image
    config = json.load(open(os.path.join(folder, "level.json"), encoding="utf-8"))
    image = Image.open(os.path.join(folder, "layout.png")).convert("RGBA")
    size = (image.width + 1) // 2
    pixels = np.array(image)
    cells = pixels[::2, ::2].transpose(1, 0, 2)
    grass = np.all(cells[:, :, :3] == [0x4f, 0x9a, 0x3c], axis=2) & (cells[:, :, 3] > 127)
    dirt = np.all(cells[:, :, :3] == [0x8a, 0x64, 0x40], axis=2) & (cells[:, :, 3] > 127)
    allowed = grass.copy()
    gx, gy = np.meshgrid(np.arange(size) + 0.5, np.arange(size) + 0.5, indexing="ij")
    for c in config.get("clearings", []):
        allowed &= np.hypot(gx - c["centre"][0], gy - c["centre"][1]) > c["radius"] + 1.0
    return allowed, dirt, config.get("clearings", [])


def reach(walkable, start):
    """Cells reachable from start, 4-connected."""
    seen = np.zeros_like(walkable)
    stack = [start]
    seen[start] = True
    w, h = walkable.shape
    while stack:
        x, y = stack.pop()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and walkable[nx, ny] and not seen[nx, ny]:
                seen[nx, ny] = True
                stack.append((nx, ny))
    return seen


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--level", help="a level folder: reads its layout and clearings, writes its trees.json")
    parser.add_argument("--standin", type=int, help="grow on a stand-in map of this many cells a side")
    parser.add_argument("--out", help="where the stand-in's trees.json and the snapshots go")
    parser.add_argument("--years", type=int, default=100)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--snapshots", default="", help="years to write trees_yN.json at, e.g. 20,50,100")
    args = parser.parse_args()
    if args.level:
        allowed, path, clearings = from_level(args.level)
        out = args.out or args.level
    else:
        allowed, path, clearings = standin(args.standin or 96, args.seed)
        out = args.out
    os.makedirs(out, exist_ok=True)
    snapshots = {int(y) for y in args.snapshots.split(",") if y}
    stand = Stand(allowed, args.seed)
    started = time.time()
    print("GROW seedlings %d on %d cells" % (len(stand.tx), allowed.sum()))
    for year in range(1, args.years + 1):
        stand.step()
        if year in snapshots or year % 10 == 0:
            print("GROW %s, %.0f s, %d branches" % (json.dumps(stand.stats()), time.time() - started, len(stand.bt)), flush=True)
        if year in snapshots:
            write(os.path.join(out, "trees_y%d.json" % year), stand, path, clearings)
    write(os.path.join(out, "trees.json"), stand, path, clearings)
    # Walkability: every cell off the trunks reached from the path.
    walkable = np.ones_like(allowed)
    for t in stand.trees():
        if t["height"] >= TRUNK_HEIGHT:
            walkable[int(t["at"][0]), int(t["at"][1])] = False
    start = tuple(np.argwhere(path & walkable)[0])
    seen = reach(walkable, start)
    print("WALK %d walkable cells cut off" % int((walkable & ~seen).sum()))


def write(file, stand, path, clearings):
    data = {
        "decision": 467,
        "years": stand.year,
        "stats": stand.stats(),
        "clearings": clearings,
        "path": np.argwhere(path).tolist(),
        "trees": stand.trees(),
    }
    with open(file, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    print("WROTE %s (%d trees)" % (file, len(data["trees"])))


if __name__ == "__main__":
    main()
