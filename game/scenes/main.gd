extends Node2D
## WP-001 playable prototype: rendering, input, debug overlay, and the scripted
## perf / capture modes. All game rules live in game/core; this file only reads
## state and forwards commands.
##
## Interactive controls
##   LMB (hold)  place at the cursor, retrying every tick while held
##   RMB         remove the structure under the cursor
##   1 / 2       placement mode: 장승 (blocks) / 화차 (fires)
##   C           toggle combat (hwachas hold fire when off)
##   Z           toggle density zone overlay
##   G           toggle hwacha range rings
##   P           pause / resume the simulation
##   R           reset the run (same seed)
##   H           toggle HUD
##   F12         save a screenshot next to the project (user://captures)
##   Esc         quit
##
## Command line (after `--`):
##   --set key=value       override any config value (see game/core/config.gd)
##   --config=path.json    merge a JSON config file
##   --speed=N             simulation steps per physics tick (default 1)
##   --quit-after=SEC      quit after SEC seconds of simulated time
##   --perf --scenario=move|combat [--warmup=10] [--measure=60] --out=path.json
##   --capture=ac01|ac02|ac06 --out-dir=dir   scripted evidence captures

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const Hwacha := preload("res://game/core/hwacha.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const TerrainLayer := preload("res://game/scenes/terrain_layer.gd")
const OverlayLayer := preload("res://game/scenes/overlay_layer.gd")
const PerfRecorder := preload("res://game/tools/perf_recorder.gd")

const COLOR_TEXT: Color = Color(0.92, 0.90, 0.85)

var battle: Battle = null
var config: Config = null

var _terrain: TerrainLayer = null
var _overlay: OverlayLayer = null
var _enemies: MultiMeshInstance2D = null
var _multimesh: MultiMesh = null
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _hud_layer: CanvasLayer = null
var _hud: Label = null
var _hud_bg: ColorRect = null
var _notice: Label = null
var _font: Font = null

var _place_mode: int = Placement.Kind.JANGSEUNG
var _paused: bool = false
var _show_zones: bool = true
var _show_ranges: bool = true
var _show_hud: bool = true
var _mouse_down: bool = false
var _sim_speed: int = 1
var _quit_after: float = -1.0
var _last_notice: String = ""
var _notice_timer: float = 0.0
var _recent_shots: Array = []      # [aim, radius, age]
var _fps_smoothed: float = 0.0
var _frame_ms_smoothed: float = 0.0
var _hud_tick: int = 0

# --- perf mode ---
var _perf: PerfRecorder = null
var _perf_out: String = ""
var _perf_scenario: String = ""
var _perf_next_toggle: float = 0.0
var _perf_jangseung_id: int = -1
var _perf_place_pending: bool = false
var _perf_rebuilds: int = 0
var _perf_refusals: int = 0

# --- capture mode ---
var _capture_name: String = ""
var _capture_dir: String = ""
var _capture_steps: Array = []
var _capture_index: int = 0
var _capture_busy: bool = false
var _capture_log: Array = []


# =============================================================== lifecycle ===

func _ready() -> void:
    config = Config.new()
    _parse_args()
    battle = Battle.new(config)
    _build_scene()
    _apply_run_mode()


func _parse_args() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--set"):
            var kv: String = arg.substr(5).strip_edges().trim_prefix("=")
            var parts: PackedStringArray = kv.split("=", true, 1)
            if parts.size() == 2 and not config.set_value(parts[0], parts[1]):
                printerr("unknown config key: %s" % parts[0])
        elif arg.begins_with("--config="):
            if not config.merge_json(arg.substr("--config=".length())):
                printerr("could not load config: %s" % arg)
        elif arg.begins_with("--speed="):
            _sim_speed = maxi(1, int(arg.substr("--speed=".length())))
        elif arg.begins_with("--quit-after="):
            _quit_after = float(arg.substr("--quit-after=".length()))
        elif arg == "--perf":
            _perf = PerfRecorder.new()
        elif arg.begins_with("--scenario="):
            _perf_scenario = arg.substr("--scenario=".length())
        elif arg.begins_with("--warmup="):
            if _perf == null:
                _perf = PerfRecorder.new()
            _perf.warmup_seconds = float(arg.substr("--warmup=".length()))
        elif arg.begins_with("--measure="):
            if _perf == null:
                _perf = PerfRecorder.new()
            _perf.measure_seconds = float(arg.substr("--measure=".length()))
        elif arg.begins_with("--out="):
            _perf_out = arg.substr("--out=".length())
        elif arg.begins_with("--capture="):
            _capture_name = arg.substr("--capture=".length())
        elif arg.begins_with("--out-dir="):
            _capture_dir = arg.substr("--out-dir=".length())


func _build_scene() -> void:
    _font = ThemeDB.fallback_font

    _terrain = TerrainLayer.new()
    _terrain.name = "Terrain"
    add_child(_terrain)
    _terrain.setup(battle.grid, battle.grid.index_center(battle.path.goal_index),
        config.get_num("goal_radius"))

    _enemies = MultiMeshInstance2D.new()
    _enemies.name = "Enemies"
    _multimesh = MultiMesh.new()
    _multimesh.transform_format = MultiMesh.TRANSFORM_2D
    _multimesh.use_colors = true
    var quad: QuadMesh = QuadMesh.new()
    var size: float = config.get_num("enemy_draw_size")
    quad.size = Vector2(size, size)
    _multimesh.mesh = quad
    _multimesh.instance_count = battle.sim.capacity
    _multimesh.visible_instance_count = 0
    _buffer.resize(battle.sim.capacity * 12)
    _enemies.multimesh = _multimesh
    add_child(_enemies)

    _overlay = OverlayLayer.new()
    _overlay.name = "Overlay"
    _overlay.battle = battle
    _overlay.font = _font
    add_child(_overlay)

    _hud_layer = CanvasLayer.new()
    _hud_layer.name = "HUD"
    add_child(_hud_layer)

    _hud_bg = ColorRect.new()
    _hud_bg.color = Color(0.0, 0.0, 0.0, 0.55)
    _hud_bg.position = Vector2(8.0, 8.0)
    _hud_bg.size = Vector2(980.0, 215.0)
    _hud_layer.add_child(_hud_bg)

    _hud = Label.new()
    _hud.position = Vector2(16.0, 12.0)
    _hud.add_theme_font_size_override("font_size", 16)
    _hud.add_theme_color_override("font_color", COLOR_TEXT)
    _hud_layer.add_child(_hud)

    _notice = Label.new()
    _notice.position = Vector2(16.0, 1040.0)
    _notice.add_theme_font_size_override("font_size", 18)
    _notice.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    _hud_layer.add_child(_notice)


func _apply_run_mode() -> void:
    var title: String = "Hanyang Defense WP-001"
    if _perf != null:
        _perf.scenario = _perf_scenario if _perf_scenario != "" else "move"
        config.values["combat_enabled"] = _perf.scenario != "move"
        battle.combat_enabled = config.get_bool("combat_enabled")
        # R-02: hold the D-009 load (alive >= target) for every measured frame.
        config.values["benchmark_hold_alive"] = true
        battle.benchmark_hold_alive = true
        _perf_next_toggle = _perf.warmup_seconds
        DisplayServer.window_set_size(Vector2i(1920, 1080))
        DisplayServer.window_set_position(Vector2i(0, 0))
        title += " [perf:%s]" % _perf.scenario
        _overlay.show_cursor = false
        _perf.start()
        print("perf: scenario=%s warmup=%.0fs measure=%.0fs" % [
            _perf.scenario, _perf.warmup_seconds, _perf.measure_seconds
        ])
    elif _capture_name != "":
        DisplayServer.window_set_size(Vector2i(1920, 1080))
        DisplayServer.window_set_position(Vector2i(0, 0))
        _sim_speed = maxi(_sim_speed, 6)
        _overlay.show_cursor = false
        _setup_capture_steps()
        title += " [capture:%s]" % _capture_name
    DisplayServer.window_set_title(title)


# ================================================================== loop ===

func _physics_process(delta: float) -> void:
    if _capture_busy:
        return
    if not _paused:
        var dt: float = config.get_num("fixed_dt")
        for _i: int in range(_sim_speed):
            battle.step(dt)
            _perf_script_step()
            _capture_script_step()
            if _capture_busy:
                break
    if _mouse_down:
        _try_place_at_cursor()
    if _notice_timer > 0.0:
        _notice_timer -= delta
        if _notice_timer <= 0.0:
            _notice.text = ""
    if _quit_after >= 0.0 and battle.sim_time >= _quit_after:
        get_tree().quit()


func _process(delta: float) -> void:
    if delta > 0.0:
        var fps: float = 1.0 / delta
        _fps_smoothed = fps if _fps_smoothed == 0.0 else lerpf(_fps_smoothed, fps, 0.08)
        _frame_ms_smoothed = lerpf(_frame_ms_smoothed, delta * 1000.0, 0.08)
    _upload_enemies()
    for shot: Array in battle.hwacha.last_shots_for_render():
        _recent_shots.append([shot[0], shot[1], 0.0])
    var i: int = 0
    while i < _recent_shots.size():
        _recent_shots[i][2] += delta
        if _recent_shots[i][2] > 0.35:
            _recent_shots.remove_at(i)
        else:
            i += 1
    _hud_tick += 1
    if _hud_tick % 6 == 0:
        _update_hud()
    _overlay.recent_shots = _recent_shots
    _overlay.show_zones = _show_zones
    _overlay.show_ranges = _show_ranges
    _overlay.place_mode = _place_mode
    _overlay.queue_redraw()
    if _perf != null:
        _perf.tick(battle.sim.alive_count)
        if _perf.is_done():
            _finish_perf()


func _upload_enemies() -> void:
    var sim := battle.sim
    var live: PackedInt32Array = sim.live_slots()
    var n: int = live.size()
    var px: PackedFloat32Array = sim.pos_x
    var py: PackedFloat32Array = sim.pos_y
    var rt: PackedInt32Array = sim.route
    var colors: Array[Color] = TestMap.ROUTE_COLORS
    var o: int = 0
    for k: int in range(n):
        var s: int = live[k]
        var c: Color = colors[rt[s]]
        _buffer[o] = 1.0
        _buffer[o + 1] = 0.0
        _buffer[o + 2] = 0.0
        _buffer[o + 3] = px[s]
        _buffer[o + 4] = 0.0
        _buffer[o + 5] = 1.0
        _buffer[o + 6] = 0.0
        _buffer[o + 7] = py[s]
        _buffer[o + 8] = c.r
        _buffer[o + 9] = c.g
        _buffer[o + 10] = c.b
        _buffer[o + 11] = 1.0
        o += 12
    _multimesh.visible_instance_count = n
    _multimesh.buffer = _buffer


# ================================================================= input ===

func _unhandled_input(event: InputEvent) -> void:
    if _perf != null or _capture_name != "":
        # Scripted evidence runs must not be perturbed by stray clicks or keys
        # on the foreground window; only Esc is honoured.
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
            get_tree().quit()
        return
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index == MOUSE_BUTTON_LEFT:
            _mouse_down = mb.pressed
            if mb.pressed:
                _try_place_at_cursor()
        elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            var res: Placement.Result = battle.remove_at_world(get_global_mouse_position())
            if res.ok:
                _say("제거: %s #%d  (경로 버전 %d)" % [res.structure.label, res.structure.id, battle.path.path_version])
            else:
                _say("제거 실패: 커서 아래 시설 없음")
    elif event is InputEventKey and event.pressed and not event.echo:
        var key: InputEventKey = event
        match key.keycode:
            KEY_1:
                _place_mode = Placement.Kind.JANGSEUNG
                _say("설치 모드: 장승 (통행 차단)")
            KEY_2:
                _place_mode = Placement.Kind.HWACHA
                _say("설치 모드: 화차 (광역 사격, 통행 비차단)")
            KEY_C:
                battle.combat_enabled = not battle.combat_enabled
                _say("전투 %s" % ("활성" if battle.combat_enabled else "비활성 (처치 끔)"))
            KEY_Z:
                _show_zones = not _show_zones
            KEY_G:
                _show_ranges = not _show_ranges
            KEY_P:
                _paused = not _paused
                _say("일시정지" if _paused else "재개")
            KEY_R:
                battle.reset()
                _recent_shots.clear()
                _say("초기화 (seed %d)" % config.get_int("seed"))
            KEY_H:
                _show_hud = not _show_hud
                _hud_layer.visible = _show_hud
            KEY_F12:
                _screenshot_to_user()
            KEY_ESCAPE:
                get_tree().quit()


func _try_place_at_cursor() -> void:
    var anchor: Vector2i = battle.placement.anchor_for_world(get_global_mouse_position())
    var res: Placement.Result
    if _place_mode == Placement.Kind.JANGSEUNG:
        res = battle.place_jangseung(anchor)
    else:
        res = battle.place_hwacha(anchor)
    if res.ok:
        _mouse_down = false  # one placement per press
        _say("설치: %s #%d @%s  (경로 버전 %d)" % [
            res.structure.label, res.structure.id, str(anchor), battle.path.path_version
        ])
    else:
        _say("거절: %s @%s" % [Placement.reject_name(res.reason), str(anchor)])


func _say(msg: String) -> void:
    _last_notice = msg
    _notice.text = msg
    _notice_timer = 3.0


# =================================================================== hud ===

func _update_hud() -> void:
    if not _show_hud:
        return
    var sim := battle.sim
    var lines: PackedStringArray = PackedStringArray()
    lines.append("한양 디펜스 · WP-001 적 흐름 프로토타입   Godot %s / %s" % [
        Engine.get_version_info().string, RenderingServer.get_current_rendering_method()
    ])
    lines.append("FPS %3.0f  frame %.1f ms   sim t=%.1fs  x%d%s%s" % [
        _fps_smoothed, _frame_ms_smoothed, battle.sim_time, _sim_speed,
        "  [일시정지]" if _paused else "", "" if battle.combat_enabled else "  [전투 비활성]"
    ])
    lines.append("동시 생존 %d (최고 %d)   생성 누계 %d   처치 %d   누수 %d" % [
        sim.alive_count, battle.peak_alive, sim.spawned_total, sim.killed_total, sim.leaked_total
    ])
    lines.append("경로별 생존: %s   경로 버전 %d" % [battle.route_summary(), battle.path.path_version])
    var zparts: PackedStringArray = PackedStringArray()
    for z: DensityDetector.Zone in battle.density.zones:
        zparts.append("Z%d %d" % [z.id, battle.density.counts[z.id]])
    lines.append("밀도: " + "  ".join(zparts))
    var hparts: PackedStringArray = PackedStringArray()
    for s: Placement.Structure in battle.placement.hwachas():
        hparts.append("%s→%s %d발/%d처치" % [
            s.label, ("Z%d" % s.last_zone) if s.last_zone >= 0 else "--", s.shots_fired, s.kills
        ])
    lines.append("화차: " + "   ".join(hparts))
    lines.append("장승 %d   화차 %d   거절 누계 %d   설치 모드 [%s]" % [
        battle.placement.count_of(Placement.Kind.JANGSEUNG),
        battle.placement.count_of(Placement.Kind.HWACHA),
        battle.placement.rejected_total,
        "1 장승" if _place_mode == Placement.Kind.JANGSEUNG else "2 화차"
    ])
    lines.append("LMB 설치  RMB 제거  1/2 모드  C 전투  Z 밀도  G 사거리  P 정지  R 초기화  H HUD  F12 캡처  Esc 종료")
    _hud.text = "\n".join(lines)


# ================================================================== perf ===

func _perf_script_step() -> void:
    if _perf == null or _perf.scenario != "combat":
        return
    # Combat scenario: every 10 s of wall time after warmup, tear the west-lane
    # jangseung down and put it back 1.5 s later (retrying while the lane is
    # occupied). Each accepted change rebuilds the path field.
    var t: float = _perf.elapsed_in_phase() + (0.0 if _perf.phase() == "warmup" else _perf.warmup_seconds)
    if _perf_place_pending:
        var res: Placement.Result = battle.place_jangseung(TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
        if res.ok:
            _perf_jangseung_id = res.structure.id
            _perf_place_pending = false
            _perf_rebuilds += 1
        else:
            _perf_refusals += 1
        return
    if t >= _perf_next_toggle:
        _perf_next_toggle += 10.0
        if _perf_jangseung_id >= 0:
            battle.placement.remove(_perf_jangseung_id)
            _perf_jangseung_id = -1
            _perf_rebuilds += 1
            _perf_place_pending = false
            _perf_next_toggle = t + 1.5   # re-place shortly, then resume the 10 s cadence
        else:
            _perf_place_pending = true
            _perf_next_toggle = t + 8.5


func _finish_perf() -> void:
    _perf.extra = {
        "target_alive": config.get_int("target_alive"),
        "benchmark_hold_alive": battle.benchmark_hold_alive,
        "spawn_rate": config.get_num("spawn_rate"),
        "cmdline_user_args": OS.get_cmdline_user_args(),
        "seed": config.get_int("seed"),
        "combat_enabled": battle.combat_enabled,
        "sim_time_at_end": battle.sim_time,
        "spawned_total": battle.sim.spawned_total,
        "killed_total": battle.sim.killed_total,
        "leaked_total": battle.sim.leaked_total,
        "shots_total": battle.hwacha.shots_total,
        "path_rebuilds_scripted": _perf_rebuilds,
        "placement_refusals_scripted": _perf_refusals,
        "path_version": battle.path.path_version,
        # path_version must equal 2 + path_rebuilds_scripted; anything else
        # means an unscripted rebuild happened during the run.
        "path_version_expected": 2 + _perf_rebuilds,
        "jangseung_count_at_end": battle.placement.count_of(Placement.Kind.JANGSEUNG),
        "hwacha_count_at_end": battle.placement.count_of(Placement.Kind.HWACHA),
        "placement_rejected_total": battle.placement.rejected_total,
        "interactive_input_ignored": true,
        "screen_size": str(DisplayServer.screen_get_size()),
    }
    var report: Dictionary = _perf.report()
    var text: String = JSON.stringify(report, "  ")
    if _perf_out != "":
        var f: FileAccess = FileAccess.open(_perf_out, FileAccess.WRITE)
        if f != null:
            f.store_string(text)
            f.close()
            print("perf report written: %s" % _perf_out)
        else:
            printerr("perf: could not write %s (%s)" % [_perf_out, error_string(FileAccess.get_open_error())])
    print("PERF %s: frames=%d avg_fps=%.1f p95=%.2fms p99=%.2fms max=%.2fms alive avg=%.0f min=%d mem=%.1f->%.1f MB" % [
        report["scenario"], report["frames"], report["avg_fps"], report["frame_ms_p95"],
        report["frame_ms_p99"], report["frame_ms_max"], report["alive_avg"], report["alive_min"],
        report["memory_static_mb_start"], report["memory_static_mb_end"]
    ])
    _perf = null
    get_tree().quit()


# =============================================================== capture ===

func _setup_capture_steps() -> void:
    var west: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_west_lane"]
    match _capture_name:
        "ac01":
            config.values["combat_enabled"] = false
            battle.combat_enabled = false
            _capture_steps = [
                {"t": 30.0, "do": "capture", "name": "ac01_t30_1000_alive_three_routes"},
                {"t": 30.0, "do": "quit"},
            ]
        "ac02":
            config.values["combat_enabled"] = false
            battle.combat_enabled = false
            _capture_steps = [
                {"t": 30.0, "do": "capture", "name": "ac02_a_reference_t30"},
                {"t": 30.0, "do": "reset"},
                {"t": 0.0, "do": "place", "anchor": west},
                {"t": 30.0, "do": "capture", "name": "ac02_b_west_lane_blocked_t30"},
                {"t": 30.0, "do": "remove_all_jangseung"},
                {"t": 42.0, "do": "capture", "name": "ac02_c_restored_t42"},
                {"t": 42.0, "do": "quit"},
            ]
        "ac06":
            config.values["combat_enabled"] = true
            battle.combat_enabled = true
            _capture_steps = [
                {"t": 35.0, "do": "capture", "name": "ac06_a_before_t35"},
                {"t": 35.0, "do": "reset"},
                {"t": 0.0, "do": "place", "anchor": west},
                {"t": 35.0, "do": "capture", "name": "ac06_b_after_t35"},
                {"t": 35.0, "do": "quit"},
            ]
        _:
            printerr("unknown capture scenario: %s" % _capture_name)
            get_tree().quit()


func _capture_script_step() -> void:
    if _capture_name == "" or _capture_busy:
        return
    while _capture_index < _capture_steps.size():
        var step: Dictionary = _capture_steps[_capture_index]
        if battle.sim_time + 1e-6 < float(step["t"]):
            return
        _capture_index += 1
        match step["do"]:
            "capture":
                _capture_busy = true
                _do_capture(step["name"])
                return
            "reset":
                battle.reset()
                _recent_shots.clear()
            "place":
                var res: Placement.Result = battle.place_jangseung(step["anchor"])
                _capture_log.append({"t": battle.sim_time, "place": str(step["anchor"]),
                    "ok": res.ok, "reason": Placement.reject_name(res.reason)})
            "remove_all_jangseung":
                for s: Placement.Structure in battle.placement.jangseungs():
                    battle.placement.remove(s.id)
                _capture_log.append({"t": battle.sim_time, "remove_all_jangseung": true})
            "quit":
                _write_capture_log()
                get_tree().quit()
                return


func _do_capture(name: String) -> void:
    _upload_enemies()
    _update_hud()
    _overlay.recent_shots = _recent_shots
    _overlay.queue_redraw()
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var img: Image = get_viewport().get_texture().get_image()
    var path: String = _capture_dir.path_join(name + ".png")
    var err: int = img.save_png(path)
    var snap: Dictionary = battle.snapshot()
    snap["capture"] = name
    snap["png"] = path
    snap["png_saved"] = err == OK
    _capture_log.append(snap)
    print("capture %s -> %s (%s)" % [name, path, error_string(err)])
    _capture_busy = false


func _write_capture_log() -> void:
    var path: String = _capture_dir.path_join("%s_log.json" % _capture_name)
    var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(_capture_log, "  "))
        f.close()
        print("capture log written: %s" % path)


func _screenshot_to_user() -> void:
    var dir: String = OS.get_user_data_dir().path_join("captures")
    DirAccess.make_dir_recursive_absolute(dir)
    var path: String = dir.path_join("shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
    await RenderingServer.frame_post_draw
    var img: Image = get_viewport().get_texture().get_image()
    var err: int = img.save_png(path)
    _say("캡처 %s: %s" % ["저장" if err == OK else "실패", path])
