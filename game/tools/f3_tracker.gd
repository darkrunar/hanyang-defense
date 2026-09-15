extends RefCounted
## WP-003 F3 per-entity evidence (GPT review R-06): follows the 12 controlled
## enemies by individual id from their spawn to their fate, records who saw
## them (S4 / H1 local / H1 shared) on the first detection, every volley H1
## fires after the placement, and the core damage they caused. Used by the
## headless evidence tool and by the windowed F3 captures, so both write the
## same ledger.

const Battle := preload("res://game/core/battle.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const S4_ID: int = 16

var ids: Array = []                  # individual ids in spawn order
var _slot_of: Dictionary = {}        # id -> slot
var entities: Dictionary = {}        # id -> ledger row
var shots: Array = []                # every H1 volley after begin()
var h1_id: int = -1
var h1_shots_at_begin: int = 0
var h1_kills_at_begin: int = 0
var core_hp_at_begin: float = 0.0
var core_arrivals_at_begin: int = 0
var killed_at_begin: int = 0
var begin_tick: int = -1
var last_h1_shot: Dictionary = {}
var _core: Vector2 = Vector2.ZERO
var _goal_r: float = 26.0
var _last_pos: Dictionary = {}       # id -> [x, y]


func begin(b: Battle, slots: PackedInt32Array) -> void:
    ids.clear()
    entities.clear()
    shots.clear()
    _slot_of.clear()
    _last_pos.clear()
    h1_id = b.run.recovery_target_id
    var h1: Placement.Structure = b.placement.get_any(h1_id)
    h1_shots_at_begin = h1.shots_fired if h1 != null else 0
    h1_kills_at_begin = h1.kills if h1 != null else 0
    core_hp_at_begin = b.run.core_hp
    core_arrivals_at_begin = b.run.core_arrivals
    killed_at_begin = b.sim.killed_total
    begin_tick = b.steps
    _core = b.grid.cell_center(TestMap.CORE_GOAL_CELL.x, TestMap.CORE_GOAL_CELL.y)
    _goal_r = b.sim.goal_radius
    for s: int in slots:
        var id: int = b.sim.enemy_id(s)
        ids.append(id)
        _slot_of[id] = s
        entities[id] = {"id": id, "slot": s, "spawn_tick": b.steps, "spawn_pos": [b.sim.pos_x[s], b.sim.pos_y[s]],
            "hp_at_spawn": b.sim.hp[s], "first_seen_by_s4_tick": -1, "first_known_by_h1_tick": -1,
            "first_known_source": "", "fate": "alive", "fate_tick": -1, "fate_sim_time": -1.0,
            "last_pos": [b.sim.pos_x[s], b.sim.pos_y[s]], "hp_last": b.sim.hp[s], "volleys_hit": 0}
        _last_pos[id] = [b.sim.pos_x[s], b.sim.pos_y[s]]


## Detection record for the tick right after the spawn (the "first observation").
func first_observation(b: Battle) -> Dictionary:
    var h1: Placement.Structure = b.placement.get_any(h1_id)
    var s4_seen: Dictionary = b.network.sensor_seen.get(S4_ID, {})
    var h1_known: Dictionary = b.network.hwacha_known.get(h1_id, {})
    var h1_local: Dictionary = b.network.hwacha_local.get(h1_id, {})
    var rows: Array = []
    var seen_by_s4: int = 0
    var known_by_h1: int = 0
    for id: int in ids:
        var alive: bool = b.sim.is_id_alive(id)
        var s: int = _slot_of[id]
        var row: Dictionary = {"id": id, "alive": alive,
            "pos": [b.sim.pos_x[s], b.sim.pos_y[s]] if alive else _last_pos[id],
            "seen_by_s4": s4_seen.has(id), "known_by_h1": h1_known.has(id), "h1_local": h1_local.has(id),
            "in_z9": _in_zone(b, 9, id) if alive else false}
        if s4_seen.has(id):
            seen_by_s4 += 1
        if h1_known.has(id):
            known_by_h1 += 1
        rows.append(row)
    var out_local: PackedInt32Array = PackedInt32Array()
    var counts: PackedInt32Array = PackedInt32Array()
    if h1 != null and not h1.detached:
        counts = b.network.known_zone_counts(h1, b.density, b.sim, out_local)
    return {"tick": b.steps, "sim_time": b.sim_time, "seen_by_s4": seen_by_s4, "known_by_h1": known_by_h1,
        "h1": _h1_brief(h1), "h1_known_zone_counts": Array(counts), "h1_known_local_counts": Array(out_local),
        "s4_seen_ids": _sorted(s4_seen.keys()), "h1_known_ids": _sorted(h1_known.keys()),
        "entities": rows, "core_hp": b.run.core_hp}


## Call after every Battle.step(): fates, detections, volleys.
func after_tick(b: Battle) -> void:
    var s4_seen: Dictionary = b.network.sensor_seen.get(S4_ID, {})
    var h1_known: Dictionary = b.network.hwacha_known.get(h1_id, {})
    var h1_local: Dictionary = b.network.hwacha_local.get(h1_id, {})
    var h1_shot_ticks: Array = []
    for shot in b.hwacha.last_shots:
        if shot.hwacha_id == h1_id:
            var rec: Dictionary = {"tick": b.steps, "sim_time": shot.sim_time, "hwacha_id": shot.hwacha_id,
                "zone": shot.zone_id, "aim": [shot.aim.x, shot.aim.y], "radius": shot.radius,
                "enemies_in_zone": shot.enemies_in_zone, "local_in_zone": shot.local_in_zone,
                "shared_in_zone": shot.shared_in_zone, "shared_only": shot.local_in_zone == 0 and shot.shared_in_zone > 0,
                "kills": shot.kills}
            shots.append(rec)
            last_h1_shot = rec
            h1_shot_ticks.append(rec)
    for id: int in ids:
        var e: Dictionary = entities[id]
        if e["fate"] != "alive":
            continue
        var s: int = _slot_of[id]
        if b.sim.is_id_alive(id):
            var px: float = b.sim.pos_x[s]
            var py: float = b.sim.pos_y[s]
            e["last_pos"] = [px, py]
            _last_pos[id] = [px, py]
            if b.sim.hp[s] < float(e["hp_last"]):
                e["volleys_hit"] = int(e["volleys_hit"]) + 1
            e["hp_last"] = b.sim.hp[s]
            if int(e["first_seen_by_s4_tick"]) < 0 and s4_seen.has(id):
                e["first_seen_by_s4_tick"] = b.steps
            if int(e["first_known_by_h1_tick"]) < 0 and h1_known.has(id):
                e["first_known_by_h1_tick"] = b.steps
                e["first_known_source"] = "local" if h1_local.has(id) else "shared"
        else:
            # Gone this tick: killed by a volley (blast around a zone centre) or
            # consumed as an arrival at the core (inside the goal radius).
            var lp: Array = _last_pos[id]
            var d: float = Vector2(lp[0], lp[1]).distance_to(_core)
            var arrived: bool = d <= _goal_r + 2.0
            e["fate"] = "arrived_core" if arrived else "killed"
            e["fate_tick"] = b.steps
            e["fate_sim_time"] = b.sim_time
            e["fate_distance_to_core"] = d
            if not arrived:
                var by: Array = []
                for rec: Dictionary in h1_shot_ticks:
                    by.append(rec["hwacha_id"])
                e["killed_by_hwacha"] = by
                e["killed_in_zone"] = h1_shot_ticks[0]["zone"] if not h1_shot_ticks.is_empty() else -1


func report(b: Battle) -> Dictionary:
    var h1: Placement.Structure = b.placement.get_any(h1_id)
    var killed: int = 0
    var arrived: int = 0
    var alive: int = 0
    var rows: Array = []
    for id: int in ids:
        var e: Dictionary = entities[id]
        rows.append(e)
        match e["fate"]:
            "killed": killed += 1
            "arrived_core": arrived += 1
            _: alive += 1
    var shared_only: int = 0
    for rec: Dictionary in shots:
        if rec["shared_only"]:
            shared_only += 1
    return {"begin_tick": begin_tick, "end_tick": b.steps, "end_sim_time": b.sim_time, "ids": ids,
        "killed": killed, "arrived_core": arrived, "still_alive": alive,
        "h1": _h1_brief(h1), "h1_shots_after_placement": (h1.shots_fired - h1_shots_at_begin) if h1 != null else -1,
        "h1_kills_after_placement": (h1.kills - h1_kills_at_begin) if h1 != null else -1,
        "h1_volleys": shots, "h1_shared_only_volleys": shared_only,
        "core_hp_at_begin": core_hp_at_begin, "core_hp_at_end": b.run.core_hp,
        "core_damage": core_hp_at_begin - b.run.core_hp,
        "core_arrivals_delta": b.run.core_arrivals - core_arrivals_at_begin,
        "killed_total_delta": b.sim.killed_total - killed_at_begin,
        "run": b.run.run_name(), "alive_on_field": b.sim.alive_count, "entities": rows}


func _in_zone(b: Battle, zone_id: int, id: int) -> bool:
    var z = b.density.zone_by_id(zone_id)
    if z == null:
        return false
    var s: int = _slot_of[id]
    return Vector2(b.sim.pos_x[s], b.sim.pos_y[s]).distance_to(z.center) <= z.radius


static func _h1_brief(h1: Placement.Structure) -> Dictionary:
    if h1 == null:
        return {}
    return {"id": h1.id, "label": h1.label, "anchor": [h1.anchor.x, h1.anchor.y], "detached": h1.detached,
        "active": h1.active, "attached_to": h1.attached_to, "group": h1.group_id, "known_local": h1.known_local,
        "known_shared": h1.known_shared, "target_zone": h1.last_zone, "wait_reason": h1.wait_reason,
        "shots": h1.shots_fired, "kills": h1.kills, "cooldown_left": h1.cooldown_left}


static func _sorted(a: Array) -> Array:
    var out: Array = a.duplicate()
    out.sort()
    return out
