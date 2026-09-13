#!/usr/bin/env bash
# WP-001 end-to-end verification (Bash).
#
#   scripts/verify.sh            tests + probe + captures + release build + perf   (Windows Git Bash only)
#   scripts/verify.sh --quick    tests + probe + captures                          (any host with Godot)
#
# Requires `godot` (4.7.stable) on PATH. The full run also needs the matching
# Windows export template and PowerShell (steps 5-6 export a Windows PE and
# sample its memory from PowerShell); other hosts must use --quick.
# Evidence lands in results/evidence/.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EVID="$ROOT/results/evidence"
mkdir -p "$EVID/captures" "$EVID/perf" build_out/windows

abs() {  # absolute native path for Godot's FileAccess on Windows
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

# Freshness: remove every artifact this script regenerates, so a leftover file
# from an earlier run can never be mistaken for new evidence.
rm -f "$EVID/test_report.txt" "$EVID/map_dump.txt" "$EVID/occupancy_probe.json"
rm -f "$EVID"/captures/ac0*_log.json "$EVID"/captures/ac0*.png

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

echo "== 4b/6 WP-002 fixture A capture (connection effect)"
EVID2="$EVID/wp-002"
mkdir -p "$EVID2/captures" "$EVID2/perf" "$EVID2/tests"
rm -f "$EVID2"/captures/wp002_a*
cp -f "$EVID/test_report.txt" "$EVID2/tests/test_report.txt"
godot --path . --rendering-driver opengl3 -- --capture=wp002_a --out-dir="$(abs "$EVID2/captures")"
[[ -s "$EVID2/captures/wp002_a_log.json" ]] || { echo "capture wp002_a produced no log"; exit 1; }
for png in wp002_a1_disconnected_no_fire_t2 wp002_a2_connected_shared_fire_t2.5 \
           wp002_a3_disconnected_again_no_stale_fire_t5 wp002_a4_local_fire_while_disconnected_t5.5 \
           wp002_a5_reconnected_reacquired_t7; do
    [[ -s "$EVID2/captures/$png.png" ]] || { echo "capture $png.png missing"; exit 1; }
done

if [[ "${1:-}" == "--quick" ]]; then
    echo "quick mode: skipping build and perf"; exit 0
fi

# The export preset produces a Windows x86_64 PE and the perf runner samples
# memory with PowerShell, so steps 5-6 are Windows (Git Bash) only. Fail
# clearly elsewhere instead of trying to execute the PE (Codex review).
if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "steps 5-6 (release export + perf) are Windows-only in WP-001: no powershell.exe / Windows host detected."
    echo "run '$0 --quick' here, or run the full script from Windows Git Bash / scripts/verify.ps1."
    exit 1
fi

echo "== 5/6 release export"
godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe

echo "== 6/6 performance (10 s warmup + 60 s measure, twice, with external memory sampling)"
# Pull one numeric field out of Godot's pretty-printed JSON without needing jq/python.
json_num() { grep -o "\"$2\": *[-0-9.]*" "$1" | head -1 | sed 's/.*: *//'; }
json_bool() { grep -o "\"$2\": *\(true\|false\)" "$1" | head -1 | sed 's/.*: *//'; }
for sc in move combat; do
    out="$EVID/perf/perf_${sc}_1000_release.json"
    rm -f "$out" "$out.memory.json"   # freshness: a stale file can never pass as new evidence
    # Sample the process working set from outside the engine too (release
    # templates report 0 for their internal memory counters).
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/perf_with_memory.ps1 \
        -Scenario "$sc" -Warmup 10 -Measure 60 -Out "results/evidence/perf/perf_${sc}_1000_release.json"
    [[ -s "$out" ]] || { echo "perf $sc produced no JSON"; exit 1; }
    # D-009 budget, same three conditions as verify.ps1: avg >= 60 FPS, p95 <= 25 ms, load held on every frame.
    fps=$(json_num "$out" avg_fps); p95=$(json_num "$out" frame_ms_p95); held=$(json_bool "$out" load_held_all_frames)
    if awk -v f="$fps" -v p="$p95" -v h="$held" 'BEGIN{exit !(f>=60 && p<=25 && h=="true")}'; then
        echo "perf $sc: avg_fps=$fps p95=${p95}ms load_held=$held -> PASS"
    else
        echo "perf $sc: avg_fps=$fps p95=${p95}ms load_held=$held -> FAIL (budget: avg>=60, p95<=25ms, alive_min>=target)"; exit 1
    fi
done

echo "== 6b/6 WP-002 fixture B performance (network_move, network_combat)"
rm -f "$EVID2"/perf/perf_network_*
for sc in network_move network_combat; do
    out="$EVID2/perf/perf_${sc}_1000_release.json"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/perf_with_memory.ps1 \
        -Scenario "$sc" -Warmup 10 -Measure 60 -Out "results/evidence/wp-002/perf/perf_${sc}_1000_release.json"
    [[ -s "$out" ]] || { echo "perf $sc produced no JSON"; exit 1; }
    fps=$(json_num "$out" avg_fps); p95=$(json_num "$out" frame_ms_p95); held=$(json_bool "$out" load_held_all_frames)
    ok=1
    awk -v f="$fps" -v p="$p95" -v h="$held" 'BEGIN{exit !(f>=60 && p<=25 && h=="true")}' || ok=0
    if [[ "$sc" == "network_combat" ]]; then
        # WP-002 fixture B contract: 12 B8 toggles, 12 successful jangseung changes,
        # path_version as expected, at least one shared-only volley.
        b8=$(json_num "$out" b8_toggles); jc=$(json_num "$out" jangseung_changes)
        pv=$(json_num "$out" path_version); pve=$(json_num "$out" path_version_expected); so=$(json_num "$out" shared_only_shots)
        [[ "$b8" == "12" && "$jc" == "12" && "$pv" == "$pve" && "$so" -ge 1 ]] || ok=0
        echo "perf $sc: b8_toggles=$b8 jangseung_changes=$jc path_version=$pv/$pve shared_only_shots=$so"
    fi
    if [[ "$ok" == "1" ]]; then
        echo "perf $sc: avg_fps=$fps p95=${p95}ms load_held=$held -> PASS"
    else
        echo "perf $sc: avg_fps=$fps p95=${p95}ms load_held=$held -> FAIL"; exit 1
    fi
done
echo "done. evidence in $EVID and $EVID2"
