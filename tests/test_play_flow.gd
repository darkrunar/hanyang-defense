extends RefCounted
## WP-004 play flow (backlog/WP-004.md AC-01..07, D-039..D-042). Drives the
## REAL scene headlessly: the real Button nodes (`pressed` signal), the real
## key handler with synthesized InputEventKey / InputEventMouseButton, and the
## real physics frame. Never flips UI state variables directly.

const Main := preload("res://game/scenes/main.gd")
const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const PlayFlow := preload("res://game/core/play_flow.gd")
const ResultModel := preload("res://game/core/result_model.gd")
const UserSettings := preload("res://game/core/user_settings.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const PerfRecorder := preload("res://game/tools/perf_recorder.gd")

const SETTINGS_TMP: String = "user://wp004_test_settings.cfg"
const OUTER_GOAL: Vector2 = Vector2(950.0, 530.0)
const CORE_GOAL: Vector2 = Vector2(950.0, 210.0)
const DT: float = 0.0166666667


func run(t: RefCounted) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    _flow_unit(t)
    _result_model_unit(t)
    _settings_unit(t)
    _launch_title(t, tree)
    _ac01_flow_f1_f2_f4(t, tree)
    _ac02_freeze(t, tree)
    _ac03_confirm_cancel(t, tree)
    _ac04_new_run_and_stale_input(t, tree)
    _ac05_esc_and_input_boundary(t, tree)
    _ac06_result_ledger(t, tree)
    _ac07_settings_in_scene(t, tree)
    _ac08_bypass(t, tree)
    _cleanup()


# ------------------------------------------------------------------ helpers ---

static func _new_scene(tree: SceneTree, settings_path: String = SETTINGS_TMP) -> Node2D:
    var scene: Node2D = Main.new()
    scene._settings_path = settings_path
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


static func _lmb(scene: Node2D, pressed: bool) -> void:
    var ev: InputEventMouseButton = InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = pressed
    scene._handle_key_event(ev)


## Press a real menu button (its `pressed` signal) and run one frame so the
## queued intent is applied. Returns false when the button is not visible.
static func _click(scene: Node2D, intent: String) -> bool:
    var b: Button = scene.menu.button(intent)
    if b == null or not scene.menu.button_visible(intent):
        return false
    b.pressed.emit()
    _frame(scene)
    return true


static func _start(scene: Node2D) -> void:
    _click(scene, "title_start")


static func _fresh_state_json() -> String:
    return Battle.new(Config.for_wp003()).full_state_json()


## Force a collapse the way the F2 test does (verification-only hooks), then
## run until the collapse tick. Returns the collapse tick.
static func _force_collapse(scene: Node2D) -> int:
    scene.battle.force_outer_hp(1.0, "test forced collapse")
    scene.battle.spawn_extra(OUTER_GOAL, 1, "test trigger enemy")
    var k: int = 0
    while scene.battle.run.collapse_count == 0 and k < 300:
        _frame(scene)
        k += 1
    return scene.battle.run.collapse_tick


## Arrivals only count at the current goal, so a LOST needs the core to be the
## target: collapse first (if not already), then core HP 1 + one arrival.
static func _force_lost(scene: Node2D) -> void:
    if scene.battle.run.collapse_count == 0:
        _force_collapse(scene)
    scene.battle.force_core_hp(1.0, "test forced LOST")
    scene.battle.spawn_extra(CORE_GOAL, 1, "test last arrival")
    var k: int = 0
    while not scene.battle.run.ended() and k < 300:
        _frame(scene)
        k += 1


static func _count(arr: Array, request: String) -> int:
    var n: int = 0
    for e: Dictionary in arr:
        if e["request"] == request:
            n += 1
    return n


func _cleanup() -> void:
    for p: String in [SETTINGS_TMP, "user://wp004_test_corrupt.cfg", "user://wp004_test_invalid.cfg", "user://wp004_test_persist.cfg"]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ----------------------------------------------------------------- units ---

func _flow_unit(t: RefCounted) -> void:
    t.case("PlayFlow unit: legal transitions, return targets, refusals, Esc one level, no quit/restart from TITLE/RESULT Esc")
    var f: PlayFlow = PlayFlow.new()
    t.eq(f.state_name(), "TITLE", "starts on TITLE")
    t.eq(f.pause(), "", "pause refused on TITLE")
    t.eq(f.back(), "", "Esc on TITLE does nothing")
    t.eq(f.start_game(), PlayFlow.ACT_NEW_RUN, "start -> new run")
    t.eq(f.state_name(), "PLAYING", "PLAYING after start")
    t.eq(f.start_game(), "", "start refused while playing")
    t.eq(f.open_settings(), "", "settings from PLAYING pauses first")
    t.eq(f.state_name(), "SETTINGS", "SETTINGS")
    t.eq(f.settings_return, PlayFlow.State.PAUSED, "return target PAUSED (never PLAYING)")
    t.eq(f.back(), "", "Esc closes settings")
    t.eq(f.state_name(), "PAUSED", "back to PAUSED, not PLAYING")
    t.eq(f.back(), "", "Esc on PAUSED resumes")
    t.eq(f.state_name(), "PLAYING", "PLAYING")
    t.eq(f.request_restart(), "", "R while playing opens CONFIRM")
    t.eq(f.state_name(), "CONFIRM", "CONFIRM")
    t.eq(f.confirm_text()["text"], "현재 전투를 종료하고 처음부터 시작할까요?", "restart confirm text")
    t.eq(f.confirm_text()["ok"], "다시 시작", "restart ok label")
    t.eq(f.back(), "", "Esc on CONFIRM cancels only")
    t.eq(f.state_name(), "PLAYING", "cancel returns to PLAYING (opened from R)")
    t.eq(f.pause(), "", "pause")
    t.eq(f.request_to_title(), "", "to title from PAUSED opens CONFIRM")
    t.eq(f.confirm_text()["text"], "현재 전투를 종료하고 시작 화면으로 돌아갈까요? 진행 상황은 저장되지 않습니다.", "to-title confirm text")
    t.eq(f.confirm_text()["ok"], "시작 화면으로", "to-title ok label")
    t.eq(f.cancel_confirm(), "", "cancel")
    t.eq(f.state_name(), "PAUSED", "cancel returns to PAUSED (opened from the pause menu)")
    t.eq(f.request_restart(), "", "restart from PAUSED opens CONFIRM")
    t.eq(f.confirm(), PlayFlow.ACT_NEW_RUN, "confirm -> new run")
    t.eq(f.state_name(), "PLAYING", "PLAYING after confirmed restart")
    t.check(f.run_ended({"outcome": "WON"}), "run ended -> RESULT")
    t.eq(f.state_name(), "RESULT", "RESULT")
    t.eq(f.pause(), "", "pause refused on RESULT")
    t.eq(f.back(), "", "Esc on RESULT does nothing")
    t.eq(f.state_name(), "RESULT", "still RESULT")
    t.eq(f.request_restart(), PlayFlow.ACT_NEW_RUN, "RESULT restart is immediate (no confirm)")
    t.check(f.result.is_empty(), "previous result discarded on restart")
    t.check(f.run_ended({"outcome": "LOST"}), "ended again")
    t.eq(f.request_to_title(), PlayFlow.ACT_TO_TITLE, "RESULT -> title immediate")
    t.eq(f.state_name(), "TITLE", "TITLE")
    t.eq(f.quit_from_title(), PlayFlow.ACT_QUIT, "quit only from TITLE")
    t.eq(f.refused.size(), 5, "every refused request was logged")
    t.check(f.transitions.size() >= 14, "transitions logged (%d)" % f.transitions.size())


func _result_model_unit(t: RefCounted) -> void:
    t.case("ResultModel unit: mm:ss floor, recovery states, outer result text, values from the real ledgers")
    t.eq(ResultModel.format_mmss(105.5), "01:45", "105.5 s -> 01:45 (floor)")
    t.eq(ResultModel.format_mmss(59.99), "00:59", "59.99 -> 00:59")
    t.eq(ResultModel.format_mmss(0.0), "00:00", "0 -> 00:00")
    var b: Battle = Battle.new(Config.for_wp003())
    var m0: Dictionary = ResultModel.build(b)
    t.eq(m0["valid"], false, "not valid before the run ended")
    # F4-style LOST after a collapse without placement
    b.spawning_enabled = false
    b.force_outer_hp(1.0, "unit")
    b.sim.force_spawn(0, OUTER_GOAL)
    b.step(DT)
    b.force_core_hp(1.0, "unit")
    b.sim.force_spawn(0, CORE_GOAL)
    b.step(DT)
    var m: Dictionary = ResultModel.build(b)
    t.eq(m["valid"], true, "valid after the end")
    t.eq(m["outcome"], "LOST", "outcome LOST")
    t.eq(m["recovery"], ResultModel.RECOVERY_WAITING, "collapsed, H1 not placed -> 회수 후 미배치")
    t.eq(m["recovery_anchor"], null, "no anchor")
    t.eq(m["outer_result"], "외곽 붕괴 · 00:00", "collapse time text")
    t.eq(m["outer_arrivals"], b.run.outer_arrivals, "outer arrivals from RunState")
    t.eq(m["core_arrivals"], b.run.core_arrivals, "core arrivals from RunState")
    t.eq(m["kills"], b.sim.killed_total, "kills from EnemySim")
    t.eq(m["core_hp"], 0.0, "core HP 0")
    t.eq(m["core_hp_max"], 60.0, "core HP max 60")
    t.eq(m["wave_reached"], 1, "wave 1 (1-based)")
    t.eq(m["play_time_seconds"], b.run.end_sim_time, "play time = end sim time")
    t.eq(ResultModel.lines(m)[7][1], "—", "unplaced position shows —")
    t.eq(ResultModel.lines(m)[0][1], "패배", "결과 line")
    # placed variant
    var c: Battle = Battle.new(Config.for_wp003())
    c.spawning_enabled = false
    c.force_outer_hp(1.0, "unit")
    c.sim.force_spawn(0, OUTER_GOAL)
    c.step(DT)
    t.check(c.place_recovery(TestMap.RECOVERY_B).ok, "placed at B")
    c.waves.configure([], 5.0, 3)
    c.step(DT)
    t.eq(c.run.run_name(), "WON", "WON with an empty schedule")
    var mc: Dictionary = ResultModel.build(c)
    t.eq(mc["recovery"], ResultModel.RECOVERY_PLACED, "재배치 완료")
    t.eq(mc["recovery_anchor"], [44, 13], "anchor (44,13)")
    t.eq(mc["recovery_world"], [900.0, 280.0], "world centre (900,280)")
    t.eq(ResultModel.lines(mc)[7][1], "(44, 13)", "position line")
    t.eq(mc["won"], true, "won")


func _settings_unit(t: RefCounted) -> void:
    t.case("UserSettings unit: missing -> defaults, save/reload persists, corrupt/invalid -> defaults, save failure reported")
    _cleanup()
    var s: UserSettings = UserSettings.new(SETTINGS_TMP)
    var r: Dictionary = s.load()
    t.eq(r["ok"], false, "missing file: not ok")
    t.eq(r["reason"], "missing", "reason missing")
    t.eq(s.window_mode, "windowed", "default windowed")
    var sv: Dictionary = s.set_window_mode("fullscreen")
    t.eq(sv["ok"], true, "save ok")
    t.check(FileAccess.file_exists(SETTINGS_TMP), "file written")
    var s2: UserSettings = UserSettings.new(SETTINGS_TMP)
    t.eq(s2.load()["reason"], "loaded", "reload ok")
    t.eq(s2.window_mode, "fullscreen", "fullscreen persisted across instances (= app relaunch)")
    t.eq(s2.window_mode_label(), "전체화면", "label")
    t.eq(s2.toggle_window_mode()["ok"], true, "toggle saves")
    t.eq(UserSettings.new(SETTINGS_TMP).load()["window_mode"], "windowed", "toggle persisted")
    var bad: String = "user://wp004_test_corrupt.cfg"
    var f: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
    f.store_string("this is = not [a valid\n[[config")
    f.close()
    var sc: UserSettings = UserSettings.new(bad)
    var rc: Dictionary = sc.load()
    t.eq(rc["ok"], false, "corrupt file: not ok")
    t.eq(rc["reason"], "parse_error", "corrupt -> parse_error")
    t.eq(sc.window_mode, "windowed", "corrupt -> default")
    var inv: String = "user://wp004_test_invalid.cfg"
    var cf: ConfigFile = ConfigFile.new()
    cf.set_value("display", "window_mode", "borderless_giant")
    cf.save(inv)
    var si: UserSettings = UserSettings.new(inv)
    t.eq(si.load()["reason"], "invalid_value", "out-of-range value -> invalid_value")
    t.eq(si.window_mode, "windowed", "invalid -> default")
    t.eq(si.set_window_mode("nope")["ok"], false, "setting an invalid mode is refused")
    var sf: UserSettings = UserSettings.new("user://wp004_no_such_dir/deeper/settings.cfg")
    var rf: Dictionary = sf.set_window_mode("fullscreen")
    t.eq(rf["ok"], false, "save into a missing directory fails")
    t.check(str(rf["error"]) != "", "failure carries an error string (%s)" % str(rf["error"]))
    t.eq(sf.window_mode, "fullscreen", "value stays usable in the session after a failed save")


# ------------------------------------------------------------------ scene ---

func _launch_title(t: RefCounted, tree: SceneTree) -> void:
    t.case("interactive launch: TITLE, static field, no battle tick, HUD hidden, settings loaded from the injected path")
    _cleanup()
    var scene: Node2D = _new_scene(tree)
    t.eq(scene.flow.state_name(), "TITLE", "TITLE")
    t.eq(scene.flow.bypass, false, "not bypassed")
    t.check(scene.menu.visible, "menu layer visible")
    t.eq(scene.menu.current_state(), "TITLE", "TITLE panel")
    t.eq(scene.menu.visible_buttons(), ["title_quit", "title_settings", "title_start"], "TITLE buttons: 게임 시작 / 설정 / 종료")
    t.eq(scene._hud_layer.visible, false, "HUD hidden on TITLE")
    t.eq(scene.settings.path, SETTINGS_TMP, "settings path injected")
    t.eq(scene.settings.last_load["reason"], "missing", "no file -> defaults, launch not blocked")
    _frame(scene, 30)
    t.eq(scene.battle.steps, 0, "no battle tick on TITLE (30 frames)")
    t.check(scene.battle.full_state_json() == _fresh_state_json(), "TITLE field is the initial state")
    _drop(scene)


func _ac01_flow_f1_f2_f4(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-01 TITLE -> PLAYING -> RESULT -> restart / title through real buttons; F1 win, F2 recovery win, F4 loss")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    t.eq(scene.flow.state_name(), "PLAYING", "게임 시작 -> PLAYING")
    t.check(scene._hud_layer.visible, "HUD shown while playing")
    t.check(scene.menu.visible == false, "menu hidden while playing")
    t.eq(scene.battle.steps, 1, "first frame advanced one tick")
    # --- F1: no input, HP 360 -> WON, RESULT appears automatically
    scene._sim_speed = 60
    var frames: int = 0
    while scene.flow.state != PlayFlow.State.RESULT and frames < 400:
        _frame(scene)
        frames += 1
    t.eq(scene.flow.state_name(), "RESULT", "F1 ended -> RESULT (%d frames)" % frames)
    t.eq(scene.battle.run.run_name(), "WON", "F1 WON")
    t.eq(scene.flow.result["outcome"], "WON", "result model WON")
    t.eq(scene.flow.result["outer_result"], "외곽 유지", "외곽 유지")
    t.eq(scene.flow.result["recovery"], "회수 없음", "회수 없음")
    t.eq(scene.flow.result["play_time_text"], "01:39", "F1 play time 99.8 s -> 01:39")
    t.eq(scene.flow.result["kills"], 826, "F1 kills 826")
    t.eq(scene.flow.result["outer_arrivals"], 314, "F1 outer arrivals 314")
    t.eq(scene.menu.visible_buttons(), ["result_restart", "result_to_title"], "RESULT buttons")
    # restart from RESULT: immediate, new run equals the initial state, run_id + 1
    var id1: int = scene.battle.run.run_id
    scene._sim_speed = 1
    t.check(_click(scene, "result_restart"), "다시 시작 pressed")
    t.eq(scene.flow.state_name(), "PLAYING", "RESULT restart -> PLAYING without confirmation")
    t.eq(scene.battle.run.run_id, id1 + 1, "run_id + 1")
    t.eq(scene.battle.steps, 1, "new run ticked once in that frame")
    t.check(scene.flow.result.is_empty(), "previous result discarded")
    # --- F2: forced collapse at 20 s, recovery at B via a real click, WON
    scene._sim_speed = 60
    _frame(scene, 20)
    t.eq(scene.battle.steps, 1201, "20 s played")
    scene._sim_speed = 1
    var ct: int = _force_collapse(scene)
    t.eq(scene.battle.run.collapse_count, 1, "collapsed at tick %d" % ct)
    scene._sim_speed = 60
    _frame(scene, 5)
    scene._sim_speed = 1
    scene._cursor_world_override = scene.battle.grid.cell_center(TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y)
    _lmb(scene, true)
    _lmb(scene, false)
    t.check(scene.battle.run.recovery_placed, "H1 placed at B by the real click")
    scene._sim_speed = 60
    frames = 0
    while scene.flow.state != PlayFlow.State.RESULT and frames < 400:
        _frame(scene)
        frames += 1
    t.eq(scene.battle.run.run_name(), "WON", "F2 WON")
    t.eq(scene.flow.result["recovery"], "재배치 완료", "재배치 완료")
    t.eq(scene.flow.result["recovery_anchor"], [44, 13], "position (44,13)")
    t.check(str(scene.flow.result["outer_result"]).begins_with("외곽 붕괴 · 00:20"), "외곽 붕괴 · 00:20 (%s)" % scene.flow.result["outer_result"])
    # --- F4: forced LOST, then 시작 화면으로 (no confirmation)
    scene._sim_speed = 1
    t.check(_click(scene, "result_restart"), "restart again")
    _frame(scene, 60)
    _force_lost(scene)
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "LOST -> RESULT")
    t.eq(scene.flow.result["outcome"], "LOST", "result LOST")
    t.eq(scene.flow.result["core_hp"], 0.0, "core HP 0")
    var id3: int = scene.battle.run.run_id
    t.check(_click(scene, "result_to_title"), "시작 화면으로 pressed")
    t.eq(scene.flow.state_name(), "TITLE", "RESULT -> TITLE without confirmation")
    t.check(scene.battle.full_state_json() == _fresh_state_json(), "TITLE discards the run: initial field again")
    t.eq(scene._hud_layer.visible, false, "HUD hidden on TITLE")
    _start(scene)
    t.eq(scene.battle.run.run_id, id3 + 2, "TITLE start is a new run (never a continuation)")
    _drop(scene)


func _ac02_freeze(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-02 PAUSED / SETTINGS / CONFIRM: 120 UI frames each, battle structured state unchanged, no placement, no catch-up on resume")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    scene._sim_speed = 60
    _frame(scene, 10)
    scene._sim_speed = 1
    _force_collapse(scene)
    t.check(scene.battle.placement.detached.has(1) and scene.battle.sim.alive_count > 0, "enemies moving, H1 waiting for recovery")
    scene._cursor_world_override = scene.battle.grid.cell_center(TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y)
    for entry: Array in [["pause", "PAUSED"], ["pause_settings", "SETTINGS"], ["pause_restart", "CONFIRM"]]:
        if entry[0] == "pause":
            _key(scene, KEY_ESCAPE)
            _frame(scene)
        else:
            t.check(_click(scene, entry[0]), "%s opened" % entry[0])
        t.eq(scene.flow.state_name(), entry[1], "state %s" % entry[1])
        var before: String = scene.battle.full_state_json()
        var steps: int = scene.battle.steps
        var accepted: int = scene.battle.commands_accepted
        var rejected: int = scene.battle.commands_rejected
        # a held click during the menu must not place anything behind it
        _lmb(scene, true)
        _frame(scene, 120)
        _lmb(scene, false)
        t.check(scene.battle.full_state_json() == before, "%s: complete battle state unchanged over 120 frames" % entry[1])
        t.eq(scene.battle.steps, steps, "%s: no tick" % entry[1])
        t.eq(scene.battle.commands_accepted, accepted, "%s: no placement" % entry[1])
        t.eq(scene.battle.commands_rejected, rejected, "%s: no command at all" % entry[1])
        t.eq(scene.battle.run.recovery_right, 1, "%s: recovery right untouched" % entry[1])
        if entry[1] == "SETTINGS":
            _key(scene, KEY_ESCAPE)
            _frame(scene)
            t.eq(scene.flow.state_name(), "PAUSED", "settings Esc -> PAUSED")
        elif entry[1] == "CONFIRM":
            t.check(_click(scene, "confirm_cancel"), "cancel")
            t.eq(scene.flow.state_name(), "PAUSED", "confirm cancel -> PAUSED")
    # resume: exactly one tick per frame, no catch-up of the 360 frozen frames
    var steps_before: int = scene.battle.steps
    var time_before: float = scene.battle.sim_time
    t.check(_click(scene, "pause_continue"), "계속하기")
    t.eq(scene.flow.state_name(), "PLAYING", "PLAYING again")
    t.eq(scene.battle.steps, steps_before + 1, "resume frame advanced exactly one tick (no catch-up)")
    _frame(scene, 5)
    t.eq(scene.battle.steps, steps_before + 6, "5 more frames -> 5 more ticks")
    t.check(absf(scene.battle.sim_time - time_before - 6.0 * DT) < 1e-5, "sim time advanced by 6 ticks only")
    _drop(scene)


func _ac03_confirm_cancel(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-03 R while playing / 다시 시작 while paused: cancel restores the entry state, confirm makes exactly one new run; RESULT restart needs no confirm")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    _frame(scene, 30)
    var st: String = scene.battle.full_state_json()
    var id0: int = scene.battle.run.run_id
    _key(scene, KEY_R)
    _frame(scene)
    t.eq(scene.flow.state_name(), "CONFIRM", "R while PLAYING opens CONFIRM (no immediate reset)")
    t.eq(scene.menu.visible_buttons(), ["confirm_cancel", "confirm_ok"], "CONFIRM buttons")
    t.eq(scene.menu.button("confirm_ok").text, "다시 시작", "ok label")
    _frame(scene, 10)
    t.check(scene.battle.full_state_json() == st, "battle untouched while the confirmation is open")
    t.check(_click(scene, "confirm_cancel"), "취소")
    t.eq(scene.flow.state_name(), "PLAYING", "cancel from R -> back to PLAYING (battle resumes)")
    t.eq(scene.battle.run.run_id, id0, "same run")
    _key(scene, KEY_R)
    _frame(scene)
    t.check(_click(scene, "confirm_ok"), "확인")
    t.eq(scene.battle.run.run_id, id0 + 1, "confirmed restart: exactly one new run")
    t.eq(_count(scene.flow.transitions, "confirm_restart"), 1, "one confirm_restart transition")
    # from PAUSED
    _key(scene, KEY_P)
    _frame(scene)
    t.check(_click(scene, "pause_restart"), "다시 시작 (paused)")
    t.eq(scene.flow.state_name(), "CONFIRM", "CONFIRM from PAUSED")
    t.check(_click(scene, "confirm_cancel"), "취소")
    t.eq(scene.flow.state_name(), "PAUSED", "cancel from the pause menu stays PAUSED")
    t.check(_click(scene, "pause_to_title"), "시작 화면으로 (paused)")
    t.eq(scene.menu.button("confirm_ok").text, "시작 화면으로", "to-title ok label")
    t.check(_click(scene, "confirm_cancel"), "취소")
    t.eq(scene.flow.state_name(), "PAUSED", "cancel keeps PAUSED")
    t.check(_click(scene, "pause_to_title"), "시작 화면으로 again")
    var before_title: int = _count(scene.flow.transitions, "confirm_to_title")
    t.check(_click(scene, "confirm_ok"), "확인")
    t.eq(scene.flow.state_name(), "TITLE", "confirmed -> TITLE exactly once")
    t.eq(_count(scene.flow.transitions, "confirm_to_title"), before_title + 1, "one confirm_to_title transition")
    # rapid double click on 다시 시작 in RESULT: one new run
    _start(scene)
    _force_lost(scene)
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "RESULT")
    var idr: int = scene.battle.run.run_id
    var b: Button = scene.menu.button("result_restart")
    b.pressed.emit()
    b.pressed.emit()
    _frame(scene)
    t.eq(scene.battle.run.run_id, idr + 1, "double click -> exactly one new run")
    t.eq(scene.stale_intents.size(), 1, "second click dropped as stale")
    t.eq(scene.flow.state_name(), "PLAYING", "PLAYING")
    _drop(scene)


func _ac04_new_run_and_stale_input(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-04 new run == WP-003 initial state (run_id excluded) after WON / LOST / in-progress; stale hold and pending inputs never act")
    var fresh: String = _fresh_state_json()
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    # in-progress restart with a held click on B
    scene._sim_speed = 60
    _frame(scene, 5)
    scene._sim_speed = 1
    _force_collapse(scene)
    scene._cursor_world_override = Vector2(100.0, 100.0)   # a wall: the hold keeps retrying and being refused
    _lmb(scene, true)
    t.check(scene._mouse_down, "hold active")
    var id0: int = scene.battle.run.run_id
    _key(scene, KEY_R)
    _frame(scene)
    t.eq(scene._mouse_down, false, "opening the confirmation dropped the hold")
    t.check(_click(scene, "confirm_ok"), "confirm")
    t.eq(scene.battle.run.run_id, id0 + 1, "new run")
    var after: Dictionary = JSON.parse_string(scene.battle.full_state_json())
    var want: Dictionary = JSON.parse_string(fresh)
    # the new run has ticked once in the confirming frame; compare against the fresh run stepped once
    var ref: Battle = Battle.new(Config.for_wp003())
    ref.step(DT)
    t.check(scene.battle.full_state_json() == ref.full_state_json(), "in-progress restart: state == fresh WP-003 run after the same tick (run_id excluded)")
    t.eq(scene.battle.run.recovery_right, 0, "no recovery right carried over")
    t.eq(scene.battle.placement.detached.size(), 0, "H1 back on the map")
    t.eq(scene.battle.run.forced_hp_writes, 0, "forced HP writes cleared")
    t.eq(int(after["steps"]), 1, "1 tick")
    t.eq(int(want["steps"]), 0, "(fresh reference not stepped)")
    # after LOST / WON: compare at tick 0 by looking right after the click? The click frame ticks once,
    # so compare with the once-stepped reference again.
    _force_lost(scene)
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "LOST")
    t.check(_click(scene, "result_restart"), "restart after LOST")
    t.check(scene.battle.full_state_json() == ref.full_state_json(), "restart after LOST: initial state")
    scene._sim_speed = 60
    var frames: int = 0
    while scene.flow.state != PlayFlow.State.RESULT and frames < 400:
        _frame(scene)
        frames += 1
    t.eq(scene.battle.run.run_name(), "WON", "played to WON")
    scene._sim_speed = 1
    t.check(_click(scene, "result_restart"), "restart after WON")
    t.check(scene.battle.full_state_json() == ref.full_state_json(), "restart after WON: initial state")
    # pending pause / restart issued before the run ended must not override RESULT nor start a run
    _frame(scene, 10)
    _force_lost(scene)
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "RESULT")
    var idr: int = scene.battle.run.run_id
    scene._intents.append({"intent": "pause", "arg": null, "state": "PLAYING"})
    scene._intents.append({"intent": "restart", "arg": null, "state": "PLAYING"})
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "RESULT kept over the pending pause / restart")
    t.eq(scene.battle.run.run_id, idr, "no automatic new run")
    t.eq(scene.stale_intents.size(), 2, "both pending inputs dropped as stale")
    _drop(scene)


func _ac05_esc_and_input_boundary(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-05 Esc hierarchy (settings -> pause -> play, confirm cancel only), menu input consumed, new field input only after a fresh press")
    var scene: Node2D = _new_scene(tree)
    _key(scene, KEY_ESCAPE)
    _frame(scene)
    t.eq(scene.flow.state_name(), "TITLE", "Esc on TITLE does not quit (still TITLE)")
    _start(scene)
    _frame(scene, 5)
    _force_collapse(scene)
    scene._cursor_world_override = scene.battle.grid.cell_center(TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y)
    _key(scene, KEY_ESCAPE)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PAUSED", "Esc -> PAUSED")
    t.check(_click(scene, "pause_settings"), "설정")
    t.eq(scene.flow.state_name(), "SETTINGS", "SETTINGS")
    _key(scene, KEY_R)
    _key(scene, KEY_P)
    _frame(scene)
    t.eq(scene.flow.state_name(), "SETTINGS", "R / P do nothing in SETTINGS")
    _key(scene, KEY_ESCAPE)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PAUSED", "Esc closes SETTINGS -> PAUSED (one level)")
    t.check(_click(scene, "pause_restart"), "다시 시작")
    _key(scene, KEY_R)
    _frame(scene)
    t.eq(scene.flow.state_name(), "CONFIRM", "R does nothing in CONFIRM")
    _key(scene, KEY_ESCAPE)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PAUSED", "Esc on CONFIRM cancels only (-> PAUSED)")
    # a click that closes nothing (press while paused) and the release after resume: no placement
    var accepted: int = scene.battle.commands_accepted
    var rejected: int = scene.battle.commands_rejected
    _lmb(scene, true)
    _frame(scene)
    t.eq(scene._mouse_down, false, "press while paused is consumed")
    _key(scene, KEY_ESCAPE)
    _frame(scene)
    t.eq(scene.flow.state_name(), "PLAYING", "Esc on PAUSED resumes")
    _lmb(scene, false)
    _frame(scene, 3)
    t.eq(scene.battle.commands_accepted, accepted, "the release after resume placed nothing")
    t.eq(scene.battle.commands_rejected, rejected, "no command issued by the leftover release / hold")
    t.eq(scene.battle.run.recovery_right, 1, "recovery right still available")
    # a NEW press after the release is real field input
    _lmb(scene, true)
    t.check(scene.battle.run.recovery_placed, "a fresh press places H1 at B")
    t.eq(scene.battle.commands_accepted, accepted + 1, "exactly one accepted command")
    _lmb(scene, false)
    # quit only from TITLE: Esc on RESULT does nothing
    _force_lost(scene)
    _frame(scene)
    _key(scene, KEY_ESCAPE)
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "Esc on RESULT does nothing")
    _drop(scene)


func _ac06_result_ledger(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-06 result model == battle ledgers, frozen for 120 frames, pause time excluded, unplaced shown as —")
    var scene: Node2D = _new_scene(tree)
    _start(scene)
    _frame(scene, 30)
    _key(scene, KEY_ESCAPE)
    _frame(scene, 120)      # paused for 120 frames: must not count as play time
    _key(scene, KEY_ESCAPE)
    _frame(scene, 30)
    _force_collapse(scene)
    _frame(scene, 60)
    _force_lost(scene)
    _frame(scene)
    t.eq(scene.flow.state_name(), "RESULT", "RESULT")
    var m: Dictionary = scene.flow.result
    var b: Battle = scene.battle
    t.eq(m["outcome"], b.run.run_name(), "outcome")
    t.eq(m["play_time_seconds"], b.run.end_sim_time, "play time = battle end sim time")
    t.check(absf(float(m["play_time_seconds"]) - float(b.steps) * DT) < 1e-3, "play time == ticks * dt (%.3f), pause frames excluded" % float(m["play_time_seconds"]))
    t.eq(m["play_time_text"], ResultModel.format_mmss(b.run.end_sim_time), "mm:ss")
    t.eq(m["wave_reached"], int(b.waves.snapshot()["wave_index"]) + 1, "wave 1-based")
    t.eq(m["kills"], b.sim.killed_total, "kills")
    t.eq(m["outer_arrivals"], b.run.outer_arrivals, "outer arrivals")
    t.eq(m["core_arrivals"], b.run.core_arrivals, "core arrivals")
    t.eq(m["outer_collapsed"], true, "collapsed")
    t.eq(m["collapse_time_seconds"], b.run.collapse_sim_time, "collapse time")
    t.eq(m["recovery"], "회수 후 미배치", "미배치")
    t.eq(ResultModel.lines(m)[7][1], "—", "position —")
    t.eq(m["core_hp"], b.run.core_hp, "core hp")
    t.eq(m["core_hp_max"], b.run.core_hp_max, "core hp max")
    var frozen: String = JSON.stringify(m)
    var battle_frozen: String = b.full_state_json()
    _frame(scene, 120)
    t.eq(JSON.stringify(scene.flow.result), frozen, "result unchanged after 120 frames on RESULT")
    t.check(b.full_state_json() == battle_frozen, "battle unchanged after 120 frames on RESULT")
    _drop(scene)


func _ac07_settings_in_scene(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-07 settings screen: toggle applies + saves, same value on TITLE and PAUSED, persists across launches, save failure notice")
    _cleanup()
    var scene: Node2D = _new_scene(tree)
    t.check(_click(scene, "title_settings"), "설정 from TITLE")
    t.eq(scene.flow.state_name(), "SETTINGS", "SETTINGS")
    t.eq(scene.menu.button("settings_window_mode").text, "창 모드", "default label")
    t.check(_click(scene, "settings_window_mode"), "toggle")
    t.eq(scene.settings.window_mode, "fullscreen", "fullscreen in memory")
    t.eq(scene.menu.button("settings_window_mode").text, "전체화면", "label updated")
    t.check(FileAccess.file_exists(SETTINGS_TMP), "saved immediately")
    t.check(_click(scene, "settings_back"), "뒤로")
    t.eq(scene.flow.state_name(), "TITLE", "back -> TITLE")
    _start(scene)
    _key(scene, KEY_P)
    _frame(scene)
    t.check(_click(scene, "pause_settings"), "설정 from PAUSED")
    t.eq(scene.menu.button("settings_window_mode").text, "전체화면", "same value shown from PAUSED")
    _drop(scene)
    var relaunch: Node2D = _new_scene(tree)
    t.eq(relaunch.settings.window_mode, "fullscreen", "relaunch keeps fullscreen")
    _drop(relaunch)
    var broken: Node2D = _new_scene(tree, "user://wp004_no_such_dir/deeper/settings.cfg")
    t.eq(broken.flow.state_name(), "TITLE", "unwritable settings path still launches")
    t.check(_click(broken, "title_settings"), "설정")
    t.check(_click(broken, "settings_window_mode"), "toggle")
    t.eq(broken.settings.window_mode, "fullscreen", "value applied for the session")
    t.check(broken.menu._settings_notice.text.begins_with("설정 저장 실패"), "save failure notice shown (%s)" % broken.menu._settings_notice.text)
    _drop(broken)


func _ac08_bypass(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-08 scripted modes bypass the menus and never load settings; wp004_ui capture keeps the menus")
    var scene: Node2D = _new_scene(tree)
    scene._perf = PerfRecorder.new()
    scene._perf_scenario = "collapse_move"
    scene._apply_run_mode()
    t.eq(scene.flow.bypass, true, "--perf bypasses the menus")
    t.eq(scene.flow.state_name(), "PLAYING", "PLAYING at once")
    t.eq(scene.menu.visible, false, "menu hidden")
    t.eq(scene.settings, null, "settings not loaded in perf mode")
    _frame(scene, 3)
    t.eq(scene.battle.steps, 3, "battle ticks without any menu interaction")
    t.eq(scene.battle.density.zones.size(), 10, "WP-003 zones for collapse scenarios")
    scene._perf = null
    scene._capture_name = "ac02"
    scene._capture_dir = "user://"
    scene._apply_run_mode()
    t.eq(scene.flow.bypass, true, "--capture=ac02 bypasses")
    t.eq(scene.battle.density.zones.size(), 8, "legacy 8 zones")
    scene._capture_name = "wp004_ui"
    scene._settings_path = ""
    scene._apply_run_mode()
    t.eq(scene.flow.bypass, false, "wp004_ui keeps the menus")
    t.eq(scene.flow.state_name(), "TITLE", "wp004_ui starts on TITLE")
    t.eq(scene.settings.path, "user://wp004_capture_settings.cfg", "capture without --settings uses a throwaway path, not the player's file")
    scene._settings_path = SETTINGS_TMP
    scene._apply_run_mode()
    t.eq(scene.settings.path, SETTINGS_TMP, "capture with --settings uses the injected path")
    scene._capture_name = ""
    _drop(scene)
