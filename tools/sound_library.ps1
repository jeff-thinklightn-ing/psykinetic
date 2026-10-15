# Dot-sourced by tools\sound_sync.ps1 and tools\sound_take.ps1: is the sound library there?
# The library is usually on the NAS (N:), and a share that's down can keep a plain Test-Path
# waiting a minute or more. Asked on a thread-pool thread instead: after $Seconds the answer
# is 'timeout', and the stuck thread doesn't keep PowerShell from exiting.
#   Test-SoundLibrary <path> <seconds>   'yes', 'no' or 'timeout'

if (-not ('PsykSoundProbe' -as [type])) {
	Add-Type -TypeDefinition @'
using System.IO;
using System.Threading.Tasks;
public static class PsykSoundProbe {
	public static string Exists(string path, int milliseconds) {
		Task<bool> probe = Task.Run(() => Directory.Exists(path));
		if (!probe.Wait(milliseconds)) return "timeout";
		return probe.Result ? "yes" : "no";
	}
}
'@
}

function Test-SoundLibrary([string]$Path, [int]$Seconds) {
	return [PsykSoundProbe]::Exists($Path, $Seconds * 1000)
}
