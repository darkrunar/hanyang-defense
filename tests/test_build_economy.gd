extends RefCounted
## WP-008 준비 배치·전투 중 건설·물자 (backlog/WP-008.md AC-01..06, D-054).
## Core rules on the real Battle (Config.for_wp008) and the real scene driven
## headlessly with the real HUD buttons and synthesized key / mouse events,
## exactly like tests/test_play_flow.gd. Nothing flips UI state directly.

const Main := preload("res://game/scenes/main.gd")
const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const PlayFlow := preload("res://game/core/play_flow.gd")
const ResultModel := preload("res://game/core/result_model.gd")
const Economy := preload("res://game/core/economy.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const PerfRecorder := preload("res://game/tools/perf_recorder.gd")

const SETTINGS_TMP: String = "user://wp008_test_settings.cfg"
const OUTER_GOAL: Vector2 = Vector2(950.0, 530.0)
const CORE_GOAL: Vector2 = Vector2(950.0, 210.0)
const DT: float = 0.0166666667
const K_J: int = Placement.Kind.JANGSEUNG
const K_H: int = Placement.Kind.HWACHA
const K_B: int = Placement.Kind.BONGSU
const K_S: int = Placement.Kind.SENSOR
const H1: int = 1
## Free plaza cells for purchases (30..65 x 16..30, away from the fixture).
const P1: Vector2i = Vector2i(40, 20)
const P2: Vector2i = Vector2i(52, 20)
const P3: Vector2i = Vector2i(36, 24)
const P4: Vector2i = Vector2i(56, 24)
const INNER_FREE: Vector2i = Vector2i(50, 8)
const WEST_LANE: Vector2i = Vector2i(44, 36)
const EAST_LANE: Vector2i = Vector2i(48, 36)


func run(t: RefCounted) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    _economy_unit(t)
    _config_and_fixture(t)
    _ac01_preparing_and_begin(t)
    _ac02_ledger(t)
    _ac02_boundaries(t)
    _ac03_purchases_and_refusals(t)
    _ac03_cap(t)
    _ac05_collapse_recovery_inner(t)
    _ac06_determinism(t)
    _scene_launch_and_preparing(t, tree)
    _scene_one_press_one_purchase(t, tree)
    _scene_ui_click_and_begin(t, tree)
    _scene_fence_and_menus(t, tree)
    _scene_restart_and_result(t, tree)
    _scene_recovery_selection(t, tree)
    _scene_classic_untouched(t, tree)
    _scene_art_modes_equal(t, tree)
    _scene_scenarios(t, tree)
    _cleanup()


# ------------------------------------------------------------------ helpers ---

static func _b() -> Battle:
    return Battle.new(Config.for_wp008())


static func _steps(b: Battle, n: int) -> void:
    for _i: int in range(n):
        b.step(DT)


static func _run_seconds(b: Battle, seconds: float) -> void:
    _steps(b, int(round(seconds / DT)))


static func _force_collapse_b(b: Battle) -> int:
    b.force_outer_hp(1.0, "test forced collapse")
    b.spawn_extra(OUTER_GOAL, 1, "test trigger enemy")
    var k: int = 0
    while b.run.collapse_count == 0 and k < 300:
        b.step(DT)
        k += 1
    return b.run.collapse_tick


static func _force_lost_b(b: Battle) -> void:
    if b.run.collapse_count == 0:
        _force_collapse_b(b)
    b.force_core_hp(1.0, "test forced LOST")
    b.spawn_extra(CORE_GOAL, 1, "test last arrival")
    var k: int = 0
    while not b.run.ended() and k < 300:
        b.step(DT)
        k += 1


## Everything a refused command must leave untouched, in one comparable value.
static func _guard(b: Battle) -> Dictionary:
    var e: Dictionary = b.economy.snapshot()
    e.erase("refusals")
    e.erase("refusal_total")
    e.erase("event_count")
    return {"hash": b.state_hash(), "supply": b.economy.supply, "spent": b.economy.spent, "structures": b.placement.structures.size(),
        "detached": b.placement.detached.size(), "path_version": b.path.path_version, "topology": b.network.topology_version,
        "outer_hp": b.run.outer_hp, "core_hp": b.run.core_hp, "economy": e, "accepted": b.commands_accepted}


static func _new_scene(tree: SceneTree, build: bool = true, art: String = "greybox") -> Node2D:
    var scene: Node2D = Main.new()
    scene._settings_path = SETTINGS_TMP
    scene._art_mode = art
    if build:
        scene._play_mode_arg = "build"
    tree.root.add_child(scene)
    if not scene.is_node_ready():
        scene._ready()
    scene.set_process(false)
    scene.set_physics_process(false)
    return scene


static func _drop(scene: Node2D) -> void:
    scene.get_parent().remove_child(scene)
    scene.free()


static func _frame(scene: Node2D, n: int = 1) -> void:
    for _i: int in range(n):
        scene._physics_process(DT)


static func _key(scene: Node2D, keycode: int, pressed: bool = true) -> void:
    var ev: InputEventKey = InputEventKey.new()
    ev.keycode = keycode
    ev.pressed = pressed
    scene._handle_key_event(ev)


static func _tap(scene: Node2D, keycode: int) -> void:
    _key(scene, keycode, true)
    _key(scene, keycode, false)


static func _lmb(scene: Node2D, pressed: bool) -> void:
    var ev: InputEventMouseButton = InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = pressed
    scene._handle_key_event(ev)


static func _cursor(scene: Node2D, anchor: Vector2i) -> void:
    scene._cursor_world_override = scene.battle.grid.cell_center(anchor.x, anchor.y)


static func _click(scene: Node2D, intent: String) -> bool:
    var b: Button = scene.menu.button(intent)
    if b == null or not scene.menu.button_visible(intent):
        return false
    b.pressed.emit()
    _frame(scene)
    return true


static func _hud(scene: Node2D, name: String) -> void:
    var b: Button = scene._build_buttons[name]
    b.pressed.emit()
    _frame(scene)


static func _start(scene: Node2D) -> void:
    _click(scene, "title_start")


static func _begin(scene: Node2D) -> void:
    _hud(scene, "begin_defense")


func _cleanup() -> void:
    if FileAccess.file_exists(SETTINGS_TMP):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TMP))


# -------------------------------------------------------------------- units ---

func _economy_unit(t: RefCounted) -> void:
    t.case("Economy unit: integer ledger, invariant, once-per-wave bonus, refusals counted")
    var e: Economy = Economy.new()
    e.enabled = true
    e.configure(240, 1, 80, {K_J: 40, K_H: 100, K_B: 60, K_S: 80}, 24)
    e.reset()
    t.eq(e.supply, 240, "start supply")
    t.check(e.balance_ok(), "invariant at start")
    t.eq(e.reward_kills(7, 10, 0.1), 7, "7 kills -> +7")
    t.eq(e.reward_kills(0, 11, 0.2), 0, "0 kills -> nothing")
    t.eq(e.kills_rewarded, 7, "kills counted")
    t.check(e.reward_wave(0, 12, 0.3), "wave 0 paid once")
    t.check(not e.reward_wave(0, 13, 0.4), "wave 0 not paid twice")
    t.check(e.reward_wave(1, 14, 0.5), "wave 1 paid")
    t.eq(e.supply, 240 + 7 + 160, "supply after income")
    t.eq(e.can_afford(K_H), true, "can afford a hwacha")
    t.eq(e.charge(K_H, 15, 0.6, P1, 5, "화차+1", "preparing"), 100, "charge returns the cost")
    t.eq(e.supply, 307, "supply after the charge")
    t.eq(e.spent, 100, "spent")
    t.check(e.balance_ok(), "invariant after income + spending")
    e.refuse(Placement.Reject.INSUFFICIENT_SUPPLY, K_H, P1, 16, 0.7)
    t.eq(e.refusal_total(), 1, "refusal counted")
    t.eq(e.supply, 307, "a refusal never touches the supply")
    e.inject(500, 17, 0.8, "unit")
    t.eq(e.injected, 500, "injection tracked")
    t.check(e.balance_ok(), "invariant with injection")
    t.eq(e.snapshot()["benchmark_injected"], true, "snapshot flags the injection")
    var off: Economy = Economy.new()
    off.configure(240, 1, 80, {}, 24)
    off.reset()
    t.eq(off.reward_kills(5, 0, 0.0), 0, "disabled ledger pays nothing")
    t.eq(off.reward_wave(0, 0, 0.0), false, "disabled ledger pays no wave bonus")
    e.reset()
    t.eq(e.supply, 240, "reset -> start supply")
    t.eq(e.purchases.size(), 0, "reset -> no purchases")
    t.eq(e.waves_rewarded.size(), 0, "reset -> no wave paid")


func _config_and_fixture(t: RefCounted) -> void:
    t.case("Config / fixture: for_wp008 = WP-003 contract + build fixture (4) + ledger; classic and fixture C untouched")
    var c: Config = Config.for_wp008()
    t.eq(c.get_str("play_mode"), "build", "play_mode build")
    t.eq(c.get_str("fixture"), "build", "fixture build")
    t.eq(c.get_str("run_mode"), "waves", "waves run")
    t.eq(c.get_num("outer_hp"), 360.0, "outer HP 360 kept")
    t.eq(c.get_int("start_supply"), 240, "start supply 240")
    t.eq(c.get_int("cost_jangseung"), 40, "장승 40")
    t.eq(c.get_int("cost_hwacha"), 100, "화차 100")
    t.eq(c.get_int("cost_bongsu"), 60, "봉수 60")
    t.eq(c.get_int("cost_sensor"), 80, "혼천의 80")
    t.eq(c.get_int("structure_cap"), 24, "cap 24")
    t.eq(c.get_int("wave_reward"), 80, "wave reward 80")
    t.eq(c.get_int("kill_reward"), 1, "kill reward 1")
    t.check(c.set_value("cost_hwacha", "120"), "--set cost_hwacha accepted")
    t.eq(c.get_int("cost_hwacha"), 120, "override applied")
    t.eq(Config.for_wp003().get_str("play_mode"), "classic", "WP-003 preset stays classic")
    t.eq(Config.for_wp003().get_str("fixture"), "c", "WP-003 preset keeps fixture C")
    t.eq(Config.new().get_str("play_mode"), "classic", "default config classic")
    var b: Battle = _b()
    t.eq(b.play_mode, "build", "battle play_mode")
    t.eq(b.economy.enabled, true, "ledger enabled")
    t.eq(b.preparing, true, "starts preparing")
    t.eq(b.placement.structures.size(), 4, "4 initial structures")
    t.eq(b.structure_total(), 4, "total 4 / 24")
    var s1: Placement.Structure = b.placement.get_structure(1)
    var s2: Placement.Structure = b.placement.get_structure(2)
    var s3: Placement.Structure = b.placement.get_structure(3)
    var s4: Placement.Structure = b.placement.get_structure(4)
    t.check(s1 != null and s1.kind == K_H and s1.anchor == Vector2i(46, 29) and s1.label == "화차·중영", "id 1 = 화차·중영 (46,29)")
    t.check(s2 != null and s2.kind == K_H and s2.anchor == Vector2i(46, 17) and s2.label == "화차·궁성", "id 2 = 화차·궁성 (46,17)")
    t.check(s3 != null and s3.kind == K_B and s3.anchor == Vector2i(44, 33), "id 3 = 봉수 B8 (44,33)")
    t.check(s4 != null and s4.kind == K_S and s4.anchor == Vector2i(44, 39), "id 4 = 혼천의 S3 (44,39)")
    t.eq(b.run.recovery_target_id, H1, "recovery target = 화차·중영")
    t.eq(b.economy.supply, 240, "supply 240")
    t.eq(b.density.zones.size(), 10, "10 zones")
    t.eq(b.waves.total_budget(), 1140, "1140 enemies")
    t.eq(b.run.outer_hp, 360.0, "outer HP 360")
    t.eq(s1.attached_to, 3, "중영 attached to B8 (within 180 px)")
    var c3: Battle = Battle.new(Config.for_wp003())
    t.eq(c3.placement.structures.size(), 18, "fixture C still 18")
    t.eq(c3.play_mode, "classic", "classic battle")
    t.eq(c3.preparing, false, "classic never prepares")
    t.eq(c3.economy.enabled, false, "classic ledger off")
    t.eq(c3.economy.supply, 0, "classic ledger empty")
    t.eq(c3.buy_structure(K_H, P1).reason, Placement.Reject.BUILD_DISABLED, "classic: purchase refused BUILD_DISABLED")
    t.eq(c3.placement.structures.size(), 18, "classic: nothing placed")


# -------------------------------------------------------------------- AC-01 ---

func _ac01_preparing_and_begin(t: RefCounted) -> void:
    t.case("AC-01 preparing: 120 ticks change nothing; purchases allowed; 방어 시작 exactly once; clock and waves from 0; restart prepares again")
    var b: Battle = _b()
    var before: String = b.full_state_json()
    _steps(b, 120)
    t.eq(b.steps, 0, "no tick advanced")
    t.eq(b.sim_time, 0.0, "sim_time 0")
    t.eq(b.sim.spawned_total, 0, "nothing spawned")
    t.eq(b.full_state_json(), before, "full state unchanged after 120 preparing ticks")
    var r: Placement.Result = b.buy_structure(K_H, P1)
    t.check(r.ok, "purchase during preparation ok")
    t.eq(b.economy.supply, 140, "240 - 100")
    t.eq(b.economy.purchases[0]["phase"], "preparing", "purchase recorded in the preparing phase")
    t.eq(b.begin_defense(), true, "begin_defense accepted once")
    t.eq(b.preparing, false, "no longer preparing")
    t.eq(b.defense_started_tick, 0, "defence started at tick 0")
    t.eq(b.begin_defense(), false, "second begin_defense refused")
    t.eq(b.begin_defense_calls_ignored, 1, "refusal counted")
    t.eq(b.run.events_of("defense_started").size(), 1, "one defense_started event")
    _steps(b, 60)
    t.eq(b.steps, 60, "60 ticks after the start")
    t.check(b.sim.spawned_total > 0, "waves spawn after the start (%d)" % b.sim.spawned_total)
    t.eq(b.waves.snapshot()["wave_started_tick"][0], 0, "W1 started at tick 0")
    t.eq(b.waves.snapshot()["wave_name"], "W1", "W1 in progress")
    b.restart()
    t.eq(b.preparing, true, "restart -> preparing again")
    t.eq(b.economy.supply, 240, "restart -> supply 240")
    t.eq(b.placement.structures.size(), 4, "restart -> 4 structures")
    t.eq(b.economy.purchases.size(), 0, "restart -> ledger empty")
    t.eq(b.run.run_id, 2, "new run id")
    _steps(b, 10)
    t.eq(b.steps, 0, "restarted run waits for 방어 시작")


# -------------------------------------------------------------------- AC-02 ---

func _ac02_ledger(t: RefCounted) -> void:
    t.case("AC-02 ledger: supply == 240 + kills + waves*80 - spent every second; arrivals pay nothing; each wave once; last wave paid in the WON tick")
    var b: Battle = _b()
    b.begin_defense()
    var ok_every_second: bool = true
    var kills_match: bool = true
    var last_sec: int = -1
    var waves_paid_at: Dictionary = {}
    var recovered: bool = false
    while not b.run.ended() and b.sim_time < 400.0:
        b.step(DT)
        if b.run.recovery_right > 0 and not recovered:
            recovered = b.place_recovery(TestMap.RECOVERY_B).ok   # the free recovery, retried while B is occupied (as the AC-09 tool does)
        var sec: int = int(floor(b.sim_time))
        if sec != last_sec:
            last_sec = sec
            if not b.economy.balance_ok():
                ok_every_second = false
            if b.economy.kills_rewarded != b.sim.killed_total:
                kills_match = false
            if b.economy.supply != 240 + b.sim.killed_total * 1 + b.economy.waves_rewarded.size() * 80:
                ok_every_second = false
        for e: Dictionary in b.run.events_of("wave_reward"):
            waves_paid_at[int(e["wave_index"])] = int(e["tick"])
    t.check(b.run.ended(), "run ended (%s at %.1f s)" % [b.run.run_name(), b.sim_time])
    t.eq(b.run.run_name(), "WON", "no purchases + free recovery at B -> WON (same commands as the AC-09 tool's no_build run; balance is GPT's call)")
    t.eq(recovered, true, "free recovery placed")
    t.eq(b.economy.spent, 0, "nothing spent")
    t.check(ok_every_second, "invariant held at every sampled second")
    t.check(kills_match, "kills rewarded == EnemySim killed_total at every sampled second")
    t.check(b.run.outer_arrivals > 0, "arrivals happened (%d) and paid nothing" % b.run.outer_arrivals)
    t.eq(b.economy.earned_kills, b.sim.killed_total, "earned_kills == killed_total (1 each)")
    t.eq(b.economy.waves_rewarded, [0, 1, 2], "three waves paid once each, in order")
    t.eq(b.economy.earned_waves, 240, "3 x 80")
    t.eq(b.economy.supply, 240 + b.sim.killed_total + 240, "final supply matches the formula")
    var ws: Dictionary = b.waves.snapshot()
    for w: int in range(3):
        t.eq(waves_paid_at.get(w, -1), int(ws["wave_cleared_tick"][w]), "W%d paid in the tick it was resolved" % (w + 1))
        t.check(int(ws["wave_cleared_tick"][w]) >= int(ws["wave_spent_tick"][w]), "W%d resolved after its budget was spent" % (w + 1))
    if b.run.run_name() == "WON":
        # RunState.end_tick is recorded after the step counter advanced, so the
        # settlement of the ending step carries end_tick - 1 (same step() call).
        t.eq(waves_paid_at.get(2, -1), b.run.end_tick - 1, "last wave paid in the step that ended the run (settlement before the verdict)")
    # the director's own transition happens one tick after the settlement
    t.eq(int(ws["wave_spent_tick"][0]) >= 0 and int(ws["wave_cleared_tick"][0]) >= 0, true, "W1 spent / cleared ticks recorded")
    var supply_end: int = b.economy.supply
    var events_end: int = b.economy.events.size()
    _steps(b, 120)
    t.eq(b.economy.supply, supply_end, "nothing paid after the run ended")
    t.eq(b.economy.events.size(), events_end, "no ledger event after the end")
    b.restart()
    t.eq(b.economy.supply, 240, "restart: 240 again, nothing carried over")
    t.eq(b.economy.earned_kills, 0, "restart: no kills carried")
    t.eq(b.economy.waves_rewarded.size(), 0, "restart: no wave paid")


func _ac02_boundaries(t: RefCounted) -> void:
    t.case("AC-02 boundaries: simultaneous kills each once, no reward after LOST, a wave is not paid on spawn end alone, duplicate clear ignored")
    var b: Battle = _b()
    b.begin_defense()
    # a controlled group inside 중영's blast: one volley, n kills, +n exactly
    b.waves.enabled = false
    var slots: PackedInt32Array = b.spawn_extra(Vector2(950.0, 560.0), 12, "AC-02 group")
    for s: int in slots:
        b.sim.hp[s] = 1.0
    var k0: int = b.sim.killed_total
    var s0: int = b.economy.supply
    _steps(b, 30)
    var dk: int = b.sim.killed_total - k0
    t.check(dk >= 2, "the volley killed several enemies at once (%d)" % dk)
    t.eq(b.economy.supply - s0, dk, "+1 per individual, no double count")
    t.eq(b.economy.kills_rewarded, b.sim.killed_total, "kills_rewarded == killed_total")
    # a wave whose budget is spent but whose enemies are alive pays nothing
    var w: Battle = _b()
    w.begin_defense()
    var paid_before_clear: bool = false
    while w.sim_time < 120.0 and not w.run.ended():
        w.step(DT)
        var ws: Dictionary = w.waves.snapshot()
        if ws["state"] == "WAITING_CLEAR" and w.sim.alive_count > 0 and w.economy.waves_rewarded.has(int(ws["wave_index"])):
            paid_before_clear = true
        if w.economy.waves_rewarded.size() >= 1:
            break
    t.check(not paid_before_clear, "no wave paid while its enemies were still alive")
    t.eq(w.economy.waves_rewarded.size(), 1, "W1 paid once when resolved (t=%.1f)" % w.sim_time)
    t.eq(w.waves.mark_cleared(w.steps, 0), -1, "duplicate clear detection of the same wave returns -1")
    t.eq(w.economy.reward_wave(0, w.steps, w.sim_time), false, "duplicate wave payment refused")
    # LOST: the ledger freezes
    var l: Battle = _b()
    l.begin_defense()
    _run_seconds(l, 5.0)
    _force_lost_b(l)
    t.eq(l.run.run_name(), "LOST", "LOST reached")
    var supply_lost: int = l.economy.supply
    var ev_lost: int = l.economy.events.size()
    _steps(l, 120)
    t.eq(l.economy.supply, supply_lost, "no reward after the loss")
    t.eq(l.economy.events.size(), ev_lost, "no ledger event after the loss")
    t.eq(l.buy_structure(K_J, INNER_FREE).reason, Placement.Reject.RUN_ENDED, "no purchase after the loss")
    for e: Dictionary in l.economy.events:
        if int(e["tick"]) > l.run.end_tick:
            t.check(false, "ledger event after end_tick")
    t.check(true, "every ledger event is at or before end_tick")


# -------------------------------------------------------------------- AC-03 ---

func _ac03_purchases_and_refusals(t: RefCounted) -> void:
    t.case("AC-03 purchases: 4 kinds charged exactly; every refusal leaves supply / HP / occupancy / path / network untouched")
    var b: Battle = _b()
    var pv0: int = b.path.path_version
    var tv0: int = b.network.topology_version
    var rj: Placement.Result = b.buy_structure(K_J, WEST_LANE)
    t.check(rj.ok and b.economy.supply == 200, "장승 -40 -> 200")
    t.eq(b.path.path_version, pv0 + 1, "장승 rebuilds the path once")
    for r: int in range(b.path.route_ids.size()):
        t.check(b.path.route_reachable(r), "route %d still reachable" % r)
    var rb: Placement.Result = b.buy_structure(K_B, Vector2i(42, 29))
    t.check(rb.ok and b.economy.supply == 140, "봉수 -60 -> 140")
    t.eq(b.path.path_version, pv0 + 1, "봉수 never rebuilds the path")
    t.check(b.network.topology_version > tv0, "봉수 purchase rebuilt the network")
    var rs: Placement.Result = b.buy_structure(K_S, Vector2i(47, 15))
    t.check(rs.ok and b.economy.supply == 60, "혼천의 -80 -> 60")
    t.check(rs.structure.detect_range > 0.0, "sensor configured")
    var rh: Placement.Result = b.buy_structure(K_H, P1)
    t.eq(rh.reason, Placement.Reject.INSUFFICIENT_SUPPLY, "화차 100 > 60 refused")
    t.eq(b.economy.refusals.get("INSUFFICIENT_SUPPLY", 0), 1, "refusal counted by reason")
    b.economy.inject(100, b.steps, b.sim_time, "test top-up")
    var rh2: Placement.Result = b.buy_structure(K_H, Vector2i(42, 25))
    t.check(rh2.ok and b.economy.supply == 60, "화차 -100 after top-up")
    t.check(rh2.structure.fire_range > 0.0 and rh2.structure.attached_to >= 0, "bought hwacha configured and attached (%d)" % rh2.structure.attached_to)
    t.eq(rh2.structure.label, "화차+4", "purchase label numbered")
    t.eq(b.structure_total(), 8, "4 + 4 purchases")
    t.eq(b.economy.spent, 280, "spent 40+60+80+100")
    t.check(b.economy.balance_ok(), "invariant")
    # refusals, one per rule, nothing changes
    b.economy.inject(1000, b.steps, b.sim_time, "test funds for the refusal probes")
    var g: Dictionary = _guard(b)
    var probes: Array = [
        ["overlap", K_H, Vector2i(46, 29), Placement.Reject.STRUCTURE_OVERLAP],
        ["terrain", K_H, Vector2i(45, 15), Placement.Reject.TERRAIN_BLOCKED],
        ["out of bounds", K_J, Vector2i(95, 53), Placement.Reject.OUT_OF_BOUNDS],
        ["district split", K_H, Vector2i(41, 8), Placement.Reject.TERRAIN_BLOCKED],
        ["unknown kind", 9, P2, Placement.Reject.UNKNOWN_STRUCTURE],
    ]
    for p: Array in probes:
        var r: Placement.Result = b.buy_structure(p[1], p[2])
        t.check(not r.ok, "%s refused (%s)" % [p[0], Placement.reject_name(r.reason)])
        t.eq(_guard(b), g, "%s: state untouched" % p[0])
    # district split: a footprint straddling the inner rect edge (x41..42)
    var split: Placement.Result = b.buy_structure(K_H, Vector2i(41, 16))
    t.check(not split.ok, "straddling footprint refused (%s)" % Placement.reject_name(split.reason))
    t.eq(_guard(b), g, "straddle: state untouched")
    # all paths blocked: the second south lane
    var block: Placement.Result = b.buy_structure(K_J, EAST_LANE)
    t.eq(block.reason, Placement.Reject.WOULD_BLOCK_ALL_PATHS, "closing both south lanes refused")
    t.eq(_guard(b), g, "block: state untouched (path version %d)" % b.path.path_version)
    # enemy on the cell
    b.begin_defense()
    b.waves.enabled = false
    b.spawn_extra(b.grid.cell_center(P2.x, P2.y), 1, "occupant")
    var g2: Dictionary = _guard(b)
    var occ: Placement.Result = b.buy_structure(K_H, P2)
    t.eq(occ.reason, Placement.Reject.ENEMY_OCCUPIES_CELL, "occupied cell refused")
    t.eq(_guard(b), g2, "occupied: state untouched")
    t.eq(b.economy.refusal_total(), 1 + probes.size() + 3, "every refusal counted (%s)" % str(b.economy.refusals))
    # network effect of a purchase: a hwacha bought next to a bongsu attaches, one bought far away does not
    var far: Placement.Result = b.buy_structure(K_H, Vector2i(30, 25))
    t.check(far.ok, "far hwacha bought")
    t.eq(far.structure.attached_to, -1, "far hwacha not attached (no bongsu within 180)")
    var near_b: Placement.Result = b.buy_structure(K_B, Vector2i(34, 21))
    t.check(near_b.ok, "bongsu bought near it")
    t.eq(b.placement.get_structure(far.structure.id).attached_to, near_b.structure.id, "hwacha attached through the existing network refresh")


func _ac03_cap(t: RefCounted) -> void:
    t.case("AC-03 cap 24: total = initial + bought + inactive + waiting; the 25th is refused; duplicate press on the last slot refused")
    var b: Battle = _b()
    b.economy.inject(5000, 0, 0.0, "test funds")
    var spots: Array = [P1, P2, P3, P4, Vector2i(34, 18), Vector2i(38, 18), Vector2i(58, 18), Vector2i(62, 18),
        Vector2i(34, 27), Vector2i(38, 27), Vector2i(58, 27), Vector2i(62, 27), Vector2i(30, 25), Vector2i(64, 25),
        Vector2i(34, 21), Vector2i(42, 21), Vector2i(50, 21), Vector2i(58, 21), Vector2i(47, 15), Vector2i(50, 12), Vector2i(44, 9)]
    var bought: int = 0
    for i: int in range(spots.size()):
        if b.structure_total() >= 24:
            break
        var r: Placement.Result = b.buy_structure(K_H if i % 2 == 0 else K_S, spots[i])
        if r.ok:
            bought += 1
    t.eq(b.structure_total(), 24, "reached the cap (%d bought)" % bought)
    var g: Dictionary = _guard(b)
    var over: Placement.Result = b.buy_structure(K_J, Vector2i(22, 24))
    t.eq(over.reason, Placement.Reject.CAP_REACHED, "25th refused CAP_REACHED")
    t.eq(_guard(b), g, "cap refusal changes nothing")
    t.eq(b.preview_build(K_J, Vector2i(22, 24)), Placement.Reject.CAP_REACHED, "preview agrees")
    # duplicate input on the last slot: a fresh battle at 23, two commands on the same cell
    var d: Battle = _b()
    d.economy.inject(5000, 0, 0.0, "test funds")
    for i: int in range(19):
        d.buy_structure(K_H if i % 2 == 0 else K_S, spots[i])
    t.eq(d.structure_total(), 23, "23 before the last slot")
    var first: Placement.Result = d.buy_structure(K_J, Vector2i(22, 24))
    var second: Placement.Result = d.buy_structure(K_J, Vector2i(22, 24))
    t.check(first.ok, "first press fills the last slot")
    t.check(not second.ok, "second press refused (%s)" % Placement.reject_name(second.reason))
    t.eq(d.structure_total(), 24, "never above the cap")
    # the waiting (detached) H1 counts: collapse keeps the total
    d.begin_defense()
    _force_collapse_b(d)
    t.eq(d.placement.detached.size(), 1, "H1 waiting")
    t.eq(d.structure_total(), 24, "total unchanged by the collapse (waiting counts)")
    t.eq(d.buy_structure(K_J, INNER_FREE).reason, Placement.Reject.CAP_REACHED, "still capped while H1 waits")
    var spent_before: int = d.economy.spent
    var supply_before: int = d.economy.supply
    var rec: Placement.Result = d.place_recovery(TestMap.RECOVERY_A)
    t.check(rec.ok, "free recovery placed (%s)" % Placement.reject_name(rec.reason))
    t.eq(d.structure_total(), 24, "recovery is not a purchase: total unchanged")
    t.eq(d.economy.spent, spent_before, "recovery cost 0 (spent unchanged)")
    t.eq(d.economy.supply, supply_before, "recovery cost 0 (supply unchanged)")
    t.eq(d.buy_structure(K_J, INNER_FREE).reason, Placement.Reject.CAP_REACHED, "still capped after the recovery")


# -------------------------------------------------------------------- AC-05 ---

func _ac05_collapse_recovery_inner(t: RefCounted) -> void:
    t.case("AC-05 collapse in build mode: outer initial + bought deactivated, only 중영 recovered free (same id), inner purchases continue, outer refused")
    var b: Battle = _b()
    t.check(b.buy_structure(K_H, P1).ok, "outer hwacha bought in preparation")
    t.check(b.buy_structure(K_J, WEST_LANE).ok, "outer jangseung bought")
    var bought_id: int = b.placement.structures.keys().max()
    b.begin_defense()
    _run_seconds(b, 3.0)
    var supply_before: int = b.economy.supply
    var total_before: int = b.structure_total()
    var ct: int = _force_collapse_b(b)
    t.check(ct >= 0, "collapse through real arrival damage (tick %d)" % ct)
    t.eq(b.run.recovery_right, 1, "one free recovery right")
    t.eq(b.placement.detached.keys(), [H1], "only 화차·중영 detached")
    var bought: Placement.Structure = b.placement.get_structure(5)
    t.check(bought != null and not bought.active and not bought.detached, "bought outer hwacha deactivated, not recovered")
    t.eq(b.placement.get_structure(2).active, true, "화차·궁성 (inner) still active")
    t.eq(b.economy.supply >= supply_before, true, "collapse never charges (supply %d -> %d)" % [supply_before, b.economy.supply])
    t.eq(b.structure_total(), total_before, "total unchanged by the collapse")
    var s0: int = b.economy.supply
    var rec: Placement.Result = b.place_recovery(TestMap.RECOVERY_B)
    t.check(rec.ok, "free recovery at B (%s)" % Placement.reject_name(rec.reason))
    t.eq(rec.structure.id, H1, "same id")
    t.eq(b.economy.supply, s0, "recovery cost 0")
    t.eq(b.economy.purchases.size(), 2, "recovery is not a purchase")
    b.economy.inject(200, b.steps, b.sim_time, "test funds")
    var outer: Placement.Result = b.buy_structure(K_H, P3)
    t.eq(outer.reason, Placement.Reject.DISTRICT_LOST, "outer purchase refused after the collapse")
    t.eq(b.preview_build(K_H, P3), Placement.Reject.DISTRICT_LOST, "preview agrees")
    t.eq(TestMap.district_of_cell(P3.x, P3.y), TestMap.DISTRICT_OUTER, "probe cell is outer")
    var inner: Placement.Result = b.buy_structure(K_H, INNER_FREE)
    t.check(inner.ok, "inner purchase ok (%s)" % Placement.reject_name(inner.reason))
    t.eq(inner.structure.district, TestMap.DISTRICT_INNER, "in the inner district")
    t.eq(inner.structure.active, true, "active")
    var shots0: int = inner.structure.shots_fired
    b.spawn_extra(Vector2(950.0, 300.0), 8, "targets for the inner gun")
    _run_seconds(b, 3.0)
    t.check(b.placement.get_structure(inner.structure.id).shots_fired > shots0, "inner purchase fires (%d volleys)" % b.placement.get_structure(inner.structure.id).shots_fired)
    t.eq(bought_id, 6, "ids stable (bought jangseung = 6)")


# -------------------------------------------------------------------- AC-06 ---

func _ac06_determinism(t: RefCounted) -> void:
    t.case("AC-06 determinism: same seed + same commands -> identical full state including the ledger")
    var states: Array = []
    for _i: int in range(2):
        var b: Battle = _b()
        b.buy_structure(K_H, P1)
        b.buy_structure(K_J, WEST_LANE)
        b.begin_defense()
        _run_seconds(b, 20.0)
        b.buy_structure(K_B, Vector2i(42, 29))
        _run_seconds(b, 10.0)
        states.append(b.full_state_json())
    t.eq(states[0], states[1], "two runs identical")
    t.check(states[0].find('"economy"') >= 0 and states[0].find('"supply"') >= 0, "state carries the ledger")


# --------------------------------------------------------------------- scene ---

func _scene_launch_and_preparing(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene AC-01: --play-mode=build pins play_mode + build fixture, TITLE -> PREPARING, HUD shown, nothing ticks before 방어 시작")
    var scene: Node2D = _new_scene(tree)
    t.eq(scene.config.get_str("play_mode"), "build", "config play_mode build")
    t.eq(scene.config.get_str("fixture"), "build", "config fixture build")
    t.eq(scene._explicit_sets.has("play_mode") and scene._explicit_sets.has("fixture"), true, "pinned like --set (scripted presets cannot drop them)")
    t.eq(scene.flow.build_mode, true, "flow in build mode")
    t.eq(scene.flow.state_name(), "TITLE", "starts on TITLE")
    t.eq(scene._build_bar.visible, false, "no construction bar on TITLE")
    t.eq(scene.battle.preparing, true, "battle prepared behind the title")
    _start(scene)
    t.eq(scene.flow.state_name(), "PREPARING", "게임 시작 -> PREPARING")
    t.eq(scene.flow.menu_open(), false, "no menu in PREPARING")
    t.eq(scene.menu.visible, false, "menu layer hidden")
    t.eq(scene._hud_layer.visible, true, "HUD shown")
    t.eq(scene._build_bar.visible, true, "construction bar shown")
    t.eq(scene.battle.economy.supply, 240, "supply 240")
    t.eq(scene.battle.structure_total(), 4, "4 structures")
    _frame(scene, 120)
    t.eq(scene.battle.steps, 0, "120 frames in PREPARING: no tick")
    t.eq(scene.battle.sim_time, 0.0, "sim_time 0")
    t.eq(scene.battle.sim.spawned_total, 0, "nothing spawned")
    _drop(scene)


func _scene_one_press_one_purchase(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene AC-04: one paid construction per new press; held button never buys again; refusal never auto-retries")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    t.eq(scene.flow.state_name(), "PREPARING", "PREPARING after 게임 시작")
    _tap(scene, KEY_2)
    t.eq(scene._sel_kind, K_H, "2 selects 화차")
    _cursor(scene, P1)
    var a0: int = scene.battle.commands_accepted
    _lmb(scene, true)
    t.eq(scene.battle.commands_accepted, a0 + 1, "press -> one purchase")
    t.eq(scene.battle.economy.supply, 140, "240 - 100")
    t.eq(scene._mouse_down, false, "paid build never arms the hold retry")
    _cursor(scene, P2)
    _frame(scene, 30)
    t.eq(scene.battle.commands_accepted, a0 + 1, "moving over other cells while held buys nothing")
    _lmb(scene, false)
    _cursor(scene, P1)
    var rj0: int = scene.battle.commands_rejected
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.commands_rejected, rj0 + 1, "press on the occupied cell refused once")
    _frame(scene, 30)
    t.eq(scene.battle.commands_rejected, rj0 + 1, "no automatic re-purchase after a refusal")
    _cursor(scene, P2)
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.economy.supply, 40, "second press on a free cell -> 40")
    _cursor(scene, P3)
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.economy.refusals.get("INSUFFICIENT_SUPPLY", 0), 1, "insufficient supply refused once")
    t.eq(scene.battle.economy.supply, 40, "insufficient supply: nothing charged")
    _frame(scene, 30)
    t.eq(scene.battle.economy.refusals.get("INSUFFICIENT_SUPPLY", 0), 1, "no automatic retry of the refused purchase")
    t.check(scene.build_clicks.size() >= 4, "scene click ledger kept (%d entries)" % scene.build_clicks.size())
    var last: Dictionary = scene.build_clicks.back()
    t.eq(last["ok"], false, "last click refused")
    t.eq(last["reason"], "INSUFFICIENT_SUPPLY", "reason recorded")
    _drop(scene)


func _scene_ui_click_and_begin(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: HUD buttons select without buying; 방어 시작 button / Space start once; second press refused; battle ticks only after it")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    t.eq(scene._build_bar.visible, true, "construction bar shown in build mode")
    t.eq(scene._begin_button.visible, true, "방어 시작 shown while preparing")
    t.eq(scene._hud_pause_button.visible, true, "pause button shown while preparing")
    var a0: int = scene.battle.commands_accepted
    _hud(scene, "build_hwacha")
    t.eq(scene._sel_kind, K_H, "button selects 화차")
    t.eq(scene.battle.commands_accepted, a0, "a UI click never buys")
    t.eq(scene.battle.economy.supply, 240, "supply untouched by the UI click")
    _frame(scene, 120)
    t.eq(scene.battle.steps, 0, "preparing: 120 frames, no tick")
    t.eq(scene.battle.sim.spawned_total, 0, "preparing: nothing spawned")
    _begin(scene)
    t.eq(scene.flow.state_name(), "PLAYING", "방어 시작 -> PLAYING")
    t.eq(scene.battle.preparing, false, "battle left the preparation")
    t.eq(scene._begin_button.visible, false, "방어 시작 hidden while playing")
    var ticks: int = scene.battle.steps
    _begin(scene)
    t.eq(scene.flow.refused.back()["request"], "begin_defense", "second 방어 시작 refused by the flow")
    t.eq(scene.battle.begin_defense_calls_ignored, 0, "the battle never saw a second start")
    _tap(scene, KEY_SPACE)
    _frame(scene)
    t.eq(scene.battle.run.events_of("defense_started").size(), 1, "exactly one defense_started")
    t.check(scene.battle.steps > ticks, "battle ticks after the start")
    _drop(scene)


func _scene_fence_and_menus(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: Esc pauses PREPARING and resumes to it; release fence blocks the purchase press; menus consume field input; settings return to the preparation")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    _tap(scene, KEY_1)
    _cursor(scene, WEST_LANE)
    var before: String = scene.battle.full_state_json()
    _key(scene, KEY_ESCAPE, true)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PAUSED", "Esc pauses the preparation")
    t.eq(scene.menu.visible, true, "menu shown")
    _lmb(scene, true)
    _lmb(scene, false)
    _frame(scene, 5)
    t.eq(scene.battle.economy.supply, 240, "click behind the menu buys nothing")
    _key(scene, KEY_ESCAPE, false)
    _key(scene, KEY_ESCAPE, true)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PREPARING", "Esc again resumes to PREPARING")
    t.eq(scene.battle.full_state_json(), before, "battle unchanged across the pause")
    var a0: int = scene.battle.commands_accepted
    _lmb(scene, true)
    t.eq(scene.battle.commands_accepted, a0, "press while Esc is still held: refused by the fence")
    t.eq(scene.fenced_inputs.back()["input"], "mouse1", "fence refusal logged")
    _lmb(scene, false)
    _key(scene, KEY_1, true)
    t.eq(scene.fenced_inputs.back()["input"], "1", "selection key fenced too")
    _key(scene, KEY_1, false)
    _key(scene, KEY_ESCAPE, false)
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.commands_accepted, a0 + 1, "new press after the release buys")
    t.eq(scene.battle.economy.supply, 200, "장승 -40")
    # settings from PREPARING pause first and come back to it
    _click(scene, "pause_settings")
    t.eq(scene.flow.state_name(), "PREPARING", "pause_settings is not visible while preparing (no-op)")
    _tap(scene, KEY_P)
    _frame(scene)
    _click(scene, "pause_settings")
    t.eq(scene.flow.state_name(), "SETTINGS", "settings opened from the pause")
    _click(scene, "settings_back")
    t.eq(scene.flow.state_name(), "PAUSED", "back to PAUSED")
    _click(scene, "pause_continue")
    t.eq(scene.flow.state_name(), "PREPARING", "continue -> PREPARING (the state it interrupted)")
    t.eq(scene.battle.steps, 0, "still no tick")
    _drop(scene)


func _scene_restart_and_result(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: R -> confirm; cancel keeps the preparation; confirm -> new PREPARING run with ledger 240; RESULT carries the economy rows")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    _tap(scene, KEY_2)
    _cursor(scene, P1)
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.economy.supply, 140, "bought one")
    _tap(scene, KEY_R)
    _frame(scene)
    t.eq(scene.flow.state_name(), "CONFIRM", "R from PREPARING opens the confirmation")
    _click(scene, "confirm_cancel")
    t.eq(scene.flow.state_name(), "PREPARING", "cancel returns to PREPARING")
    t.eq(scene.battle.economy.supply, 140, "run untouched by the cancel")
    var old_id: int = scene.battle.run.run_id
    _tap(scene, KEY_R)
    _frame(scene)
    _click(scene, "confirm_ok")
    t.eq(scene.flow.state_name(), "PREPARING", "confirmed restart -> PREPARING")
    t.eq(scene.battle.run.run_id, old_id + 1, "new run")
    t.eq(scene.battle.economy.supply, 240, "ledger reset")
    t.eq(scene.battle.placement.structures.size(), 4, "initial 4")
    t.eq(scene._sel_kind, Main.SEL_NONE, "selection cleared")
    t.eq(scene._mouse_down, false, "no held click")
    # play to a LOST with one purchase and the free recovery; the result model has the ledger
    _tap(scene, KEY_1)
    _cursor(scene, WEST_LANE)
    _lmb(scene, true)
    _lmb(scene, false)
    _begin(scene)
    _frame(scene, 60)
    scene.battle.force_outer_hp(1.0, "test forced collapse")
    scene.battle.spawn_extra(OUTER_GOAL, 1, "test trigger enemy")
    var k: int = 0
    while scene.battle.run.collapse_count == 0 and k < 300:
        _frame(scene)
        k += 1
    t.eq(scene._sel_kind, Main.SEL_RECOVERY, "collapse switches the selection to the recovery placement")
    _cursor(scene, TestMap.RECOVERY_B)
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.run.recovery_placed, true, "free recovery placed by the click")
    scene.battle.force_core_hp(1.0, "test forced LOST")
    scene.battle.spawn_extra(CORE_GOAL, 1, "test last arrival")
    k = 0
    while scene.flow.state != PlayFlow.State.RESULT and k < 300:
        _frame(scene)
        k += 1
    t.eq(scene.flow.state_name(), "RESULT", "RESULT shown")
    var m: Dictionary = scene.flow.result
    t.eq(m["play_mode"], "build", "result model knows the mode")
    var e: Dictionary = m["economy"]
    t.eq(int(e["spent"]), 40, "result ledger: spent 40")
    t.eq(int(e["purchase_count"]), 1, "result ledger: 1 purchase")
    t.check(bool(e["balance_ok"]), "result ledger balanced")
    t.eq(int(e["supply"]), 240 + int(e["earned_kills"]) + int(e["earned_waves"]) - 40, "result formula")
    var rows: Array = ResultModel.economy_lines(m)
    t.eq(rows.size(), 2, "two economy rows on the result panel")
    t.check(str(rows[0][1]).find("잔액 %d" % int(e["supply"])) >= 0, "물자 row shows the balance")
    t.check(str(rows[1][1]).find("장승 1") >= 0, "건설 row lists the purchase")
    t.eq(ResultModel.economy_lines({"play_mode": "classic"}).size(), 0, "classic result has no economy rows")
    _tap(scene, KEY_R)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PREPARING", "R on RESULT -> new PREPARING run")
    t.eq(scene.battle.economy.supply, 240, "ledger 240 again")
    _drop(scene)


func _scene_recovery_selection(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: recovery placement keeps its hold retry; switching 5 <-> 1..4; classic run unaffected by the selection keys")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    _begin(scene)
    _frame(scene, 30)
    scene.battle.force_outer_hp(1.0, "test forced collapse")
    scene.battle.spawn_extra(OUTER_GOAL, 1, "test trigger enemy")
    var k: int = 0
    while scene.battle.run.collapse_count == 0 and k < 300:
        _frame(scene)
        k += 1
    t.eq(scene._sel_kind, Main.SEL_RECOVERY, "recovery selected after the collapse")
    _cursor(scene, P1)   # outer cell: WRONG_DISTRICT, retried while held
    var rj0: int = scene.battle.commands_rejected
    _lmb(scene, true)
    t.eq(scene._mouse_down, true, "recovery press arms the hold retry")
    _frame(scene, 5)
    t.check(scene.battle.commands_rejected >= rj0 + 3, "held recovery click retries every tick (%d refusals)" % (scene.battle.commands_rejected - rj0))
    _lmb(scene, false)
    _tap(scene, KEY_2)
    t.eq(scene._sel_kind, K_H, "2 switches back to buying")
    t.eq(scene._mouse_down, false, "selection change drops the hold")
    _tap(scene, KEY_5)
    t.eq(scene._sel_kind, Main.SEL_RECOVERY, "5 selects the recovery again")
    _cursor(scene, TestMap.RECOVERY_B)
    _lmb(scene, true)
    _lmb(scene, false)
    t.eq(scene.battle.run.recovery_placed, true, "recovery placed")
    t.eq(scene.battle.economy.spent, 0, "free")
    _drop(scene)


func _scene_classic_untouched(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: the classic launch is unchanged (no bar, no PREPARING, 1..4 refused, ledger off)")
    var scene: Node2D = _new_scene(tree, false)
    t.eq(scene.battle.play_mode, "classic", "classic play mode")
    t.eq(scene.config.get_str("fixture"), "c", "fixture C")
    _start(scene)
    t.eq(scene.flow.state_name(), "PLAYING", "PLAYING directly")
    t.eq(scene._build_bar.visible, false, "no construction bar")
    t.eq(scene.battle.economy.enabled, false, "ledger off")
    _tap(scene, KEY_2)
    t.eq(scene._sel_kind, Main.SEL_NONE, "selection keys do nothing")
    _frame(scene, 5)
    t.check(scene.battle.steps >= 5, "battle ticks at once")
    _drop(scene)


func _scene_art_modes_equal(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene AC-06: greybox and sample renderings of the same build-mode script hold identical battle state (ledger included)")
    var states: Array = []
    for art: String in ["greybox", "sample"]:
        var scene: Node2D = _new_scene(tree, true, art)
        _start(scene)
        _tap(scene, KEY_2)
        _cursor(scene, P1)
        _lmb(scene, true)
        _lmb(scene, false)
        _begin(scene)
        _frame(scene, 240)
        _tap(scene, KEY_1)
        _cursor(scene, WEST_LANE)
        _lmb(scene, true)
        _lmb(scene, false)
        _frame(scene, 120)
        states.append(scene.battle.full_state_json())
        _drop(scene)
    t.eq(states[0], states[1], "greybox == sample")


func _scene_scenarios(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene entry paths: build_* perf scenarios (24 / 22 structures, injected supply flagged, defence started) and the wp008 capture (TITLE, build mode)")
    var expect: Dictionary = {"build_full_move": [24, false], "build_full_combat": [24, true], "build_grow_move": [22, false], "build_grow_combat": [22, true]}
    for sc: String in expect:
        var scene: Node2D = _new_scene(tree, false)
        scene._perf = PerfRecorder.new()
        scene._perf_scenario = sc
        scene._apply_run_mode()
        t.eq(scene.battle.play_mode, "build", "%s: build mode" % sc)
        t.eq(scene.battle.structure_total(), expect[sc][0], "%s: structures" % sc)
        t.eq(scene.battle.combat_enabled, expect[sc][1], "%s: combat switch" % sc)
        t.eq(scene.battle.preparing, false, "%s: defence started for the benchmark" % sc)
        t.eq(scene.battle.economy.injected, 3000, "%s: benchmark supply injected" % sc)
        t.eq(scene.battle.economy.snapshot()["benchmark_injected"], true, "%s: injection flagged" % sc)
        t.eq(scene.battle.waves.enabled, false, "%s: waves off" % sc)
        t.eq(scene.battle.run.outer_hp, 1000000.0, "%s: outer HP 1e6" % sc)
        t.eq(scene.battle.density.zones.size(), 10, "%s: 10 zones" % sc)
        t.check(scene.battle.economy.balance_ok(), "%s: ledger balanced after the setup purchases" % sc)
        scene._perf = null
        _drop(scene)
    var cap: Node2D = _new_scene(tree, false)
    cap._capture_name = "wp008_build"
    cap._capture_dir = "user://"
    cap._settings_path = ""
    cap._apply_run_mode()
    t.eq(cap.flow.state_name(), "TITLE", "wp008_build: starts on TITLE (menus driven by the script)")
    t.eq(cap.battle.play_mode, "build", "wp008_build: build mode")
    t.eq(cap.flow.build_mode, true, "wp008_build: flow in build mode")
    t.eq(cap.battle.placement.structures.size(), 4, "wp008_build: build fixture")
    t.check(cap.settings != null and cap.settings.path == "user://wp008_capture_settings.cfg", "wp008_build: throwaway settings path")
    cap._capture_name = ""
    _drop(cap)
    # the classic scripted scenarios never inherit the build mode
    var col: Node2D = _new_scene(tree, false)
    col._perf = PerfRecorder.new()
    col._perf_scenario = "collapse_combat"
    col._apply_run_mode()
    t.eq(col.battle.play_mode, "classic", "collapse_combat stays classic")
    t.eq(col.battle.placement.structures.size(), 18, "collapse_combat keeps fixture C")
    col._perf = null
    _drop(col)
