extends SceneTree
const Main = preload("res://game/scenes/main.gd")
const Config = preload("res://game/core/config.gd")
const Battle = preload("res://game/core/battle.gd")
var report: Dictionary = {}
func _initialize() -> void:
    call_deferred("review")
func review() -> void:
    var scene = Main.new()
    root.add_child(scene)
    scene.set_process(false)
    scene.set_physics_process(false)
    var modes: Array = []
    for scenario: String in ["move", "network_move"]:
        scene._perf = Main.PerfRecorder.new()
        scene._perf_scenario = scenario
        scene._apply_run_mode()
        modes.append({"scenario": scenario, "declared_zone_set": scene.config.get_str("zone_set"),
            "actual_zones": scene.battle.density.zones.size(), "run_mode": scene.battle.run_mode,
            "expected_zones": 8, "arrival_mode": scene.battle.arrival_mode})
    report["legacy_mode_repro"] = modes
    scene._perf = null
    scene._apply_mode_preset(Config.for_wp003())
    scene.battle.reset()
    scene._mouse_down = true
    scene._paused = true
    var old_id: int = scene.battle.run.run_id
    var key := InputEventKey.new()
    key.keycode = KEY_R
    key.pressed = true
    scene._unhandled_input(key)
    report["restart_input"] = {"old_run_id": old_id, "new_run_id": scene.battle.run.run_id,
        "held_click_after_restart": scene._mouse_down, "paused_after_restart": scene._paused}
    # The original click keeps dispatching even though the run has changed.
    var refusals: int = scene.battle.commands_rejected
    scene._physics_process(1.0 / 60.0)
    report["restart_input"]["old_hold_dispatched_in_new_run"] = scene.battle.commands_rejected > refusals
    scene.queue_free()
    var cfg = Config.for_wp003()
    cfg.values["outer_hp"] = 1000000.0
    var b = Battle.new(cfg)
    while not b.run.ended() and b.sim_time < 300.0:
        b.step(cfg.get_num("fixed_dt"))
    report["f1_large_hp_diagnostic_only"] = {"outer_hp_initial":1000000,
        "state": b.run.run_name(), "time": b.sim_time, "outer_arrivals": b.run.outer_arrivals,
        "core_hp": b.run.core_hp, "spawned": b.sim.spawned_total, "killed": b.sim.killed_total,
        "alive": b.sim.alive_count, "note":"Not an AC pass; only HP changed to measure total outer leakage."}
    var once = Battle.new(Config.for_wp003())
    once.spawning_enabled = false
    once.force_outer_hp(1.0, "review real arrival")
    once.spawn_extra(Vector2(950,530),1,"review trigger")
    once.step(1.0/60.0)
    once.place_recovery(Vector2i(44,13))
    var before_path: int = once.path.path_version
    once._collapse() # explicit duplicate callback required by AC-01
    report["duplicate_collapse_callback"] = {"collapse_count":once.run.collapse_count,
        "collapse_events":once.run.events_of("collapse").size(), "recovery_created_events":once.run.events_of("recovery_created").size(),
        "right_after_already_successful_placement":once.run.recovery_right,
        "path_delta_on_duplicate":once.path.path_version-before_path, "detached_again":once.placement.detached.has(1)}
    var tuned_cfg = Config.for_wp003()
    tuned_cfg.values["outer_hp"] = 360.0
    var tuned = Battle.new(tuned_cfg)
    while not tuned.run.ended() and tuned.sim_time < 300.0:
        tuned.step(tuned_cfg.get_num("fixed_dt"))
    report["f1_hp360_proposal_diagnostic_only"] = {"state":tuned.run.run_name(), "outer_hp":tuned.run.outer_hp,
        "core_hp":tuned.run.core_hp,"outer_arrivals":tuned.run.outer_arrivals,"collapse_count":tuned.run.collapse_count,
        "spawned":tuned.sim.spawned_total,"alive":tuned.sim.alive_count,"time":tuned.sim_time,
        "note":"Only outer_hp changed; not a pass under READY v1.0 HP120."}
    var f = FileAccess.open("res://results/evidence/wp-003/gpt-review/2026-09-15-followup/review_checks.json", FileAccess.WRITE)
    f.store_string(JSON.stringify(report, "  ") + "\n")
    print(JSON.stringify(report))
    quit()
