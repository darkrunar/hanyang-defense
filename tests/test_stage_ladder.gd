extends RefCounted
## Core-loop expansion ladder (docs/CORE_LOOP_STAGES.md, D-056): the stage
## data, each stage's headless A/B check, and the real scene in every test
## mode (`--stage=N`): flow, allowed commands, refusal hints, stage switching.

const Main := preload("res://game/scenes/main.gd")
const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const PlayFlow := preload("res://game/core/play_flow.gd")
const StageLadder := preload("res://game/core/stage_ladder.gd")
const StageChecks := preload("res://game/tools/stage_checks.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SETTINGS_TMP: String = "user://stage_test_settings.cfg"
const DT: float = 0.0166666667
const OUTER_GOAL: Vector2 = Vector2(950.0, 530.0)
const CORE_GOAL: Vector2 = Vector2(950.0, 210.0)


func run(t: RefCounted) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    _data(t)
    _checks(t)
    _scene_each_stage(t, tree)
    _scene_commands(t, tree)
    _scene_switching(t, tree)
    _scene_loop_and_build(t, tree)
    if FileAccess.file_exists(SETTINGS_TMP):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TMP))


static func _new_scene(tree: SceneTree, stage: String) -> Node2D:
    var scene: Node2D = Main.new()
    scene._settings_path = SETTINGS_TMP
    scene._art_mode = "greybox"
    scene._stage_arg = stage
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


static func _tap(scene: Node2D, keycode: int) -> void:
    for pressed: bool in [true, false]:
        var ev: InputEventKey = InputEventKey.new()
        ev.keycode = keycode
        ev.pressed = pressed
        scene._handle_key_event(ev)


static func _click(scene: Node2D, anchor: Vector2i) -> void:
    scene._cursor_world_override = scene.battle.grid.cell_center(anchor.x, anchor.y)
    for pressed: bool in [true, false]:
        var ev: InputEventMouseButton = InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = pressed
        scene._handle_key_event(ev)


func _data(t: RefCounted) -> void:
    t.case("ladder data: 8 playable stages in order, planned 9.., parse, presets, one new command kind at a time")
    t.eq(StageLadder.count(), 8, "8 playable stages")
    for i: int in range(StageLadder.count()):
        var st: Dictionary = StageLadder.STAGES[i]
        t.eq(int(st["id"]), i + 1, "stage %d id in order" % (i + 1))
        for k: String in ["key", "title", "wp", "adds", "verb", "preset", "observe", "check"]:
            t.check(str(st.get(k, "")) != "", "stage %d has %s" % [i + 1, k])
    for p: Dictionary in StageLadder.PLANNED:
        t.check(not StageLadder.is_playable(int(p["id"])), "planned stage %d is not launchable (%s)" % [int(p["id"]), p["wp"]])
    t.eq(StageLadder.parse("3"), 3, "parse number")
    t.eq(StageLadder.parse("hwacha"), 3, "parse key")
    t.eq(StageLadder.parse("stage4"), 4, "parse stageN")
    t.eq(StageLadder.parse("gate"), 9, "parse planned key")
    t.eq(StageLadder.parse("nope"), -1, "unknown")
    var expect: Array = [
        # [run_mode, fixture, targeting, combat, play_mode, outer_hp]
        ["sandbox", "none", "wp001", false, "classic", 360.0],
        ["sandbox", "none", "wp001", false, "classic", 360.0],
        ["sandbox", "wp001", "wp001", true, "classic", 360.0],
        ["sandbox", "b", "wp002", true, "classic", 360.0],
        ["waves", "c", "wp002", true, "classic", 360.0],
        ["waves", "c", "wp002", true, "classic", 40.0],
        ["waves", "c", "wp002", true, "classic", 360.0],
        ["waves", "build", "wp002", true, "build", 360.0],
    ]
    for i: int in range(expect.size()):
        var c: Config = StageLadder.config_for(i + 1)
        var e: Array = expect[i]
        var got: Array = [c.get_str("run_mode"), c.get_str("fixture"), c.get_str("targeting_mode"), c.get_bool("combat_enabled"),
            c.get_str("play_mode"), c.get_num("outer_hp")]
        t.eq(got, e, "stage %d preset" % (i + 1))
    t.eq(StageLadder.stage_adding_kind(Placement.Kind.JANGSEUNG), 2, "장승 first at stage 2")
    t.eq(StageLadder.stage_adding_kind(Placement.Kind.HWACHA), 3, "화차 first at stage 3")
    t.eq(StageLadder.stage_adding_kind(Placement.Kind.BONGSU), 4, "봉수대 first at stage 4")
    t.eq(StageLadder.stage_adding_kind(Placement.Kind.SENSOR), 4, "혼천의 first at stage 4 (with the bongsu: the network is one content)")
    # sandbox stages 1..4 only ever add command kinds
    for i: int in range(1, 4):
        for k: Variant in StageLadder.STAGES[i - 1]["kinds"]:
            t.check((StageLadder.STAGES[i]["kinds"] as Array).has(k), "stage %d keeps stage %d's kinds" % [i + 1, i])


func _checks(t: RefCounted) -> void:
    t.case("per-stage A/B checks on the real Battle (same seed): each stage's new content changes what its check measures")
    for id: int in range(1, StageLadder.count() + 1):
        var r: Dictionary = StageChecks.run(id)
        t.check(bool(r["pass"]), "stage %d %s: %s %s" % [id, r["key"], r["check"], str(r["failed"])])
        t.note("stage %d metrics %s" % [id, JSON.stringify(r["metrics"])])


func _scene_each_stage(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene --stage=N: preset, flow (1..6 direct, 7/8 menus), stage panel with the stage text")
    for id: int in range(1, StageLadder.count() + 1):
        var st: Dictionary = StageLadder.get_stage(id)
        var scene: Node2D = _new_scene(tree, str(id))
        t.eq(scene._stage, id, "stage %d entered" % id)
        t.eq(scene.battle.run_mode, StageLadder.config_for(id).get_str("run_mode"), "stage %d run mode" % id)
        t.eq(scene.config.get_str("fixture"), StageLadder.config_for(id).get_str("fixture"), "stage %d fixture" % id)
        if bool(st["menus"]):
            t.eq(scene.flow.state_name(), "TITLE", "stage %d starts on TITLE" % id)
            t.eq(scene.flow.bypass, false, "stage %d uses the real menus" % id)
        else:
            t.eq(scene.flow.state_name(), "PLAYING", "stage %d starts at once" % id)
            _frame(scene, 3)
            t.eq(scene.battle.steps, 3, "stage %d ticks from the first frame" % id)
        t.eq(scene._stage_layer.visible, true, "stage %d panel visible" % id)
        t.check(scene._stage_label.text.find(str(st["title"])) >= 0, "stage %d panel names the stage" % id)
        t.check(scene._stage_label.text.find("지금:") >= 0, "stage %d panel has the live line" % id)
        _drop(scene)
    # integration 2026-09-24: stage modes are a developer tool -> developer view by default
    var sd: Node2D = _new_scene(tree, "3")
    t.eq(sd._player_view, false, "--stage opens in the developer view")
    t.eq(sd._show_zones and sd._show_ranges, true, "zones and rings on (stage 3 asks to look at them)")
    _drop(sd)
    var sp: Node2D = Main.new()
    sp._settings_path = SETTINGS_TMP
    sp._art_mode = "greybox"
    sp._stage_arg = "2"
    sp._view_arg = "player"
    tree.root.add_child(sp)
    if not sp.is_node_ready():
        sp._ready()
    sp.set_process(false)
    sp.set_physics_process(false)
    t.eq(sp._player_view, true, "--stage with --view=player: player view")
    sp._update_hud()
    t.check(sp._hud.text.find("1장승") >= 0 and sp._hud.text.find("2화차") < 0, "player HUD uses the stage's own controls line (%s)" % sp._hud.text.get_slice("\n", 1))
    _drop(sp)
    var planned: Node2D = _new_scene(tree, "9")
    t.eq(planned._stage, 0, "--stage=9 (planned) enters no stage")
    t.check(planned._last_notice.find("WP-009") >= 0, "and says it is WP-009 DRAFT (%s)" % planned._last_notice)
    t.eq(planned.battle.run_mode, "waves", "the default launch is kept")
    _drop(planned)


func _scene_commands(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: each stage lets through only its own commands and names the stage that adds a refused one")
    var s1: Node2D = _new_scene(tree, "1")
    _click(s1, TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    t.eq(s1.battle.placement.structures.size(), 0, "stage 1: click places nothing")
    t.check(s1._last_notice.find("관찰") >= 0, "stage 1: says it is an observation stage (%s)" % s1._last_notice)
    _tap(s1, KEY_1)
    t.check(s1._last_notice.find("단계 2") >= 0, "stage 1: key 1 refused, points to stage 2")
    _drop(s1)
    var s2: Node2D = _new_scene(tree, "2")
    _tap(s2, KEY_2)
    t.eq(s2._place_mode, Placement.Kind.JANGSEUNG, "stage 2: key 2 refused, mode stays 장승")
    t.check(s2._last_notice.find("단계 3") >= 0, "stage 2: refusal points to stage 3 (%s)" % s2._last_notice)
    _tap(s2, KEY_C)
    t.check(s2._last_notice.find("단계 3") >= 0, "stage 2: C refused, points to stage 3")
    var ctl: String = s2._stage_controls_line()
    t.check(ctl.find("1장승") >= 0 and ctl.find("2화차") < 0 and ctl.find("T 활성전환") < 0, "stage 2: HUD controls list only 장승 (%s)" % ctl)
    _click(s2, TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    t.eq(s2.battle.placement.count_of(Placement.Kind.JANGSEUNG), 1, "stage 2: click places a 장승")
    t.eq(s2.battle.path.path_version, 3, "stage 2: path rebuilt")
    _drop(s2)
    var s3: Node2D = _new_scene(tree, "3")
    t.eq(s3.battle.placement.count_of(Placement.Kind.HWACHA), 4, "stage 3: the four WP-001 hwachas")
    _tap(s3, KEY_3)
    t.check(s3._last_notice.find("단계 4") >= 0, "stage 3: key 3 refused, points to stage 4")
    _tap(s3, KEY_2)
    t.eq(s3._place_mode, Placement.Kind.HWACHA, "stage 3: key 2 selects 화차")
    _tap(s3, KEY_T)
    t.check(s3._last_notice.find("단계 4") >= 0, "stage 3: T refused, points to stage 4")
    var combat_before: bool = s3.battle.combat_enabled
    _tap(s3, KEY_C)
    t.eq(s3.battle.combat_enabled, not combat_before, "stage 3: C toggles combat")
    _drop(s3)
    var s4: Node2D = _new_scene(tree, "4")
    _tap(s4, KEY_4)
    t.eq(s4._place_mode, Placement.Kind.SENSOR, "stage 4: key 4 selects 혼천의")
    _click(s4, Vector2i(40, 20))
    t.eq(s4.battle.placement.count_of(Placement.Kind.SENSOR), 5, "stage 4: sensor placed (4 + 1)")
    _drop(s4)
    var s5: Node2D = _new_scene(tree, "5")
    _tap(s5, KEY_1)
    t.check(s5._last_notice.find("WP-003") >= 0, "stage 5: free construction refused by the WP-003 rule (%s)" % s5._last_notice)
    _click(s5, Vector2i(40, 20))
    t.eq(s5.battle.placement.structures.size(), 18, "stage 5: nothing placed")
    _drop(s5)


func _scene_switching(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: `]` / `[` switch the stage in place at the next frame; bounds say what comes next")
    var scene: Node2D = _new_scene(tree, "2")
    _click(scene, TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    _frame(scene, 30)
    _tap(scene, KEY_BRACKETRIGHT)
    t.eq(scene._stage, 2, "switch waits for the frame")
    _frame(scene)
    t.eq(scene._stage, 3, "`]` -> stage 3")
    t.eq(scene.battle.placement.count_of(Placement.Kind.HWACHA), 4, "stage 3 fixture after the switch")
    t.eq(scene.battle.placement.count_of(Placement.Kind.JANGSEUNG), 0, "the stage-2 jangseung is gone (fresh stage)")
    t.eq(scene.battle.steps, 1, "fresh run: one tick in the switching frame")
    t.eq(scene._mouse_down, false, "no held input carried over")
    _tap(scene, KEY_PAGEUP)
    _frame(scene)
    t.eq(scene._stage, 2, "PageUp -> stage 2")
    _tap(scene, KEY_BRACKETLEFT)
    _frame(scene)
    t.eq(scene._stage, 1, "`[` -> stage 1")
    _tap(scene, KEY_BRACKETLEFT)
    _frame(scene)
    t.eq(scene._stage, 1, "no stage 0")
    t.check(scene._last_notice.find("첫 단계") >= 0, "says it is the first stage")
    scene._enter_stage(8)
    t.eq(scene.flow.state_name(), "TITLE", "stage 8 on TITLE")
    _tap(scene, KEY_BRACKETRIGHT)
    _frame(scene)
    t.eq(scene._stage, 8, "no stage 9")
    t.check(scene._last_notice.find("WP-009") >= 0, "says stage 9 is WP-009 (%s)" % scene._last_notice)
    _tap(scene, KEY_BRACKETLEFT)
    _frame(scene)
    t.eq(scene._stage, 7, "`[` works over the title screen too")
    t.eq(scene.battle.play_mode, "classic", "stage 7 is classic")
    t.eq(scene.config.get_num("outer_hp"), 360.0, "stage 7 outer HP back to 360 (stage 6's 40 does not leak)")
    _drop(scene)


func _scene_loop_and_build(t: RefCounted, tree: SceneTree) -> void:
    t.case("scene: stage 7 = title -> run -> result -> R restart; stage 8 = title -> preparing -> 방어 시작")
    var s7: Node2D = _new_scene(tree, "7")
    s7.menu.button("title_start").pressed.emit()
    _frame(s7)
    t.eq(s7.flow.state_name(), "PLAYING", "stage 7: 게임 시작 -> PLAYING")
    var rid: int = s7.battle.run.run_id
    s7.battle.force_outer_hp(1.0, "stage test forced collapse")
    s7.battle.spawn_extra(OUTER_GOAL, 1, "stage test trigger")
    var k: int = 0
    while s7.battle.run.collapse_count == 0 and k < 300:
        _frame(s7)
        k += 1
    s7.battle.force_core_hp(1.0, "stage test forced LOST")
    s7.battle.spawn_extra(CORE_GOAL, 1, "stage test last arrival")
    k = 0
    while s7.flow.state != PlayFlow.State.RESULT and k < 300:
        _frame(s7)
        k += 1
    t.eq(s7.flow.state_name(), "RESULT", "stage 7: the run ends on the result screen")
    _tap(s7, KEY_R)
    _frame(s7)
    t.eq(s7.flow.state_name(), "PLAYING", "stage 7: R restarts at once")
    t.eq(s7.battle.run.run_id, rid + 1, "stage 7: new run id")
    _drop(s7)
    var s8: Node2D = _new_scene(tree, "8")
    t.eq(s8.flow.build_mode, true, "stage 8: build flow")
    s8.menu.button("title_start").pressed.emit()
    _frame(s8)
    t.eq(s8.flow.state_name(), "PREPARING", "stage 8: 게임 시작 -> PREPARING")
    t.eq(s8._build_bar.visible, true, "stage 8: construction bar")
    _frame(s8, 60)
    t.eq(s8.battle.steps, 0, "stage 8: preparing does not tick")
    s8._build_buttons["begin_defense"].pressed.emit()
    _frame(s8)
    t.eq(s8.flow.state_name(), "PLAYING", "stage 8: 방어 시작 -> PLAYING")
    _drop(s8)
