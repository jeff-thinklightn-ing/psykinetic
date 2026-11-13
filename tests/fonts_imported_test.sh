#!/usr/bin/env bash
# tools/fonts_imported.sh (a part of tests/land.sh): a font whose .fontdata is missing gets one
# re-import, said; still missing after it, the part fails naming the font; never a second import.
# A fake project and a fake godot (it counts its calls), so no Godot runs here.
set -u
cd "$(dirname "$0")/.."
tool="$PWD/tools/fonts_imported.sh"
tmp="$(mktemp -d -t fonts_imported.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}

project() {
	rm -rf "$tmp/p"; mkdir -p "$tmp/p/art/fonts" "$tmp/p/.godot/imported" "$tmp/p/art/kit"
	printf '[remap]\n\nimporter="font_data_dynamic"\ntype="FontFile"\nuid="uid://a"\npath="res://.godot/imported/A.ttf-1.fontdata"\n' >"$tmp/p/art/fonts/A.ttf.import"
	# CRLF, as a checkout with autocrlf has it.
	printf '[remap]\r\n\r\nimporter="font_data_dynamic"\r\npath="res://.godot/imported/B[wght].ttf-2.fontdata"\r\n' >"$tmp/p/art/fonts/B[wght].ttf.import"
	# Not fonts' .fontdata: an image, and a font kept as a plain file.
	printf '[remap]\npath="res://.godot/imported/x.png-3.ctex"\n' >"$tmp/p/art/kit/x.png.import"
	printf '[remap]\nimporter="keep"\n' >"$tmp/p/art/fonts/C.otf.import"
	echo data >"$tmp/p/.godot/imported/A.ttf-1.fontdata"
	echo data >"$tmp/p/.godot/imported/B[wght].ttf-2.fontdata"
}
# $1: what the fake import does: "make" makes every .fontdata, "nothing" makes none.
fake() {
	cat >"$tmp/godot" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$tmp/calls"
[ "$1" = make ] && for f in A.ttf-1 'B[wght].ttf-2'; do echo data >"$tmp/p/.godot/imported/\$f.fontdata"; done
exit 0
EOF
	chmod +x "$tmp/godot"; : >"$tmp/calls"
}
calls() { wc -l <"$tmp/calls" | tr -d ' '; }

project; fake make
out="$(GODOT_PATH="$tmp/godot" bash "$tool" "$tmp/p")"; code=$?
check $([ $code = 0 ] && [ "$(calls)" = 0 ] && printf '%s' "$out" | grep -q "PASS  every font has its .fontdata"; echo $?) \
	"every .fontdata there: passes, no import ($out)"

project; rm "$tmp/p/.godot/imported/B[wght].ttf-2.fontdata"; fake make
out="$(GODOT_PATH="$tmp/godot" bash "$tool" "$tmp/p")"; code=$?
check $([ $code = 0 ] && [ "$(calls)" = 1 ] && printf '%s' "$out" | grep -qxF "re-imported: art/fonts/B[wght].ttf had no .fontdata" \
	&& ! printf '%s' "$out" | grep -q "A.ttf"; echo $?) "one missing (a CRLF .import): said, one re-import, passes ($(calls) import, $out)"
grep -q -- "--log-file .*font_import.log --headless --audio-driver Dummy --path . --import" "$tmp/calls"
check $? "the re-import is headless and silent ($(cat "$tmp/calls"))"

project; : >"$tmp/p/.godot/imported/A.ttf-1.fontdata"; fake make
out="$(GODOT_PATH="$tmp/godot" bash "$tool" "$tmp/p")"; code=$?
check $([ $code = 0 ] && printf '%s' "$out" | grep -qxF "re-imported: art/fonts/A.ttf had no .fontdata"; echo $?) "an empty .fontdata counts as missing"

project; rm "$tmp/p/.godot/imported/A.ttf-1.fontdata"; fake nothing
out="$(GODOT_PATH="$tmp/godot" bash "$tool" "$tmp/p")"; code=$?
check $([ $code = 1 ] && [ "$(calls)" = 1 ] && printf '%s' "$out" | grep -qxF "FAIL  art/fonts/A.ttf: still no .fontdata after one re-import"; echo $?) \
	"still missing after the re-import: fails naming it, one import only ($(calls) import, $out)"

grep -q "^part font_import bash tools/fonts_imported.sh" tests/land.sh
check $? "tests/land.sh runs it as its font_import part"
grep -q "& bash tools/fonts_imported.sh \. 2>&1" tests/land.ps1 && grep -q "\$failed += 'font_import'" tests/land.ps1
check $? "tests/land.ps1 runs it too, and fails on it"
echo
echo "RESULT: $([ $failed = 0 ] && echo PASS || echo FAIL) ($failed failed)"
[ $failed = 0 ]
