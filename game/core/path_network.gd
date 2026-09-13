extends RefCounted
## Route graph over the grid: distance field + flow field toward the shared goal.
##
## The field is rebuilt only when passability changes. `path_version` is the
## observable handle WP-001 uses to prove that a placement did (or did not)
## change traffic, so it MUST NOT move when a placement is rejected.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")

const COST_ORTHO: int = 10
const COST_DIAG: int = 14
const UNREACHABLE: int = 0x3FFFFFFF

## Neighbour order is fixed so Dijkstra tie-breaking stays deterministic.
const NEIGHBOURS: Array[Vector2i] = [
    Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
    Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var grid: TerrainGrid = null
var goal_cell: Vector2i = Vector2i.ZERO
var goal_index: int = -1

## One entry per route. Every spawn cell of a route shares its connectivity.
var route_ids: PackedStringArray = PackedStringArray()
var route_spawn_cells: Array[PackedInt32Array] = []

var dist: PackedInt32Array = PackedInt32Array()
var flow: PackedInt32Array = PackedInt32Array()
var path_version: int = 0

var _heap: PackedInt64Array = PackedInt64Array()
var _scratch_seen: PackedByteArray = PackedByteArray()
var _scratch_queue: PackedInt32Array = PackedInt32Array()


func _init(g: TerrainGrid) -> void:
    grid = g
    var n: int = g.width * g.height
    dist.resize(n)
    flow.resize(n)
    _scratch_seen.resize(n)
    _scratch_queue.resize(n)


func add_route(id: String, spawn_cells: PackedInt32Array) -> int:
    route_ids.append(id)
    route_spawn_cells.append(spawn_cells)
    return route_ids.size() - 1


func set_goal(cx: int, cy: int) -> void:
    goal_cell = Vector2i(cx, cy)
    goal_index = grid.idx(cx, cy)


# ---------------------------------------------------------------- Dijkstra ---

func _heap_push(key: int) -> void:
    _heap.append(key)
    var i: int = _heap.size() - 1
    while i > 0:
        var p: int = (i - 1) >> 1
        if _heap[p] <= _heap[i]:
            break
        var t: int = _heap[p]
        _heap[p] = _heap[i]
        _heap[i] = t
        i = p


func _heap_pop() -> int:
    var top: int = _heap[0]
    var n: int = _heap.size() - 1
    var last: int = _heap[n]
    _heap.resize(n)
    if n > 0:
        _heap[0] = last
        var i: int = 0
        while true:
            var l: int = i * 2 + 1
            var r: int = l + 1
            var s: int = i
            if l < n and _heap[l] < _heap[s]:
                s = l
            if r < n and _heap[r] < _heap[s]:
                s = r
            if s == i:
                break
            var t: int = _heap[s]
            _heap[s] = _heap[i]
            _heap[i] = t
            i = s
    return top


## Rebuild the distance/flow field and bump `path_version`.
func rebuild() -> void:
    _compute_field()
    path_version += 1


func _compute_field() -> void:
    dist.fill(UNREACHABLE)
    flow.fill(-1)
    _heap.clear()
    if goal_index < 0 or not grid.is_passable_i(goal_index):
        return
    var w: int = grid.width
    var h: int = grid.height
    dist[goal_index] = 0
    # key = cost << 24 | index  -> pops by (cost, index): stable across runs.
    _heap_push(goal_index)
    while _heap.size() > 0:
        var key: int = _heap_pop()
        var d: int = key >> 24
        var ci: int = key & 0xFFFFFF
        if d > dist[ci]:
            continue
        var cx: int = ci % w
        var cy: int = ci / w
        for k: int in range(8):
            var off: Vector2i = NEIGHBOURS[k]
            var nx: int = cx + off.x
            var ny: int = cy + off.y
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            var ni: int = ny * w + nx
            if not grid.is_passable_i(ni):
                continue
            var cost: int = COST_ORTHO
            if off.x != 0 and off.y != 0:
                # No corner cutting: both shared orthogonal cells must be open.
                if not grid.is_passable(cx + off.x, cy):
                    continue
                if not grid.is_passable(cx, cy + off.y):
                    continue
                cost = COST_DIAG
            var nd: int = d + cost
            if nd < dist[ni]:
                dist[ni] = nd
                flow[ni] = ci
                _heap_push((nd << 24) | ni)


# ------------------------------------------------------- Reachability probe ---

## Reachability-only flood fill. Never touches dist/flow/path_version, so a
## rejected placement leaves the observable traffic state byte-identical.
func probe_all_routes_reachable() -> bool:
    if goal_index < 0 or not grid.is_passable_i(goal_index):
        return false
    _scratch_seen.fill(0)
    var w: int = grid.width
    var h: int = grid.height
    var head: int = 0
    var tail: int = 0
    _scratch_queue[tail] = goal_index
    tail += 1
    _scratch_seen[goal_index] = 1
    while head < tail:
        var ci: int = _scratch_queue[head]
        head += 1
        var cx: int = ci % w
        var cy: int = ci / w
        for k: int in range(8):
            var off: Vector2i = NEIGHBOURS[k]
            var nx: int = cx + off.x
            var ny: int = cy + off.y
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            var ni: int = ny * w + nx
            if _scratch_seen[ni] == 1:
                continue
            if not grid.is_passable_i(ni):
                continue
            if off.x != 0 and off.y != 0:
                if not grid.is_passable(cx + off.x, cy):
                    continue
                if not grid.is_passable(cx, cy + off.y):
                    continue
            _scratch_seen[ni] = 1
            _scratch_queue[tail] = ni
            tail += 1
    for r: int in range(route_spawn_cells.size()):
        var cells: PackedInt32Array = route_spawn_cells[r]
        for c: int in cells:
            if _scratch_seen[c] != 1:
                return false
    return true


func unreachable_route_ids() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for r: int in range(route_spawn_cells.size()):
        var cells: PackedInt32Array = route_spawn_cells[r]
        var any: bool = false
        for c: int in cells:
            if dist[c] < UNREACHABLE:
                any = true
                break
        if not any:
            out.append(route_ids[r])
    return out


func route_reachable(route: int) -> bool:
    for c: int in route_spawn_cells[route]:
        if dist[c] >= UNREACHABLE:
            return false
    return true


func is_reachable_index(i: int) -> bool:
    return i >= 0 and dist[i] < UNREACHABLE


## Next cell index on the way to the goal, or -1 at the goal / unreachable.
func next_index(i: int) -> int:
    if i < 0:
        return -1
    return flow[i]


## Nearest passable, goal-connected neighbour. Used when an agent is stranded
## on a cell that became impassable while it stood on the boundary.
func best_escape_index(i: int) -> int:
    var w: int = grid.width
    var cx: int = i % w
    var cy: int = i / w
    var best: int = -1
    var best_d: int = UNREACHABLE
    for k: int in range(8):
        var off: Vector2i = NEIGHBOURS[k]
        var nx: int = cx + off.x
        var ny: int = cy + off.y
        if nx < 0 or ny < 0 or nx >= w or ny >= grid.height:
            continue
        var ni: int = ny * w + nx
        if not grid.is_passable_i(ni):
            continue
        if dist[ni] < best_d:
            best_d = dist[ni]
            best = ni
    return best
