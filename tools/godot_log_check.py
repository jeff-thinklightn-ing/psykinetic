"""Every Godot the tooling starts names its own log (decision 664).

A Godot run without --log-file writes user://logs/godot.log, and that shared
folder keeps only the last five: a suite's dozens of runs rotated Jeff's own
client's log (a draugr fight he wanted read) out within minutes. So each
launch in tests/ and tools/ passes --log-file into its checkout's build/logs
(tests/godot_log.sh's godot_log, tests/godot_log.ps1's Get-GodotLog). This
fails any launch line that doesn't; land.sh runs it before the gate.

Every launch is silent too (664 amended): Jeff heard sessions' test windows
play music on his speakers. --headless already means --audio-driver Dummy; a
windowed run (a clip, a shot) passes --audio-driver Dummy itself. Sound's own
capture runs name a real driver (--audio-driver WASAPI), which also passes.

  python -B tools/godot_log_check.py      prints each line missing either, exit 1
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# A launch: sh "$GODOT" with an option after it; ps1 & / Start-Process on the
# exe; a GDScript tool's OS.execute of its own exe.
LAUNCH = {
	".sh": re.compile(r'"\$GODOT"\s+-'),
	".ps1": re.compile(r'(?:&|-FilePath)\s+\$(?:godot|env:GODOT_PATH)\b', re.I),
	".gd": re.compile(r'OS\.execute\(OS\.get_executable_path\(\)'),
}
# How far a launch's arguments may run on (continued lines, an $arguments
# array built just above a Start-Process).
SPAN = 3


def missing(path: pathlib.Path) -> list[str]:
	pattern = LAUNCH[path.suffix]
	lines = path.read_text(encoding="utf-8-sig").splitlines()
	found = []
	for i, line in enumerate(lines):
		if line.lstrip().startswith("#") or not pattern.search(line):
			continue
		near = "\n".join(lines[max(0, i - SPAN):i + SPAN + 1])
		if "--version" in line:
			continue
		lacks = [why for why, ok in (("no --log-file", "--log-file" in near),
				("not silent (--headless or --audio-driver Dummy)", "--headless" in near or "--audio-driver" in near)) if not ok]
		if lacks:
			found.append("%s:%d: %s: %s" % (path.relative_to(ROOT).as_posix(), i + 1, ", ".join(lacks), line.strip()))
	return found


def main() -> int:
	found = []
	for folder in ("tests", "tools"):
		for path in sorted((ROOT / folder).rglob("*")):
			if path.suffix in LAUNCH and path.is_file():
				found += missing(path)
	for line in found:
		print(line)
	if found:
		print("godot_log_check: %d Godot launch(es) without --log-file or silence (decision 664: give each its own log in build/logs; 664 amended: --headless or --audio-driver Dummy)" % len(found))
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
