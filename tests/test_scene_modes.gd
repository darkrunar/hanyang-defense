extends RefCounted
## WP-003 GPT review R-02 / R-03: the REAL scene entry paths. Instantiates the
## playable scene headlessly, selects every scripted scenario the way the
## command line does (`_apply_run_mode`), and asserts the simulation the scene
## actually holds: zone table identical to the 8 approved WP-001 zones for the
## legacy scenarios (id / centre / radius), mode fields, fixture; and that a
## restart through the R key drops the previous run's held click and pause.

const Main := preload("res://game/scenes/main.gd")
const Config := preload("res://game/core/config.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const PerfRecorder := preload("res://game/tools/perf_recorder.gd")


func run(t: RefCounted) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    if tree == null:
        t.check(false, "scene tests need a SceneTree main loop")
        return
    _legacy_perf_scenarios(t, tree)
    _legacy_capture_scenarios(t, tree)
    _wp003_scenarios(t, tree)
    _restart_clears_input(t, tree)


static func _new_scene(tree: SceneTree) -> Node2D:
    var scene: Node2D = Main.new()
    scene._art_mode = "greybox"   # WP-003 scene suites render the grey box
    tree.root.add_child(scene)
    if not scene.is_node_ready():
        # The suite runs inside SceneTree._initialize(), before the root has
        # been ready-notified, so the engine does not call _ready() here yet.
        # Call the real entry point ourselves: default WP-003 config, Battle, HUD.
        scene._ready()
    scene.set_process(false)
    scene.set_physics_process(false)
    return scene


static func _drop(scene: Node2D) -> void:
    scene.get_parent().remove_child(scene)
    scene.free()


## The 8 approved zones, exactly as game/maps/hanyang_test_map.gd declares them.
func _assert_legacy_zones(t: RefCounted, scene: Node2D, label: String) -> void:
    var zones: Array = scene.battle.zone_state()
    t.eq(zones.size(), 8, "%s: the scene's detector holds exactly 8 zones" % label)
    for i: int in range(mini(zones.size(), TestMap.ZONES.size())):
        var z: Dictionary = zones[i]
        var ref: Array = TestMap.ZONES[i]
        var same: bool = int(z["id"]) == i and z["name"] == ref[0] \
            and float(z["center"][0]) == float(ref[1]) and float(z["center"][1]) == float(ref[2]) \
            and float(z["radius"]) == float(ref[3])
        t.check(same, "%s: Z%d id/name/centre/radius match the WP-001 table (%s)" % [label, i, str(z)])
    t.eq(scene.battle.density.zones.size(), 8, "%s: live DensityDetector has 8 zones" % label)
    t.eq(scene.battle.zone_set, "wp001", "%s: battle.zone_set" % label)
    t.eq(scene.battle.run_mode, "sandbox", "%s: run_mode sandbox" % label)
    t.eq(scene.battle.arrival_mode, "immediate", "%s: arrival_mode immediate" % label)
    t.eq(scene.battle.sim.arrival_mode, "immediate", "%s: EnemySim arrival_mode immediate" % label)
    t.eq(scene.battle.district_rules, false, "%s: district rules off" % label)
    t.eq(scene.battle.waves.enabled, false, "%s: wave director off" % label)
    t.eq(scene.battle.path.goal_cell, TestMap.GOAL_CELL, "%s: goal is the WP-001 core cell" % label)
    t.eq(scene.battle.placement.count_of(0), 0, "%s: no jangseung in the fixture" % label)


func _legacy_perf_scenarios(t: RefCounted, tree: SceneTree) -> void:
    t.case("R-02 scene path: --perf move/combat/network_move/network_combat keep the 8 WP-001 zones")
    var expect: Dictionary = {
        "move": ["wp001", "wp001", 4], "combat": ["wp001", "wp001", 4],
        "network_move": ["wp002", "b", 16], "network_combat": ["wp002", "b", 16],
    }
    for sc: String in expect:
        var scene: Node2D = _new_scene(tree)
        t.eq(scene.battle.density.zones.size(), 10, "%s: the scene starts from the WP-003 default (10 zones) before the scenario is applied" % sc)
        scene._perf = PerfRecorder.new()
        scene._perf_scenario = sc
        scene._apply_run_mode()
        _assert_legacy_zones(t, scene, "perf " + sc)
        t.eq(scene.battle.targeting_mode, expect[sc][0], "%s: targeting_mode" % sc)
        t.eq(scene.config.get_str("fixture"), expect[sc][1], "%s: fixture" % sc)
        t.eq(scene.battle.placement.structures.size(), expect[sc][2], "%s: structure count" % sc)
        t.eq(scene.battle.benchmark_hold_alive, true, "%s: load held for the benchmark" % sc)
        t.eq(scene.battle.combat_enabled, not sc.ends_with("move"), "%s: combat switch" % sc)
        # The manifest the perf JSON will carry comes from the live detector.
        t.eq(scene.battle.zone_state().size(), 8, "%s: zone manifest source has 8 entries" % sc)
        scene._perf = null
        _drop(scene)


func _legacy_capture_scenarios(t: RefCounted, tree: SceneTree) -> void:
    t.case("R-02 scene path: --capture ac01/ac02/ac06/wp002_a keep the 8 WP-001 zones")
    for sc: String in ["ac01", "ac02", "ac06", "wp002_a"]:
        var scene: Node2D = _new_scene(tree)
        scene._capture_name = sc
        scene._capture_dir = "user://"
        scene._apply_run_mode()
        _assert_legacy_zones(t, scene, "capture " + sc)
        if sc.begins_with("ac0"):
            t.eq(scene.battle.targeting_mode, "wp001", "%s: WP-001 global targeting" % sc)
            t.eq(scene.battle.placement.structures.size(), 4, "%s: the four WP-001 hwachas" % sc)
        else:
            t.eq(scene.battle.targeting_mode, "wp002", "%s: WP-002 targeting" % sc)
            t.eq(scene.battle.placement.structures.size(), 0, "%s: fixture A starts empty" % sc)
            t.eq(scene.battle.spawning_enabled, false, "%s: no spawning" % sc)
        scene._capture_name = ""
        _drop(scene)


func _wp003_scenarios(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene path: WP-003 scenarios keep 10 zones, waves mode, outer HP 360 (D-032)")
    for sc: String in ["collapse_move", "collapse_combat"]:
        var scene: Node2D = _new_scene(tree)
        scene._perf = PerfRecorder.new()
        scene._perf_scenario = sc
        scene._apply_run_mode()
        t.eq(scene.battle.density.zones.size(), 10, "%s: 10 zones" % sc)
        t.eq(scene.battle.run_mode, "waves", "%s: waves mode" % sc)
        t.eq(scene.battle.arrival_mode, "after_fire", "%s: after_fire arrivals" % sc)
        t.eq(scene.battle.waves.enabled, false, "%s: finite waves off for the benchmark" % sc)
        t.eq(scene.battle.run.outer_hp, 1000000.0, "%s: benchmark outer HP 1e6 until the trigger" % sc)
        t.eq(scene.battle.run.core_invulnerable, true, "%s: benchmark core invulnerable" % sc)
        t.eq(scene.battle.placement.structures.size(), 18, "%s: fixture C" % sc)
        scene._perf = null
        _drop(scene)
    var f2: Node2D = _new_scene(tree)
    f2._capture_name = "wp003_f2"
    f2._capture_dir = "user://"
    f2._apply_run_mode()
    t.eq(f2.battle.density.zones.size(), 10, "wp003_f2: 10 zones")
    t.eq(f2.battle.run.outer_hp, 360.0, "wp003_f2: outer HP 360")
    t.eq(f2.battle.run.outer_hp_max, 360.0, "wp003_f2: outer HP max 360")
    t.eq(f2.battle.waves.enabled, true, "wp003_f2: real waves")
    f2._capture_name = ""
    _drop(f2)
    for v: String in ["wp003_f3a", "wp003_f3b"]:
        var f3: Node2D = _new_scene(tree)
        f3._capture_name = v
        f3._capture_dir = "user://"
        f3._apply_run_mode()
        t.eq(f3.battle.density.zones.size(), 10, "%s: 10 zones" % v)
        t.eq(f3.config.get_num("enemy_speed_jitter"), 0.0, "%s: jitter 0" % v)
        t.eq(f3.config.get_num("enemy_lane_offset"), 0.0, "%s: lane offset 0" % v)
        t.eq(f3.battle.waves.enabled, false, "%s: waves off" % v)
        t.eq(f3.battle.placement.get_structure(4).active, false, "%s: H4 deactivated" % v)
        t.eq(f3.battle.run.outer_hp, 1.0, "%s: outer HP forced to 1 for the collapse trigger" % v)
        t.eq(f3.battle.sim.alive_count, 1, "%s: trigger enemy on the outer stronghold" % v)
        f3._capture_name = ""
        _drop(f3)
    var play: Node2D = _new_scene(tree)
    t.eq(play.battle.run.outer_hp, 360.0, "interactive default run: outer HP 360")
    t.eq(play.battle.run_mode, "waves", "interactive default run: waves mode")
    _drop(play)


func _restart_clears_input(t: RefCounted, tree: SceneTree) -> void:
    t.case("R-03 real keys: held click / pause / stale run_id never carry into the new run (WP-004: R -> confirm -> new run)")
    var scene: Node2D = _new_scene(tree)
    scene._perf = null
    scene._capture_name = ""
    var dt: float = scene.config.get_num("fixed_dt")
    # Interactive launch starts on TITLE (WP-004); the game start button opens the run.
    t.eq(scene.flow.state_name(), "TITLE", "interactive launch shows TITLE")
    scene.menu.button("title_start").pressed.emit()
    scene._physics_process(dt)
    t.eq(scene.flow.state_name(), "PLAYING", "게임 시작 -> PLAYING")
    # No viewport / mouse headlessly: the cursor stands on recovery anchor B.
    scene._cursor_world_override = scene.battle.grid.cell_center(TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y)
    scene.battle.run_for(1.0)
    # Player holds the button (a refused recovery click keeps retrying), then pauses with P.
    scene._mouse_down = true
    scene._mouse_down_run_id = scene.battle.run.run_id
    var old_id: int = scene.battle.run.run_id
    _press(scene, KEY_P)
    scene._physics_process(dt)
    t.eq(scene.flow.state_name(), "PAUSED", "P pauses")
    t.eq(scene._mouse_down, false, "entering the menu drops the held click")
    # R while paused -> restart confirmation; confirm -> exactly one new run.
    scene.menu.button("pause_restart").pressed.emit()
    scene._physics_process(dt)
    t.eq(scene.flow.state_name(), "CONFIRM", "다시 시작 opens the confirmation")
    scene.menu.button("confirm_ok").pressed.emit()
    scene._physics_process(dt)
    t.eq(scene.battle.run.run_id, old_id + 1, "run_id advanced by the confirmed restart")
    t.eq(scene.flow.state_name(), "PLAYING", "new run is PLAYING (pause cleared)")
    t.eq(scene._mouse_down, false, "held click cleared by the restart")
    t.eq(scene._mouse_down_run_id, -1, "held-click run id cleared")
    t.eq(scene.battle.steps, 1, "new run advanced exactly one tick in the frame that started it")
    var rejected: int = scene.battle.commands_rejected
    var accepted: int = scene.battle.commands_accepted
    scene._physics_process(dt)
    t.eq(scene.battle.commands_rejected, rejected, "no command retried in the new run on the next physics tick")
    t.eq(scene.battle.commands_accepted, accepted, "nothing placed in the new run")
    t.eq(scene.battle.steps, 2, "the new run keeps advancing (not paused)")
    # A hold that somehow outlives a restart (stale run id) is dropped, not retried.
    scene._mouse_down = true
    scene._mouse_down_run_id = scene.battle.run.run_id - 1
    rejected = scene.battle.commands_rejected
    scene._physics_process(dt)
    t.eq(scene._mouse_down, false, "stale-run hold dropped")
    t.eq(scene.battle.commands_rejected, rejected, "stale-run hold issued no command")
    # A hold from the CURRENT run keeps retrying (behaviour unchanged).
    scene._mouse_down = true
    scene._mouse_down_run_id = scene.battle.run.run_id
    rejected = scene.battle.commands_rejected
    scene._physics_process(dt)
    t.check(scene.battle.commands_rejected > rejected, "current-run hold still retries (refused: no recovery right yet)")
    # Sandbox reset path goes through the same confirmation and clears the same state.
    scene._apply_mode_preset(Config.new())
    scene.battle.reset()
    scene._mouse_down = true
    scene._mouse_down_run_id = scene.battle.run.run_id
    _press(scene, KEY_R)
    scene._physics_process(dt)
    t.eq(scene.flow.state_name(), "CONFIRM", "sandbox R: confirmation first")
    scene.menu.button("confirm_ok").pressed.emit()
    scene._physics_process(dt)
    t.eq(scene.flow.state_name(), "PLAYING", "sandbox R confirmed: playing")
    t.eq(scene._mouse_down, false, "sandbox R: held click cleared")
    _drop(scene)


## A key tap: press then release (R-01: a key still held when the menu closes
## keeps the field closed, so a tap is what a player's restart key is).
static func _press(scene: Node2D, keycode: int) -> void:
    for pressed: bool in [true, false]:
        var key: InputEventKey = InputEventKey.new()
        key.keycode = keycode
        key.pressed = pressed
        scene._handle_key_event(key)
