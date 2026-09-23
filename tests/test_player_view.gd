extends RefCounted
## WP-005 V-01 (D-053, docs/art/WP005_VISUAL_REVISION_PLAN.md): the default
## display of a normal launch. The player view collapses the developer
## overlays and panels, puts wave / HP / recovery first and shortens the
## structure names; scripted modes keep the developer view; every toggle still
## works; the battle is never touched.

const Main := preload("res://game/scenes/main.gd")
const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const PlayFlow := preload("res://game/core/play_flow.gd")
const OverlayLayer := preload("res://game/scenes/overlay_layer.gd")
const PerfRecorder := preload("res://game/tools/perf_recorder.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SETTINGS_TMP: String = "user://v01_test_settings.cfg"
const DT: float = 0.0166666667


func run(t: RefCounted) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    _defaults(t, tree)
    _hud_text(t, tree)
    _toggles(t, tree)
    _labels(t)
    _battle_untouched(t, tree)
    _capture_hold(t, tree)
    if FileAccess.file_exists(SETTINGS_TMP):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TMP))


static func _scene(tree: SceneTree, view: String = "", capture: String = "") -> Node2D:
    var scene: Node2D = Main.new()
    scene._settings_path = SETTINGS_TMP
    scene._art_mode = "greybox"
    scene._view_arg = view
    scene._capture_name = capture
    if capture != "":
        scene._capture_dir = "user://"
    tree.root.add_child(scene)
    if not scene.is_node_ready():
        scene._ready()
    scene.set_process(false)
    scene.set_physics_process(false)
    return scene


static func _drop(scene: Node2D) -> void:
    scene._capture_name = ""
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


static func _start(scene: Node2D) -> void:
    scene.menu.button("title_start").pressed.emit()
    _frame(scene)


func _defaults(t: RefCounted, tree: SceneTree) -> void:
    t.case("V-01 defaults: a normal launch is the player view; --perf / --capture / --view=dev keep the developer view")
    var play: Node2D = _scene(tree)
    t.eq(play._player_view, true, "normal launch: player view")
    t.eq(play._show_zones, false, "density zones collapsed")
    t.eq(play._show_ranges, false, "range rings collapsed")
    t.eq(play._show_detail, false, "detail panel collapsed")
    t.eq(play._detail.visible, false, "detail label hidden")
    t.eq(play._hud_bottom.visible, false, "empty bottom panel hidden")
    t.eq(play._overlay.debug_labels, false, "short structure names")
    _drop(play)
    var dev: Node2D = _scene(tree, "dev")
    t.eq(dev._player_view, false, "--view=dev: developer view")
    t.eq(dev._show_zones and dev._show_ranges and dev._show_detail, true, "--view=dev: overlays and detail as before")
    _drop(dev)
    var cap: Node2D = _scene(tree, "", "wp005_assets")
    t.eq(cap._player_view, false, "--capture keeps the developer view (existing evidence reproducible)")
    t.eq(cap._show_zones, true, "capture: zones as before")
    _drop(cap)
    var cap_p: Node2D = _scene(tree, "player", "wp005_assets")
    t.eq(cap_p._player_view, true, "--view=player applies to a capture too")
    _drop(cap_p)
    var perf: Node2D = Main.new()
    perf._settings_path = SETTINGS_TMP
    perf._art_mode = "greybox"
    perf._perf = PerfRecorder.new()
    perf._perf_scenario = "collapse_move"
    tree.root.add_child(perf)
    if not perf.is_node_ready():
        perf._ready()
    perf.set_process(false)
    perf.set_physics_process(false)
    t.eq(perf._player_view, false, "--perf keeps the developer view")
    perf._perf = null
    _drop(perf)


func _hud_text(t: RefCounted, tree: SceneTree) -> void:
    t.case("V-01 HUD: wave / HP / recovery first in the top panel, the developer lines move to the detail panel")
    var s: Node2D = _scene(tree)
    _start(s)
    _frame(s, 60)
    s._update_hud()
    var top: String = s._hud.text
    t.check(top.begins_with("웨이브 1/3"), "first line is the wave (%s)" % top.get_slice("\n", 0))
    t.check(top.find("외곽 거점 HP") >= 0 and top.find("핵심 시설 HP") >= 0, "both objectives' HP")
    t.check(top.find("무너지면 화차·중영 1대를 회수") >= 0, "what happens at the collapse")
    t.check(top.find("Godot") < 0 and top.find("FPS") < 0 and top.find("생성 누계") < 0, "no engine / FPS / counters in the top panel")
    t.eq(top.split("\n").size(), 4, "four lines (the developer HUD had 7+)")
    t.check(s._detail.text.find("Godot") >= 0 and s._detail.text.find("FPS") >= 0, "engine and FPS moved to the detail panel")
    t.check(s._detail.text.find("공유전용 사격") >= 0, "network counters kept in the detail panel")
    # after the collapse the recovery instruction replaces the explanation
    s.battle.force_outer_hp(1.0, "V-01 test forced collapse")
    s.battle.spawn_extra(Vector2(950.0, 530.0), 1, "V-01 test trigger")
    var k: int = 0
    while s.battle.run.collapse_count == 0 and k < 300:
        _frame(s)
        k += 1
    s._update_hud()
    t.check(s._hud.text.find("▶ 외곽 붕괴!") >= 0, "collapse: recovery instruction shown")
    t.check(s._hud.text.find("외곽 붕괴 — 내곽 방어") >= 0, "collapse: defence state in the first line")
    _drop(s)
    var d: Node2D = _scene(tree, "dev")
    _start(d)
    d._update_hud()
    t.check(d._hud.text.find("Godot") >= 0, "developer view: HUD unchanged (engine line in the top panel)")
    _drop(d)


func _toggles(t: RefCounted, tree: SceneTree) -> void:
    t.case("V-01 toggles: Z / G / D / L / H still reach every developer display from the player view")
    var s: Node2D = _scene(tree)
    _start(s)
    _tap(s, KEY_Z)
    t.eq(s._show_zones, true, "Z shows the zones")
    _tap(s, KEY_G)
    t.eq(s._show_ranges, true, "G shows the rings")
    _tap(s, KEY_D)
    t.eq(s._show_detail, true, "D opens the detail panel")
    t.eq(s._hud_bottom.visible, true, "bottom panel shown with the detail")
    s._process(DT)
    t.eq(s._overlay.debug_labels, true, "detail on -> developer labels")
    _tap(s, KEY_D)
    s._process(DT)
    t.eq(s._overlay.debug_labels, false, "detail off -> short names again")
    t.eq(s._hud_bottom.visible, false, "bottom panel hidden again")
    s._say("테스트 알림")
    t.eq(s._hud_bottom.visible, true, "a notice shows the bottom panel")
    _tap(s, KEY_L)
    t.eq(s._show_labels, false, "L hides the names")
    _tap(s, KEY_H)
    t.eq(s._hud_layer.visible, false, "H hides the HUD")
    _tap(s, KEY_ESCAPE)
    _frame(s)
    t.eq(s.flow.state_name(), "PAUSED", "Esc still pauses")
    _drop(s)


func _labels(t: RefCounted) -> void:
    t.case("V-01 labels: short names in the player view, the developer text unchanged")
    var b: Battle = Battle.new(Config.for_wp003())
    var hw: Placement.Structure = b.placement.hwachas()[3]
    var bs: Placement.Structure = b.placement.bongsus()[1]
    var sn: Placement.Structure = b.placement.sensors()[0]
    t.eq(OverlayLayer.structure_label(hw, false, "wp002"), hw.label, "hwacha player label = name")
    t.eq(OverlayLayer.structure_label(hw, true, "wp002"), hw.label + " g%d L%d/S%d" % [hw.group_id, hw.known_local, hw.known_shared], "hwacha developer label unchanged")
    t.eq(OverlayLayer.structure_label(bs, false, "wp002"), bs.label, "bongsu player label = name")
    t.eq(OverlayLayer.structure_label(bs, true, "wp002"), "%s g%d" % [bs.label, bs.group_id], "bongsu developer label unchanged")
    t.eq(OverlayLayer.structure_label(sn, false, "wp002"), sn.label, "sensor player label = name")
    t.eq(OverlayLayer.structure_label(hw, true, "wp001"), hw.label, "wp001 mode: name only (as before)")


func _battle_untouched(t: RefCounted, tree: SceneTree) -> void:
    t.case("V-01 is display only: player and developer views run the same battle to the same state")
    var states: Array = []
    for view: String in ["player", "dev"]:
        var s: Node2D = _scene(tree, view)
        _start(s)
        _frame(s, 600)
        states.append(s.battle.full_state_json())
        _drop(s)
    t.eq(states[0], states[1], "player view == developer view after 600 frames")


func _capture_hold(t: RefCounted, tree: SceneTree) -> void:
    t.case("capture hold: the battle does not advance while the same tick is captured in several views")
    var s: Node2D = _scene(tree, "", "wp005_v01")
    s._capture_steps = [{"t": 0.0, "do": "hold", "on": true}, {"t": 0.0, "do": "view", "player": true}]
    s._capture_index = 0
    _frame(s)
    var steps0: int = s.battle.steps
    _frame(s, 30)
    t.eq(s.battle.steps, steps0, "no tick while held")
    t.eq(s._player_view, true, "view switched while held")
    s._capture_hold = false
    _frame(s, 2)
    t.check(s.battle.steps > steps0, "ticks resume after the hold")
    _drop(s)
