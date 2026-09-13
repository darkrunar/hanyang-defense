extends RefCounted
## Structure placement and removal, with the WP-001 rejection rules.
##
## Rules implemented here (SYSTEM_SPEC "WP-001: 흐름과 화력"):
##  * a placement that leaves ANY route entry unable to reach the goal is refused
##  * a cell currently occupied by a living enemy cannot take a structure
##  * a refused placement leaves traffic state and structure state untouched,
##    including `path_version`
##
## Per GAME_DESIGN, 길 차단 belongs to 장승: a JANGSEUNG blocks traffic, a HWACHA
## is a firing platform the crowd flows around and never blocks a path.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")

enum Kind { JANGSEUNG, HWACHA }

enum Reject {
    NONE,
    OUT_OF_BOUNDS,
    TERRAIN_BLOCKED,
    STRUCTURE_OVERLAP,
    ENEMY_OCCUPIES_CELL,
    WOULD_BLOCK_ALL_PATHS,
    UNKNOWN_STRUCTURE,
}

const REJECT_NAMES: Array[String] = [
    "NONE",
    "OUT_OF_BOUNDS",
    "TERRAIN_BLOCKED",
    "STRUCTURE_OVERLAP",
    "ENEMY_OCCUPIES_CELL",
    "WOULD_BLOCK_ALL_PATHS",
    "UNKNOWN_STRUCTURE",
]

## Every structure is a 2x2 cell footprint (40x40 px at the default cell size).
const FOOTPRINT: int = 2


class Structure:
    extends RefCounted
    var id: int = -1
    var kind: int = 0  # Kind.JANGSEUNG
    var anchor: Vector2i = Vector2i.ZERO
    var cells: PackedInt32Array = PackedInt32Array()
    var center: Vector2 = Vector2.ZERO
    var label: String = ""
    # Hwacha runtime state (unused by jangseung).
    var fire_range: float = 0.0
    var blast_radius: float = 0.0
    var damage: float = 0.0
    var cooldown: float = 0.0
    var cooldown_left: float = 0.0
    var last_zone: int = -1
    var last_aim: Vector2 = Vector2.ZERO
    var shots_fired: int = 0
    var kills: int = 0
    var muzzle_timer: float = 0.0
    ## True only for 장승. Cached so the inner class never reaches outward.
    var blocking: bool = true


class Result:
    extends RefCounted
    var ok: bool = false
    var reason: int = 0  # Reject.NONE
    var structure: Structure = null
    var blocked_cell: int = -1


var grid: TerrainGrid = null
var path: PathNetwork = null

var structures: Dictionary = {}      # id -> Structure
var _cell_owner: Dictionary = {}     # cell index -> structure id (all kinds)
var _next_id: int = 1

var rejected_total: int = 0
var last_result: Result = null


func _init(g: TerrainGrid, p: PathNetwork) -> void:
    grid = g
    path = p


func reset() -> void:
    structures.clear()
    _cell_owner.clear()
    grid.clear_structures()
    _next_id = 1
    rejected_total = 0
    last_result = null


static func reject_name(reason: int) -> String:
    if reason < 0 or reason >= REJECT_NAMES.size():
        return "UNKNOWN"
    return REJECT_NAMES[reason]


func footprint_cells(anchor: Vector2i) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    for dy: int in range(FOOTPRINT):
        for dx: int in range(FOOTPRINT):
            var cx: int = anchor.x + dx
            var cy: int = anchor.y + dy
            if not grid.in_bounds(cx, cy):
                return PackedInt32Array()
            out.append(grid.idx(cx, cy))
    return out


func footprint_center(anchor: Vector2i) -> Vector2:
    return Vector2(
        (float(anchor.x) + float(FOOTPRINT) * 0.5) * TerrainGrid.CELL_SIZE,
        (float(anchor.y) + float(FOOTPRINT) * 0.5) * TerrainGrid.CELL_SIZE
    )


## Anchor for a 2x2 footprint centred as closely as possible on a world point.
func anchor_for_world(p: Vector2) -> Vector2i:
    return Vector2i(
        int(round(p.x / TerrainGrid.CELL_SIZE)) - 1,
        int(round(p.y / TerrainGrid.CELL_SIZE)) - 1
    )


func _fail(reason: int, blocked_cell: int = -1) -> Result:
    var r: Result = Result.new()
    r.ok = false
    r.reason = reason
    r.blocked_cell = blocked_cell
    rejected_total += 1
    last_result = r
    return r


## Validate and place. On failure nothing at all is mutated.
func try_place(kind: int, anchor: Vector2i, sim: EnemySim, label: String = "") -> Result:
    var cells: PackedInt32Array = footprint_cells(anchor)
    if cells.is_empty():
        return _fail(Reject.OUT_OF_BOUNDS)

    for ci: int in cells:
        if grid.is_wall_i(ci):
            return _fail(Reject.TERRAIN_BLOCKED, ci)
    for ci: int in cells:
        if _cell_owner.has(ci):
            return _fail(Reject.STRUCTURE_OVERLAP, ci)
    if sim != null:
        for ci: int in cells:
            if sim.is_cell_occupied(ci):
                return _fail(Reject.ENEMY_OCCUPIES_CELL, ci)

    var blocking: bool = (kind == Kind.JANGSEUNG)
    if blocking:
        # Tentatively block, probe reachability without touching dist/flow/version.
        for ci: int in cells:
            grid.set_structure_i(ci, _next_id)
        var ok: bool = path.probe_all_routes_reachable()
        if not ok:
            for ci: int in cells:
                grid.set_structure_i(ci, -1)
            return _fail(Reject.WOULD_BLOCK_ALL_PATHS)

    var s: Structure = Structure.new()
    s.id = _next_id
    _next_id += 1
    s.kind = kind
    s.blocking = blocking
    s.anchor = anchor
    s.cells = cells
    s.center = footprint_center(anchor)
    s.label = label
    structures[s.id] = s
    for ci: int in cells:
        _cell_owner[ci] = s.id

    if blocking:
        path.rebuild()

    var r: Result = Result.new()
    r.ok = true
    r.structure = s
    last_result = r
    return r


func configure_hwacha(s: Structure, fire_range: float, blast_radius: float, damage: float, cooldown: float) -> void:
    s.fire_range = fire_range
    s.blast_radius = blast_radius
    s.damage = damage
    s.cooldown = cooldown
    s.cooldown_left = 0.0


func structure_at_cell(ci: int) -> Structure:
    if not _cell_owner.has(ci):
        return null
    return structures.get(_cell_owner[ci], null)


func structure_at_world(p: Vector2) -> Structure:
    var ci: int = grid.world_to_index(p)
    if ci < 0:
        return null
    return structure_at_cell(ci)


func remove(structure_id: int) -> Result:
    if not structures.has(structure_id):
        return _fail(Reject.UNKNOWN_STRUCTURE)
    var s: Structure = structures[structure_id]
    for ci: int in s.cells:
        _cell_owner.erase(ci)
        if s.blocking:
            grid.set_structure_i(ci, -1)
    structures.erase(structure_id)
    if s.blocking:
        path.rebuild()
    var r: Result = Result.new()
    r.ok = true
    r.structure = s
    last_result = r
    return r


func hwachas() -> Array:
    var out: Array = []
    for id: int in structures:
        var s: Structure = structures[id]
        if s.kind == Kind.HWACHA:
            out.append(s)
    out.sort_custom(func(a: Structure, b: Structure) -> bool: return a.id < b.id)
    return out


func jangseungs() -> Array:
    var out: Array = []
    for id: int in structures:
        var s: Structure = structures[id]
        if s.kind == Kind.JANGSEUNG:
            out.append(s)
    out.sort_custom(func(a: Structure, b: Structure) -> bool: return a.id < b.id)
    return out


func count_of(kind: int) -> int:
    var n: int = 0
    for id: int in structures:
        if (structures[id] as Structure).kind == kind:
            n += 1
    return n
