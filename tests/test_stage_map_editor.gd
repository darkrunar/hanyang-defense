extends RefCounted
## Stage-map planning contract and editor data regression tests.

const StageMap := preload("res://game/maps/stage_map_definition.gd")
const Ld01 := preload("res://tests/test_ld_dev_01_map_reliability.gd")


func run(t: RefCounted) -> void:
    _flat_template_contract(t)
    _closed_gate_is_detected(t)
    _terrain_template_contract(t)
    _serialization_round_trip(t)
    Ld01.new().run(t)


func _flat_template_contract(t: RefCounted) -> void:
    t.case("stage 001: enemies spawn off-screen, enter the field, then use the castle gate")
    var data = StageMap.flat_template()
    var result: Dictionary = data.validate()
    t.check(result["ok"], "flat template passes every planning check")
    t.eq(data.map_type, StageMap.MapType.FLAT, "map type is flat")
    t.check(not data.in_bounds(data.spawn_center), "the single spawn centre is outside the screen")
    t.ge(float(data.entries.size()), 1.0, "at least one field entry is defined")
    t.eq(data.spawn_sample_count, 12, "twelve deterministic random samples are used for validation")
    var samples: Array[Vector2i] = data.generated_spawn_points()
    t.eq(samples.size(), data.spawn_sample_count, "random samples fill the configured radius")
    var distinct_from_center: bool = false
    for spawn: Vector2i in samples:
        t.check(not data.in_bounds(spawn), "random sample is outside the screen")
        if spawn != data.spawn_center:
            distinct_from_center = true
    t.check(distinct_from_center, "samples are scattered around the centre")
    t.eq(data._extra_terrain_count(), 0, "flat map has no natural terrain obstacle")
    t.eq(result["paths"].size(), samples.size(), "every random sample has a tested route")
    for i: int in range(result["paths"].size()):
        var path: Array = result["paths"][i]
        var crossed_gate: bool = false
        var crossed_entry: bool = false
        for cell: Vector2i in path:
            if data.cell_at(cell) == StageMap.Cell.GATE:
                crossed_gate = true
            if data.entries.has(cell):
                crossed_entry = true
        t.eq(path[0], samples[i], "spawn %d path starts off-screen" % (i + 1))
        t.check(crossed_entry, "spawn %d path crosses a field entry" % (i + 1))
        t.check(crossed_gate, "spawn %d path crosses a gate" % (i + 1))
        t.eq(path[path.size() - 1], data.goal, "spawn %d path reaches the objective" % (i + 1))


func _closed_gate_is_detected(t: RefCounted) -> void:
    t.case("closing the main gate makes every outside route invalid")
    var data = StageMap.flat_template()
    var old_gates: Array[Vector2i] = data.gates.duplicate()
    for gate: Vector2i in old_gates:
        data.set_cell(gate, StageMap.Cell.WALL)
    var result: Dictionary = data.validate()
    t.check(not result["ok"], "invalid stage is rejected")
    var found_gate_error: bool = false
    var found_route_error: bool = false
    for check: Dictionary in result["checks"]:
        if check["label"] == "성문" and not check["ok"]:
            found_gate_error = true
        if check["label"] == "침입 전체 동선" and not check["ok"]:
            found_route_error = true
    t.check(found_gate_error, "missing gate is reported")
    t.check(found_route_error, "unreachable spawn routes are reported")


func _terrain_template_contract(t: RefCounted) -> void:
    t.case("terrain stage keeps gate routes while adding field obstacles")
    var data = StageMap.terrain_template()
    var result: Dictionary = data.validate()
    t.check(result["ok"], "terrain template passes every planning check")
    t.eq(data.map_type, StageMap.MapType.TERRAIN, "map type is terrain")
    t.gt(float(data._extra_terrain_count()), 0.0, "terrain obstacles exist outside the castle wall")
    t.eq(result["paths"].size(), data.spawn_sample_count, "terrain routes are tested for every random sample")


func _serialization_round_trip(t: RefCounted) -> void:
    t.case("stage data survives JSON-compatible dictionary round trip")
    var original = StageMap.terrain_template()
    original.stage_id = "stage_round_trip"
    original.stage_name = "왕복 테스트"
    original.tuning["wave_count"] = 7
    var restored = StageMap.from_dictionary(original.to_dictionary())
    t.eq(restored.stage_id, original.stage_id, "stage id")
    t.eq(restored.stage_name, original.stage_name, "stage name")
    t.eq(restored.map_type, original.map_type, "map type")
    t.eq(restored.goal, original.goal, "goal")
    t.eq(restored.spawn_center, original.spawn_center, "spawn centre")
    t.eq(restored.spawn_radius_cells, original.spawn_radius_cells, "spawn radius")
    t.eq(restored.spawn_sample_count, original.spawn_sample_count, "spawn sample count")
    t.eq(restored.entries, original.entries, "field entries")
    t.eq(restored.gates, original.gates, "gate cells")
    t.eq(restored.cells, original.cells, "cell data")
    t.eq(restored.tuning["wave_count"], 7, "tuning")
    t.check(restored.validate()["ok"], "restored stage remains valid")
