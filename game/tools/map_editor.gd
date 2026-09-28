extends Node2D
## Runtime stage map editor. Run with:
## godot --path . res://game/tools/map_editor.tscn

const StageMap := preload("res://game/maps/stage_map_definition.gd")

const PANEL_WIDTH: float = 400.0
const CANVAS_ORIGIN: Vector2 = Vector2(430.0, 78.0)
const CELL_PIXELS: float = 20.0

enum Tool { WALL, OPEN, GATE, ENTRY, SPAWN, GOAL }

const OUTSIDE_ROWS: int = 8

var data = null
var active_tool: int = Tool.WALL
var validation: Dictionary = {}
var preview_paths: Array = []
var test_running: bool = false
var test_clock: float = 0.0

var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _type_option: OptionButton = null
var _tool_option: OptionButton = null
var _wave_spin: SpinBox = null
var _rate_spin: SpinBox = null
var _radius_spin: SpinBox = null
var _checklist: RichTextLabel = null
var _status: Label = null


func _ready() -> void:
    data = StageMap.flat_template()
    _build_ui()
    _sync_ui_from_data()
    _validate_and_preview(false)
    set_process(true)
    queue_redraw()


func _build_ui() -> void:
    var panel: PanelContainer = PanelContainer.new()
    panel.position = Vector2(12.0, 12.0)
    panel.size = Vector2(PANEL_WIDTH, 1056.0)
    add_child(panel)

    var margin: MarginContainer = MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 14)
    margin.add_theme_constant_override("margin_right", 14)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(margin)
    var column: VBoxContainer = VBoxContainer.new()
    column.add_theme_constant_override("separation", 8)
    margin.add_child(column)

    var title: Label = Label.new()
    title.text = "스테이지 맵 에디터"
    title.add_theme_font_size_override("font_size", 26)
    column.add_child(title)
    column.add_child(_label("스테이지별로 맵 규칙과 몬스터 동선을 저장·검증합니다."))

    column.add_child(_label("스테이지 ID"))
    _id_edit = LineEdit.new()
    _id_edit.placeholder_text = "stage_001"
    column.add_child(_id_edit)
    column.add_child(_label("스테이지 이름"))
    _name_edit = LineEdit.new()
    column.add_child(_name_edit)

    column.add_child(_label("맵 구분"))
    _type_option = OptionButton.new()
    _type_option.add_item("지형 없음 · 초반 일반 필드", StageMap.MapType.FLAT)
    _type_option.add_item("지형 있음 · 확장 필드", StageMap.MapType.TERRAIN)
    column.add_child(_type_option)

    var template_row: HBoxContainer = HBoxContainer.new()
    template_row.add_child(_button("기본맵 새로 만들기", func() -> void: _new_template(StageMap.MapType.FLAT)))
    template_row.add_child(_button("지형맵 새로 만들기", func() -> void: _new_template(StageMap.MapType.TERRAIN)))
    column.add_child(template_row)

    column.add_child(_label("편집 도구 · 단축키 1~6"))
    _tool_option = OptionButton.new()
    _tool_option.add_item("1 성벽/지형", Tool.WALL)
    _tool_option.add_item("2 일반 필드", Tool.OPEN)
    _tool_option.add_item("3 성문", Tool.GATE)
    _tool_option.add_item("4 외곽 진입점", Tool.ENTRY)
    _tool_option.add_item("5 화면 밖 생성 중심", Tool.SPAWN)
    _tool_option.add_item("6 최종 방어 목표", Tool.GOAL)
    _tool_option.item_selected.connect(func(index: int) -> void:
        active_tool = _tool_option.get_item_id(index)
        queue_redraw())
    column.add_child(_tool_option)

    var tuning_row: HBoxContainer = HBoxContainer.new()
    var wave_box: VBoxContainer = VBoxContainer.new()
    wave_box.add_child(_label("웨이브 수"))
    _wave_spin = SpinBox.new()
    _wave_spin.min_value = 1
    _wave_spin.max_value = 99
    _wave_spin.custom_minimum_size.x = 160
    wave_box.add_child(_wave_spin)
    tuning_row.add_child(wave_box)
    var rate_box: VBoxContainer = VBoxContainer.new()
    rate_box.add_child(_label("초당 생성 수"))
    _rate_spin = SpinBox.new()
    _rate_spin.min_value = 0.5
    _rate_spin.max_value = 100
    _rate_spin.step = 0.5
    _rate_spin.custom_minimum_size.x = 160
    rate_box.add_child(_rate_spin)
    tuning_row.add_child(rate_box)
    column.add_child(tuning_row)

    var radius_box: VBoxContainer = VBoxContainer.new()
    radius_box.add_child(_label("랜덤 생성 반경 (칸)"))
    _radius_spin = SpinBox.new()
    _radius_spin.min_value = 1.0
    _radius_spin.max_value = 15.0
    _radius_spin.step = 0.5
    _radius_spin.custom_minimum_size.x = 150
    radius_box.add_child(_radius_spin)
    column.add_child(radius_box)

    var action_row: HBoxContainer = HBoxContainer.new()
    action_row.add_child(_button("검증·동선 테스트 (V)", func() -> void: _validate_and_preview(true)))
    action_row.add_child(_button("테스트 정지", func() -> void:
        test_running = false
        queue_redraw()))
    column.add_child(action_row)
    var file_row: HBoxContainer = HBoxContainer.new()
    file_row.add_child(_button("스테이지 저장 (S)", _save_stage))
    file_row.add_child(_button("불러오기 (L)", _load_stage))
    column.add_child(file_row)

    column.add_child(_label("기획 검증 결과"))
    _checklist = RichTextLabel.new()
    _checklist.bbcode_enabled = true
    _checklist.fit_content = false
    _checklist.custom_minimum_size = Vector2(360.0, 300.0)
    column.add_child(_checklist)
    _status = _label("")
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.custom_minimum_size.y = 48
    column.add_child(_status)
    column.add_child(_label("LMB: 선택 도구 적용 · RMB: 일반 필드로 지우기\nV: 검증/이동 테스트 · S/L: 저장/불러오기"))


static func _label(text: String) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return label


static func _button(text: String, callback: Callable) -> Button:
    var button: Button = Button.new()
    button.text = text
    button.pressed.connect(callback)
    return button


func _new_template(type: int) -> void:
    data = StageMap.flat_template() if type == StageMap.MapType.FLAT else StageMap.terrain_template()
    validation = {}
    preview_paths.clear()
    test_running = false
    _sync_ui_from_data()
    _validate_and_preview(false)


func _sync_ui_from_data() -> void:
    _id_edit.text = data.stage_id
    _name_edit.text = data.stage_name
    _type_option.select(0 if data.map_type == StageMap.MapType.FLAT else 1)
    _wave_spin.value = float(data.tuning.get("wave_count", 3))
    _rate_spin.value = float(data.tuning.get("spawn_rate", 8.0))
    _radius_spin.value = data.spawn_radius_cells


func _sync_data_from_ui() -> void:
    data.stage_id = _id_edit.text.strip_edges()
    data.stage_name = _name_edit.text.strip_edges()
    data.map_type = _type_option.get_item_id(_type_option.selected)
    data.tuning["wave_count"] = int(_wave_spin.value)
    data.tuning["spawn_rate"] = _rate_spin.value
    data.spawn_radius_cells = _radius_spin.value


func _stage_path() -> String:
    var safe_id: String = data.stage_id.to_lower().validate_filename().replace(" ", "_")
    if safe_id == "":
        safe_id = "stage_custom"
    return "user://stage_maps/%s.json" % safe_id


func _save_stage() -> void:
    _sync_data_from_ui()
    _validate_and_preview(false)
    if not validation.get("ok", false):
        _status.text = "저장 전 검증 실패: 빨간 항목을 먼저 수정하세요."
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://stage_maps"))
    var path: String = _stage_path()
    if data.save_json(path):
        _status.text = "저장 완료: %s" % ProjectSettings.globalize_path(path)
    else:
        _status.text = "저장 실패: %s" % ProjectSettings.globalize_path(path)


func _load_stage() -> void:
    _sync_data_from_ui()
    var path: String = _stage_path()
    var loaded = StageMap.load_json(path)
    if loaded == null:
        _status.text = "불러올 파일이 없습니다: %s" % ProjectSettings.globalize_path(path)
        return
    data = loaded
    test_running = false
    _sync_ui_from_data()
    _validate_and_preview(false)
    _status.text = "불러오기 완료: %s" % ProjectSettings.globalize_path(path)


func _validate_and_preview(run_test: bool) -> void:
    _sync_data_from_ui()
    validation = data.validate()
    preview_paths = validation.get("paths", [])
    _render_checklist()
    test_running = run_test and validation.get("ok", false)
    test_clock = 0.0
    if run_test:
        _status.text = "동선 테스트 실행 중" if test_running else "동선 테스트 불가: 검증 실패 항목을 수정하세요."
    queue_redraw()


func _render_checklist() -> void:
    var lines: Array[String] = []
    for check: Dictionary in validation.get("checks", []):
        var color: String = "#6ee7a8" if check["ok"] else "#ff7b72"
        var mark: String = "PASS" if check["ok"] else "FAIL"
        lines.append("[color=%s]● %s[/color]  %s" % [color, mark, check["label"]])
        if not check["ok"]:
            lines.append("    %s" % check["detail"])
    _checklist.text = "\n".join(lines)


func _process(delta: float) -> void:
    if test_running:
        test_clock += delta
        queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
                active_tool = int(event.keycode - KEY_1)
                _tool_option.select(active_tool)
                queue_redraw()
            KEY_V:
                _validate_and_preview(true)
            KEY_S:
                _save_stage()
            KEY_L:
                _load_stage()
    if event is InputEventMouseButton and event.pressed:
        var cell: Vector2i = _mouse_cell(event.position)
        var spawn_area: bool = _is_spawn_edit_area(cell)
        if active_tool == Tool.SPAWN and spawn_area and event.button_index == MOUSE_BUTTON_LEFT:
            data.set_spawn_center(cell)
            _map_changed()
            return
        if not data.in_bounds(cell):
            return
        if event.button_index == MOUSE_BUTTON_RIGHT:
            data.set_cell(cell, StageMap.Cell.OPEN)
            _map_changed()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            _apply_tool(cell)
    elif event is InputEventMouseMotion and event.button_mask != 0:
        var cell: Vector2i = _mouse_cell(event.position)
        if active_tool == Tool.SPAWN and _is_spawn_edit_area(cell) and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
            data.set_spawn_center(cell)
            _map_changed()
            return
        if not data.in_bounds(cell):
            return
        if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
            data.set_cell(cell, StageMap.Cell.OPEN)
            _map_changed()
        elif event.button_mask & MOUSE_BUTTON_MASK_LEFT and active_tool in [Tool.WALL, Tool.OPEN]:
            _apply_tool(cell)


func _apply_tool(cell: Vector2i) -> void:
    match active_tool:
        Tool.WALL:
            data.set_cell(cell, StageMap.Cell.WALL)
        Tool.OPEN:
            data.set_cell(cell, StageMap.Cell.OPEN)
        Tool.GATE:
            data.set_cell(cell, StageMap.Cell.GATE)
        Tool.ENTRY:
            data.set_cell(cell, StageMap.Cell.ENTRY)
        Tool.SPAWN:
            data.set_spawn_center(cell)
        Tool.GOAL:
            data.set_goal(cell)
    _map_changed()


func _map_changed() -> void:
    test_running = false
    validation = {}
    preview_paths.clear()
    _status.text = "변경됨 · V를 눌러 기획 규칙과 동선을 다시 검증하세요."
    queue_redraw()


func _mouse_cell(mouse: Vector2) -> Vector2i:
    var local: Vector2 = mouse - CANVAS_ORIGIN
    return Vector2i(int(floor(local.x / CELL_PIXELS)), int(floor(local.y / CELL_PIXELS)))


func _is_spawn_edit_area(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < data.width and cell.y >= data.height and cell.y < data.height + OUTSIDE_ROWS


func _cell_rect(cell: Vector2i) -> Rect2:
    return Rect2(CANVAS_ORIGIN + Vector2(cell) * CELL_PIXELS, Vector2(CELL_PIXELS, CELL_PIXELS))


func _cell_center(cell: Vector2i) -> Vector2:
    return CANVAS_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_PIXELS


func _draw() -> void:
    if data == null:
        return
    var outside_rect: Rect2 = Rect2(
        CANVAS_ORIGIN + Vector2(0, data.height * CELL_PIXELS),
        Vector2(data.width * CELL_PIXELS, OUTSIDE_ROWS * CELL_PIXELS))
    draw_rect(outside_rect, Color(0.08, 0.09, 0.11), true)
    draw_string(ThemeDB.fallback_font, outside_rect.position + Vector2(8, 22),
        "화면 밖 생성 영역", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.65, 0.68, 0.72))
    draw_rect(Rect2(CANVAS_ORIGIN - Vector2(2, 2), Vector2(data.width, data.height) * CELL_PIXELS + Vector2(4, 4)), Color(0.05, 0.06, 0.07), true)
    for y: int in range(data.height):
        for x: int in range(data.width):
            var cell: Vector2i = Vector2i(x, y)
            var color: Color = Color(0.18, 0.24, 0.18)
            match data.cell_at(cell):
                StageMap.Cell.WALL:
                    color = Color(0.29, 0.25, 0.22)
                StageMap.Cell.GATE:
                    color = Color(0.78, 0.55, 0.22)
                StageMap.Cell.ENTRY:
                    color = Color(0.20, 0.72, 0.76)
            draw_rect(_cell_rect(cell), color, true)

    var grid_color: Color = Color(1, 1, 1, 0.08)
    for x: int in range(data.width + 1):
        var px: float = CANVAS_ORIGIN.x + x * CELL_PIXELS
        draw_line(Vector2(px, CANVAS_ORIGIN.y), Vector2(px, CANVAS_ORIGIN.y + data.height * CELL_PIXELS), grid_color)
    for y: int in range(data.height + 1):
        var py: float = CANVAS_ORIGIN.y + y * CELL_PIXELS
        draw_line(Vector2(CANVAS_ORIGIN.x, py), Vector2(CANVAS_ORIGIN.x + data.width * CELL_PIXELS, py), grid_color)

    for path: Array in preview_paths:
        if path.size() < 2:
            continue
        var points: PackedVector2Array = PackedVector2Array()
        for cell: Vector2i in path:
            points.append(_cell_center(cell))
        draw_polyline(points, Color(0.40, 0.78, 1.0, 0.55), 2.0, true)

    var samples: Array[Vector2i] = data.generated_spawn_points()
    for spawn: Vector2i in samples:
        draw_circle(_cell_center(spawn), 4.5, Color(0.95, 0.30, 0.28))
    if _is_spawn_edit_area(data.spawn_center):
        var spawn_center_world: Vector2 = _cell_center(data.spawn_center)
        draw_arc(spawn_center_world, data.spawn_radius_cells * CELL_PIXELS, 0.0, TAU, 64,
            Color(1.0, 0.35, 0.32, 0.65), 2.0)
        draw_circle(spawn_center_world, 8.0, Color(1.0, 0.2, 0.18))
        draw_circle(spawn_center_world, 11.0, Color.WHITE, false, 2.0)
    if data.in_bounds(data.goal):
        var goal_center: Vector2 = _cell_center(data.goal)
        draw_circle(goal_center, 8.0, Color(0.98, 0.84, 0.30))
        draw_line(goal_center - Vector2(6, 0), goal_center + Vector2(6, 0), Color.BLACK, 2)
        draw_line(goal_center - Vector2(0, 6), goal_center + Vector2(0, 6), Color.BLACK, 2)

    if test_running:
        _draw_test_monsters()

    var type_text: String = data.map_type_name()
    draw_string(ThemeDB.fallback_font, CANVAS_ORIGIN + Vector2(0, -20),
        "%s · %s · 빨강=화면 밖 생성 · 청록=외곽 진입 · 금색=성문/목표 · 파랑=동선" % [data.stage_id, type_text],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.92, 0.92, 0.92))


func _draw_test_monsters() -> void:
    for i: int in range(preview_paths.size()):
        var path: Array = preview_paths[i]
        if path.size() < 2:
            continue
        var progress: float = fmod(test_clock * 7.0 + i * 3.0, float(path.size() - 1))
        var segment: int = int(floor(progress))
        var alpha: float = progress - segment
        var a: Vector2 = _cell_center(path[segment])
        var b: Vector2 = _cell_center(path[mini(segment + 1, path.size() - 1)])
        var pos: Vector2 = a.lerp(b, alpha)
        draw_circle(pos, 5.0, Color(0.88, 0.18, 0.22))
        draw_circle(pos, 6.5, Color(0.08, 0.04, 0.04), false, 1.5)
