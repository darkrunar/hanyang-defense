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

## JANGSEUNG blocks traffic. HWACHA fires. BONGSU relays (WP-002 D-012).
## SENSOR (혼천의) detects and shares enemy ids through its bongsu group.
## Only JANGSEUNG blocks paths (D-011 / D-014).
enum Kind { JANGSEUNG, HWACHA, BONGSU, SENSOR }

const KIND_NAMES: Array[String] = ["JANGSEUNG", "HWACHA", "BONGSU", "SENSOR"]
const KIND_LABELS: Array[String] = ["장승", "화차", "봉수대", "혼천의"]

enum Reject {
    NONE,
    OUT_OF_BOUNDS,
    TERRAIN_BLOCKED,
    STRUCTURE_OVERLAP,
    ENEMY_OCCUPIES_CELL,
    WOULD_BLOCK_ALL_PATHS,
    UNKNOWN_STRUCTURE,
    # --- WP-003 (D-022 / D-023 / D-024) ---
    DISTRICT_SPLIT,        # footprint straddles two districts
    DISTRICT_LOST,         # district is lost (outer after collapse)
    WRONG_DISTRICT,        # recovery placement outside the allowed district
    RUN_ENDED,             # run is WON / LOST
    NO_RECOVERY_RIGHT,     # no recovery right left (already placed / no collapse)
    NOT_DETACHED,          # restore() on a structure that is not detached
    # --- WP-008 paid construction (D-054) ---
    BUILD_DISABLED,        # not a build-mode run (classic: recovery placement only)
    CAP_REACHED,           # structure total (initial + bought + inactive + waiting) at the cap
    INSUFFICIENT_SUPPLY,   # supply < cost
}

const REJECT_NAMES: Array[String] = [
    "NONE",
    "OUT_OF_BOUNDS",
    "TERRAIN_BLOCKED",
    "STRUCTURE_OVERLAP",
    "ENEMY_OCCUPIES_CELL",
    "WOULD_BLOCK_ALL_PATHS",
    "UNKNOWN_STRUCTURE",
    "DISTRICT_SPLIT",
    "DISTRICT_LOST",
    "WRONG_DISTRICT",
    "RUN_ENDED",
    "NO_RECOVERY_RIGHT",
    "NOT_DETACHED",
    "BUILD_DISABLED",
    "CAP_REACHED",
    "INSUFFICIENT_SUPPLY",
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
    # --- WP-002 network state ---
    ## Inactive structures keep their footprint but stop detecting / relaying / firing.
    var active: bool = true
    ## Detection radius: sensor range for SENSOR, local range for HWACHA.
    var detect_range: float = 0.0
    ## Bongsu this terminal (sensor / hwacha) is attached to, or -1.
    var attached_to: int = -1
    ## Connected-component id (min bongsu id of the component), or -1.
    var group_id: int = -1
    ## Last targeting diagnostics for the overlay (WP-002 mode).
    var known_local: int = 0
    var known_shared: int = 0
    var last_target_local: int = 0
    var last_target_shared: int = 0
    var wait_reason: String = ""
    # --- WP-003 ---
    ## District the footprint lies in (TestMap.DISTRICT_*), -1 when unknown.
    var district: int = -1
    ## Detached = recovered and waiting: no footprint, no detection, no fire,
    ## cooldown frozen (the structure is not in `structures` while detached).
    var detached: bool = false


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
## Detached (recovered, waiting) structures: id -> Structure. Not in `structures`.
var detached: Dictionary = {}
## WP-003 district rules. `district_fn(cx, cy) -> int`; invalid = no rule.
var district_fn: Callable = Callable()
## District where every new placement / restore is refused (outer after collapse).
var locked_district: int = -1

var rejected_total: int = 0
var last_result: Result = null


func _init(g: TerrainGrid, p: PathNetwork) -> void:
    grid = g
    path = p


func reset() -> void:
    structures.clear()
    _cell_owner.clear()
    detached.clear()
    grid.clear_structures()
    _next_id = 1
    rejected_total = 0
    last_result = null
    locked_district = -1


## District of a footprint, or -1 when the rule is off / the footprint straddles.
func footprint_district(cells: PackedInt32Array) -> int:
    if not district_fn.is_valid():
        return -1
    var d: int = -2
    for ci: int in cells:
        var cd: int = district_fn.call(ci % grid.width, int(ci / grid.width))
        if d == -2:
            d = cd
        elif cd != d:
            return -1
    return d


static func reject_name(reason: int) -> String:
    if reason < 0 or reason >= REJECT_NAMES.size():
        return "UNKNOWN"
    return REJECT_NAMES[reason]


## Player-facing refusal text (HUD notice, cursor ghost, WP-008 build preview).
static func reject_ko(reason: int) -> String:
    match reason:
        Reject.NONE: return "배치 가능"
        Reject.NO_RECOVERY_RIGHT: return "회수권 없음 (붕괴 전이거나 이미 배치함)"
        Reject.RUN_ENDED: return "런 종료 — R로 재시작"
        Reject.DISTRICT_LOST: return "붕괴한 외곽에는 설치 불가"
        Reject.WRONG_DISTRICT: return "내곽(경복궁·광화문·광장 북단)에만 배치 가능"
        Reject.DISTRICT_SPLIT: return "구역 경계에 걸침"
        Reject.ENEMY_OCCUPIES_CELL: return "적이 점유 중"
        Reject.STRUCTURE_OVERLAP: return "다른 시설과 겹침"
        Reject.TERRAIN_BLOCKED: return "벽·지형"
        Reject.OUT_OF_BOUNDS: return "지도 밖"
        Reject.WOULD_BLOCK_ALL_PATHS: return "모든 경로를 막음"
        Reject.BUILD_DISABLED: return "이 런에서는 건설 불가"
        Reject.CAP_REACHED: return "시설 상한 도달"
        Reject.INSUFFICIENT_SUPPLY: return "물자 부족"
        _: return reject_name(reason)


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


## Run every placement rule without mutating anything. Returns Reject.NONE
## when the placement would be accepted. The cursor ghost and `try_place`
## share this so the preview can never disagree with the command.
func validate(kind: int, anchor: Vector2i, sim: EnemySim, restrict_district: int = -1) -> int:
    var cells: PackedInt32Array = footprint_cells(anchor)
    if cells.is_empty():
        return Reject.OUT_OF_BOUNDS
    for ci: int in cells:
        if grid.is_wall_i(ci):
            return Reject.TERRAIN_BLOCKED
    for ci: int in cells:
        if _cell_owner.has(ci):
            return Reject.STRUCTURE_OVERLAP
    if sim != null:
        for ci: int in cells:
            if sim.is_cell_occupied(ci):
                return Reject.ENEMY_OCCUPIES_CELL
    if district_fn.is_valid():
        var d: int = footprint_district(cells)
        if d < 0:
            return Reject.DISTRICT_SPLIT
        if locked_district >= 0 and d == locked_district:
            return Reject.DISTRICT_LOST
        if restrict_district >= 0 and d != restrict_district:
            return Reject.WRONG_DISTRICT
    if kind == Kind.JANGSEUNG:
        # Tentatively block, probe reachability without touching dist/flow/version,
        # then restore. The probe uses scratch arrays only.
        for ci: int in cells:
            grid.set_structure_i(ci, _next_id)
        var ok: bool = path.probe_all_routes_reachable()
        for ci: int in cells:
            grid.set_structure_i(ci, -1)
        if not ok:
            return Reject.WOULD_BLOCK_ALL_PATHS
    return Reject.NONE


## Side-effect-free preview for the cursor: same rules as `try_place`, no
## rejection counter or last_result update.
func preview(kind: int, anchor: Vector2i, sim: EnemySim) -> bool:
    return validate(kind, anchor, sim) == Reject.NONE


## Validate and place. On failure nothing at all is mutated.
func try_place(kind: int, anchor: Vector2i, sim: EnemySim, label: String = "") -> Result:
    var reason: int = validate(kind, anchor, sim)
    if reason != Reject.NONE:
        var blocked: int = -1
        var cells_for_report: PackedInt32Array = footprint_cells(anchor)
        if reason == Reject.TERRAIN_BLOCKED or reason == Reject.STRUCTURE_OVERLAP \
                or reason == Reject.ENEMY_OCCUPIES_CELL:
            for ci: int in cells_for_report:
                if (reason == Reject.TERRAIN_BLOCKED and grid.is_wall_i(ci)) \
                        or (reason == Reject.STRUCTURE_OVERLAP and _cell_owner.has(ci)) \
                        or (reason == Reject.ENEMY_OCCUPIES_CELL and sim != null and sim.is_cell_occupied(ci)):
                    blocked = ci
                    break
        return _fail(reason, blocked)

    var cells: PackedInt32Array = footprint_cells(anchor)
    var blocking: bool = (kind == Kind.JANGSEUNG)
    if blocking:
        for ci: int in cells:
            grid.set_structure_i(ci, _next_id)

    var s: Structure = Structure.new()
    s.id = _next_id
    _next_id += 1
    s.kind = kind
    s.blocking = blocking
    s.anchor = anchor
    s.cells = cells
    s.center = footprint_center(anchor)
    s.label = label
    s.district = footprint_district(cells)
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


## Structures of one kind, in ascending id order (the stable order every
## tie-break in this project relies on).
func of_kind(kind: int) -> Array:
    var out: Array = []
    for id: int in structures:
        var s: Structure = structures[id]
        if s.kind == kind:
            out.append(s)
    out.sort_custom(func(a: Structure, b: Structure) -> bool: return a.id < b.id)
    return out


## WP-003 D-024: take a structure off the map but keep the SAME object (id,
## stats, counters, cooldown_left). While detached it is absent from
## `structures`, so nothing detects, attaches, fires or decrements its cooldown.
func detach(structure_id: int) -> bool:
    var s: Structure = structures.get(structure_id, null)
    if s == null:
        return false
    for ci: int in s.cells:
        _cell_owner.erase(ci)
        if s.blocking:
            grid.set_structure_i(ci, -1)
    structures.erase(structure_id)
    s.detached = true
    s.active = false
    detached[structure_id] = s
    if s.blocking:
        path.rebuild()
    return true


## Put a detached structure back at `anchor` through the FULL placement
## validation (terrain, overlap, current enemy occupancy, districts). On
## failure nothing changes. On success the same object re-occupies the map.
func restore(structure_id: int, anchor: Vector2i, sim: EnemySim, restrict_district: int = -1) -> Result:
    var s: Structure = detached.get(structure_id, null)
    if s == null:
        return _fail(Reject.NOT_DETACHED)
    var reason: int = validate(s.kind, anchor, sim, restrict_district)
    if reason != Reject.NONE:
        return _fail(reason)
    var cells: PackedInt32Array = footprint_cells(anchor)
    s.anchor = anchor
    s.cells = cells
    s.center = footprint_center(anchor)
    s.district = footprint_district(cells)
    s.detached = false
    s.active = true
    s.attached_to = -1
    s.group_id = -1
    # Targeting diagnostics belong to the old position: a restored hwacha has
    # no target until its next decision (counters and cooldown_left are kept).
    s.last_zone = -1
    s.last_aim = Vector2.ZERO
    s.last_target_local = 0
    s.last_target_shared = 0
    s.known_local = 0
    s.known_shared = 0
    s.wait_reason = ""
    s.muzzle_timer = 0.0
    for ci: int in cells:
        _cell_owner[ci] = s.id
        if s.blocking:
            grid.set_structure_i(ci, s.id)
    detached.erase(structure_id)
    structures[structure_id] = s
    if s.blocking:
        path.rebuild()
    var r: Result = Result.new()
    r.ok = true
    r.structure = s
    last_result = r
    return r


## Preview for a restore (same rules, no side effects, no counters).
func preview_restore(structure_id: int, anchor: Vector2i, sim: EnemySim, restrict_district: int = -1) -> int:
    var s: Structure = detached.get(structure_id, null)
    if s == null:
        return Reject.NOT_DETACHED
    return validate(s.kind, anchor, sim, restrict_district)


func get_any(structure_id: int) -> Structure:
    var s: Structure = structures.get(structure_id, null)
    if s == null:
        s = detached.get(structure_id, null)
    return s


func hwachas() -> Array:
    return of_kind(Kind.HWACHA)


func jangseungs() -> Array:
    return of_kind(Kind.JANGSEUNG)


func bongsus() -> Array:
    return of_kind(Kind.BONGSU)


func sensors() -> Array:
    return of_kind(Kind.SENSOR)


func get_structure(structure_id: int) -> Structure:
    return structures.get(structure_id, null)


## Debug "destroy" stand-in (WP-002 D-014): an inactive structure keeps its
## footprint (overlap is still refused) but stops detecting / relaying / firing.
## Returns false for an unknown id. Never touches the path field.
func set_active(structure_id: int, active: bool) -> bool:
    var s: Structure = structures.get(structure_id, null)
    if s == null:
        return false
    s.active = active
    return true


static func kind_name(kind: int) -> String:
    if kind < 0 or kind >= KIND_NAMES.size():
        return "UNKNOWN"
    return KIND_NAMES[kind]


static func kind_label(kind: int) -> String:
    if kind < 0 or kind >= KIND_LABELS.size():
        return "?"
    return KIND_LABELS[kind]


func count_of(kind: int) -> int:
    var n: int = 0
    for id: int in structures:
        if (structures[id] as Structure).kind == kind:
            n += 1
    return n
