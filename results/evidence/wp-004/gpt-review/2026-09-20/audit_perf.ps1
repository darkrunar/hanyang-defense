$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
$items = foreach ($scenario in 'move','combat') {
    $file = Join-Path $repo "results/evidence/wp-004/perf/perf_collapse_${scenario}_1000_release.json"
    $p = Get-Content $file -Raw | ConvertFrom-Json
    $mem = Get-Content "$file.memory.json" -Raw | ConvertFrom-Json
    $raw = @($p.frame_us_raw)
    $sorted = @($raw | Sort-Object)
    $sum = ($raw | Measure-Object -Sum).Sum
    $fps = $raw.Count * 1000000.0 / $sum
    $p95 = $sorted[[int][Math]::Ceiling($raw.Count * 0.95)-1]/1000.0
    $aliveMin = ($p.alive_raw | Measure-Object -Minimum).Minimum
    $next = 0
    $segResults = foreach ($prop in ($p.collapse.segments.PSObject.Properties | Sort-Object {$_.Value.frame_index_start})) {
        $seg = $prop.Value
        $slice = @($raw[$seg.frame_index_start..$seg.frame_index_end])
        $ss = @($slice | Sort-Object)
        $sp95 = $ss[[int][Math]::Ceiling($slice.Count * 0.95)-1]/1000.0
        $sfps = $slice.Count*1000000.0/($slice | Measure-Object -Sum).Sum
        if ($seg.frame_index_start -ne $next -or $slice.Count -ne $seg.frames -or [Math]::Abs($sp95-$seg.p95_ms) -gt 0.002 -or [Math]::Abs($sfps-$seg.avg_fps) -gt 0.01 -or $seg.eval_delta -le 0) { throw "Segment mismatch: $scenario $($prop.Name)" }
        $next = $seg.frame_index_end+1
        @{name=$prop.Name;frames=$slice.Count;fps=$sfps;p95_ms=$sp95;eval_delta=$seg.eval_delta}
    }
    if ($raw.Count -ne $p.frames -or $p.alive_raw.Count -ne $raw.Count -or $next -ne $raw.Count -or $aliveMin -lt 1000 -or -not $p.load_held_all_frames -or [Math]::Abs($fps-$p.avg_fps) -gt 0.01 -or [Math]::Abs($p95-$p.frame_ms_p95) -gt 0.002 -or $p95 -gt 25 -or $fps -lt 60) { throw "Raw contract mismatch: $scenario" }
    if ($p.manifest.executable.sha256 -ne $mem.exe_sha256 -or $p.manifest.implementation_sha -ne $mem.implementation_sha -or $p.manifest.zones.Count -ne 10 -or $p.manifest.structures_at_start.Count -ne 18 -or $p.collapse.semantic_events.Count -ne 6 -or $p.collapse.ticks_trigger_to_collapse -gt 2 -or $p.path_version -ne ($p.path_version_at_start + 1)) { throw "Manifest/event mismatch: $scenario" }
    @{scenario=$scenario;frames=$raw.Count;seconds=$sum/1000000.0;fps=$fps;p95_ms=$p95;alive_min=$aliveMin;segments=$segResults;events=@($p.collapse.semantic_events | Select-Object type,tick);placement=$p.collapse.placement_result;h1_shots_after=$p.collapse.h1_shots_after_placement;implementation_sha=$p.manifest.implementation_sha;exe_sha256=$mem.exe_sha256;status='PASS'}
}
$items | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $PSScriptRoot 'perf_audit.json') -Encoding utf8
$items | Select-Object scenario,frames,fps,p95_ms,alive_min,status | Format-Table
