#!/usr/bin/env bash
# tools/land_rebase.sh (394 amended (65)): a landing's fetch and rebase in one place, the
# resolvers' files let through, anything else aborted with the checkout left as it was; and its
# --would mode, which touches no working tree and no index. A scratch bare remote and clone; the
# lock's log and marks in a scratch folder. Never touches this checkout or the real lock.
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2${3:+: $3}"; failed=$((failed + 1)); fi
}
g() { git -c user.name=t -c user.email=t@t -c core.autocrlf=false -c advice.detachedHead=false "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export PSYKINETIC_LAND_LOCK="$tmp/land.lock"
LOG="$tmp/land.lock.log"

git init -q --bare -b main "$tmp/remote.git"
g clone -q "$tmp/remote.git" "$tmp/main" 2>/dev/null
g clone -q "$tmp/remote.git" "$tmp/take" 2>/dev/null
# This machine's own autocrlf would show LF files as changed to the tool's plain git calls.
for each in main take; do git -C "$tmp/$each" config core.autocrlf false; git -C "$tmp/$each" config user.name t; git -C "$tmp/$each" config user.email t@t; done
cd "$tmp/main"
mkdir -p tools docs art/kit
cp "$here/tools/land_rebase.sh" "$here/tools/changelog_resolve.py" tools/
printf '# Changelog\n\n## Unreleased\n\n- an old bullet\n\n## v0.1.0\n\n- shipped\n' > CHANGELOG.md
printf 'voice 1\nvoice 2\n' > docs/voice_inventory.md
printf 'art 1\n' > docs/art_status.md
printf 'var a = 1\nvar b = 2\n' > main.gd
printf 'game\n' > game.gd
g add -A; g commit -q -m base; g push -q origin HEAD:main 2>/dev/null
# The resolver's stand-in for the pages (the real one runs the generators over the whole game):
# each conflicted page from main's side, as changelog_resolve.py does before its generator; exit 1
# with any other file in conflict, as it does.
cat > "$tmp/pages.sh" <<'EOF'
#!/usr/bin/env bash
for f in $(git diff --name-only --diff-filter=U); do
	case "$f" in docs/voice_inventory.md|docs/art_status.md|art/kit/status.json) git checkout --ours -- "$f" && git add -- "$f" ;; *) exit 1 ;; esac
done
EOF
cat > "$tmp/refuse.sh" <<'EOF'
#!/usr/bin/env bash
echo "changelog_resolve: refused (the test's)"; exit 1
EOF
main_commit() {  # <file> <text> [<file> <text>]: main moves by one commit
	cd "$tmp/main"; g pull -q --rebase origin main 2>/dev/null
	while [ $# -ge 2 ]; do printf '%s' "$2" > "$1"; shift 2; done
	g add -A; g commit -q -m "main moves"; g push -q origin HEAD:main 2>/dev/null
}
take_reset() {  # the take: a branch from the base, before main moved
	cd "$tmp/take"; g fetch -q origin; g rebase --abort >/dev/null 2>&1
	g checkout -q -B take "$(g rev-list --max-parents=0 origin/main)"; g reset -q --hard "$(g rev-list --max-parents=0 origin/main)"
}
take_commit() {
	cd "$tmp/take"
	while [ $# -ge 2 ]; do printf '%s' "$2" > "$1"; shift 2; done
	g add -A; g commit -q -m "the take"
}
run() { (cd "$tmp/take" && LAND_REBASE_RESOLVER="${RESOLVER:-bash $tmp/pages.sh}" bash tools/land_rebase.sh "$@" 2>&1); }
lines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
clean_tree() { cd "$tmp/take"; [ -z "$(git status --porcelain --untracked-files=no)" ] && [ ! -d "$(git rev-parse --git-path rebase-merge)" ] && [ ! -d "$(git rev-parse --git-path rebase-apply)" ]; }

echo "== the rebase =="
take_reset; take_commit game.gd 'game, the take'
cd "$tmp/take"; mkdir -p tools; cp "$tmp/main/tools/"* tools/ 2>/dev/null
main_commit README.md 'readme'
cd "$tmp/take"; said="$(run take-a)"; code=$?
[ $code = 0 ] && printf '%s' "$said" | grep -q "^rebased onto" && [ "$(git rev-parse HEAD~1)" = "$(git rev-parse origin/main)" ]
check $? "no conflict: rebased onto origin/main, exit 0" "[$code $said]"
grep -q "land_rebase take-a: rebased onto" "$LOG"; check $? "and said in the lock's log"
[ "$(cut -d' ' -f3 "$tmp/land.lock.would/take-a")" = rebased ]; check $? "its mark: rebased"

take_reset; take_commit docs/voice_inventory.md 'voice 1, the take
voice 2
' game.gd 'game, the take'
main_commit docs/voice_inventory.md 'voice 1, main
voice 2
'
said="$(run take-b)"; code=$?
cd "$tmp/take"
[ $code = 0 ] && printf '%s' "$said" | grep -q "resolved: docs/voice_inventory.md" && grep -q "voice 1, main" docs/voice_inventory.md && grep -q "game, the take" game.gd
check $? "the voice page alone: main's side taken, the rest of the commit kept, exit 0" "[$code $said]"
clean_tree; check $? "and the checkout clean, no rebase left stopped"
grep -q "land_rebase take-b: rebased onto .*, resolved docs/voice_inventory.md" "$LOG"; check $? "the log names what was resolved"

take_reset; take_commit docs/voice_inventory.md 'voice 1, two
voice 2
' docs/art_status.md 'art 1, two
' game.gd 'game, two'
main_commit docs/voice_inventory.md 'voice 1, main two
voice 2
' docs/art_status.md 'art 1, main two
'
said="$(run take-c)"; code=$?
[ $code = 0 ] && printf '%s' "$said" | grep -q "docs/art_status.md" && printf '%s' "$said" | grep -q "docs/voice_inventory.md"
check $? "two pages together in one stop: both resolved" "[$code $said]"

take_reset; take_commit docs/voice_inventory.md 'voice 1, real
voice 2
' main.gd 'var a = 1
var take = 3
'
start="$(cd "$tmp/take" && git rev-parse HEAD)"
main_commit docs/voice_inventory.md 'voice 1, main real
voice 2
' main.gd 'var a = 1
var rack = {}
'
before="$(lines)"
said="$(run take-d)"; code=$?
cd "$tmp/take"
[ $code = 1 ] && printf '%s' "$said" | grep -q "REBASE CONFLICT onto .*main.gd" && ! printf '%s' "$said" | grep -q "CONFLICT onto [^:]*: docs/voice"
check $? "a page beside a real conflict (main.gd): exit 1, main.gd named" "[$code $said]"
[ "$(git rev-parse HEAD)" = "$start" ] && clean_tree; check $? "and aborted: the checkout at its own commit, clean, no rebase stopped"
[ $(( $(lines) - before )) = 1 ] && tail -1 "$LOG" | grep -q "land_rebase take-d: stopped onto .*main.gd.*aborted"; check $? "one line in the lock's log, the file named" "[$(tail -1 "$LOG")]"
[ "$(cut -d' ' -f3 "$tmp/land.lock.would/take-d")" = conflict ]; check $? "its mark: conflict"

take_reset; take_commit docs/voice_inventory.md 'voice 1, refused
voice 2
'
start="$(cd "$tmp/take" && git rev-parse HEAD)"
main_commit docs/voice_inventory.md 'voice 1, main refused
voice 2
'
said="$(RESOLVER="bash $tmp/refuse.sh" run take-e)"; code=$?
cd "$tmp/take"
[ $code = 1 ] && printf '%s' "$said" | grep -q "the resolver refused docs/voice_inventory.md" && [ "$(git rev-parse HEAD)" = "$start" ] && clean_tree
check $? "the resolver refuses (THIRD_PARTY.md outside its spans, say): aborted, clean, exit 1" "[$code $said]"

take_reset; take_commit docs/voice_inventory.md 'voice 1, only
voice 2
'
take_commit game.gd 'game, after'
main_commit docs/voice_inventory.md 'voice 1, main only
voice 2
'
said="$(run take-f)"; code=$?
cd "$tmp/take"
[ $code = 0 ] && [ "$(git rev-list --count origin/main..HEAD)" = 1 ] && grep -q "game, after" game.gd && clean_tree
check $? "a commit that changed only the page, left empty: dropped, the next one kept" "[$code $said; $(git rev-list --count origin/main..HEAD) ahead]"

take_reset; take_commit docs/voice_inventory.md 'voice 1, first
voice 2
'
take_commit docs/voice_inventory.md 'voice 1, second
voice 2
' game.gd 'game, second'
main_commit docs/voice_inventory.md 'voice 1, main both
voice 2
'
said="$(run take-g)"; code=$?
cd "$tmp/take"
[ $code = 0 ] && grep -q "game, second" game.gd && clean_tree; check $? "two commits each stopping on the page: both stops resolved" "[$code $said]"

echo "== CHANGELOG.md through the real resolver =="
take_reset; take_commit CHANGELOG.md '# Changelog

## Unreleased

- an old bullet
- the take'"'"'s bullet

## v0.1.0

- shipped
'
main_commit CHANGELOG.md '# Changelog

## Unreleased

- an old bullet
- main'"'"'s bullet

## v0.1.0

- shipped
'
said="$(RESOLVER="python -B tools/changelog_resolve.py" run take-h)"; code=$?
cd "$tmp/take"
[ $code = 0 ] && grep -q "the take's bullet" CHANGELOG.md && grep -q "main's bullet" CHANGELOG.md && [ "$(grep -c "an old bullet" CHANGELOG.md)" = 1 ]
check $? "both bullets under Unreleased, none doubled (changelog_resolve.py itself)" "[$code $said]"

echo "== refused before it starts =="
take_reset; take_commit game.gd 'game, dirty'; printf 'uncommitted\n' >> "$tmp/take/game.gd"
said="$(run take-i)"; code=$?
[ $code = 2 ] && printf '%s' "$said" | grep -q "not committed"; check $? "tracked changes not committed: exit 2, nothing done" "[$code $said]"
cd "$tmp/take"; g checkout -q -- game.gd
take_reset; take_commit main.gd 'var a = 1
var stop = 1
'
main_commit main.gd 'var a = 1
var main = 1
'
cd "$tmp/take"; g rebase -q origin/main >/dev/null 2>&1
said="$(run take-j)"; code=$?
[ $code = 2 ] && printf '%s' "$said" | grep -q "already stopped"; check $? "a rebase already stopped here: exit 2, left as it was" "[$code $said]"
cd "$tmp/take"; g rebase --abort
said="$(run)"; code=$?
[ $code = 2 ] && printf '%s' "$said" | grep -q "^usage"; check $? "no tree named: usage, exit 2"

echo "== --would: no working tree, no index =="
take_reset; take_commit game.gd 'game, would'
cd "$tmp/take"; g fetch -q origin
head0="$(git rev-parse HEAD)"; index0="$(git write-tree)"
said="$(run --would take-w)"; code=$?
[ $code = 1 ] || [ $code = 0 ]; check $? "it answers (exit $code: $said)"
take_reset; take_commit notes.txt "notes, would"
cd "$tmp/take"; g fetch -q origin
main_commit game.gd 'game, main would'
cd "$tmp/take"; head0="$(git rev-parse HEAD)"; index0="$(git write-tree)"
said="$(run --would take-w)"; code=$?
[ $code = 0 ] && printf '%s' "$said" | grep -q "^clean"; check $? "no conflict: clean, exit 0" "[$code $said]"
take_reset; take_commit docs/voice_inventory.md 'voice 1, would
voice 2
'
cd "$tmp/take"; head0="$(git rev-parse HEAD)"; index0="$(git write-tree)"
said="$(run --would take-w)"; code=$?
[ $code = 0 ] && printf '%s' "$said" | grep -q "^resolvable: docs/voice_inventory.md"; check $? "the page alone: resolvable, exit 0" "[$code $said]"
take_reset; take_commit docs/voice_inventory.md 'voice 1, would two
voice 2
' main.gd 'var a = 1
var would = 1
'
cd "$tmp/take"; head0="$(git rev-parse HEAD)"; index0="$(git write-tree)"; files0="$(cat main.gd docs/voice_inventory.md)"
before="$(lines)"
said="$(run --would take-w)"; code=$?
[ $code = 1 ] && printf '%s' "$said" | grep -q "^CONFLICT: main.gd .*; and the resolvers' docs/voice_inventory.md"
check $? "a real conflict beside the page: CONFLICT naming main.gd, the page apart, exit 1" "[$code $said]"
[ "$(git rev-parse HEAD)" = "$head0" ] && [ "$(git write-tree)" = "$index0" ] && [ "$(cat main.gd docs/voice_inventory.md)" = "$files0" ] && clean_tree
check $? "HEAD, the index and the files untouched"
[ $(( $(lines) - before )) = 1 ] && tail -1 "$LOG" | grep -q "land_rebase take-w: would conflict onto .* in .*main.gd.*rebase before its turn"
check $? "the lock's log told once" "[$(tail -1 "$LOG")]"
run --would --no-fetch take-w >/dev/null
[ $(( $(lines) - before )) = 1 ]; check $? "asked again on the same tip of main: no second line"
grep -q " conflict .*main.gd" "$tmp/land.lock.would/take-w"; check $? "its mark: conflict, main.gd" "[$(cat "$tmp/land.lock.would/take-w")]"
main_commit README.md 'main moves on'
cd "$tmp/take"; run --would take-w >/dev/null
[ $(( $(lines) - before )) = 2 ]; check $? "main's tip moves: told again"
# A stack whose base landed under another sha (perf's place on lockroom, 11-16): one merge of the
# tip met the base's lines on both sides and called it a conflict; the rebase drops the landed copy.
take_reset; take_commit lib.gd 'v2
'
take_commit lib.gd 'v3
'
main_commit lib.gd 'v2
'
cd "$tmp/take"; g fetch -q origin
git merge-tree --write-tree --name-only --no-messages origin/main HEAD >/dev/null 2>&1; tip=$?
said="$(run --would --no-fetch take-s)"; code=$?
[ $tip = 1 ] && [ $code = 0 ] && printf '%s' "$said" | grep -q "^clean"
check $? "a stack on a base landed as another sha: clean, as the rebase finds it (one merge of the tip: exit $tip)" "[$code $said]"
said="$(run take-s)"; code=$?
[ $code = 0 ] && grep -q v3 "$tmp/take/lib.gd" && [ "$(cd "$tmp/take" && git rev-list --count origin/main..HEAD)" = 1 ]
check $? "and the rebase itself: the landed copy dropped, the top commit on main" "[$code $said]"
# A stop in the middle of a stack that its tip undoes: the replay meets it where the rebase does.
take_reset; take_commit main.gd 'var a = 1
var mid = 1
'
take_commit main.gd 'var a = 1
var b = 2
'
main_commit main.gd 'var a = 1
var b = 2
var main_mid = 1
'
cd "$tmp/take"; g fetch -q origin
said="$(run --would --no-fetch take-m)"; code=$?
[ $code = 1 ] && printf '%s' "$said" | grep -q "^CONFLICT: main.gd"
check $? "a middle commit's conflict the tip undoes: CONFLICT, as the rebase would stop" "[$code $said]"
# The coordinator's term: --would leaves nothing in the store nobody may gc. Its replay's objects
# go to a temp folder of its own, removed on the way out.
store() { (cd "$tmp/take" && git count-objects -v | grep -E '^(count|packs|size-pack):' | tr '\n' ' '; ls "$(git rev-parse --git-common-dir)/objects/pack" 2>/dev/null | tr '\n' ' '); }
mkdir -p "$tmp/temp"
take_reset; take_commit main.gd 'var a = 1
var stack1 = 1
'
take_commit main.gd 'var a = 1
var stack2 = 1
' CHANGELOG.md '# Changelog

## Unreleased

- an old bullet
- a stacked bullet

## v0.1.0

- shipped
'
cd "$tmp/take"; g fetch -q origin
before="$(store)"
said="$(TEMP="$tmp/temp" run --would --no-fetch take-o)"; code=$?
after="$(store)"
[ $code = 1 ] && [ "$before" = "$after" ]; check $? "a conflicting stack replayed: the store's loose objects and packs the same after" "[$code $said; $before / $after]"
[ -z "$(ls -A "$tmp/temp")" ]; check $? "and its own object folder gone" "[$(ls -A "$tmp/temp")]"
take_reset; take_commit notes.txt 'notes, store'
cd "$tmp/take"; g fetch -q origin
before="$(store)"
said="$(TEMP="$tmp/temp" run --would --no-fetch take-o)"; code=$?
[ $code = 0 ] && [ "$before" = "$(store)" ] && [ -z "$(ls -A "$tmp/temp")" ]; check $? "a clean replay: the same" "[$code $said]"

echo "== nothing shared changed =="
cd "$tmp/take"
[ -z "$(git config --get-regexp '^merge\.' 2>/dev/null)" ] && [ ! -s "$(git rev-parse --git-common-dir)/info/attributes" ] && [ ! -f .gitattributes ]
check $? "no merge driver in the config, no attributes written"
take_reset; take_commit main.gd 'var a = 1
var old = 1
'
cd "$tmp/take"; g fetch -q; g rebase -q origin/main >/dev/null 2>&1; code=$?
[ $code != 0 ] && git diff --name-only --diff-filter=U | grep -qx main.gd; check $? "a land script from before it, its own rebase: the same stop as ever"
g rebase --abort; clean_tree; check $? "and its own abort leaves it clean"

echo
echo "RESULT: $([ $failed = 0 ] && echo PASS || echo "FAIL ($failed failed)")"
exit $([ $failed = 0 ] && echo 0 || echo 1)
