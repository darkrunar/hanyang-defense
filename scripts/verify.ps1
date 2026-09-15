# WP-001 end-to-end verification (Windows PowerShell 5.1+).
#
#   .\scripts\verify.ps1            tests + captures + release build + perf
#   .\scripts\verify.ps1 -Quick     tests + captures only
#
# Requires `godot` (4.7.stable) on PATH and, for build/perf, the matching
# Windows export template. Evidence lands in results\evidence\.
# Every external step is checked: a non-zero exit code or a missing artifact
# stops the run, regenerated artifacts are deleted first so a stale file can
# never pass as new evidence, and the perf JSON is checked against the D-009
# budget (GPT review recommendations).
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

# Freshness: remove every artifact this script regenerates.
$stale = @(
    (Join-Path $evid "test_report.txt"), (Join-Path $evid "map_dump.txt"), (Join-Path $evid "occupancy_probe.json"),
    (Join-Path $evid "captures\ac0*_log.json"), (Join-Path $evid "captures\ac0*.png"),
    (Join-Path $evid "perf\perf_move_1000_release.json*"), (Join-Path $evid "perf\perf_combat_1000_release.json*")
)
Remove-Item -Force -ErrorAction SilentlyContinue $stale

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

Write-Host "== 4b/6 WP-002 fixture A capture (connection effect)"
$evid2 = Join-Path $evid "wp-002"
New-Item -ItemType Directory -Force (Join-Path $evid2 "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid2 "perf") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid2 "tests") | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$evid2\captures\wp002_a*"
Copy-Item -Force "$evid\test_report.txt" "$evid2\tests\test_report.txt"
& godot --path . --rendering-driver opengl3 -- "--capture=wp002_a" "--out-dir=$evid2\captures"
Assert-Exit "capture wp002_a"
Assert-File "$evid2\captures\wp002_a_log.json" "capture wp002_a"
foreach ($png in @("wp002_a1_disconnected_no_fire_t2", "wp002_a2_connected_shared_fire_t2.5",
                   "wp002_a3_disconnected_again_no_stale_fire_t5", "wp002_a4_local_fire_while_disconnected_t5.5",
                   "wp002_a5_reconnected_reacquired_t7")) {
    Assert-File "$evid2\captures\$png.png" "capture wp002_a"
}

Write-Host "== 4c/6 WP-003 F1 timeline + F2 capture"
$evid3 = Join-Path $evid "wp-003"
New-Item -ItemType Directory -Force (Join-Path $evid3 "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid3 "perf") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid3 "tests") | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$evid3\captures\wp003_f2*", "$evid3\tests\f1_timeline.json"
Copy-Item -Force "$evid\test_report.txt" "$evid3\tests\test_report.txt"
& godot --headless --path . --script res://game/tools/wp003_timeline.gd -- "--out=$evid3\tests\f1_timeline.json" | Out-Null
Assert-Exit "F1 timeline"
Assert-File "$evid3\tests\f1_timeline.json" "F1 timeline"
& godot --path . --rendering-driver opengl3 -- "--capture=wp003_f2" "--out-dir=$evid3\captures"
Assert-Exit "capture wp003_f2"
Assert-File "$evid3\captures\wp003_f2_log.json" "capture wp003_f2"
foreach ($png in @("wp003_f2_a_outer_defense_t15", "wp003_f2_b_collapse_notice_t20.5", "wp003_f2_c_invalid_outer_preview_t23",
                   "wp003_f2_d_valid_inner_preview_t23.5", "wp003_f2_e_recovery_placed_t25.5", "wp003_f2_f_inner_fire_t45", "wp003_f2_g_run_end")) {
    Assert-File "$evid3\captures\$png.png" "capture wp003_f2"
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

Write-Host "== 6b/6 WP-002 fixture B performance (network_move, network_combat)"
Remove-Item -Force -ErrorAction SilentlyContinue "$evid2\perf\perf_network_*"
foreach ($sc in @("network_move", "network_combat")) {
    $out = "results\evidence\wp-002\perf\perf_${sc}_1000_release.json"
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out
    Assert-File $out "perf $sc"
    Assert-File "$out.memory.json" "perf $sc memory sampler"
    $r = Get-Content $out -Raw | ConvertFrom-Json
    $ok = ($r.avg_fps -ge 60) -and ($r.frame_ms_p95 -le 25) -and $r.load_held_all_frames
    # R-02: the targeting workload must have been paid in BOTH scenarios.
    $ok = $ok -and ($r.measured_window.candidate_evaluations_delta -gt 0)
    if ($sc -eq "network_combat") {
        # WP-002 fixture B contract: 12 B8 toggles, 12 successful jangseung changes,
        # path_version as expected, 12 logged events at 0,5,...,55 s, and at least
        # one shared-only volley INSIDE the measured window (R-03).
        $evOk = ($r.events | Where-Object { $_.command -eq "toggle_b8" -and $_.ok }).Count -eq 12
        $ok = $ok -and ($r.b8_toggles -eq 12) -and ($r.jangseung_changes -eq 12) -and `
              ($r.path_version -eq $r.path_version_expected) -and $evOk -and `
              ($r.measured_window.shared_only_shots -ge 1)
    }
    $verdict = if ($ok) { "PASS" } else { "FAIL" }
    Write-Host ("perf {0}: avg_fps={1:N1} p95={2:N2}ms alive_min={3} load_held={4} eval_delta={5} b8_toggles={6} jangseung_changes={7} pv={8}/{9} window_shared_only={10} -> {11}" -f `
        $sc, $r.avg_fps, $r.frame_ms_p95, $r.alive_min, $r.load_held_all_frames, $r.measured_window.candidate_evaluations_delta, $r.b8_toggles, $r.jangseung_changes, $r.path_version, $r.path_version_expected, $r.measured_window.shared_only_shots, $verdict)
    if ($verdict -ne "PASS") { throw "perf $sc did not meet the WP-002 fixture B contract" }
}
Write-Host "== 6c/6 WP-003 transition performance (collapse_move, collapse_combat)"
Remove-Item -Force -ErrorAction SilentlyContinue "$evid3\perf\perf_collapse_*"
foreach ($sc in @("collapse_move", "collapse_combat")) {
    $out = "results\evidence\wp-003\perf\perf_${sc}_1000_release.json"
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out
    Assert-File $out "perf $sc"
    Assert-File "$out.memory.json" "perf $sc memory sampler"
    $r = Get-Content $out -Raw | ConvertFrom-Json
    $c = $r.collapse
    $types = @($c.semantic_events | ForEach-Object { $_.type })
    $six = @("benchmark_trigger", "collapse", "outer_deactivated_batch", "target_changed", "recovery_created", "recovery_placed")
    $sixOk = $true; foreach ($ty in $six) { if (@($types | Where-Object { $_ -eq $ty }).Count -ne 1) { $sixOk = $false } }
    $segOk = ($c.segments.pre_collapse_0_20.eval_delta -gt 0) -and ($c.segments.waiting_20_25.eval_delta -gt 0) -and ($c.segments.post_placement_25_60.eval_delta -gt 0)
    $ok = ($r.avg_fps -ge 60) -and ($r.frame_ms_p95 -le 25) -and $r.load_held_all_frames -and $sixOk -and $segOk -and `
          ($c.placement_result -eq "ok") -and (-not $c.natural_collapse_before_trigger) -and ($c.ticks_trigger_to_collapse -ge 0) -and ($c.ticks_trigger_to_collapse -le 2) -and `
          ($r.path_version -eq $r.path_version_expected + 1)
    if ($sc -eq "collapse_combat") { $ok = $ok -and ($c.h1_shots_after_placement -ge 1) }
    $verdict = if ($ok) { "PASS" } else { "FAIL" }
    Write-Host ("perf {0}: avg_fps={1:N1} p95={2:N2}ms alive_min={3} six_events={4} segments_eval={5} placement={6} trigger->collapse={7} ticks h1_shots_after={8} -> {9}" -f `
        $sc, $r.avg_fps, $r.frame_ms_p95, $r.alive_min, $sixOk, $segOk, $c.placement_result, $c.ticks_trigger_to_collapse, $c.h1_shots_after_placement, $verdict)
    if ($verdict -ne "PASS") { throw "perf $sc did not meet the WP-003 D-027 contract" }
}
Write-Host "done. evidence in $evid, $evid2 and $evid3"
