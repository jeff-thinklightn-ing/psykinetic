#!/usr/bin/env bash
# tools/list_lines.py (decision 944): the lists every tree adds a name to are one name a line, in
# order, so two takes' adds merge. On a scratch copy of the repo's two files and a scratch git
# repository; never the checkout's own files. LIST_LINES_TEST_FILES=<folder> takes the two files
# from that folder's client3d/ and net/ instead (the old ones, to see the merge row fail there).
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null | tail -8; fi; }
src="${LIST_LINES_TEST_FILES:-$here}"
work="$tmp/repo"
mkdir -p "$work/tools" "$work/client3d" "$work/net"
cp "$here/tools/list_lines.py" "$work/tools/"
cp "$src/client3d/room_fields.gd" "$work/client3d/"
cp "$src/net/net.gd" "$work/net/"
LL() { python -B "$work/tools/list_lines.py" "$@" >"$tmp/out.txt" 2>&1; }

echo "== the files as they stand =="
LL; code=$?
if [ -z "${LIST_LINES_TEST_FILES:-}" ]; then
	check $code "the checkout's four lists are one name a line, in order"
else
	echo "  (old files: the check says $code)"
	LL --fix; check $? "--fix writes them one name a line, in order"
fi

echo "== out of shape: each way is named, and --fix mends it =="
cp "$work/client3d/room_fields.gd" "$tmp/room_fields.gd.good"
python - "$work/client3d/room_fields.gd" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
i = s.index("const VIEW")
j = s.index("]\n", i)
s = s[:j] + '\t&"zz_last", &"aa_first",\n' + s[j:]
open(p, "w", encoding="utf-8", newline="").write(s)
EOF
LL; check $([ $? = 1 ] && grep -q "room_fields.gd: VIEW (names out of order)" "$tmp/out.txt"; echo $?) "two names put at the end on one line: VIEW named out of order, exit 1"
LL --fix; check $? "--fix exits 0"
LL; check $? "and the check passes after it"
python - "$work/client3d/room_fields.gd" <<'EOF' >"$tmp/out.txt" 2>&1
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
i = s.index("const VIEW"); j = s.index("]\n", i)
names = re.findall(r'&"([^"]*)"', s[i:j])
assert names == sorted(names), "sorted"
assert "aa_first" in names and "zz_last" in names, "both kept"
assert len(names) == len(set(names)), "no repeat"
print(len(names))
EOF
check $([ $? = 0 ] && grep -q '^	&"aa_first",$' "$work/client3d/room_fields.gd" && grep -q '^	&"zz_last",$' "$work/client3d/room_fields.gd"; echo $?) "the two names each on a line of their own, in order, no repeat"
cp "$tmp/room_fields.gd.good" "$work/client3d/room_fields.gd"
python - "$work/net/net.gd" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
i = s.index("const MESSAGE_KINDS")
j = s.index('\t"admin",\n', i)
s = s[:j] + '\t"admin",\n' + s[j:]
open(p, "w", encoding="utf-8", newline="").write(s)
EOF
LL; check $([ $? = 1 ] && grep -q "net.gd: MESSAGE_KINDS (a repeated name)" "$tmp/out.txt"; echo $?) "a name twice: MESSAGE_KINDS named for the repeat"
LL --fix; LL; check $? "--fix drops the repeat"
grep -c '^	"admin",$' "$work/net/net.gd" >"$tmp/out.txt"; check $([ "$(cat "$tmp/out.txt")" = 1 ]; echo $?) "\"admin\" once"

echo "== two takes each add a var: git merges them (the point) =="
# A take adds <name> to VIEW as trees do: one name a line then --fix (944); on the old files (the
# variable above) at the end of the list's last line, as every take did before.
add_var() {
	python - client3d/room_fields.gd "$1" "${LIST_LINES_TEST_FILES:+old}" <<'EOF'
import sys
p, name = sys.argv[1], sys.argv[2]
old = len(sys.argv) > 3 and sys.argv[3] == "old"
s = open(p, encoding="utf-8", newline="").read()
i = s.index("const VIEW"); j = s.index("\n]\n", i)
s = s[:j] + (', &"%s"' % name if old else '\n\t&"%s",' % name) + s[j:]
open(p, "w", encoding="utf-8", newline="").write(s)
EOF
	[ -n "${LIST_LINES_TEST_FILES:-}" ] || python -B tools/list_lines.py --fix >/dev/null
}
cd "$work"
[ -n "${LIST_LINES_TEST_FILES:-}" ] && cp "$src/client3d/room_fields.gd" client3d/
git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false
git add -A && git commit -qm base
base="$(git rev-parse HEAD)"
git checkout -qb a
add_var _aa_from_take_a
git commit -qam "a adds _aa_from_take_a"
git checkout -q "$base"
git checkout -qb b
add_var _zz_from_take_b
git commit -qam "b adds _zz_from_take_b"
git rebase -q a >"$tmp/out.txt" 2>&1; code=$?
[ $code = 0 ] || git rebase --abort >/dev/null 2>&1
check $code "b's add rebased onto a's: no conflict"
[ -n "${LIST_LINES_TEST_FILES:-}" ] || { python -B tools/list_lines.py >"$tmp/out.txt" 2>&1; check $? "and the merged list still one name a line, in order"; }
check $(grep -q '&"_aa_from_take_a"' client3d/room_fields.gd && grep -q '&"_zz_from_take_b"' client3d/room_fields.gd; echo $?) "both names in it"
if [ -z "${LIST_LINES_TEST_FILES:-}" ]; then
	# Two adds that sort into the same gap edit the same spot: git stops, and --fix merges them.
	git checkout -q "$base" && git checkout -qb c && add_var _zz_from_take_c && git commit -qam "c adds _zz_from_take_c"
	git rebase -q b >"$tmp/out.txt" 2>&1; code=$?
	if [ $code != 0 ]; then
		python -B tools/list_lines.py --fix >"$tmp/out.txt" 2>&1; code=$?
		git add client3d/room_fields.gd && GIT_EDITOR=true git rebase --continue >>"$tmp/out.txt" 2>&1 || code=1
	fi
	check $([ $code = 0 ] && python -B tools/list_lines.py >/dev/null 2>&1 && grep -q '^	&"_zz_from_take_b",$' client3d/room_fields.gd && grep -q '^	&"_zz_from_take_c",$' client3d/room_fields.gd && grep -q '^	&"_aa_from_take_a",$' client3d/room_fields.gd; echo $?) "two adds in the same gap: rebased (through --fix if git stopped), all three names in, in shape"
fi
cd "$here"

echo "== a take queued before 944, rebased onto it: --fix keeps both sides' names =="
old="${LIST_LINES_TEST_FILES:-}"
if [ -z "$old" ]; then
	old="$tmp/old"
	mkdir -p "$old/client3d" "$old/net"
	git show origin/main:client3d/room_fields.gd >"$old/client3d/room_fields.gd" 2>/dev/null
	git show origin/main:net/net.gd >"$old/net/net.gd" 2>/dev/null
fi
if grep -q '^	"admin",$' "$old/net/net.gd" 2>/dev/null; then
	echo "  (origin/main already has 944's lists: the old files are gone, the row is not run)"
else
	q="$tmp/queued"
	mkdir -p "$q/tools" "$q/client3d" "$q/net"
	cp "$here/tools/list_lines.py" "$q/tools/"
	cp "$old/client3d/room_fields.gd" "$q/client3d/"
	cp "$old/net/net.gd" "$q/net/"
	cd "$q"
	git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false
	git add -A && git commit -qm "main before 944"
	base="$(git rev-parse HEAD)"
	git checkout -qb take
	python - client3d/room_fields.gd net/net.gd <<'EOF'
import sys
view, net = sys.argv[1], sys.argv[2]
s = open(view, encoding="utf-8", newline="").read()
i = s.index("const VIEW"); j = s.index("\n]\n", i)
s = s[:j] + ', &"_queued_var"' + s[j:]
open(view, "w", encoding="utf-8", newline="").write(s)
s = open(net, encoding="utf-8", newline="").read()
i = s.index("const MESSAGE_KINDS"); j = s.index("]", s.index("= [", i))
s = s[:j] + ', "queued_kind"' + s[j:]
open(net, "w", encoding="utf-8", newline="").write(s)
EOF
	git commit -qam "a take adds a var and a message kind the old way"
	git checkout -q "$base"
	git checkout -qb main944
	python -B tools/list_lines.py --fix >/dev/null
	git commit -qam "944 lands"
	git checkout -q take
	git rebase -q main944 >"$tmp/out.txt" 2>&1; code=$?
	check $([ $code != 0 ]; echo $?) "the queued take stops at its rebase (the one-time cost of 944)"
	python -B tools/list_lines.py --fix >"$tmp/out.txt" 2>&1; code=$?
	check $code "--fix on the stopped rebase: exit 0"
	python -B tools/list_lines.py >"$tmp/out.txt" 2>&1; check $? "the lists in shape"
	check $(! grep -q '^<<<<<<<\|^=======\|^>>>>>>>' client3d/room_fields.gd net/net.gd && grep -q '^	&"_queued_var",$' client3d/room_fields.gd && grep -q '^	"queued_kind",$' net/net.gd && grep -q '^	&"_camera",$' client3d/room_fields.gd && grep -q '^	"admin",$' net/net.gd; echo $?) "no markers left; the take's var and kind and main's names all there"
	git add client3d/room_fields.gd net/net.gd && GIT_EDITOR=true git rebase --continue >"$tmp/out.txt" 2>&1
	check $? "the rebase goes on"
	# A queued take that takes a name out (ui-design's bbf3d845b drops &"_hp_bar_shader" from VIEW) and
	# adds one: after --fix the name stays out (the merge base read three ways), the add is in.
	git checkout -q "$base" 2>/dev/null
	git checkout -qb drop
	gone_name="$(python - client3d/room_fields.gd <<'EOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
i = s.index("const VIEW"); j = s.index("\n]\n", i)
names = re.findall(r'&"([^"]*)"', s[s.index("= [", i):j])
name = "_hp_bar_shader" if "_hp_bar_shader" in names else names[1]
body = s[i:j]
cut = re.sub(r'&"%s"\s*,\s*' % re.escape(name), "", body, count=1)
if cut == body:
    cut = re.sub(r',\s*&"%s"' % re.escape(name), "", body, count=1)
cut += ', &"_dropper_var"'
open(p, "w", encoding="utf-8", newline="").write(s[:i] + cut + s[j:])
print(name)
EOF
)"
	git commit -qam "a take drops $gone_name and adds _dropper_var the old way"
	git rebase -q main944 >"$tmp/out.txt" 2>&1; code=$?
	check $([ $code != 0 ] && [ -n "$gone_name" ]; echo $?) "the dropping take stops at its rebase (it took out $gone_name)"
	python -B tools/list_lines.py --fix >"$tmp/out.txt" 2>&1; code=$?
	check $([ $code = 0 ] && grep -q "merged three ways" "$tmp/out.txt"; echo $?) "--fix on it: exit 0, the merge base read"
	check $(! grep -q '^<<<<<<<\|^=======\|^>>>>>>>' client3d/room_fields.gd && ! grep -q "&\"$gone_name\"" client3d/room_fields.gd && grep -q '^	&"_dropper_var",$' client3d/room_fields.gd && grep -q '^	&"_camera",$' client3d/room_fields.gd; echo $?) "$gone_name stays out, _dropper_var in, main's other names kept"
	python -B tools/list_lines.py >"$tmp/out.txt" 2>&1; check $? "the lists in shape"
	git add client3d/room_fields.gd && GIT_EDITOR=true git rebase --continue >"$tmp/out.txt" 2>&1
	check $? "the rebase goes on"
	# Any other conflict in the file is refused, never guessed.
	git checkout -q "$base" 2>/dev/null
	git checkout -qb other
	python - net/net.gd <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
s = s.replace("const MESSAGE_KINDS", "## a comment the take wrote\nconst MESSAGE_KINDS", 1)
i = s.index("const MESSAGE_KINDS"); j = s.index("]", s.index("= [", i))
s = s[:j] + ', "other_kind"' + s[j:]
open(p, "w", encoding="utf-8", newline="").write(s)
EOF
	git commit -qam "a take edits beside the list too"
	git checkout -q main944
	python - net/net.gd <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
s = s.replace("const MESSAGE_KINDS", "## main's own comment there\nconst MESSAGE_KINDS", 1)
open(p, "w", encoding="utf-8", newline="").write(s)
EOF
	git commit -qam "main edits beside the list"
	git checkout -q other
	git rebase -q main944 >/dev/null 2>&1
	python -B tools/list_lines.py --fix >"$tmp/out.txt" 2>&1; code=$?
	check $([ $code = 2 ] && grep -q "a conflict outside its lists" "$tmp/out.txt" && grep -q '^<<<<<<<' net/net.gd; echo $?) "a conflict beside the list too: refused (exit 2), the file left as git stopped it"
	git rebase --abort >/dev/null 2>&1
	cd "$here"
fi

echo
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($failed)"; exit 1; fi
