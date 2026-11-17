#!/usr/bin/env bash
# tests/test_ports.sh and tests/test_ports.ps1 give an unlisted folder the offset
# tests/port_hash_cases.txt names for it (278 amended (11)): 5600 + 200 * (the md5 of the name,
# lower-cased, mod 100), the offset tests/suite_test holds test_ports.gd's hashed() to, so the
# three agree. Each is run as its tests run it: from a folder of each case's name, holding a copy
# of tests/. A listed folder keeps the table's offset, and PSYKINETIC_TEST_PORT_OFFSET overrides
# both. No Godot.
set -u
cd "$(dirname "$0")/.."
unset PSYKINETIC_TEST_PORT_OFFSET
tmp="$(mktemp -d -t port_hash.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}
ps=""
command -v powershell.exe >/dev/null 2>&1 && ps=powershell.exe

# A folder of [name] holding tests/test_ports.* and the table; prints its folder.
make_folder() {
	mkdir -p "$tmp/$1/tests"
	cp tests/test_ports.sh tests/test_ports.ps1 tests/port_offsets.txt "$tmp/$1/tests/"
	printf '%s' "$tmp/$1"
}
sh_offset() { (cd "$1" && . tests/test_ports.sh && printf '%s' "$PORT_OFFSET"); }
ps_offset() {
	"$ps" -NoProfile -ExecutionPolicy Bypass -Command ". '$(cygpath -w "$1/tests/test_ports.ps1")'; [Console]::Out.Write(\$portOffset)" | tr -d '\r'
}

cases=0
while read -r name want; do
	case "$name" in "#"*|"") continue ;; esac
	cases=$((cases + 1))
	folder="$(make_folder "$name")"
	got="$(sh_offset "$folder")"
	check $([ "$got" = "$want" ]; echo $?) "test_ports.sh: $name gets $want ($got)"
	if [ -n "$ps" ]; then
		got="$(ps_offset "$folder")"
		check $([ "$got" = "$want" ]; echo $?) "test_ports.ps1: $name gets $want ($got)"
	fi
done <tests/port_hash_cases.txt
check $([ "$cases" -ge 6 ]; echo $?) "$cases cases read"

folder="$(make_folder perf)"
got="$(sh_offset "$folder")"
check $([ "$got" = 200 ]; echo $?) "test_ports.sh: a listed folder (perf) keeps the table's 200 ($got)"
got="$(PSYKINETIC_TEST_PORT_OFFSET=1234 sh_offset "$folder")"
check $([ "$got" = 1234 ]; echo $?) "test_ports.sh: PSYKINETIC_TEST_PORT_OFFSET overrides ($got)"
if [ -n "$ps" ]; then
	got="$(ps_offset "$folder")"
	check $([ "$got" = 200 ]; echo $?) "test_ports.ps1: a listed folder (perf) keeps the table's 200 ($got)"
	got="$(PSYKINETIC_TEST_PORT_OFFSET=1234 ps_offset "$folder")"
	check $([ "$got" = 1234 ]; echo $?) "test_ports.ps1: PSYKINETIC_TEST_PORT_OFFSET overrides ($got)"
else
	echo "  (no powershell.exe here: test_ports.ps1 not run)"
fi
grep -q "^tool_part port_hash_test bash tests/port_hash_test.sh" tests/land.sh
check $? "tests/land.sh runs this test"
echo
echo "RESULT: $([ $failed = 0 ] && echo PASS || echo FAIL) ($failed failed)"
[ $failed = 0 ]
