extends RefCounted
## Structure-of-arrays enemy pool: spawning, flow-field movement, damage, death.
##
## Counters deliberately separate cumulative spawns from the concurrent alive
## count (WP-001 verification rule). `alive_count` is what AC-01 is about.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")

var capacity: int = 0

var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_y: PackedFloat32Array = PackedFloat32Array()
var off_x: PackedFloat32Array = PackedFloat32Array()
var off_y: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var route: PackedInt32Array = PackedInt32Array()
var cell: PackedInt32Array = PackedInt32Array()
var alive: PackedByteArray = PackedByteArray()

var _free: PackedInt32Array = PackedInt32Array()
var _live: PackedInt32Array = PackedInt32Array()

var alive_count: int = 0
var spawned_total: int = 0
var killed_total: int = 0
var leaked_total: int = 0
var route_alive: PackedInt32Array = PackedInt32Array()
var route_spawned: PackedInt32Array = PackedInt32Array()
var route_leaked: PackedInt32Array = PackedInt32Array()

var _grid: TerrainGrid = null
var _path: PathNetwork = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- tuning, injected from config ---
var base_speed: float = 58.0
var speed_jitter: float = 0.22
var lane_offset: float = 7.0
var max_hp: float = 60.0
var goal_radius: float = 26.0

var _spawn_cursor: int = 0
var _spawn_accum: float = 0.0


func _init(g: TerrainGrid, p: PathNetwork, cap: int) -> void:
    _grid = g
    _path = p
    capacity = cap
    pos_x.resize(cap)
    pos_y.resize(cap)
    off_x.resize(cap)
    off_y.resize(cap)
    speed.resize(cap)
    hp.resize(cap)
    route.resize(cap)
    cell.resize(cap)
    alive.resize(cap)
    route_alive.resize(p.route_ids.size())
    route_spawned.resize(p.route_ids.size())
    route_leaked.resize(p.route_ids.size())
    reset(0)


func reset(seed_value: int) -> void:
    _rng = RandomNumberGenerator.new()
    _rng.seed = seed_value
    alive.fill(0)
    _live.clear()
    _free.resize(capacity)
    for i: int in range(capacity):
        _free[i] = capacity - 1 - i
    alive_count = 0
    spawned_total = 0
    killed_total = 0
    leaked_total = 0
    route_alive.fill(0)
    route_spawned.fill(0)
    route_leaked.fill(0)
    _spawn_cursor = 0
    _spawn_accum = 0.0


# ----------------------------------------------------------------- spawning ---

## Spawn one enemy on `route_index` at `spawn_cell`. Returns the slot or -1.
func spawn_at(route_index: int, spawn_cell: int) -> int:
    if _free.is_empty():
        return -1
    var s: int = _free[_free.size() - 1]
    _free.resize(_free.size() - 1)
    var c: Vector2 = _grid.index_center(spawn_cell)
    var ox: float = _rng.randf_range(-lane_offset, lane_offset)
    var oy: float = _rng.randf_range(-lane_offset, lane_offset)
    pos_x[s] = c.x + ox
    pos_y[s] = c.y + oy
    off_x[s] = ox
    off_y[s] = oy
    speed[s] = base_speed * (1.0 + _rng.randf_range(-speed_jitter, speed_jitter))
    hp[s] = max_hp
    route[s] = route_index
    cell[s] = spawn_cell
    alive[s] = 1
    _live.append(s)
    alive_count += 1
    spawned_total += 1
    route_alive[route_index] += 1
    route_spawned[route_index] += 1
    return s


## Round-robin across routes and across each route's spawn cells, so all three
## entries are provably used and the lane split inside a route is position-driven.
func spawn_round_robin(count: int) -> int:
    var routes: int = _path.route_ids.size()
    var made: int = 0
    for _n: int in range(count):
        var attempts: int = 0
        var placed: bool = false
        while attempts < routes:
            var r: int = _spawn_cursor % routes
            var cells: PackedInt32Array = _path.route_spawn_cells[r]
            var ci: int = cells[int(_spawn_cursor / routes) % cells.size()]
            _spawn_cursor += 1
            attempts += 1
            if not _path.is_reachable_index(ci):
                continue
            if spawn_at(r, ci) >= 0:
                made += 1
                placed = true
            break
        if not placed and attempts >= routes:
            break
    return made


## Keep `target_alive` enemies on the field, adding at most `rate` per second.
func maintain(target_alive: int, rate: float, dt: float) -> int:
    if alive_count >= target_alive:
        _spawn_accum = 0.0
        return 0
    _spawn_accum += rate * dt
    var budget: int = int(_spawn_accum)
    if budget <= 0:
        return 0
    _spawn_accum -= float(budget)
    return spawn_round_robin(mini(budget, target_alive - alive_count))


# ----------------------------------------------------------------- movement ---

func step_movement(dt: float) -> void:
    var w: int = _grid.width
    var h: int = _grid.height
    var cs: float = TerrainGrid.CELL_SIZE
    var goal_c: Vector2 = _grid.index_center(_path.goal_index)
    var gr2: float = goal_radius * goal_radius
    var flow_field: PackedInt32Array = _path.flow
    var i: int = 0
    while i < _live.size():
        var s: int = _live[i]
        var px: float = pos_x[s]
        var py: float = pos_y[s]

        var cx: int = int(px / cs)
        var cy: int = int(py / cs)
        if cx < 0:
            cx = 0
        elif cx >= w:
            cx = w - 1
        if cy < 0:
            cy = 0
        elif cy >= h:
            cy = h - 1
        var ci: int = cy * w + cx
        cell[s] = ci

        var dxg: float = goal_c.x - px
        var dyg: float = goal_c.y - py
        if dxg * dxg + dyg * dyg <= gr2:
            _despawn_at(i, true)
            continue

        var ni: int = flow_field[ci]
        if ni < 0:
            # Stranded (cell became impassable underfoot): steer to the best
            # goal-connected neighbour instead of freezing in place.
            ni = _path.best_escape_index(ci)
            if ni < 0:
                i += 1
                continue
        var tx: float = (float(ni % w) + 0.5) * cs + off_x[s]
        var ty: float = (float(int(ni / w)) + 0.5) * cs + off_y[s]
        var dx: float = tx - px
        var dy: float = ty - py
        var len_sq: float = dx * dx + dy * dy
        if len_sq > 1e-6:
            var inv: float = 1.0 / sqrt(len_sq)
            var step: float = speed[s] * dt
            pos_x[s] = px + dx * inv * step
            pos_y[s] = py + dy * inv * step
        i += 1


func _despawn_at(live_index: int, leaked: bool) -> void:
    var s: int = _live[live_index]
    alive[s] = 0
    var r: int = route[s]
    route_alive[r] -= 1
    alive_count -= 1
    if leaked:
        leaked_total += 1
        route_leaked[r] += 1
    else:
        killed_total += 1
    _free.append(s)
    var last: int = _live.size() - 1
    _live[live_index] = _live[last]
    _live.resize(last)


# ------------------------------------------------------------------- damage ---

## Apply `damage` once to every alive enemy inside the blast. Returns kills.
## A dead enemy leaves the live list immediately, so it can never be damaged
## twice by the same volley nor counted twice as a kill.
func apply_blast(center: Vector2, radius: float, damage: float) -> int:
    var r2: float = radius * radius
    var kills: int = 0
    var i: int = 0
    while i < _live.size():
        var s: int = _live[i]
        var dx: float = pos_x[s] - center.x
        var dy: float = pos_y[s] - center.y
        if dx * dx + dy * dy <= r2:
            hp[s] -= damage
            if hp[s] <= 0.0:
                _despawn_at(i, false)
                kills += 1
                continue
        i += 1
    return kills


func live_slots() -> PackedInt32Array:
    return _live


func is_cell_occupied(ci: int) -> bool:
    for s: int in _live:
        if cell[s] == ci:
            return true
    return false


## Recompute the cached cell index of every living enemy.
func refresh_cells() -> void:
    var w: int = _grid.width
    var cs: float = TerrainGrid.CELL_SIZE
    for s: int in _live:
        var cx: int = clampi(int(pos_x[s] / cs), 0, w - 1)
        var cy: int = clampi(int(pos_y[s] / cs), 0, _grid.height - 1)
        cell[s] = cy * w + cx


## Test hook: place one enemy at an exact world position.
func force_spawn(route_index: int, world_pos: Vector2, hp_value: float = -1.0) -> int:
    var ci: int = _grid.world_to_index(world_pos)
    if ci < 0:
        return -1
    var s: int = spawn_at(route_index, ci)
    if s < 0:
        return -1
    pos_x[s] = world_pos.x
    pos_y[s] = world_pos.y
    off_x[s] = 0.0
    off_y[s] = 0.0
    if hp_value > 0.0:
        hp[s] = hp_value
    return s
