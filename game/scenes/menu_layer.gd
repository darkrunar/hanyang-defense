extends CanvasLayer
## WP-004 menus (D-042): TITLE / PAUSED / SETTINGS / CONFIRM / RESULT panels
## drawn above the battlefield. Plain bordered panels, low-saturation Joseon
## wood / stone / tile colours, teal (bongsu) for focus, orange (hwacha) for
## the primary action, red for threat. No external assets. Every button is a
## real Button node; the scene connects them to PlayFlow intents through
## `on_intent`. A full-screen dim rectangle with mouse_filter STOP sits under
## every panel so a click that misses a button never reaches the field.
##
## Anchors are in the 1920x1080 logical space (project stretch: canvas_items /
## keep), so a 1280x720 window shows the same layout scaled.

const PlayFlow := preload("res://game/core/play_flow.gd")
const ResultModel := preload("res://game/core/result_model.gd")

const C_WOOD: Color = Color(0.36, 0.26, 0.17)
const C_WOOD_DARK: Color = Color(0.22, 0.16, 0.11)
const C_STONE: Color = Color(0.30, 0.30, 0.28)
const C_TILE: Color = Color(0.14, 0.13, 0.14, 0.96)
const C_PAPER: Color = Color(0.90, 0.86, 0.76)
const C_TEAL: Color = Color(0.36, 0.76, 0.72)
const C_ORANGE: Color = Color(0.90, 0.55, 0.20)
const C_RED: Color = Color(0.86, 0.33, 0.30)
const C_DIM: Color = Color(0.05, 0.04, 0.04, 0.55)
const C_DIM_TITLE: Color = Color(0.05, 0.04, 0.04, 0.72)

const BUTTON_W: float = 360.0
const BUTTON_H: float = 60.0
const FONT_BUTTON: int = 24
const FONT_TITLE: int = 56
const FONT_BODY: int = 20

## Callable(intent: String, arg: Variant) set by the scene.
var on_intent: Callable = Callable()

var _dim: ColorRect = null
var _panels: Dictionary = {}          # state name -> Control
var _buttons: Dictionary = {}         # intent name -> Button
var _confirm_text: Label = null
var _confirm_ok: Button = null
var _result_rows: VBoxContainer = null
var _result_title: Label = null
var _result_map: Control = null
var _result_marker: Vector2 = Vector2.INF
var _settings_mode: Button = null
var _settings_notice: Label = null
var _title_notice: Label = null
var _pause_hint: Label = null
var _current: String = ""
## intent -> panel name, so visibility can be answered from our own state
## (is_visible_in_tree() is not reliable in a headless test tree).
var _button_panel: Dictionary = {}
var _building_panel: String = ""


var _built: bool = false


## Build the panels. Called explicitly by the scene right after add_child so
## the menu exists even where _ready() is not delivered (headless test trees).
func build() -> void:
    if _built:
        return
    _built = true
    layer = 20
    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = C_DIM
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_dim)
    _build_title()
    _build_pause()
    _build_settings()
    _build_confirm()
    _build_result()
    show_state("TITLE", {})


# ----------------------------------------------------------------- widgets ---

func _panel_style(border: Color, bg: Color = C_TILE) -> StyleBoxFlat:
    var sb: StyleBoxFlat = StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(4)
    sb.set_corner_radius_all(0)
    sb.set_content_margin_all(28.0)
    sb.shadow_size = 0
    return sb


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
    var sb: StyleBoxFlat = StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(0)
    sb.content_margin_left = 16.0
    sb.content_margin_right = 16.0
    sb.content_margin_top = 10.0
    sb.content_margin_bottom = 10.0
    return sb


func _make_panel(name: String, width: float) -> PanelContainer:
    var p: PanelContainer = PanelContainer.new()
    p.name = name
    p.add_theme_stylebox_override("panel", _panel_style(C_WOOD))
    p.custom_minimum_size = Vector2(width, 0.0)
    p.set_anchors_preset(Control.PRESET_CENTER)
    p.grow_horizontal = Control.GROW_DIRECTION_BOTH
    p.grow_vertical = Control.GROW_DIRECTION_BOTH
    p.mouse_filter = Control.MOUSE_FILTER_STOP
    p.visible = false
    add_child(p)
    _panels[name] = p
    _building_panel = name
    return p


func _make_label(text: String, size: int, color: Color = C_PAPER, center: bool = true) -> Label:
    var l: Label = Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    if center:
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return l


func _make_button(intent: String, text: String, primary: bool = false, danger: bool = false) -> Button:
    var b: Button = Button.new()
    b.name = intent
    b.text = text
    b.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
    b.add_theme_font_size_override("font_size", FONT_BUTTON)
    b.add_theme_color_override("font_color", C_PAPER)
    b.add_theme_color_override("font_hover_color", Color.WHITE)
    b.add_theme_color_override("font_focus_color", Color.WHITE)
    b.add_theme_color_override("font_pressed_color", Color.WHITE)
    var bg: Color = C_ORANGE.darkened(0.35) if primary else (C_RED.darkened(0.45) if danger else C_STONE)
    b.add_theme_stylebox_override("normal", _button_style(bg, C_WOOD_DARK))
    b.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.12), C_PAPER))
    b.add_theme_stylebox_override("pressed", _button_style(bg.darkened(0.2), C_PAPER))
    b.add_theme_stylebox_override("focus", _button_style(bg.lightened(0.08), C_TEAL))
    b.focus_mode = Control.FOCUS_ALL
    b.mouse_filter = Control.MOUSE_FILTER_STOP
    b.pressed.connect(func() -> void: _emit(intent, null))
    _buttons[intent] = b
    _button_panel[intent] = _building_panel
    return b


func _emit(intent: String, arg: Variant) -> void:
    if on_intent.is_valid():
        on_intent.call(intent, arg)


# ------------------------------------------------------------------ panels ---

func _build_title() -> void:
    var p: PanelContainer = _make_panel("TITLE", 640.0)
    var v: VBoxContainer = VBoxContainer.new()
    v.add_theme_constant_override("separation", 14)
    p.add_child(v)
    v.add_child(_make_label("한양 디펜스", FONT_TITLE, C_PAPER))
    v.add_child(_make_label("한양 전체를 무기화하는 대규모 전투 디펜스 · 프로토타입", FONT_BODY, C_TEAL))
    v.add_child(_make_label("외곽 거점을 지키고, 무너지면 내곽으로 후퇴해 화차를 다시 놓아 핵심 시설을 사수한다.", FONT_BODY - 2, C_PAPER.darkened(0.15)))
    var sp: Control = Control.new()
    sp.custom_minimum_size = Vector2(0.0, 12.0)
    v.add_child(sp)
    v.add_child(_centered(_make_button("title_start", "게임 시작", true)))
    v.add_child(_centered(_make_button("title_settings", "설정")))
    v.add_child(_centered(_make_button("title_quit", "종료")))
    _title_notice = _make_label("", FONT_BODY - 4, C_RED)
    v.add_child(_title_notice)


func _build_pause() -> void:
    var p: PanelContainer = _make_panel("PAUSED", 520.0)
    var v: VBoxContainer = VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    p.add_child(v)
    v.add_child(_make_label("일시정지", FONT_TITLE - 16, C_PAPER))
    _pause_hint = _make_label("전투와 배치가 멈춰 있다. Esc 또는 계속하기로 재개.", FONT_BODY - 2, C_TEAL)
    v.add_child(_pause_hint)
    v.add_child(_centered(_make_button("pause_continue", "계속하기", true)))
    v.add_child(_centered(_make_button("pause_settings", "설정")))
    v.add_child(_centered(_make_button("pause_restart", "다시 시작")))
    v.add_child(_centered(_make_button("pause_to_title", "시작 화면으로", false, true)))


func _build_settings() -> void:
    var p: PanelContainer = _make_panel("SETTINGS", 560.0)
    var v: VBoxContainer = VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    p.add_child(v)
    v.add_child(_make_label("설정", FONT_TITLE - 16, C_PAPER))
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    var lbl: Label = _make_label("화면", FONT_BUTTON, C_PAPER, false)
    lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    lbl.custom_minimum_size = Vector2(120.0, BUTTON_H)
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(lbl)
    _settings_mode = _make_button("settings_window_mode", "창 모드", true)
    row.add_child(_settings_mode)
    v.add_child(_make_label("클릭할 때마다 창 모드 ↔ 전체화면이 바뀌고 즉시 적용·저장된다.", FONT_BODY - 4, C_PAPER.darkened(0.2)))
    _settings_notice = _make_label("", FONT_BODY - 4, C_RED)
    v.add_child(_settings_notice)
    v.add_child(_centered(_make_button("settings_back", "뒤로")))


func _build_confirm() -> void:
    var p: PanelContainer = _make_panel("CONFIRM", 700.0)
    p.add_theme_stylebox_override("panel", _panel_style(C_RED.darkened(0.2)))
    var v: VBoxContainer = VBoxContainer.new()
    v.add_theme_constant_override("separation", 16)
    p.add_child(v)
    _confirm_text = _make_label("", FONT_BUTTON, C_PAPER)
    v.add_child(_confirm_text)
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 24)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    var cancel: Button = _make_button("confirm_cancel", "취소", true)
    cancel.custom_minimum_size = Vector2(280.0, BUTTON_H)
    row.add_child(cancel)
    _confirm_ok = _make_button("confirm_ok", "확인", false, true)
    _confirm_ok.custom_minimum_size = Vector2(280.0, BUTTON_H)
    row.add_child(_confirm_ok)


func _build_result() -> void:
    var p: PanelContainer = _make_panel("RESULT", 760.0)
    var v: VBoxContainer = VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    p.add_child(v)
    _result_title = _make_label("", FONT_TITLE - 12, C_PAPER)
    v.add_child(_result_title)
    var body: HBoxContainer = HBoxContainer.new()
    body.add_theme_constant_override("separation", 24)
    v.add_child(body)
    _result_rows = VBoxContainer.new()
    _result_rows.add_theme_constant_override("separation", 6)
    _result_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(_result_rows)
    _result_map = Control.new()
    _result_map.custom_minimum_size = Vector2(192.0, 108.0)
    _result_map.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    _result_map.draw.connect(_draw_result_map)
    body.add_child(_result_map)
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 24)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    var again: Button = _make_button("result_restart", "다시 시작 (R)", true)
    again.custom_minimum_size = Vector2(300.0, BUTTON_H)
    row.add_child(again)
    var title: Button = _make_button("result_to_title", "시작 화면으로")
    title.custom_minimum_size = Vector2(300.0, BUTTON_H)
    row.add_child(title)


func _centered(b: Button) -> Control:
    var c: CenterContainer = CenterContainer.new()
    c.add_child(b)
    return c


## 1920x1080 world -> 192x108 mini-map with the recovery marker.
func _draw_result_map() -> void:
    var r: Rect2 = Rect2(Vector2.ZERO, _result_map.size)
    _result_map.draw_rect(r, C_STONE.darkened(0.4), true)
    _result_map.draw_rect(r, C_WOOD, false, 2.0)
    # inner district outline (x42..53, y6..22 cells of 20 px) scaled 1/10
    _result_map.draw_rect(Rect2(Vector2(84.0, 12.0), Vector2(24.0, 34.0)), C_TEAL.darkened(0.3), false, 1.0)
    # core / outer objectives
    _result_map.draw_circle(Vector2(95.0, 21.0), 2.5, C_RED)
    _result_map.draw_circle(Vector2(95.0, 53.0), 2.5, C_ORANGE.darkened(0.2))
    if _result_marker != Vector2.INF:
        var m: Vector2 = _result_marker * 0.1
        _result_map.draw_rect(Rect2(m - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), C_ORANGE, true)
        _result_map.draw_rect(Rect2(m - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), C_PAPER, false, 1.0)


# ------------------------------------------------------------------- state ---

## Show the panel for `state_name` ("PLAYING" hides everything). `ctx` carries
## the confirm text, the result model, the settings label and notices.
func show_state(state_name: String, ctx: Dictionary) -> void:
    _current = state_name
    visible = state_name != "PLAYING" and state_name != "PREPARING"
    _dim.color = C_DIM_TITLE if state_name == "TITLE" else C_DIM
    for k: String in _panels:
        (_panels[k] as Control).visible = k == state_name
    match state_name:
        "CONFIRM":
            var t: Dictionary = ctx.get("confirm", {})
            _confirm_text.text = str(t.get("text", ""))
            _confirm_ok.text = str(t.get("ok", "확인"))
            (_buttons["confirm_cancel"] as Button).text = str(t.get("cancel", "취소"))
        "RESULT":
            _fill_result(ctx.get("result", {}))
        "PAUSED":
            _pause_hint.text = "준비 단계가 멈춰 있다. Esc 또는 계속하기로 준비를 이어간다." if str(ctx.get("pause_return", "")) == "PREPARING" \
                else "전투와 배치가 멈춰 있다. Esc 또는 계속하기로 재개."
        "SETTINGS":
            _settings_mode.text = str(ctx.get("window_mode_label", "창 모드"))
            _settings_notice.text = str(ctx.get("settings_notice", ""))
        "TITLE":
            _title_notice.text = str(ctx.get("settings_notice", ""))
    _focus_default(state_name)


func set_settings_notice(text: String) -> void:
    _settings_notice.text = text
    _title_notice.text = text


func set_window_mode_label(text: String) -> void:
    _settings_mode.text = text


func _fill_result(m: Dictionary) -> void:
    for c: Node in _result_rows.get_children():
        c.queue_free()
    if m.is_empty():
        _result_title.text = ""
        _result_marker = Vector2.INF
        return
    var won: bool = bool(m.get("won", false))
    _result_title.text = "승리 — 핵심 시설 사수" if won else "패배 — 핵심 시설 함락"
    _result_title.add_theme_color_override("font_color", C_TEAL if won else C_RED)
    for row: Array in ResultModel.lines(m) + ResultModel.economy_lines(m):
        var h: HBoxContainer = HBoxContainer.new()
        var k: Label = _make_label(str(row[0]), FONT_BODY, C_PAPER.darkened(0.25), false)
        k.custom_minimum_size = Vector2(170.0, 0.0)
        k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        var val: Label = _make_label(str(row[1]), FONT_BODY, C_PAPER, false)
        h.add_child(k)
        h.add_child(val)
        _result_rows.add_child(h)
    var w: Variant = m.get("recovery_world", null)
    _result_marker = Vector2(float(w[0]), float(w[1])) if w != null else Vector2.INF
    _result_map.queue_redraw()


## Default focus per screen (D-040: CONFIRM defaults to 취소).
func _focus_default(state_name: String) -> void:
    var intent: String = ""
    match state_name:
        "TITLE": intent = "title_start"
        "PAUSED": intent = "pause_continue"
        "SETTINGS": intent = "settings_window_mode"
        "CONFIRM": intent = "confirm_cancel"
        "RESULT": intent = "result_restart"
    if intent != "" and _buttons.has(intent):
        (_buttons[intent] as Button).call_deferred("grab_focus")


func button(intent: String) -> Button:
    return _buttons.get(intent, null)


func current_state() -> String:
    return _current


## True when the button's panel is the one shown right now.
func button_visible(intent: String) -> bool:
    if not visible or not _buttons.has(intent):
        return false
    var panel: String = str(_button_panel.get(intent, ""))
    return panel == _current and (_buttons[intent] as Button).visible


## Buttons visible right now (for the evidence log / tests).
func visible_buttons() -> Array:
    var out: Array = []
    for k: String in _buttons:
        if button_visible(k):
            out.append(k)
    out.sort()
    return out
