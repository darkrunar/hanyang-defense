extends SceneTree
## LD-DEV-01 behaviour probe. Prints what the stage-map contract does today so
## the same script can be run on the baseline and on the fixed commit and the
## two outputs compared line by line. It only uses the API that already existed
## at the baseline (ddabd04): validate(), goal, set_goal(), set_cell(),
## generated_spawn_points(), offscreen_route(), to/from_dictionary(),
## save_json()/load_json().
##
##   godot --headless --path . --script res://game/tools/map_contract_probe.gd

const StageMap := preload("res://game/maps/stage_map_definition.gd")
const TMP_DIR: String = "user://ld_dev_01_probe"


func _initialize() -> void:
    print("== LD-DEV-01 map contract probe")
    _goal_cases()
    _set_goal_on_wall()
    _gate_cases()
    _json_file_round_trip()
    _terrain_route_change()
    quit(0)


func _verdict(data) -> String:
    var result: Dictionary = data.validate()
    return "validate ok=%s errors=%d" % [str(result["ok"]), (result["errors"] as Array).size()]


func _goal_cases() -> void:
    print("-- goal placement (R-02 / AC-M01)")
    var cases: Array = [
        ["inside (31,17)", Vector2i(31, 17)],
        ["outside field (31,30)", Vector2i(31, 30)],
        ["castle wall (24,17)", Vector2i(24, 17)],
        ["gate (31,25)", Vector2i(31, 25)],
        ["out of bounds (70,17)", Vector2i(70, 17)],
    ]
    for c: Array in cases:
        var data = StageMap.flat_template()
        data.goal = c[1]
        print("  direct goal=%s %s: %s" % [str(c[1]), c[0], _verdict(data)])


func _set_goal_on_wall() -> void:
    print("-- set_goal on a wall cell (AC-M01: no auto carve)")
    var data = StageMap.flat_template()
    var wall: Vector2i = Vector2i(24, 17)
    var before: int = data.cell_at(wall)
    var ret: Variant = data.set_goal(wall)
    print("  set_goal(%s) return=%s cell before=%d after=%d goal now=%s %s" % [
        str(wall), str(ret), before, data.cell_at(wall), str(data.goal), _verdict(data)])


func _gate_cases() -> void:
    print("-- gate and wall (AC-M02)")
    var data = StageMap.flat_template()
    var gates: Array[Vector2i] = data.gates.duplicate()
    print("  open gates %s: %s" % [str(gates), _verdict(data)])
    for g: Vector2i in gates:
        data.set_cell(g, StageMap.Cell.WALL)
    print("  gates closed: %s" % _verdict(data))
    var holed = StageMap.flat_template()
    holed.set_cell(Vector2i(24, 17), StageMap.Cell.OPEN)
    var route: Array = holed.offscreen_route(holed.generated_spawn_points()[0])
    var gate_seen: bool = false
    for cell: Vector2i in route:
        if holed.cell_at(cell) == StageMap.Cell.GATE:
            gate_seen = true
    print("  hole at (24,17): %s, sample 1 route len=%d crosses gate=%s" % [_verdict(holed), route.size(), str(gate_seen)])
    var field_gate = StageMap.flat_template()
    field_gate.set_cell(Vector2i(31, 33), StageMap.Cell.GATE)
    print("  extra gate cell in the field (31,33): %s" % _verdict(field_gate))


func _json_file_round_trip() -> void:
    print("-- JSON file round trip (AC-M05)")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
    var original = StageMap.terrain_template()
    original.tuning["wave_count"] = 7
    var path_a: String = TMP_DIR + "/a.json"
    var path_b: String = TMP_DIR + "/b.json"
    print("  save a: %s" % str(original.save_json(path_a)))
    var loaded = StageMap.load_json(path_a)
    print("  loaded wave_count=%s type=%d (TYPE_INT=%d)" % [str(loaded.tuning["wave_count"]), typeof(loaded.tuning["wave_count"]), TYPE_INT])
    print("  save b from loaded: %s" % str(loaded.save_json(path_b)))
    var text_a: String = FileAccess.get_file_as_string(path_a)
    var text_b: String = FileAccess.get_file_as_string(path_b)
    print("  a == b byte-identical: %s (len %d vs %d)" % [str(text_a == text_b), text_a.length(), text_b.length()])
    var short: Dictionary = original.to_dictionary()
    (short["cells"] as Array).resize(10)
    var bad = StageMap.from_dictionary(short)
    if bad == null:
        print("  cells array of 10 (expected %d): loader returned null" % (original.width * original.height))
    else:
        var open_cells: int = 0
        for v: int in bad.cells:
            if v == StageMap.Cell.OPEN:
                open_cells += 1
        print("  cells array of 10 (expected %d): loader returned a map, open cells=%d/%d" % [
            original.width * original.height, open_cells, bad.cells.size()])
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func _terrain_route_change() -> void:
    print("-- terrain changes the route? (R-01 / AC-M04), same 12 spawn cells")
    var flat = StageMap.flat_template()
    var spawns: Array[Vector2i] = flat.generated_spawn_points()
    var old_terrain = StageMap.terrain_template()
    var changed: int = 0
    for s: Vector2i in spawns:
        if flat.offscreen_route(s) != old_terrain.offscreen_route(s):
            changed += 1
    print("  spawns=%s" % str(spawns))
    print("  existing terrain_template: %d/%d routes differ from flat" % [changed, spawns.size()])
    var revised = StageMap.flat_template()
    revised.map_type = StageMap.MapType.TERRAIN
    for y: int in range(29, 31):
        for x: int in range(28, 36):
            revised.set_cell(Vector2i(x, y), StageMap.Cell.WALL)
    changed = 0
    for s: Vector2i in spawns:
        if flat.offscreen_route(s) != revised.offscreen_route(s):
            changed += 1
    print("  revised x28-35,y29-30: %d/%d routes differ from flat, %s" % [changed, spawns.size(), _verdict(revised)])
