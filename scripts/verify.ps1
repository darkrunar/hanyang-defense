# WP-001 end-to-end verification (Windows PowerShell 5.1+).
#
#   .\scripts\verify.ps1            tests + captures + release build + perf
#   .\scripts\verify.ps1 -Quick     tests + captures only
#   .\scripts\verify.ps1 -Wp003     tests + WP-003 evidence only (F1/F3 ledgers, F2/F3 captures,
#                                    release build, collapse perf); the approved WP-001/002
#                                    evidence files are left untouched
#   .\scripts\verify.ps1 -Wp008     tests + WP-008 evidence only (build-mode captures at two
#                                    resolutions, AC-09 strategy comparison, release build, the four
#                                    build_* transition benchmarks); approved evidence untouched
#
# Requires `godot` (4.7.stable) on PATH and, for build/perf, the matching
# Windows export template. Evidence lands in results\evidence\.
# Every external step is checked: a non-zero exit code or a missing artifact
# stops the run, regenerated artifacts are deleted first so a stale file can
# never pass as new evidence, and the perf JSON is checked against the D-009
# budget (GPT review recommendations).
param([switch]$Quick, [switch]$Wp003, [switch]$Wp004, [switch]$Wp005, [switch]$Wp008)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$root = (Get-Location).Path
$evid = Join-Path $root "results\evidence"
New-Item -ItemType Directory -Force (Join-Path $evid "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid "perf") | Out-Null
New-Item -ItemType Directory -Force "build_out\windows" | Out-Null

function Assert-Exit([string]$step) {
    # godot.exe is a GUI-subsystem binary: every call below is piped (| Out-Host)
    # so PowerShell waits for it and $LASTEXITCODE is really set.
    if ($null -eq $LASTEXITCODE) { throw "${step}: no exit code (the process was not awaited)" }
    if ($LASTEXITCODE -ne 0) { throw "$step failed (exit $LASTEXITCODE)" }
}
function Assert-File([string]$path, [string]$step) {
    if (-not (Test-Path $path)) { throw "$step produced no '$path'" }
    if ((Get-Item $path).Length -eq 0) { throw "$step produced an empty '$path'" }
}

if ($Wp008) { $Wp005 = $true }   # -Wp008 = WP-008 build-mode captures + AC-09 comparison + build_* perf under wp-008/; approved WP-001..005 evidence untouched
if ($Wp005) { $Wp004 = $true }   # -Wp005 = WP-005 art pipeline captures (greybox / sample, dev fixture) + perf per art mode under wp-005/; approved WP-001..004 evidence untouched
if ($Wp004) { $Wp003 = $true }   # -Wp004 = WP-004 captures + new release collapse perf under wp-004/; approved WP-001/002/003 evidence untouched
$evid3 = Join-Path $evid "wp-003"
$evid4 = Join-Path $evid "wp-004"
$evid5 = Join-Path $evid "wp-005"
New-Item -ItemType Directory -Force (Join-Path $evid3 "tests") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid4 "tests") | Out-Null
if ($Wp005) { New-Item -ItemType Directory -Force (Join-Path $evid5 "tests") | Out-Null }
$evid8 = "$root\results\evidence\wp-008"
if ($Wp008) { foreach ($d in @("tests", "captures", "compare", "perf")) { New-Item -ItemType Directory -Force (Join-Path $evid8 $d) | Out-Null } }
$report = if ($Wp008) { "$evid8\tests\test_report.txt" } elseif ($Wp005) { "$evid5\tests\test_report.txt" } elseif ($Wp004) { "$evid4\tests\test_report.txt" } elseif ($Wp003) { "$evid3\tests\test_report.txt" } else { "$evid\test_report.txt" }

# Freshness: remove every artifact this script regenerates.
$stale = @(
    $report, (Join-Path $evid "map_dump.txt"), (Join-Path $evid "occupancy_probe.json"),
    (Join-Path $evid "captures\ac0*_log.json"), (Join-Path $evid "captures\ac0*.png"),
    (Join-Path $evid "perf\perf_move_1000_release.json*"), (Join-Path $evid "perf\perf_combat_1000_release.json*")
)
if ($Wp003) { $stale = @($report) }
Remove-Item -Force -ErrorAction SilentlyContinue $stale

Write-Host "== 1/6 headless test suite"
& godot --headless --path . --script res://tests/run_tests.gd -- "--report=$report" | Out-Host
Assert-Exit "test suite"
Assert-File $report "test suite"
if (-not (Select-String -Path $report -Pattern "failed=0" -Quiet)) { throw "test report does not say failed=0" }

if (-not $Wp003) {
Write-Host "== 2/6 map dump"
& godot --headless --path . --script res://game/tools/dump_map.gd | Out-File -Encoding utf8 (Join-Path $evid "map_dump.txt")
Assert-Exit "map dump"
Assert-File "$evid\map_dump.txt" "map dump"

Write-Host "== 3/6 P-007 occupancy probe"
& godot --headless --path . --script res://game/tools/probe_occupancy.gd -- "--out=$evid\occupancy_probe.json" | Out-Host
Assert-Exit "occupancy probe"
Assert-File "$evid\occupancy_probe.json" "occupancy probe"

Write-Host "== 4/6 evidence captures (windowed)"
foreach ($sc in @("ac01", "ac02", "ac06")) {
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid\captures" | Out-Host
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
& godot --path . --rendering-driver opengl3 -- "--capture=wp002_a" "--out-dir=$evid2\captures" | Out-Host
Assert-Exit "capture wp002_a"
Assert-File "$evid2\captures\wp002_a_log.json" "capture wp002_a"
foreach ($png in @("wp002_a1_disconnected_no_fire_t2", "wp002_a2_connected_shared_fire_t2.5",
                   "wp002_a3_disconnected_again_no_stale_fire_t5", "wp002_a4_local_fire_while_disconnected_t5.5",
                   "wp002_a5_reconnected_reacquired_t7")) {
    Assert-File "$evid2\captures\$png.png" "capture wp002_a"
}
}   # end of the WP-001/002 block skipped by -Wp003

if (-not $Wp004) {   # -Wp004 leaves the approved WP-003 evidence files untouched
Write-Host "== 4c/6 WP-003 F1 timeline + F3 A/B ledger + F2 / F3 captures"
New-Item -ItemType Directory -Force (Join-Path $evid3 "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid3 "perf") | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$evid3\captures\wp003_f2*", "$evid3\captures\wp003_f3*", "$evid3\tests\f1_timeline.json", "$evid3\tests\f3_ab.json"
if (-not $Wp003) { Copy-Item -Force "$evid\test_report.txt" "$evid3\tests\test_report.txt" }
& godot --headless --path . --script res://game/tools/wp003_timeline.gd -- "--out=$evid3\tests\f1_timeline.json" | Out-Null
Assert-Exit "F1 timeline"
Assert-File "$evid3\tests\f1_timeline.json" "F1 timeline"
$f1 = Get-Content "$evid3\tests\f1_timeline.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if ($f1.summary.run -ne "WON" -or $f1.summary.collapse_tick -ne -1) { throw "F1 timeline is not a WON-without-collapse run (run=$($f1.summary.run), collapse_tick=$($f1.summary.collapse_tick))" }
# R-06: independent F3 A/B ledger (exit 1 when the pre-placement states differ).
& godot --headless --path . --script res://game/tools/wp003_f3_evidence.gd -- "--out=$evid3\tests\f3_ab.json" | Out-Null
Assert-Exit "F3 A/B ledger"
Assert-File "$evid3\tests\f3_ab.json" "F3 A/B ledger"
$f3 = Get-Content "$evid3\tests\f3_ab.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $f3.state_identical_before_placement) { throw "F3: A/B states differ before the placement" }
if ($f3.summary.b_shared_only -lt 1 -or $f3.summary.kills_b_minus_a -lt 6 -or $f3.summary.core_damage_a_minus_b -lt 6) { throw "F3 pass lines not met: $($f3.summary | ConvertTo-Json -Compress)" }
foreach ($sc in @("wp003_f2", "wp003_f3a", "wp003_f3b")) {
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid3\captures" | Out-Host
    Assert-Exit "capture $sc"
    Assert-File "$evid3\captures\${sc}_log.json" "capture $sc"
}
foreach ($png in @("wp003_f2_a_outer_defense_t15", "wp003_f2_b_collapse_notice_t20.5", "wp003_f2_c_invalid_outer_preview_t23",
                   "wp003_f2_d_valid_inner_preview_t23.5", "wp003_f2_e_recovery_placed_t25.5", "wp003_f2_f_inner_fire_t45", "wp003_f2_g_run_end",
                   "wp003_f3a_1_collapsed_t0", "wp003_f3a_2_placed_t5", "wp003_f3a_3_first_observation_t5.02", "wp003_f3a_5_end_t35",
                   "wp003_f3b_1_collapsed_t0", "wp003_f3b_2_placed_t5", "wp003_f3b_3_first_observation_t5.02", "wp003_f3b_4_first_h1_shot", "wp003_f3b_5_end_t35")) {
    Assert-File "$evid3\captures\$png.png" "capture wp003"
}
if (Test-Path "$evid3\captures\wp003_f3a_4_first_h1_shot.png") { throw "F3 A: H1 must not fire (it has no connection and no local target)" }
}   # end of the WP-003 evidence block skipped by -Wp004

if (-not $Wp005) {   # -Wp005 leaves the approved WP-004 evidence files untouched
Write-Host "== 4d/6 WP-004 menu flow captures (1920x1080 and 1280x720, throwaway settings file)"
New-Item -ItemType Directory -Force (Join-Path $evid4 "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid4 "perf") | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$evid4\captures\wp004_ui*", "$evid4\captures\settings_capture.cfg"
if ($report -ne "$evid4\tests\test_report.txt") { Copy-Item -Force $report "$evid4\tests\test_report.txt" }
foreach ($sc in @("wp004_ui", "wp004_ui_720")) {
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid4\captures" "--settings=$evid4\captures\settings_capture.cfg" | Out-Host
    Assert-Exit "capture $sc"
    Assert-File "$evid4\captures\${sc}_log.json" "capture $sc"
    foreach ($n in @("01_title", "02_settings_from_title", "03_playing_t12", "04_paused", "05_settings_from_pause", "06_confirm_restart",
                     "07_confirm_to_title", "08_confirm_from_r_after_collapse", "09_result_lost", "10_result_won", "11_title_again")) {
        Assert-File "$evid4\captures\${sc}_$n.png" "capture $sc"
    }
    $log = Get-Content "$evid4\captures\${sc}_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $states = @($log | Where-Object { $_.ui_state } | ForEach-Object { "$($_.label)=$($_.ui_state)" })
    Write-Host ("capture {0}: {1}" -f $sc, ($states -join " "))
    $expect = @{ launch="TITLE"; settings_esc_returns_to_title="TITLE"; esc_pauses="PAUSED"; settings_esc_returns_to_pause="PAUSED";
                 confirm_cancel_returns_to_pause="PAUSED"; confirm_esc_cancels_only="PAUSED"; pause_esc_resumes="PLAYING";
                 r_while_playing_opens_confirm="CONFIRM"; confirm_cancel_resumes_playing="PLAYING"; r_on_result_restarts_immediately="PLAYING";
                 result_to_title_immediate="TITLE" }
    foreach ($k in $expect.Keys) {
        $row = $log | Where-Object { $_.label -eq $k } | Select-Object -First 1
        if ($null -eq $row -or $row.ui_state -ne $expect[$k]) { throw "capture ${sc}: state after '$k' should be $($expect[$k]) (got $($row.ui_state))" }
    }
    $results = @($log | Where-Object { $_.wait_result })
    if ($results.Count -ne 2 -or $results[0].result.outcome -ne "LOST" -or $results[1].result.outcome -ne "WON") { throw "capture ${sc}: expected a LOST then a WON result" }
    # R-01 release fence (D-047): two probes with real events (before the collapse: no recovery right,
    # so both presses are refused by the battle; in the WON run: refused while Esc is held, placed after).
    $probes = @($log | Where-Object { $_.fence_probe })
    if ($probes.Count -ne 2) { throw "capture ${sc}: expected 2 fence probes (got $($probes.Count))" }
    foreach ($pr in $probes) {
        if ($pr.after_esc_press -ne "PAUSED" -or $pr.after_second_esc_press -ne "PLAYING") { throw "capture ${sc}: fence probe states $($pr.after_esc_press)/$($pr.after_second_esc_press)" }
        if (@($pr.fence_after_resume) -notcontains "Escape") { throw "capture ${sc}: fence should hold Escape after the resume press" }
        if ($pr.lmb_while_esc_held_accepted_delta -ne 0 -or $pr.lmb_while_esc_held_recovery_placed) { throw "capture ${sc}: LMB while Esc held must not place" }
        if (@($pr.fence_after_esc_release).Count -ne 0) { throw "capture ${sc}: fence must be empty after the Esc release" }
    }
    if ($probes[1].lmb_after_release_accepted_delta -ne 1 -or -not $probes[1].recovery_placed) { throw "capture ${sc}: the new press after the release must place H1" }
    if ($probes[0].lmb_after_release_accepted_delta -ne 0) { throw "capture ${sc}: no recovery right before the collapse, nothing to place" }
    Write-Host ("capture {0}: fence probes ok (held: delta {1}/{2}; after release: delta {3}/{4}, placed {5})" -f $sc,
        $probes[0].lmb_while_esc_held_accepted_delta, $probes[1].lmb_while_esc_held_accepted_delta,
        $probes[0].lmb_after_release_accepted_delta, $probes[1].lmb_after_release_accepted_delta, $probes[1].recovery_placed)
}
}   # end of the WP-004 capture block skipped by -Wp005

if ($Wp008) {
# GPT review R-01 (PR #13): evidence must come from a committed source tree. The perf
# JSON and the release capture logs carry `implementation_sha`; a "-dirty" tag there
# cannot be tied to the reviewed commit, so the run refuses to start on a dirty tree.
$wp8Dirty = (& git status --porcelain --untracked-files=no -- game project.godot export_presets.cfg 2>$null)
if ($wp8Dirty) { throw "-Wp008: commit the game tree first (dirty: $($wp8Dirty -join '; ')). Evidence must name a clean implementation sha." }
$wp8Sha = (& git rev-parse HEAD).Trim()
Write-Host "== 4f/6 WP-008: clean tree at $wp8Sha (build-mode captures run on the release exe in step 6f)"

Write-Host "== 4g/6 WP-008 AC-09 strategy comparison (headless, same seed: no construction vs planned strategies)"
Remove-Item -Force -ErrorAction SilentlyContinue "$evid8\compare\ac09_compare.json"
& godot --headless --path . --script res://game/tools/wp008_compare.gd -- "--out=$evid8\compare\ac09_compare.json" | Out-Host
Assert-Exit "ac09 compare"
Assert-File "$evid8\compare\ac09_compare.json" "ac09 compare"
$cmp = Get-Content "$evid8\compare\ac09_compare.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($cmp.winning_strategies).Count -lt 1) { throw "ac09: no winning construction strategy" }
foreach ($name in ($cmp.summary | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name })) {
    $r = $cmp.summary.$name
    if (-not $r.balance_ok) { throw "ac09: ledger invariant broken in strategy $name" }
    if ($r.supply_end -ne (240 + $r.earned_kills + $r.earned_waves - $r.spent)) { throw "ac09: formula broken in strategy $name" }
}
Write-Host ("ac09: winning strategies {0}; no_build {1} collapse {2:N1}s core {3}" -f (@($cmp.winning_strategies) -join ","), $cmp.summary.no_build.outcome, $cmp.summary.no_build.collapse_sim_time, $cmp.summary.no_build.core_hp)
} else {
if ($Wp005) {
Write-Host "== 4e/6 WP-005 art pipeline captures (greybox / sample with the dev fixture, 1920x1080 and 1280x720)"
# The fixture is programmatic placeholder art in the ArtSet file contract (NOT game assets):
# it proves the loader / atlas / fx / capture pipeline and the greybox == sample battle state.
New-Item -ItemType Directory -Force (Join-Path $evid5 "captures") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $evid5 "perf") | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$evid5\captures\wp005_*"
& godot --headless --path . --script res://game/tools/wp005_dev_fixture.gd | Out-Host
Assert-Exit "wp005 dev fixture"
$fixture = "user://wp005_art_fixture"
$logs = @{}
# greybox / sample(fixture) prove the pipeline; assets = --art=sample on the shipped
# assets/art/wp005 directory (D-050), the evidence for the reviewed files.
foreach ($art in @("greybox", "sample", "assets")) {
    foreach ($size in @("", "_720")) {
        $sc = "wp005_${art}${size}"
        $extra = @("--art=$(if ($art -eq 'greybox') { 'greybox' } else { 'sample' })")
        if ($art -eq "sample") { $extra += "--art-dir=$fixture" }
        & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid5\captures" @extra | Out-Host
        Assert-Exit "capture $sc"
        Assert-File "$evid5\captures\${sc}_log.json" "capture $sc"
        foreach ($n in @("a_dense_t15", "b_collapse_t20.5", "c_invalid_preview_t23", "d_valid_preview_t23.5", "e_recovery_placed_t25.5", "f_inner_fire_t45", "g_run_end")) {
            Assert-File "$evid5\captures\${sc}_$n.png" "capture $sc"
        }
        $logs[$sc] = Get-Content "$evid5\captures\${sc}_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}
foreach ($size in @("", "_720")) {
    # AC-05 (pipeline): the structured battle state is identical in both rendering modes at every checkpoint.
    $g = $logs["wp005_greybox$size"]; $s = $logs["wp005_sample$size"]
    foreach ($label in @("initial", "before_collapse", "after_collapse", "after_recovery")) {
        $gs = $g | Where-Object { $_.state_log -eq $label } | Select-Object -First 1
        $ss = $s | Where-Object { $_.state_log -eq $label } | Select-Object -First 1
        if ($null -eq $gs -or $null -eq $ss) { throw "capture wp005${size}: state_log '$label' missing" }
        if ($gs.state_hash -ne $ss.state_hash -or $gs.tick -ne $ss.tick) { throw "capture wp005${size}: state differs at '$label' (greybox $($gs.state_hash) vs sample $($ss.state_hash))" }
        if (($gs.full_state | ConvertTo-Json -Depth 20 -Compress) -ne ($ss.full_state | ConvertTo-Json -Depth 20 -Compress)) { throw "capture wp005${size}: full_state differs at '$label'" }
    }
    $ge = $g | Where-Object { $_.capture -eq "wp005_greybox${size}_g_run_end" } | Select-Object -First 1
    $se = $s | Where-Object { $_.capture -eq "wp005_sample${size}_g_run_end" } | Select-Object -First 1
    if ($ge.run.run -ne $se.run.run) { throw "capture wp005${size}: different outcome ($($ge.run.run) vs $($se.run.run))" }
    # sample side: every fixture file loaded, sprites and tiles drawn, fx follow real events (fire == impact == volleys, 1 collapse)
    $launch = $s | Where-Object { $_.art_log -eq "launch" } | Select-Object -First 1
    $t45 = $s | Where-Object { $_.art_log -eq "t45" } | Select-Object -First 1
    if ($launch.art.loaded_count -ne $launch.art.contract_count -or $launch.art.missing_count -ne 0) { throw "capture wp005_sample${size}: fixture not fully loaded ($($launch.art.loaded_count)/$($launch.art.contract_count))" }
    if (-not $launch.enemy_sprites) { throw "capture wp005_sample${size}: enemies not rendered from the atlas" }
    if ($t45.fx.created_by_kind.fire -lt 1 -or $t45.fx.created_by_kind.fire -ne $t45.fx.created_by_kind.impact -or $t45.fx.created_by_kind.collapse -ne 1) { throw "capture wp005_sample${size}: fx counts do not follow the events ($($t45.fx.created_by_kind | ConvertTo-Json -Compress))" }
    $a = $s | Where-Object { $_.capture -eq "wp005_sample${size}_a_dense_t15" } | Select-Object -First 1
    if ($a.sample_tiles_drawn.skipped -ne 0 -or $a.sample_tiles_drawn.ground -lt 1 -or ($a.sprites_drawn.PSObject.Properties | Measure-Object).Count -lt 5) { throw "capture wp005_sample${size}: tiles / sprites not drawn" }
    Write-Host ("capture wp005{0}: greybox == sample at 4 checkpoints, outcome {1}; sample fx fire={2} impact={3} collapse={4} despawn={5}, tiles ground={6} edge={7} wall={8} roof={9} gate={10}" -f $size, $se.run.run,
        $t45.fx.created_by_kind.fire, $t45.fx.created_by_kind.impact, $t45.fx.created_by_kind.collapse, $t45.fx.created_by_kind.enemy_despawn,
        $a.sample_tiles_drawn.ground, $a.sample_tiles_drawn.edge, $a.sample_tiles_drawn.wall, $a.sample_tiles_drawn.roof, $a.sample_tiles_drawn.gate)
    # reviewed assets: same battle as the grey box; every shipped contract file loaded, the rest reported missing; facility sprites drawn
    $r5 = $logs["wp005_assets$size"]
    foreach ($label in @("initial", "before_collapse", "after_collapse", "after_recovery")) {
        $gs = $g | Where-Object { $_.state_log -eq $label } | Select-Object -First 1
        $rs = $r5 | Where-Object { $_.state_log -eq $label } | Select-Object -First 1
        if ($null -eq $rs -or $gs.state_hash -ne $rs.state_hash -or $gs.tick -ne $rs.tick) { throw "capture wp005_assets${size}: state differs from greybox at '$label'" }
    }
    $rl = $r5 | Where-Object { $_.art_log -eq "launch" } | Select-Object -First 1
    $shipped = @(Get-ChildItem -Recurse -Filter *.png "assets\art\wp005").Count
    if ($rl.art.loaded_count -ne $shipped) { throw "capture wp005_assets${size}: loaded $($rl.art.loaded_count) != $shipped shipped png" }
    if ($rl.art.loaded_count + $rl.art.missing_count + $rl.art.optional_missing_count -ne $rl.art.contract_count) { throw "capture wp005_assets${size}: loaded + missing + optional != contract" }
    $ra = $r5 | Where-Object { $_.capture -eq "wp005_assets${size}_a_dense_t15" } | Select-Object -First 1
    $rb = $r5 | Where-Object { $_.capture -eq "wp005_assets${size}_b_collapse_t20.5" } | Select-Object -First 1
    if ($ra.sprites_drawn.'hwacha/idle' -lt 1 -or $ra.sprites_drawn.'jangseung/idle' -lt 1 -or $ra.sprites_drawn.'bongsu/connected' -lt 1 -or $ra.sprites_drawn.'sensor/active' -lt 1) { throw "capture wp005_assets${size}: facility sprites not drawn at t15 ($($ra.sprites_drawn | ConvertTo-Json -Compress))" }
    if ($rb.sprites_drawn.'hwacha/inactive' -lt 1 -or $rb.sprites_drawn.'bongsu/disconnected' -lt 1 -or $rb.sprites_drawn.'sensor/inactive' -lt 1) { throw "capture wp005_assets${size}: inactive / disconnected sprites not drawn after the collapse" }
    if ($rb.marks_drawn.off -lt 1 -or $rb.marks_drawn.recovery_slot -lt 1) { throw "capture wp005_assets${size}: procedural off / recovery marks not drawn after the collapse ($($rb.marks_drawn | ConvertTo-Json -Compress))" }
    if ($ra.sample_tiles_drawn.edge_procedural -lt 1) { throw "capture wp005_assets${size}: procedural edge lines not drawn" }
    Write-Host ("capture wp005_assets{0}: greybox == assets at 4 checkpoints; loaded {1}/{2} (missing {3}); t15 sprites {4}; t20.5 sprites {5}" -f $size, $rl.art.loaded_count, $rl.art.contract_count, $rl.art.missing_count,
        ($ra.sprites_drawn | ConvertTo-Json -Compress), ($rb.sprites_drawn | ConvertTo-Json -Compress))
}
# AC-06: 1,000 enemies held on the field (benchmark load) with the shipped assets, with and without labels, 1080p and 720p
foreach ($size in @("", "_720")) {
    $sc = "wp005_dense$size"
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid5\captures" "--art=sample" | Out-Host
    Assert-Exit "capture $sc"
    Assert-File "$evid5\captures\${sc}_log.json" "capture $sc"
    foreach ($n in @("a_1000_t15", "a2_1000_nolabels_t15", "a3_1000_nooutline_t15", "b_collapse_1000_t20.5", "c_recovery_1000_t25.5", "c2_recovery_1000_nolabels_t25.5")) { Assert-File "$evid5\captures\${sc}_$n.png" "capture $sc" }
    $dl = Get-Content "$evid5\captures\${sc}_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $da = $dl | Where-Object { $_.capture -eq "${sc}_a_1000_t15" } | Select-Object -First 1
    if ($da.alive -lt 1000) { throw "capture ${sc}: expected 1,000 enemies alive at t15 (got $($da.alive))" }
    $dc = $dl | Where-Object { $_.capture -eq "${sc}_c_recovery_1000_t25.5" } | Select-Object -First 1
    if (-not $dc.run.recovery_placed) { throw "capture ${sc}: H1 not placed at t25" }
    Write-Host ("capture {0}: alive {1} at t15, collapse {2}, recovery placed {3}" -f $sc, $da.alive, $dc.run.collapse_count, $dc.run.recovery_placed)
}
# AC-02: 3x close-ups (plaza with / without footprint grid, outer post at the collapse, cell B preview + placement)
& godot --path . --rendering-driver opengl3 -- "--capture=wp005_closeup" "--out-dir=$evid5\captures" "--art=sample" | Out-Host
Assert-Exit "capture wp005_closeup"
foreach ($n in @("a_plaza_x3_footprints_t15", "a2_plaza_x3_t15", "b_outer_post_x3_t20.5", "c_preview_B_x3_footprints_t23.5", "d_recovery_B_x3_t25.5")) { Assert-File "$evid5\captures\wp005_closeup_$n.png" "capture wp005_closeup" }
$cl = Get-Content "$evid5\captures\wp005_closeup_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$cz = $cl | Where-Object { $_.capture -eq "wp005_closeup_a_plaza_x3_footprints_t15" } | Select-Object -First 1
if ($cz.zoom -ne 3 -or $cz.marks_drawn.footprint -lt 1) { throw "capture wp005_closeup: zoom / footprint overlay not recorded" }
Write-Host ("capture wp005_closeup: 5 close-ups at zoom {0}, footprint overlay {1}" -f $cz.zoom, $cz.marks_drawn.footprint)
# AC-06: the WP-004 menu flow over the sample art at both resolutions (menus, text, placement marks)
New-Item -ItemType Directory -Force (Join-Path $evid5 "captures\menus") | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$evid5\captures\menus\*"
foreach ($sc in @("wp004_ui", "wp004_ui_720")) {
    & godot --path . --rendering-driver opengl3 -- "--capture=$sc" "--out-dir=$evid5\captures\menus" "--settings=$evid5\captures\menus\settings_capture.cfg" "--art=sample" | Out-Host
    Assert-Exit "capture $sc (sample art)"
    foreach ($n in @("01_title", "03_playing_t12", "04_paused", "05_settings_from_pause", "06_confirm_restart", "09_result_lost", "10_result_won")) { Assert-File "$evid5\captures\menus\${sc}_$n.png" "capture $sc (sample art)" }
    $ml = Get-Content "$evid5\captures\menus\${sc}_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $mr = @($ml | Where-Object { $_.wait_result })
    if ($mr.Count -ne 2) { throw "capture ${sc} (sample art): expected LOST then WON results" }
    Write-Host ("capture {0} over sample art: 11 menu screens, results {1}/{2}" -f $sc, $mr[0].result.outcome, $mr[1].result.outcome)
}
}   # end of the WP-005 capture block
}   # end of the WP-005 capture block skipped by -Wp008

if ($Quick) { Write-Host "quick mode: skipping build and perf"; exit 0 }

Write-Host "== 5/6 release export"
& godot --headless --path . --export-release "Windows Desktop Release" build_out\windows\hanyang_defense_wp001.exe | Out-Host
Assert-Exit "release export"
Assert-File "build_out\windows\hanyang_defense_wp001.exe" "release export"

if (-not $Wp003) {
Write-Host "== 6/6 performance (10 s warmup + 60 s measure, twice, with external memory sampling)"
foreach ($sc in @("move", "combat")) {
    $out = "results\evidence\perf\perf_${sc}_1000_release.json"
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out
    Assert-File $out "perf $sc"
    Assert-File "$out.memory.json" "perf $sc memory sampler"
    $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
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
    $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
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
}   # end of the WP-001/002 perf block skipped by -Wp003
# D-027 collapse benchmark contract check, shared by 6c (WP-003/004) and 6d (WP-005 per art mode).
function Assert-CollapsePerf([string]$out, [string]$sc, [string]$tag, [int]$structuresAtStart = 18) {
    $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
    $c = $r.collapse
    $types = @($c.semantic_events | ForEach-Object { $_.type })
    $six = @("benchmark_trigger", "collapse", "outer_deactivated_batch", "target_changed", "recovery_created", "recovery_placed")
    $sixOk = $true; foreach ($ty in $six) { if (@($types | Where-Object { $_ -eq $ty }).Count -ne 1) { $sixOk = $false } }
    $segOk = ($c.segments.pre_collapse_0_20.eval_delta -gt 0) -and ($c.segments.waiting_20_25.eval_delta -gt 0) -and ($c.segments.post_placement_25_60.eval_delta -gt 0)
    # R-05: every measured frame in exactly one segment, live manifest (10 zones,
    # 18 structures at start, J1/J2 anchors), executable hash present.
    $manOk = ($c.segments_cover_all_frames -eq $true) -and ($c.global_frames -eq $r.frames) -and `
             (@($r.manifest.zones).Count -eq 10) -and (@($r.manifest.structures_at_start).Count -eq $structuresAtStart) -and `
             ($r.manifest.executable.sha256.Length -eq 64) -and (-not $r.manifest.executable.is_editor_binary)
    $ok = ($r.avg_fps -ge 60) -and ($r.frame_ms_p95 -le 25) -and $r.load_held_all_frames -and $sixOk -and $segOk -and $manOk -and `
          ($c.placement_result -eq "ok") -and (-not $c.natural_collapse_before_trigger) -and ($c.ticks_trigger_to_collapse -ge 0) -and ($c.ticks_trigger_to_collapse -le 2) -and `
          ($r.path_version -eq $r.path_version_expected + 1)
    if ($sc -eq "collapse_combat") { $ok = $ok -and ($c.h1_shots_after_placement -ge 1) -and ($c.h1_shots_at_placement -ge 0) }
    $verdict = if ($ok) { "PASS" } else { "FAIL" }
    Write-Host ("perf {0}{13}: avg_fps={1:N1} p95={2:N2}ms alive_min={3} six_events={4} segments_eval={5} placement={6} trigger->collapse={7} ticks h1_shots_after={8} frames_covered={9}/{10} manifest_ok={11} -> {12}" -f `
        $sc, $r.avg_fps, $r.frame_ms_p95, $r.alive_min, $sixOk, $segOk, $c.placement_result, $c.ticks_trigger_to_collapse, $c.h1_shots_after_placement, $c.segments_frames_total, $r.frames, $manOk, $verdict, $tag)
    if ($verdict -ne "PASS") { throw "perf $sc$tag did not meet the WP-003 D-027 contract" }
}

if ($Wp008) {
Write-Host "== 6e/6 WP-008 build-mode transition performance (build_full_* = 24 from the start, build_grow_* = 22 + 2 bought in the window; same exe, D-027 contract + ledger)"
Remove-Item -Force -ErrorAction SilentlyContinue "$evid8\perf\perf_build_*_1000_release.json*"
foreach ($sc in @("build_full_move", "build_full_combat", "build_grow_move", "build_grow_combat")) {
    $out = "results\evidence\wp-008\perf\perf_${sc}_1000_release.json"
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out -Art greybox
    Assert-File $out "perf $sc"
    Assert-File "$out.memory.json" "perf $sc memory sampler"
    $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
    $startCount = if ($sc -like "build_full_*") { 24 } else { 22 }
    if ($r.play_mode -ne "build" -or -not $r.economy.benchmark_injected -or -not $r.economy.balance_ok) { throw "perf ${sc}: build mode / flagged injection / ledger invariant missing" }
    $cmds = @($r.collapse.build_commands | Where-Object { $_.phase -eq "measure" })
    $capRefused = @($cmds | Where-Object { $_.reason -eq "CAP_REACHED" }).Count
    $okBuys = @($cmds | Where-Object { $_.ok }).Count
    if ($capRefused -lt 1) { throw "perf ${sc}: the cap refusal inside the window is missing" }
    if ($sc -like "build_grow_*" -and $okBuys -ne 2) { throw "perf ${sc}: expected exactly 2 accepted purchases in the window (got $okBuys)" }
    if ($sc -like "build_full_*" -and $okBuys -ne 0) { throw "perf ${sc}: no purchase may succeed at the cap (got $okBuys)" }
    if ($r.structure_total -ne 24) { throw "perf ${sc}: structure total at the end must be 24 (got $($r.structure_total))" }
    if ($r.collapse.build_commands_pending -ne 0) { throw "perf ${sc}: scripted purchases still pending" }
    Assert-CollapsePerf $out $sc " [build]" $startCount
    Write-Host ("perf {0}: window purchases ok={1} cap_refused={2} supply_end={3} (injected {4})" -f $sc, $okBuys, $capRefused, $r.economy.supply, $r.economy.injected)
}
foreach ($pf in @("build_full_move", "build_full_combat", "build_grow_move", "build_grow_combat")) {
    $r = Get-Content "results\evidence\wp-008\perf\perf_${pf}_1000_release.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($r.manifest.implementation_sha -ne $wp8Sha) { throw "perf ${pf}: implementation_sha '$($r.manifest.implementation_sha)' is not the clean HEAD $wp8Sha (R-01)" }
}

Write-Host "== 6f/6 WP-008 build-mode captures on the RELEASE exe (greybox + sample art, 1920x1080 + 1280x720; real HUD buttons / keys / clicks, throwaway settings file)"
$wp8Exe = Get-Item (Resolve-Path "build_out\windows\hanyang_defense_wp001.exe")
$wp8ExeSha = (Get-FileHash -Algorithm SHA256 $wp8Exe.FullName).Hash.ToLower()
$capRoot = "$evid8\captures"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$capRoot\release_greybox", "$capRoot\release_sample"
Remove-Item -Force -ErrorAction SilentlyContinue "$capRoot\wp008_build*", "$capRoot\settings_capture.cfg"   # editor-run captures of the first submission are superseded
$wp8Hashes = @{}
foreach ($art in @("greybox", "sample")) {
    $capDir = "$capRoot\release_$art"
    New-Item -ItemType Directory -Force $capDir | Out-Null
    foreach ($sc in @("wp008_build", "wp008_build_720")) {
        $capArgs = @("--", "--capture=$sc", "--out-dir=$capDir", "--settings=$capDir\settings_capture.cfg", "--art=$art", "--sha=$wp8Sha")
        $proc = Start-Process -FilePath $wp8Exe.FullName -ArgumentList $capArgs -PassThru -Wait
        if ($proc.ExitCode -ne 0) { throw "release capture $sc [$art] exited with $($proc.ExitCode)" }
        Assert-File "$capDir\${sc}_log.json" "release capture $sc [$art]"
        foreach ($n in @("01_preparing", "02_preview_hwacha_cost", "03_bought_in_preparation", "04_insufficient_supply", "05_invalid_terrain",
                         "06_invalid_overlap", "07_paused_in_preparation", "08_battle_t20", "09_battle_purchase_t45", "10_collapse_recovery_selected",
                         "11_recovery_preview_B", "12_recovery_placed_free", "13_outer_refused_after_collapse", "14_inner_preview",
                         "15_inner_purchase", "16_result", "17_restart_preparing")) {
            Assert-File "$capDir\${sc}_$n.png" "release capture $sc [$art]"
        }
        $log = Get-Content "$capDir\${sc}_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $man = ($log | Where-Object { $_.capture_manifest } | Select-Object -First 1).capture_manifest
        if ($null -eq $man) { throw "release capture ${sc} [$art]: capture_manifest missing" }
        if ($man.executable.sha256 -ne $wp8ExeSha -or $man.executable.is_editor_binary) { throw "release capture ${sc} [$art]: executable hash '$($man.executable.sha256)' is not the exported exe $wp8ExeSha" }
        if ($man.implementation_sha -ne $wp8Sha) { throw "release capture ${sc} [$art]: implementation_sha '$($man.implementation_sha)' != $wp8Sha" }
        if ($man.art_mode -ne $art) { throw "release capture ${sc}: art_mode '$($man.art_mode)' != '$art'" }
        if ($art -eq "sample" -and ($man.art.loaded_count -lt 13)) { throw "release capture ${sc} [sample]: shipped assets not loaded ($($man.art.loaded_count))" }
        if ($man.settings_path -ne "$capDir\settings_capture.cfg") { throw "release capture ${sc}: settings path '$($man.settings_path)' is not the throwaway file (--settings= parser)" }
        $expect = @{ launch="TITLE"; start_goes_to_preparing="PREPARING"; esc_pauses_preparing="PAUSED"; esc_resumes_to_preparing="PREPARING";
                     begin_defense_playing="PLAYING"; second_begin_defense_refused="PLAYING"; r_on_result_restarts_to_preparing="PREPARING" }
        foreach ($k in $expect.Keys) {
            $row = $log | Where-Object { $_.label -eq $k -and $_.ui_state } | Select-Object -First 1
            if ($null -eq $row -or $row.ui_state -ne $expect[$k]) { throw "release capture ${sc} [$art]: state after '$k' should be $($expect[$k]) (got $($row.ui_state))" }
        }
        $econ = @{}; foreach ($row in ($log | Where-Object { $_.econ_log })) { $econ[$row.econ_log] = $row }
        if ($econ["preparing_start"].economy.supply -ne 240 -or -not $econ["preparing_start"].preparing) { throw "release capture ${sc}: preparation must start at 240 supply" }
        if ($econ["after_preparation_purchases"].economy.purchase_count -ne 3 -or $econ["after_preparation_purchases"].economy.supply -ne 40) { throw "release capture ${sc}: expected 3 preparation purchases leaving 40" }
        foreach ($k in $econ.Keys) {
            if (-not $econ[$k].economy.balance_ok) { throw "release capture ${sc}: ledger invariant broken at '$k'" }
            if (-not $econ[$k].economy.events_well_ordered) { throw "release capture ${sc}: ledger event seq not monotonic at '$k' (R-03)" }
        }
        $clicks = @($log | Where-Object { $_.lmb_at })
        $bought = @($clicks | Where-Object { $_.last_click.buy -and $_.last_click.ok })
        $reasons = @($clicks | Where-Object { $_.last_click.buy -and -not $_.last_click.ok } | ForEach-Object { $_.last_click.reason })
        if ($bought.Count -lt 5) { throw "release capture ${sc}: expected at least 5 accepted purchases by real clicks (got $($bought.Count))" }
        if ($reasons -notcontains "INSUFFICIENT_SUPPLY") { throw "release capture ${sc}: the insufficient-supply click must be refused (got $($reasons -join ','))" }
        foreach ($c in $clicks) { if ($c.accepted_delta -gt 1) { throw "release capture ${sc}: one click accepted $($c.accepted_delta) commands" } }
        if (@($clicks | Where-Object { $_.recovery_placed }).Count -lt 1) { throw "release capture ${sc}: the free recovery was never placed by a click" }
        if ($econ["after_recovery"].economy.spent -ne $econ["after_collapse"].economy.spent) { throw "release capture ${sc}: the recovery must cost nothing" }
        $previews = @($log | Where-Object { $_.preview_at -and $_.reason })
        foreach ($need in @("DISTRICT_LOST", "TERRAIN_BLOCKED", "STRUCTURE_OVERLAP", "INSUFFICIENT_SUPPLY")) {
            if (@($previews | Where-Object { $_.reason -eq $need }).Count -lt 1) { throw "release capture ${sc}: preview reason $need missing" }
        }
        $second = $log | Where-Object { $_.label -eq "second_begin_defense_refused" } | Select-Object -First 1
        if ($second.begin_defense_calls_ignored -ne 0) { throw "release capture ${sc}: the battle must never see a second 방어 시작" }
        $results = @($log | Where-Object { $_.wait_result })
        if ($results.Count -ne 1 -or -not $results[0].result.economy.balance_ok -or $results[0].result.play_mode -ne "build") { throw "release capture ${sc}: expected one build-mode result with a balanced ledger" }
        $restart = $econ["restart_ledger_reset"].economy
        if ($restart.supply -ne 240 -or $restart.purchase_count -ne 0 -or $restart.earned_kills -ne 0) { throw "release capture ${sc}: the restart must reset the ledger" }
        # state checkpoints for the cross-mode / cross-resolution comparison below
        $h = @{}; foreach ($row in ($log | Where-Object { $_.state_log })) { $h[$row.state_log] = $row.state_hash }
        $wp8Hashes["$art|$sc"] = $h
        Write-Host ("release capture {0} [{1}]: exe {2}… sha {3}, purchases by click {4}, refused ({5}), result {6} supply {7}, checkpoints {8}" -f $sc, $art, $wp8ExeSha.Substring(0, 12), $wp8Sha.Substring(0, 7), $bought.Count, ($reasons -join ","), $results[0].result.outcome, $results[0].result.economy.supply, $h.Count)
    }
}
# AC-06: the whole build-mode cycle (preparation purchases -> battle -> collapse -> free recovery -> inner purchase -> result -> restart)
# holds identical battle state in greybox and sample, and at 1920x1080 and 1280x720 (same seed, same commands).
$labels = @("preparing_start", "after_preparation_purchases", "battle_t20", "after_collapse", "after_recovery", "after_inner_purchase", "result", "restart_preparing")
$ref = $wp8Hashes["greybox|wp008_build"]
foreach ($key in $wp8Hashes.Keys) {
    foreach ($lb in $labels) {
        if (-not $ref.ContainsKey($lb) -or -not $wp8Hashes[$key].ContainsKey($lb)) { throw "release capture ${key}: checkpoint '$lb' missing" }
        if ($wp8Hashes[$key][$lb] -ne $ref[$lb]) { throw "release capture ${key}: battle state at '$lb' differs from greybox 1080p (AC-06)" }
    }
}
Write-Host ("release captures: {0} runs x {1} checkpoints identical to greybox 1080p (greybox == sample, 1080p == 720p)" -f $wp8Hashes.Count, $labels.Count)
} elseif (-not $Wp005) {
Write-Host "== 6c/6 WP-003 transition performance (collapse_move, collapse_combat)"
$perfDir = if ($Wp004) { "results\evidence\wp-004\perf" } else { "results\evidence\wp-003\perf" }
Remove-Item -Force -ErrorAction SilentlyContinue "$root\$perfDir\perf_collapse_move_1000_release.json*", "$root\$perfDir\perf_collapse_combat_1000_release.json*"   # archived *_runN_* files are kept
foreach ($sc in @("collapse_move", "collapse_combat")) {
    $out = "$perfDir\perf_${sc}_1000_release.json"
    & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out
    Assert-File $out "perf $sc"
    Assert-File "$out.memory.json" "perf $sc memory sampler"
    Assert-CollapsePerf $out $sc ""
}
} else {
Write-Host "== 6d/6 WP-005 transition performance per rendering mode (greybox / sample on the shipped assets; same exe, D-027 contract)"
Remove-Item -Force -ErrorAction SilentlyContinue "$evid5\perf\perf_collapse_*_1000_release.json*"
foreach ($art in @("greybox", "sample")) {
    foreach ($sc in @("collapse_move", "collapse_combat")) {
        $out = "results\evidence\wp-005\perf\perf_${sc}_${art}_1000_release.json"
        if ($art -eq "sample") {
            & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out -Art sample   # default dir = assets/art/wp005 (D-051)
        } else {
            & (Join-Path $PSScriptRoot "perf_with_memory.ps1") -Scenario $sc -Warmup 10 -Measure 60 -Out $out -Art greybox
        }
        Assert-File $out "perf $sc $art"
        Assert-File "$out.memory.json" "perf $sc $art memory sampler"
        $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($r.art_mode -ne $art) { throw "perf ${sc}: manifest art_mode '$($r.art_mode)' != '$art'" }
        if ($art -eq "sample" -and (-not $r.art.enemy_atlas -or $r.art.loaded_count -lt 13)) { throw "perf $sc sample: shipped assets not loaded (loaded $($r.art.loaded_count), atlas $($r.art.enemy_atlas))" }
        Assert-CollapsePerf $out $sc " [$art]"
    }
}
}
Write-Host "done. evidence in $(if ($Wp008) { $evid8 } elseif ($Wp005) { $evid5 } else { $evid3 })$(if (-not $Wp003) { ", $evid and $evid2" })"
