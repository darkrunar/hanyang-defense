extends RefCounted
## AC-01 (counting side) and AC-06 (chokepoint scenario), plus determinism.

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SOUTH: int = 0
const Z_SOUTH_WEST_LANE: int = 0
const Z_SOUTH_EAST_LANE: int = 1


func run(t: RefCounted) -> void:
    _ac01_thousand_concurrent_on_three_routes(t)
    _ac01_counts_are_consistent(t)
    _ac06_chokepoint_raises_density_and_kills(t)
    _determinism_same_seed_same_result(t)


# --------------------------------------------------------------------- AC-01 ---

func _ac01_thousand_concurrent_on_three_routes(t: RefCounted) -> void:
    t.case("AC-01 1000 concurrent living enemies across all three entries")
    var cfg: Config = Config.for_wp001()
    cfg.values["combat_enabled"] = false   # kills off: prove the concurrent count
    var b: Battle = Battle.new(cfg)
    b.run_for(30.0)

    t.ge(float(b.sim.alive_count), 1000.0,
        "concurrent living enemies at t=30 s")
    t.ge(float(b.peak_alive), 1000.0, "peak concurrent living enemies")
    t.gt(float(b.sim.spawned_total), float(b.sim.alive_count),
        "cumulative spawns exceed the concurrent count (the two are distinct)")
    for r: int in range(b.path.route_ids.size()):
        t.gt(float(b.sim.route_alive[r]), 0.0,
            "route %s has living enemies" % TestMap.route_display_name(r))
        t.gt(float(b.sim.route_spawned[r]), 0.0,
            "route %s has spawned enemies" % TestMap.route_display_name(r))
    t.note("alive=%d peak=%d spawned=%d leaked=%d killed=%d | per-route alive %s" % [
        b.sim.alive_count, b.peak_alive, b.sim.spawned_total,
        b.sim.leaked_total, b.sim.killed_total, b.route_summary()
    ])

    # Both lanes of the south route are genuinely used.
    var counts: PackedInt32Array = b.density.evaluate(b.sim)
    t.gt(float(counts[Z_SOUTH_WEST_LANE]), 0.0, "south-west lane is in use")
    t.gt(float(counts[Z_SOUTH_EAST_LANE]), 0.0, "south-east lane is in use")


func _ac01_counts_are_consistent(t: RefCounted) -> void:
    t.case("AC-01 spawned = alive + killed + leaked at all times")
    var cfg: Config = Config.for_wp001()
    cfg.values["combat_enabled"] = true
    var b: Battle = Battle.new(cfg)
    for _i: int in range(6):
        b.run_for(5.0)
        var expect: int = b.sim.alive_count + b.sim.killed_total + b.sim.leaked_total
        if not t.eq(b.sim.spawned_total, expect, "book-keeping at t=%.0fs" % b.sim_time):
            return
    var route_sum: int = 0
    for r: int in range(b.path.route_ids.size()):
        route_sum += b.sim.route_alive[r]
    t.eq(route_sum, b.sim.alive_count, "per-route alive counts sum to the total")


# --------------------------------------------------------------------- AC-06 ---

func _ac06_chokepoint_raises_density_and_kills(t: RefCounted) -> void:
    t.case("AC-06 same seed, same instant: the jangseung raises the fired-on density")
    # Both halves use the same seed and are measured over the same simulated
    # window [settle, settle + window]. The only difference is whether the
    # jangseung is standing in the south-west lane.
    var settle: float = 30.0
    var window: float = 20.0
    var anchor: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_west_lane"]

    var baseline: Dictionary = _run_choke_case(false, settle, window, anchor)
    var choked: Dictionary = _run_choke_case(true, settle, window, anchor)

    if baseline["error"] != "" or choked["error"] != "":
        t.check(false, "scenario setup failed: baseline=%s choked=%s" % [
            baseline["error"], choked["error"]
        ])
        return

    t.note("baseline : east-lane density avg %.1f / west-lane avg %.1f / 화차·중영 kills %d / south arrivals %d" % [
        baseline["avg_east"], baseline["avg_west"], baseline["kills"], baseline["leaks"]
    ])
    t.note("with 장승 : east-lane density avg %.1f / west-lane avg %.1f / 화차·중영 kills %d / south arrivals %d" % [
        choked["avg_east"], choked["avg_west"], choked["kills"], choked["leaks"]
    ])

    t.gt(choked["avg_east"], baseline["avg_east"],
        "blocking the west lane raises the density in the zone the hwacha fires on")
    t.gt(float(choked["kills"]), float(baseline["kills"]),
        "the same hwacha kills more over the same window")
    t.check(float(choked["leaks"]) < float(baseline["leaks"]),
        "fewer south-route enemies reach the objective (%d < %d)" % [
            choked["leaks"], baseline["leaks"]
        ])
    t.eq(choked["avg_west"], 0.0, "the blocked lane stays empty in the choked case")


## One half of the AC-06 comparison. The jangseung goes down before the wave
## arrives, because the occupancy rule makes mid-flood lane placement rare
## (measured in the AC-03 suite); the comparison window is identical either way.
static func _run_choke_case(place: bool, settle: float, window: float, anchor: Vector2i) -> Dictionary:
    var cfg: Config = Config.for_wp001()
    cfg.values["combat_enabled"] = true
    var b: Battle = Battle.new(cfg)
    if place:
        var res: Placement.Result = b.place_jangseung(anchor)
        if not res.ok:
            return {"avg_east": -1.0, "avg_west": -1.0, "kills": -1, "leaks": -1,
                "error": Placement.reject_name(res.reason)}
    b.run_for(settle)

    var gun: Placement.Structure = b.placement.hwachas()[0]  # 화차·중영
    var kills_before: int = gun.kills
    var leaks_before: int = b.sim.route_leaked[SOUTH]

    var dt: float = b.config.get_num("fixed_dt")
    var n: int = int(round(window / dt))
    var sum_east: float = 0.0
    var sum_west: float = 0.0
    for _i: int in range(n):
        b.step(dt)
        sum_east += float(b.density.counts[Z_SOUTH_EAST_LANE])
        sum_west += float(b.density.counts[Z_SOUTH_WEST_LANE])
    return {
        "avg_east": sum_east / float(n),
        "avg_west": sum_west / float(n),
        "kills": gun.kills - kills_before,
        "leaks": b.sim.route_leaked[SOUTH] - leaks_before,
        "error": "",
    }


# -------------------------------------------------------------- determinism ---

func _determinism_same_seed_same_result(t: RefCounted) -> void:
    t.case("the same seed and the same inputs reproduce the same run")
    var a: Dictionary = _scripted_run(20260913)
    var b: Dictionary = _scripted_run(20260913)
    var c: Dictionary = _scripted_run(777)

    t.eq(a["alive"], b["alive"], "alive count reproduces")
    t.eq(a["killed"], b["killed"], "kill count reproduces")
    t.eq(a["leaked"], b["leaked"], "leak count reproduces")
    t.eq(a["zones"], b["zones"], "per-zone densities reproduce")
    t.eq(a["pos_hash"], b["pos_hash"], "enemy positions reproduce")
    t.ne(c["pos_hash"], a["pos_hash"], "a different seed gives a different run")


static func _scripted_run(seed_value: int) -> Dictionary:
    var cfg: Config = Config.for_wp001()
    cfg.values["seed"] = seed_value
    cfg.values["combat_enabled"] = true
    var b: Battle = Battle.new(cfg)
    b.run_for(12.0)
    b.place_jangseung(TestMap.AC_SCENARIO_ANCHORS["south_west_lane"])
    b.run_for(8.0)
    var h: float = 0.0
    for s: int in b.sim.live_slots():
        h += b.sim.pos_x[s] * 0.37 + b.sim.pos_y[s] * 1.13
    return {
        "alive": b.sim.alive_count,
        "killed": b.sim.killed_total,
        "leaked": b.sim.leaked_total,
        "zones": b.density.counts,
        "pos_hash": "%.3f" % h,
    }
