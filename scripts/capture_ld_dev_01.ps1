# LD-DEV-01 map reliability evidence (Windows PowerShell 5.1+).
#
#   .\scripts\capture_ld_dev_01.ps1 [-BaselineSha ddabd04]
#
# Refuses a dirty tree so every file names the commit it was made from.
# Output: results\evidence\level-development\LD-DEV-01\<yyyyMMdd>-<sha>\
#   probe_before.txt   map_contract_probe.gd on the baseline commit (temporary worktree)
#   probe_after.txt    the same probe on HEAD
#   tests_map.txt / tests_full.txt       focused map suite / full regression report
#   stage003_r01_route_compare.json      AC-M04 comparison (editor route model + core PathNetwork)
#   editor_*.png       map editor captures - route PREVIEW, not battle
#   preview_*.gif      route preview animation clips - PREVIEW, not battle
#   manifest.json      commit, engine, OS, per-file sha256
# Local absolute paths are replaced by <repo> / <appdata>; the run fails if any remain.
param([string]$BaselineSha = "ddabd04")
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Set-Location (Join-Path $PSScriptRoot "..")
$root = (Get-Location).Path
if (git status --porcelain) { throw "working tree is dirty: commit first so the evidence names the reviewed commit" }
$sha = (git rev-parse --short HEAD).Trim()
$runRel = "results/evidence/level-development/LD-DEV-01/$(Get-Date -Format yyyyMMdd)-$sha"
$run = Join-Path $root ($runRel -replace "/", "\")
if (Test-Path $run) { Remove-Item -Recurse -Force $run }
New-Item -ItemType Directory -Force $run | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$tmp = Join-Path $env:TEMP "ld_dev_01_$sha"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force $tmp | Out-Null

function Assert-Exit([string]$step) {
    if ($null -eq $LASTEXITCODE) { throw "${step}: no exit code" }
    if ($LASTEXITCODE -ne 0) { throw "$step failed (exit $LASTEXITCODE)" }
}
function Assert-File([string]$path, [string]$step) {
    if (-not (Test-Path $path)) { throw "$step produced no '$path'" }
    if ((Get-Item $path).Length -eq 0) { throw "$step produced an empty '$path'" }
}
function Save-Lines([string]$path, $lines) {
    [IO.File]::WriteAllText($path, (($lines | ForEach-Object { "$_" }) -join "`n") + "`n", $utf8)
}
function Invoke-Godot([string]$step, [string[]]$argv) {
    # Godot writes warnings to stderr; PowerShell 5.1 would turn them into
    # terminating errors under "Stop", so collect them as text here.
    $ErrorActionPreference = "Continue"
    $out = & godot @argv 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $script:LASTEXITCODE = $code
    Assert-Exit $step
    return $out
}

Write-Host "== 1/7 probe on the baseline $BaselineSha (temporary worktree) and on $sha"
$wt = Join-Path $tmp "baseline"
function Invoke-Quiet([scriptblock]$block) {
    # git and godot report progress on stderr; keep it out of the error stream.
    $ErrorActionPreference = "Continue"
    & $block 2>&1 | Out-Null
}
Invoke-Quiet { git worktree add --detach $wt $BaselineSha }
if (-not (Test-Path (Join-Path $wt "game"))) { throw "baseline worktree was not created" }
try {
    Copy-Item game\tools\map_contract_probe.gd (Join-Path $wt "game\tools\map_contract_probe.gd")
    Invoke-Quiet { godot --headless --path $wt --import }
    $before = Invoke-Godot "baseline probe" @("--headless", "--path", $wt, "--script", "res://game/tools/map_contract_probe.gd")
    Save-Lines (Join-Path $run "probe_before.txt") (@("# map_contract_probe.gd (from $sha) run on baseline $BaselineSha") + ($before | Where-Object { $_ -notmatch "^Godot Engine" }))
} finally {
    Invoke-Quiet { git worktree remove --force $wt }
}
$after = Invoke-Godot "probe" @("--headless", "--path", ".", "--script", "res://game/tools/map_contract_probe.gd")
Save-Lines (Join-Path $run "probe_after.txt") (@("# map_contract_probe.gd run on $sha") + ($after | Where-Object { $_ -notmatch "^Godot Engine" }))

Write-Host "== 2/7 focused map suite and full regression"
$map = Invoke-Godot "map suite" @("--headless", "--path", ".", "--script", "res://tests/run_stage_map_tests.gd")
Save-Lines (Join-Path $run "tests_map.txt") ($map | Where-Object { $_ -notmatch "^Godot Engine" })
$full = Join-Path $run "tests_full.txt"
& godot --headless --path . --script res://tests/run_tests.gd -- "--report=$full" | Out-Host
Assert-Exit "full suite"
Assert-File $full "full suite"
if (-not (Select-String -Path $full -Pattern "failed=0" -Quiet)) { throw "full report does not say failed=0" }

Write-Host "== 3/7 AC-M04 route comparison"
Invoke-Godot "compare" @("--headless", "--path", ".", "--script", "res://game/tools/ld_dev_01_compare.gd", "--", "--out=res://$runRel", "--sha=$sha") | Out-Host
Assert-File (Join-Path $run "stage003_r01_route_compare.json") "compare"

Write-Host "== 4/7 capture inputs"
Invoke-Godot "capture inputs" @("--headless", "--path", ".", "--script", "res://game/tools/ld_dev_01_compare.gd", "--", "--write-capture-inputs=user://ld_dev_01_capture") | Out-Host

$ctl = "res://game/maps/stages/stage_003_r01_control.json"
$var = "res://game/maps/stages/stage_003_r01.json"
$cap = "user://ld_dev_01_capture"
$shots = @(
    @("editor_01_control_flat", @("--map=$ctl")),
    @("editor_02_r01_before_legacy_terrain", @("--map=$cap/legacy_terrain.json", "--compare=$ctl")),
    @("editor_03_r01_after_revised", @("--map=$var", "--compare=$ctl")),
    @("editor_04_goal_refused_outside_31_30", @("--map=$ctl", "--goal=31,30")),
    @("editor_05_goal_refused_wall_24_17", @("--map=$ctl", "--goal=24,17")),
    @("editor_06_goal_refused_gate_31_25", @("--map=$ctl", "--goal=31,25")),
    @("editor_07_spawn_candidates_on_screen", @("--map=$cap/spawn_on_screen.json")),
    @("editor_08_wall_hole_24_17", @("--map=$cap/wall_hole.json")),
    @("editor_09_broken_file_refused", @("--map=$cap/broken_wave_count.json"))
)
Write-Host "== 5/7 editor captures ($($shots.Count), windowed)"
foreach ($s in $shots) {
    $png = Join-Path $run "$($s[0]).png"
    $argv = @("--path", ".", "res://game/tools/map_editor.tscn", "--") + $s[1] + @("--capture=$png")
    Invoke-Godot "capture $($s[0])" $argv | Out-Null
    Assert-File $png "capture $($s[0])"
}

Write-Host "== 6/7 route preview clips (movie maker PNG frames -> GIF)"
$clips = @(
    @("preview_r01_before_legacy_terrain", @("--map=$cap/legacy_terrain.json", "--compare=$ctl", "--preview")),
    @("preview_r01_after_revised", @("--map=$var", "--compare=$ctl", "--preview"))
)
foreach ($c in $clips) {
    $frames = Join-Path $tmp $c[0]
    New-Item -ItemType Directory -Force $frames | Out-Null
    $argv = @("--path", ".", "--write-movie", (Join-Path $frames "f.png"), "--fixed-fps", "20", "--quit-after", "120",
        "res://game/tools/map_editor.tscn", "--") + $c[1]
    Invoke-Godot "clip $($c[0])" $argv | Out-Null
    & python scripts\frames_to_gif.py $frames (Join-Path $run "$($c[0]).gif") --scale 0.5 --every 2 --fps-in 20 | Out-Host
    Assert-Exit "gif $($c[0])"
}

Write-Host "== 7/7 redact local paths and write the manifest"
$appdata = $env:APPDATA
foreach ($f in Get-ChildItem $run -File | Where-Object { $_.Extension -in ".txt", ".json" }) {
    $t = [IO.File]::ReadAllText($f.FullName, $utf8)
    foreach ($p in @($root, $root.Replace("\", "/"))) { $t = $t.Replace($p, "<repo>") }
    foreach ($p in @($appdata, $appdata.Replace("\", "/"))) { $t = $t.Replace($p, "<appdata>") }
    [IO.File]::WriteAllText($f.FullName, $t, $utf8)
}
$leak = Get-ChildItem $run -File | Where-Object { $_.Extension -in ".txt", ".json" } | Select-String -Pattern ([regex]::Escape($root)), ([regex]::Escape($root.Replace("\", "/"))), ([regex]::Escape($env:USERPROFILE)), ([regex]::Escape($env:USERPROFILE.Replace("\", "/")))
if ($leak) { throw "local path left in evidence: $($leak[0])" }
$files = @{}
foreach ($f in Get-ChildItem $run -File) { $files[$f.Name] = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower() }
$gpu = ((Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join "; ")
$engine = (& godot --version | Select-Object -First 1 | ForEach-Object { "$_".Trim() })
$os = (Get-CimInstance Win32_OperatingSystem).Caption
$manifest = [ordered]@{
    kind = "LD-DEV-01 map reliability evidence (editor route preview and headless checks; no battle run)"
    implementation_sha = $sha
    baseline_sha = $BaselineSha
    engine = $engine
    os = $os
    gpu = $gpu
    window = "project default 1920x1080 (editor scene), clips 20 fps fixed, 120 frames, GIF at 0.5 scale every 2nd frame"
    files = $files
}
[IO.File]::WriteAllText((Join-Path $run "manifest.json"), ($manifest | ConvertTo-Json -Depth 4), $utf8)
Remove-Item -Recurse -Force $tmp
Write-Host "evidence: $runRel"
