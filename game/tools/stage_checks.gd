extends RefCounted
## Headless checks for the core-loop ladder (game/core/stage_ladder.gd, D-056).
## Each check runs the REAL Battle with the stage's config and compares the
## stage against the condition one step earlier on the same seed, so the
## number shows what the one new content changes. Used by
## tests/test_stage_ladder.gd (assertions) and game/tools/stage_report.gd
## (evidence JSON). Stages 7 / 8 add screens and input, so their checks live
## in the scene tests; here they report the core run they start.

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const StageLadder := preload("res://game/core/stage_ladder.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const Z_SOUTH_WEST_LANE: int = 0
const Z_SOUTH_EAST_LANE: int = 1
const SOUTH: int = 0


static func run(id: int) -> Dictionary:
    match id:
        1: return _stage1()
        2: return _stage2()
        3: return _stage3()
        4: return _stage4()
        5: return _stage5()
        6: return _stage6()
        7: return _stage_core_only(7)
        8: return _stage_core_only(8)
    return {"id": id, "pass": false, "error": "not a playable stage"}


static func _battle(id: int) -> Battle:
    return Battle.new(StageLadder.config_for(id))


static func _result(id: int, ok: bool, metrics: Dictionary, why: Array) -> Dictionary:
    var st: Dictionary = StageLadder.get_stage(id)
    return {"id": id, "key": st.get("key", ""), "title": st.get("title", ""), "check": st.get("check", ""),
        "pass": ok, "failed": why, "metrics": metrics}


static func _need(cond: bool, why: Array, msg: String) -> bool:
    if not cond:
        why.append(msg)
    return cond


# 1 · enemy flow: three routes carry traffic to the goal, nothing kills.
static func _stage1() -> Dictionary:
    var b: Battle = _battle(1)
    b.run_for(30.0)
    var per_route: Array = Array(b.sim.route_alive)
    var why: Array = []
    for r: int in range(per_route.size()):
        _need(int(per_route[r]) > 0, why, "route %d empty" % r)
    _need(b.sim.leaked_total > 0, why, "nothing reached the goal")
    _need(b.sim.killed_total == 0, why, "kills without any hwacha")
    _need(b.placement.structures.size() == 0, why, "structures present")
    return _result(1, why.is_empty(), {"t": b.sim_time, "alive": b.sim.alive_count, "route_alive": per_route,
        "route_leaked": Array(b.sim.route_leaked), "leaked": b.sim.leaked_total, "killed": b.sim.killed_total}, why)


# 2 · 장승: the same seed with one jangseung in the south-west lane.
static func _lane_density(place: bool, window_start: float, window: float) -> Dictionary:
    var b: Battle = _battle(2)
    var res: Placement.Result = null
    if place:
        res = b.place_jangseung(TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    b.run_for(window_start)
    var dt: float = b.config.get_num("fixed_dt")
    var n: int = int(round(window / dt))
    var sw: float = 0.0
    var se: float = 0.0
    for _i: int in range(n):
        b.step(dt)
        sw += float(b.density.counts[Z_SOUTH_WEST_LANE])
        se += float(b.density.counts[Z_SOUTH_EAST_LANE])
    return {"b": b, "placed": res.ok if res != null else false, "avg_west": sw / float(n), "avg_east": se / float(n),
        "path_version": b.path.path_version}


static func _stage2() -> Dictionary:
    var ref: Dictionary = _lane_density(false, 25.0, 10.0)
    var blk: Dictionary = _lane_density(true, 25.0, 10.0)
    # the second south lane would seal the south route: refused, nothing
    # changes. Probed on the empty field at t=0 (occupancy is checked before
    # reachability, so a lane full of enemies would answer ENEMY_OCCUPIES_CELL).
    var b: Battle = _battle(2)
    b.place_jangseung(TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    var pv: int = b.path.path_version
    var seal: Placement.Result = b.place_jangseung(TestMap.AC_SCENARIO_ANCHORS["south_east_lane"])
    var why: Array = []
    _need(blk["placed"], why, "jangseung refused")
    _need(float(blk["avg_west"]) == 0.0, why, "blocked lane not empty")
    _need(float(blk["avg_east"]) > float(ref["avg_east"]), why, "no detour into the east lane")
    _need(not seal.ok and seal.reason == Placement.Reject.WOULD_BLOCK_ALL_PATHS, why, "sealing placement not refused")
    _need(b.path.path_version == pv, why, "refusal changed the path")
    return _result(2, why.is_empty(), {"window": "25..35 s", "no_jangseung": {"avg_west": ref["avg_west"], "avg_east": ref["avg_east"]},
        "jangseung_44_36": {"avg_west": blk["avg_west"], "avg_east": blk["avg_east"], "path_version": blk["path_version"]},
        "seal_refused": Placement.reject_name(seal.reason)}, why)


# 3 · 화차: fewer leaks than stage 1, and the jangseung bottleneck feeds the gun.
static func _choke(place: bool) -> Dictionary:
    var b: Battle = _battle(3)
    if place:
        b.place_jangseung(TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    b.run_for(20.0)
    var gun: Placement.Structure = b.placement.hwachas()[0]   # 화차·중영
    var k0: int = gun.kills
    b.run_for(15.0)
    return {"b": b, "gun_kills": gun.kills - k0, "killed": b.sim.killed_total, "leaked": b.sim.leaked_total}


static func _stage3() -> Dictionary:
    var s1: Battle = _battle(1)
    s1.run_for(35.0)
    var open: Dictionary = _choke(false)
    var choke: Dictionary = _choke(true)
    var why: Array = []
    _need(int(open["killed"]) > 0, why, "hwachas killed nothing")
    _need(int(open["leaked"]) < s1.sim.leaked_total, why, "no fewer leaks than stage 1")
    _need(int(choke["gun_kills"]) > int(open["gun_kills"]), why, "bottleneck did not raise 화차·중영 kills")
    return _result(3, why.is_empty(), {"t": 35.0, "stage1_leaked": s1.sim.leaked_total, "leaked": open["leaked"], "killed": open["killed"],
        "window": "20..35 s", "gun_kills_open": open["gun_kills"], "gun_kills_bottleneck": choke["gun_kills"]}, why)


# 4 · 봉수망: shared-only volleys exist, and vanish with every bongsu off.
static func _network(all_off: bool) -> Battle:
    var b: Battle = _battle(4)
    if all_off:
        for s: Placement.Structure in b.placement.bongsus():
            b.set_active(s.id, false)
    b.run_for(20.0)
    return b


static func _stage4() -> Dictionary:
    var on: Battle = _network(false)
    var off: Battle = _network(true)
    var shared_known: int = 0
    for h: Placement.Structure in on.placement.hwachas():
        shared_known += h.known_shared
    var why: Array = []
    _need(on.hwacha.shared_only_shots > 0, why, "no shared-only volley")
    _need(off.hwacha.shared_only_shots == 0, why, "shared volleys with the network off")
    return _result(4, why.is_empty(), {"t": 20.0, "shared_only_shots": on.hwacha.shared_only_shots, "shots": on.hwacha.shots_total,
        "killed": on.sim.killed_total, "network_off": {"shared_only_shots": off.hwacha.shared_only_shots, "shots": off.hwacha.shots_total,
        "killed": off.sim.killed_total}, "groups": on.network.groups()}, why)


static func _to_end(b: Battle, limit: float, recover_at: Vector2i = Vector2i(-1, -1)) -> Dictionary:
    var dt: float = b.config.get_num("fixed_dt")
    var placed: bool = false
    var place_t: float = -1.0
    while not b.run.ended() and b.sim_time < limit:
        b.step(dt)
        if recover_at.x >= 0 and not placed and b.run.recovery_right > 0:
            var r: Placement.Result = b.place_recovery(recover_at)
            if r.ok:
                placed = true
                place_t = b.sim_time
    return {"placed": placed, "place_t": place_t}


# 5 · waves + strongholds: a finite run that ends WON without a collapse.
static func _stage5() -> Dictionary:
    var b: Battle = _battle(5)
    _to_end(b, 300.0)
    var why: Array = []
    _need(b.run.run_name() == "WON", why, "run not WON (%s)" % b.run.run_name())
    _need(b.run.collapse_count == 0, why, "collapsed")
    _need(b.sim.spawned_total == 1140, why, "spawned %d != 1140" % b.sim.spawned_total)
    _need(b.run.outer_hp > 0.0, why, "outer HP 0")
    return _result(5, why.is_empty(), {"outcome": b.run.run_name(), "ended_at": b.sim_time, "outer_hp": b.run.outer_hp,
        "outer_arrivals": b.run.outer_arrivals, "core_hp": b.run.core_hp, "killed": b.sim.killed_total, "spawned": b.sim.spawned_total}, why)


# 6 · collapse: outer HP 40 collapses from real arrivals, H1 goes to B, the run finishes.
static func _stage6() -> Dictionary:
    var b: Battle = _battle(6)
    var rec: Dictionary = _to_end(b, 300.0, TestMap.RECOVERY_B)
    var h1: Placement.Structure = b.placement.get_any(b.run.recovery_target_id)
    var why: Array = []
    _need(b.run.collapse_count == 1, why, "no collapse")
    _need(b.run.forced_hp_writes == 0, why, "forced HP writes")
    _need(bool(rec["placed"]), why, "recovery not placed")
    _need(h1 != null and h1.id == b.run.recovery_target_id and not h1.detached, why, "recovered hwacha missing")
    _need(b.run.ended(), why, "run did not end")
    return _result(6, why.is_empty(), {"collapse_t": b.run.collapse_sim_time, "recovery_t": rec["place_t"], "outcome": b.run.run_name(),
        "ended_at": b.sim_time, "core_hp": b.run.core_hp, "core_arrivals": b.run.core_arrivals, "h1_shots": h1.shots_fired if h1 != null else -1}, why)


# 7 / 8: the screens are scene-tested; record the core run the stage starts.
static func _stage_core_only(id: int) -> Dictionary:
    var b: Battle = _battle(id)
    var why: Array = []
    _need(b.run_mode == "waves", why, "not a waves run")
    if id == 8:
        _need(b.preparing and b.economy.supply == 240 and b.placement.structures.size() == 4, why, "build start state")
    else:
        _need(not b.preparing and b.placement.structures.size() == 18, why, "classic start state")
    return _result(id, why.is_empty(), {"play_mode": b.play_mode, "preparing": b.preparing, "structures": b.placement.structures.size(),
        "supply": b.economy.supply, "note": "screens / input checked by tests/test_stage_ladder.gd scene cases"}, why)
