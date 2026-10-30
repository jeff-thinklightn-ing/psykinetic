# Adds a take to a sound slot from a third-party file (decision 268).
#   tools\sound_take.ps1 -Slot sfx.door_wood_open -From sonniss-gdc-2024 -Source <file> [-Original <text>]
#                        [-Start 1.2] [-Length 0.8] [-By <author>] [-Url <page>] [-License <name>] [-PeakDb -3] [-FadeOut 0.1] [-Rate 0.9]
#
# Cuts -Source (any format ffmpeg reads; -Start and -Length in seconds), trims silence off
# both ends of a one-shot, raises or lowers it to peak at -PeakDb dBFS if given (a quiet source), makes a loop or bed seamless (its end cross-faded into its
# start, -LoopFade s), makes a positional slot's take mono and any other stereo, encodes Ogg Vorbis, and
# stores it as the slot's next take, <slot>.ogg, <slot>.2.ogg ...:
#   a source stored "external" (Sonniss): in the sound library, <library>\takes\<slot>\,
#     then copied into the game by tools\sound_sync.ps1 (the library is $env:PSYK_SOUND_DIR,
#     else N:\assets\sound);
#   any other (Freesound CC0, say): in the repo, at the source's path, <slot>\.
# tools\sound_take.gd then lists it in art\audio\takes.json (its source, original and
# sha256) and rewrites docs\sound_status.md and THIRD_PARTY.md's sound block. Commit those
# (and a repo take) as usual. Never feed a Sonniss file to anything that trains or runs AI.
param(
	[Parameter(Mandatory = $true)][string]$Slot,
	[Parameter(Mandatory = $true)][string]$From,
	[Parameter(Mandatory = $true)][string]$Source,
	[string]$Original = '',
	[double]$Start = -1,
	[double]$Length = -1,
	[string]$By = '',
	[string]$Url = '',
	# The take's own licence, where its source's varies by sound (Freesound).
	[string]$License = '',
	# A loop's or bed's seam: this many seconds of its end cross-faded into its start.
	[double]$LoopFade = 2.0,
	# The take's loudest sample at this many dBFS (0 or above: left as the source has it).
	[double]$PeakDb = 1,
	# A one-shot cut out of a longer sound (-Length) fades to nothing over its last this many
	# seconds, so it ends before the source's ring or tail rather than on a step (732).
	[double]$FadeOut = 0,
	# Played at this share of its speed, slower and lower together (0.9: a tenth slower and
	# about two semitones down), for a voice that shouldn't read as a plain man's (735).
	[double]$Rate = 1,
	[string]$Library = $(if ($env:PSYK_SOUND_DIR) { $env:PSYK_SOUND_DIR } else { 'N:\assets\sound' }),
	[int]$TimeoutSeconds = 10
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '..\tests\godot_log.ps1')  # Its logs in build/logs (decision 664).

function Fail($message) {
	[Console]::Error.WriteLine("sound_take: $message")
	exit 1
}

$manifest = Get-Content (Join-Path $root 'art\audio\slots.json') -Raw | ConvertFrom-Json
$list = Get-Content (Join-Path $root 'art\audio\takes.json') -Raw | ConvertFrom-Json
$spec = $manifest.slots.PSObject.Properties[$Slot]
if ($null -eq $spec) { Fail "no slot $Slot in art\audio\slots.json" }
$spec = $spec.Value
$sourceEntry = $manifest.sources.PSObject.Properties[$From]
if ($null -eq $sourceEntry) { Fail "no source $From in art\audio\slots.json (sources: $(($manifest.sources.PSObject.Properties | ForEach-Object Name) -join ', '))" }
$sourceEntry = $sourceEntry.Value
if (-not (Test-Path -LiteralPath $Source)) { Fail "no file $Source" }
# A recording Jeff rejected is never cut again, for any slot (slots.json "rejected", 728).
foreach ($rejected in @($manifest.rejected)) {
	if ($null -ne $rejected -and $rejected.from -eq $From -and (Split-Path $Source -Leaf) -eq $rejected.file) {
		Fail "$($rejected.file) is rejected (it was $($rejected.was)): $($rejected.why)"
	}
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Fail 'ffmpeg is not on PATH' }

# Where it goes.
if ($sourceEntry.store -eq 'external') {
	. (Join-Path $PSScriptRoot 'sound_library.ps1')
	$reachable = Test-SoundLibrary $Library $TimeoutSeconds
	if ($reachable -eq 'timeout') {
		Fail "the sound library $Library did not answer within $TimeoutSeconds s. Is the NAS up and N: mapped?"
	}
	if ($reachable -ne 'yes') { Fail "no sound library at $Library" }
	$folder = Join-Path (Join-Path $Library 'takes') $Slot
} else {
	$folder = Join-Path (Join-Path $root (([string]$sourceEntry.path) -replace '^res://', '')) $Slot
}
$existing = @()
$slotTakes = $list.takes.PSObject.Properties[$Slot]
if ($null -ne $slotTakes) { $existing = @($slotTakes.Value) }
$index = $existing.Count + 1
$file = if ($index -eq 1) { "$Slot.ogg" } else { "$Slot.$index.ogg" }
$out = Join-Path $folder $file
if (Test-Path -LiteralPath $out) { Fail "$out is there already but takes.json doesn't list it: move it away or list it first" }
New-Item -ItemType Directory -Force $folder | Out-Null

# Cut, trim, encode.
$slow = ''
if ($Rate -ne 1) {
	if ($Rate -le 0) { Fail '-Rate must be above 0' }
	if ($spec.type -ne 'oneshot') { Fail '-Rate is for a one-shot' }
	$hz = [double](& ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $Source)
	$slow = "asetrate=$([math]::Round($hz * $Rate)),aresample=44100,"
}
$ffmpegArgs = @('-loglevel', 'error', '-y')
if ($Start -ge 0) { $ffmpegArgs += @('-ss', "$Start") }
$ffmpegArgs += @('-i', $Source)
# The output's length: slowed (-Rate), the cut lasts longer.
if ($Length -gt 0) { $ffmpegArgs += @('-t', "$($Length / $Rate)") }
# A gain to peak at -PeakDb: the cut's loudest sample measured first.
$gain = ''
if ($PeakDb -lt 0) {
	$measure = @('-hide_banner', '-nostats')
	if ($Start -ge 0) { $measure += @('-ss', "$Start") }
	$measure += @('-i', $Source)
	if ($Length -gt 0) { $measure += @('-t', "$Length") }
	$ErrorActionPreference = 'Continue'
	# astats, not volumedetect: volumedetect reads at 16 bits, so a float
	# source over full scale measured 0 dB and its take kept the overshoot.
	$report = (& ffmpeg @measure -af astats=measure_perchannel=none -f null - 2>&1 | ForEach-Object { "$_" }) -join "`n"
	$ErrorActionPreference = 'Stop'
	if ($report -notmatch 'Peak level dB: (-?[\d.]+)') { Fail "couldn't measure $Source's peak" }
	$gain = ",volume=$($PeakDb - [double]$Matches[1])dB"
}
$positional = -not ($spec.PSObject.Properties['positional'] -and $spec.positional -eq $false)
# Positional: mono (the 3D player places it). Flat: stereo, whatever the source
# (quad and ambisonic beds folded down).
$ffmpegArgs += @('-ac', $(if ($positional) { '1' } else { '2' }))
if ($spec.type -eq 'oneshot') {
	$trim = 'silenceremove=start_periods=1:start_threshold=-50dB'
	$fade = ''
	if ($FadeOut -gt 0) {
		if ($Length -le 0) { Fail '-FadeOut needs -Length' }
		$fade = "afade=t=out:st=$([math]::Max(0.0, $Length - $FadeOut)):d=$FadeOut,"
	}
	$ffmpegArgs += @('-af', "$fade$slow$trim,areverse,$trim,areverse$gain")
} else {
	# A loop or a bed loops without a seam: its last LoopFade seconds fade out
	# over its first fading in, and it ends where that overlap began.
	$whole = if ($Length -gt 0) { $Length } else {
		[double](& ffprobe -v error -show_entries format=duration -of csv=p=0 $Source) - [math]::Max($Start, 0)
	}
	$fade = [math]::Min($LoopFade, $whole / 4)
	$body = $whole - $fade
	$ffmpegArgs += @('-filter_complex', ("[0:a]asplit=3[a][b][c];" +
		"[a]atrim=0:$fade,asetpts=PTS-STARTPTS,afade=t=in:d=$fade[head];" +
		"[b]atrim=${fade}:$body,asetpts=PTS-STARTPTS[mid];" +
		"[c]atrim=${body}:$whole,asetpts=PTS-STARTPTS,afade=t=out:d=$fade[tail];" +
		"[tail][head]amix=inputs=2:normalize=0[seam];[seam][mid]concat=n=2:v=0:a=1$gain"))
}
$ffmpegArgs += @('-ar', '44100', '-c:a', 'libvorbis', '-q:a', '5', $out)
# A warning on stderr (a source's truncated last sample) is not a failure: its exit code says.
$ErrorActionPreference = 'Continue'
& ffmpeg @ffmpegArgs 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'Invalid PCM packet' } | ForEach-Object { [Console]::Error.WriteLine($_) }
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) { Fail "ffmpeg could not make $out" }

$hash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLower()
if (-not $Original) { $Original = Split-Path $Source -Leaf }
if ($Start -ge 0 -or $Length -gt 0) { $Original += " (from $([math]::Max($Start, 0)) s$(if ($Length -gt 0) { " for $Length s" }))" }
if ($Rate -ne 1) { $Original += " at $Rate speed" }

$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}
$ErrorActionPreference = 'Continue'
& $godot --log-file (Get-GodotLog 'sound_take') --headless --path $root --scene res://tools/sound_take.tscn -- "--slot=$Slot" "--file=$file" "--from=$From" "--original=$Original" "--sha256=$hash" "--by=$By" "--url=$Url" "--license=$License" 2>&1 |
	ForEach-Object { "$_" } | Where-Object { $_ -match '^sound_take|ERROR' }
$listed = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($listed -ne 0) { Fail "made $out, but couldn't list it in takes.json" }

if ($sourceEntry.store -eq 'external') {
	& (Join-Path $PSScriptRoot 'sound_sync.ps1') -Library $Library
	if ($LASTEXITCODE -ne 0) { Fail 'listed, but sound_sync failed' }
}
Write-Output "sound_take: $Slot take $index is $out ($hash)"
