extends RefCounted
## Editable stage-map data shared by the runtime map editor and headless tests.
## The early-game contract is explicit: an open field surrounds a sealed castle,
## enemies spawn randomly around one off-screen centre, enter through a marked
## field entry, and then pass through the castle gate before the objective.
##
## LD-DEV-01 (map reliability) adds the checks the editor previously skipped:
## the objective must sit inside the castle (AC-M01), the wall may only be
## crossed at a gate on the wall (AC-M02), every cell the random spawn model can
## produce is checked, not just the 12 preview samples (AC-M03), and saved files
## load back with the same types (AC-M05).

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")

enum MapType { FLAT, TERRAIN }
enum Cell { OPEN, WALL, GATE, ENTRY }

## v4: explicit spawn_seed; integer fields must hold whole numbers on load.
const FORMAT_VERSION: int = 4
const DEFAULT_WIDTH: int = 64
const DEFAULT_HEIGHT: int = 36
## spawn_seed < 0 keeps the v1..v3 behaviour: the seed is derived from stage_id.
const DERIVED_SEED_SALT: int = 20260924

## Tuning keys with a fixed type. JSON has one number type, so these are
## converted back on load; other keys are kept as parsed.
const TUNING_INT_KEYS: PackedStringArray = ["wave_count"]
const TUNING_FLOAT_KEYS: PackedStringArray = ["spawn_rate", "test_duration"]

## Objective placement verdicts (AC-M01). "" means accepted.
const GOAL_OUT_OF_BOUNDS: String = "out_of_bounds"
const GOAL_WALL: String = "wall"
const GOAL_GATE: String = "gate"
const GOAL_ENTRY: String = "entry"
const GOAL_NO_CASTLE: String = "no_castle"
const GOAL_OUTSIDE_CASTLE: String = "outside_castle"
const GOAL_MESSAGES: Dictionary = {
    GOAL_OUT_OF_BOUNDS: "맵 범위 밖입니다.",
    GOAL_WALL: "성벽/지형 셀입니다. 벽을 지워 목표를 두지 않습니다.",
    GOAL_GATE: "성문 셀입니다. 성문은 중간 방어선이며 목표가 아닙니다.",
    GOAL_ENTRY: "외곽 진입점 셀입니다.",
    GOAL_NO_CASTLE: "성 영역이 정의되지 않았습니다.",
    GOAL_OUTSIDE_CASTLE: "성 밖입니다. 목표는 성벽·성문을 제외한 성 내부에만 둡니다.",
}

## Spawn candidate verdicts (AC-M03). "" means valid.
const SPAWN_ON_SCREEN: String = "on_screen"
const SPAWN_ON_SCREEN_WALL: String = "on_screen_wall"
const SPAWN_UNREACHABLE: String = "unreachable"

var stage_id: String = "stage_001"
var stage_name: String = "초반 일반 필드"
var map_type: int = MapType.FLAT
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var cells: PackedByteArray = PackedByteArray()
var spawn_center: Vector2i = Vector2i(-1, -1)
var spawn_radius_cells: float = 4.0
var spawn_sample_count: int = 12
var spawn_seed: int = -1
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


## Cells strictly inside the castle wall ring.
func castle_interior() -> Rect2i:
    if castle_rect.size.x < 3 or castle_rect.size.y < 3:
        return Rect2i()
    return castle_rect.grow(-1)


func on_castle_perimeter(cell: Vector2i) -> bool:
    if not castle_rect.has_point(cell):
        return false
    return cell.x == castle_rect.position.x or cell.x == castle_rect.end.x - 1 \
        or cell.y == castle_rect.position.y or cell.y == castle_rect.end.y - 1


## Why `cell` cannot hold the objective, or "" when it can (AC-M01).
func goal_rejection(cell: Vector2i) -> String:
    if not in_bounds(cell):
        return GOAL_OUT_OF_BOUNDS
    match cell_at(cell):
        Cell.WALL:
            return GOAL_WALL
        Cell.GATE:
            return GOAL_GATE
        Cell.ENTRY:
            return GOAL_ENTRY
    var interior: Rect2i = castle_interior()
    if interior.size == Vector2i.ZERO:
        return GOAL_NO_CASTLE
    if not interior.has_point(cell):
        return GOAL_OUTSIDE_CASTLE
    return ""


static func goal_rejection_message(code: String) -> String:
    return str(GOAL_MESSAGES.get(code, code))


## Moves the objective only to an accepted cell. The map is never edited to
## make a placement succeed (no wall carving). Returns the rejection code.
func set_goal(cell: Vector2i) -> String:
    var code: String = goal_rejection(cell)
    if code == "":
        goal = cell
    return code


func effective_spawn_seed() -> int:
    return spawn_seed if spawn_seed >= 0 else (stage_id.hash() ^ DERIVED_SEED_SALT)


func generated_spawn_points(seed_value: int = -1) -> Array[Vector2i]:
    var points: Array[Vector2i] = []
    if in_bounds(spawn_center):
        return points
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = seed_value if seed_value >= 0 else effective_spawn_seed()
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


## Every integer cell the random model above can produce (AC-M03).
## A point p with |p| <= r rounds to (dx, dy) only if p lies in the closed unit
## box around (dx, dy), so the box's nearest point must be within r. The set is
## exact up to measure-zero boundary touches, which are kept (conservative).
## Order: row-major from the top-left, independent of the RNG.
func spawn_candidate_cells() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if spawn_radius_cells < 0.0:
        return out
    var reach: int = ceili(spawn_radius_cells + 0.5)
    for dy: int in range(-reach, reach + 1):
        for dx: int in range(-reach, reach + 1):
            var nx: float = maxf(absf(dx) - 0.5, 0.0)
            var ny: float = maxf(absf(dy) - 0.5, 0.0)
            if nx * nx + ny * ny <= spawn_radius_cells * spawn_radius_cells + 1e-9:
                out.append(spawn_center + Vector2i(dx, dy))
    return out


## "" for a usable spawn cell, otherwise why it is not. `entry_ok` caches the
## per-entry route verdict: the route after the entry does not depend on the
## spawn cell.
func spawn_candidate_rejection(cell: Vector2i, entry_ok: Dictionary) -> String:
    if in_bounds(cell):
        return SPAWN_ON_SCREEN_WALL if cell_at(cell) == Cell.WALL else SPAWN_ON_SCREEN
    var entry: Vector2i = nearest_entry(cell)
    if not in_bounds(entry):
        return SPAWN_UNREACHABLE
    if not entry_ok.has(entry):
        entry_ok[entry] = route_order_problem(offscreen_route(cell)) == ""
    return "" if entry_ok[entry] else SPAWN_UNREACHABLE


func spawn_candidate_report() -> Dictionary:
    var candidates: Array[Vector2i] = spawn_candidate_cells()
    var counts: Dictionary = {SPAWN_ON_SCREEN: 0, SPAWN_ON_SCREEN_WALL: 0, SPAWN_UNREACHABLE: 0}
    var rejected: Array = []
    var entry_ok: Dictionary = {}
    var valid: int = 0
    for cell: Vector2i in candidates:
        var reason: String = spawn_candidate_rejection(cell, entry_ok)
        if reason == "":
            valid += 1
        else:
            counts[reason] = int(counts[reason]) + 1
            rejected.append({"cell": [cell.x, cell.y], "reason": reason})
    return {
        "center": [spawn_center.x, spawn_center.y],
        "radius_cells": spawn_radius_cells,
        "total": candidates.size(),
        "valid": valid,
        "rejected_counts": counts,
        "rejected": rejected,
    }


## Nearest field entry; ties go to the smaller x, then the smaller y, so the
## result does not depend on the order entries were painted or loaded.
func nearest_entry(spawn: Vector2i) -> Vector2i:
    var best: Vector2i = Vector2i(-1, -1)
    var best_distance: float = INF
    for entry: Vector2i in entries:
        var distance: float = Vector2(spawn).distance_squared_to(Vector2(entry))
        if distance < best_distance or (distance == best_distance
                and (entry.x < best.x or (entry.x == best.x and entry.y < best.y))):
            best_distance = distance
            best = entry
    return best


## [spawn, entry, ..., gate, ..., goal]. The first step is the off-screen
## approach (not a grid walk); the rest is a 4-neighbour grid path.
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


## "" when `route` keeps the order off-screen spawn -> field entry -> gate ->
## objective, stays outside the castle before the gate and inside after it,
## and moves one grid step at a time after the entry (AC-M02).
func route_order_problem(route: Array) -> String:
    if route.size() < 3:
        return "no_route"
    if in_bounds(route[0]):
        return "spawn_on_screen"
    if cell_at(route[1]) != Cell.ENTRY:
        return "entry_not_first"
    var gate_at: int = -1
    for i: int in range(1, route.size()):
        var cell: Vector2i = route[i]
        if i > 1:
            var step: Vector2i = cell - (route[i - 1] as Vector2i)
            if absi(step.x) + absi(step.y) != 1:
                return "discontinuous"
        if cell_at(cell) == Cell.WALL:
            return "through_wall"
        if gate_at < 0:
            if cell_at(cell) == Cell.GATE:
                gate_at = i
            elif castle_rect.has_point(cell):
                return "inside_before_gate"
        elif not castle_rect.has_point(cell):
            return "left_castle_after_gate"
    if gate_at < 0:
        return "no_gate"
    if route[route.size() - 1] != goal:
        return "goal_not_reached"
    return ""


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


## 4-neighbour flood over non-wall cells. Gates count as closed when
## `gates_closed`. 4-neighbour reachability equals the battle PathNetwork's
## (8 directions without corner cutting), so the verdict carries over.
func _flood(starts: Array[Vector2i], gates_closed: bool) -> PackedByteArray:
    var seen: PackedByteArray = PackedByteArray()
    seen.resize(width * height)
    var queue: Array[Vector2i] = []
    for s: Vector2i in starts:
        if in_bounds(s) and seen[index(s)] == 0 and _floodable(s, gates_closed):
            seen[index(s)] = 1
            queue.append(s)
    var cursor: int = 0
    var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
    while cursor < queue.size():
        var current: Vector2i = queue[cursor]
        cursor += 1
        for dir: Vector2i in dirs:
            var next: Vector2i = current + dir
            if not in_bounds(next) or seen[index(next)] != 0 or not _floodable(next, gates_closed):
                continue
            seen[index(next)] = 1
            queue.append(next)
    return seen


func _floodable(cell: Vector2i, gates_closed: bool) -> bool:
    var value: int = cell_at(cell)
    return value != Cell.WALL and not (gates_closed and value == Cell.GATE)


## Castle cells reachable from the field without crossing a gate. Empty for a
## sealed castle; otherwise the listed perimeter cells are the holes.
func wall_leak_cells() -> Array[Vector2i]:
    var leaks: Array[Vector2i] = []
    if castle_interior().size == Vector2i.ZERO:
        return leaks
    var outside: Array[Vector2i] = []
    for y: int in range(height):
        for x: int in range(width):
            var cell: Vector2i = Vector2i(x, y)
            if not castle_rect.has_point(cell):
                outside.append(cell)
    var seen: PackedByteArray = _flood(outside, true)
    var interior_reached: Array[Vector2i] = []
    for y: int in range(castle_rect.position.y, castle_rect.end.y):
        for x: int in range(castle_rect.position.x, castle_rect.end.x):
            var cell: Vector2i = Vector2i(x, y)
            if seen[index(cell)] == 0:
                continue
            if on_castle_perimeter(cell):
                leaks.append(cell)
            else:
                interior_reached.append(cell)
    return leaks if not leaks.is_empty() else interior_reached


## Gate cells that are not on the castle wall ring (corners excluded: a corner
## opening does not lead into the interior).
func misplaced_gates() -> Array[Vector2i]:
    var bad: Array[Vector2i] = []
    for gate: Vector2i in gates:
        var corner: bool = (gate.x == castle_rect.position.x or gate.x == castle_rect.end.x - 1) \
            and (gate.y == castle_rect.position.y or gate.y == castle_rect.end.y - 1)
        if not on_castle_perimeter(gate) or corner:
            bad.append(gate)
    return bad


## Whether the objective can be reached from the field entries, with the gates
## open or closed. Sealed castle: open -> true, closed -> false.
func goal_reachable_from_entries(gates_closed: bool) -> bool:
    if not in_bounds(goal):
        return false
    return _flood(entries, gates_closed)[index(goal)] != 0


func validate() -> Dictionary:
    var checks: Array = []
    var paths: Array = []
    _add_check(checks, stage_id.strip_edges() != "", "스테이지 ID", "저장·비교용 ID가 필요합니다.")
    var goal_code: String = goal_rejection(goal)
    _add_check(checks, goal_code == "", "최종 방어 목표",
        "목표는 성벽·성문을 제외한 성 내부의 이동 가능 셀에 있어야 합니다."
        + ("" if goal_code == "" else " 현재 %s: %s" % [str(goal), goal_rejection_message(goal_code)]))
    _add_check(checks, not in_bounds(spawn_center),
        "화면 밖 생성 중심", "몬스터 생성 중심은 화면과 맵 경계 바깥에 있어야 합니다.")
    _add_check(checks, spawn_radius_cells >= 1.0, "랜덤 생성 반경", "생성 반경은 한 칸 이상이어야 합니다.")
    _add_check(checks, gates.size() > 0, "성문", "성벽 진입 지점인 성문이 필요합니다.")
    var bad_gates: Array[Vector2i] = misplaced_gates()
    _add_check(checks, bad_gates.is_empty(), "성문 위치",
        "성문은 성벽 둘레(모서리 제외)에만 둡니다." + ("" if bad_gates.is_empty() else " 벗어난 성문: %s" % str(bad_gates)))
    _add_check(checks, _entries_are_valid(), "외곽 진입점",
        "화면 밖 몬스터가 필드로 들어올 수 있도록 맵 가장자리에 진입점을 둡니다.")
    _add_check(checks, _castle_perimeter_is_closed(), "성벽 폐쇄", "성문을 제외한 성벽 둘레가 막혀 있어야 합니다.")
    var leaks: Array[Vector2i] = wall_leak_cells()
    var closed_reach: bool = goal_reachable_from_entries(true)
    _add_check(checks, leaks.is_empty() and not closed_reach, "성문 외 진입 차단",
        "성문을 닫으면 외부에서 성 안 목표에 닿을 수 없어야 합니다."
        + ("" if leaks.is_empty() else " 구멍: %s" % str(leaks.slice(0, 8)))
        + (" 성문 폐쇄 상태에서 목표 도달 가능." if closed_reach else ""))
    _add_check(checks, float(tuning.get("wave_count", 0)) > 0.0 and float(tuning.get("spawn_rate", 0.0)) > 0.0,
        "웨이브 설정", "웨이브 수와 초당 생성 수는 0보다 커야 합니다.")

    var candidates: Dictionary = spawn_candidate_report()
    var candidates_ok: bool = int(candidates["total"]) > 0 and int(candidates["valid"]) == int(candidates["total"])
    _add_check(checks, candidates_ok, "생성 후보 전수",
        "생성 반경 안 모든 정수 셀이 화면 밖이고 성문 경유로 목표에 닿아야 합니다. 유효 %d/%d%s" % [
            int(candidates["valid"]), int(candidates["total"]),
            "" if candidates_ok else " · 화면 안 %d · 화면 안 벽 %d · 도달 불가 %d" % [
                int(candidates["rejected_counts"][SPAWN_ON_SCREEN]),
                int(candidates["rejected_counts"][SPAWN_ON_SCREEN_WALL]),
                int(candidates["rejected_counts"][SPAWN_UNREACHABLE])]])

    var samples: Array[Vector2i] = generated_spawn_points()
    var candidate_cells: Array[Vector2i] = spawn_candidate_cells()
    var samples_in_model: bool = true
    for spawn: Vector2i in samples:
        if not candidate_cells.has(spawn):
            samples_in_model = false
    var enough_samples: bool = samples.size() == spawn_sample_count
    _add_check(checks, enough_samples and samples_in_model, "랜덤 분산 표본",
        "미리보기용 표본 %d개(전수 검사와 별개)를 반경 안 후보 셀에서 확보해야 합니다." % spawn_sample_count)
    var outside: bool = not in_bounds(spawn_center)
    var routes_ok: bool = enough_samples
    var problems: Array = []
    for spawn: Vector2i in samples:
        if in_bounds(spawn):
            outside = false
        var route: Array[Vector2i] = offscreen_route(spawn)
        paths.append(route)
        var problem: String = route_order_problem(route)
        problems.append(problem)
        if problem != "":
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
    return {"ok": errors.is_empty(), "checks": checks, "errors": errors, "paths": paths,
        "route_problems": problems, "spawn_candidates": candidates}


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


## Cells of one kind in row-major order (the canonical order used on disk).
func cells_of(value: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for i: int in range(cells.size()):
        if int(cells[i]) == value:
            out.append(Vector2i(i % width, i / width))
    return out


func to_dictionary() -> Dictionary:
    var cell_values: Array[int] = []
    for value: int in cells:
        cell_values.append(value)
    var gate_values: Array = []
    for gate: Vector2i in cells_of(Cell.GATE):
        gate_values.append([gate.x, gate.y])
    var entry_values: Array = []
    for entry: Vector2i in cells_of(Cell.ENTRY):
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
        "spawn_seed": spawn_seed,
        "gates": gate_values,
        "entries": entry_values,
        "goal": [goal.x, goal.y],
        "castle_rect": [castle_rect.position.x, castle_rect.position.y, castle_rect.size.x, castle_rect.size.y],
        "tuning": _typed_tuning(tuning, _no_errors),
    }


# ------------------------------------------------------------- loading ---
# Load policy (AC-M05). JSON has a single number type and Godot parses every
# number as float, so each integer field (format_version, width, height, cells,
# coordinates, spawn_sample_count, spawn_seed, castle_rect, tuning.wave_count)
# must hold a whole number and is converted back to int; a fractional value is
# an error, never truncated. Float fields (spawn_radius_cells, tuning.spawn_rate,
# tuning.test_duration) accept any number. A broken file yields errors and no
# map: the loader never substitutes defaults for missing cells. Gate and entry
# lists are derived from the cells; stored lists must agree with them.

## Scratch sink for _typed_tuning() when saving (in-memory values are already typed).
var _no_errors: Array[String] = []


static func _whole(value: Variant, field: String, errors: Array[String]) -> int:
    if value is int:
        return value
    if value is float and is_finite(value) and value == floorf(value):
        return int(value)
    errors.append("%s: 정수가 아닙니다 (%s)" % [field, str(value)])
    return 0


static func _number(value: Variant, field: String, errors: Array[String]) -> float:
    if (value is int or value is float) and is_finite(float(value)):
        return float(value)
    errors.append("%s: 숫자가 아닙니다 (%s)" % [field, str(value)])
    return 0.0


static func _cell_pair(value: Variant, field: String, errors: Array[String]) -> Vector2i:
    if not (value is Array) or (value as Array).size() != 2:
        errors.append("%s: [x, y] 형식이 아닙니다 (%s)" % [field, str(value)])
        return Vector2i(-1, -1)
    return Vector2i(_whole(value[0], field + "[0]", errors), _whole(value[1], field + "[1]", errors))


static func _typed_tuning(raw: Dictionary, errors: Array[String]) -> Dictionary:
    var out: Dictionary = {}
    for key: Variant in raw:
        var name: String = str(key)
        if TUNING_INT_KEYS.has(name):
            out[name] = _whole(raw[key], "tuning." + name, errors)
        elif TUNING_FLOAT_KEYS.has(name):
            out[name] = _number(raw[key], "tuning." + name, errors)
        else:
            out[name] = raw[key]
    return out


static func _pair_set(cells_list: Array[Vector2i]) -> Dictionary:
    var out: Dictionary = {}
    for cell: Vector2i in cells_list:
        out[cell] = true
    return out


## {ok, data, errors}. `data` is null whenever `errors` is not empty.
static func parse_dictionary(raw: Dictionary) -> Dictionary:
    var errors: Array[String] = []
    var version: int = _whole(raw.get("format_version", 1), "format_version", errors)
    if version > FORMAT_VERSION:
        errors.append("format_version: 이 빌드(%d)보다 새 형식입니다 (%d)" % [FORMAT_VERSION, version])
    for required: String in ["width", "height", "cells"]:
        if not raw.has(required):
            errors.append("%s: 필수 항목이 없습니다" % required)
    if not errors.is_empty():
        return {"ok": false, "data": null, "errors": errors}
    var w: int = _whole(raw["width"], "width", errors)
    var h: int = _whole(raw["height"], "height", errors)
    if w < 3 or h < 3:
        errors.append("width/height: 3 이상이어야 합니다 (%d x %d)" % [w, h])
        return {"ok": false, "data": null, "errors": errors}
    var data = new(w, h)
    data.stage_id = str(raw.get("stage_id", "stage_custom"))
    data.stage_name = str(raw.get("stage_name", "사용자 스테이지"))
    var type_name: String = str(raw.get("map_type", "flat"))
    if type_name != "flat" and type_name != "terrain":
        errors.append("map_type: flat 또는 terrain 이어야 합니다 (%s)" % type_name)
    data.map_type = MapType.TERRAIN if type_name == "terrain" else MapType.FLAT

    var raw_cells: Variant = raw["cells"]
    if not (raw_cells is Array) or (raw_cells as Array).size() != w * h:
        errors.append("cells: 길이가 width*height(%d)와 다릅니다 (%s)" % [
            w * h, str((raw_cells as Array).size()) if raw_cells is Array else type_string(typeof(raw_cells))])
    else:
        var bad_cells: int = 0
        for i: int in range((raw_cells as Array).size()):
            var cell_errors: Array[String] = []
            var value: int = _whole(raw_cells[i], "cells[%d]" % i, cell_errors)
            if cell_errors.is_empty() and (value < Cell.OPEN or value > Cell.ENTRY):
                cell_errors.append("cells[%d]: 알 수 없는 셀 값 %d" % [i, value])
            if not cell_errors.is_empty():
                bad_cells += 1
                if bad_cells <= 5:
                    errors.append_array(cell_errors)
                continue
            data.cells[i] = value
        if bad_cells > 5:
            errors.append("cells: 잘못된 셀 %d개 (앞 5개만 표시)" % bad_cells)

    if raw.has("spawn_center"):
        data.spawn_center = _cell_pair(raw["spawn_center"], "spawn_center", errors)
    else:
        # v1 migration: use the first former fixed spawn as the new centre.
        var legacy_spawns: Variant = raw.get("spawns", [])
        if legacy_spawns is Array and not (legacy_spawns as Array).is_empty():
            data.spawn_center = _cell_pair(legacy_spawns[0], "spawns[0]", errors)
    data.spawn_radius_cells = _number(raw.get("spawn_radius_cells", 4.0), "spawn_radius_cells", errors)
    data.spawn_sample_count = _whole(raw.get("spawn_sample_count", 12), "spawn_sample_count", errors)
    data.spawn_seed = _whole(raw.get("spawn_seed", -1), "spawn_seed", errors)
    data.goal = _cell_pair(raw.get("goal", [-1, -1]), "goal", errors)
    var raw_castle: Variant = raw.get("castle_rect", [0, 0, 0, 0])
    if not (raw_castle is Array) or (raw_castle as Array).size() != 4:
        errors.append("castle_rect: [x, y, w, h] 형식이 아닙니다 (%s)" % str(raw_castle))
    else:
        data.castle_rect = Rect2i(
            _whole(raw_castle[0], "castle_rect[0]", errors), _whole(raw_castle[1], "castle_rect[1]", errors),
            _whole(raw_castle[2], "castle_rect[2]", errors), _whole(raw_castle[3], "castle_rect[3]", errors))
    var raw_tuning: Variant = raw.get("tuning", {})
    if raw_tuning is Dictionary:
        data.tuning = _typed_tuning(raw_tuning, errors)
    else:
        errors.append("tuning: 객체가 아닙니다 (%s)" % str(raw_tuning))

    data.gates.assign(data.cells_of(Cell.GATE))
    data.entries.assign(data.cells_of(Cell.ENTRY))
    for pair: Array in [["gates", data.gates], ["entries", data.entries]]:
        if not raw.has(pair[0]):
            continue
        var listed: Array[Vector2i] = []
        var raw_list: Variant = raw[pair[0]]
        if raw_list is Array:
            for item: Variant in raw_list:
                listed.append(_cell_pair(item, pair[0], errors))
        if _pair_set(listed) != _pair_set(pair[1]) or listed.size() != (pair[1] as Array).size():
            errors.append("%s: 목록이 cells의 셀과 다릅니다 (목록 %d · cells %d)" % [
                pair[0], listed.size(), (pair[1] as Array).size()])

    if not errors.is_empty():
        return {"ok": false, "data": null, "errors": errors}
    return {"ok": true, "data": data, "errors": errors}


## The map, or null when the dictionary breaks the load policy above.
static func from_dictionary(raw: Dictionary) -> RefCounted:
    return parse_dictionary(raw)["data"]


func to_json_text() -> String:
    return JSON.stringify(to_dictionary(), "  ", true, true) + "\n"


func save_json(path: String) -> bool:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(to_json_text())
    file.close()
    return true


## {ok, data, errors} for a file on disk.
static func load_json_result(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"ok": false, "data": null, "errors": ["파일이 없습니다: %s" % path]}
    var json: JSON = JSON.new()
    if json.parse(FileAccess.get_file_as_string(path)) != OK:
        return {"ok": false, "data": null, "errors": [
            "JSON 오류 %d행: %s" % [json.get_error_line(), json.get_error_message()]]}
    if not (json.data is Dictionary):
        return {"ok": false, "data": null, "errors": ["최상위 값이 객체가 아닙니다"]}
    return parse_dictionary(json.data)


static func load_json(path: String) -> RefCounted:
    return load_json_result(path)["data"]
