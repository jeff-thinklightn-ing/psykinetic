#!/usr/bin/env bash
# tools/land_push.sh (667 amended (3)) in a scratch clone pushing to a scratch bare remote,
# git's push and fetch faked where a case needs the network to fail (LAND_PUSH_GIT), the
# land lock a scratch folder (PSYKINETIC_LAND_LOCK). Never touches this checkout's own
# remote, hooks or the real lock.
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null; echo "      calls: $(tr "
" " " < "$tmp/calls" 2>/dev/null)"; fi
}
g() { git -c user.name=t -c user.email=t@t -c core.autocrlf=false "$@"; }

git init -q --bare -b main "$tmp/remote.git"
g clone -q "$tmp/remote.git" "$tmp/clone" 2>/dev/null
g clone -q "$tmp/remote.git" "$tmp/other" 2>/dev/null
cd "$tmp/clone"
echo base > f; g add -A; g commit -q -m base; g push -q origin HEAD:main 2>/dev/null
(cd "$tmp/other" && g pull -q origin main 2>/dev/null)

# The fake git: each push takes the next line of $tmp/plan (ok: the real push; hang: no
# answer; net: a network error, nothing pushed; landed: the real push, then the network
# error; refuse: a refused push; move: another tree lands first, then a network error;
# steal: the lock taken by another, then a network error; freeze: release's freeze, then a
# network error), each fetch the next of
# $tmp/fetchplan (ok, or fail). Every push and fetch is counted.
cat > "$tmp/fakegit.sh" <<'EOF'
tmp="$(dirname "$0")"
next() { line="$(head -1 "$tmp/$1" 2>/dev/null)"; sed -i '1d' "$tmp/$1" 2>/dev/null; echo "${line:-ok}"; }
neterr() { echo "fatal: unable to access 'https://example.invalid/r.git/': Connection timed out after 300048 milliseconds" >&2; exit 128; }
case " $* " in
*" push "*)
	echo push >> "$tmp/calls"
	case "$(next plan)" in
	ok) exec git "$@" ;;
	hang) exec sleep 8 ;;
	net) neterr ;;
	landed) git "$@" >/dev/null 2>&1; neterr ;;
	refuse) echo " ! [rejected]        main -> main (non-fast-forward)" >&2; echo "error: failed to push some refs" >&2; exit 1 ;;
	move) (cd "$tmp/other" && git fetch -q origin && git reset -q --hard origin/main && echo moved >> f && git -c user.name=o -c user.email=o@o commit -qam moved && git push -q origin HEAD:main) >/dev/null 2>&1; neterr ;;
	steal) echo other > "$PSYKINETIC_LAND_LOCK/owner"; neterr ;;
	freeze) echo release > "$PSYKINETIC_LAND_LOCK/owner"; echo "main frozen for the cut" > "$PSYKINETIC_LAND_LOCK/what"; neterr ;;
	esac ;;
*" fetch "*)
	echo fetch >> "$tmp/calls"
	[ "$(next fetchplan)" = fail ] && { echo "fatal: unable to access: Could not resolve host" >&2; exit 128; }
	exec git "$@" ;;
*) exec git "$@" ;;
esac
EOF
export LAND_PUSH_GIT="bash $tmp/fakegit.sh" LAND_PUSH_TIMEOUT=3 LAND_PUSH_WAIT=0
export PSYKINETIC_LAND_LOCK="$tmp/land.lock"
lock() {  # lock <owner> <what>: the scratch land lock, held.
	rm -rf "$PSYKINETIC_LAND_LOCK"; mkdir -p "$PSYKINETIC_LAND_LOCK"
	echo "$1" > "$PSYKINETIC_LAND_LOCK/owner"; echo "$2" > "$PSYKINETIC_LAND_LOCK/what"
	echo 1 > "$PSYKINETIC_LAND_LOCK/since"; date +%s > "$PSYKINETIC_LAND_LOCK/taken"
}
n=0
take() {  # take "<push plan>" "<fetch plan>": a fresh tested commit on origin/main, the lock t's.
	# origin/main as this clone last saw it: a push and land_push's fetch keep it current.
	g reset -q --hard origin/main
	n=$((n + 1)); echo "take $n" >> f; g commit -qam "take $n"
	sha="$(git rev-parse HEAD)"
	printf '%s\n' $1 > "$tmp/plan"; printf '%s\n' ${2:-} > "$tmp/fetchplan"; : > "$tmp/calls"
	lock t "a take"
}
push() { sh "$here/tools/land_push.sh" t "$sha" > "$tmp/out.txt" 2>&1; }
pushes() { grep -c push "$tmp/calls"; }
remote() { git --git-dir="$tmp/remote.git" rev-parse main; }
logged() { grep -qF "$1" "$PSYKINETIC_LAND_LOCK.log"; }

echo "== it answers =="
take "ok"
push; check $? "pushed: exit 0"
[ "$(remote)" = "$sha" ]; check $? "main is the tested sha"
grep -q "^pushed $sha$" "$tmp/out.txt"; check $? "it says \"pushed <sha>\""
logged "pushed by t: $(echo "$sha" | cut -c1-9) (try 1)"; check $? "the try in the lock's log"
[ "$(cat "$PSYKINETIC_LAND_LOCK/since")" != 1 ]; check $? "the lock beaten"

echo "== no answer (the fake timeout), then it answers =="
take "hang ok" "ok"
started=$(date +%s)
push; check $? "pushed on the second try: exit 0"
[ $(( $(date +%s) - started )) -lt 20 ]; check $? "the dead try cut at LAND_PUSH_TIMEOUT, not left to hang"
[ "$(remote)" = "$sha" ] && [ "$(pushes)" = 2 ]; check $? "main is the tested sha, after two pushes"
logged "failed on the network: $(echo "$sha" | cut -c1-9) (try 1 of 3): no answer in 3 s"; check $? "the timed-out try logged"

echo "== it landed after all =="
take "landed ok" "ok"
push; check $? "exit 0"
[ "$(remote)" = "$sha" ] && [ "$(pushes)" = 1 ]; check $? "found on main by the fetch: no second push"
grep -q "landed after all" "$tmp/out.txt" && logged "landed after all"; check $? "it says so, and logs it"

echo "== refused =="
take "refuse ok" "ok"
push; check $(( $? == 1 ? 0 : 1 )) "exit 1"
[ "$(pushes)" = 1 ] && [ "$(remote)" != "$sha" ]; check $? "never tried again"
grep -q "non-fast-forward" "$tmp/out.txt" && logged "refused"; check $? "git's refusal shown and logged"

echo "== main moved during the wait =="
take "move ok" "ok"
push; check $(( $? == 1 ? 0 : 1 )) "exit 1"
[ "$(pushes)" = 1 ] && [ "$(remote)" != "$sha" ]; check $? "not pushed over it"
grep -q "main moved" "$tmp/out.txt" && logged "main moved"; check $? "it says main moved, and logs it"

echo "== the fetch fails =="
take "net ok" "fail"
push; check $(( $? == 1 ? 0 : 1 )) "exit 1"
[ "$(pushes)" = 1 ]; check $? "no second push"
logged "the fetch before try 2 failed"; check $? "logged"

echo "== the lock no longer the tree's =="
take "steal ok" "ok"
push; check $(( $? == 1 ? 0 : 1 )) "exit 1"
[ "$(pushes)" = 1 ] && [ "$(grep -c fetch "$tmp/calls")" = 0 ]; check $? "neither fetched nor pushed again"
logged "the lock not its own (other)"; check $? "logged"

echo "== release's freeze =="
take "ok"
lock release "main frozen for the cut"
push; check $(( $? == 3 ? 0 : 1 )) "exit 3, as land_lock.sh take's"
[ "$(pushes)" = 0 ]; check $? "nothing pushed"
take "freeze ok" "ok"
push; check $(( $? == 3 ? 0 : 1 )) "frozen between tries: exit 3"
[ "$(pushes)" = 1 ]; check $? "no second push"

echo "== the network down through every try =="
take "net net net ok" "ok ok ok"
push; check $(( $? == 1 ? 0 : 1 )) "exit 1"
[ "$(pushes)" = 3 ]; check $? "three tries, no fourth"
grep -q "down through 3 tries" "$tmp/out.txt"; check $? "it says so"

echo "== usage =="
take "ok"
sh "$here/tools/land_push.sh" t abc > "$tmp/out.txt" 2>&1; check $(( $? == 2 ? 0 : 1 )) "a short sha: exit 2"
sh "$here/tools/land_push.sh" "" "$sha" > "$tmp/out.txt" 2>&1; check $(( $? == 2 ? 0 : 1 )) "no tree: exit 2"
g reset -q --hard HEAD~1; echo off > f; g commit -qam "off main"; aside="$(git rev-parse HEAD)"
(cd "$tmp/other" && g fetch -q origin && g reset -q --hard origin/main && echo ahead >> f && g commit -qam ahead && g push -q origin HEAD:main) >/dev/null 2>&1
g fetch -q origin
sh "$here/tools/land_push.sh" t "$aside" > "$tmp/out.txt" 2>&1; check $(( $? == 2 ? 0 : 1 )) "a sha not on origin/main as fetched: exit 2"
[ "$(pushes)" = 0 ]; check $? "nothing pushed"

echo
[ "$failed" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL ($failed failed)"
[ "$failed" = 0 ]
