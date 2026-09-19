# Runs one WP-001 perf scenario on the release build and samples the process
# working set / private bytes once per second from outside the engine, because
# Godot release templates compile out their internal memory counters.
#
#   .\scripts\perf_with_memory.ps1 -Scenario combat -Out results\evidence\perf\perf_combat_1000_release.json
#
# Writes <Out> (from the game) and <Out>.memory.json (from this sampler).
param(
    [ValidateSet("move", "combat", "network_move", "network_combat", "collapse_move", "collapse_combat")][string]$Scenario = "move",
    [string]$Exe = "build_out\windows\hanyang_defense_wp001.exe",
    [int]$Warmup = 10,
    [int]$Measure = 60,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateSet("greybox", "sample")][string]$Art = "greybox",   # WP-005: rendering choice only (D-049)
    [string]$ArtDir = ""
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$outAbs = [System.IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force (Split-Path $outAbs) | Out-Null

$sha = (& git rev-parse HEAD 2>$null); if (-not $sha) { $sha = "unknown" }
# "-dirty" only when the code that goes into the exe differs from HEAD; evidence
# files under results/ are expected to change during a verification run.
$dirty = (& git status --porcelain --untracked-files=no -- game project.godot export_presets.cfg 2>$null)
$shaTag = if ($dirty) { "$sha-dirty" } else { $sha }
$args = @("--", "--perf", "--scenario=$Scenario", "--warmup=$Warmup", "--measure=$Measure", "--out=$outAbs", "--sha=$shaTag", "--art=$Art")
if ($ArtDir -ne "") { $args += "--art-dir=$ArtDir" }
# R-05: hash the executable that is about to run, independently of the game's
# own self-hash in the perf JSON manifest (the two must agree).
$exeItem = Get-Item (Resolve-Path $Exe)
$exeSha256 = (Get-FileHash -Algorithm SHA256 $exeItem.FullName).Hash.ToLower()
$proc = Start-Process -FilePath $exeItem.FullName -ArgumentList $args -PassThru
$samples = @()
$t0 = Get-Date
while (-not $proc.HasExited) {
    Start-Sleep -Seconds 1
    try {
        $p = Get-Process -Id $proc.Id -ErrorAction Stop
        $samples += [pscustomobject]@{
            t_s            = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
            working_set_mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
            private_mb     = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
            peak_ws_mb     = [math]::Round($p.PeakWorkingSet64 / 1MB, 1)
        }
    } catch { break }
}
$ws = $samples | Select-Object -ExpandProperty working_set_mb
$measureStart = $Warmup  # sampler t≈0 is process start; the game's window begins after warmup
$inWindow = $samples | Where-Object { $_.t_s -ge $measureStart }
$report = [ordered]@{
    scenario            = $Scenario
    art_mode            = $Art
    art_dir             = $ArtDir
    exe                 = $exeItem.Name          # basename only: no local paths in evidence
    exe_sha256          = $exeSha256
    exe_size_bytes      = $exeItem.Length
    exe_modified_utc    = $exeItem.LastWriteTimeUtc.ToString("o")
    implementation_sha  = $shaTag
    sampler             = "Get-Process WorkingSet64 / PrivateMemorySize64, 1 Hz, external"
    samples             = $samples.Count
    working_set_mb_min  = ($ws | Measure-Object -Minimum).Minimum
    working_set_mb_max  = ($ws | Measure-Object -Maximum).Maximum
    working_set_mb_at_measure_start = ($inWindow | Select-Object -First 1).working_set_mb
    working_set_mb_at_end           = ($samples | Select-Object -Last 1).working_set_mb
    private_mb_max      = ($samples | Select-Object -ExpandProperty private_mb | Measure-Object -Maximum).Maximum
    peak_ws_mb          = ($samples | Select-Object -ExpandProperty peak_ws_mb | Measure-Object -Maximum).Maximum
    exit_code           = $proc.ExitCode
    per_second          = $samples
}
$json = $report | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText("$outAbs.memory.json", $json, (New-Object System.Text.UTF8Encoding $false))  # UTF-8 without BOM
Write-Host ("MEMORY {0}: working set {1} -> {2} MB (min {3}, max {4}), private max {5} MB, samples {6}" -f `
    $Scenario, $report.working_set_mb_at_measure_start, $report.working_set_mb_at_end, `
    $report.working_set_mb_min, $report.working_set_mb_max, $report.private_mb_max, $samples.Count)
if ($proc.ExitCode -ne 0) { throw "game exited with code $($proc.ExitCode)" }
if (-not (Test-Path $outAbs)) { throw "game did not write $outAbs" }
# The game's self-hash of its executable must match the external hash.
$game = Get-Content $outAbs -Raw -Encoding UTF8 | ConvertFrom-Json
$selfSha = $game.manifest.executable.sha256
if ($selfSha -ne $exeSha256) { throw "executable hash mismatch: game reports '$selfSha', sampler computed '$exeSha256'" }
Write-Host ("EXE {0}: sha256 {1} ({2} bytes) matches the game's self-hash" -f $exeItem.Name, $exeSha256, $exeItem.Length)
