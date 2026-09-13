#!/usr/bin/env bash
# WP-001 end-to-end verification (Git Bash / Linux / macOS shells).
#
#   scripts/verify.sh            tests + captures + release build + perf
#   scripts/verify.sh --quick    tests + captures only (no build, no perf)
#
# Requires `godot` (4.7.stable) on PATH and, for the build/perf steps, the
# matching Windows export template. Evidence lands in results/evidence/.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EVID="$ROOT/results/evidence"
mkdir -p "$EVID/captures" "$EVID/perf" build_out/windows

abs() {  # absolute native path for Godot's FileAccess on Windows
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

echo "== 1/6 headless test suite"
godot --headless --path . --script res://tests/run_tests.gd -- --report="$(abs "$EVID/test_report.txt")"

grep -q "failed=0" "$EVID/test_report.txt" || { echo "test report does not say failed=0"; exit 1; }

echo "== 2/6 map dump"
godot --headless --path . --script res://game/tools/dump_map.gd > "$EVID/map_dump.txt"
[[ -s "$EVID/map_dump.txt" ]] || { echo "map dump missing"; exit 1; }

echo "== 3/6 P-007 occupancy probe"
godot --headless --path . --script res://game/tools/probe_occupancy.gd -- --out="$(abs "$EVID/occupancy_probe.json")"
[[ -s "$EVID/occupancy_probe.json" ]] || { echo "occupancy probe missing"; exit 1; }

echo "== 4/6 evidence captures (windowed)"
for sc in ac01 ac02 ac06; do
    godot --path . --rendering-driver opengl3 -- --capture="$sc" --out-dir="$(abs "$EVID/captures")"
    [[ -s "$EVID/captures/${sc}_log.json" ]] || { echo "capture $sc produced no log"; exit 1; }
done
for png in ac01_t30_1000_alive_three_routes ac02_a_reference_t30 ac02_b_west_lane_blocked_t30 \
           ac02_c_restored_t42 ac06_a_before_t35 ac06_b_after_t35; do
    [[ -s "$EVID/captures/$png.png" ]] || { echo "capture $png.png missing"; exit 1; }
done

if [[ "${1:-}" == "--quick" ]]; then
    echo "quick mode: skipping build and perf"; exit 0
fi

echo "== 5/6 release export"
godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe

echo "== 6/6 performance (10 s warmup + 60 s measure, twice, with external memory sampling)"
for sc in move combat; do
    if command -v powershell.exe >/dev/null 2>&1; then
        # Windows: sample the process working set from outside the engine too.
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/perf_with_memory.ps1 \
            -Scenario "$sc" -Warmup 10 -Measure 60 -Out "results/evidence/perf/perf_${sc}_1000_release.json"
    else
        ./build_out/windows/hanyang_defense_wp001.exe -- --perf --scenario="$sc" --warmup=10 --measure=60 \
            --out="$(abs "$EVID/perf/perf_${sc}_1000_release.json")"
    fi
done
echo "done. evidence in $EVID"
