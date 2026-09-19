param([string]$EvidenceDir = 'results/evidence/wp-005/revision1')
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
# Reuse the exact D-027 contract without executing verify.ps1's destructive reruns.
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'verify.ps1'), [ref]$tokens, [ref]$parseErrors)
$fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-CollapsePerf' }, $true)
if ($null -eq $fn) { throw 'D-027 validator not found' }
. ([scriptblock]::Create($fn.Extent.Text))
$rows = @()
foreach ($art in @('greybox','sample')) {
    foreach ($scenario in @('collapse_move','collapse_combat')) {
        $path = Join-Path $EvidenceDir "perf/perf_${scenario}_${art}.json"
        Assert-CollapsePerf $path $scenario $art
        $r = Get-Content $path -Raw | ConvertFrom-Json
        $memory = Get-Content "$path.memory.json" -Raw | ConvertFrom-Json
        $sorted = @($r.frame_us_raw | Sort-Object)
        $p95 = $sorted[[int][Math]::Ceiling($sorted.Count * 0.95) - 1] / 1000.0
        $fps = 1000000.0 * $sorted.Count / ($sorted | Measure-Object -Sum).Sum
        $aliveMin = ($r.alive_raw | Measure-Object -Minimum).Minimum
        if ($sorted.Count -ne $r.frames -or $r.alive_raw.Count -ne $r.frames -or $aliveMin -lt 1000) { throw 'Raw frame/load mismatch' }
        if ([Math]::Abs($p95 - $r.frame_ms_p95) -gt 0.001 -or [Math]::Abs($fps - $r.avg_fps) -gt 0.001) { throw 'Raw timing mismatch' }
        if ($r.art_mode -ne $art -or $r.vsync_mode -ne 0 -or $r.warmup_seconds -ne 10 -or $r.measure_seconds -ne 60) { throw 'Measurement settings mismatch' }
        if ($art -eq 'sample' -and ($r.art.loaded_count -ne 17 -or -not $r.art.enemy_atlas -or $r.art.dir -ne 'res://assets/art/wp005')) { throw 'Real assets not loaded' }
        $rows += [pscustomobject]@{ mode=$art; scenario=$scenario; avg_fps=$fps; p95_ms=$p95; alive_min=$aliveMin; frames=$r.frames; exe_sha256=$r.manifest.executable.sha256; implementation_sha=$r.manifest.implementation_sha; memory_peak_mb=$memory.working_set_mb_max; verdict='PASS' }
    }
}
if (@($rows.exe_sha256 | Select-Object -Unique).Count -ne 1 -or @($rows.implementation_sha | Select-Object -Unique).Count -ne 1) { throw 'Different builds were measured' }
foreach ($row in $rows | Where-Object mode -eq 'sample') {
    $baseline = $rows | Where-Object { $_.scenario -eq $row.scenario -and $_.mode -eq 'greybox' }
    $row | Add-Member NoteProperty fps_change_percent (($row.avg_fps / $baseline.avg_fps - 1) * 100)
    $row | Add-Member NoteProperty p95_change_ms ($row.p95_ms - $baseline.p95_ms)
}
$json = $rows | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path (Get-Location) "$EvidenceDir/perf_summary.json"), $json + "`n", (New-Object Text.UTF8Encoding($false)))
$rows | Format-Table mode,scenario,avg_fps,p95_ms,alive_min,verdict
