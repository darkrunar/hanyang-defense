extends RefCounted
## WP-003 run / defence-line state (backlog/WP-003.md READY v1.0, D-023 / D-024).
##
##  * run_state RUNNING / WON / LOST is final once left RUNNING
##  * defense_state OUTER_ACTIVE / INNER_ONLY changes exactly once (collapse)
##  * stronghold HP never goes below 0 and overflow is never forwarded
##  * the recovery right is created once by the collapse and consumed once by a
##    successful placement
##  * every meaningful transition is logged with tick + sequence number

enum Run { RUNNING, WON, LOST }
enum Defense { OUTER_ACTIVE, INNER_ONLY }

const RUN_NAMES: Array[String] = ["RUNNING", "WON", "LOST"]
const DEFENSE_NAMES: Array[String] = ["OUTER_ACTIVE", "INNER_ONLY"]

var run: int = Run.RUNNING
var defense: int = Defense.OUTER_ACTIVE
var run_id: int = 1

var outer_hp: float = 120.0
var core_hp: float = 60.0
var outer_hp_max: float = 120.0
var core_hp_max: float = 60.0
var arrival_damage: float = 1.0

var collapse_count: int = 0
var collapse_tick: int = -1
var collapse_sim_time: float = -1.0

## Recovery (D-024): target id is bound when the fixture is created.
var recovery_target_id: int = -1
var recovery_right: int = 0          # 1 after the collapse, 0 after the placement
var recovery_placed: bool = false
var recovery_placed_tick: int = -1
var recovery_anchor: Vector2i = Vector2i(-1, -1)

## Damage accounting (arrivals are leaks, never kills).
var outer_arrivals: int = 0
var core_arrivals: int = 0
var outer_damage_total: float = 0.0
var core_damage_total: float = 0.0
## Benchmark-only (D-027): attempts that were absorbed by core invulnerability.
var core_damage_absorbed: float = 0.0
var core_invulnerable: bool = false

var end_tick: int = -1
var end_sim_time: float = -1.0

var events: Array = []
var _seq: int = 0
## Verification-only forced HP writes are logged so evidence can show them.
var forced_hp_writes: int = 0


func reset(outer: float, core: float, dmg: float, keep_run_id: bool) -> void:
    run = Run.RUNNING
    defense = Defense.OUTER_ACTIVE
    if not keep_run_id:
        run_id += 1
    outer_hp = outer
    core_hp = core
    outer_hp_max = outer
    core_hp_max = core
    arrival_damage = dmg
    collapse_count = 0
    collapse_tick = -1
    collapse_sim_time = -1.0
    recovery_target_id = -1
    recovery_right = 0
    recovery_placed = false
    recovery_placed_tick = -1
    recovery_anchor = Vector2i(-1, -1)
    outer_arrivals = 0
    core_arrivals = 0
    outer_damage_total = 0.0
    core_damage_total = 0.0
    core_damage_absorbed = 0.0
    end_tick = -1
    end_sim_time = -1.0
    events.clear()
    _seq = 0
    forced_hp_writes = 0


func ended() -> bool:
    return run != Run.RUNNING


func run_name() -> String:
    return RUN_NAMES[run]


func defense_name() -> String:
    return DEFENSE_NAMES[defense]


func log_event(tick: int, sim_time: float, type: String, data: Dictionary = {}) -> Dictionary:
    _seq += 1
    var e: Dictionary = {"seq": _seq, "tick": tick, "sim_time": sim_time, "run_id": run_id, "type": type}
    for k: Variant in data:
        e[k] = data[k]
    events.append(e)
    return e


func events_of(type: String) -> Array:
    var out: Array = []
    for e: Dictionary in events:
        if e["type"] == type:
            out.append(e)
    return out


## Apply `arrivals` arrivals to the OUTER stronghold. Returns the damage dealt
## (clamped at the remaining HP; overflow is dropped, never forwarded).
func damage_outer(arrivals: int) -> float:
    if arrivals <= 0:
        return 0.0
    var attempted: float = float(arrivals) * arrival_damage
    var dealt: float = minf(attempted, outer_hp)
    outer_hp -= dealt
    outer_arrivals += arrivals
    outer_damage_total += dealt
    return dealt


## Apply arrivals to the CORE. With core_invulnerable the attempt is counted
## and absorbed (benchmark only, D-027).
func damage_core(arrivals: int) -> float:
    if arrivals <= 0:
        return 0.0
    var attempted: float = float(arrivals) * arrival_damage
    core_arrivals += arrivals
    if core_invulnerable:
        core_damage_absorbed += attempted
        return 0.0
    var dealt: float = minf(attempted, core_hp)
    core_hp -= dealt
    core_damage_total += dealt
    return dealt


func snapshot() -> Dictionary:
    return {
        "run": run_name(),
        "defense": defense_name(),
        "run_id": run_id,
        "outer_hp": outer_hp,
        "core_hp": core_hp,
        "outer_hp_max": outer_hp_max,
        "core_hp_max": core_hp_max,
        "arrival_damage": arrival_damage,
        "collapse_count": collapse_count,
        "collapse_tick": collapse_tick,
        "collapse_sim_time": collapse_sim_time,
        "recovery_target_id": recovery_target_id,
        "recovery_right": recovery_right,
        "recovery_placed": recovery_placed,
        "recovery_placed_tick": recovery_placed_tick,
        "recovery_anchor": [recovery_anchor.x, recovery_anchor.y],
        "outer_arrivals": outer_arrivals,
        "core_arrivals": core_arrivals,
        "outer_damage_total": outer_damage_total,
        "core_damage_total": core_damage_total,
        "core_damage_absorbed": core_damage_absorbed,
        "core_invulnerable": core_invulnerable,
        "end_tick": end_tick,
        "end_sim_time": end_sim_time,
        "forced_hp_writes": forced_hp_writes,
        "event_count": events.size(),
    }
