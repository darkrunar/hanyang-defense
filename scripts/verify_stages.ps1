# Core-loop stage ladder verification (docs/CORE_LOOP_STAGES.md, D-056).
#
#   .\scripts\verify_stages.ps1          tests + per-stage checks + release export + stage tour captures
#   .\scripts\verify_stages.ps1 -Quick   tests + per-stage checks only (no export / captures)
#
# Evidence lands in results\evidence\stages\. The full run refuses a dirty game
# tree so every capture manifest names the reviewed commit (WP-008 R-01 lesson).
param([switch]$Quick)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$root = (Get-Location).Path
$ev = "$root\results\evidence\stages"

function Assert-File([string]$path, [string]$step) {
    if (-not (Test-Path $path)) { throw "${step}: missing $path" }
}

if (-not $Quick) {
    $dirty = (& git status --porcelain --untracked-files=no -- game project.godot export_presets.cfg 2>$null)
    if ($dirty) { throw "commit the game tree first (dirty: $($dirty -join '; ')). Evidence must name a clean implementation sha." }
}
$sha = (& git rev-parse HEAD).Trim()
foreach ($d in @("tests", "captures")) { New-Item -ItemType Directory -Force (Join-Path $ev $d) | Out-Null }
Remove-Item -Force -ErrorAction SilentlyContinue "$ev\tests\test_report.txt", "$ev\stage_report.json"

Write-Host "== 1/4 headless test suite (includes the core-loop stage suite)"
& godot --headless --path . --script res://tests/run_tests.gd -- "--report=$ev\tests\test_report.txt" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "test suite failed (exit $LASTEXITCODE)" }
Assert-File "$ev\tests\test_report.txt" "tests"
if (-not (Select-String -Path "$ev\tests\test_report.txt" -Pattern "failed=0" -Quiet)) { throw "test report does not say failed=0" }
Write-Host (Select-String -Path "$ev\tests\test_report.txt" -Pattern "^TOTAL" | Select-Object -Last 1).Line

Write-Host "== 2/4 per-stage A/B checks (headless, same seed)"
& godot --headless --path . --script res://game/tools/stage_report.gd -- "--out=$ev\stage_report.json" | Out-Host
if ($LASTEXITCODE -ne 0) { throw "a stage check failed (exit $LASTEXITCODE)" }
Assert-File "$ev\stage_report.json" "stage report"
$rep = Get-Content "$ev\stage_report.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $rep.all_pass -or @($rep.stages).Count -ne 8) { throw "stage report: all_pass=$($rep.all_pass), stages=$(@($rep.stages).Count)" }

if ($Quick) { Write-Host "quick mode: skipping export and captures"; exit 0 }

Write-Host "== 3/4 release export"
& godot --headless --path . --export-release "Windows Desktop Release" build_out\windows\hanyang_defense_wp001.exe | Out-Host
Assert-File "build_out\windows\hanyang_defense_wp001.exe" "release export"
$exe = Get-Item (Resolve-Path "build_out\windows\hanyang_defense_wp001.exe")
$exeSha = (Get-FileHash -Algorithm SHA256 $exe.FullName).Hash.ToLower()

Write-Host "== 4/4 stage tour on the release exe (greybox / sample x 1920x1080 / 1280x720)"
$names = @("s1_flow_t15", "s2_jangseung_t25", "s3_hwacha_bottleneck_t25", "s4_network_t15", "s5_waves_t60",
           "s6_collapse", "s6_recovered_t30", "s7_title", "s7_playing_t10", "s8_preparing")
$endHash = @{}
foreach ($art in @("greybox", "sample")) {
    $dir = "$ev\captures\$art"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $dir
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($sc in @("stage_tour", "stage_tour_720")) {
        $capArgs = @("--", "--capture=$sc", "--out-dir=$dir", "--art=$art", "--sha=$sha")
        $proc = Start-Process -FilePath $exe.FullName -ArgumentList $capArgs -PassThru -Wait
        if ($proc.ExitCode -ne 0) { throw "capture $sc [$art] exited with $($proc.ExitCode)" }
        Assert-File "$dir\${sc}_log.json" "capture $sc [$art]"
        foreach ($n in $names) { Assert-File "$dir\${sc}_$n.png" "capture $sc [$art]" }
        $log = Get-Content "$dir\${sc}_log.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $man = ($log | Where-Object { $_.capture_manifest } | Select-Object -First 1).capture_manifest
        if ($man.executable.sha256 -ne $exeSha -or $man.executable.is_editor_binary) { throw "capture $sc [$art]: exe hash '$($man.executable.sha256)' is not the exported $exeSha" }
        if ($man.implementation_sha -ne $sha) { throw "capture $sc [$art]: implementation_sha '$($man.implementation_sha)' != $sha" }
        if ($man.art_mode -ne $art) { throw "capture ${sc}: art_mode '$($man.art_mode)' != $art" }
        $entered = @($log | Where-Object { $null -ne $_.stage -and $null -ne $_.ok })
        foreach ($id in 1..8) {
            $row = $entered | Where-Object { $_.stage -eq $id } | Select-Object -First 1
            if ($null -eq $row -or -not $row.ok) { throw "capture $sc [$art]: stage $id not entered" }
        }
        $s7 = $entered | Where-Object { $_.stage -eq 7 } | Select-Object -First 1
        $s8 = $entered | Where-Object { $_.stage -eq 8 } | Select-Object -First 1
        if ($s7.flow_state -ne "TITLE" -or $s8.flow_state -ne "TITLE" -or $s8.play_mode -ne "build") { throw "capture $sc [$art]: menu stages did not open on TITLE" }
        $s6 = @($log | Where-Object { $_.wait_collapse -ne $null } | Select-Object -First 1)
        if ($s6.Count -ne 1 -or $s6[0].wait_collapse -ne 1) { throw "capture $sc [$art]: stage 6 did not collapse from real arrivals" }
        $end = ($log | Where-Object { $_.stage_log -eq "end" } | Select-Object -First 1)
        if ($null -eq $end -or $end.flow_state -ne "PREPARING") { throw "capture $sc [$art]: tour did not end in stage 8 PREPARING" }
        $endHash["$art|$sc"] = $end.state_hash
        Write-Host ("capture {0} [{1}]: exe {2}... sha {3}, stages 1..8 entered, stage 6 collapse ok, end {4}" -f $sc, $art, $exeSha.Substring(0, 12), $sha.Substring(0, 7), $end.live)
    }
}
$ref = $endHash["greybox|stage_tour"]
foreach ($k in $endHash.Keys) { if ($endHash[$k] -ne $ref) { throw "capture ${k}: final battle state differs from greybox 1080p" } }
Write-Host "done: 4 tours, final state identical across art modes and resolutions. evidence in $ev"
