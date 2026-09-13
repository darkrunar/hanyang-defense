# WP-001 end-to-end verification (Windows PowerShell 5.1+).
#
#   .\scripts\verify.ps1            tests + captures + release build + perf
#   .\scripts\verify.ps1 -Quick     tests + captures only
#
# Requires `godot` (4.7.stable) on PATH and, for build/perf, the matching
# Windows export template. Evidence lands in results\evidence\.
param([switch]$Quick)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$root = (Get-Location).Path
$evid = Join-Path $root "results\evidence"
New-Item -ItemType Directory -Force (Join-Path $evid "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid "perf") | Out-Null
New-Item -ItemType Directory -Force "build_out\windows" | Out-Null

Write-Host "== 1/5 headless test suite"
& godot --headless --path . --script res://tests/run_tests.gd -- "--report=$evid\test_report.txt"
if ($LASTEXITCODE -ne 0) { throw "test suite failed ($LASTEXITCODE)" }

Write-Host "== 2/5 map dump"
& godot --headless --path . --script res://game/tools/dump_map.gd | Out-File -Encoding utf8 (Join-Path $evid "map_dump.txt")

Write-Host "== 3/5 evidence captures (windowed)"
foreach ($sc in @("ac01", "ac02", "ac06")) {
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid\captures"
}

if ($Quick) { Write-Host "quick mode: skipping build and perf"; exit 0 }

Write-Host "== 4/5 release export"
& godot --headless --path . --export-release "Windows Desktop Release" build_out\windows\hanyang_defense_wp001.exe

Write-Host "== 5/5 performance (10 s warmup + 60 s measure, twice, with external memory sampling)"
foreach ($sc in @("move", "combat")) {
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out "results\evidence\perf\perf_${sc}_1000_release.json"
}
Write-Host "done. evidence in $evid"
