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
## Generation counter per slot: bumped on every spawn, so (slot, gen) names one
## individual and a reused slot can never be mistaken for its predecessor
## (WP-002 shared-target identity rule).
var gen: PackedInt32Array = PackedInt32Array()

var _free: PackedInt32Array = PackedInt32Array()
var _live: PackedInt32Array = PackedInt32Array()

var alive_count: int = 0
var spawned_total: int = 0
var killed_total: int = 0
var leaked_total: int = 0
## Number of individual damage applications (one per enemy per volley).
var damage_applications: int = 0
## WP-005 render ledger (D-049): [x, y, kind] triples for every despawn / hit
## since the renderer last took them. kind 0 = killed, 1 = leaked (arrived),
## 2 = damaged but alive. Pure output (nothing in the simulation reads it),
## capped so headless runs never grow it.
var render_events: PackedFloat32Array = PackedFloat32Array()
const RENDER_EVENTS_CAP: int = 768   # 256 events
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
## "immediate": an enemy inside the goal radius is consumed during movement
## (WP-001/002 behaviour, unchanged). "after_fire": it stops and waits; the
## battle consumes the survivors with collect_arrivals() after the hwachas fired
## (WP-003 D-023).
var arrival_mode: String = "immediate"
var _route_cursor: PackedInt32Array = PackedInt32Array()

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
    gen.resize(cap)
    route_alive.resize(p.route_ids.size())
    route_spawned.resize(p.route_ids.size())
    route_leaked.resize(p.route_ids.size())
    _route_cursor.resize(p.route_ids.size())
    reset(0)


func reset(seed_value: int) -> void:
    _rng = RandomNumberGenerator.new()
    _rng.seed = seed_value
    alive.fill(0)
    gen.fill(0)
    _live.clear()
    _free.resize(capacity)
    for i: int in range(capacity):
        _free[i] = capacity - 1 - i
    alive_count = 0
    spawned_total = 0
    killed_total = 0
    leaked_total = 0
    damage_applications = 0
    route_alive.fill(0)
    route_spawned.fill(0)
    route_leaked.fill(0)
    _spawn_cursor = 0
    _spawn_accum = 0.0
    _route_cursor.fill(0)
    render_events = PackedFloat32Array()


## Current RNG state (for state-equality checks between two deterministic runs).
func rng_state() -> int:
    return _rng.state


# ----------------------------------------------------------------- spawning ---

## Spawn `count` enemies on ONE route, cycling that route's spawn cells in
## their stable order (WP-003 waves: order south -> west -> east per tick is
## the caller's responsibility). Returns how many were spawned.
func spawn_on_route(route_index: int, count: int) -> int:
    var cells: PackedInt32Array = _path.route_spawn_cells[route_index]
    var made: int = 0
    for _n: int in range(count):
        var ci: int = cells[_route_cursor[route_index] % cells.size()]
        _route_cursor[route_index] += 1
        if not _path.is_reachable_index(ci):
            continue
        if spawn_at(route_index, ci) < 0:
            break
        made += 1
    return made

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
    gen[s] += 1
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
            if arrival_mode == "immediate":
                _despawn_at(i, true)
                continue
            # after_fire: stay on the doorstep; the battle consumes survivors later.
            i += 1
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
            var nx: float = px + dx * inv * step
            var ny: float = py + dy * inv * step
            pos_x[s] = nx
            pos_y[s] = ny
            # Keep the cached cell in sync with the position the enemy ENDS the
            # tick on, so occupancy checks issued after this step see the truth
            # (GPT review R-01: the pre-move cache let a jangseung land on an
            # enemy that had just stepped into the footprint).
            var ncx: int = int(nx / cs)
            var ncy: int = int(ny / cs)
            if ncx < 0:
                ncx = 0
            elif ncx >= w:
                ncx = w - 1
            if ncy < 0:
                ncy = 0
            elif ncy >= h:
                ncy = h - 1
            cell[s] = ncy * w + ncx
        i += 1


## WP-003 D-023: consume every LIVING enemy inside the goal radius, once each,
## and return their individual ids. Called after the hwachas fired, so an enemy
## killed on the doorstep this tick is not here. Arrivals count as leaks
## (`leaked_total`), never as kills.
func collect_arrivals() -> PackedInt64Array:
    var out: PackedInt64Array = PackedInt64Array()
    var goal_c: Vector2 = _grid.index_center(_path.goal_index)
    var gr2: float = goal_radius * goal_radius
    var i: int = 0
    while i < _live.size():
        var s: int = _live[i]
        var dx: float = pos_x[s] - goal_c.x
        var dy: float = pos_y[s] - goal_c.y
        if dx * dx + dy * dy <= gr2:
            out.append(enemy_id(s))
            _despawn_at(i, true)
            continue
        i += 1
    return out


func _despawn_at(live_index: int, leaked: bool) -> void:
    var s: int = _live[live_index]
    alive[s] = 0
    _render_event(pos_x[s], pos_y[s], 1.0 if leaked else 0.0)
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
            damage_applications += 1
            if hp[s] <= 0.0:
                _despawn_at(i, false)
                kills += 1
                continue
            _render_event(pos_x[s], pos_y[s], 2.0)
        i += 1
    return kills


func _render_event(x: float, y: float, kind: float) -> void:
    if render_events.size() < RENDER_EVENTS_CAP:
        render_events.append(x)
        render_events.append(y)
        render_events.append(kind)


## The renderer takes the ledger (and empties it) once per drawn frame.
func take_render_events() -> PackedFloat32Array:
    var out: PackedFloat32Array = render_events
    render_events = PackedFloat32Array()
    return out


func live_slots() -> PackedInt32Array:
    return _live


## Stable individual id for a living slot: generation in the high bits.
func enemy_id(s: int) -> int:
    return (gen[s] << 16) | s


## True when `enemy_id` still names a living individual (same slot AND same generation).
func is_id_alive(id: int) -> bool:
    var s: int = id & 0xFFFF
    return s < capacity and alive[s] == 1 and gen[s] == (id >> 16)


## True when any LIVING enemy's current position lies inside cell `ci`.
## Deliberately derived from pos_x/pos_y rather than the cached `cell` array,
## so the answer can never lag behind movement (GPT review R-01). Uses the
## same floor-to-cell rule as `step_movement` / `world_to_index`.
func is_cell_occupied(ci: int) -> bool:
    var w: int = _grid.width
    var cs: float = TerrainGrid.CELL_SIZE
    var x0: float = float(ci % w) * cs
    var y0: float = float(int(ci / w)) * cs
    var x1: float = x0 + cs
    var y1: float = y0 + cs
    for s: int in _live:
        var px: float = pos_x[s]
        var py: float = pos_y[s]
        if px >= x0 and px < x1 and py >= y0 and py < y1:
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
