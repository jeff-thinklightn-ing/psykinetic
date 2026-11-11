"""Reads clip.gd walkreel's [gait] lines: the gait's numbers for each moving stretch.

python gait_read.py <godot log> [ground_lift_m]
"""
import math
import statistics as st
import sys

PLANT = 0.03  # A toe this near its lowest is planted (m).
AIR = 0.05  # Both toes this far above their lowest: off the ground (m).

rows = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
	if not line.startswith("[gait] "):
		continue
	f = line.split()[1:]
	t, x, z, speed = map(float, f[0:4])
	clip = f[4]
	rate, pos, hips, lx, ly, lz, rx, ry, rz = map(float, f[5:14])
	tick = int(f[14])
	ex, ez = (float(f[15]), float(f[16])) if len(f) > 16 else (None, None)
	rows.append(dict(t=t, x=x, z=z, speed=speed, clip=clip, rate=rate, pos=pos, hips=hips,
		l=(lx, ly, lz), r=(rx, ry, rz), tick=tick, ex=ex, ez=ez))
print("frames", len(rows), "over %.2f s" % (rows[-1]["t"] - rows[0]["t"]))
ground = min(min(r["l"][1], r["r"][1]) for r in rows)
print("ground (lowest toe) %.3f" % ground)

# Moving stretches: the drawn body moving faster than 0.5 m/s, frame to frame.
for i in range(1, len(rows)):
	a, b = rows[i - 1], rows[i]
	dt = b["t"] - a["t"]
	b["v"] = math.hypot(b["x"] - a["x"], b["z"] - a["z"]) / dt if dt > 0 else 0.0
rows[0]["v"] = 0.0
stretches = []
cur = []
for r in rows:
	if r["v"] > 0.5:
		cur.append(r)
	elif cur:
		if len(cur) > 30:
			stretches.append(cur)
		cur = []
if len(cur) > 30:
	stretches.append(cur)


def pct(xs, q):
	xs = sorted(xs)
	return xs[min(len(xs) - 1, int(q * len(xs)))]


for n, s in enumerate(stretches):
	dur = s[-1]["t"] - s[0]["t"]
	# The steady middle: past the first 0.6 s and before the last 0.6 s.
	mid = [r for r in s if s[0]["t"] + 0.6 < r["t"] < s[-1]["t"] - 0.6]
	print("\n== stretch %d: %.2f s from %.2f, %d frames, steady middle %d" % (n, dur, s[0]["t"], len(s), len(mid)))
	if len(mid) < 20:
		mid = s
	# This stretch's planted level: the lower toe's 5th percentile (the toe bone stands above the sole).
	ground = pct([min(r["l"][1], r["r"][1]) for r in mid], 0.05)
	print("  planted level (lower toe p5) %.3f; the lowest toe here %.3f" % (ground, min(min(r["l"][1], r["r"][1]) for r in mid)))
	vs = [r["v"] for r in mid]
	print("  body ground speed m/s: mean %.3f  min %.3f  p10 %.3f  p90 %.3f  max %.3f  (sd %.3f)"
		% (st.mean(vs), min(vs), pct(vs, 0.1), pct(vs, 0.9), max(vs), st.pstdev(vs)))
	# The surge bar (physics and animation, 11-11): over frames a second in and a second before the stop.
	steady = [r for r in s if s[0]["t"] + 1.0 < r["t"] < s[-1]["t"] - 1.0]
	def bar(name, speeds):
		m = st.mean(speeds)
		out = sum(1 for v in speeds if abs(v - m) > 0.1 * m)
		print("  %s per frame: mean %.3f sd %.3f p5 %.3f p95 %.3f, outside +-10%% of the mean %.0f%% (%d frames)"
			% (name, m, st.pstdev(speeds), pct(speeds, 0.05), pct(speeds, 0.95), 100.0 * out / len(speeds), len(speeds)))
	if len(steady) > 10:
		bar("puppet", [r["v"] for r in steady])
		if steady[0]["ex"] is not None:
			es = []
			for i in range(1, len(steady)):
				a0, b0 = steady[i - 1], steady[i]
				dt = b0["t"] - a0["t"]
				if dt > 0:
					es.append(math.hypot(b0["ex"] - a0["ex"], b0["ez"] - a0["ez"]) / dt)
			bar("entity", es)
	# The body's speed a tick at a time (cells): surges per cell?
	by_tick = {}
	for r in mid:
		by_tick.setdefault(r["tick"], []).append(r["v"])
	print("  speed by tick:", " ".join("%.2f" % st.mean(by_tick[k]) for k in sorted(by_tick)[:24]))
	gs = [r["speed"] for r in mid]
	print("  Client3D speed (smoothed) mean %.3f min %.3f max %.3f" % (st.mean(gs), min(gs), max(gs)))
	clips = {}
	for r in mid:
		clips[r["clip"]] = clips.get(r["clip"], 0) + 1
	rates = [r["rate"] for r in mid]
	print("  clips", clips, " rate mean %.3f min %.3f max %.3f" % (st.mean(rates), min(rates), max(rates)))
	hs = [r["hips"] - ground for r in mid]
	print("  hips above ground: mean %.3f  min %.3f  max %.3f  -> rise and fall %.3f m" % (st.mean(hs), min(hs), max(hs), max(hs) - min(hs)))
	# Plants: a toe planted (within PLANT of the ground) for a run of frames; its slide while planted.
	plants = []
	slides = []
	for side in ("l", "r"):
		run = []
		for r in mid:
			if r[side][1] - ground < PLANT:
				run.append(r)
			else:
				if len(run) >= 2:
					plants.append((run[0]["t"], side, run))
				run = []
		if len(run) >= 2:
			plants.append((run[0]["t"], side, run))
	plants.sort(key=lambda p: p[0])
	for _, side, run in plants:
		for i in range(1, len(run)):
			a, b = run[i - 1][side], run[i][side]
			dt = run[i]["t"] - run[i - 1]["t"]
			slides.append(math.hypot(b[0] - a[0], b[2] - a[2]) / dt)
	if slides:
		print("  planted toe's ground speed m/s: median %.3f  p90 %.3f  max %.3f (0 is no slide)" % (st.median(slides), pct(slides, 0.9), max(slides)))
	if len(plants) >= 3:
		starts = [p[0] for p in plants]
		gaps = [b - a for a, b in zip(starts, starts[1:])]
		where = []
		for _, side, run in plants:
			mx = st.mean(r[side][0] for r in run)
			mz = st.mean(r[side][2] for r in run)
			where.append((mx, mz))
		lengths = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(where, where[1:])]
		held = [p[2][-1]["t"] - p[2][0]["t"] for p in plants]
		print("  steps: %d, cadence %.2f a second (%.0f a minute), step length mean %.2f m (min %.2f max %.2f), each foot down %.3f s"
			% (len(plants), 1.0 / st.mean(gaps), 60.0 / st.mean(gaps), st.mean(lengths), min(lengths), max(lengths), st.mean(held)))
		print("  step gaps s:", " ".join("%.3f" % g for g in gaps[:16]))
	air = [r for r in mid if min(r["l"][1], r["r"][1]) - ground > AIR]
	print("  both toes over %.2f m: %.0f%% of the time (%d frames)" % (AIR, 100.0 * len(air) / len(mid), len(air)))
	low = [min(r["l"][1], r["r"][1]) - ground for r in mid]
	print("  lower toe above ground: median %.3f p90 %.3f max %.3f" % (st.median(low), pct(low, 0.9), max(low)))
	# The loop's seam: the clip's place wrapping, and the toes' jump there against a usual frame's.
	jumps = []
	usual = []
	for i in range(1, len(mid)):
		a, b = mid[i - 1], mid[i]
		d = max(math.dist(a["l"], b["l"]), math.dist(a["r"], b["r"]))
		if b["pos"] < a["pos"] - 0.05 and a["clip"] == b["clip"]:
			jumps.append(d)
		else:
			usual.append(d)
	if jumps and usual:
		print("  at the loop's seam the toes move %.3f m in a frame (a usual frame %.3f, p99 %.3f)" % (max(jumps), st.median(usual), pct(usual, 0.99)))
	# The hips' rise and fall a cycle: their period against the steps'.
	ups = [mid[i]["t"] for i in range(1, len(mid) - 1) if mid[i]["hips"] > mid[i - 1]["hips"] and mid[i]["hips"] >= mid[i + 1]["hips"]]
	if len(ups) > 2:
		print("  hips peak every %.3f s (%d peaks)" % (st.mean(b - a for a, b in zip(ups, ups[1:])), len(ups)))
