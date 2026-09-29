extends RefCounted
## LD-DEV-01 map reliability (docs/LEVEL_DEVELOPMENT_PLAN.md AC-M01..M05).
## Negative cases first reproduce the baseline defect they guard (see
## results/evidence/level-development/LD-DEV-01/<run>/probe_*.txt).

const StageMap := preload("res://game/maps/stage_map_definition.gd")
const PathNetwork := preload("res://game/core/path_network.gd")
const Compare := preload("res://game/tools/ld_dev_01_compare.gd")
const Editor := preload("res://game/tools/map_editor.gd")

const TMP_DIR: String = "user://ld_dev_01_tests"
const INSIDE: Vector2i = Vector2i(31, 17)
const OUTSIDE: Vector2i = Vector2i(31, 30)


func run(t: RefCounted) -> void:
    _m01_goal_inside_castle(t)
    _m01_goal_rejections_do_not_edit_the_map(t)
    _m01_editor_refusal_and_load_errors(t)
    _m02_gate_open_closed(t)
    _m02_holes_and_misplaced_gates(t)
    _m02_route_order(t)
    _m03_candidate_model(t)
    _m03_candidate_rejections(t)
    _m04_stage003_terrain_changes_routes(t)
    _m05_file_round_trip(t)
    _m05_load_policy_rejects_broken_files(t)


static func _check_ok(result: Dictionary, label: String) -> bool:
    for check: Dictionary in result["checks"]:
        if check["label"] == label:
            return check["ok"]
    return false


# --------------------------------------------------------------- AC-M01 ---

func _m01_goal_inside_castle(t: RefCounted) -> void:
    t.case("AC-M01 objective must be inside the castle (R-02)")
    var data = StageMap.flat_template()
    t.eq(data.goal_rejection(INSIDE), "", "inside (31,17) is accepted")
    t.eq(data.set_goal(INSIDE), "", "set_goal(31,17) succeeds")
    t.check(data.validate()["ok"], "stage with the inside objective validates")
    # R-02: the baseline validator passed this map.
    data.goal = OUTSIDE
    var result: Dictionary = data.validate()
    t.check(not result["ok"], "R-02: objective outside the castle (31,30) fails validation")
    t.check(not _check_ok(result, "최종 방어 목표"), "the objective check itself names the failure")
    t.check(not _check_ok(result, "성문 외 진입 차단"), "an outside objective is reachable with the gates closed")
    t.eq(data.goal_rejection(OUTSIDE), StageMap.GOAL_OUTSIDE_CASTLE, "(31,30) is rejected as outside")
    var cases: Array = [
        [Vector2i(24, 17), StageMap.GOAL_WALL, "castle wall"],
        [Vector2i(24, 10), StageMap.GOAL_WALL, "castle wall corner"],
        [Vector2i(31, 25), StageMap.GOAL_GATE, "gate"],
        [Vector2i(32, 25), StageMap.GOAL_GATE, "second gate cell"],
        [Vector2i(31, 35), StageMap.GOAL_ENTRY, "field entry"],
        [Vector2i(70, 17), StageMap.GOAL_OUT_OF_BOUNDS, "out of bounds (x)"],
        [Vector2i(31, -1), StageMap.GOAL_OUT_OF_BOUNDS, "out of bounds (y)"],
        [Vector2i(10, 30), StageMap.GOAL_OUTSIDE_CASTLE, "open field"],
    ]
    for c: Array in cases:
        t.eq(data.goal_rejection(c[0]), c[1], "%s %s rejected" % [c[2], str(c[0])])
    for inner: Vector2i in [Vector2i(25, 11), Vector2i(38, 11), Vector2i(25, 24), Vector2i(38, 24)]:
        t.eq(data.goal_rejection(inner), "", "interior corner %s accepted" % str(inner))
    var no_castle = StageMap.flat_template()
    no_castle.castle_rect = Rect2i()
    t.eq(no_castle.goal_rejection(INSIDE), StageMap.GOAL_NO_CASTLE, "no castle defined: rejected, not guessed")


func _m01_goal_rejections_do_not_edit_the_map(t: RefCounted) -> void:
    t.case("AC-M01 a rejected objective is not moved and no wall is removed")
    var data = StageMap.flat_template()
    var before: PackedByteArray = data.cells.duplicate()
    for cell: Vector2i in [Vector2i(24, 17), OUTSIDE, Vector2i(31, 25), Vector2i(99, 99)]:
        var code: String = data.set_goal(cell)
        t.ne(code, "", "set_goal%s refused (%s)" % [str(cell), code])
        t.eq(data.goal, INSIDE, "objective stays at (31,17) after refusing %s" % str(cell))
    t.eq(data.cells, before, "no cell changed (baseline set_goal carved the wall at (24,17))")
    t.check(data.validate()["ok"], "map still validates after the refusals")
    t.check(StageMap.goal_rejection_message(StageMap.GOAL_OUTSIDE_CASTLE).contains("성 내부"),
        "the rejection message says where the objective may go")


func _m01_editor_refusal_and_load_errors(t: RefCounted) -> void:
    t.case("AC-M01/M05 editor: objective tool refuses with a reason; broken files are refused")
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    var ed: Node2D = Editor.new()
    tree.root.add_child(ed)
    if not ed.is_node_ready():
        ed._ready()
    ed.set_process(false)
    ed.active_tool = Editor.Tool.GOAL
    var before: PackedByteArray = ed.data.cells.duplicate()
    ed._apply_tool(OUTSIDE)
    t.eq(ed.data.goal, INSIDE, "editor: objective not moved to (31,30)")
    t.check(ed._status.text.contains("목표 거절") and ed._status.text.contains("성 밖"),
        "editor status names the refusal (%s)" % ed._status.text)
    t.eq(ed.rejected_goal, OUTSIDE, "refused cell is marked on the map")
    ed._apply_tool(Vector2i(24, 17))
    t.eq(ed.data.cells, before, "editor: clicking the wall with the objective tool leaves the wall")
    t.check(ed._status.text.contains("성벽"), "wall refusal reason shown")
    ed._apply_tool(Vector2i(31, 20))
    t.eq(ed.data.goal, Vector2i(31, 20), "an inside cell is accepted")
    t.eq(ed.rejected_goal, Vector2i(-1, -1), "refusal mark cleared after an accepted edit")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
    var bad_path: String = TMP_DIR + "/editor_broken.json"
    var raw: Dictionary = JSON.parse_string(StageMap.flat_template().to_json_text())
    raw["tuning"]["wave_count"] = 2.5
    var f: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
    f.store_string(JSON.stringify(raw))
    f.close()
    var kept = ed.data
    t.check(not ed._load_file(bad_path), "editor refuses a file with a fractional wave_count")
    t.check(ed.data == kept, "the map on screen stays; no template substituted")
    t.check(ed._status.text.contains("불러오기 거절") and ed._status.text.contains("wave_count"),
        "status gives the reason (%s)" % ed._status.text.left(80))
    t.check(ed._load_file(Compare.VARIANT_PATH, Compare.CONTROL_PATH), "R-01 button path loads the revised map")
    t.eq(ed.data.stage_id, "stage_003_r01", "revised map on screen")
    t.eq(ed.compare_paths.size(), 12, "control routes kept for the grey overlay")
    t.check(ed.validation.get("ok", false), "revised map validates in the editor")
    var drive: RegEx = RegEx.create_from_string("(^|[^a-z])[A-Za-z]:[/" + char(92) + char(92) + "]")
    t.check(ed._status.text.contains("res://") and drive.search(ed._status.text) == null,
        "status shows the res:// path, not a local absolute path (%s)" % ed._status.text)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
    tree.root.remove_child(ed)
    ed.free()


# --------------------------------------------------------------- AC-M02 ---

func _m02_gate_open_closed(t: RefCounted) -> void:
    t.case("AC-M02 gate open: reachable, gate closed: not reachable (editor and core path agree)")
    var data = StageMap.flat_template()
    t.check(data.goal_reachable_from_entries(false), "gates open: objective reachable from the entries")
    t.check(not data.goal_reachable_from_entries(true), "gates treated as closed: objective unreachable")
    t.eq(data.wall_leak_cells().size(), 0, "sealed castle has no leak")
    var core: PathNetwork = data.build_path()
    t.check(core.probe_all_routes_reachable(), "core PathNetwork: every entry reaches the objective")
    var closed = StageMap.flat_template()
    for gate: Vector2i in closed.gates.duplicate():
        closed.set_cell(gate, StageMap.Cell.WALL)
    t.check(not closed.goal_reachable_from_entries(false), "gates walled: objective unreachable")
    var closed_core: PathNetwork = closed.build_path()
    t.eq(closed_core.unreachable_route_ids().size(), closed.entries.size(), "core PathNetwork agrees: every entry cut off")
    var result: Dictionary = closed.validate()
    t.check(not _check_ok(result, "생성 후보 전수"), "closed gates: every spawn candidate is unreachable")
    t.eq(int(result["spawn_candidates"]["rejected_counts"][StageMap.SPAWN_UNREACHABLE]),
        int(result["spawn_candidates"]["total"]), "all candidates reported unreachable")
    var reopened = StageMap.flat_template()
    for gate: Vector2i in reopened.gates.duplicate():
        reopened.set_cell(gate, StageMap.Cell.WALL)
    reopened.set_cell(Vector2i(31, 25), StageMap.Cell.GATE)
    t.check(reopened.goal_reachable_from_entries(false) and reopened.validate()["ok"],
        "reopening one gate cell restores the route")


func _m02_holes_and_misplaced_gates(t: RefCounted) -> void:
    t.case("AC-M02 openings other than the gate are found and located")
    for hole: Vector2i in [Vector2i(24, 17), Vector2i(27, 25), Vector2i(39, 12), Vector2i(30, 10)]:
        var data = StageMap.flat_template()
        data.set_cell(hole, StageMap.Cell.OPEN)
        var result: Dictionary = data.validate()
        t.check(not result["ok"], "hole %s fails validation" % str(hole))
        t.check(not _check_ok(result, "성문 외 진입 차단"), "hole %s: gate-only entry check fails" % str(hole))
        t.check(data.wall_leak_cells().has(hole), "hole %s is the reported leak cell" % str(hole))
        t.check(data.goal_reachable_from_entries(true), "hole %s: objective reachable with gates closed" % str(hole))
    var entry_hole = StageMap.flat_template()
    entry_hole.set_cell(Vector2i(24, 20), StageMap.Cell.ENTRY)
    t.check(entry_hole.wall_leak_cells().has(Vector2i(24, 20)), "an entry painted on the wall is also a leak")
    var field_gate = StageMap.flat_template()
    field_gate.set_cell(Vector2i(31, 33), StageMap.Cell.GATE)
    var result: Dictionary = field_gate.validate()
    t.check(field_gate.misplaced_gates().has(Vector2i(31, 33)), "gate cell out in the field is misplaced")
    t.check(not _check_ok(result, "성문 위치"), "misplaced gate fails the gate-position check (baseline passed)")
    t.check(not _check_ok(result, "침입 전체 동선"), "routes that meet the field gate first fail the order check")
    var corner = StageMap.flat_template()
    corner.set_cell(Vector2i(39, 25), StageMap.Cell.GATE)
    t.check(corner.misplaced_gates().has(Vector2i(39, 25)), "gate on a wall corner is misplaced")


func _m02_route_order(t: RefCounted) -> void:
    t.case("AC-M02 every route keeps off-screen -> entry -> gate -> objective")
    var data = StageMap.flat_template()
    var result: Dictionary = data.validate()
    var problems: Array = result["route_problems"]
    t.eq(problems.size(), data.spawn_sample_count, "one order verdict per sample")
    for i: int in range(problems.size()):
        t.eq(problems[i], "", "sample %d order ok" % (i + 1))
    var route: Array = result["paths"][0]
    var gate_at: int = -1
    for i: int in range(route.size()):
        if gate_at < 0 and data.cell_at(route[i]) == StageMap.Cell.GATE:
            gate_at = i
    t.check(gate_at > 1, "gate comes after the entry (index %d)" % gate_at)
    var outside_before: bool = true
    for i: int in range(1, gate_at):
        outside_before = outside_before and not data.castle_rect.has_point(route[i])
    var inside_after: bool = true
    for i: int in range(gate_at, route.size()):
        inside_after = inside_after and data.castle_rect.has_point(route[i])
    t.check(outside_before and inside_after, "outside before the gate, inside from the gate on")
    # LD-02: a map whose objective is reached by going through the gate and back out.
    var back_out = StageMap.flat_template()
    back_out.goal = OUTSIDE
    t.eq(back_out.route_order_problem(back_out.offscreen_route(Vector2i(31, 40))), "left_castle_after_gate",
        "gate then back outside to an outside objective is rejected")
    var spawn: Vector2i = Vector2i(31, 40)
    var good: Array = data.offscreen_route(spawn)
    var skipped: Array = good.duplicate()
    skipped.remove_at(3)
    t.eq(data.route_order_problem(skipped), "discontinuous", "a route that skips a cell is rejected")
    var no_entry: Array = good.duplicate()
    no_entry.remove_at(1)
    t.eq(data.route_order_problem(no_entry), "entry_not_first", "a route that does not start at an entry is rejected")
    t.eq(data.route_order_problem([]), "no_route", "empty route is rejected")


# --------------------------------------------------------------- AC-M03 ---

func _m03_candidate_model(t: RefCounted) -> void:
    t.case("AC-M03 spawn candidates: the whole radius, distinct from the 12 preview samples")
    var data = StageMap.flat_template()
    var expected: Dictionary = {0.5: 5, 1.0: 9, 3.0: 45}
    for r: float in expected:
        data.spawn_radius_cells = r
        t.eq(data.spawn_candidate_cells().size(), expected[r], "radius %.1f: %d candidate cells" % [r, expected[r]])
    data.spawn_radius_cells = 3.0
    var candidates: Array[Vector2i] = data.spawn_candidate_cells()
    var seen: Dictionary = {}
    var outside_model: int = 0
    for s: int in range(400):
        for p: Vector2i in data.generated_spawn_points(s):
            seen[p] = true
            if not candidates.has(p):
                outside_model += 1
    t.eq(outside_model, 0, "4,800 generated points (400 seeds x 12): none outside the candidate model")
    t.eq(seen.size(), candidates.size(), "every candidate cell is actually produced: the model is exact, not a loose bound")
    var result: Dictionary = data.validate()
    t.eq(int(result["spawn_candidates"]["total"]), 45, "validation checks all 45 candidates")
    t.eq(int(result["spawn_candidates"]["valid"]), 45, "all 45 are off-screen and reach the objective via the gate")
    t.eq((result["paths"] as Array).size(), 12, "the 12 preview routes stay a separate list")


func _m03_candidate_rejections(t: RefCounted) -> void:
    t.case("AC-M03 on-screen, wall and unreachable candidates are counted with their reason")
    # Centre one row below the map: the top of the radius reaches the screen.
    var near = StageMap.flat_template()
    near.spawn_center = Vector2i(31, 37)
    var report: Dictionary = near.spawn_candidate_report()
    var counts: Dictionary = report["rejected_counts"]
    t.gt(float(counts[StageMap.SPAWN_ON_SCREEN]), 0.0, "entry cells inside the radius are on-screen candidates (%d)" % counts[StageMap.SPAWN_ON_SCREEN])
    t.gt(float(counts[StageMap.SPAWN_ON_SCREEN_WALL]), 0.0, "bottom border walls inside the radius are counted (%d)" % counts[StageMap.SPAWN_ON_SCREEN_WALL])
    var result: Dictionary = near.validate()
    t.check(_check_ok(result, "랜덤 분산 표본"), "the 12 preview samples still pass (the generator skips on-screen cells)")
    t.check(not _check_ok(result, "생성 후보 전수"), "the full candidate check fails: 12 samples are no guarantee")
    var sample: Dictionary = report["rejected"][0]
    t.check(sample.has("cell") and sample.has("reason"), "each rejected cell is listed with its reason")
    # Boundary: centre exactly r+1 rows below the last map row keeps every candidate off-screen.
    var edge = StageMap.flat_template()
    edge.spawn_center = Vector2i(31, 35 + 4)
    t.eq(int(edge.spawn_candidate_report()["valid"]), 45, "centre (31,39), r=3: the top row y=36 is off-screen")
    edge.spawn_center = Vector2i(31, 35 + 3)
    t.gt(float(edge.spawn_candidate_report()["rejected_counts"][StageMap.SPAWN_ON_SCREEN]), 0.0,
        "centre (31,38), r=3: the top row y=35 is on-screen")
    # Isolate entry (33,35): wall above it and turn its neighbour entry into wall.
    var cut = StageMap.flat_template()
    cut.set_cell(Vector2i(33, 34), StageMap.Cell.WALL)
    cut.set_cell(Vector2i(32, 35), StageMap.Cell.WALL)
    var cut_report: Dictionary = cut.spawn_candidate_report()
    var unreachable: int = int(cut_report["rejected_counts"][StageMap.SPAWN_UNREACHABLE])
    t.gt(float(unreachable), 0.0, "candidates whose nearest entry is sealed are unreachable (%d)" % unreachable)
    var all_via_33: bool = true
    for item: Dictionary in cut_report["rejected"]:
        var cell: Vector2i = Vector2i(item["cell"][0], item["cell"][1])
        all_via_33 = all_via_33 and cut.nearest_entry(cell) == Vector2i(33, 35)
    t.check(all_via_33, "every unreachable candidate uses the sealed entry (33,35)")
    t.check(not _check_ok(cut.validate(), "생성 후보 전수"), "validation reports it")


# --------------------------------------------------------------- AC-M04 ---

func _m04_stage003_terrain_changes_routes(t: RefCounted) -> void:
    t.case("AC-M04 Stage003 revised obstacle vs no-terrain control, same spawn cells (R-01)")
    var control_load: Dictionary = StageMap.load_json_result(Compare.CONTROL_PATH)
    var variant_load: Dictionary = StageMap.load_json_result(Compare.VARIANT_PATH)
    t.check(control_load["ok"], "control fixture loads (%s)" % str(control_load["errors"]))
    t.check(variant_load["ok"], "revised fixture loads (%s)" % str(variant_load["errors"]))
    if not (control_load["ok"] and variant_load["ok"]):
        return
    var control = control_load["data"]
    var variant = variant_load["data"]
    t.eq(FileAccess.get_file_as_string(Compare.CONTROL_PATH), Compare.build_control().to_json_text(),
        "control file matches its rule (no hand drift)")
    t.eq(FileAccess.get_file_as_string(Compare.VARIANT_PATH), Compare.build_variant().to_json_text(),
        "revised file matches its rule (no hand drift)")
    t.check(control.validate()["ok"] and variant.validate()["ok"], "both maps pass every check")
    t.eq(variant.map_type, StageMap.MapType.TERRAIN, "revised map is a terrain map")
    var obstacle: int = 0
    for y: int in range(1, variant.height - 1):
        for x: int in range(1, variant.width - 1):
            var c: Vector2i = Vector2i(x, y)
            if variant.cell_at(c) != control.cell_at(c):
                obstacle += 1
                if not (Compare.R01_OBSTACLE.has_point(c) and variant.cell_at(c) == StageMap.Cell.WALL):
                    t.check(false, "difference %s is outside the x28~35,y29~30 obstacle" % str(c))
    t.eq(obstacle, 16, "the only difference is the 8x2 obstacle")
    t.eq(Compare._obstacle_touches(variant).size(), 0, "obstacle touches neither the border nor the castle wall")
    var samples: Array[Vector2i] = control.generated_spawn_points()
    t.eq(variant.generated_spawn_points(), samples, "both maps use the same 12 spawn cells (explicit spawn_seed)")
    t.eq(control.spawn_seed, Compare.R01_SPAWN_SEED, "seed is written in the file, not derived from stage_id")
    var changed: int = 0
    for s: Vector2i in samples:
        if control.offscreen_route(s) != variant.offscreen_route(s):
            changed += 1
    t.ge(float(changed), 1.0, "at least one of 12 routes changes (%d/12)" % changed)
    var report: Dictionary = variant.spawn_candidate_report()
    t.eq(int(report["valid"]), int(report["total"]), "every candidate cell still reaches the objective (%d/%d)" % [report["valid"], report["total"]])
    var legacy = StageMap.terrain_template()
    var legacy_changed: int = 0
    for s: Vector2i in samples:
        if control.offscreen_route(s) != legacy.offscreen_route(s):
            legacy_changed += 1
    t.note("R-01 baseline: existing terrain_template changes %d/12 of the same routes" % legacy_changed)
    var core_a: PathNetwork = control.build_path()
    var core_b: PathNetwork = variant.build_path()
    t.check(core_b.probe_all_routes_reachable(), "core PathNetwork: every entry reaches the objective on the revised map")
    var cost_changed: int = 0
    var grid = variant.build_grid()
    for e: Vector2i in variant.cells_of(StageMap.Cell.ENTRY):
        if core_a.dist[grid.idx(e.x, e.y)] != core_b.dist[grid.idx(e.x, e.y)]:
            cost_changed += 1
    t.ge(float(cost_changed), 1.0, "core PathNetwork distance changes for %d/5 entries" % cost_changed)


# --------------------------------------------------------------- AC-M05 ---

func _m05_file_round_trip(t: RefCounted) -> void:
    t.case("AC-M05 real JSON file: save -> load -> identical map, settings, seed, checks and routes")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
    var original = Compare.build_variant()
    original.stage_id = "stage_ld01_round_trip"
    original.stage_name = "파일 왕복 · 한글 이름"
    original.tuning["wave_count"] = 7
    original.tuning["spawn_rate"] = 7.3
    original.tuning["test_duration"] = 45.25
    original.spawn_seed = 123456789
    original.spawn_radius_cells = 3.5
    # Paint an extra entry after the others so the in-memory list order differs
    # from the canonical file order.
    original.set_cell(Vector2i(0, 30), StageMap.Cell.ENTRY)
    var before: Dictionary = original.validate()
    var path_a: String = TMP_DIR + "/a.json"
    var path_b: String = TMP_DIR + "/b.json"
    t.check(original.save_json(path_a), "saved to a real file")
    var loaded_result: Dictionary = StageMap.load_json_result(path_a)
    t.check(loaded_result["ok"], "file loads (%s)" % str(loaded_result["errors"]))
    if not loaded_result["ok"]:
        return
    var loaded = loaded_result["data"]
    t.eq(loaded.to_dictionary(), original.to_dictionary(), "every stored field is equal")
    t.eq(typeof(loaded.tuning["wave_count"]), TYPE_INT, "wave_count comes back as int (baseline: float 7.0)")
    t.eq(loaded.tuning["spawn_rate"], 7.3, "spawn_rate keeps full precision")
    t.eq(loaded.tuning["test_duration"], 45.25, "test_duration")
    t.eq(loaded.spawn_seed, 123456789, "spawn_seed")
    t.eq(loaded.spawn_radius_cells, 3.5, "spawn radius")
    t.eq(loaded.cells, original.cells, "cells")
    t.eq(loaded.generated_spawn_points(), original.generated_spawn_points(), "same 12 preview spawn cells")
    var after: Dictionary = loaded.validate()
    t.eq(after["checks"], before["checks"], "same check list and verdicts")
    t.eq(after["paths"], before["paths"], "same preview routes")
    t.eq(after["spawn_candidates"], before["spawn_candidates"], "same full candidate report")
    t.check(loaded.save_json(path_b), "re-saved")
    t.eq(FileAccess.get_file_as_string(path_b), FileAccess.get_file_as_string(path_a),
        "re-saved file is byte-identical (baseline differed: 7 -> 7.0)")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))


func _m05_load_policy_rejects_broken_files(t: RefCounted) -> void:
    t.case("AC-M05 load policy: integers must be whole, broken files are refused with a reason")
    var good: Dictionary = StageMap.flat_template().to_dictionary()
    var float_ints: Dictionary = JSON.parse_string(JSON.stringify(good))
    t.eq(typeof(float_ints["width"]), TYPE_FLOAT, "Godot's JSON parser returns numbers as float")
    var parsed: Dictionary = StageMap.parse_dictionary(float_ints)
    t.check(parsed["ok"], "whole-number floats are accepted and converted")
    t.eq(typeof(parsed["data"].width), TYPE_INT, "width is int after load")
    var cases: Array = [
        ["tuning.wave_count", func(d: Dictionary) -> void: d["tuning"]["wave_count"] = 2.5],
        ["cells: 길이", func(d: Dictionary) -> void: (d["cells"] as Array).resize(10)],
        ["cells[5]: 알 수 없는", func(d: Dictionary) -> void: d["cells"][5] = 9],
        ["cells[7]: 정수가", func(d: Dictionary) -> void: d["cells"][7] = 0.5],
        ["gates: 목록", func(d: Dictionary) -> void: d["gates"] = [[31, 25]]],
        ["entries: 목록", func(d: Dictionary) -> void: (d["entries"] as Array).append([0, 20])],
        ["format_version", func(d: Dictionary) -> void: d["format_version"] = 99],
        ["map_type", func(d: Dictionary) -> void: d["map_type"] = "hills"],
        ["goal", func(d: Dictionary) -> void: d["goal"] = [31.5, 17]],
        ["spawn_seed", func(d: Dictionary) -> void: d["spawn_seed"] = "abc"],
        ["cells: 필수", func(d: Dictionary) -> void: d.erase("cells")],
    ]
    for c: Array in cases:
        # Start from parsed JSON (untyped arrays, float numbers) like a real file.
        var raw: Dictionary = JSON.parse_string(JSON.stringify(good))
        (c[1] as Callable).call(raw)
        var r: Dictionary = StageMap.parse_dictionary(raw)
        var named: bool = false
        for e: String in r["errors"]:
            if e.begins_with(c[0]) or e.contains(c[0]):
                named = true
        t.check(not r["ok"] and r["data"] == null and named, "refused with '%s' (%s)" % [c[0], str(r["errors"]).left(90)])
    t.check(StageMap.from_dictionary({"width": 64}) == null, "from_dictionary returns null instead of an empty map")
    var legacy: Dictionary = good.duplicate(true)
    legacy["format_version"] = 3
    legacy.erase("spawn_seed")
    var legacy_map = StageMap.from_dictionary(legacy)
    t.check(legacy_map != null and legacy_map.spawn_seed == -1, "v3 file without spawn_seed loads (seed derived from stage_id)")
    t.eq(legacy_map.generated_spawn_points(), StageMap.flat_template().generated_spawn_points(), "v3 file keeps its old samples")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
    var bad_path: String = TMP_DIR + "/broken.json"
    var f: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
    f.store_string("{\"width\": 64, ")
    f.close()
    var broken: Dictionary = StageMap.load_json_result(bad_path)
    t.check(not broken["ok"] and str(broken["errors"]).contains("JSON"), "truncated file: JSON error with line (%s)" % str(broken["errors"]))
    t.check(not StageMap.load_json_result(TMP_DIR + "/missing.json")["ok"], "missing file is an error")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))
