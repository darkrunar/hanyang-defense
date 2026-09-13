# WP-001 end-to-end verification (Windows PowerShell 5.1+).
#
#   .\scripts\verify.ps1            tests + captures + release build + perf
#   .\scripts\verify.ps1 -Quick     tests + captures only
#
# Requires `godot` (4.7.stable) on PATH and, for build/perf, the matching
# Windows export template. Evidence lands in results\evidence\.
# Every external step is checked: a non-zero exit code or a missing artifact
# stops the run (GPT review recommendation).
param([switch]$Quick)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$root = (Get-Location).Path
$evid = Join-Path $root "results\evidence"
New-Item -ItemType Directory -Force (Join-Path $evid "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid "perf") | Out-Null
New-Item -ItemType Directory -Force "build_out\windows" | Out-Null

function Assert-Exit([string]$step) {
    if ($LASTEXITCODE -ne 0) { throw "$step failed (exit $LASTEXITCODE)" }
}
function Assert-File([string]$path, [string]$step) {
    if (-not (Test-Path $path)) { throw "$step produced no '$path'" }
    if ((Get-Item $path).Length -eq 0) { throw "$step produced an empty '$path'" }
}

Write-Host "== 1/6 headless test suite"
& godot --headless --path . --script res://tests/run_tests.gd -- "--report=$evid\test_report.txt"
Assert-Exit "test suite"
Assert-File "$evid\test_report.txt" "test suite"
if (-not (Select-String -Path "$evid\test_report.txt" -Pattern "failed=0" -Quiet)) { throw "test report does not say failed=0" }

Write-Host "== 2/6 map dump"
& godot --headless --path . --script res://game/tools/dump_map.gd | Out-File -Encoding utf8 (Join-Path $evid "map_dump.txt")
Assert-Exit "map dump"
Assert-File "$evid\map_dump.txt" "map dump"

Write-Host "== 3/6 P-007 occupancy probe"
& godot --headless --path . --script res://game/tools/probe_occupancy.gd -- "--out=$evid\occupancy_probe.json"
Assert-Exit "occupancy probe"
Assert-File "$evid\occupancy_probe.json" "occupancy probe"

Write-Host "== 4/6 evidence captures (windowed)"
foreach ($sc in @("ac01", "ac02", "ac06")) {
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid\captures"
    Assert-Exit "capture $sc"
    Assert-File "$evid\captures\${sc}_log.json" "capture $sc"
}
foreach ($png in @("ac01_t30_1000_alive_three_routes", "ac02_a_reference_t30", "ac02_b_west_lane_blocked_t30",
                   "ac02_c_restored_t42", "ac06_a_before_t35", "ac06_b_after_t35")) {
    Assert-File "$evid\captures\$png.png" "capture"
}

if ($Quick) { Write-Host "quick mode: skipping build and perf"; exit 0 }

Write-Host "== 5/6 release export"
& godot --headless --path . --export-release "Windows Desktop Release" build_out\windows\hanyang_defense_wp001.exe
Assert-Exit "release export"
Assert-File "build_out\windows\hanyang_defense_wp001.exe" "release export"

Write-Host "== 6/6 performance (10 s warmup + 60 s measure, twice, with external memory sampling)"
foreach ($sc in @("move", "combat")) {
    $out = "results\evidence\perf\perf_${sc}_1000_release.json"
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out
    Assert-File $out "perf $sc"
    Assert-File "$out.memory.json" "perf $sc memory sampler"
    $r = Get-Content $out -Raw | ConvertFrom-Json
    $verdict = if ($r.avg_fps -ge 60 -and $r.frame_ms_p95 -le 25 -and $r.load_held_all_frames) { "PASS" } else { "FAIL" }
    Write-Host ("perf {0}: avg_fps={1:N1} p95={2:N2}ms alive_min={3} load_held={4} -> {5} (budget: avg>=60, p95<=25ms, alive_min>=target)" -f `
        $sc, $r.avg_fps, $r.frame_ms_p95, $r.alive_min, $r.load_held_all_frames, $verdict)
    if ($verdict -ne "PASS") { throw "perf $sc did not meet the D-009 budget" }
}
Write-Host "done. evidence in $evid"
