extends SceneTree
## LD-DEV-01 AC-M04 comparison: Stage003 revised obstacle vs a no-terrain
## control that uses the same spawn coordinates. Writes one JSON with the
## sample routes, lengths, gate-front (rally) cells, every candidate cell's
## verdict, and the battle PathNetwork cross-check.
##
##   godot --headless --path . --script res://game/tools/ld_dev_01_compare.gd -- --out=<dir> [--sha=<commit>]
##   godot --headless --path . --script res://game/tools/ld_dev_01_compare.gd -- --write-fixtures
##   godot --headless --path . --script res://game/tools/ld_dev_01_compare.gd -- --write-capture-inputs=user://ld_dev_01_capture
##
## --write-fixtures regenerates the two committed fixture files from the rule
## below; the files are the source the tests and the editor read.

const StageMap := preload("res://game/maps/stage_map_definition.gd")

const CONTROL_PATH: String = "res://game/maps/stages/stage_003_r01_control.json"
const VARIANT_PATH: String = "res://game/maps/stages/stage_003_r01.json"
## LEVEL_DESIGN_STAGES Stage003 revision: one obstacle x28~35, y29~30 (inclusive).
const R01_OBSTACLE: Rect2i = Rect2i(28, 29, 8, 2)
## Stage001's derived seed ("stage_001".hash() ^ 20260924), written explicitly
## so both fixtures produce Stage001's 12 preview samples regardless of stage_id.
const R01_SPAWN_SEED: int = 2003935061
## Stage003 facility candidates (top-left of a 2x2 footprint), informational.
const FACILITY_CANDIDATES: Dictionary = {"A_outer": Vector2i(25, 29), "B_gate": Vector2i(30, 26)}


static func build_control() -> RefCounted:
    var data = StageMap.flat_template()
    data.stage_id = "stage_003_r01_control"
    data.stage_name = "Stage003 R-01 대조군 · 지형 없음"
    data.spawn_seed = R01_SPAWN_SEED
    return data


static func build_variant() -> RefCounted:
    var data = build_control()
    data.stage_id = "stage_003_r01"
    data.stage_name = "Stage003 굽어진 접근로 · R-01 수정안"
    data.map_type = StageMap.MapType.TERRAIN
    data._fill_rect(R01_OBSTACLE, StageMap.Cell.WALL)
    return data


func _initialize() -> void:
    var args: Dictionary = {}
    for a: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
        if a.begins_with("--") and a.contains("="):
            args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
        elif a.begins_with("--"):
            args[a.substr(2)] = true
    if args.has("write-fixtures"):
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTROL_PATH.get_base_dir()))
        var ok: bool = build_control().save_json(CONTROL_PATH) and build_variant().save_json(VARIANT_PATH)
        print("fixtures written: %s" % str(ok))
        quit(0 if ok else 1)
        return
    if args.has("write-capture-inputs"):
        quit(0 if write_capture_inputs(str(args["write-capture-inputs"])) else 1)
        return
    var report: Dictionary = compare(str(args.get("sha", "")))
    var out_dir: String = str(args.get("out", "user://ld_dev_01"))
    var virtual_dir: bool = out_dir.begins_with("res://") or out_dir.begins_with("user://")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if virtual_dir else out_dir)
    var out_path: String = out_dir.path_join("stage003_r01_route_compare.json")
    var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
    if file == null:
        push_error("cannot write " + out_path)
        quit(1)
        return
    file.store_string(JSON.stringify(report, "  ", false) + "\n")
    file.close()
    var s: Dictionary = report["samples_summary"]
    print("samples changed %d/%d, all candidates changed %d/%d, control valid %s, variant valid %s -> %s" % [
        s["changed"], s["count"], report["all_candidates"]["changed"], report["all_candidates"]["total"],
        str(report["control"]["validate_ok"]), str(report["variant"]["validate_ok"]), out_path.get_file()])
    quit(0 if report["ac_m04_pass"] else 1)


## Editor capture inputs (not fixtures): the existing terrain template with the
## shared seed (R-01 "before"), an on-screen spawn radius, a wall hole and a
## file with a fractional integer field. Written to `dir` (user:// by default)
## so editor captures show a virtual path.
static func write_capture_inputs(dir: String) -> bool:
    if dir == "" or dir == "true":
        dir = "user://ld_dev_01_capture"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    var legacy = StageMap.terrain_template()
    legacy.stage_id = "stage_003_legacy_terrain"
    legacy.stage_name = "기존 지형 템플릿 (R-01 이전)"
    legacy.spawn_seed = R01_SPAWN_SEED
    var near = build_control()
    near.stage_id = "ld01_spawn_on_screen"
    near.stage_name = "검사용 · 생성 반경이 화면에 걸침"
    near.spawn_center = Vector2i(31, 37)
    var hole = build_control()
    hole.stage_id = "ld01_wall_hole"
    hole.stage_name = "검사용 · 성벽 구멍 (24,17)"
    hole.set_cell(Vector2i(24, 17), StageMap.Cell.OPEN)
    var ok: bool = legacy.save_json(dir.path_join("legacy_terrain.json")) \
        and near.save_json(dir.path_join("spawn_on_screen.json")) \
        and hole.save_json(dir.path_join("wall_hole.json"))
    var raw: Dictionary = JSON.parse_string(build_control().to_json_text())
    raw["tuning"]["wave_count"] = 2.5
    var f: FileAccess = FileAccess.open(dir.path_join("broken_wave_count.json"), FileAccess.WRITE)
    ok = ok and f != null
    if f != null:
        f.store_string(JSON.stringify(raw, "  ") + "\n")
        f.close()
    print("capture inputs written to %s: %s" % [dir, str(ok)])
    return ok


static func _pairs(list: Array) -> Array:
    var out: Array = []
    for c: Vector2i in list:
        out.append([c.x, c.y])
    return out


## Gate cell used and the field cell right before it (where the route queues
## in front of the gate).
static func _gate_front(data, route: Array) -> Dictionary:
    for i: int in range(1, route.size()):
        if data.cell_at(route[i]) == StageMap.Cell.GATE:
            var before: Vector2i = route[i - 1]
            var gate: Vector2i = route[i]
            return {"gate": [gate.x, gate.y], "front": [before.x, before.y], "index": i}
    return {"gate": null, "front": null, "index": -1}


## Which side of the obstacle a route uses in the obstacle rows.
static func _detour_side(route: Array) -> String:
    var side: String = "none"
    for c: Vector2i in route:
        if c.y >= R01_OBSTACLE.position.y and c.y < R01_OBSTACLE.end.y:
            if c.x < R01_OBSTACLE.position.x:
                side = "left"
            elif c.x >= R01_OBSTACLE.end.x:
                side = "right"
            else:
                side = "through"
    return side


static func _first_divergence(a: Array, b: Array) -> int:
    for i: int in range(mini(a.size(), b.size())):
        if a[i] != b[i]:
            return i
    return -1 if a.size() == b.size() else mini(a.size(), b.size())


static func _map_summary(data, path: String) -> Dictionary:
    var result: Dictionary = data.validate()
    var failed: Array = []
    for check: Dictionary in result["checks"]:
        if not check["ok"]:
            failed.append(check["label"])
    var cand: Dictionary = result["spawn_candidates"]
    return {
        "file": path,
        "file_sha256": FileAccess.get_sha256(path) if path != "" else "",
        "stage_id": data.stage_id,
        "map_type": "flat" if data.map_type == StageMap.MapType.FLAT else "terrain",
        "spawn_seed": data.spawn_seed,
        "effective_spawn_seed": data.effective_spawn_seed(),
        "spawn_center": [data.spawn_center.x, data.spawn_center.y],
        "spawn_radius_cells": data.spawn_radius_cells,
        "goal": [data.goal.x, data.goal.y],
        "gates": _pairs(data.cells_of(StageMap.Cell.GATE)),
        "extra_terrain_cells": data._extra_terrain_count(),
        "validate_ok": result["ok"],
        "failed_checks": failed,
        "spawn_candidates": {"total": cand["total"], "valid": cand["valid"], "rejected_counts": cand["rejected_counts"]},
    }


## Battle-side cross-check: the core PathNetwork (8 directions, no corner
## cutting) built from the same map. Follows the flow field from each entry.
static func _core_routes(data) -> Dictionary:
    var grid = data.build_grid()
    var path = data.build_path(grid)
    var out: Dictionary = {}
    for entry: Vector2i in data.cells_of(StageMap.Cell.ENTRY):
        var i: int = grid.idx(entry.x, entry.y)
        var cells_walked: Array = []
        var crosses_gate: bool = false
        var guard: int = 0
        while i >= 0 and guard < 4096:
            var c: Vector2i = Vector2i(grid.cell_x(i), grid.cell_y(i))
            cells_walked.append([c.x, c.y])
            if data.cell_at(c) == StageMap.Cell.GATE:
                crosses_gate = true
            if c == data.goal:
                break
            i = path.next_index(i)
            guard += 1
        var reached: bool = not cells_walked.is_empty() and cells_walked[-1] == [data.goal.x, data.goal.y]
        out["%d,%d" % [entry.x, entry.y]] = {
            "reachable": path.is_reachable_index(grid.idx(entry.x, entry.y)),
            "reached_goal": reached, "crosses_gate": crosses_gate,
            "cost": path.dist[grid.idx(entry.x, entry.y)], "cells": cells_walked,
        }
    return out


static func _stats(values: Array) -> Dictionary:
    if values.is_empty():
        return {"min": null, "max": null, "mean": null}
    var total: float = 0.0
    for v: float in values:
        total += v
    return {"min": values.min(), "max": values.max(), "mean": snappedf(total / values.size(), 0.01)}


static func compare(sha: String) -> Dictionary:
    var control = StageMap.load_json(CONTROL_PATH)
    var variant = StageMap.load_json(VARIANT_PATH)
    var legacy = StageMap.terrain_template()
    var samples: Array[Vector2i] = control.generated_spawn_points()
    var variant_samples: Array[Vector2i] = variant.generated_spawn_points()

    var rows: Array = []
    var changed: int = 0
    var legacy_changed: int = 0
    var deltas: Array = []
    var control_fronts: Dictionary = {}
    var variant_fronts: Dictionary = {}
    var sides: Dictionary = {}
    for i: int in range(samples.size()):
        var s: Vector2i = samples[i]
        var a: Array[Vector2i] = control.offscreen_route(s)
        var b: Array[Vector2i] = variant.offscreen_route(s)
        if legacy.offscreen_route(s) != a:
            legacy_changed += 1
        var differs: bool = a != b
        if differs:
            changed += 1
        deltas.append(float(b.size() - a.size()))
        var fa: Dictionary = _gate_front(control, a)
        var fb: Dictionary = _gate_front(variant, b)
        control_fronts[str(fa["front"])] = int(control_fronts.get(str(fa["front"]), 0)) + 1
        variant_fronts[str(fb["front"])] = int(variant_fronts.get(str(fb["front"]), 0)) + 1
        var side: String = _detour_side(b)
        sides[side] = int(sides.get(side, 0)) + 1
        rows.append({
            "sample": i + 1, "spawn": [s.x, s.y],
            "entry": [a[1].x, a[1].y] if a.size() > 1 else null,
            "changed": differs, "first_divergence_index": _first_divergence(a, b),
            "control": {"length": a.size(), "order_problem": control.route_order_problem(a), "gate_front": fa, "route": _pairs(a)},
            "variant": {"length": b.size(), "order_problem": variant.route_order_problem(b), "gate_front": fb,
                "detour_side": side, "route": _pairs(b)},
            "length_delta": b.size() - a.size(),
        })

    # Every candidate cell (not only the 12 previews). The route after the
    # off-screen step depends only on the entry, so group by entry.
    var by_entry: Dictionary = {}
    var cand_changed: int = 0
    var cand_valid_both: int = 0
    var cand_deltas: Array = []
    var cand_cells: Array[Vector2i] = control.spawn_candidate_cells()
    var entry_ok_a: Dictionary = {}
    var entry_ok_b: Dictionary = {}
    for c: Vector2i in cand_cells:
        var ra: String = control.spawn_candidate_rejection(c, entry_ok_a)
        var rb: String = variant.spawn_candidate_rejection(c, entry_ok_b)
        if ra == "" and rb == "":
            cand_valid_both += 1
        var entry: Vector2i = control.nearest_entry(c)
        var key: String = "%d,%d" % [entry.x, entry.y]
        if not by_entry.has(key):
            var pa: Array[Vector2i] = control.shortest_gate_path(entry)
            var pb: Array[Vector2i] = variant.shortest_gate_path(entry)
            by_entry[key] = {"candidates": 0, "changed": pa != pb, "control_length": pa.size(),
                "variant_length": pb.size(), "variant_detour_side": _detour_side(pb)}
        by_entry[key]["candidates"] = int(by_entry[key]["candidates"]) + 1
        if by_entry[key]["changed"]:
            cand_changed += 1
        cand_deltas.append(float(int(by_entry[key]["variant_length"]) - int(by_entry[key]["control_length"])))

    var facilities: Dictionary = {}
    for key: String in FACILITY_CANDIDATES:
        var top_left: Vector2i = FACILITY_CANDIDATES[key]
        var blocked: Array = []
        for dy: int in range(2):
            for dx: int in range(2):
                var c: Vector2i = top_left + Vector2i(dx, dy)
                if variant.cell_at(c) != StageMap.Cell.OPEN:
                    blocked.append([c.x, c.y, variant.cell_at(c)])
        facilities[key] = {"top_left": [top_left.x, top_left.y], "footprint_clear": blocked.is_empty(), "blocked_cells": blocked,
            "note": "occupancy only; target zones, range and firing are LD-DEV-05"}

    var obstacle_touch: Array = _obstacle_touches(variant)
    var control_core: Dictionary = _core_routes(control)
    var variant_core: Dictionary = _core_routes(variant)
    var core_changed: int = 0
    var core_ok: bool = true
    for key: String in variant_core:
        if control_core[key]["cells"] != variant_core[key]["cells"]:
            core_changed += 1
        core_ok = core_ok and variant_core[key]["reached_goal"] and variant_core[key]["crosses_gate"]
    var same_samples: bool = samples == variant_samples
    var control_summary: Dictionary = _map_summary(control, CONTROL_PATH)
    var variant_summary: Dictionary = _map_summary(variant, VARIANT_PATH)
    var all_valid: bool = int(variant_summary["spawn_candidates"]["valid"]) == int(variant_summary["spawn_candidates"]["total"])
    var pass_m04: bool = same_samples and changed >= 1 and all_valid and control_summary["validate_ok"] \
        and variant_summary["validate_ok"] and obstacle_touch.is_empty()

    return {
        "kind": "LD-DEV-01 AC-M04 route comparison (editor route model + core PathNetwork cross-check; not a battle run)",
        "generated_by": "game/tools/ld_dev_01_compare.gd",
        "implementation_sha": sha,
        "engine": Engine.get_version_info()["string"],
        "route_model": "stage_map_definition.gd shortest_gate_path: 4-neighbour BFS that must cross a gate; tie order RIGHT, LEFT, DOWN, UP; spawn -> nearest entry is an off-screen step",
        "obstacle": {"rect_inclusive": [R01_OBSTACLE.position.x, R01_OBSTACLE.position.y, R01_OBSTACLE.end.x - 1, R01_OBSTACLE.end.y - 1],
            "touching_other_walls": obstacle_touch},
        "control": control_summary,
        "variant": variant_summary,
        "same_spawn_samples": same_samples,
        "samples": rows,
        "samples_summary": {
            "count": samples.size(), "changed": changed,
            "length_delta": _stats(deltas),
            "control_gate_front_cells": control_fronts, "variant_gate_front_cells": variant_fronts,
            "variant_detour_sides": sides,
        },
        "legacy_terrain_template_r01": {"stage_id": legacy.stage_id,
            "changed_vs_control": legacy_changed, "count": samples.size(),
            "note": "R-01 reproduction: the existing side obstacles never meet these routes"},
        "all_candidates": {"total": cand_cells.size(), "valid_in_both": cand_valid_both, "changed": cand_changed,
            "length_delta": _stats(cand_deltas), "by_entry": by_entry},
        "core_path_network": {"model": "PathNetwork flow field from each entry cell (8 directions, no corner cutting)",
            "entries_changed": core_changed, "entries": variant_core.size(), "variant_all_reach_goal_via_gate": core_ok,
            "control": control_core, "variant": variant_core},
        "facility_candidates": facilities,
        "ac_m04_pass": pass_m04,
    }


## Wall cells 8-adjacent to the obstacle that are not part of it (border,
## castle wall or other terrain). Empty = the obstacle stands alone.
static func _obstacle_touches(data) -> Array:
    var touching: Array = []
    for y: int in range(R01_OBSTACLE.position.y - 1, R01_OBSTACLE.end.y + 1):
        for x: int in range(R01_OBSTACLE.position.x - 1, R01_OBSTACLE.end.x + 1):
            var c: Vector2i = Vector2i(x, y)
            if R01_OBSTACLE.has_point(c):
                continue
            if data.cell_at(c) == StageMap.Cell.WALL:
                touching.append([c.x, c.y])
    return touching
