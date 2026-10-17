# Finds and fetches sounds on Freesound for the sound slots (decision 268's sources).
#   tools\freesound.ps1 search -Query "deer snort" [-Max 15] [-MaxSeconds 10] [-Sort downloads_desc] [-Page 2]
#   tools\freesound.ps1 authorize            the page to approve the app on, once (OAuth2)
#   tools\freesound.ps1 token -Code <code>   the code that page shows, for a day's access
#   tools\freesound.ps1 fetch -Id 12345 -Slot sfx.deer_snort
#   tools\freesound.ps1 take -Id 12345 -Slot sfx.deer_snort [-Start 0.2] [-Length 0.8] [-PeakDb -6]
#
# Only CC0 and CC BY sounds: search filters by licence, and fetch reads the sound's licence
# again and refuses any other (nothing non-commercial, no Sampling+). fetch keeps the
# original in the sound library's freesound\<slot>\<id>\, a folder of its own, beside a
# freesound.json naming its licence, maker and page; take cuts it into a take with
# tools\sound_take.ps1, credited (THIRD_PARTY.md lists each Freesound take's maker and page).
#
# The app's credentials come from the file $env:PSYK_FREESOUND_CREDENTIALS (or
# -Credentials): lines "Client_id: ..." and "Client_secret: ..." (quoted or not; the secret is
# the API key). They're never printed or written anywhere; the OAuth2 token is kept in
# $env:PSYK_FREESOUND_TOKEN, else %LOCALAPPDATA%\Psykinetic\freesound_token.json. Neither
# may be inside the checkout: the tool refuses a path there. Before using it, read the API's
# own terms in docs\licenses\freesound.md. Downloads are untrusted: nothing here runs or opens them but ffmpeg.
param(
	[Parameter(Mandatory = $true, Position = 0)][ValidateSet('search', 'authorize', 'token', 'fetch', 'take')][string]$Command,
	[string]$Query = '',
	[int]$Max = 15,
	[double]$MaxSeconds = 0,
	# Freesound's orders: score, downloads_desc, rating_desc, duration_asc ...
	[string]$Sort = 'score',
	[int]$Page = 1,
	[string]$Code = '',
	[int]$Id = 0,
	[string]$Slot = '',
	[double]$Start = -1,
	[double]$Length = -1,
	[double]$LoopFade = 2.0,
	[double]$PeakDb = 1,
	[string]$Credentials = $env:PSYK_FREESOUND_CREDENTIALS,
	[string]$TokenFile = $(if ($env:PSYK_FREESOUND_TOKEN) { $env:PSYK_FREESOUND_TOKEN } else { Join-Path $env:LOCALAPPDATA 'Psykinetic\freesound_token.json' }),
	[string]$Library = $(if ($env:PSYK_SOUND_DIR) { $env:PSYK_SOUND_DIR } else { 'N:\assets\sound' })
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$api = 'https://freesound.org/apiv2'
# The licences we take, by the URL Freesound gives each sound's, and what we call them.
$allowed = @{
	'creativecommons.org/publicdomain/zero/1.0/' = 'CC0 1.0'
	'creativecommons.org/licenses/by/4.0/' = 'CC BY 4.0'
	'creativecommons.org/licenses/by/3.0/' = 'CC BY 3.0'
}

function Fail($message) {
	[Console]::Error.WriteLine("freesound: $message")
	exit 1
}

# The credentials and the token never sit inside the checkout, where git could take them.
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\') + '\'
foreach ($secret in @($Credentials, $TokenFile)) {
	if ($secret -and [IO.Path]::GetFullPath($secret).StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
		Fail 'the credentials file and the token must be outside the checkout'
	}
}

function Read-Credentials {
	if (-not $Credentials) { Fail 'set PSYK_FREESOUND_CREDENTIALS (or -Credentials) to the credentials file' }
	if (-not (Test-Path -LiteralPath $Credentials)) { Fail 'the credentials file is not there' }
	$found = @{}
	foreach ($line in Get-Content -LiteralPath $Credentials) {
		if ($line -match '^\s*(Client_id|Client_secret)\s*[:=]\s*"?([^"\s]+)"?\s*$') { $found[$Matches[1].ToLower()] = $Matches[2] }
	}
	if (-not $found['client_id'] -or -not $found['client_secret']) { Fail 'the credentials file needs Client_id: and Client_secret: lines' }
	return $found
}

# A sound's licence as we name it, or '' when we don't take it.
function Licence-Name($url) {
	$key = ([string]$url) -replace '^https?://', ''
	if ($allowed.ContainsKey($key)) { return $allowed[$key] }
	return ''
}

function Access-Token {
	if (-not (Test-Path -LiteralPath $TokenFile)) { Fail "no access yet: run 'freesound.ps1 authorize', approve, then 'token -Code <code>'" }
	$token = Get-Content -LiteralPath $TokenFile -Raw | ConvertFrom-Json
	if ([DateTime]::UtcNow -lt [DateTime]::Parse($token.expires, $null, 'RoundtripKind')) { return $token.access_token }
	$c = Read-Credentials
	Save-Token (Invoke-RestMethod -Method Post -Uri "$api/oauth2/access_token/" -Body @{
		client_id = $c.client_id; client_secret = $c.client_secret; grant_type = 'refresh_token'; refresh_token = $token.refresh_token })
	return (Get-Content -LiteralPath $TokenFile -Raw | ConvertFrom-Json).access_token
}

function Save-Token($reply) {
	New-Item -ItemType Directory -Force (Split-Path $TokenFile -Parent) | Out-Null
	[ordered]@{
		access_token = $reply.access_token; refresh_token = $reply.refresh_token
		expires = [DateTime]::UtcNow.AddSeconds([int]$reply.expires_in - 60).ToString('o')
	} | ConvertTo-Json | Set-Content -LiteralPath $TokenFile -Encoding UTF8
}

function Sound-Folder { Join-Path (Join-Path (Join-Path $Library 'freesound') $Slot) "$Id" }

switch ($Command) {
	'search' {
		if (-not $Query) { Fail 'search needs -Query' }
		$c = Read-Credentials
		$filter = 'license:("Creative Commons 0" OR "Attribution")'
		if ($MaxSeconds -gt 0) { $filter += " duration:[0 TO $MaxSeconds]" }
		$found = Invoke-RestMethod -Uri "$api/search/text/" -Body @{
			query = $Query; filter = $filter; page_size = $Max; page = $Page; sort = $Sort; token = $c.client_secret
			fields = 'id,name,username,license,duration,channels,samplerate,type,avg_rating,num_ratings,num_downloads,tags'
		}
		"$($found.count) found; the first $([math]::Min($Max, $found.count)):"
		$found.results | ForEach-Object {
			$licence = Licence-Name $_.license
			[pscustomobject]@{
				id = $_.id; licence = $(if ($licence) { $licence } else { "NOT OURS ($($_.license))" })
				s = [math]::Round($_.duration, 2); ch = $_.channels; hz = $_.samplerate; type = $_.type
				rating = "$([math]::Round($_.avg_rating, 1))/$($_.num_ratings)"; dl = $_.num_downloads
				by = $_.username; name = $_.name; tags = (@($_.tags) | Select-Object -First 8) -join ' '
			}
		} | Format-Table -AutoSize -Wrap | Out-String -Width 400
	}
	'authorize' {
		$c = Read-Credentials
		"Open, approve, and pass back the code the page shows (it lasts 10 minutes):"
		"$api/oauth2/authorize/?client_id=$($c.client_id)&response_type=code&state=psykinetic"
	}
	'token' {
		if (-not $Code) { Fail 'token needs -Code' }
		$c = Read-Credentials
		Save-Token (Invoke-RestMethod -Method Post -Uri "$api/oauth2/access_token/" -Body @{
			client_id = $c.client_id; client_secret = $c.client_secret; grant_type = 'authorization_code'; code = $Code })
		"freesound: access kept in $TokenFile (renewed from it when it runs out)"
	}
	'fetch' {
		if ($Id -le 0 -or -not $Slot) { Fail 'fetch needs -Id and -Slot' }
		$folder = Sound-Folder
		if (Test-Path -LiteralPath (Join-Path $folder 'freesound.json')) { "freesound: $Id is in $folder already"; break }
		$headers = @{ Authorization = "Bearer $(Access-Token)" }
		$sound = Invoke-RestMethod -Uri "$api/sounds/$Id/" -Headers $headers -Body @{ fields = 'id,name,username,license,url,type,duration,channels,samplerate' }
		$licence = Licence-Name $sound.license
		if (-not $licence) { Fail "$Id is under $($sound.license): not a licence we take" }
		# A file name of our own: the original's name is untrusted.
		$type = ([string]$sound.type) -replace '[^a-z0-9]', ''
		if (-not $type) { $type = 'bin' }
		New-Item -ItemType Directory -Force $folder | Out-Null
		$file = Join-Path $folder "$Id.$type"
		try {
			Invoke-WebRequest -Uri "$api/sounds/$Id/download/" -Headers $headers -OutFile $file -UseBasicParsing
		} catch {
			Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
			Fail "couldn't download $Id ($($_.Exception.Message))"
		}
		# Two calls a fetch; Freesound allows 30 a minute (its terms: no excessive volume).
		Start-Sleep -Seconds 4
		[ordered]@{
			id = $sound.id; name = $sound.name; by = $sound.username; license = $licence; license_url = $sound.license
			url = $sound.url; file = "$Id.$type"; duration = $sound.duration; channels = $sound.channels
			samplerate = $sound.samplerate; fetched = (Get-Date).ToString('yyyy-MM-dd')
		} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'freesound.json') -Encoding UTF8
		"freesound: $Id ($licence, by $($sound.username)) is $file"
	}
	'take' {
		if ($Id -le 0 -or -not $Slot) { Fail 'take needs -Id and -Slot' }
		$meta = Join-Path (Sound-Folder) 'freesound.json'
		if (-not (Test-Path -LiteralPath $meta)) { Fail "fetch $Id for $Slot first" }
		$sound = Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json
		& (Join-Path $PSScriptRoot 'sound_take.ps1') -Slot $Slot -From freesound -Source (Join-Path (Sound-Folder) $sound.file) `
			-Original "freesound $($sound.id): $($sound.name)" -By $sound.by -Url $sound.url -License $sound.license `
			-Start $Start -Length $Length -LoopFade $LoopFade -PeakDb $PeakDb -Library $Library
		exit $LASTEXITCODE
	}
}
