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
    # Interactive play defaults to the WP-003 run (READY v1.0). Scripted WP-001/002
    # scenarios pin their own presets in _apply_run_mode; --set overrides here.
    config = Config.for_wp003()
    _parse_args()
    battle = Battle.new(config)
    _build_scene()
    _apply_run_mode()


var _explicit_sets: Dictionary = {}

## Every key that selects a game mode. A scripted scenario must reapply ALL of
## them from its own preset (Codex review on PR #4: the legacy WP-001/002
## scenarios had inherited run_mode="waves" & co. from the WP-003 default).
const MODE_KEYS: Array[String] = [
    "targeting_mode", "fixture", "zone_set", "arrival_mode", "run_mode", "district_rules",
    "outer_hp", "core_hp", "arrival_damage", "wave_gap_seconds", "benchmark_core_invulnerable",
]


## Copy the mode keys from `src` into the live config, except keys the user
## pinned explicitly with --set.
func _apply_mode_preset(src: Config) -> void:
    for k: String in MODE_KEYS:
        if not _explicit_sets.has(k):
            config.values[k] = src.values[k]


func _parse_args() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--set"):
            var kv: String = arg.substr(5).strip_edges().trim_prefix("=")
            var parts: PackedStringArray = kv.split("=", true, 1)
            if parts.size() == 2 and not config.set_value(parts[0], parts[1]):
                printerr("unknown config key: %s" % parts[0])
            elif parts.size() == 2:
                _explicit_sets[parts[0]] = true
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
        elif arg.begins_with("--sha="):
            _build_sha = arg.substr("--sha=".length())
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
    _sync_terrain_marker()

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
    _hud_bg.size = Vector2(1280.0, 340.0 if battle.run_mode == "waves" else 262.0)
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


## The static terrain goal marker belongs to the sandbox modes only; in the
## WP-003 run the overlay draws both objectives with their live state.
func _sync_terrain_marker() -> void:
    var show: bool = battle.run_mode != "waves"
    if _terrain.show_goal_marker != show:
        _terrain.show_goal_marker = show
        _terrain.queue_redraw()


func _apply_run_mode() -> void:
    var title: String = "Hanyang Defense WP-002"
    if _perf != null:
        _perf.scenario = _perf_scenario if _perf_scenario != "" else "move"
        config.values["combat_enabled"] = not _perf.scenario.ends_with("move")
        # R-02: hold the D-009 load (alive >= target) for every measured frame.
        config.values["benchmark_hold_alive"] = true
        if _perf.scenario.begins_with("collapse"):
            # WP-003 D-027 transition benchmark: fixture C + 10 zones, waves OFF,
            # 1000 held by top-up, outer HP 1e6 until the scripted trigger,
            # core invulnerable (attempts counted). All of it goes into the manifest.
            # Only the mode keys come from the preset: the benchmark flags set
            # above and the per-scenario combat switch must survive.
            _apply_mode_preset(Config.for_wp003())
            config.values["outer_hp"] = 1000000.0
            config.values["benchmark_core_invulnerable"] = true
        elif _perf.scenario.begins_with("network"):
            # WP-002 sandbox: fixture B, local+shared targeting, immediate arrivals, no strongholds.
            _apply_mode_preset(Config.new())
        else:
            # WP-001 sandbox: global targeting + the four original hwachas.
            _apply_mode_preset(Config.for_wp001())
        battle.reset()
        if _perf.scenario.begins_with("collapse"):
            battle.waves.enabled = false   # finite waves off: the load is the benchmark top-up
        _perf_next_toggle = _perf.warmup_seconds
        _perf_pv_start = battle.path.path_version
        _perf_topology_start = battle.network.topology_version
        DisplayServer.window_set_size(Vector2i(1920, 1080))
        DisplayServer.window_set_position(Vector2i(0, 0))
        title += " [perf:%s]" % _perf.scenario
        _overlay.show_cursor = false
        _perf.start()
        print("perf: scenario=%s warmup=%.0fs measure=%.0fs" % [
            _perf.scenario, _perf.warmup_seconds, _perf.measure_seconds
        ])
    elif _capture_name != "":
        if _capture_name.begins_with("ac0"):
            # WP-001 evidence scenarios keep the approved configuration (all mode keys).
            _apply_mode_preset(Config.for_wp001())
            battle.reset()
        elif _capture_name.begins_with("wp002"):
            _apply_mode_preset(Config.new())
            battle.reset()
        DisplayServer.window_set_size(Vector2i(1920, 1080))
        DisplayServer.window_set_position(Vector2i(0, 0))
        _sim_speed = maxi(_sim_speed, 6)
        _overlay.show_cursor = false
        _setup_capture_steps()
        title += " [capture:%s]" % _capture_name
    DisplayServer.window_set_title(title)
    _sync_terrain_marker()


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
        # Held-click retry dispatches by mode exactly like the initial press
        # (Codex review on PR #4: a refused recovery click must never fall
        # through to free construction in the WP-003 run).
        if battle.run_mode == "waves":
            _try_recovery_at_cursor()
        else:
            _try_place_at_cursor()
    if _notice_timer > 0.0:
        _notice_timer -= delta
        if _notice_timer <= 0.0:
            _notice.text = ""
    # --quit-after: by simulated time, or as soon as a waves run has ended
    # (sim_time freezes after WON/LOST, so waiting for it would hang).
    if _quit_after >= 0.0 and (battle.sim_time >= _quit_after or battle.run.ended()):
        get_tree().quit()


func _process(delta: float) -> void:
    if delta > 0.0:
        var fps: float = 1.0 / delta
        _fps_smoothed = fps if _fps_smoothed == 0.0 else lerpf(_fps_smoothed, fps, 0.08)
        _frame_ms_smoothed = lerpf(_frame_ms_smoothed, delta * 1000.0, 0.08)
    _upload_enemies()
    if _first_shared_shot_time < 0.0 and battle.hwacha.shared_only_shots > 0:
        _first_shared_shot_time = battle.sim_time
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
        var was_measuring: bool = _perf.phase() == "measure"
        _perf.tick(battle.sim.alive_count)
        if was_measuring and _perf.phase() == "measure":
            _col_sample_frame(_perf.last_frame_us)
        if not was_measuring and _perf.phase() == "measure" and _measure_start.is_empty():
            # Snapshot at the start of the measured window, so window deltas
            # can be separated from the warm-up (GPT review R-03).
            _measure_start = {
                "sim_time": battle.sim_time,
                "shots_total": battle.hwacha.shots_total,
                "shared_only_shots": battle.hwacha.shared_only_shots,
                "killed_total": battle.sim.killed_total,
                "spawned_total": battle.sim.spawned_total,
                "candidate_evaluations": battle.hwacha.candidate_evaluations,
                "state": _state_brief(),
            }
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
    var waves_mode: bool = battle.run_mode == "waves"
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index == MOUSE_BUTTON_LEFT:
            _mouse_down = mb.pressed
            if mb.pressed:
                if waves_mode:
                    _try_recovery_at_cursor()
                else:
                    _try_place_at_cursor()
        elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            if waves_mode:
                _say("WP-003 런에서는 시설 철거를 제공하지 않는다 (회수 화차 배치만 가능)")
            else:
                var res: Placement.Result = battle.remove_at_world(get_global_mouse_position())
                if res.ok:
                    _say("제거: %s #%d  (경로 버전 %d)" % [res.structure.label, res.structure.id, battle.path.path_version])
                else:
                    _say("제거 실패: 커서 아래 시설 없음")
    elif event is InputEventKey and event.pressed and not event.echo:
        var key: InputEventKey = event
        if waves_mode and key.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_T, KEY_C]:
            _say("WP-003 런에서는 자유 설치·활성 전환·전투 토글 디버그 명령을 제공하지 않는다")
            return
        match key.keycode:
            KEY_1:
                _place_mode = Placement.Kind.JANGSEUNG
                _say("설치 모드: 장승 (통행 차단)")
            KEY_2:
                _place_mode = Placement.Kind.HWACHA
                _say("설치 모드: 화차 (광역 사격, 통행 비차단)")
            KEY_3:
                _place_mode = Placement.Kind.BONGSU
                _say("설치 모드: 봉수대 (중계 180px, 통행 비차단)")
            KEY_4:
                _place_mode = Placement.Kind.SENSOR
                _say("설치 모드: 혼천의 (탐지 140px, 통행 비차단)")
            KEY_T:
                var st: Placement.Structure = battle.toggle_active_at_world(get_global_mouse_position())
                if st == null:
                    _say("활성 전환 실패: 커서 아래 시설 없음")
                else:
                    _say("%s #%d → %s (그룹 %d, 부착 %d)" % [
                        st.label, st.id, "활성" if st.active else "비활성", st.group_id, st.attached_to
                    ])
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
                if waves_mode:
                    battle.restart()
                    _recent_shots.clear()
                    _say("재시작 (run #%d, seed %d)" % [battle.run.run_id, config.get_int("seed")])
                else:
                    battle.reset()
                    _recent_shots.clear()
                    _say("초기화 (seed %d)" % config.get_int("seed"))
                _sync_terrain_marker()
            KEY_H:
                _show_hud = not _show_hud
                _hud_layer.visible = _show_hud
            KEY_F12:
                _screenshot_to_user()
            KEY_ESCAPE:
                get_tree().quit()


## WP-003: the only player placement is the recovered H1 into the inner district.
func _try_recovery_at_cursor() -> void:
    var anchor: Vector2i = battle.placement.anchor_for_world(get_global_mouse_position())
    var res: Placement.Result = battle.place_recovery(anchor)
    if res.ok:
        _mouse_down = false
        _say("회수 화차 배치: %s #%d @%s  부착 %d · 그룹 %d · 재장전 잔여 %.2fs" % [
            res.structure.label, res.structure.id, str(anchor), res.structure.attached_to,
            res.structure.group_id, res.structure.cooldown_left])
    else:
        _say("배치 거절: %s @%s" % [_reason_ko(res.reason), str(anchor)])


static func _reason_ko(reason: int) -> String:
    match reason:
        Placement.Reject.NO_RECOVERY_RIGHT: return "회수권 없음 (붕괴 전이거나 이미 배치함)"
        Placement.Reject.RUN_ENDED: return "런 종료 — R로 재시작"
        Placement.Reject.DISTRICT_LOST: return "붕괴한 외곽에는 설치 불가"
        Placement.Reject.WRONG_DISTRICT: return "내곽(경복궁·광화문·광장 북단)에만 배치 가능"
        Placement.Reject.DISTRICT_SPLIT: return "구역 경계에 걸침"
        Placement.Reject.ENEMY_OCCUPIES_CELL: return "적이 점유 중 (누르고 있으면 재시도)"
        Placement.Reject.STRUCTURE_OVERLAP: return "다른 시설과 겹침"
        Placement.Reject.TERRAIN_BLOCKED: return "지형"
        Placement.Reject.OUT_OF_BOUNDS: return "지도 밖"
        _: return Placement.reject_name(reason)


func _try_place_at_cursor() -> void:
    var anchor: Vector2i = battle.placement.anchor_for_world(get_global_mouse_position())
    var res: Placement.Result = battle.place_structure(_place_mode, anchor)
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

func _active_of(kind: int) -> int:
    var n: int = 0
    for st: Placement.Structure in battle.placement.of_kind(kind):
        if st.active:
            n += 1
    return n


func _active_total() -> int:
    var n: int = 0
    for id: int in battle.placement.structures:
        if (battle.placement.structures[id] as Placement.Structure).active:
            n += 1
    return n


func _update_hud() -> void:
    if not _show_hud:
        return
    var sim := battle.sim
    var lines: PackedStringArray = PackedStringArray()
    lines.append("한양 디펜스 · %s   Godot %s / %s" % [
        "WP-003 검증·붕괴·후퇴·재편 프로토타입" if battle.run_mode == "waves" else "WP-002 봉수망 프로토타입",
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
        "%d %s" % [_place_mode + 1, Placement.kind_label(_place_mode)]
    ])
    var net: Dictionary = battle.network.snapshot(battle.placement)
    var nparts: PackedStringArray = PackedStringArray()
    for hw: Placement.Structure in battle.placement.hwachas():
        nparts.append("%s g%d 로컬%d/공유%d%s" % [
            hw.label.trim_prefix("화차·"), hw.group_id, hw.known_local, hw.known_shared,
            ("" if hw.active else "[비활성]")
        ])
    if battle.run_mode == "waves":
        var rs := battle.run
        var ws: Dictionary = battle.waves.snapshot()
        var dc: Dictionary = battle.district_counts()
        var end_txt: String = ""
        if rs.run == 1:
            end_txt = "  ★ 승리 — 핵심 시설 사수 (R 재시작)"
        elif rs.run == 2:
            end_txt = "  ✖ 패배 — 핵심 HP 0 (R 재시작)"
        lines.append("WP-003 런 #%d  %s / %s%s" % [rs.run_id, rs.run_name(), "외곽 방어 중" if rs.defense == 0 else "내곽 방어 (외곽 붕괴)", end_txt])
        lines.append("외곽 거점 HP %.0f/%.0f (도달 %d)   핵심 HP %.0f/%.0f (도달 %d)   웨이브 %s %s 잔여 %s" % [
            rs.outer_hp, rs.outer_hp_max, rs.outer_arrivals, rs.core_hp, rs.core_hp_max, rs.core_arrivals,
            ws["wave_name"], ws["state"], str(ws["remaining"])])
        var rec: String
        if rs.collapse_count == 0:
            rec = "회수 화차: 붕괴 전 (외곽 HP 0이 되면 화차·중영 1대를 회수해 내곽에 재배치)"
        elif rs.recovery_right > 0:
            rec = "▶ 붕괴! 화차·중영 회수 1/1 — 내곽(노란 테두리) 빈 칸을 클릭해 배치 (누르고 있으면 재시도)"
        else:
            rec = "회수 화차 배치 완료 0/1 @%s (부착 %d)" % [str(rs.recovery_anchor),
                battle.placement.get_any(rs.recovery_target_id).attached_to if battle.placement.get_any(rs.recovery_target_id) != null else -1]
        lines.append(rec + "   시설: 내곽 %d(활성 %d) / 외곽 %d(활성 %d) / 대기 %d" % [
            dc["inner_total"], dc["inner_active"], dc["outer_total"], dc["outer_active"], dc["detached"]])
    lines.append("봉수망 [%s]: 봉수대 %d(활성 %d) 센서 %d 간선 %d 그룹 %s 위상 v%d | 공유전용 사격 %d" % [
        battle.targeting_mode, battle.placement.count_of(Placement.Kind.BONGSU),
        _active_of(Placement.Kind.BONGSU), battle.placement.count_of(Placement.Kind.SENSOR),
        net["link_count"], str(net["groups"]), net["topology_version"], battle.hwacha.shared_only_shots
    ])
    lines.append("화차 인지: " + "  ".join(nparts))
    if battle.run_mode == "waves":
        lines.append("LMB 회수 화차 배치(내곽)  R 재시작  Z 밀도  G 사거리  P 정지  H HUD  F12 캡처  Esc   (자유 설치/철거/T/C는 WP-003 런에서 비활성)")
    else:
        lines.append("LMB 설치  RMB 제거  1장승 2화차 3봉수대 4혼천의  T 활성전환  C 전투  Z 밀도  G 사거리  P 정지  R 초기화  H HUD  F12 캡처  Esc")
    _hud.text = "\n".join(lines)


# ================================================================== perf ===

## WP-002 fixture B combat script: at measure-relative 0,5,...,55 s toggle
## bongsu B8 (the southern sensor's only relay) and place/remove a jangseung in
## the west-south lane (22,28), alternating. A refused jangseung placement is
## retried every tick until it succeeds; refusals are counted, never skipped.
var _net_next_event: float = 0.0
var _net_events_done: int = 0
var _net_b8_toggles: int = 0
var _net_jang_id: int = -1
var _net_jang_pending: bool = false
var _net_jang_changes: int = 0
var _net_jang_refusals: int = 0
var _first_shared_shot_time: float = -1.0
var _perf_pv_start: int = 0
var _perf_topology_start: int = 0


## Per-event history (GPT review R-03): every scripted command with its
## measure-relative time, result, and the B8 / S3 / path / topology state
## before and after. Only commands that actually succeeded are counted.
var _net_events: Array = []
var _net_pending_retries: int = 0
var _net_pending_reasons: Dictionary = {}
var _measure_start: Dictionary = {}
var _measured_shots: int = 0
var _measured_shared_only: int = 0
var _shared_only_samples: Array = []
const SHARED_ONLY_SAMPLE_CAP: int = 300
var _build_sha: String = "unknown"


func _s3() -> Placement.Structure:
    var sensors: Array = battle.placement.sensors()
    return sensors[2] if sensors.size() >= 3 else null


func _state_brief() -> Dictionary:
    var s3: Placement.Structure = _s3()
    return {
        "path_version": battle.path.path_version,
        "topology_version": battle.network.topology_version,
        "groups": battle.network.groups(),
        "links": battle.network.link_count(),
        "s3_attached_to": s3.attached_to if s3 != null else -1,
        "s3_group": s3.group_id if s3 != null else -1,
    }


func _perf_network_combat_step() -> void:
    if _perf.phase() != "measure":
        return
    var t: float = _perf.elapsed_in_phase()
    if _net_jang_pending:
        var before: Dictionary = _state_brief()
        var res: Placement.Result = battle.place_jangseung(Vector2i(22, 28))
        if res.ok:
            _net_jang_id = res.structure.id
            _net_jang_pending = false
            _net_jang_changes += 1
            _perf_rebuilds += 1
            _net_events.append({
                "event": _net_events_done, "t_measure": t, "sim_time": battle.sim_time,
                "command": "place_jangseung", "anchor": "(22, 28)", "id": res.structure.id, "ok": true,
                "retries_before_success": _net_pending_retries, "refusal_reasons": _net_pending_reasons.duplicate(),
                "before": before, "after": _state_brief(),
            })
            _net_pending_retries = 0
            _net_pending_reasons = {}
        else:
            _net_jang_refusals += 1
            _net_pending_retries += 1
            var rn: String = Placement.reject_name(res.reason)
            _net_pending_reasons[rn] = int(_net_pending_reasons.get(rn, 0)) + 1
    if _net_events_done < 12 and t >= _net_next_event:
        _net_events_done += 1
        _net_next_event = float(_net_events_done) * 5.0
        var b8: Placement.Structure = battle.placement.bongsus()[7]
        var before: Dictionary = _state_brief()
        var b8_before: bool = b8.active
        var ok: bool = battle.set_active(b8.id, not b8.active)
        if ok:
            _net_b8_toggles += 1
        _net_events.append({
            "event": _net_events_done, "t_measure": t, "sim_time": battle.sim_time,
            "command": "toggle_b8", "b8_id": b8.id, "active_before": b8_before, "active_after": b8.active, "ok": ok,
            "before": before, "after": _state_brief(),
        })
        if _net_jang_id >= 0:
            var before_r: Dictionary = _state_brief()
            var rid: int = _net_jang_id
            var rres: Placement.Result = battle.remove_structure(rid)
            if rres.ok:
                _net_jang_id = -1
                _net_jang_changes += 1
                _perf_rebuilds += 1
            _net_events.append({
                "event": _net_events_done, "t_measure": t, "sim_time": battle.sim_time,
                "command": "remove_jangseung", "id": rid, "ok": rres.ok,
                "reason": Placement.reject_name(rres.reason),
                "before": before_r, "after": _state_brief(),
            })
        else:
            _net_jang_pending = true
            _net_pending_retries = 0
            _net_pending_reasons = {}


## Called after every simulation step in perf mode: collects the shots of the
## measured window (shared-only samples with time / hwacha / zone / sources).
func _perf_collect_shots() -> void:
    if _perf == null or _perf.phase() != "measure":
        return
    for shot in battle.hwacha.last_shots:
        _measured_shots += 1
        if shot.local_in_zone == 0 and shot.shared_in_zone > 0:
            _measured_shared_only += 1
            if _shared_only_samples.size() < SHARED_ONLY_SAMPLE_CAP:
                _shared_only_samples.append({
                    "t_measure": _perf.elapsed_in_phase(), "sim_time": shot.sim_time,
                    "hwacha_id": shot.hwacha_id, "zone": shot.zone_id,
                    "local": shot.local_in_zone, "shared": shot.shared_in_zone, "kills": shot.kills,
                })


## WP-003 D-027 transition benchmark script (both collapse_move and
## collapse_combat): first tick at measure 20 s -> outer HP 1 + one real enemy
## on the outer stronghold (benchmark_trigger), the collapse follows through
## real arrival damage; first tick at measure 25 s -> recovery placement at B.
## Segment statistics [0,20) / [20,25) / [25,60] are collected per frame.
var _col_triggered: bool = false
var _col_placed: bool = false
var _col_trigger_tick: int = -1
var _col_place_attempts: int = 0
var _col_place_result: String = ""
var _col_snapshots: Dictionary = {}
var _col_segments: Dictionary = {}
var _col_events: Array = []


func _col_seg_name(t_measure: float) -> String:
    if t_measure < 20.0:
        return "pre_collapse_0_20"
    if t_measure < 25.0:
        return "waiting_20_25"
    return "post_placement_25_60"


func _col_segment(name: String) -> Dictionary:
    if not _col_segments.has(name):
        _col_segments[name] = {"frames": 0, "frame_us": [], "eval_start": battle.hwacha.candidate_evaluations,
            "shots_start": battle.hwacha.shots_total, "shared_start": battle.hwacha.shared_only_shots,
            "alive_min": 999999, "sim_time_start": battle.sim_time}
    return _col_segments[name]


func _col_close_segment(name: String) -> void:
    if not _col_segments.has(name):
        return
    var s: Dictionary = _col_segments[name]
    if s.has("closed"):
        return
    s["eval_delta"] = battle.hwacha.candidate_evaluations - int(s["eval_start"])
    s["shots_delta"] = battle.hwacha.shots_total - int(s["shots_start"])
    s["shared_only_delta"] = battle.hwacha.shared_only_shots - int(s["shared_start"])
    s["sim_time_end"] = battle.sim_time
    var us: Array = s["frame_us"]
    if not us.is_empty():
        var sorted: Array = us.duplicate()
        sorted.sort()
        var n: int = sorted.size()
        var idx: int = clampi(int(ceil(0.95 * float(n))) - 1, 0, n - 1)
        s["p95_ms"] = float(sorted[idx]) / 1000.0
        s["max_ms"] = float(sorted[n - 1]) / 1000.0
        var total: int = 0
        for v: Variant in us:
            total += int(v)
        s["avg_fps"] = float(n) * 1000000.0 / float(total) if total > 0 else 0.0
    s["closed"] = true


func _col_state_snapshot(label: String, t_measure: float) -> void:
    var snap: Dictionary = battle.snapshot()
    snap.erase("hwachas")
    snap.erase("zones")
    snap["t_measure"] = t_measure
    snap["hwacha_brief"] = []
    for h: Placement.Structure in battle.placement.hwachas():
        snap["hwacha_brief"].append({"id": h.id, "label": h.label, "active": h.active, "district": h.district,
            "attached_to": h.attached_to, "group": h.group_id, "shots": h.shots_fired, "cooldown_left": h.cooldown_left})
    _col_snapshots[label] = snap


func _perf_collapse_step() -> void:
    if _perf.phase() != "measure":
        return
    var t: float = _perf.elapsed_in_phase()
    if not _col_snapshots.has("measure_start"):
        _col_state_snapshot("measure_start", t)
    if not _col_triggered and t >= 20.0:
        _col_triggered = true
        _col_trigger_tick = battle.steps
        _col_close_segment("pre_collapse_0_20")
        _col_state_snapshot("before_trigger_20s", t)
        battle.force_outer_hp(1.0, "benchmark_trigger")
        battle.spawn_extra(Vector2(950.0, 530.0), 1, "benchmark_trigger enemy")
        battle.run.log_event(battle.steps, battle.sim_time, "benchmark_trigger", {"t_measure": t,
            "outer_hp_set": 1.0, "trigger_enemy": [950.0, 530.0]})
    if _col_triggered and battle.run.collapse_count == 1 and not _col_snapshots.has("after_collapse"):
        _col_state_snapshot("after_collapse", t)
    if _col_triggered and not _col_placed and t >= 25.0:
        _col_close_segment("waiting_20_25")
        _col_place_attempts += 1
        var res: Placement.Result = battle.place_recovery(TestMap.RECOVERY_B)
        _col_place_result = "ok" if res.ok else Placement.reject_name(res.reason)
        _col_placed = true     # one attempt only: a refusal is a FAIL, never retried silently
        _col_state_snapshot("after_placement_25s", t)


## Per-frame segment sampling for the collapse scenarios (called from _process).
func _col_sample_frame(frame_us: int) -> void:
    if _perf == null or _perf.phase() != "measure" or not _perf.scenario.begins_with("collapse"):
        return
    var t: float = _perf.elapsed_in_phase()
    var seg: Dictionary = _col_segment(_col_seg_name(t))
    seg["frames"] = int(seg["frames"]) + 1
    (seg["frame_us"] as Array).append(frame_us)
    seg["alive_min"] = mini(int(seg["alive_min"]), battle.sim.alive_count)


func _perf_script_step() -> void:
    if _perf == null:
        return
    _perf_collect_shots()
    if _perf.scenario.begins_with("collapse"):
        _perf_collapse_step()
        return
    if _perf.scenario == "network_combat":
        _perf_network_combat_step()
        return
    if _perf.scenario != "combat":
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


func _collapse_perf_extra() -> Dictionary:
    if _perf == null or not _perf.scenario.begins_with("collapse"):
        return {}
    _col_close_segment("post_placement_25_60")
    _col_state_snapshot("end", _perf.elapsed_in_phase())
    var segs: Dictionary = {}
    for k: Variant in _col_segments:
        var s: Dictionary = (_col_segments[k] as Dictionary).duplicate()
        s.erase("frame_us")
        segs[k] = s
    var semantic: Array = []
    for e: Dictionary in battle.run.events:
        if e["type"] in ["benchmark_trigger", "collapse", "outer_deactivated_batch", "target_changed", "recovery_created", "recovery_placed", "recovery_refused", "recovery_failed"]:
            semantic.append(e)
    var h1: Placement.Structure = battle.placement.get_any(battle.run.recovery_target_id)
    var placed_tick: int = battle.run.recovery_placed_tick
    return {
        "trigger_tick": _col_trigger_tick,
        "collapse_tick": battle.run.collapse_tick,
        "collapse_sim_time": battle.run.collapse_sim_time,
        "ticks_trigger_to_collapse": (battle.run.collapse_tick - _col_trigger_tick) if battle.run.collapse_tick >= 0 else -1,
        "placement_tick": placed_tick,
        "ticks_collapse_to_placement": (placed_tick - battle.run.collapse_tick) if placed_tick >= 0 and battle.run.collapse_tick >= 0 else -1,
        "placement_attempts": _col_place_attempts,
        "placement_result": _col_place_result,
        "placement_anchor": [TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y],
        "h1_shots_after_placement": (h1.shots_fired - int(_col_snapshots.get("after_placement_25s", {}).get("shots_total", 0))) if h1 != null and _col_snapshots.has("after_placement_25s") else -1,
        "h1_final": {"id": h1.id, "attached_to": h1.attached_to, "group": h1.group_id, "shots": h1.shots_fired, "kills": h1.kills, "cooldown_left": h1.cooldown_left} if h1 != null else {},
        "semantic_events": semantic,
        "semantic_event_types_expected": ["benchmark_trigger", "collapse", "outer_deactivated_batch", "target_changed", "recovery_created", "recovery_placed"],
        "all_events": battle.run.events,
        "segments": segs,
        "snapshots": _col_snapshots,
        "run": battle.run.snapshot(),
        "districts": battle.district_counts(),
        "core_damage_absorbed": battle.run.core_damage_absorbed,
        "natural_collapse_before_trigger": battle.run.collapse_tick >= 0 and _col_trigger_tick >= 0 and battle.run.collapse_tick < _col_trigger_tick,
    }


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
        # path_version must equal its value at perf start + the scripted
        # rebuilds; anything else means an unscripted rebuild happened.
        "path_version_at_start": _perf_pv_start,
        "run_mode": battle.run_mode,
        "arrival_mode": battle.arrival_mode,
        "zone_set": config.get_str("zone_set"),
        "path_version_expected": _perf_pv_start + _perf_rebuilds,
        "topology_version_at_start": _perf_topology_start,
        "jangseung_count_at_end": battle.placement.count_of(Placement.Kind.JANGSEUNG),
        "hwacha_count_at_end": battle.placement.count_of(Placement.Kind.HWACHA),
        "placement_rejected_total": battle.placement.rejected_total,
        "interactive_input_ignored": true,
        "targeting_mode": battle.targeting_mode,
        "fixture": config.get_str("fixture"),
        "structure_count": battle.placement.structures.size(),
        "active_structure_count": _active_total(),
        "bongsu_count": battle.placement.count_of(Placement.Kind.BONGSU),
        "sensor_count": battle.placement.count_of(Placement.Kind.SENSOR),
        "network": battle.network.snapshot(battle.placement),
        "topology_version": battle.network.topology_version,
        "network_events_scripted": _net_events_done,
        "b8_toggles": _net_b8_toggles,
        "b8_toggles_expected": 12 if _perf.scenario == "network_combat" else 0,
        "jangseung_changes": _net_jang_changes,
        "jangseung_changes_expected": 12 if _perf.scenario == "network_combat" else 0,
        "jangseung_refusals": _net_jang_refusals,
        "shared_only_shots": battle.hwacha.shared_only_shots,
        "shared_only_shots_first_sim_time": _first_shared_shot_time,
        "activation_changes": battle.activation_changes,
        "candidate_evaluations": battle.hwacha.candidate_evaluations,
        "damage_applications": battle.sim.damage_applications,
        # --- R-03: measured-window accounting (cumulative values above include warm-up) ---
        "measure_start": _measure_start,
        "measured_window": {
            "shots": _measured_shots,
            "shared_only_shots": _measured_shared_only,
            "shots_total_delta": battle.hwacha.shots_total - int(_measure_start.get("shots_total", 0)),
            "shared_only_delta": battle.hwacha.shared_only_shots - int(_measure_start.get("shared_only_shots", 0)),
            "killed_delta": battle.sim.killed_total - int(_measure_start.get("killed_total", 0)),
            "candidate_evaluations_delta": battle.hwacha.candidate_evaluations - int(_measure_start.get("candidate_evaluations", 0)),
            "sim_seconds": battle.sim_time - float(_measure_start.get("sim_time", 0.0)),
        },
        "shared_only_samples": _shared_only_samples,
        "shared_only_samples_cap": SHARED_ONLY_SAMPLE_CAP,
        "events": _net_events,
        "events_expected_t_measure": [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0] if _perf.scenario == "network_combat" else [],
        "collapse": _collapse_perf_extra(),
        "manifest": {
            "implementation_sha": _build_sha,
            "config": config.to_dictionary(),
            "fixture_b_hwachas": TestMap.HWACHAS,
            "fixture_b_bongsu": TestMap.FIXTURE_B_BONGSU,
            "fixture_b_sensors": TestMap.FIXTURE_B_SENSORS,
            "jangseung_anchor": "(22, 28)",
            "b8_id": battle.placement.bongsus()[7].id if battle.placement.bongsus().size() >= 8 else -1,
            "s3_id": _s3().id if _s3() != null else -1,
            "zones": TestMap.ZONES,
        },
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
        "wp002_a":
            # Fixture A (backlog/WP-002.md): empty field, stationary enemy at Z0,
            # H/B/S placed before the enemy. Combat on, no spawning.
            config.values["targeting_mode"] = "wp002"
            config.values["fixture"] = "none"
            config.values["combat_enabled"] = true
            config.values["enemy_speed"] = 0.0
            battle.reset()
            battle.spawning_enabled = false
            _sim_speed = 1
            var fa: Dictionary = TestMap.FIXTURE_A
            _capture_steps = [
                {"t": 0.0, "do": "place_kind", "kind": Placement.Kind.HWACHA, "anchor": fa["hwacha"], "label": "H 화차"},
                {"t": 0.0, "do": "place_kind", "kind": Placement.Kind.BONGSU, "anchor": fa["bongsu"], "label": "B 봉수대"},
                {"t": 0.0, "do": "place_kind", "kind": Placement.Kind.SENSOR, "anchor": fa["sensor"], "label": "S 혼천의"},
                {"t": 0.0, "do": "set_active", "label": "B 봉수대", "active": false},
                {"t": 0.0, "do": "spawn", "pos": fa["enemy"]},
                {"t": 2.0, "do": "capture", "name": "wp002_a1_disconnected_no_fire_t2"},
                {"t": 2.0, "do": "set_active", "label": "B 봉수대", "active": true},
                {"t": 2.5, "do": "hover", "label": "H 화차"},
                {"t": 2.5, "do": "capture", "name": "wp002_a2_connected_shared_fire_t2.5"},
                {"t": 2.5, "do": "hover", "label": ""},
                {"t": 2.5, "do": "set_active", "label": "B 봉수대", "active": false},
                {"t": 5.0, "do": "capture", "name": "wp002_a3_disconnected_again_no_stale_fire_t5"},
                {"t": 5.0, "do": "place_kind", "kind": Placement.Kind.HWACHA, "anchor": Vector2i(48, 41), "label": "H2 화차(로컬)"},
                {"t": 5.0, "do": "spawn", "pos": Vector2(980.0, 750.0)},
                {"t": 5.5, "do": "hover", "label": "H2 화차(로컬)"},
                {"t": 5.5, "do": "capture", "name": "wp002_a4_local_fire_while_disconnected_t5.5"},
                {"t": 5.5, "do": "hover", "label": ""},
                {"t": 5.5, "do": "set_active", "label": "B 봉수대", "active": true},
                {"t": 7.0, "do": "capture", "name": "wp002_a5_reconnected_reacquired_t7"},
                {"t": 7.0, "do": "quit"},
            ]
        "wp003_f2":
            # WP-003 F2 (D-026): the real run, verification-forced collapse at
            # 20 s through real arrival damage, recovery at collapse + 5 s to B,
            # then play to the end. Times are absolute: the collapse follows the
            # trigger on the next tick (deterministic, see test_collapse_retreat).
            _apply_mode_preset(Config.for_wp003())
            battle.reset()
            _sim_speed = 6
            _capture_steps = [
                {"t": 15.0, "do": "capture", "name": "wp003_f2_a_outer_defense_t15"},
                {"t": 20.0, "do": "force_outer_hp", "value": 1.0, "why": "F2 forced collapse"},
                {"t": 20.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "F2 trigger enemy"},
                {"t": 20.5, "do": "capture", "name": "wp003_f2_b_collapse_notice_t20.5"},
                {"t": 23.0, "do": "preview_at", "anchor": Vector2i(46, 29)},
                {"t": 23.0, "do": "capture", "name": "wp003_f2_c_invalid_outer_preview_t23"},
                {"t": 23.0, "do": "preview_at", "anchor": TestMap.RECOVERY_B},
                {"t": 23.5, "do": "capture", "name": "wp003_f2_d_valid_inner_preview_t23.5"},
                {"t": 23.5, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 25.0, "do": "place_recovery", "anchor": TestMap.RECOVERY_B},
                {"t": 25.5, "do": "hover", "label": "화차·중영"},
                {"t": 25.5, "do": "capture", "name": "wp003_f2_e_recovery_placed_t25.5"},
                {"t": 25.5, "do": "hover", "label": ""},
                {"t": 45.0, "do": "capture", "name": "wp003_f2_f_inner_fire_t45"},
                {"t": 400.0, "do": "capture_on_end", "name": "wp003_f2_g_run_end"},
            ]
        _:
            printerr("unknown capture scenario: %s" % _capture_name)
            get_tree().quit()


func _capture_script_step() -> void:
    if _capture_name == "" or _capture_busy:
        return
    while _capture_index < _capture_steps.size():
        var step: Dictionary = _capture_steps[_capture_index]
        if step["do"] == "capture_on_end":
            # Fires when the run has ended (WON / LOST), or at its time as a safety net.
            if not battle.run.ended() and battle.sim_time + 1e-6 < float(step["t"]):
                return
            _capture_index += 1
            _capture_log.append({"t": battle.sim_time, "run_end_capture": battle.run.run_name(),
                "ended": battle.run.ended(), "tick": battle.steps})
            _capture_steps.insert(_capture_index, {"t": 0.0, "do": "quit"})
            _capture_busy = true
            _do_capture(step["name"])
            return
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
            "place_kind":
                var pr: Placement.Result = battle.place_structure(step["kind"], step["anchor"], step["label"])
                _capture_log.append({"t": battle.sim_time, "place": str(step["anchor"]),
                    "kind": Placement.kind_name(step["kind"]), "label": step["label"],
                    "ok": pr.ok, "reason": Placement.reject_name(pr.reason),
                    "id": pr.structure.id if pr.ok else -1})
            "set_active":
                var target: Placement.Structure = null
                for id: int in battle.placement.structures:
                    var cand: Placement.Structure = battle.placement.structures[id]
                    if cand.label == step["label"]:
                        target = cand
                var ok: bool = target != null and battle.set_active(target.id, step["active"])
                _capture_log.append({"t": battle.sim_time, "set_active": step["label"],
                    "active": step["active"], "ok": ok,
                    "topology_version": battle.network.topology_version})
            "force_outer_hp":
                battle.force_outer_hp(step["value"], step["why"])
                _capture_log.append({"t": battle.sim_time, "force_outer_hp": step["value"], "why": step["why"]})
            "spawn_extra":
                var slots: PackedInt32Array = battle.spawn_extra(step["pos"], step["count"], step["why"])
                _capture_log.append({"t": battle.sim_time, "spawn_extra": slots.size(), "pos": str(step["pos"]), "why": step["why"]})
            "place_recovery":
                var rr: Placement.Result = battle.place_recovery(step["anchor"])
                _capture_log.append({"t": battle.sim_time, "place_recovery": str(step["anchor"]), "ok": rr.ok,
                    "reason": Placement.reject_name(rr.reason), "tick": battle.steps,
                    "collapse_tick": battle.run.collapse_tick, "core_hp": battle.run.core_hp,
                    "attached_to": rr.structure.attached_to if rr.ok else -1})
            "preview_at":
                # Scripted stand-in for the placement cursor at a fixed anchor
                # (Vector2i(-1,-1) clears it).
                var a: Vector2i = step["anchor"]
                _overlay.preview_override = a
                _capture_log.append({"t": battle.sim_time, "preview_at": str(a),
                    "reason": Placement.reject_name(battle.preview_recovery(a)) if a.x >= 0 else ""})
            "hover":
                # Scripted stand-in for the mouse: show the hover panel of the
                # labelled structure (empty label clears it).
                _overlay.hover_override = Vector2.INF
                for id: int in battle.placement.structures:
                    var cand: Placement.Structure = battle.placement.structures[id]
                    if step["label"] != "" and cand.label == step["label"]:
                        _overlay.hover_override = cand.center
                _capture_log.append({"t": battle.sim_time, "hover": step["label"]})
            "spawn":
                var slot: int = battle.sim.force_spawn(0, step["pos"])
                _capture_log.append({"t": battle.sim_time, "spawn": str(step["pos"]), "slot": slot,
                    "enemy_id": battle.sim.enemy_id(slot) if slot >= 0 else -1})
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
