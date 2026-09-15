extends SceneTree
## WP-003 F3 evidence (GPT review R-06): the controlled A/B comparison as an
## independent JSON ledger. For each variant: the complete structured state
## right before the placement (must be identical between A and B), after the
## placement, the first observation of the 12 enemies (who saw them, what H1
## knows, target zone), every H1 volley, each enemy's fate, and the end state.
##
##   godot --headless --path . --script res://game/tools/wp003_f3_evidence.gd -- --out=<abs>/f3_ab.json

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const F3Tracker := preload("res://game/tools/f3_tracker.gd")

const H4: int = 4


func _initialize() -> void:
    var out_path: String = ""
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())
    var a: Dictionary = _variant("A", TestMap.RECOVERY_A)
    var b: Dictionary = _variant("B", TestMap.RECOVERY_B)
    var same_before: bool = a["state_before_placement_json"] == b["state_before_placement_json"]
    var report: Dictionary = {
        "contract": "backlog/WP-003.md F3 (D-026): jitter 0, lane offset 0, H4 off, waves off, forced collapse at tick 0, placement at collapse+300 ticks, 12 enemies at (950,450) next tick, 30 s observation",
        "seed": Config.for_wp003().get_int("seed"),
        "state_identical_before_placement": same_before,
        "state_before_placement_sha256": a["state_before_placement_json"].sha256_text(),
        "pass_lines": {"b_shared_only_volleys_min": 1, "kills_b_minus_a_min": 6, "core_damage_a_minus_b_min": 6},
        "summary": {
            "a_kills": a["end"]["killed"], "b_kills": b["end"]["killed"],
            "a_core_damage": a["end"]["core_damage"], "b_core_damage": b["end"]["core_damage"],
            "a_shared_only": a["end"]["h1_shared_only_volleys"], "b_shared_only": b["end"]["h1_shared_only_volleys"],
            "kills_b_minus_a": int(b["end"]["killed"]) - int(a["end"]["killed"]),
            "core_damage_a_minus_b": float(a["end"]["core_damage"]) - float(b["end"]["core_damage"]),
        },
        "A": a, "B": b,
    }
    # The full "before" state is stored once (identical for A and B by construction).
    report["state_before_placement"] = JSON.parse_string(a["state_before_placement_json"])
    a.erase("state_before_placement_json")
    b.erase("state_before_placement_json")
    print(JSON.stringify(report["summary"]))
    print("state identical before placement: %s" % str(same_before))
    if out_path != "":
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify(report, "  "))
            f.close()
            print("written: %s" % out_path)
    quit(0 if same_before else 1)


func _variant(label: String, anchor: Vector2i) -> Dictionary:
    var cfg: Config = Config.for_wp003()
    cfg.values["enemy_speed_jitter"] = 0.0
    cfg.values["enemy_lane_offset"] = 0.0
    var b: Battle = Battle.new(cfg)
    b.waves.enabled = false
    var h4_off: bool = b.set_active(H4, false)
    b.force_outer_hp(1.0, "F3 forced collapse")
    b.spawn_extra(Vector2(950.0, 530.0), 1, "F3 trigger enemy")
    var dt: float = cfg.get_num("fixed_dt")
    var k: int = 0
    while b.run.collapse_count == 0 and k < 300:
        b.step(dt)
        k += 1
    var ct: int = b.run.collapse_tick
    while b.steps < ct + 300:
        b.step(dt)
    var before_json: String = b.full_state_json()
    var res: Placement.Result = b.place_recovery(anchor)
    var tracker: F3Tracker = F3Tracker.new()
    var slots: PackedInt32Array = b.spawn_extra(TestMap.F3_SPAWN_POINT, TestMap.F3_SPAWN_COUNT, "F3 controlled group")
    tracker.begin(b, slots)
    var after_placement: Dictionary = b.full_state()
    b.step(dt)
    tracker.after_tick(b)
    var first: Dictionary = tracker.first_observation(b)
    var first_state: Dictionary = b.full_state()
    var first_shot: Dictionary = {}
    for _i: int in range(int(30.0 / dt) - 1):
        b.step(dt)
        tracker.after_tick(b)
        if first_shot.is_empty() and not tracker.shots.is_empty():
            first_shot = {"shot": tracker.shots[0], "state": b.full_state()}
    return {
        "variant": label, "anchor": [anchor.x, anchor.y], "h4_deactivated": h4_off,
        "collapse_tick": ct, "placement_tick": b.run.recovery_placed_tick,
        "placement_ok": res.ok, "placement_reason": Placement.reject_name(res.reason),
        "state_before_placement_json": before_json,
        "state_after_placement": after_placement,
        "first_observation": first,
        "state_at_first_observation": first_state,
        "first_h1_volley": first_shot,
        "end": tracker.report(b),
        "state_at_end": b.full_state(),
    }
