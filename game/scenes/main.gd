extends Node2D
## WP-001 playable prototype: rendering, input, debug overlay, and the scripted
## perf / capture modes. All game rules live in game/core; this file only reads
## state and forwards commands.
##
## Interactive controls (WP-004 play flow: TITLE -> PLAYING -> PAUSED / SETTINGS /
## CONFIRM -> RESULT; see game/core/play_flow.gd)
##   LMB (hold)  place at the cursor, retrying every tick while held (PLAYING only)
##   RMB         remove the structure under the cursor (sandbox only)
##   1 / 2       placement mode: 장승 (blocks) / 화차 (fires) (sandbox only)
##   C           toggle combat (sandbox only)
##   Z           toggle density zone overlay
##   G           toggle hwacha range rings
##   Esc / P     pause (opens the pause menu); Esc closes one menu level
##   R           PLAYING: restart confirmation; RESULT: restart at once
##   H           toggle HUD
##   D           toggle the detail panel (routes, densities, per-hwacha, network)
##   F12         save a screenshot next to the project (user://captures)
##   Quit        TITLE "종료" button (or the OS window close)
##
## Command line (after `--`):
##   --set key=value       override any config value (see game/core/config.gd)
##   --config=path.json    merge a JSON config file
##   --speed=N             simulation steps per physics tick (default 1)
##   --quit-after=SEC      quit after SEC seconds of simulated time
##   --perf --scenario=move|combat [--warmup=10] [--measure=60] --out=path.json
##   --capture=ac01|ac02|ac06|wp002_a|wp003_f2|wp003_f3a|wp003_f3b|wp004_ui|wp004_ui_720 --out-dir=dir
##                         scripted evidence captures (menus bypassed except wp004_ui*)
##   --art=greybox|sample  WP-005 rendering choice only (D-049): sample draws the reviewed PNGs from
##                         assets/art/wp005 (missing files keep the grey box); game data, seed and
##                         automation are identical in both. --art-dir=res://... overrides the directory,
##                         --labels=off hides structure name labels (AC-03 legend comparison).
##   --settings=path.cfg   user settings file (default user://settings.cfg; never read by --perf/--capture
##                         unless given explicitly, WP-004 §6)
##   --view=player|dev     WP-005 V-01 (D-053) display defaults. A normal launch starts in the player view
##                         (density zones, range rings and the detail panel collapsed, short structure
##                         names, wave / HP / recovery first); --perf / --capture keep the developer view.
##                         Z / G / D bring each piece back at any time.
##   --play-mode=build     WP-008 (D-054): preparation phase + paid construction + supply ledger on the
##                         "build" fixture (4 structures). Never the default; the classic run is unchanged.
##
## WP-008 build-mode controls (PREPARING and PLAYING):
##   1 / 2 / 3 / 4   select 장승 / 화차 / 봉수대 / 혼천의 to buy (cost shown at the cursor)
##   5               select the free recovery placement (after the collapse)
##   LMB             one paid construction per NEW press (no hold retry); the recovery
##                   placement keeps its hold retry
##   Space           방어 시작 (PREPARING only, once)

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
const F3Tracker := preload("res://game/tools/f3_tracker.gd")
const PlayFlow := preload("res://game/core/play_flow.gd")
const ResultModel := preload("res://game/core/result_model.gd")
const UserSettings := preload("res://game/core/user_settings.gd")
const MenuLayer := preload("res://game/scenes/menu_layer.gd")
const ArtSet := preload("res://game/scenes/art_set.gd")
const FxLayer := preload("res://game/scenes/fx_layer.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")

const COLOR_TEXT: Color = Color(0.92, 0.90, 0.85)

var battle: Battle = null
var config: Config = null

var _terrain: TerrainLayer = null
var _overlay: OverlayLayer = null
var _enemies: MultiMeshInstance2D = null
var _multimesh: MultiMesh = null
var _buffer: PackedFloat32Array = PackedFloat32Array()
## WP-005 (D-049): rendering choice. "greybox" is the WP-001..004 drawing,
## "sample" reads the art set; nothing in the simulation depends on it.
## Empty = not chosen on the command line: an interactive launch shows the
## reviewed art (sample), scripted evidence runs (--perf / --capture) stay
## grey box unless --art says otherwise (D-050).
var _art_mode: String = ""
var _art_dir: String = ArtSet.DEFAULT_DIR
var art: ArtSet = null
var _art_report: Dictionary = {}
var _fx: FxLayer = null
var _fx_collapses_seen: int = 0
var _show_labels: bool = true
var _enemy_sprites: bool = false
## D-052: 1-texel pale rim around enemy sprites in the atlas shader (contrast
## on dark streets); rendering only, --art-outline=off disables it.
var _enemy_outline: bool = true
var _capture_cam: Camera2D = null
var _enemy_stride: int = 12
var _last_outer_hp: float = -1.0
var _last_core_hp: float = -1.0
var _hud_layer: CanvasLayer = null
## R-07: two panels that never cover the inner district / objectives.
## Top-left (x 8..~824, above the plaza): run state, HP, recovery guidance, controls.
## Bottom-left (x 8..~854, below the west corridor): detail / debug lines + notices.
var _hud_top: PanelContainer = null
var _hud: Label = null
var _hud_bottom: PanelContainer = null
var _detail: Label = null
var _notice: Label = null
const HUD_TOP_WIDTH: float = 800.0
const HUD_DETAIL_WIDTH: float = 830.0
var _font: Font = null

var _place_mode: int = Placement.Kind.JANGSEUNG
## WP-008 selection in build mode: a kind to buy (0..3), the free recovery
## placement (SEL_RECOVERY) or nothing (SEL_NONE, recovery clicks still work).
const SEL_NONE: int = -1
const SEL_RECOVERY: int = 4
var _sel_kind: int = SEL_NONE
var _recovery_prompt_run: int = -1
var _play_mode_arg: String = ""
var _build_bar: PanelContainer = null
var _build_label: Label = null
var _build_buttons: Dictionary = {}
var _begin_button: Button = null
## Paid-build attempts issued by the scene (AC-04 evidence: one per press).
var build_clicks: Array = []
## WP-004: top-level UI state (TITLE / PLAYING / PAUSED / SETTINGS / CONFIRM /
## RESULT), the menu layer, the persisted settings and the frozen result.
var flow: PlayFlow = PlayFlow.new()
var menu: MenuLayer = null
var settings: UserSettings = null
var _settings_path: String = ""
## Requests from buttons / keys are queued and applied at the start of the
## next physics frame, in order, each validated against the state at that
## moment (so a run that has already ended wins over a pending pause/restart,
## and a double click performs exactly one transition).
var _intents: Array = []
var _result_model: Dictionary = {}
var _hud_pause_button: Button = null
var _show_zones: bool = true
var _show_ranges: bool = true
var _show_hud: bool = true
var _show_detail: bool = true
## WP-005 V-01: player view vs developer view (see --view).
var _player_view: bool = false
var _view_arg: String = ""
## Capture-only: freeze the battle while several captures of one tick are
## taken (before / after comparisons at the same simulation tick).
var _capture_hold: bool = false
var _mouse_down: bool = false
## run_id the held click was issued in (R-03): a retry never crosses a restart.
var _mouse_down_run_id: int = -1
## Inputs physically held right now, keyed by name ("Escape", "Enter", "R",
## "mouse1"...). Tracked from `_input` (every event, before the GUI consumes
## it) and from `_handle_key_event` (synthesized events in tests / captures).
## It mirrors the devices, so a restart never clears it; a window focus loss
## does, because the releases may never arrive.
var _held: Dictionary = {}
## Release fence (WP-004 §2, R-01 of the 2026-09-19 GPT review, D-047): the
## inputs that were still held at the moment a menu closed to PLAYING. Field
## commands are refused until every one of them has been released; a press
## refused this way is logged in `fenced_inputs` and is never held for retry.
var _fence: Dictionary = {}
var fenced_inputs: Array = []
var _menu_was_open: bool = true
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
    if _play_mode_arg != "":
        # --play-mode pins play_mode (and the build fixture unless --set fixture
        # was given) exactly like an explicit --set, so a scripted preset
        # cannot silently drop it.
        config.values["play_mode"] = _play_mode_arg
        _explicit_sets["play_mode"] = true
        if _play_mode_arg == "build" and not _explicit_sets.has("fixture"):
            config.values["fixture"] = "build"
            _explicit_sets["fixture"] = true
    if _art_mode == "":
        _art_mode = "greybox" if (_perf != null or _capture_name != "") else "sample"
    battle = Battle.new(config)
    _build_scene()
    _apply_run_mode()
    _set_player_view(_view_arg == "player" or (_view_arg == "" and _perf == null and _capture_name == ""))


var _explicit_sets: Dictionary = {}

## Every key that selects a game mode. A scripted scenario must reapply ALL of
## them from its own preset (Codex review on PR #4: the legacy WP-001/002
## scenarios had inherited run_mode="waves" & co. from the WP-003 default).
const MODE_KEYS: Array[String] = [
    "targeting_mode", "fixture", "zone_set", "arrival_mode", "run_mode", "district_rules",
    "outer_hp", "core_hp", "arrival_damage", "wave_gap_seconds", "benchmark_core_invulnerable",
    "play_mode", "benchmark_supply",
]


## Copy the mode keys from `src` into the live config, except keys the user
## pinned explicitly with --set.
func _apply_mode_preset(src: Config) -> void:
    for k: String in MODE_KEYS:
        if not _explicit_sets.has(k):
            config.values[k] = src.values[k]


func _parse_args() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--settings="):
            # Before the "--set" prefix test: "--settings=path" is not a config override
            # (GPT observation on PR #13; the file path was silently ignored before).
            _settings_path = arg.substr("--settings=".length())
        elif arg.begins_with("--set"):
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
        elif arg.begins_with("--art="):
            var m: String = arg.substr("--art=".length())
            if m == "greybox" or m == "sample":
                _art_mode = m
            else:
                printerr("unknown --art mode: %s (greybox|sample)" % m)
        elif arg.begins_with("--art-dir="):
            _art_dir = arg.substr("--art-dir=".length())
        elif arg.begins_with("--labels="):
            _show_labels = arg.substr("--labels=".length()) != "off"
        elif arg.begins_with("--view="):
            _view_arg = arg.substr("--view=".length())
        elif arg.begins_with("--art-outline="):
            _enemy_outline = arg.substr("--art-outline=".length()) != "off"
        elif arg.begins_with("--play-mode="):
            var pm: String = arg.substr("--play-mode=".length())
            if pm == "build" or pm == "classic":
                _play_mode_arg = pm
            else:
                printerr("unknown --play-mode: %s (classic|build)" % pm)


func _build_scene() -> void:
    _font = ThemeDB.fallback_font

    _terrain = TerrainLayer.new()
    _terrain.name = "Terrain"
    add_child(_terrain)
    _terrain.setup(battle.grid, battle.grid.index_center(battle.path.goal_index),
        config.get_num("goal_radius"))
    _sync_terrain_marker()

    if _art_mode == "sample":
        art = ArtSet.new(_art_dir)
        _art_report = art.load_all()
        _terrain.art = art
        _terrain.queue_redraw()
        print("art: sample set %s -> %d/%d files, %d missing" % [_art_dir, art.loaded_count(), art.contract_count(), art.missing.size()])

    _enemies = MultiMeshInstance2D.new()
    _enemies.name = "Enemies"
    _multimesh = MultiMesh.new()
    _multimesh.transform_format = MultiMesh.TRANSFORM_2D
    _multimesh.use_colors = true
    _enemy_sprites = art != null and art.enemy_atlas != null
    if _enemy_sprites:
        # One batched draw as before: the atlas frame is chosen per instance
        # from INSTANCE_CUSTOM.x in the vertex shader (D-049).
        _multimesh.use_custom_data = true
        _enemy_stride = 16
        _multimesh.mesh = _sprite_quad(art.enemy_frame_size)
        _enemies.texture = art.enemy_atlas
        var mat: ShaderMaterial = ShaderMaterial.new()
        mat.shader = _enemy_atlas_shader()
        mat.set_shader_parameter("frame_uv", Vector2(art.enemy_frame_size) / Vector2(art.enemy_atlas_size))
        mat.set_shader_parameter("pitch_uv", Vector2(art.enemy_atlas_pitch) / Vector2(art.enemy_atlas_size))
        mat.set_shader_parameter("columns", ArtSet.ATLAS_COLUMNS)
        mat.set_shader_parameter("texel", Vector2.ONE / Vector2(art.enemy_atlas_size))
        mat.set_shader_parameter("outline", 1.0 if _enemy_outline else 0.0)
        _enemies.material = mat
    else:
        var quad: QuadMesh = QuadMesh.new()
        var size: float = config.get_num("enemy_draw_size")
        quad.size = Vector2(size, size)
        _multimesh.mesh = quad
    _multimesh.instance_count = battle.sim.capacity
    _multimesh.visible_instance_count = 0
    _buffer.resize(battle.sim.capacity * _enemy_stride)
    _enemies.multimesh = _multimesh
    add_child(_enemies)

    if _art_mode == "sample":
        _fx = FxLayer.new()
        _fx.name = "Fx"
        _fx.art = art
        add_child(_fx)

    _overlay = OverlayLayer.new()
    _overlay.name = "Overlay"
    _overlay.battle = battle
    _overlay.font = _font
    _overlay.art = art
    _overlay.show_labels = _show_labels
    _overlay.draw_blasts = _fx == null
    add_child(_overlay)

    _hud_layer = CanvasLayer.new()
    _hud_layer.name = "HUD"
    add_child(_hud_layer)

    # Top-left panel: sized by its content, capped at HUD_TOP_WIDTH so it ends
    # left of the 경복궁 compound (x >= 840) and above the plaza (y >= 320).
    _hud_top = _make_panel()
    _hud_top.position = Vector2(8.0, 8.0)
    _hud_layer.add_child(_hud_top)
    _hud = _make_hud_label(HUD_TOP_WIDTH, 15)
    _hud_top.add_child(_hud)

    # Bottom-left panel: anchored to the bottom edge and growing upward, in the
    # solid block below the 서대문 corridor (y >= 600) and left of 남대문 (x < 880).
    _hud_bottom = _make_panel()
    _hud_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    _hud_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _hud_bottom.offset_left = 8.0
    _hud_bottom.offset_bottom = -8.0
    _hud_layer.add_child(_hud_bottom)
    var vbox: VBoxContainer = VBoxContainer.new()
    _hud_bottom.add_child(vbox)
    _detail = _make_hud_label(HUD_DETAIL_WIDTH, 14)
    vbox.add_child(_detail)
    _notice = _make_hud_label(HUD_DETAIL_WIDTH, 17)
    _notice.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    vbox.add_child(_notice)

    # WP-004: pause button (top-right, outside the plaza / compound) and the menu layer.
    _hud_pause_button = Button.new()
    _hud_pause_button.name = "PauseButton"
    _hud_pause_button.text = "일시정지 (Esc)"
    _hud_pause_button.add_theme_font_size_override("font_size", 18)
    _hud_pause_button.custom_minimum_size = Vector2(180.0, 44.0)
    _hud_pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    _hud_pause_button.offset_left = -196.0
    _hud_pause_button.offset_right = -16.0
    _hud_pause_button.offset_top = 12.0
    _hud_pause_button.offset_bottom = 56.0
    _hud_pause_button.focus_mode = Control.FOCUS_NONE
    _hud_pause_button.pressed.connect(func() -> void: queue_intent("pause"))
    _hud_layer.add_child(_hud_pause_button)

    # WP-008: construction bar (bottom-right, over the solid block below the
    # 동대문 corridor). Real Button nodes: a click is consumed by the Control
    # and never reaches the field. Hidden outside build mode.
    _build_bar = _make_panel()
    _build_bar.name = "BuildBar"
    _build_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    _build_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _build_bar.offset_right = -16.0
    _build_bar.offset_bottom = -16.0
    _hud_layer.add_child(_build_bar)
    var bv: VBoxContainer = VBoxContainer.new()
    bv.add_theme_constant_override("separation", 6)
    _build_bar.add_child(bv)
    _build_label = _make_hud_label(560.0, 16)
    _build_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    bv.add_child(_build_label)
    var bh: HBoxContainer = HBoxContainer.new()
    bh.add_theme_constant_override("separation", 6)
    bv.add_child(bh)
    for spec: Array in [["build_jangseung", Placement.Kind.JANGSEUNG], ["build_hwacha", Placement.Kind.HWACHA],
            ["build_bongsu", Placement.Kind.BONGSU], ["build_sensor", Placement.Kind.SENSOR], ["build_recovery", SEL_RECOVERY]]:
        var b: Button = Button.new()
        b.name = spec[0]
        b.add_theme_font_size_override("font_size", 16)
        b.custom_minimum_size = Vector2(104.0, 40.0)
        b.focus_mode = Control.FOCUS_NONE
        var kind: int = spec[1]
        b.pressed.connect(func() -> void: _select_build(kind, "button"))
        bh.add_child(b)
        _build_buttons[spec[0]] = b
    _begin_button = Button.new()
    _begin_button.name = "begin_defense"
    _begin_button.text = "방어 시작 (Space)"
    _begin_button.add_theme_font_size_override("font_size", 18)
    _begin_button.custom_minimum_size = Vector2(200.0, 44.0)
    _begin_button.focus_mode = Control.FOCUS_NONE
    _begin_button.pressed.connect(func() -> void: queue_intent("begin_defense"))
    bv.add_child(_begin_button)
    _build_buttons["begin_defense"] = _begin_button
    _build_bar.visible = false

    menu = MenuLayer.new()
    menu.name = "Menu"
    menu.on_intent = Callable(self, "queue_intent")
    add_child(menu)
    menu.build()


static func _make_panel() -> PanelContainer:
    var p: PanelContainer = PanelContainer.new()
    var sb: StyleBoxFlat = StyleBoxFlat.new()
    sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
    sb.content_margin_left = 8.0
    sb.content_margin_right = 8.0
    sb.content_margin_top = 4.0
    sb.content_margin_bottom = 4.0
    p.add_theme_stylebox_override("panel", sb)
    return p


static func _make_hud_label(width: float, font_size: int) -> Label:
    var l: Label = Label.new()
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(width, 0.0)
    l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", COLOR_TEXT)
    return l


## A 2D quad whose origin is the bottom centre (enemy pivot, ART_GUIDE) with
## plain 0..1 UVs, so the atlas shader can offset them per instance.
static func _sprite_quad(size: Vector2i) -> ArrayMesh:
    var w: float = float(size.x)
    var h: float = float(size.y)
    var verts: PackedVector2Array = PackedVector2Array([
        Vector2(-w * 0.5, -h), Vector2(w * 0.5, -h), Vector2(w * 0.5, 0.0), Vector2(-w * 0.5, 0.0)])
    var uvs: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
    var idx: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3])
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = idx
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


static func _enemy_atlas_shader() -> Shader:
    var sh: Shader = Shader.new()
    sh.code = """
shader_type canvas_item;
uniform vec2 frame_uv;
uniform vec2 pitch_uv;
uniform int columns = 4;
uniform vec2 texel;
uniform float outline = 1.0;
uniform vec4 outline_color : source_color = vec4(0.93, 0.88, 0.78, 0.85);
void vertex() {
    int f = int(INSTANCE_CUSTOM.x + 0.5);
    vec2 origin = vec2(float(f % columns), float(f / columns)) * pitch_uv;
    UV = origin + UV * frame_uv;
}
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    if (outline > 0.5 && c.a < 0.05) {
        // a transparent texel next to an opaque one becomes the rim; the
        // atlas gutters are transparent, so frames never bleed into each other
        float n = texture(TEXTURE, UV + vec2(texel.x, 0.0)).a + texture(TEXTURE, UV - vec2(texel.x, 0.0)).a
                + texture(TEXTURE, UV + vec2(0.0, texel.y)).a + texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
        if (n > 0.2) {
            c = outline_color;
        }
    }
    COLOR = c * COLOR;
}
"""
    return sh


## Which atlas frame an enemy shows: walking direction from the flow field
## (the cell it heads to), two frames alternating on simulation time.
func _enemy_frame(slot: int, sim: EnemySim, flow: PackedInt32Array, w: int, phase: int) -> int:
    var ci: int = sim.cell[slot]
    var ni: int = flow[ci] if ci >= 0 and ci < flow.size() else -1
    var base: int = 0   # walk_down
    if ni >= 0 and ni != ci:
        var dx: int = (ni % w) - (ci % w)
        var dy: int = int(ni / w) - int(ci / w)
        if absi(dx) > absi(dy):
            base = 6 if dx > 0 else 4      # walk_right / walk_left
        else:
            base = 0 if dy > 0 else 2      # walk_down / walk_up
    return base + ((phase + slot) & 1)


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
        if _perf.scenario.begins_with("build"):
            # WP-008 AC-08: the D-027 transition benchmark on the build profile
            # (24-structure worst case, benchmark supply injected and flagged).
            _apply_mode_preset(Config.for_wp008())
            config.values["outer_hp"] = 1000000.0
            config.values["benchmark_core_invulnerable"] = true
            config.values["benchmark_supply"] = 3000
        elif _perf.scenario.begins_with("collapse"):
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
        if _is_transition_perf():
            battle.waves.enabled = false   # finite waves off: the load is the benchmark top-up
        if _perf.scenario.begins_with("build"):
            _setup_build_perf()
        _perf_structures_at_start = _structure_manifest()
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
    if _art_mode != "greybox":
        title += " [art:%s]" % _art_mode
    if battle.play_mode == "build":
        title += " [play:build]"
    DisplayServer.window_set_title(title)
    _sync_terrain_marker()
    _apply_play_flow_mode()
    _last_outer_hp = battle.run.outer_hp
    _last_core_hp = battle.run.core_hp


## WP-004 §6: scripted / automated modes bypass the menus and never read the
## user's settings file; a normal launch starts on TITLE with the settings
## loaded (missing / broken file -> defaults, launch never blocked).
func _apply_play_flow_mode() -> void:
    var menu_capture: bool = _capture_name.begins_with("wp004") or _capture_name.begins_with("wp008")
    var scripted: bool = _perf != null or (_capture_name != "" and not menu_capture)
    if scripted:
        flow.start_bypass()
        settings = null           # never read or written by the verification modes
        menu.show_state("PLAYING", {})
        _hud_pause_button.visible = false
        if battle.preparing:
            # Bypass modes have no preparation screen: the scenario's own
            # setup (perf) has run, the defence starts now (logged event).
            battle.begin_defense()
        _sync_build_bar()
        return
    var path: String = _settings_path if _settings_path != "" else UserSettings.DEFAULT_PATH
    if menu_capture:
        _overlay.show_cursor = false
        if _settings_path == "":
            path = "user://%s_capture_settings.cfg" % _capture_name.substr(0, 5)   # never the player's real file
    settings = UserSettings.new(path)
    if _capture_name == "" or _settings_path != "":
        settings.load()
        _apply_window_mode(settings.window_mode)
    flow = PlayFlow.new()   # fresh machine on TITLE (a previous scripted bypass never leaks in)
    _hud_pause_button.visible = false
    battle.reset()          # TITLE shows the initial field; nothing ticks until "게임 시작"
    flow.build_mode = battle.play_mode == "build"   # after the reset: the preset may have changed the mode
    _reset_input_state()
    _sync_menu()


func _apply_window_mode(mode: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    var want: int = DisplayServer.WINDOW_MODE_FULLSCREEN if mode == "fullscreen" else DisplayServer.WINDOW_MODE_WINDOWED
    if DisplayServer.window_get_mode() != want:
        DisplayServer.window_set_mode(want)


## Buttons and keys call this; the request is applied on the next physics
## frame (see _apply_intents).
func queue_intent(intent: String, arg: Variant = null) -> void:
    _intents.append({"intent": intent, "arg": arg, "state": flow.state_name()})


## Intents issued in a state that is no longer current are dropped (logged in
## `stale_intents`): a pause / restart pressed just before the run ended does
## not override RESULT or start a run, and the second of two rapid clicks
## finds the state already changed and does nothing (WP-004 §1 / §2).
var stale_intents: Array = []


func _apply_intents() -> void:
    if _intents.is_empty():
        return
    var pending: Array = _intents
    _intents = []
    for it: Dictionary in pending:
        if str(it["state"]) != flow.state_name():
            stale_intents.append({"intent": it["intent"], "issued_in": it["state"], "now": flow.state_name(), "tick": battle.steps})
            continue
        _apply_intent(str(it["intent"]), it["arg"])


## One request -> PlayFlow transition -> side effect. Refused requests (wrong
## state, double click, key repeat) are logged by the flow and do nothing.
func _apply_intent(intent: String, arg: Variant) -> void:
    var act: String = PlayFlow.ACT_NONE
    match intent:
        "title_start": act = flow.start_game()
        "title_settings", "pause_settings": act = flow.open_settings()
        "title_quit": act = flow.quit_from_title()
        "pause": act = flow.pause()
        "pause_continue": act = flow.resume()
        "pause_restart", "restart": act = flow.request_restart()
        "pause_to_title": act = flow.request_to_title()
        "settings_back": act = flow.close_settings()
        "settings_window_mode":
            if flow.state == PlayFlow.State.SETTINGS and settings != null:
                var r: Dictionary = settings.toggle_window_mode() if arg == null else settings.set_window_mode(str(arg))
                _apply_window_mode(settings.window_mode)
                menu.set_window_mode_label(settings.window_mode_label())
                menu.set_settings_notice("" if bool(r.get("ok", false)) else "설정 저장 실패: %s (%s) — 이번 세션에는 적용됨" % [str(r.get("path", "")), str(r.get("error", ""))])
        "confirm_ok": act = flow.confirm()
        "confirm_cancel": act = flow.cancel_confirm()
        "result_restart": act = flow.request_restart()
        "result_to_title": act = flow.request_to_title()
        "back": act = flow.back()
        "begin_defense": act = flow.begin_defense()
        _:
            printerr("unknown intent: %s" % intent)
    match act:
        PlayFlow.ACT_NEW_RUN:
            _start_new_run()
        PlayFlow.ACT_TO_TITLE:
            _discard_run_to_title()
        PlayFlow.ACT_QUIT:
            get_tree().quit()
        PlayFlow.ACT_BEGIN_DEFENSE:
            # WP-008: the flow accepted exactly one 방어 시작; the battle leaves
            # its preparation phase in the same frame (waves from 0).
            if battle.begin_defense():
                _clear_field_input()
                _say("방어 시작 — 웨이브 W1 진입. 전투 중에도 물자로 건설할 수 있다")
    _sync_menu()


## A fresh run from the initial data (D-040): same seed and fixture, new
## run_id, no pending input, no pause, no previous result.
func _start_new_run() -> void:
    battle.restart()
    _result_model = {}
    _reset_input_state()
    _sync_terrain_marker()


## Leaving to TITLE discards the current run; the title shows the initial
## field again. Settings are kept.
func _discard_run_to_title() -> void:
    battle.restart()
    _result_model = {}
    _reset_input_state()


## Entering any menu drops the field's pending input (held click, hover,
## preview) so nothing is retried behind the menu (WP-004 §2).
func _clear_field_input() -> void:
    _mouse_down = false
    _mouse_down_run_id = -1
    if _overlay != null:
        _overlay.hover_override = Vector2.INF
        _overlay.preview_override = Vector2i(-1, -1)


func _sync_menu() -> void:
    var st: String = flow.state_name()
    var ctx: Dictionary = {"confirm": flow.confirm_text(), "result": flow.result, "pause_return": PlayFlow.STATE_NAMES[flow.pause_return]}
    if settings != null:
        ctx["window_mode_label"] = settings.window_mode_label()
        if not bool(settings.last_save.get("ok", true)):
            ctx["settings_notice"] = "설정 저장 실패: %s" % str(settings.last_save.get("path", ""))
    menu.show_state(st, ctx)
    var open: bool = flow.menu_open()
    _sync_build_bar()
    if open:
        _clear_field_input()
    elif _menu_was_open:
        # A menu just closed to PLAYING (resume, cancel, new run). Whatever
        # closed it (Esc, Enter on a button, the mouse button on 계속하기, R on
        # RESULT) may still be held: the field stays closed until it is
        # released (R-01). Nothing held -> the fence is empty -> open now.
        _fence = _held.duplicate()
    _menu_was_open = open
    # No HUD before a run exists: TITLE and the settings opened from TITLE.
    var before_run: bool = st == "TITLE" or (st == "SETTINGS" and flow.settings_return == PlayFlow.State.TITLE)
    _hud_layer.visible = _show_hud and not before_run
    if _hud_pause_button != null:
        _hud_pause_button.visible = flow.field_active()


## WP-008: the construction bar follows the flow state (PREPARING / PLAYING
## in build mode only) and the 방어 시작 button exists only while preparing.
func _sync_build_bar() -> void:
    if _build_bar == null:
        return
    var build: bool = battle.play_mode == "build"
    _build_bar.visible = build and (flow.field_active() or flow.bypass)
    if _begin_button != null:
        _begin_button.visible = build and flow.state == PlayFlow.State.PREPARING
    if not build:
        return
    var eco := battle.economy
    for spec: Array in [["build_jangseung", Placement.Kind.JANGSEUNG, "1 장승"], ["build_hwacha", Placement.Kind.HWACHA, "2 화차"],
            ["build_bongsu", Placement.Kind.BONGSU, "3 봉수대"], ["build_sensor", Placement.Kind.SENSOR, "4 혼천의"]]:
        var b: Button = _build_buttons[spec[0]]
        var kind: int = spec[1]
        b.text = "%s %d" % [spec[2], eco.cost_of(kind)]
        b.disabled = false
        b.modulate = Color(1.0, 0.85, 0.4) if _sel_kind == kind else (Color(1, 1, 1, 1) if eco.can_afford(kind) else Color(0.7, 0.7, 0.7, 1))
    var rb: Button = _build_buttons["build_recovery"]
    rb.text = "5 회수 화차 %s" % ("1/1" if battle.run.recovery_right > 0 else ("0/1" if battle.run.collapse_count > 0 else "—"))
    rb.modulate = Color(1.0, 0.85, 0.4) if _sel_kind == SEL_RECOVERY else Color(1, 1, 1, 1)
    var sel: String
    match _sel_kind:
        SEL_NONE: sel = "선택 없음 (1~4 건설, 5 회수)"
        SEL_RECOVERY: sel = "회수 화차 배치 (무료, 내곽만)"
        _: sel = "%s 건설 · 비용 %d" % [Placement.kind_label(_sel_kind), eco.cost_of(_sel_kind)]
    _build_label.text = "물자 %d   시설 %d/%d   %s%s" % [eco.supply, battle.structure_total(), eco.cap, sel,
        "   [준비 중: 시간·생성 정지]" if battle.preparing else ""]


## Selection change (keys 1..5 or the bar buttons). Never a battle command.
func _select_build(kind: int, source: String) -> void:
    if battle.play_mode != "build":
        return
    _sel_kind = kind
    _mouse_down = false   # a selection change drops any pending hold
    if kind == SEL_RECOVERY:
        _say("선택: 회수 화차 배치 (무료 · 내곽 빈 칸 · 누르고 있으면 재시도)")
    else:
        _say("선택: %s 건설 — 비용 %d · 잔액 %d · 클릭 1회에 1개" % [Placement.kind_label(kind), battle.economy.cost_of(kind), battle.economy.supply])
    _sync_build_bar()
    build_clicks.append({"select": kind, "source": source, "tick": battle.steps, "run_id": battle.run.run_id})


## The run just reached WON / LOST while PLAYING: freeze the result model
## from the real ledgers once and show RESULT. Pending pause / restart intents
## are then refused by the flow (RESULT wins, WP-004 §2).
func _check_run_end() -> void:
    if flow.bypass or flow.state != PlayFlow.State.PLAYING or not battle.run.ended():
        return
    _result_model = ResultModel.build(battle)
    flow.run_ended(_result_model)
    _clear_field_input()
    _sync_menu()


# ================================================================== loop ===

func _physics_process(delta: float) -> void:
    if _capture_busy:
        return
    # A run that already ended while PLAYING (only possible when something
    # outside this loop stepped the battle) shows RESULT before any pending
    # pause / restart is applied, so those are dropped as stale (§2, RESULT
    # wins; GPT review 2026-09-19 boundary observation).
    _check_run_end()
    _apply_intents()
    if flow.battle_active() and not _capture_hold:
        var dt: float = config.get_num("fixed_dt")
        for _i: int in range(_sim_speed):
            battle.step(dt)
            _perf_script_step()
            _capture_script_step()
            if _capture_busy or not flow.battle_active():
                break
        _check_run_end()
    else:
        # Menus open: no battle tick, no held-click retry; the capture script
        # (wp004_ui) still advances so it can drive the menus.
        _capture_script_step()
    if flow.field_active() and battle.play_mode == "build":
        _prompt_recovery()
    if _mouse_down and flow.field_active():
        # Held-click retry dispatches by mode exactly like the initial press
        # (Codex review on PR #4: a refused recovery click must never fall
        # through to free construction in the WP-003 run). A hold issued in a
        # previous run is dropped, never retried in the new one (R-03); no
        # retry while the release fence is up (R-01). WP-008: a paid build is
        # never retried (one press = at most one purchase), only the free
        # recovery placement keeps the hold retry.
        if _mouse_down_run_id != battle.run.run_id:
            _mouse_down = false
        elif not _fence.is_empty():
            pass
        elif battle.run_mode == "waves":
            if _recovery_selected():
                _try_recovery_at_cursor()
            else:
                _mouse_down = false
        else:
            _try_place_at_cursor()
    if _notice_timer > 0.0:
        _notice_timer -= delta
        if _notice_timer <= 0.0:
            _notice.text = ""
            _sync_bottom_panel()
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
        if _fx != null:
            # exactly one fire + one impact per real volley (WP-005 AC-04)
            _fx.spawn("fire", shot[2] if shot.size() > 2 else shot[0])
            _fx.spawn("impact", shot[0], shot[1])
    if _fx != null:
        _feed_fx()
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
    _overlay.debug_labels = (not _player_view) or _show_detail
    _overlay.place_mode = _place_mode
    _overlay.build_kind = _sel_kind if battle.play_mode == "build" else SEL_NONE
    _overlay.sim_time = battle.sim_time
    _overlay.queue_redraw()
    if _perf != null:
        var was_measuring: bool = _perf.phase() == "measure"
        _perf.tick(battle.sim.alive_count)
        if was_measuring:
            # The recorder appended this frame (it was measuring on entry), even
            # when this very tick flipped the phase to "done": every global
            # sample lands in exactly one segment (R-05).
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


## WP-005 fx from the battle ledgers: enemy hits / despawns (EnemySim render
## events), the outer collapse (RunState.collapse_count), objective hit
## flashes (HP decrease). Effects follow simulation time, so they freeze with
## the battle and are cleared by _reset_input_state on a restart.
func _feed_fx() -> void:
    var ev: PackedFloat32Array = battle.sim.take_render_events()
    var i: int = 0
    while i + 2 < ev.size():
        var kind: int = int(ev[i + 2])
        if kind == 0:
            _fx.spawn("enemy_despawn", Vector2(ev[i], ev[i + 1]))
        elif kind == 2:
            _fx.spawn("enemy_hit", Vector2(ev[i], ev[i + 1]))
        i += 3
    if battle.run.collapse_count > _fx_collapses_seen:
        _fx.spawn("collapse", battle.grid.cell_center(TestMap.OUTER_GOAL_CELL.x, TestMap.OUTER_GOAL_CELL.y))
        _fx_collapses_seen = battle.run.collapse_count
    if battle.run.outer_hp < _last_outer_hp:
        _overlay.objective_hit_time["outer"] = battle.sim_time
    if battle.run.core_hp < _last_core_hp:
        _overlay.objective_hit_time["core"] = battle.sim_time
    _last_outer_hp = battle.run.outer_hp
    _last_core_hp = battle.run.core_hp
    _fx.advance(battle.sim_time)


func _upload_enemies() -> void:
    if _enemy_sprites:
        _upload_enemy_sprites()
        return
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


## Sample mode: the same single MultiMesh upload, 16 floats per instance
## (transform, white colour, custom = atlas frame), bottom-centre pivot.
func _upload_enemy_sprites() -> void:
    var sim := battle.sim
    var live: PackedInt32Array = sim.live_slots()
    var n: int = live.size()
    var px: PackedFloat32Array = sim.pos_x
    var py: PackedFloat32Array = sim.pos_y
    var flow: PackedInt32Array = battle.path.flow
    var w: int = battle.grid.width
    var phase: int = int(battle.sim_time * 6.0)
    var o: int = 0
    for k: int in range(n):
        var s: int = live[k]
        _buffer[o] = 1.0
        _buffer[o + 1] = 0.0
        _buffer[o + 2] = 0.0
        _buffer[o + 3] = px[s]
        _buffer[o + 4] = 0.0
        _buffer[o + 5] = 1.0
        _buffer[o + 6] = 0.0
        _buffer[o + 7] = py[s]
        _buffer[o + 8] = 1.0
        _buffer[o + 9] = 1.0
        _buffer[o + 10] = 1.0
        _buffer[o + 11] = 1.0
        _buffer[o + 12] = float(_enemy_frame(s, sim, flow, w, phase))
        _buffer[o + 13] = 0.0
        _buffer[o + 14] = 0.0
        _buffer[o + 15] = 0.0
        o += 16
    _multimesh.visible_instance_count = n
    _multimesh.buffer = _buffer


# ================================================================= input ===

## Every event, before the GUI: only the held-input ledger, never a command.
func _input(event: InputEvent) -> void:
    _track_held(event)


static func _input_name(event: InputEvent) -> String:
    if event is InputEventKey:
        var k: InputEventKey = event
        var n: String = OS.get_keycode_string(k.keycode)
        return n if n != "" else "key%d" % k.keycode
    if event is InputEventMouseButton:
        return "mouse%d" % (event as InputEventMouseButton).button_index
    return ""


func _track_held(event: InputEvent) -> void:
    if event is InputEventKey and (event as InputEventKey).echo:
        return
    var n: String = _input_name(event)
    if n == "":
        return
    if event.is_pressed():
        _held[n] = true
    else:
        _held.erase(n)
        _fence.erase(n)


func _fence_refuse(n: String) -> void:
    fenced_inputs.append({"input": n, "fence": _fence.keys(), "tick": battle.steps, "run_id": battle.run.run_id})


func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        # Releases are not delivered to an unfocused window: forget the held
        # inputs rather than keep the field closed forever.
        _held.clear()
        _fence.clear()
        _mouse_down = false


func _unhandled_input(event: InputEvent) -> void:
    if _perf != null or _capture_name != "":
        # Scripted evidence runs must not be perturbed by stray clicks or keys
        # on the foreground window; only Esc is honoured (bypass modes quit,
        # the wp004_ui menu scenario ignores it and drives itself).
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and flow.bypass:
            get_tree().quit()
        return
    _handle_key_event(event)


## The real input handler body, also driven by the wp004_ui capture script
## and the headless flow tests with synthesized events.
func _handle_key_event(event: InputEvent) -> void:
    _track_held(event)
    if flow.menu_open():
        # A menu is open: mouse events are consumed by the Controls (dim
        # rectangle + buttons) before they get here; keys close exactly one
        # level. Nothing reaches the field (WP-004 §2, D-039).
        if event is InputEventKey and event.pressed and not event.echo:
            var mk: InputEventKey = event
            if mk.keycode == KEY_ESCAPE:
                queue_intent("back")
            elif mk.keycode == KEY_R and flow.state == PlayFlow.State.RESULT:
                queue_intent("result_restart")
        var vp: Viewport = get_viewport()
        if vp != null:
            vp.set_input_as_handled()
        return
    var waves_mode: bool = battle.run_mode == "waves"
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.pressed and not _fence.is_empty():
            # R-01: the input that closed the menu is still held. Refuse the
            # press, do not hold it for retry; only a new press after the
            # release is field input.
            _mouse_down = false
            _fence_refuse(_input_name(mb))
            return
        if mb.button_index == MOUSE_BUTTON_LEFT:
            _mouse_down = mb.pressed
            _mouse_down_run_id = battle.run.run_id
            if mb.pressed:
                if waves_mode and battle.play_mode == "build" and not _recovery_selected():
                    # WP-008 AC-04: one paid construction per new press, never
                    # retried while held, never re-bought after a refusal.
                    _mouse_down = false
                    _try_buy_at_cursor()
                elif waves_mode:
                    _try_recovery_at_cursor()
                else:
                    _try_place_at_cursor()
        elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            if battle.play_mode == "build":
                _say("건설 모드에는 철거·판매·환불이 없다 (WP-008)")
            elif waves_mode:
                _say("WP-003 런에서는 시설 철거를 제공하지 않는다 (회수 화차 배치만 가능)")
            else:
                var res: Placement.Result = battle.remove_at_world(get_global_mouse_position())
                if res.ok:
                    _say("제거: %s #%d  (경로 버전 %d)" % [res.structure.label, res.structure.id, battle.path.path_version])
                else:
                    _say("제거 실패: 커서 아래 시설 없음")
    elif event is InputEventKey and event.pressed and not event.echo:
        var key: InputEventKey = event
        if not _fence.is_empty() and key.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_T, KEY_C, KEY_SPACE]:
            _fence_refuse(_input_name(key))   # field commands only; view toggles and menu keys are not fenced
            return
        if battle.play_mode == "build":
            # WP-008: 1..4 pick a kind to buy, 5 the free recovery placement,
            # Space starts the defence (flow refuses it outside PREPARING).
            # The sandbox debug commands (T / C / RMB removal) stay unavailable.
            match key.keycode:
                KEY_1: _select_build(Placement.Kind.JANGSEUNG, "key"); return
                KEY_2: _select_build(Placement.Kind.HWACHA, "key"); return
                KEY_3: _select_build(Placement.Kind.BONGSU, "key"); return
                KEY_4: _select_build(Placement.Kind.SENSOR, "key"); return
                KEY_5: _select_build(SEL_RECOVERY, "key"); return
                KEY_SPACE: queue_intent("begin_defense"); return
                KEY_T, KEY_C:
                    _say("건설 모드에는 활성 전환·전투 토글 디버그 명령이 없다 (WP-008)")
                    return
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
            KEY_L:
                _show_labels = not _show_labels
                _overlay.show_labels = _show_labels
            KEY_G:
                _show_ranges = not _show_ranges
            KEY_P:
                queue_intent("pause")
            KEY_R:
                # D-040: never an immediate reset while playing; the flow opens
                # the restart confirmation (취소 keeps the run untouched).
                queue_intent("restart")
            KEY_H:
                _show_hud = not _show_hud
                _hud_layer.visible = _show_hud
            KEY_D:
                _show_detail = not _show_detail
                _detail.visible = _show_detail
                _sync_bottom_panel()
            KEY_F12:
                _screenshot_to_user()
            KEY_ESCAPE:
                queue_intent("pause")


## R-03: a restart / reset drops everything the previous run left in the
## scene: the held click (and its run id), the pause, pending visuals and the
## scripted overrides. The new run starts running with no pending command.
func _reset_input_state() -> void:
    _mouse_down = false
    _mouse_down_run_id = -1
    _intents.clear()
    _sel_kind = SEL_NONE
    _recovery_prompt_run = -1
    _recent_shots.clear()
    _notice_timer = 0.0
    _notice.text = ""
    _sync_bottom_panel()
    if _overlay != null:
        _overlay.hover_override = Vector2.INF
        _overlay.preview_override = Vector2i(-1, -1)
        _overlay.objective_hit_time = {"outer": -1.0, "core": -1.0}
    # WP-005 AC-04: no effect of the previous run survives a restart.
    if _fx != null:
        _fx.clear()
        _fx.sim_time = battle.sim_time
    _fx_collapses_seen = battle.run.collapse_count
    _last_outer_hp = battle.run.outer_hp
    _last_core_hp = battle.run.core_hp
    battle.sim.take_render_events()
    battle.hwacha.last_shots_for_render()


## World position of the placement cursor. Headless tests / scripts that have
## no viewport set `_cursor_world_override` instead of a real mouse.
var _cursor_world_override: Vector2 = Vector2.INF


func _cursor_world() -> Vector2:
    if _cursor_world_override != Vector2.INF or get_viewport() == null:
        return _cursor_world_override
    return get_global_mouse_position()


## WP-003: the only player placement is the recovered H1 into the inner district.
func _try_recovery_at_cursor() -> void:
    var anchor: Vector2i = battle.placement.anchor_for_world(_cursor_world())
    var res: Placement.Result = battle.place_recovery(anchor)
    if res.ok:
        _mouse_down = false
        _say("회수 화차 배치: %s #%d @%s  부착 %d · 그룹 %d · 재장전 잔여 %.2fs" % [
            res.structure.label, res.structure.id, str(anchor), res.structure.attached_to,
            res.structure.group_id, res.structure.cooldown_left])
    else:
        _say("배치 거절: %s @%s" % [_reason_ko(res.reason), str(anchor)])


static func _reason_ko(reason: int) -> String:
    if reason == Placement.Reject.ENEMY_OCCUPIES_CELL:
        return "적이 점유 중 (누르고 있으면 재시도)"
    return Placement.reject_ko(reason)


## WP-008: true when a click means the free recovery placement (classic run,
## or build mode with 5 / nothing selected).
func _recovery_selected() -> bool:
    return battle.play_mode != "build" or _sel_kind == SEL_RECOVERY or _sel_kind == SEL_NONE


## WP-008: the collapse hands out the recovery right; switch the selection to
## the free placement once per run (the player may switch back to buying).
func _prompt_recovery() -> void:
    if battle.run.recovery_right > 0 and _recovery_prompt_run != battle.run.run_id:
        _recovery_prompt_run = battle.run.run_id
        _sel_kind = SEL_RECOVERY
        _mouse_down = false
        _say("▶ 외곽 붕괴 — 회수 화차 배치로 전환 (무료, 내곽만). 1~4로 유료 건설과 전환 가능")
        _sync_build_bar()


## WP-008: one paid construction at the cursor (one call per press).
func _try_buy_at_cursor() -> void:
    var anchor: Vector2i = battle.placement.anchor_for_world(_cursor_world())
    var kind: int = _sel_kind
    var before: int = battle.economy.supply
    var res: Placement.Result = battle.buy_structure(kind, anchor)
    build_clicks.append({"buy": Placement.kind_name(kind), "anchor": [anchor.x, anchor.y], "ok": res.ok,
        "reason": Placement.reject_name(res.reason), "supply_before": before, "supply_after": battle.economy.supply,
        "tick": battle.steps, "run_id": battle.run.run_id, "preparing": battle.preparing})
    if res.ok:
        _say("건설: %s #%d @%s  −%d → 잔액 %d  (시설 %d/%d%s)" % [res.structure.label, res.structure.id, str(anchor),
            battle.economy.cost_of(kind), battle.economy.supply, battle.structure_total(), battle.economy.cap,
            (", 경로 버전 %d" % battle.path.path_version) if kind == Placement.Kind.JANGSEUNG else ((", 그룹 %d" % res.structure.group_id) if kind == Placement.Kind.BONGSU else (", 부착 %d" % res.structure.attached_to))])
    else:
        var why: String = Placement.reject_ko(res.reason)
        if res.reason == Placement.Reject.INSUFFICIENT_SUPPLY:
            why += " (%d 필요, 잔액 %d)" % [battle.economy.cost_of(kind), battle.economy.supply]
        _say("건설 거절: %s @%s — %s" % [Placement.kind_label(kind), str(anchor), why])
    _sync_build_bar()


func _try_place_at_cursor() -> void:
    var anchor: Vector2i = battle.placement.anchor_for_world(_cursor_world())
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
    _sync_bottom_panel()


## V-01: the bottom-left panel only shows when it has something to say
## (the detail lines, or a notice); an empty dark strip is not left behind.
func _sync_bottom_panel() -> void:
    if _hud_bottom != null:
        _hud_bottom.visible = _show_detail or _notice.text != ""


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
    var detail: PackedStringArray = PackedStringArray()
    if _player_view:
        _update_player_hud(detail)
        return
    lines.append("한양 디펜스 · %s   Godot %s / %s" % [
        ("WP-008 건설·물자 프로토타입 (build)" if battle.play_mode == "build" else "WP-003 검증·붕괴·후퇴·재편 프로토타입") if battle.run_mode == "waves" else "WP-002 봉수망 프로토타입",
        Engine.get_version_info().string, RenderingServer.get_current_rendering_method()
    ])
    lines.append("FPS %3.0f  frame %.1f ms   sim t=%.1fs  x%d%s%s" % [
        _fps_smoothed, _frame_ms_smoothed, battle.sim_time, _sim_speed,
        "  [일시정지]" if flow.state == PlayFlow.State.PAUSED else "", "" if battle.combat_enabled else "  [전투 비활성]"
    ])
    lines.append("동시 생존 %d (최고 %d)   생성 누계 %d   처치 %d   누수 %d" % [
        sim.alive_count, battle.peak_alive, sim.spawned_total, sim.killed_total, sim.leaked_total
    ])
    detail.append("경로별 생존: %s   경로 버전 %d" % [battle.route_summary(), battle.path.path_version])
    var zparts: PackedStringArray = PackedStringArray()
    for z: DensityDetector.Zone in battle.density.zones:
        zparts.append("Z%d %d" % [z.id, battle.density.counts[z.id]])
    detail.append("밀도: " + "  ".join(zparts))
    var hparts: PackedStringArray = PackedStringArray()
    for s: Placement.Structure in battle.placement.hwachas():
        hparts.append("%s→%s %d발/%d처치" % [
            s.label, ("Z%d" % s.last_zone) if s.last_zone >= 0 else "--", s.shots_fired, s.kills
        ])
    detail.append("화차: " + "   ".join(hparts))
    detail.append("장승 %d   화차 %d   거절 누계 %d   설치 모드 [%s]" % [
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
        lines.append("%s 런 #%d  %s / %s%s" % ["건설(WP-008)" if battle.play_mode == "build" else "WP-003", rs.run_id, rs.run_name(), "외곽 방어 중" if rs.defense == 0 else "내곽 방어 (외곽 붕괴)", end_txt])
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
        if battle.play_mode == "build":
            var eco := battle.economy
            lines.append("건설 모드 (WP-008)  물자 %d = 시작 %d + 처치 %d + 웨이브 %d − 소비 %d%s   구매 %d   시설 %d/%d" % [
                eco.supply, eco.start_supply, eco.earned_kills, eco.earned_waves, eco.spent,
                (" + 주입 %d[벤치마크]" % eco.injected) if eco.injected > 0 else "", eco.purchases.size(), battle.structure_total(), eco.cap])
            if battle.preparing:
                lines.append("▶ 준비 중: 시간·생성·웨이브 정지. 시설을 고르고(1~4) 빈 칸을 클릭해 배치한 뒤 [방어 시작]을 누른다")
    detail.append("봉수망 [%s]: 봉수대 %d(활성 %d) 센서 %d 간선 %d 그룹 %s 위상 v%d | 공유전용 사격 %d" % [
        battle.targeting_mode, battle.placement.count_of(Placement.Kind.BONGSU),
        _active_of(Placement.Kind.BONGSU), battle.placement.count_of(Placement.Kind.SENSOR),
        net["link_count"], str(net["groups"]), net["topology_version"], battle.hwacha.shared_only_shots
    ])
    detail.append("화차 인지: " + "  ".join(nparts))
    if battle.play_mode == "build":
        lines.append("1~4 건설 선택  5 회수 화차  LMB 클릭 1회 = 1개 구매(홀드 재시도 없음; 회수 배치만 재시도)  Space 방어 시작  Esc/P 일시정지  R 재시작(확인)  Z 밀도  G 사거리  H HUD  D 상세  F12 캡처")
    elif battle.run_mode == "waves":
        lines.append("LMB 회수 화차 배치(내곽)  Esc/P 일시정지  R 재시작(확인)  Z 밀도  G 사거리  H HUD  D 상세  F12 캡처   (자유 설치/철거/T/C는 WP-003 런에서 비활성)")
    else:
        lines.append("LMB 설치  RMB 제거  1장승 2화차 3봉수대 4혼천의  T 활성전환  C 전투  Z 밀도  G 사거리  Esc/P 일시정지  R 초기화(확인)  H HUD  D 상세  F12 캡처")
    _hud.text = "\n".join(lines)
    _detail.text = "\n".join(detail)


# ============================================================ V-01 view ===
# D-053 / docs/art/WP005_VISUAL_REVISION_PLAN.md V-01: the default display of
# a normal launch. Nothing here changes the battle; it only picks what the
# HUD / overlay show by default. The developer view is the previous display.

const WAVE_STATE_KO: Dictionary = {"SPAWNING": "진격 중", "WAITING_CLEAR": "잔적 정리", "GAP": "다음 웨이브 대기", "DONE": "모든 웨이브 종료"}


## Top HUD font: 18 px in the player view (about 12 px at 1280x720, where the
## 15 px developer HUD shrinks to 10 px), 15 px in the developer view.
const HUD_FONT_PLAYER: int = 18
const HUD_FONT_DEV: int = 15


func _set_player_view(on: bool) -> void:
    _player_view = on
    if _hud != null:
        _hud.add_theme_font_size_override("font_size", HUD_FONT_PLAYER if on else HUD_FONT_DEV)
    _show_zones = not on
    _show_ranges = not on
    _show_detail = not on
    if _detail != null:
        _detail.visible = _show_detail
        _sync_bottom_panel()
    if _overlay != null:
        _overlay.show_zones = _show_zones
        _overlay.show_ranges = _show_ranges
        _overlay.debug_labels = (not on) or _show_detail


## Player view: what to defend, how it goes, what to do next. The developer
## lines (engine, FPS, counters, zones, per-hwacha, network) go to the detail
## panel, which D opens.
func _update_player_hud(detail: PackedStringArray) -> void:
    var sim := battle.sim
    var lines: PackedStringArray = PackedStringArray()
    if battle.run_mode == "waves":
        var rs := battle.run
        var ws: Dictionary = battle.waves.snapshot()
        var state: String = WAVE_STATE_KO.get(str(ws["state"]), str(ws["state"]))
        if str(ws["state"]) == "GAP":
            state += " %.0fs" % maxf(float(ws["gap_left"]), 0.0)
        var head: String = "웨이브 %s/%d · %s · %s" % [str(ws["wave_name"]).trim_prefix("W"), (ws["spawned_by_wave"] as Array).size(),
            state, "외곽 방어 중" if rs.defense == 0 else "외곽 붕괴 — 내곽 방어"]
        if rs.run == 1:
            head = "★ 승리 — 핵심 시설 사수 · R 다시 시작"
        elif rs.run == 2:
            head = "✖ 패배 — 핵심 시설 함락 · R 다시 시작"
        var build: bool = battle.play_mode == "build"
        if build and battle.preparing and not rs.ended():
            head = "준비 단계 — 시간·웨이브 정지 · 시설을 고르고(1~4) 빈 칸을 클릭한 뒤 Space로 방어 시작"
        if flow.state == PlayFlow.State.PAUSED:
            head += "   [일시정지]"
        lines.append(head)
        lines.append("외곽 거점 HP %.0f/%.0f · 핵심 시설 HP %.0f/%.0f · 처치 %d · 도달 %d" % [
            rs.outer_hp, rs.outer_hp_max, rs.core_hp, rs.core_hp_max, sim.killed_total, rs.outer_arrivals + rs.core_arrivals])
        if build:
            # WP-008 in the player view: the balance and what earns more, the
            # structure count against the cap (the ledger formula is in D).
            var eco := battle.economy
            lines.append("물자 %d (처치 +%d · 웨이브 완료 +%d) · 시설 %d/%d · 구매 %d" % [eco.supply, eco.kill_reward, eco.wave_reward,
                battle.structure_total(), eco.cap, eco.purchases.size()])
        if rs.collapse_count == 0:
            lines.append("외곽 거점이 무너지면 화차·중영 1대를 회수해 내곽(노란 테두리)에 다시 놓을 수 있다")
        elif rs.recovery_right > 0:
            lines.append("▶ 외곽 붕괴! 회수한 화차·중영을 내곽 빈 칸에 클릭해 배치 (누르고 있으면 재시도)")
        else:
            lines.append("회수 화차 재배치 완료 %s" % str(rs.recovery_anchor))
        if build:
            lines.append("1~4 건설 · 5 회수 화차 · 클릭 1회 = 1개 구매%s · Esc 일시정지 · R 다시 시작 · D 상세" % [" · Space 방어 시작" if battle.preparing else ""])
        else:
            lines.append("Esc 일시정지 · R 다시 시작 · L 이름 · Z 밀도 · G 사거리 · D 상세 · H HUD · F12 캡처")
    else:
        lines.append("동시 생존 %d · 처치 %d · 누수 %d%s" % [sim.alive_count, sim.killed_total, sim.leaked_total,
            "   [일시정지]" if flow.state == PlayFlow.State.PAUSED else ""])
        lines.append("LMB 설치 · RMB 제거 · 1장승 2화차 3봉수대 4혼천의 · T 활성 · C 전투 · Esc 일시정지 · R 초기화 · Z 밀도 · G 사거리 · D 상세")
    detail.append("한양 디펜스 · %s   Godot %s / %s" % ["WP-003 검증·붕괴·후퇴·재편 프로토타입" if battle.run_mode == "waves" else "WP-002 봉수망 프로토타입",
        Engine.get_version_info().string, RenderingServer.get_current_rendering_method()])
    detail.append("FPS %3.0f  frame %.1f ms   sim t=%.1fs  x%d%s" % [_fps_smoothed, _frame_ms_smoothed, battle.sim_time, _sim_speed,
        "" if battle.combat_enabled else "  [전투 비활성]"])
    detail.append("동시 생존 %d (최고 %d)   생성 누계 %d   처치 %d   누수 %d" % [sim.alive_count, battle.peak_alive, sim.spawned_total,
        sim.killed_total, sim.leaked_total])
    detail.append("경로별 생존: %s   경로 버전 %d" % [battle.route_summary(), battle.path.path_version])
    var hparts: PackedStringArray = PackedStringArray()
    for s: Placement.Structure in battle.placement.hwachas():
        hparts.append("%s g%d 로컬%d/공유%d → %s %d발/%d처치%s" % [s.label.trim_prefix("화차·"), s.group_id, s.known_local, s.known_shared,
            ("Z%d" % s.last_zone) if s.last_zone >= 0 else "--", s.shots_fired, s.kills, "" if s.active else "[비활성]"])
    detail.append("화차: " + "  ".join(hparts))
    detail.append("봉수망: 봉수대 %d(활성 %d) · 그룹 %s · 공유전용 사격 %d" % [battle.placement.count_of(Placement.Kind.BONGSU),
        _active_of(Placement.Kind.BONGSU), str(battle.network.snapshot(battle.placement)["groups"]), battle.hwacha.shared_only_shots])
    if battle.play_mode == "build":
        var e2 := battle.economy
        detail.append("장부: 물자 %d = 시작 %d + 처치 %d + 웨이브 %d − 소비 %d%s" % [e2.supply, e2.start_supply, e2.earned_kills,
            e2.earned_waves, e2.spent, (" + 주입 %d[벤치마크]" % e2.injected) if e2.injected > 0 else ""])
    _hud.text = "\n".join(lines)
    _detail.text = "\n".join(detail)


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
## H1's own shot counter right after the recovery placement (R-05: the
## "shots after placement" figure is H1's delta, not a cross-hwacha subtraction).
var _col_h1_shots_at_placement: int = -1
var _col_h1_kills_at_placement: int = -1
## Global measured-frame index (0-based) so every segment can name the raw
## frame range it covers and a reviewer can recompute it from frame_us_raw.
var _col_frame_index: int = -1
var _perf_structures_at_start: Array = []


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
            "alive_min": 999999, "sim_time_start": battle.sim_time,
            "frame_index_start": -1, "frame_index_end": -1, "t_measure_start": -1.0, "t_measure_end": -1.0}
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


## D-027 transition scenarios: WP-003/004/005 collapse_* and the WP-008 build_*
## variants share the trigger / recovery script and the segment ledger.
func _is_transition_perf() -> bool:
    return _perf != null and (_perf.scenario.begins_with("collapse") or _perf.scenario.begins_with("build"))


## WP-008 AC-08 setup (before the perf starts, during the preparation phase):
## buy the extra structures with the injected benchmark supply.
##   build_full_*: 24 from the start, hwacha-heavy (12 hwacha, 5 bongsu, 5 sensors, 2 jangseung)
##   build_grow_*: 22 network-heavy (6 hwacha, 8 bongsu, 6 sensors, 2 jangseung), 2 bought in the measure
var _perf_build_plan: Array = []
var _perf_build_log: Array = []


const BUILD_PERF_SETUP_FULL: Array = [
    [Placement.Kind.HWACHA, Vector2i(30, 25)], [Placement.Kind.HWACHA, Vector2i(64, 25)],
    [Placement.Kind.HWACHA, Vector2i(34, 18)], [Placement.Kind.HWACHA, Vector2i(38, 18)],
    [Placement.Kind.HWACHA, Vector2i(58, 18)], [Placement.Kind.HWACHA, Vector2i(62, 18)],
    [Placement.Kind.HWACHA, Vector2i(34, 27)], [Placement.Kind.HWACHA, Vector2i(38, 27)],
    [Placement.Kind.HWACHA, Vector2i(58, 27)], [Placement.Kind.HWACHA, Vector2i(62, 27)],
    [Placement.Kind.BONGSU, Vector2i(34, 21)], [Placement.Kind.BONGSU, Vector2i(42, 21)],
    [Placement.Kind.BONGSU, Vector2i(50, 21)], [Placement.Kind.BONGSU, Vector2i(58, 21)],
    [Placement.Kind.SENSOR, Vector2i(30, 27)], [Placement.Kind.SENSOR, Vector2i(62, 29)],
    [Placement.Kind.SENSOR, Vector2i(47, 15)], [Placement.Kind.SENSOR, Vector2i(50, 12)],
    [Placement.Kind.JANGSEUNG, Vector2i(44, 36)], [Placement.Kind.JANGSEUNG, Vector2i(22, 24)],
]
const BUILD_PERF_SETUP_GROW: Array = [
    [Placement.Kind.HWACHA, Vector2i(30, 25)], [Placement.Kind.HWACHA, Vector2i(64, 25)],
    [Placement.Kind.HWACHA, Vector2i(34, 18)], [Placement.Kind.HWACHA, Vector2i(62, 18)],
    [Placement.Kind.BONGSU, Vector2i(34, 21)], [Placement.Kind.BONGSU, Vector2i(42, 21)],
    [Placement.Kind.BONGSU, Vector2i(50, 21)], [Placement.Kind.BONGSU, Vector2i(58, 21)],
    [Placement.Kind.BONGSU, Vector2i(34, 29)], [Placement.Kind.BONGSU, Vector2i(42, 29)],
    [Placement.Kind.BONGSU, Vector2i(58, 29)],
    [Placement.Kind.SENSOR, Vector2i(30, 27)], [Placement.Kind.SENSOR, Vector2i(62, 27)],
    [Placement.Kind.SENSOR, Vector2i(47, 15)], [Placement.Kind.SENSOR, Vector2i(50, 12)],
    [Placement.Kind.SENSOR, Vector2i(38, 18)],
    [Placement.Kind.JANGSEUNG, Vector2i(44, 36)], [Placement.Kind.JANGSEUNG, Vector2i(22, 24)],
]
## Measured-window purchases (t_measure, kind, anchor). The grow variant buys a
## 장승 (path rebuild) and a 화차 (-> 24); both variants then attempt one more
## purchase that the cap must refuse. Plaza corner cells: a lane cell stays
## enemy-occupied for the whole window at 1,000 alive (first run: 1,530
## refusals at (22,28)), and the plaza is lost after the 20 s collapse.
const BUILD_PERF_MEASURE_GROW: Array = [
    [5.0, Placement.Kind.JANGSEUNG, Vector2i(31, 17)],
    [10.0, Placement.Kind.HWACHA, Vector2i(64, 17)],
    [12.0, Placement.Kind.HWACHA, Vector2i(36, 24)],
]
const BUILD_PERF_MEASURE_FULL: Array = [
    [5.0, Placement.Kind.HWACHA, Vector2i(38, 27)],
]


func _setup_build_perf() -> void:
    var full: bool = _perf.scenario.begins_with("build_full")
    var setup: Array = BUILD_PERF_SETUP_FULL if full else BUILD_PERF_SETUP_GROW
    _perf_build_plan = (BUILD_PERF_MEASURE_FULL if full else BUILD_PERF_MEASURE_GROW).duplicate(true)
    for e: Array in setup:
        var res: Placement.Result = battle.buy_structure(e[0], e[1])
        _perf_build_log.append({"phase": "setup", "kind": Placement.kind_name(e[0]), "anchor": [e[1].x, e[1].y],
            "ok": res.ok, "reason": Placement.reject_name(res.reason), "supply": battle.economy.supply})
        if not res.ok:
            printerr("perf build setup: %s at %s refused: %s" % [Placement.kind_name(e[0]), str(e[1]), Placement.reject_name(res.reason)])
    battle.begin_defense()


## Purchases inside the measured window; a refusal (enemy on the cell) is
## retried on the next tick as a NEW command and every attempt is logged,
## a cap refusal is final.
func _perf_build_step(t: float) -> void:
    if _perf_build_plan.is_empty():
        return
    var next: Array = _perf_build_plan[0]
    if t < float(next[0]):
        return
    var res: Placement.Result = battle.buy_structure(next[1], next[2])
    _perf_build_log.append({"phase": "measure", "t_measure": t, "tick": battle.steps, "kind": Placement.kind_name(next[1]),
        "anchor": [next[2].x, next[2].y], "ok": res.ok, "reason": Placement.reject_name(res.reason),
        "supply": battle.economy.supply, "total": battle.structure_total(), "path_version": battle.path.path_version})
    if res.ok or res.reason != Placement.Reject.ENEMY_OCCUPIES_CELL:
        _perf_build_plan.pop_front()
    if res.ok and next[1] == Placement.Kind.JANGSEUNG:
        _perf_rebuilds += 1


func _perf_collapse_step() -> void:
    if _perf.phase() != "measure":
        return
    var t: float = _perf.elapsed_in_phase()
    if _perf.scenario.begins_with("build"):
        _perf_build_step(t)
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
        var h1p: Placement.Structure = battle.placement.get_any(battle.run.recovery_target_id)
        if h1p != null:
            _col_h1_shots_at_placement = h1p.shots_fired
            _col_h1_kills_at_placement = h1p.kills
        _col_state_snapshot("after_placement_25s", t)


## Per-frame segment sampling for the collapse scenarios (called from _process).
## The caller guarantees the recorder was measuring when this frame was
## ticked; the phase may already read "done" for the very last frame, which
## still belongs to the last segment (R-05: segments cover every frame).
func _col_sample_frame(frame_us: int) -> void:
    if not _is_transition_perf():
        return
    var t: float = _perf.elapsed_in_phase()
    _col_frame_index += 1
    var seg: Dictionary = _col_segment(_col_seg_name(t))
    if int(seg["frame_index_start"]) < 0:
        seg["frame_index_start"] = _col_frame_index
        seg["t_measure_start"] = t
    seg["frame_index_end"] = _col_frame_index
    seg["t_measure_end"] = t
    seg["frames"] = int(seg["frames"]) + 1
    (seg["frame_us"] as Array).append(frame_us)
    seg["alive_min"] = mini(int(seg["alive_min"]), battle.sim.alive_count)


func _perf_script_step() -> void:
    if _perf == null:
        return
    _perf_collect_shots()
    if _is_transition_perf():
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
    if not _is_transition_perf():
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
    var seg_frames: int = 0
    for k: Variant in segs:
        seg_frames += int((segs[k] as Dictionary)["frames"])
    var global_frames: int = _perf.frames()
    return {
        # R-05: every global measured frame is in exactly one contiguous segment
        # (frame_index_start..end are indices into frame_us_raw / alive_raw).
        "global_frames": global_frames,
        "segments_frames_total": seg_frames,
        "segments_cover_all_frames": seg_frames == global_frames,
        "trigger_tick": _col_trigger_tick,
        "collapse_tick": battle.run.collapse_tick,
        "collapse_sim_time": battle.run.collapse_sim_time,
        "ticks_trigger_to_collapse": (battle.run.collapse_tick - _col_trigger_tick) if battle.run.collapse_tick >= 0 else -1,
        "placement_tick": placed_tick,
        "ticks_collapse_to_placement": (placed_tick - battle.run.collapse_tick) if placed_tick >= 0 and battle.run.collapse_tick >= 0 else -1,
        "placement_attempts": _col_place_attempts,
        "placement_result": _col_place_result,
        "placement_anchor": [TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y],
        # R-05: H1's own counter delta since the placement (was wrongly derived
        # from the all-hwacha shots_total before).
        "h1_shots_at_placement": _col_h1_shots_at_placement,
        "h1_kills_at_placement": _col_h1_kills_at_placement,
        "h1_shots_after_placement": (h1.shots_fired - _col_h1_shots_at_placement) if h1 != null and _col_h1_shots_at_placement >= 0 else -1,
        "h1_kills_after_placement": (h1.kills - _col_h1_kills_at_placement) if h1 != null and _col_h1_kills_at_placement >= 0 else -1,
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
        # WP-008 AC-08: the construction commands of the benchmark and the ledger
        "build_commands": _perf_build_log.duplicate(true),
        "build_commands_pending": _perf_build_plan.size(),
    }


## Structures as the placement holds them right now (on the map + detached).
func _structure_manifest() -> Array:
    var out: Array = []
    var ids: Array = battle.placement.structures.keys()
    ids.sort()
    for id: int in ids:
        var st: Placement.Structure = battle.placement.structures[id]
        out.append({"id": st.id, "kind": Placement.kind_name(st.kind), "label": st.label,
            "anchor": [st.anchor.x, st.anchor.y], "center": [st.center.x, st.center.y],
            "district": st.district, "active": st.active, "detached": false})
    var dids: Array = battle.placement.detached.keys()
    dids.sort()
    for id: int in dids:
        var d: Placement.Structure = battle.placement.detached[id]
        out.append({"id": d.id, "kind": Placement.kind_name(d.kind), "label": d.label,
            "anchor": [d.anchor.x, d.anchor.y], "center": [d.center.x, d.center.y],
            "district": d.district, "active": d.active, "detached": true})
    return out


## The commands each scripted scenario issues (so the manifest names the real
## anchors: WP-001 combat (44,36), WP-002 network_combat (22,28), WP-003 B (44,13)).
func _scripted_command_manifest() -> Dictionary:
    if _perf == null:
        return {}
    match _perf.scenario:
        "combat":
            var a: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_west_lane"]
            return {"jangseung_anchor": [a.x, a.y], "cadence": "remove at 10 s wall cadence, re-place 1.5 s later"}
        "network_combat":
            return {"jangseung_anchor": [22, 28], "b8_toggle_every_s": 5.0, "events": 12}
        "collapse_move", "collapse_combat":
            return {"trigger_t_measure": 20.0, "trigger_outer_hp": 1.0, "trigger_enemy": [950.0, 530.0],
                "recovery_t_measure": 25.0, "recovery_anchor": [TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y],
                "waves_enabled": battle.waves.enabled}
        "build_full_move", "build_full_combat", "build_grow_move", "build_grow_combat":
            var plan: Array = []
            for e: Array in (BUILD_PERF_MEASURE_FULL if _perf.scenario.begins_with("build_full") else BUILD_PERF_MEASURE_GROW):
                plan.append({"t_measure": e[0], "kind": Placement.kind_name(e[1]), "anchor": [e[2].x, e[2].y]})
            return {"trigger_t_measure": 20.0, "trigger_outer_hp": 1.0, "trigger_enemy": [950.0, 530.0],
                "recovery_t_measure": 25.0, "recovery_anchor": [TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y],
                "waves_enabled": battle.waves.enabled, "play_mode": battle.play_mode,
                "benchmark_supply": config.get_int("benchmark_supply"), "structure_cap": battle.economy.cap,
                "setup_purchases": (BUILD_PERF_SETUP_FULL if _perf.scenario.begins_with("build_full") else BUILD_PERF_SETUP_GROW).size(),
                "measure_purchases": plan}
        _:
            return {}


## Hash and size of the running executable (basename only: no local paths in
## evidence). In an editor run this is the editor binary and says so.
func _executable_manifest() -> Dictionary:
    var exe: String = OS.get_executable_path()
    var out: Dictionary = {"basename": exe.get_file(), "is_editor_binary": OS.has_feature("editor"),
        "sha256": "", "size_bytes": -1}
    if FileAccess.file_exists(exe):
        out["sha256"] = FileAccess.get_sha256(exe)
        var f: FileAccess = FileAccess.open(exe, FileAccess.READ)
        if f != null:
            out["size_bytes"] = f.get_length()
            f.close()
    return out


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
        "art_mode": _art_mode,
        "art": _art_report,
        "enemy_outline": _enemy_outline,
        "fx": _fx.snapshot() if _fx != null else {},
        "targeting_mode": battle.targeting_mode,
        "fixture": config.get_str("fixture"),
        "play_mode": battle.play_mode,
        "economy": battle.economy.snapshot(),
        "structure_total": battle.structure_total(),
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
        # R-05: the manifest is generated from the LIVE run (zones the detector
        # holds, structures as placed at perf start and at the end), plus the
        # executable's hash so the build behind the numbers is provable.
        "manifest": {
            "implementation_sha": _build_sha,
            "executable": _executable_manifest(),
            "config": config.to_dictionary(),
            "fixture": config.get_str("fixture"),
            "zone_set": battle.zone_set,
            "zones": battle.zone_state(),
            "structures_at_start": _perf_structures_at_start,
            "structures_at_end": _structure_manifest(),
            "scripted_commands": _scripted_command_manifest(),
            "b8_id": battle.placement.bongsus()[7].id if battle.placement.bongsus().size() >= 8 else -1,
            "s3_id": _s3().id if _s3() != null else -1,
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
        "wp003_f3a", "wp003_f3b":
            # WP-003 F3 (D-026, R-06): the controlled A/B comparison exactly as
            # tests/test_collapse_retreat.gd runs it (jitter 0, lane offset 0,
            # H4 off, waves off, forced collapse at tick 0, placement at
            # collapse + 300 ticks, 12 enemies at (950,450) the next tick,
            # 30 s of observation) with real renders and per-entity evidence.
            _apply_mode_preset(Config.for_wp003())
            if not _explicit_sets.has("enemy_speed_jitter"):
                config.values["enemy_speed_jitter"] = 0.0
            if not _explicit_sets.has("enemy_lane_offset"):
                config.values["enemy_lane_offset"] = 0.0
            battle.reset()
            battle.waves.enabled = false
            var h4_off: bool = battle.set_active(4, false)
            battle.force_outer_hp(1.0, "F3 forced collapse")
            battle.spawn_extra(Vector2(950.0, 530.0), 1, "F3 trigger enemy")
            _capture_log.append({"t": battle.sim_time, "f3_setup": _capture_name, "h4_deactivated": h4_off,
                "enemy_speed_jitter": config.get_num("enemy_speed_jitter"), "enemy_lane_offset": config.get_num("enemy_lane_offset"),
                "waves_enabled": battle.waves.enabled, "outer_hp": battle.run.outer_hp})
            _sim_speed = 6
            var variant: String = "a" if _capture_name.ends_with("a") else "b"
            var anchor: Vector2i = TestMap.RECOVERY_A if variant == "a" else TestMap.RECOVERY_B
            var pfx: String = "wp003_f3%s" % variant
            _capture_steps = [
                {"t": 0.0, "do": "f3_check_collapse"},
                {"t": 0.0, "do": "capture", "name": pfx + "_1_collapsed_t0"},
                {"t": 5.0, "do": "place_recovery", "anchor": anchor},
                {"t": 5.0, "do": "f3_spawn_group"},
                {"t": 5.0, "do": "f3_state", "label": "setup_after_placement"},
                {"t": 5.0, "do": "hover", "label": "화차·중영"},
                {"t": 5.0, "do": "capture", "name": pfx + "_2_placed_t5"},
                {"t": 5.0, "do": "hover", "label": ""},
                {"t": 5.01, "do": "f3_first_observation"},
                {"t": 5.01, "do": "f3_state", "label": "first_observation"},
                {"t": 5.01, "do": "capture", "name": pfx + "_3_first_observation_t5.02"},
                {"t": 5.01, "do": "f3_capture_on_h1_shot", "name": pfx + "_4_first_h1_shot", "deadline": 35.0},
                {"t": 35.0, "do": "f3_state", "label": "end_of_observation"},
                {"t": 35.0, "do": "f3_end"},
                {"t": 35.0, "do": "capture", "name": pfx + "_5_end_t35"},
                {"t": 35.0, "do": "quit"},
            ]
        "wp004_ui", "wp004_ui_720":
            # WP-004 AC-07 / AC-01 evidence: the real menu flow driven by real
            # key events and the real Button nodes at 1920x1080 (wp004_ui) or
            # 1280x720 (wp004_ui_720). Verification-only battle controls
            # (force_outer_hp / spawn_extra / force_core_hp) are used to reach
            # a collapse and a LOST quickly; they are logged, never exposed in
            # the menus. Times ("t") are battle simulation seconds; menu steps
            # run once per physics frame while a menu is open.
            _apply_mode_preset(Config.for_wp003())
            if _capture_name == "wp004_ui_720":
                DisplayServer.window_set_size(Vector2i(1280, 720))
            _sim_speed = 6
            var pfx: String = "wp004_ui" if _capture_name == "wp004_ui" else "wp004_ui_720"
            _capture_steps = [
                {"t": 0.0, "do": "ui_state_log", "label": "launch"},
                {"t": 0.0, "do": "capture", "name": pfx + "_01_title"},
                {"t": 0.0, "do": "button", "intent": "title_settings"},
                {"t": 0.0, "do": "capture", "name": pfx + "_02_settings_from_title"},
                {"t": 0.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 0.0, "do": "ui_state_log", "label": "settings_esc_returns_to_title"},
                {"t": 0.0, "do": "button", "intent": "title_start"},
                {"t": 12.0, "do": "capture", "name": pfx + "_03_playing_t12"},
                {"t": 12.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 12.0, "do": "ui_state_log", "label": "esc_pauses"},
                {"t": 12.0, "do": "capture", "name": pfx + "_04_paused"},
                {"t": 12.0, "do": "button", "intent": "pause_settings"},
                {"t": 12.0, "do": "capture", "name": pfx + "_05_settings_from_pause"},
                {"t": 12.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 12.0, "do": "ui_state_log", "label": "settings_esc_returns_to_pause"},
                {"t": 12.0, "do": "button", "intent": "pause_restart"},
                {"t": 12.0, "do": "capture", "name": pfx + "_06_confirm_restart"},
                {"t": 12.0, "do": "button", "intent": "confirm_cancel"},
                {"t": 12.0, "do": "ui_state_log", "label": "confirm_cancel_returns_to_pause"},
                {"t": 12.0, "do": "button", "intent": "pause_to_title"},
                {"t": 12.0, "do": "capture", "name": pfx + "_07_confirm_to_title"},
                {"t": 12.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 12.0, "do": "ui_state_log", "label": "confirm_esc_cancels_only"},
                {"t": 12.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 12.0, "do": "ui_state_log", "label": "pause_esc_resumes"},
                {"t": 12.0, "do": "fence_probe", "anchor": TestMap.RECOVERY_B},
                {"t": 12.0, "do": "ui_state_log", "label": "fence_probe_before_collapse"},
                {"t": 20.0, "do": "force_outer_hp", "value": 1.0, "why": "wp004_ui forced collapse (verification only)"},
                {"t": 20.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "wp004_ui trigger enemy"},
                {"t": 22.0, "do": "key", "keycode": KEY_R},
                {"t": 22.0, "do": "ui_state_log", "label": "r_while_playing_opens_confirm"},
                {"t": 22.0, "do": "capture", "name": pfx + "_08_confirm_from_r_after_collapse"},
                {"t": 22.0, "do": "button", "intent": "confirm_cancel"},
                {"t": 22.0, "do": "ui_state_log", "label": "confirm_cancel_resumes_playing"},
                {"t": 26.0, "do": "force_core_hp", "value": 1.0, "why": "wp004_ui forced LOST (verification only)"},
                {"t": 26.0, "do": "spawn_extra", "pos": Vector2(950.0, 210.0), "count": 1, "why": "wp004_ui last arrival"},
                {"t": 26.0, "do": "wait_result"},
                {"t": 26.0, "do": "capture", "name": pfx + "_09_result_lost"},
                {"t": 26.0, "do": "key", "keycode": KEY_R},
                # a new run starts at sim time 0: the times below are relative to it
                {"t": 0.0, "do": "ui_state_log", "label": "r_on_result_restarts_immediately"},
                {"t": 20.0, "do": "force_outer_hp", "value": 1.0, "why": "wp004_ui forced collapse for the WON result"},
                {"t": 20.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "wp004_ui trigger enemy"},
                {"t": 25.0, "do": "fence_probe", "anchor": TestMap.RECOVERY_B},
                {"t": 25.0, "do": "ui_state_log", "label": "fence_probe_done"},
                {"t": 25.0, "do": "wait_result"},
                {"t": 25.0, "do": "capture", "name": pfx + "_10_result_won"},
                {"t": 25.0, "do": "button", "intent": "result_to_title"},
                {"t": 0.0, "do": "ui_state_log", "label": "result_to_title_immediate"},
                {"t": 0.0, "do": "capture", "name": pfx + "_11_title_again"},
                {"t": 0.0, "do": "quit"},
            ]
        "wp008_build", "wp008_build_720":
            # WP-008 AC-07: the real build-mode flow (TITLE -> PREPARING -> 방어 시작
            # -> battle -> collapse -> free recovery -> inner purchase -> RESULT)
            # driven by the real HUD buttons and real key / mouse events, at
            # 1920x1080 or 1280x720. The collapse is forced with the verification
            # hooks (logged, never in the menus) so the run stays short.
            _apply_mode_preset(Config.for_wp008())
            if _capture_name.ends_with("_720"):
                DisplayServer.window_set_size(Vector2i(1280, 720))
            _sim_speed = 6
            var pb: String = _capture_name
            _capture_steps = [
                {"t": 0.0, "do": "ui_state_log", "label": "launch"},
                {"t": 0.0, "do": "button", "intent": "title_start"},
                {"t": 0.0, "do": "ui_state_log", "label": "start_goes_to_preparing"},
                {"t": 0.0, "do": "econ_log", "label": "preparing_start"},
                {"t": 0.0, "do": "state_log", "label": "preparing_start"},
                {"t": 0.0, "do": "capture", "name": pb + "_01_preparing"},
                {"t": 0.0, "do": "hud_button", "name": "build_hwacha"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(40, 20)},
                {"t": 0.0, "do": "capture", "name": pb + "_02_preview_hwacha_cost"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(31, 17)},
                {"t": 0.0, "do": "capture", "name": pb + "_02b_no_target_zone"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(37, 27)},
                {"t": 0.0, "do": "capture", "name": pb + "_02c_zone_not_detectable"},
                {"t": 0.0, "do": "lmb_at", "anchor": Vector2i(40, 20)},
                {"t": 0.0, "do": "hud_button", "name": "build_jangseung"},
                {"t": 0.0, "do": "lmb_at", "anchor": Vector2i(44, 36)},
                {"t": 0.0, "do": "hud_button", "name": "build_bongsu"},
                {"t": 0.0, "do": "lmb_at", "anchor": Vector2i(42, 21)},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 0.0, "do": "econ_log", "label": "after_preparation_purchases"},
                {"t": 0.0, "do": "state_log", "label": "after_preparation_purchases"},
                {"t": 0.0, "do": "capture", "name": pb + "_03_bought_in_preparation"},
                {"t": 0.0, "do": "hud_button", "name": "build_hwacha"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(52, 20)},
                {"t": 0.0, "do": "capture", "name": pb + "_04_insufficient_supply"},
                {"t": 0.0, "do": "lmb_at", "anchor": Vector2i(52, 20)},
                {"t": 0.0, "do": "hud_button", "name": "build_jangseung"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(45, 15)},
                {"t": 0.0, "do": "capture", "name": pb + "_05_invalid_terrain"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(46, 29)},
                {"t": 0.0, "do": "capture", "name": pb + "_06_invalid_overlap"},
                {"t": 0.0, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 0.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 0.0, "do": "ui_state_log", "label": "esc_pauses_preparing"},
                {"t": 0.0, "do": "capture", "name": pb + "_07_paused_in_preparation"},
                {"t": 0.0, "do": "key", "keycode": KEY_ESCAPE},
                {"t": 0.0, "do": "ui_state_log", "label": "esc_resumes_to_preparing"},
                {"t": 0.0, "do": "hud_button", "name": "begin_defense"},
                {"t": 0.0, "do": "ui_state_log", "label": "begin_defense_playing"},
                {"t": 0.0, "do": "hud_button", "name": "begin_defense"},
                {"t": 0.0, "do": "ui_state_log", "label": "second_begin_defense_refused"},
                {"t": 20.0, "do": "econ_log", "label": "battle_t20"},
                {"t": 20.0, "do": "state_log", "label": "battle_t20"},
                {"t": 20.0, "do": "capture", "name": pb + "_08_battle_t20"},
                {"t": 45.0, "do": "hud_button", "name": "build_jangseung"},
                {"t": 45.0, "do": "lmb_at", "anchor": Vector2i(48, 36)},
                {"t": 45.0, "do": "hud_button", "name": "build_hwacha"},
                {"t": 45.0, "do": "lmb_at", "anchor": Vector2i(36, 24)},
                {"t": 45.0, "do": "econ_log", "label": "battle_purchase_t45"},
                {"t": 45.0, "do": "capture", "name": pb + "_09_battle_purchase_t45"},
                {"t": 50.0, "do": "force_outer_hp", "value": 1.0, "why": "wp008_build forced collapse (verification only)"},
                {"t": 50.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "wp008_build trigger enemy"},
                {"t": 51.0, "do": "econ_log", "label": "after_collapse"},
                {"t": 51.0, "do": "state_log", "label": "after_collapse"},
                {"t": 51.0, "do": "capture", "name": pb + "_10_collapse_recovery_selected"},
                {"t": 51.0, "do": "preview_at", "anchor": TestMap.RECOVERY_B},
                {"t": 51.0, "do": "capture", "name": pb + "_11_recovery_preview_B"},
                {"t": 51.0, "do": "lmb_at", "anchor": TestMap.RECOVERY_B},
                {"t": 51.0, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 51.5, "do": "econ_log", "label": "after_recovery"},
                {"t": 51.5, "do": "state_log", "label": "after_recovery"},
                {"t": 51.5, "do": "capture", "name": pb + "_12_recovery_placed_free"},
                {"t": 51.5, "do": "hud_button", "name": "build_jangseung"},
                {"t": 51.5, "do": "preview_at", "anchor": Vector2i(31, 17)},
                {"t": 51.5, "do": "capture", "name": pb + "_13_outer_refused_after_collapse"},
                {"t": 51.5, "do": "preview_at", "anchor": Vector2i(50, 8)},
                {"t": 51.5, "do": "capture", "name": pb + "_14_inner_preview"},
                {"t": 51.5, "do": "lmb_at", "anchor": Vector2i(50, 8)},
                {"t": 51.5, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 52.0, "do": "econ_log", "label": "after_inner_purchase"},
                {"t": 52.0, "do": "state_log", "label": "after_inner_purchase"},
                {"t": 52.0, "do": "capture", "name": pb + "_15_inner_purchase"},
                {"t": 52.0, "do": "wait_result"},
                {"t": 52.0, "do": "econ_log", "label": "result"},
                {"t": 52.0, "do": "state_log", "label": "result"},
                {"t": 52.0, "do": "capture", "name": pb + "_16_result"},
                {"t": 52.0, "do": "key", "keycode": KEY_R},
                {"t": 0.0, "do": "ui_state_log", "label": "r_on_result_restarts_to_preparing"},
                {"t": 0.0, "do": "econ_log", "label": "restart_ledger_reset"},
                {"t": 0.0, "do": "state_log", "label": "restart_preparing"},
                {"t": 0.0, "do": "capture", "name": pb + "_17_restart_preparing"},
                {"t": 0.0, "do": "quit"},
            ]
        "wp005_v01", "wp005_v01_720":
            # WP-005 V-01 evidence (D-053): the F2 timeline; at each checkpoint
            # the battle is held and the same tick is captured in the
            # developer view (the previous default), the player view, and the
            # player view without names. Label boxes + overlapping pairs are
            # logged per capture. Art mode from --art (default greybox here;
            # verify runs it with --art=sample like a normal launch).
            _apply_mode_preset(Config.for_wp003())
            battle.reset()
            _sim_speed = 6
            if _capture_name.ends_with("_720"):
                DisplayServer.window_set_size(Vector2i(1280, 720))
            var pv: String = _capture_name
            _capture_steps = [{"t": 0.0, "do": "art_log", "label": "launch"}]
            var checkpoints: Array = [
                [15.0, "a_battle_t15", []],
                [20.5, "b_collapse_t20.5", [{"do": "force_outer_hp", "value": 1.0, "why": "V-01 forced collapse (verification only)", "t": 20.0},
                    {"do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "V-01 trigger enemy", "t": 20.0}]],
                [23.5, "c_recovery_preview_t23.5", [{"do": "preview_at", "anchor": TestMap.RECOVERY_B, "t": 23.0}]],
                [25.5, "d_recovery_placed_t25.5", [{"do": "preview_at", "anchor": Vector2i(-1, -1), "t": 25.0},
                    {"do": "place_recovery", "anchor": TestMap.RECOVERY_B, "t": 25.0}]],
                [45.0, "e_inner_fire_t45", []],
            ]
            for cp: Array in checkpoints:
                for pre: Dictionary in cp[2]:
                    _capture_steps.append(pre)
                var ct: float = cp[0]
                _capture_steps.append_array([
                    {"t": ct, "do": "hold", "on": true},
                    {"t": ct, "do": "view", "player": false},
                    {"t": ct, "do": "capture", "name": pv + "_" + cp[1] + "_dev"},
                    {"t": ct, "do": "view", "player": true},
                    {"t": ct, "do": "capture", "name": pv + "_" + cp[1] + "_player"},
                    {"t": ct, "do": "labels", "on": false},
                    {"t": ct, "do": "capture", "name": pv + "_" + cp[1] + "_player_nolabels"},
                    {"t": ct, "do": "labels", "on": true},
                    {"t": ct, "do": "hold", "on": false},
                ])
            _capture_steps.append({"t": 45.0, "do": "quit"})
        "wp005_playtest", "wp005_playtest_720":
            # docs/PLAYTEST_WP005.md T1..T4 as a scripted run: no verification
            # hooks; the collapse comes from real arrivals (run with
            # --set=outer_hp=40 as the playtest does). 1920x1080 or 1280x720.
            _apply_mode_preset(Config.for_wp003())
            battle.reset()
            _sim_speed = 6
            if _capture_name.ends_with("_720"):
                DisplayServer.window_set_size(Vector2i(1280, 720))
            var pt: String = _capture_name
            _capture_steps = [
                {"t": 0.0, "do": "art_log", "label": "launch"},
                {"t": 15.0, "do": "capture", "name": pt + "_T1_first_t15"},
                {"t": 15.0, "do": "labels", "on": false},
                {"t": 15.0, "do": "capture", "name": pt + "_T1_nolabels_t15"},
                {"t": 15.0, "do": "labels", "on": true},
                {"t": 60.0, "do": "capture", "name": pt + "_T2_wave2_t60"},
                {"t": 60.0, "do": "show", "zones": false, "ranges": false},
                {"t": 60.0, "do": "capture", "name": pt + "_T2_wave2_clean_t60"},
                {"t": 90.0, "do": "capture", "name": pt + "_T2_wave3_clean_t90"},
                {"t": 90.0, "do": "show", "zones": true, "ranges": true},
                {"t": 90.0, "do": "wait_collapse", "deadline": 400.0},
                {"t": 90.0, "do": "capture", "name": pt + "_T3_collapse"},
                {"t": 90.0, "do": "labels", "on": false},
                {"t": 90.0, "do": "capture", "name": pt + "_T3_collapse_nolabels"},
                {"t": 90.0, "do": "labels", "on": true},
                {"t": 90.0, "do": "preview_at", "anchor": Vector2i(46, 29)},
                {"t": 90.0, "do": "capture", "name": pt + "_T3_preview_outer_refused"},
                {"t": 90.0, "do": "preview_at", "anchor": TestMap.RECOVERY_B},
                {"t": 90.0, "do": "capture", "name": pt + "_T3_preview_B_ok"},
                {"t": 90.0, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 90.0, "do": "place_recovery", "anchor": TestMap.RECOVERY_B},
                {"t": 90.0, "do": "capture", "name": pt + "_T3_placed_B"},
                {"t": 400.0, "do": "capture_on_end", "name": pt + "_T4_result"},
            ]
        "wp005_closeup":
            # AC-02 evidence: 3x close-ups of the plaza (footprint / grid
            # overlay on and off), the outer post at the collapse and cell B
            # at the preview / placement, on the F2 timeline in sample mode.
            _apply_mode_preset(Config.for_wp003())
            battle.reset()
            _sim_speed = 6
            var pc: String = _capture_name
            _capture_steps = [
                {"t": 0.0, "do": "art_log", "label": "launch"},
                {"t": 15.0, "do": "zoom", "center": Vector2(950.0, 450.0), "factor": 3.0},
                {"t": 15.0, "do": "footprints", "on": true},
                {"t": 15.0, "do": "capture", "name": pc + "_a_plaza_x3_footprints_t15"},
                {"t": 15.0, "do": "footprints", "on": false},
                {"t": 15.0, "do": "capture", "name": pc + "_a2_plaza_x3_t15"},
                {"t": 15.0, "do": "zoom", "center": Vector2(950.0, 450.0), "factor": 1.0},
                {"t": 20.0, "do": "force_outer_hp", "value": 1.0, "why": "WP-005 closeup forced collapse (verification only)"},
                {"t": 20.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "WP-005 closeup trigger enemy"},
                {"t": 20.5, "do": "zoom", "center": Vector2(950.0, 530.0), "factor": 3.0},
                {"t": 20.5, "do": "capture", "name": pc + "_b_outer_post_x3_t20.5"},
                {"t": 23.0, "do": "preview_at", "anchor": TestMap.RECOVERY_B},
                {"t": 23.5, "do": "zoom", "center": Vector2(900.0, 280.0), "factor": 3.0},
                {"t": 23.5, "do": "footprints", "on": true},
                {"t": 23.5, "do": "capture", "name": pc + "_c_preview_B_x3_footprints_t23.5"},
                {"t": 23.5, "do": "footprints", "on": false},
                {"t": 23.5, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 25.0, "do": "place_recovery", "anchor": TestMap.RECOVERY_B},
                {"t": 25.5, "do": "capture", "name": pc + "_d_recovery_B_x3_t25.5"},
                {"t": 25.5, "do": "zoom", "center": Vector2(900.0, 280.0), "factor": 1.0},
                {"t": 25.5, "do": "art_log", "label": "t25.5"},
                {"t": 25.5, "do": "quit"},
            ]
        "wp005_dense", "wp005_dense_720":
            # AC-06 evidence: the D-027 benchmark load (1,000 enemies held by
            # top-up, finite waves off, outer HP 1e6 until the scripted
            # trigger) in the rendering mode given by --art; captures with
            # and without structure labels, the collapse and the recovery.
            _apply_mode_preset(Config.for_wp003())
            config.values["benchmark_hold_alive"] = true
            config.values["outer_hp"] = 1000000.0
            config.values["benchmark_core_invulnerable"] = true
            battle.reset()
            battle.waves.enabled = false
            _sim_speed = 6
            if _capture_name.ends_with("_720"):
                DisplayServer.window_set_size(Vector2i(1280, 720))
            var pd: String = _capture_name
            _capture_steps = [
                {"t": 0.0, "do": "art_log", "label": "launch"},
                {"t": 15.0, "do": "capture", "name": pd + "_a_1000_t15"},
                {"t": 15.0, "do": "labels", "on": false},
                {"t": 15.0, "do": "capture", "name": pd + "_a2_1000_nolabels_t15"},
                {"t": 15.0, "do": "labels", "on": true},
                {"t": 15.0, "do": "outline", "on": false},
                {"t": 15.0, "do": "capture", "name": pd + "_a3_1000_nooutline_t15"},
                {"t": 15.0, "do": "outline", "on": true},
                {"t": 20.0, "do": "force_outer_hp", "value": 1.0, "why": "WP-005 dense forced collapse (verification only)"},
                {"t": 20.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "WP-005 dense trigger enemy"},
                {"t": 20.5, "do": "capture", "name": pd + "_b_collapse_1000_t20.5"},
                {"t": 25.0, "do": "place_recovery", "anchor": TestMap.RECOVERY_B},
                {"t": 25.5, "do": "capture", "name": pd + "_c_recovery_1000_t25.5"},
                {"t": 25.5, "do": "labels", "on": false},
                {"t": 25.5, "do": "capture", "name": pd + "_c2_recovery_1000_nolabels_t25.5"},
                {"t": 25.5, "do": "art_log", "label": "t25.5"},
                {"t": 25.5, "do": "quit"},
            ]
        "wp005_sample", "wp005_sample_720", "wp005_greybox", "wp005_greybox_720", "wp005_assets", "wp005_assets_720":
            # WP-005 evidence: the F2 timeline (forced collapse at 20 s, H1 to B
            # at 25 s) in the rendering mode given by --art, at 1920x1080 or
            # 1280x720. The scenario name only picks the window size and the
            # file prefix (wp005_assets* = --art=sample on the default asset
            # directory); the battle data are the WP-003 contract in every
            # variant (AC-05).
            _apply_mode_preset(Config.for_wp003())
            battle.reset()
            _sim_speed = 6
            if _capture_name.ends_with("_720"):
                DisplayServer.window_set_size(Vector2i(1280, 720))
            var p5: String = _capture_name
            _capture_steps = [
                {"t": 0.0, "do": "art_log", "label": "launch"},
                {"t": 0.0, "do": "state_log", "label": "initial"},
                {"t": 15.0, "do": "capture", "name": p5 + "_a_dense_t15"},
                {"t": 20.0, "do": "state_log", "label": "before_collapse"},
                {"t": 20.0, "do": "force_outer_hp", "value": 1.0, "why": "WP-005 forced collapse (verification only)"},
                {"t": 20.0, "do": "spawn_extra", "pos": Vector2(950.0, 530.0), "count": 1, "why": "WP-005 trigger enemy"},
                {"t": 20.2, "do": "state_log", "label": "after_collapse"},
                {"t": 20.5, "do": "capture", "name": p5 + "_b_collapse_t20.5"},
                {"t": 23.0, "do": "preview_at", "anchor": Vector2i(46, 29)},
                {"t": 23.0, "do": "capture", "name": p5 + "_c_invalid_preview_t23"},
                {"t": 23.0, "do": "preview_at", "anchor": TestMap.RECOVERY_B},
                {"t": 23.5, "do": "capture", "name": p5 + "_d_valid_preview_t23.5"},
                {"t": 23.5, "do": "preview_at", "anchor": Vector2i(-1, -1)},
                {"t": 25.0, "do": "place_recovery", "anchor": TestMap.RECOVERY_B},
                {"t": 25.2, "do": "state_log", "label": "after_recovery"},
                {"t": 25.5, "do": "capture", "name": p5 + "_e_recovery_placed_t25.5"},
                {"t": 45.0, "do": "capture", "name": p5 + "_f_inner_fire_t45"},
                {"t": 45.0, "do": "art_log", "label": "t45"},
                {"t": 400.0, "do": "capture_on_end", "name": p5 + "_g_run_end"},
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


var _f3: F3Tracker = null


func _capture_script_step() -> void:
    if _capture_name == "" or _capture_busy:
        return
    if _f3 != null:
        _f3.after_tick(battle)
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
            "show":
                _show_zones = bool(step["zones"])
                _show_ranges = bool(step["ranges"])
                _capture_log.append({"t": battle.sim_time, "show_zones": _show_zones, "show_ranges": _show_ranges, "tick": battle.steps})
            "wait_collapse":
                # Stay on this step until the outer district collapses from real
                # arrivals (no forced HP); give up at the deadline (sim seconds).
                if battle.run.collapse_count == 0 and battle.sim_time < float(step["deadline"]) and not battle.run.ended():
                    _capture_index -= 1
                    return
                _capture_log.append({"t": battle.sim_time, "wait_collapse": battle.run.collapse_count, "outer_hp": battle.run.outer_hp,
                    "tick": battle.steps, "run": battle.run.run_name()})
            "hold":
                _capture_hold = bool(step["on"])
                _capture_log.append({"t": battle.sim_time, "hold": _capture_hold, "tick": battle.steps})
            "view":
                _set_player_view(bool(step["player"]))
                _capture_log.append({"t": battle.sim_time, "view": "player" if _player_view else "dev", "tick": battle.steps})
            "labels":
                _show_labels = bool(step["on"])
                _overlay.show_labels = _show_labels
                _capture_log.append({"t": battle.sim_time, "labels": _show_labels, "tick": battle.steps})
            "outline":
                _set_enemy_outline(bool(step["on"]))
                _capture_log.append({"t": battle.sim_time, "outline": _enemy_outline, "tick": battle.steps})
            "footprints":
                _overlay.show_footprints = bool(step["on"])
                _capture_log.append({"t": battle.sim_time, "footprints": _overlay.show_footprints, "tick": battle.steps})
            "zoom":
                # Close-up evidence (AC-02): a Camera2D on the world layers only;
                # HUD / menu CanvasLayers are unaffected. factor 1 = restore.
                _apply_zoom(step["center"], float(step["factor"]))
                _capture_log.append({"t": battle.sim_time, "zoom": float(step["factor"]), "center": [step["center"].x, step["center"].y], "tick": battle.steps})
            "art_log":
                _capture_log.append({"t": battle.sim_time, "art_log": step["label"], "art_mode": _art_mode,
                    "art": _art_report, "fx": _fx.snapshot() if _fx != null else {}, "labels": _show_labels,
                    "enemy_sprites": _enemy_sprites, "enemy_outline": _enemy_outline, "tick": battle.steps})
            "state_log":
                # AC-05: the structured battle state at the comparison points
                # (initial / before + after collapse / after recovery / end).
                _capture_log.append({"t": battle.sim_time, "state_log": step["label"], "tick": battle.steps,
                    "run_id": battle.run.run_id, "state_hash": battle.state_hash(), "full_state": battle.full_state()})
            "reset":
                battle.reset()
                _reset_input_state()
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
                # (Vector2i(-1,-1) clears it). In build mode with a kind selected
                # the preview is the paid-construction ghost.
                var a: Vector2i = step["anchor"]
                _overlay.preview_override = a
                var pv_reason: int = Placement.Reject.NONE
                if a.x >= 0:
                    pv_reason = battle.preview_build(_sel_kind, a) if (battle.play_mode == "build" and _sel_kind >= 0 and _sel_kind < SEL_RECOVERY) else battle.preview_recovery(a)
                var pv_log: Dictionary = {"t": battle.sim_time, "preview_at": str(a), "selection": _sel_kind,
                    "reason": Placement.reject_name(pv_reason) if a.x >= 0 else ""}
                if a.x >= 0 and battle.play_mode == "build" and _sel_kind == Placement.Kind.HWACHA:
                    var hh: Dictionary = battle.hwacha_placement_hint(a)
                    pv_log["hwacha_hint"] = hh
                    pv_log["hwacha_hint_text"] = OverlayLayer.hwacha_hint_text(hh)
                _capture_log.append(pv_log)
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
            "f3_check_collapse":
                _capture_log.append({"t": battle.sim_time, "f3_check_collapse": true, "tick": battle.steps,
                    "collapse_count": battle.run.collapse_count, "collapse_tick": battle.run.collapse_tick,
                    "recovery_right": battle.run.recovery_right, "h1_detached": battle.placement.detached.has(1)})
            "f3_spawn_group":
                var slots: PackedInt32Array = battle.spawn_extra(TestMap.F3_SPAWN_POINT, TestMap.F3_SPAWN_COUNT, "F3 controlled group")
                _f3 = F3Tracker.new()
                _f3.begin(battle, slots)
                _capture_log.append({"t": battle.sim_time, "f3_spawn_group": slots.size(), "tick": battle.steps,
                    "pos": [TestMap.F3_SPAWN_POINT.x, TestMap.F3_SPAWN_POINT.y], "ids": _f3.ids})
            "f3_first_observation":
                _capture_log.append({"t": battle.sim_time, "f3_first_observation": _f3.first_observation(battle), "tick": battle.steps})
            "f3_state":
                _capture_log.append({"t": battle.sim_time, "f3_state": step["label"], "tick": battle.steps,
                    "full_state": battle.full_state()})
            "f3_capture_on_h1_shot":
                # Wait (re-check every tick) until H1 fires for the first time
                # after the placement, then capture that very tick; give up at
                # the deadline and record that no volley happened (variant A).
                var h1s: Placement.Structure = battle.placement.get_any(battle.run.recovery_target_id)
                var fired: bool = h1s != null and _f3 != null and h1s.shots_fired > _f3.h1_shots_at_begin
                if not fired and battle.sim_time + 1e-6 < float(step["deadline"]):
                    _capture_index -= 1
                    return
                _capture_log.append({"t": battle.sim_time, "f3_h1_first_shot": fired, "tick": battle.steps,
                    "shot": _f3.last_h1_shot if _f3 != null else {}, "deadline": step["deadline"]})
                if fired:
                    _capture_busy = true
                    _do_capture(step["name"])
                    return
            "f3_end":
                _capture_log.append({"t": battle.sim_time, "f3_end": _f3.report(battle) if _f3 != null else {}, "tick": battle.steps})
            "button":
                # A real Button node press (its `pressed` signal), exactly what a click does.
                var b: Button = menu.button(step["intent"])
                var before: String = flow.state_name()
                var shown: bool = menu.button_visible(step["intent"])
                if b != null and shown:
                    b.pressed.emit()
                    _apply_intents()
                _capture_log.append({"t": battle.sim_time, "button": step["intent"], "found": b != null,
                    "visible": shown, "state_before": before, "state_after": flow.state_name(),
                    "tick": battle.steps, "run_id": battle.run.run_id})
            "key":
                # A key tap: press (intent applied) then release, so the
                # release fence opens exactly as it does for a real tap.
                var before_k: String = flow.state_name()
                _probe_key(step["keycode"], true)
                _apply_intents()
                var fence_held: Array = _fence.keys()
                _probe_key(step["keycode"], false)
                _capture_log.append({"t": battle.sim_time, "key": OS.get_keycode_string(step["keycode"]),
                    "state_before": before_k, "state_after": flow.state_name(), "fence_before_release": fence_held,
                    "fence_after_release": _fence.keys(), "tick": battle.steps, "run_id": battle.run.run_id})
            "fence_probe":
                # R-01 evidence with real events at the anchor: Esc pauses,
                # Esc pressed again (not released) resumes, a LMB press is
                # refused while Esc is still held, the Esc release opens the
                # fence, the next LMB press places H1.
                var anchor: Vector2i = step["anchor"]
                _cursor_world_override = battle.grid.cell_center(anchor.x, anchor.y)
                var probe: Dictionary = {"t": battle.sim_time, "fence_probe": str(anchor), "tick": battle.steps, "run_id": battle.run.run_id}
                var a0: int = battle.commands_accepted
                _probe_key(KEY_ESCAPE, true)
                _apply_intents()
                probe["after_esc_press"] = flow.state_name()
                _probe_key(KEY_ESCAPE, false)
                _probe_key(KEY_ESCAPE, true)
                _apply_intents()
                probe["after_second_esc_press"] = flow.state_name()
                probe["fence_after_resume"] = _fence.keys()
                _probe_mouse(true)
                probe["lmb_while_esc_held_accepted_delta"] = battle.commands_accepted - a0
                probe["lmb_while_esc_held_recovery_placed"] = battle.run.recovery_placed
                _probe_mouse(false)
                _probe_key(KEY_ESCAPE, false)
                probe["fence_after_esc_release"] = _fence.keys()
                _probe_mouse(true)
                probe["lmb_after_release_accepted_delta"] = battle.commands_accepted - a0
                probe["recovery_placed"] = battle.run.recovery_placed
                _probe_mouse(false)
                probe["fenced_inputs"] = fenced_inputs.duplicate(true)
                _cursor_world_override = Vector2.INF
                _capture_log.append(probe)
            "ui_state_log":
                _capture_log.append({"t": battle.sim_time, "ui_state": flow.state_name(), "label": step["label"],
                    "tick": battle.steps, "run_id": battle.run.run_id, "run": battle.run.run_name(),
                    "visible_buttons": menu.visible_buttons(), "flow": flow.snapshot(),
                    "fence": _fence.keys(), "fenced_inputs": fenced_inputs.size(),
                    "preparing": battle.preparing, "begin_defense_calls_ignored": battle.begin_defense_calls_ignored,
                    "settings_path": settings.path if settings != null else ""})
            "econ_log":
                # WP-008: the ledger and the structure totals at a named point.
                _capture_log.append({"t": battle.sim_time, "econ_log": step["label"], "tick": battle.steps,
                    "run_id": battle.run.run_id, "run": battle.run.run_name(), "preparing": battle.preparing,
                    "economy": battle.economy.snapshot(), "structure_total": battle.structure_total(),
                    "districts": battle.district_counts(), "selection": _sel_kind,
                    "build_clicks": build_clicks.duplicate(true), "recovery": battle.run.snapshot()})
            "hud_button":
                # A real HUD Button press (construction bar / 방어 시작), then the
                # intent frame, exactly what a click does.
                var hb: Button = _build_buttons.get(step["name"], null)
                var hb_before: String = flow.state_name()
                var hb_visible: bool = hb != null and hb.visible and _build_bar.visible
                if hb != null and hb_visible:
                    hb.pressed.emit()
                    _apply_intents()
                _capture_log.append({"t": battle.sim_time, "hud_button": step["name"], "found": hb != null, "visible": hb_visible,
                    "state_before": hb_before, "state_after": flow.state_name(), "selection": _sel_kind,
                    "preparing": battle.preparing, "tick": battle.steps, "run_id": battle.run.run_id})
            "lmb_at":
                # A real left-click (press + release) with the cursor on the anchor.
                var la: Vector2i = step["anchor"]
                _cursor_world_override = battle.grid.cell_center(la.x, la.y)
                var a0l: int = battle.commands_accepted
                var s0: int = battle.economy.supply
                _probe_mouse(true)
                _probe_mouse(false)
                _cursor_world_override = Vector2.INF
                _capture_log.append({"t": battle.sim_time, "lmb_at": str(la), "accepted_delta": battle.commands_accepted - a0l,
                    "supply_before": s0, "supply_after": battle.economy.supply, "selection": _sel_kind,
                    "last_click": build_clicks.back() if not build_clicks.is_empty() else {},
                    "recovery_placed": battle.run.recovery_placed, "tick": battle.steps, "run_id": battle.run.run_id})
            "force_core_hp":
                battle.force_core_hp(step["value"], step["why"])
                _capture_log.append({"t": battle.sim_time, "force_core_hp": step["value"], "why": step["why"]})
            "wait_result":
                # Stay on this step until the run has ended and RESULT is shown.
                if flow.state != PlayFlow.State.RESULT:
                    _capture_index -= 1
                    return
                _capture_log.append({"t": battle.sim_time, "wait_result": flow.state_name(), "result": flow.result,
                    "tick": battle.steps, "run_id": battle.run.run_id})
            "quit":
                _write_capture_log()
                get_tree().quit()
                return


func _set_enemy_outline(on: bool) -> void:
    _enemy_outline = on
    if _enemies != null and _enemies.material is ShaderMaterial:
        (_enemies.material as ShaderMaterial).set_shader_parameter("outline", 1.0 if on else 0.0)


## Capture-only close-up camera. Never used by play or by the tests' battle
## state; it only changes what the world layers show on screen.
func _apply_zoom(center: Vector2, factor: float) -> void:
    if factor <= 1.0:
        if _capture_cam != null:
            _capture_cam.enabled = false
            _capture_cam.queue_free()
            _capture_cam = null
        return
    if _capture_cam == null:
        _capture_cam = Camera2D.new()
        _capture_cam.name = "CaptureCam"
        _capture_cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
        add_child(_capture_cam)
    _capture_cam.position = center
    _capture_cam.zoom = Vector2(factor, factor)
    _capture_cam.enabled = true
    _capture_cam.make_current()


## Synthesized events for the capture script (the same handler the real
## input takes, so the held ledger and the fence see them).
func _probe_key(keycode: int, pressed: bool) -> void:
    var ev: InputEventKey = InputEventKey.new()
    ev.keycode = keycode
    ev.pressed = pressed
    _handle_key_event(ev)


func _probe_mouse(pressed: bool) -> void:
    var ev: InputEventMouseButton = InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = pressed
    _handle_key_event(ev)


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
    snap["art_mode"] = _art_mode
    snap["flow_state"] = flow.state_name()
    snap["selection"] = _sel_kind
    snap["view"] = "player" if _player_view else "dev"
    snap["labels_on"] = _show_labels
    snap["hud_text"] = _hud.text
    snap["label_boxes"] = _overlay.text_boxes.size()
    snap["label_overlaps"] = _overlay.label_overlaps()
    if _fx != null:
        snap["fx"] = _fx.snapshot()
        snap["sprites_drawn"] = _overlay.sprites_drawn.duplicate()
        snap["marks_drawn"] = _overlay.marks_drawn.duplicate()
        snap["sample_tiles_drawn"] = _terrain.sample_tiles_drawn.duplicate()
        snap["enemy_outline"] = _enemy_outline
        snap["zoom"] = _capture_cam.zoom.x if _capture_cam != null else 1.0
    _capture_log.append(snap)
    print("capture %s -> %s (%s)" % [name, path, error_string(err)])
    _capture_busy = false


func _write_capture_log() -> void:
    var path: String = _capture_dir.path_join("%s_log.json" % _capture_name)
    # R-02 (PR #13 review): the log names the executable that produced the
    # PNGs (hash, editor or release), the implementation sha passed by the
    # runner and the rendering / settings choices, so a release capture can
    # be tied to a commit exactly like a perf JSON.
    _capture_log.insert(0, {"capture_manifest": {"scenario": _capture_name, "implementation_sha": _build_sha,
        "executable": _executable_manifest(), "art_mode": _art_mode, "art": _art_report,
        "settings_path": settings.path if settings != null else "", "window_size": str(DisplayServer.window_get_size()),
        "engine": Engine.get_version_info().string, "cmdline_user_args": OS.get_cmdline_user_args(),
        "config": config.to_dictionary()}})
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
