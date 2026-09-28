extends RefCounted
## Editable stage-map data shared by the runtime map editor and headless tests.
## The early-game contract is explicit: an open field surrounds a sealed castle,
## enemies spawn randomly around one off-screen centre, enter through a marked
## field entry, and then pass through the castle gate before the objective.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")

enum MapType { FLAT, TERRAIN }
enum Cell { OPEN, WALL, GATE, ENTRY }

const FORMAT_VERSION: int = 3
const DEFAULT_WIDTH: int = 64
const DEFAULT_HEIGHT: int = 36

var stage_id: String = "stage_001"
var stage_name: String = "초반 일반 필드"
var map_type: int = MapType.FLAT
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var cells: PackedByteArray = PackedByteArray()
var spawn_center: Vector2i = Vector2i(-1, -1)
var spawn_radius_cells: float = 4.0
var spawn_sample_count: int = 12
var gates: Array[Vector2i] = []
var entries: Array[Vector2i] = []
var goal: Vector2i = Vector2i(-1, -1)
var castle_rect: Rect2i = Rect2i()
var tuning: Dictionary = {"wave_count": 3, "spawn_rate": 8.0, "test_duration": 60.0}


func _init(w: int = DEFAULT_WIDTH, h: int = DEFAULT_HEIGHT) -> void:
    width = w
    height = h
    cells.resize(width * height)
    cells.fill(Cell.OPEN)


static func flat_template() -> RefCounted:
    var data = new()
    data.map_type = MapType.FLAT
    data.stage_id = "stage_001"
    data.stage_name = "초반 일반 필드"
    data._build_base_castle()
    return data


static func terrain_template() -> RefCounted:
    var data = new()
    data.map_type = MapType.TERRAIN
    data.stage_id = "stage_003"
    data.stage_name = "지형 도입 필드"
    data._build_base_castle()
    # Deliberately simple terrain samples. They alter approach lanes without
    # replacing the gate as the only castle entry.
    data._fill_rect(Rect2i(9, 8, 9, 2), Cell.WALL)
    data._fill_rect(Rect2i(46, 25, 9, 2), Cell.WALL)
    data._fill_rect(Rect2i(6, 26, 7, 2), Cell.WALL)
    data._fill_rect(Rect2i(51, 7, 7, 2), Cell.WALL)
    return data


func _build_base_castle() -> void:
    cells.fill(Cell.OPEN)
    spawn_center = Vector2i(-1, -1)
    gates.clear()
    entries.clear()
    for x: int in range(width):
        set_cell(Vector2i(x, 0), Cell.WALL)
        set_cell(Vector2i(x, height - 1), Cell.WALL)
    for y: int in range(height):
        set_cell(Vector2i(0, y), Cell.WALL)
        set_cell(Vector2i(width - 1, y), Cell.WALL)

    # Field entry at the bottom edge. Off-screen enemies first approach this
    # opening, then use the normal grid path toward the castle gate.
    for x: int in range(29, 34):
        set_cell(Vector2i(x, height - 1), Cell.ENTRY)

    castle_rect = Rect2i(24, 10, 16, 16)
    var left: int = castle_rect.position.x
    var right: int = castle_rect.end.x - 1
    var top: int = castle_rect.position.y
    var bottom: int = castle_rect.end.y - 1
    for x: int in range(left, right + 1):
        set_cell(Vector2i(x, top), Cell.WALL)
        set_cell(Vector2i(x, bottom), Cell.WALL)
    for y: int in range(top, bottom + 1):
        set_cell(Vector2i(left, y), Cell.WALL)
        set_cell(Vector2i(right, y), Cell.WALL)

    # One main gate represented by a two-cell opening.
    set_cell(Vector2i(31, bottom), Cell.GATE)
    set_cell(Vector2i(32, bottom), Cell.GATE)
    goal = Vector2i(31, 17)
    # Early stages use one approach origin. Individual monsters are scattered
    # randomly inside this radius instead of coming from fixed spawn points.
    spawn_center = Vector2i(31, height + 4)
    spawn_radius_cells = 3.0
    spawn_sample_count = 12


func _fill_rect(rect: Rect2i, value: int) -> void:
    for y: int in range(rect.position.y, rect.end.y):
        for x: int in range(rect.position.x, rect.end.x):
            set_cell(Vector2i(x, y), value)


func in_bounds(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func index(cell: Vector2i) -> int:
    return cell.y * width + cell.x


func cell_at(cell: Vector2i) -> int:
    if not in_bounds(cell):
        return Cell.WALL
    return int(cells[index(cell)])


func set_cell(cell: Vector2i, value: int) -> void:
    if not in_bounds(cell):
        return
    _erase_vector(gates, cell)
    _erase_vector(entries, cell)
    cells[index(cell)] = value
    if value == Cell.GATE:
        gates.append(cell)
    elif value == Cell.ENTRY:
        entries.append(cell)
    if value == Cell.WALL and spawn_center == cell:
        spawn_center = Vector2i(-1, -1)


func set_spawn_center(cell: Vector2i) -> void:
    if in_bounds(cell) and cell_at(cell) == Cell.WALL:
        return
    spawn_center = cell


func set_goal(cell: Vector2i) -> void:
    if not in_bounds(cell):
        return
    if cell_at(cell) == Cell.WALL:
        set_cell(cell, Cell.OPEN)
    goal = cell


func generated_spawn_points(seed_value: int = -1) -> Array[Vector2i]:
    var points: Array[Vector2i] = []
    if in_bounds(spawn_center):
        return points
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = seed_value if seed_value >= 0 else (stage_id.hash() ^ 20260924)
    var wanted: int = maxi(spawn_sample_count, 1)
    var attempts: int = 0
    while points.size() < wanted and attempts < wanted * 50:
        attempts += 1
        var angle: float = rng.randf_range(0.0, TAU)
        # sqrt gives a uniform distribution over the circle's area.
        var distance: float = sqrt(rng.randf()) * spawn_radius_cells
        var candidate: Vector2i = spawn_center + Vector2i(
            roundi(cos(angle) * distance), roundi(sin(angle) * distance))
        if in_bounds(candidate) or points.has(candidate):
            continue
        points.append(candidate)
    return points


func nearest_entry(spawn: Vector2i) -> Vector2i:
    var best: Vector2i = Vector2i(-1, -1)
    var best_distance: float = INF
    for entry: Vector2i in entries:
        var distance: float = Vector2(spawn).distance_squared_to(Vector2(entry))
        if distance < best_distance:
            best_distance = distance
            best = entry
    return best


func offscreen_route(spawn: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if in_bounds(spawn):
        return result
    var entry: Vector2i = nearest_entry(spawn)
    if not in_bounds(entry):
        return result
    var inside_path: Array[Vector2i] = shortest_gate_path(entry)
    if inside_path.is_empty():
        return result
    result.append(spawn)
    result.append_array(inside_path)
    return result


static func _erase_vector(list: Array[Vector2i], value: Vector2i) -> void:
    var at: int = list.find(value)
    if at >= 0:
        list.remove_at(at)


func map_type_name() -> String:
    return "지형 없음" if map_type == MapType.FLAT else "지형 있음"


func build_grid() -> TerrainGrid:
    var grid: TerrainGrid = TerrainGrid.new(width, height)
    for y: int in range(height):
        for x: int in range(width):
            if cell_at(Vector2i(x, y)) != Cell.WALL:
                grid.carve_open(x, y, x, y)
    return grid


func build_path(grid: TerrainGrid = null) -> PathNetwork:
    var result_grid: TerrainGrid = grid if grid != null else build_grid()
    var path: PathNetwork = PathNetwork.new(result_grid)
    path.set_goal(goal.x, goal.y)
    for i: int in range(entries.size()):
        var route_cells: PackedInt32Array = PackedInt32Array([result_grid.idx(entries[i].x, entries[i].y)])
        path.add_route("SPAWN_%02d" % (i + 1), route_cells)
    path.rebuild()
    return path


func shortest_gate_path(start: Vector2i) -> Array[Vector2i]:
    var empty: Array[Vector2i] = []
    if not in_bounds(start) or not in_bounds(goal):
        return empty
    if cell_at(start) == Cell.WALL or cell_at(goal) == Cell.WALL:
        return empty

    # State = cell index * 2 + whether a gate has been crossed. Reaching the
    # goal without crossing a gate is intentionally not accepted.
    var state_count: int = width * height * 2
    var parent: PackedInt32Array = PackedInt32Array()
    parent.resize(state_count)
    parent.fill(-2)
    var start_gate: int = 1 if cell_at(start) == Cell.GATE else 0
    var start_state: int = index(start) * 2 + start_gate
    var queue: Array[int] = [start_state]
    parent[start_state] = -1
    var cursor: int = 0
    var target_state: int = index(goal) * 2 + 1
    var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

    while cursor < queue.size():
        var state: int = queue[cursor]
        cursor += 1
        if state == target_state:
            break
        var ci: int = state / 2
        var passed_gate: bool = state % 2 == 1
        var current: Vector2i = Vector2i(ci % width, ci / width)
        for dir: Vector2i in dirs:
            var next: Vector2i = current + dir
            if not in_bounds(next) or cell_at(next) == Cell.WALL:
                continue
            var gate_seen: int = 1 if passed_gate or cell_at(next) == Cell.GATE else 0
            var next_state: int = index(next) * 2 + gate_seen
            if parent[next_state] != -2:
                continue
            parent[next_state] = state
            queue.append(next_state)

    if parent[target_state] == -2:
        return empty
    var reversed: Array[Vector2i] = []
    var walk: int = target_state
    while walk >= 0:
        var cell_index: int = walk / 2
        reversed.append(Vector2i(cell_index % width, cell_index / width))
        walk = parent[walk]
    reversed.reverse()
    return reversed


func validate() -> Dictionary:
    var checks: Array = []
    var paths: Array = []
    _add_check(checks, stage_id.strip_edges() != "", "스테이지 ID", "저장·비교용 ID가 필요합니다.")
    _add_check(checks, in_bounds(goal) and cell_at(goal) != Cell.WALL,
        "최종 방어 목표", "목표가 맵 안의 이동 가능 셀에 있어야 합니다.")
    _add_check(checks, not in_bounds(spawn_center),
        "화면 밖 생성 중심", "몬스터 생성 중심은 화면과 맵 경계 바깥에 있어야 합니다.")
    _add_check(checks, spawn_radius_cells >= 1.0, "랜덤 생성 반경", "생성 반경은 한 칸 이상이어야 합니다.")
    _add_check(checks, gates.size() > 0, "성문", "성벽 진입 지점인 성문이 필요합니다.")
    _add_check(checks, _entries_are_valid(), "외곽 진입점",
        "화면 밖 몬스터가 필드로 들어올 수 있도록 맵 가장자리에 진입점을 둡니다.")
    _add_check(checks, _castle_perimeter_is_closed(), "성벽 폐쇄", "성문을 제외한 성벽 둘레가 막혀 있어야 합니다.")
    _add_check(checks, float(tuning.get("wave_count", 0)) > 0.0 and float(tuning.get("spawn_rate", 0.0)) > 0.0,
        "웨이브 설정", "웨이브 수와 초당 생성 수는 0보다 커야 합니다.")

    var samples: Array[Vector2i] = generated_spawn_points()
    var enough_samples: bool = samples.size() == spawn_sample_count
    _add_check(checks, enough_samples, "랜덤 분산 표본",
        "중심 반경 안에 서로 다른 생성 후보 %d개를 확보해야 합니다." % spawn_sample_count)
    var outside: bool = not in_bounds(spawn_center)
    var routes_ok: bool = enough_samples
    for spawn: Vector2i in samples:
        if in_bounds(spawn):
            outside = false
        var route: Array[Vector2i] = offscreen_route(spawn)
        paths.append(route)
        if route.is_empty():
            routes_ok = false
    _add_check(checks, outside, "화면 밖 랜덤 생성", "생성 중심과 랜덤 표본은 모두 화면 바깥이어야 합니다.")
    _add_check(checks, routes_ok, "침입 전체 동선",
        "모든 랜덤 표본이 외곽 진입점, 성문, 최종 목표 순서로 연결되어야 합니다.")

    if map_type == MapType.FLAT:
        _add_check(checks, _extra_terrain_count() == 0, "초반 일반 필드",
            "지형 없는 맵에는 외곽 경계와 성벽 외 장애물을 두지 않습니다.")
    else:
        _add_check(checks, _extra_terrain_count() > 0, "지형 요소",
            "지형 있는 맵에는 성벽 이외 이동 장애물이 하나 이상 있어야 합니다.")

    var errors: Array[String] = []
    for check: Dictionary in checks:
        if not check["ok"]:
            errors.append("%s: %s" % [check["label"], check["detail"]])
    return {"ok": errors.is_empty(), "checks": checks, "errors": errors, "paths": paths}


static func _add_check(checks: Array, ok: bool, label: String, detail: String) -> void:
    checks.append({"ok": ok, "label": label, "detail": detail})


func _castle_perimeter_is_closed() -> bool:
    if castle_rect.size.x < 3 or castle_rect.size.y < 3:
        return false
    var left: int = castle_rect.position.x
    var right: int = castle_rect.end.x - 1
    var top: int = castle_rect.position.y
    var bottom: int = castle_rect.end.y - 1
    for x: int in range(left, right + 1):
        if not _is_castle_barrier(Vector2i(x, top)) or not _is_castle_barrier(Vector2i(x, bottom)):
            return false
    for y: int in range(top, bottom + 1):
        if not _is_castle_barrier(Vector2i(left, y)) or not _is_castle_barrier(Vector2i(right, y)):
            return false
    return true


func _is_castle_barrier(cell: Vector2i) -> bool:
    return cell_at(cell) == Cell.WALL or cell_at(cell) == Cell.GATE


func _entries_are_valid() -> bool:
    if entries.is_empty():
        return false
    for entry: Vector2i in entries:
        var edge: bool = entry.x == 0 or entry.y == 0 or entry.x == width - 1 or entry.y == height - 1
        if not edge or cell_at(entry) != Cell.ENTRY:
            return false
    return true


func _extra_terrain_count() -> int:
    var count: int = 0
    for y: int in range(1, height - 1):
        for x: int in range(1, width - 1):
            var cell: Vector2i = Vector2i(x, y)
            if cell_at(cell) != Cell.WALL:
                continue
            var on_castle: bool = castle_rect.has_point(cell) and (
                x == castle_rect.position.x or x == castle_rect.end.x - 1
                or y == castle_rect.position.y or y == castle_rect.end.y - 1)
            if not on_castle:
                count += 1
    return count


func to_dictionary() -> Dictionary:
    var cell_values: Array[int] = []
    for value: int in cells:
        cell_values.append(value)
    var gate_values: Array = []
    for gate: Vector2i in gates:
        gate_values.append([gate.x, gate.y])
    var entry_values: Array = []
    for entry: Vector2i in entries:
        entry_values.append([entry.x, entry.y])
    return {
        "format_version": FORMAT_VERSION,
        "stage_id": stage_id,
        "stage_name": stage_name,
        "map_type": "flat" if map_type == MapType.FLAT else "terrain",
        "width": width,
        "height": height,
        "cells": cell_values,
        "spawn_center": [spawn_center.x, spawn_center.y],
        "spawn_radius_cells": spawn_radius_cells,
        "spawn_sample_count": spawn_sample_count,
        "gates": gate_values,
        "entries": entry_values,
        "goal": [goal.x, goal.y],
        "castle_rect": [castle_rect.position.x, castle_rect.position.y, castle_rect.size.x, castle_rect.size.y],
        "tuning": tuning.duplicate(true),
    }


static func from_dictionary(raw: Dictionary) -> RefCounted:
    var w: int = int(raw.get("width", DEFAULT_WIDTH))
    var h: int = int(raw.get("height", DEFAULT_HEIGHT))
    var data = new(w, h)
    data.stage_id = str(raw.get("stage_id", "stage_custom"))
    data.stage_name = str(raw.get("stage_name", "사용자 스테이지"))
    data.map_type = MapType.TERRAIN if str(raw.get("map_type", "flat")) == "terrain" else MapType.FLAT
    var raw_cells: Array = raw.get("cells", [])
    if raw_cells.size() == w * h:
        for i: int in range(raw_cells.size()):
            data.cells[i] = int(raw_cells[i])
    var raw_center: Array = raw.get("spawn_center", [])
    if raw_center.size() >= 2:
        data.spawn_center = Vector2i(int(raw_center[0]), int(raw_center[1]))
    else:
        # v1 migration: use the first former fixed spawn as the new centre.
        var legacy_spawns: Array = raw.get("spawns", [])
        if not legacy_spawns.is_empty() and (legacy_spawns[0] as Array).size() >= 2:
            data.spawn_center = Vector2i(int(legacy_spawns[0][0]), int(legacy_spawns[0][1]))
    data.spawn_radius_cells = float(raw.get("spawn_radius_cells", 4.0))
    data.spawn_sample_count = int(raw.get("spawn_sample_count", 12))
    data.gates.clear()
    for item: Array in raw.get("gates", []):
        if item.size() >= 2:
            data.gates.append(Vector2i(int(item[0]), int(item[1])))
    data.entries.clear()
    for item: Array in raw.get("entries", []):
        if item.size() >= 2:
            data.entries.append(Vector2i(int(item[0]), int(item[1])))
    var raw_goal: Array = raw.get("goal", [-1, -1])
    data.goal = Vector2i(int(raw_goal[0]), int(raw_goal[1])) if raw_goal.size() >= 2 else Vector2i(-1, -1)
    var raw_castle: Array = raw.get("castle_rect", [0, 0, 0, 0])
    if raw_castle.size() >= 4:
        data.castle_rect = Rect2i(int(raw_castle[0]), int(raw_castle[1]), int(raw_castle[2]), int(raw_castle[3]))
    data.tuning = (raw.get("tuning", {}) as Dictionary).duplicate(true)
    return data


func save_json(path: String) -> bool:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(to_dictionary(), "  ") + "\n")
    file.close()
    return true


static func load_json(path: String) -> RefCounted:
    if not FileAccess.file_exists(path):
        return null
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        return null
    return from_dictionary(parsed)
