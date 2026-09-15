extends RefCounted
## WP-003 AC-01..06: strongholds, collapse, retreat, recovery, waves, win/lose,
## restart, and the fixed scenarios F1..F4 (backlog/WP-003.md READY v1.0).

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const RunState := preload("res://game/core/run_state.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SOUTH: int = 0
const K_H: int = Placement.Kind.HWACHA
const K_S: int = Placement.Kind.SENSOR
const Z7: int = 7
const Z8: int = 8
const Z9: int = 9
const OUTER_GOAL: Vector2 = Vector2(950.0, 530.0)
const CORE_GOAL: Vector2 = Vector2(950.0, 210.0)
const H1: int = 1
const H2: int = 2
const H4: int = 4
const B2: int = 6
const S4: int = 16
const MAX_RUN_SECONDS: float = 300.0


static func _wp003(combat: bool = true) -> Battle:
    var cfg: Config = Config.for_wp003()
    cfg.values["combat_enabled"] = combat
    return Battle.new(cfg)


static func _dt(b: Battle) -> float:
    return b.config.get_num("fixed_dt")


## Run until the run ends or `limit` seconds pass. Returns elapsed seconds.
static func _run_until_end(b: Battle, limit: float) -> float:
    var dt: float = _dt(b)
    var n: int = int(round(limit / dt))
    for _i: int in range(n):
        if b.run.ended():
            break
        b.step(dt)
    return b.sim_time


func run(t: RefCounted) -> void:
    _setup_fixture_c(t)
    _ac01_collapse_once(t)
    _ac01_doorstep_kill_deals_no_damage(t)
    _ac01_duplicate_collapse_callback(t)
    _ac02_targets_and_state_preserved(t)
    _ac03_recovery_rules(t)
    _ac03_cooldown_freeze_vs_inactive(t)
    _f1_normal_defense(t)
    _f2_forced_collapse_recovery_win(t)
    _f3_ab_comparison(t)
    _f4_lose_stop_restart(t)


# --------------------------------------------------------------------- setup ---

func _setup_fixture_c(t: RefCounted) -> void:
    t.case("setup: fixture C = 18 structures, 10 zones, outer goal, recovery target H1")
    var b: Battle = _wp003()
    t.eq(b.placement.structures.size(), 18, "18 structures placed")
    t.eq(b.placement.count_of(K_H), 4, "4 hwacha")
    t.eq(b.placement.count_of(Placement.Kind.BONGSU), 8, "8 bongsu")
    t.eq(b.placement.count_of(K_S), 4, "4 sensors")
    t.eq(b.placement.count_of(Placement.Kind.JANGSEUNG), 2, "2 outer jangseung")
    var ids: Array = b.placement.structures.keys()
    ids.sort()
    t.eq(ids, range(1, 19), "stable ids 1..18 in creation order")
    var d: Dictionary = b.district_counts()
    t.eq(d["inner_total"], 4, "inner structures: H4, B2, B3, S4")
    t.eq(d["outer_total"], 14, "outer structures")
    var inner_ids: Array = []
    for id: int in b.placement.structures:
        if (b.placement.structures[id] as Placement.Structure).district == TestMap.DISTRICT_INNER:
            inner_ids.append(id)
    inner_ids.sort()
    t.eq(inner_ids, [4, 6, 7, 16], "inner ids are H4(4), B2(6), B3(7), S4(16)")
    t.eq(b.density.zones.size(), 10, "10 candidate zones (8 + Z8 + Z9)")
    t.eq(b.density.zones[Z8].center, Vector2(950.0, 560.0), "Z8 centre")
    t.eq(b.density.zones[Z9].center, Vector2(950.0, 410.0), "Z9 centre")
    t.eq(b.path.goal_cell, TestMap.OUTER_GOAL_CELL, "run starts with the outer stronghold as the goal")
    for r: int in range(b.path.route_ids.size()):
        t.check(b.path.route_reachable(r), "route %d reaches the outer goal with the jangseung standing" % r)
    t.eq(b.run.run_name(), "RUNNING", "run state")
    t.eq(b.run.defense_name(), "OUTER_ACTIVE", "defense state")
    t.eq(b.run.outer_hp, 360.0, "outer HP 360 (D-032)")
    t.eq(b.run.outer_hp_max, 360.0, "outer HP max 360 (D-032)")
    t.eq(b.run.core_hp, 60.0, "core HP 60")
    t.eq(b.run.recovery_target_id, H1, "recovery target bound to H1's id at creation")
    t.eq(b.run.recovery_right, 0, "no recovery right before the collapse")
    t.eq(b.waves.total_budget(), 1140, "wave budget 1140")
    t.eq(b.sim.alive_count, 0, "no enemies at start")
    t.eq(b.sim.arrival_mode, "after_fire", "WP-003 arrival mode")
    # WP-001/002 defaults untouched
    var sandbox: Battle = Battle.new(Config.new())
    t.eq(sandbox.density.zones.size(), 8, "WP-002 default keeps 8 zones")
    t.eq(sandbox.sim.arrival_mode, "immediate", "WP-002 default keeps immediate arrivals")
    t.eq(sandbox.path.goal_cell, TestMap.GOAL_CELL, "WP-002 default keeps the core goal")


# --------------------------------------------------------------------- AC-01 ---

func _ac01_collapse_once(t: RefCounted) -> void:
    t.case("AC-01 outer HP 0 by real arrivals -> exactly one collapse, overflow dropped, one recovery right")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    b.force_outer_hp(1.0, "AC-01 verification")
    # Three survivors on the doorstep: 3 attempted damage, only 1 HP left.
    for i: int in range(3):
        b.sim.force_spawn(SOUTH, OUTER_GOAL + Vector2(float(i) * 2.0, 0.0))
    var pv: int = b.path.path_version
    var jang_before: int = b.placement.count_of(Placement.Kind.JANGSEUNG)
    b.step(_dt(b))
    t.eq(b.run.collapse_count, 1, "collapse happened once")
    t.eq(b.run.outer_hp, 0.0, "outer HP clamped at 0")
    t.eq(b.run.core_hp, 60.0, "overflow (2) was NOT forwarded to the core")
    t.eq(b.run.outer_arrivals, 3, "all three arrivals consumed")
    t.eq(b.sim.alive_count, 0, "consumed enemies are gone (leaks, not kills)")
    t.eq(b.sim.killed_total, 0, "arrivals are not kills")
    t.eq(b.run.defense_name(), "INNER_ONLY", "defense state switched")
    t.eq(b.run.recovery_right, 1, "one recovery right created")
    t.eq(b.run.events_of("collapse").size(), 1, "one collapse event")
    t.eq(b.run.events_of("recovery_created").size(), 1, "one recovery_created event")
    t.eq(b.path.goal_cell, TestMap.CORE_GOAL_CELL, "goal is now the core")
    t.eq(b.path.path_version, pv + 1, "exactly one path rebuild for the target change")
    t.check(b.placement.detached.has(H1), "H1 is detached (waiting)")
    t.check(not b.placement.structures.has(H1), "H1 is not on the map")
    var d: Dictionary = b.district_counts()
    t.eq(d["outer_active"], 0, "no active outer structure")
    t.eq(d["outer_total"], 13, "13 outer structures keep their footprint")
    t.eq(d["inner_active"], 4, "inner structures stay active")
    t.eq(b.placement.count_of(Placement.Kind.JANGSEUNG), jang_before, "jangseung still standing (blocking kept)")
    for r: int in range(b.path.route_ids.size()):
        t.check(b.path.route_reachable(r), "route %d reaches the core with the jangseung kept" % r)
    # Further arrivals go to the core and never re-trigger the collapse.
    for i: int in range(2):
        b.sim.force_spawn(SOUTH, CORE_GOAL + Vector2(float(i) * 2.0, 0.0))
    b.step(_dt(b))
    t.eq(b.run.core_hp, 58.0, "post-collapse arrivals damage the core (60 -> 58)")
    t.eq(b.run.collapse_count, 1, "collapse count still 1")
    t.eq(b.run.recovery_right, 1, "no second recovery right")
    t.eq(b.run.events_of("collapse").size(), 1, "still one collapse event")
    t.eq(b.run.outer_hp, 0.0, "outer HP unchanged at 0")


func _ac01_doorstep_kill_deals_no_damage(t: RefCounted) -> void:
    t.case("AC-01/F4 contrast: an enemy killed by fire on the doorstep deals no damage")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    # hp 1 enemy at the outer goal: inside Z8 (dist 30) and H1's local radius (70.7).
    b.sim.force_spawn(SOUTH, OUTER_GOAL, 1.0)
    b.step(_dt(b))
    t.eq(b.sim.killed_total, 1, "H1 killed it on the doorstep")
    t.eq(b.run.outer_hp, 360.0, "no stronghold damage")
    t.eq(b.run.outer_arrivals, 0, "no arrival recorded")
    t.eq(b.run.collapse_count, 0, "no collapse")
    # Same position, sturdy enemy: survives the volley (34 < 60) and arrives.
    b.sim.force_spawn(SOUTH, OUTER_GOAL)
    b.step(_dt(b))
    t.eq(b.run.outer_hp, 359.0, "a surviving arrival deals exactly arrival_damage 1")
    t.eq(b.run.outer_arrivals, 1, "one arrival")


## R-04 (GPT review): the collapse entry point is idempotent. A duplicate call
## in the waiting state, after the placement and after the run has ended
## changes no state, right, path, network or event.
func _ac01_duplicate_collapse_callback(t: RefCounted) -> void:
    t.case("AC-01/AC-03 R-04 duplicate collapse callback: refused in waiting / placed / ended states, nothing changes")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    b.force_outer_hp(1.0, "R-04 verification")
    b.sim.force_spawn(SOUTH, OUTER_GOAL)
    b.step(_dt(b))
    t.eq(b.run.collapse_count, 1, "real collapse through arrival damage")
    t.eq(b.run.collapse_calls_ignored, 0, "no ignored call yet")
    # (a) waiting state: H1 detached, right 1
    var before: String = b.full_state_json()
    var pv: int = b.path.path_version
    var topo: int = b.network.topology_version
    var ev: int = b.run.events.size()
    t.eq(b.collapse(), false, "duplicate call in the waiting state is refused")
    t.eq(b.full_state_json(), before, "waiting: full state unchanged")
    t.eq(b.run.recovery_right, 1, "waiting: right still 1")
    t.eq(b.run.events_of("collapse").size(), 1, "waiting: one collapse event")
    t.eq(b.run.events_of("recovery_created").size(), 1, "waiting: one recovery_created event")
    t.eq(b.run.events.size(), ev, "waiting: no new event")
    t.eq(b.path.path_version, pv, "waiting: no path rebuild")
    t.eq(b.network.topology_version, topo, "waiting: network topology unchanged")
    t.eq(b.run.collapse_calls_ignored, 1, "waiting: ignored counter 1")
    # (b) placed state: right consumed, H1 on the map at B
    var ok: Placement.Result = b.place_recovery(TestMap.RECOVERY_B)
    t.check(ok.ok, "placement at B accepted")
    before = b.full_state_json()
    pv = b.path.path_version
    topo = b.network.topology_version
    ev = b.run.events.size()
    t.eq(b.collapse(), false, "duplicate call after the placement is refused")
    t.eq(b.full_state_json(), before, "placed: full state unchanged")
    t.eq(b.run.recovery_right, 0, "placed: right stays consumed (0)")
    t.check(b.placement.structures.has(H1) and not b.placement.detached.has(H1), "placed: H1 stays on the map, not detached again")
    t.eq(b.placement.structures.size(), 18, "placed: 18 structures")
    t.eq(b.run.events_of("collapse").size(), 1, "placed: still one collapse event")
    t.eq(b.run.events_of("recovery_created").size(), 1, "placed: still one recovery_created event")
    t.eq(b.run.events.size(), ev, "placed: no new event")
    t.eq(b.path.path_version, pv, "placed: no path rebuild")
    t.eq(b.network.topology_version, topo, "placed: network topology unchanged")
    t.eq(b.run.collapse_calls_ignored, 2, "placed: ignored counter 2")
    # (c) ended state (LOST through a real core arrival at core HP 1)
    b.force_core_hp(1.0, "R-04 end the run")
    b.sim.force_spawn(SOUTH, CORE_GOAL)
    b.step(_dt(b))
    t.eq(b.run.run_name(), "LOST", "run ended")
    before = b.full_state_json()
    ev = b.run.events.size()
    t.eq(b.collapse(), false, "duplicate call after the end is refused")
    t.eq(b.full_state_json(), before, "ended: full state unchanged")
    t.eq(b.run.events.size(), ev, "ended: no new event")
    t.eq(b.run.collapse_calls_ignored, 3, "ended: ignored counter 3")
    # (d) a fresh run: a duplicate arriving at the natural path is also
    # impossible because _process_arrivals only calls it while collapse_count == 0;
    # the restart clears the ignored counter.
    b.restart()
    t.eq(b.run.collapse_calls_ignored, 0, "restart clears the ignored counter")
    t.eq(b.run.collapse_count, 0, "restart clears the collapse")


# --------------------------------------------------------------------- AC-02 ---

func _ac02_targets_and_state_preserved(t: RefCounted) -> void:
    t.case("AC-02 living and new enemies switch to the core, state preserved, no teleport")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    b.run_for(1.0)
    # A few enemies in flight on the south road (Z2, which no hwacha covers, so
    # they take no volley during the collapse tick) plus the trigger enemy.
    var flying: PackedInt32Array = PackedInt32Array()
    for i: int in range(5):
        flying.append(b.sim.force_spawn(SOUTH, Vector2(940.0, 1000.0 + float(i) * 6.0)))
    b.force_outer_hp(1.0, "AC-02 verification")
    b.sim.force_spawn(SOUTH, OUTER_GOAL)
    var ids_before: Array = []
    var pos_before: Array = []
    var hp_before: Array = []
    for s: int in flying:
        ids_before.append(b.sim.enemy_id(s))
        pos_before.append(Vector2(b.sim.pos_x[s], b.sim.pos_y[s]))
        hp_before.append(b.sim.hp[s])
    b.step(_dt(b))
    t.eq(b.run.collapse_count, 1, "collapse happened")
    var max_move: float = b.sim.base_speed * (1.0 + b.sim.speed_jitter) * _dt(b) + 0.001
    for i: int in range(flying.size()):
        var s: int = flying[i]
        t.check(b.sim.alive[s] == 1 and b.sim.enemy_id(s) == ids_before[i], "enemy %d keeps its id" % i)
        t.eq(b.sim.hp[s], hp_before[i], "enemy %d keeps its hp" % i)
        var moved: float = Vector2(b.sim.pos_x[s], b.sim.pos_y[s]).distance_to(pos_before[i])
        t.check(moved <= max_move, "enemy %d moved at most one tick (%.2f px), no teleport" % [i, moved])
    # Next ticks: they follow the core field. A new spawn also targets the core.
    var new_slot: int = b.sim.spawn_on_route(SOUTH, 1)
    t.eq(new_slot, 1, "new enemy spawned after the collapse")
    b.run_for(40.0)
    t.eq(b.run.outer_arrivals, 1, "no further outer arrivals after the collapse")
    t.check(b.run.core_arrivals + b.sim.killed_total >= 5, "flying enemies reached the core or died on the way (%d arrived, %d killed)" % [b.run.core_arrivals, b.sim.killed_total])
    t.eq(b.sim.alive_count, 0, "nobody is stuck on the abandoned target")
    t.eq(b.run.events_of("target_changed").size(), 1, "one target_changed event")


# --------------------------------------------------------------------- AC-03 ---

func _ac03_recovery_rules(t: RefCounted) -> void:
    t.case("AC-03 outer functions stop; only H1 can be restored, once, inner only, same id")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    # Before the collapse: no right.
    var early: Placement.Result = b.place_recovery(TestMap.RECOVERY_B)
    t.eq(early.reason, Placement.Reject.NO_RECOVERY_RIGHT, "no recovery before the collapse")
    # Fire once so H1 carries counters into the detached state.
    b.sim.force_spawn(SOUTH, OUTER_GOAL + Vector2(0.0, -20.0))
    b.step(_dt(b))
    var h1: Placement.Structure = b.placement.get_structure(H1)
    var shots_before: int = h1.shots_fired
    t.check(shots_before >= 1, "H1 fired before the collapse")
    b.sim.apply_blast(OUTER_GOAL + Vector2(0.0, -20.0), 30.0, 9999.0)
    b.force_outer_hp(1.0, "AC-03 verification")
    b.sim.force_spawn(SOUTH, OUTER_GOAL)
    b.step(_dt(b))
    t.eq(b.run.collapse_count, 1, "collapsed")
    var cd_at_collapse: float = h1.cooldown_left
    # Outer functions are off: put enemies into an outer lane zone, nobody outer fires.
    var h2: Placement.Structure = b.placement.get_structure(H2)
    var h2_shots: int = h2.shots_fired
    for i: int in range(6):
        b.sim.force_spawn(SOUTH, Vector2(460.0 + float(i) * 3.0, 500.0))   # Z3 (west north lane)
    b.run_for(2.0)
    t.eq(h2.shots_fired, h2_shots, "inactive outer hwacha fired nothing")
    t.eq(h2.known_local + h2.known_shared, 0, "inactive outer hwacha knows nothing")
    t.eq(b.network.link_count(), 1, "only the inner B2-B3 link remains")
    # Refusals keep the right and change nothing.
    var structures_before: int = b.placement.structures.size()
    var cases: Array = [
        [Vector2i(46, 29), Placement.Reject.DISTRICT_LOST, "outer district (H1's old spot)"],
        [Vector2i(41, 18), Placement.Reject.DISTRICT_SPLIT, "footprint straddles outer/inner (plaza strip)"],
        [Vector2i(44, 4), Placement.Reject.TERRAIN_BLOCKED, "wall"],
        [Vector2i(47, 15), Placement.Reject.STRUCTURE_OVERLAP, "on S4"],
    ]
    for c: Array in cases:
        var r: Placement.Result = b.place_recovery(c[0])
        t.eq(r.reason, c[1], "refused: %s" % c[2])
        t.eq(b.run.recovery_right, 1, "right kept after refusal (%s)" % c[2])
        t.eq(b.placement.structures.size(), structures_before, "no structure change (%s)" % c[2])
    var occ: int = b.sim.force_spawn(SOUTH, b.grid.cell_center(TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y))
    var r_occ: Placement.Result = b.place_recovery(TestMap.RECOVERY_B)
    t.eq(r_occ.reason, Placement.Reject.ENEMY_OCCUPIES_CELL, "refused: living enemy on the cell")
    t.eq(b.run.recovery_right, 1, "right kept after occupancy refusal")
    t.eq(b.preview_recovery(TestMap.RECOVERY_B), Placement.Reject.ENEMY_OCCUPIES_CELL, "preview agrees")
    b.sim.apply_blast(b.grid.cell_center(TestMap.RECOVERY_B.x, TestMap.RECOVERY_B.y), 5.0, 9999.0)
    t.check(b.sim.alive[occ] == 0, "occupant cleared")
    # Outer re-activation and outer new placement are refused.
    t.check(not b.set_active(H2, true), "re-activating an outer structure is refused")
    var outer_new: Placement.Result = b.place_structure(K_S, Vector2i(36, 20))
    t.eq(outer_new.reason, Placement.Reject.DISTRICT_LOST, "new outer placement refused after the collapse")
    # Success: same object, same id, counters and cooldown preserved, attached to B2.
    t.eq(b.preview_recovery(TestMap.RECOVERY_B), Placement.Reject.NONE, "preview says B is legal")
    var ok: Placement.Result = b.place_recovery(TestMap.RECOVERY_B)
    t.check(ok.ok, "recovery placement at B accepted")
    t.eq(ok.structure.id, H1, "same id")
    t.check(ok.structure == h1, "same object")
    t.eq(h1.shots_fired, shots_before, "shot counter preserved")
    t.eq(h1.cooldown_left, cd_at_collapse, "cooldown preserved across the detached period")
    t.eq(h1.attached_to, B2, "attached to B2")
    t.eq(h1.group_id, b.placement.get_structure(S4).group_id, "same group as S4")
    t.eq(b.run.recovery_right, 0, "right consumed")
    t.check(b.run.recovery_placed, "placed flag")
    t.eq(b.placement.detached.size(), 0, "nothing left waiting")
    t.eq(b.placement.structures.size(), 18, "18 structures on the map again")
    var again: Placement.Result = b.place_recovery(TestMap.RECOVERY_A)
    t.eq(again.reason, Placement.Reject.NO_RECOVERY_RIGHT, "second placement refused")
    t.eq(b.placement.count_of(K_H), 4, "no hwacha duplicated")
    t.eq(b.run.events_of("recovery_placed").size(), 1, "one recovery_placed event")


func _ac03_cooldown_freeze_vs_inactive(t: RefCounted) -> void:
    t.case("AC-03 detached H1 cooldown is frozen; an inactive outer hwacha keeps decrementing")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    b.force_outer_hp(1.0, "AC-03 verification")
    b.sim.force_spawn(SOUTH, OUTER_GOAL)
    b.step(_dt(b))
    t.eq(b.run.collapse_count, 1, "collapsed")
    var h1: Placement.Structure = b.placement.get_any(H1)
    var h2: Placement.Structure = b.placement.get_structure(H2)
    h1.cooldown_left = 0.5
    h2.cooldown_left = 0.5
    b.run_for(2.0)
    t.eq(h1.cooldown_left, 0.5, "detached H1: cooldown frozen at 0.5")
    t.eq(h2.cooldown_left, 0.0, "inactive H2: cooldown ran down (existing policy kept)")
    b.place_recovery(TestMap.RECOVERY_B)
    b.run_for(0.25)
    t.check(h1.cooldown_left < 0.5 and h1.cooldown_left > 0.2, "after placement the cooldown resumes (%.2f)" % h1.cooldown_left)


# ------------------------------------------------------------------------ F1 ---

func _f1_normal_defense(t: RefCounted) -> void:
    t.case("F1 normal defense (D-032 outer HP 360): 18 structures, 1140 enemies, no input -> WON without collapse")
    var b: Battle = _wp003()
    t.eq(b.run.outer_hp, 360.0, "F1 starts from the D-032 outer HP 360")
    var elapsed: float = _run_until_end(b, MAX_RUN_SECONDS)
    t.eq(b.run.run_name(), "WON", "run WON within %.0f s (ended at %.1f s)" % [MAX_RUN_SECONDS, elapsed])
    t.eq(b.run.collapse_count, 0, "no collapse")
    t.gt(b.run.outer_hp, 0.0, "outer HP > 0 (%.0f)" % b.run.outer_hp)
    t.eq(b.run.core_hp, 60.0, "core untouched")
    t.eq(b.sim.spawned_total, 1140, "all 1140 spawned")
    t.eq(b.sim.alive_count, 0, "no survivors")
    t.eq(b.sim.spawned_total, b.sim.killed_total + b.sim.leaked_total + b.sim.alive_count, "ledger: spawned = killed + arrived + alive")
    t.eq(b.run.forced_hp_writes, 0, "no forced HP writes")
    t.eq(b.waves.spawned_scheduled, 1140, "wave director spawned exactly the budget")
    t.note("F1: ended %.1f s, outer_hp %.0f, killed %d, arrived %d, peak alive %d" % [
        elapsed, b.run.outer_hp, b.sim.killed_total, b.sim.leaked_total, b.peak_alive])


# ------------------------------------------------------------------------ F2 ---

func _f2_forced_collapse_recovery_win(t: RefCounted) -> void:
    t.case("F2 real waves, forced collapse at 20 s, H1 -> B at collapse+5 s, WON")
    var b: Battle = _wp003()
    b.run_for(20.0)
    t.eq(b.run.collapse_count, 0, "no natural collapse before 20 s")
    b.force_outer_hp(1.0, "F2 forced collapse")
    b.spawn_extra(OUTER_GOAL, 1, "F2 trigger enemy")
    var dt: float = _dt(b)
    var ticks: int = 0
    while b.run.collapse_count == 0 and ticks < 300:
        b.step(dt)
        ticks += 1
    t.check(b.run.collapse_count == 1, "collapse through real arrival damage within %d ticks" % ticks)
    var collapse_tick: int = b.run.collapse_tick
    # +5 s (300 ticks after the collapse tick), same tick for every observation.
    while b.steps < collapse_tick + 300 and not b.run.ended():
        b.step(dt)
    t.gt(b.run.core_hp, 0.0, "core alive at collapse+5 s (%.0f)" % b.run.core_hp)
    t.eq(b.run.recovery_right, 1, "right available at +5 s")
    var res: Placement.Result = b.place_recovery(TestMap.RECOVERY_B)
    t.check(res.ok, "recovery placement at B succeeded at +5 s (%s)" % Placement.reject_name(res.reason))
    var h1: Placement.Structure = b.placement.get_any(H1)
    t.eq(h1.attached_to, B2, "H1 attached to B2")
    var elapsed: float = _run_until_end(b, MAX_RUN_SECONDS - b.sim_time)
    t.eq(b.run.run_name(), "WON", "run WON (ended at %.1f s)" % elapsed)
    t.eq(b.run.defense_name(), "INNER_ONLY", "won from INNER_ONLY")
    t.gt(b.run.core_hp, 0.0, "core survived (%.0f)" % b.run.core_hp)
    t.eq(b.sim.spawned_total, 1141, "1140 waves + 1 trigger enemy")
    t.eq(b.waves.spawned_extra, 1, "extra budget recorded")
    t.eq(b.sim.alive_count, 0, "no survivors")
    t.note("F2: collapse tick %d, placed tick %d, H1 shots after %d, core_hp %.0f, ended %.1f s" % [
        collapse_tick, b.run.recovery_placed_tick, h1.shots_fired, b.run.core_hp, elapsed])
    # +0 / +10 s observations (separate runs, same inputs), informational.
    for delay: int in [0, 600]:
        var o: Battle = _wp003()
        o.run_for(20.0)
        o.force_outer_hp(1.0, "F2 delay observation")
        o.spawn_extra(OUTER_GOAL, 1, "F2 trigger enemy")
        var k: int = 0
        while o.run.collapse_count == 0 and k < 300:
            o.step(dt)
            k += 1
        var ct: int = o.run.collapse_tick
        while o.steps < ct + delay and not o.run.ended():
            o.step(dt)
        var r: Placement.Result = o.place_recovery(TestMap.RECOVERY_B)
        t.note("F2 +%d ticks: core_hp %.0f, placement %s" % [delay, o.run.core_hp, "ok" if r.ok else Placement.reject_name(r.reason)])


# ------------------------------------------------------------------------ F3 ---

static func _f3_run(anchor: Vector2i, t: RefCounted, label: String) -> Dictionary:
    var cfg: Config = Config.for_wp003()
    cfg.values["enemy_speed_jitter"] = 0.0
    cfg.values["enemy_lane_offset"] = 0.0
    var b: Battle = Battle.new(cfg)
    b.waves.enabled = false            # finite test spawn list only
    t.check(b.set_active(H4, false), "%s: H4 deactivated for the controlled test" % label)
    b.force_outer_hp(1.0, "F3 forced collapse")
    b.spawn_extra(OUTER_GOAL, 1, "F3 trigger enemy")
    var dt: float = _dt(b)
    var k: int = 0
    while b.run.collapse_count == 0 and k < 300:
        b.step(dt)
        k += 1
    var ct: int = b.run.collapse_tick
    while b.steps < ct + 300:
        b.step(dt)
    var hash_before: String = b.state_hash()
    var state_before: String = b.full_state_json()   # R-06: complete structured state
    var res: Placement.Result = b.place_recovery(anchor)
    var h1: Placement.Structure = b.placement.get_any(H1)
    var shots0: int = h1.shots_fired
    var kills0: int = h1.kills
    var shared0: int = b.hwacha.shared_only_shots
    var core0: float = b.run.core_hp
    # Next tick: the 12 test enemies appear at (950,450) in the spawn phase.
    b.spawn_extra(TestMap.F3_SPAWN_POINT, TestMap.F3_SPAWN_COUNT, "F3 controlled group")
    b.step(dt)
    var first: Dictionary = {}
    var seen_by_s4: int = 0
    var s4_seen: Dictionary = b.network.sensor_seen.get(S4, {})
    for s: int in b.sim.live_slots():
        if s4_seen.has(b.sim.enemy_id(s)):
            seen_by_s4 += 1
    var out_local: PackedInt32Array = PackedInt32Array()
    var counts: PackedInt32Array = b.network.known_zone_counts(h1, b.density, b.sim, out_local)
    first = {"seen_by_s4": seen_by_s4, "h1_local": h1.known_local, "z9_known": counts[Z9], "z9_local": out_local[Z9]}
    for _i: int in range(int(30.0 / dt) - 1):
        b.step(dt)
    return {"ok": res.ok, "reason": Placement.reject_name(res.reason), "hash_before": hash_before,
        "state_before": state_before, "state_before_len": state_before.length(),
        "attached": h1.attached_to, "group": h1.group_id, "first": first,
        "shots": h1.shots_fired - shots0, "kills": h1.kills - kills0,
        "shared_only": b.hwacha.shared_only_shots - shared0, "core_damage": core0 - b.run.core_hp,
        "core_hp": b.run.core_hp, "run": b.run.run_name(), "alive": b.sim.alive_count}


func _f3_ab_comparison(t: RefCounted) -> void:
    t.case("F3 controlled A/B: connection alone changes shared fire, kills and core damage")
    var a: Dictionary = _f3_run(TestMap.RECOVERY_A, t, "A")
    var bb: Dictionary = _f3_run(TestMap.RECOVERY_B, t, "B")
    t.eq(a["hash_before"], bb["hash_before"], "state hash identical right before the placement (same snapshot)")
    t.check(a["state_before"] == bb["state_before"], "R-06: COMPLETE structured state identical before the placement (%d chars: every enemy id/pos/hp, structures, network, waves, rng)" % int(a["state_before_len"]))
    var parsed: Variant = JSON.parse_string(a["state_before"])
    t.check(parsed is Dictionary and (parsed as Dictionary)["enemies"].size() == 0 and (parsed as Dictionary)["detached"].size() == 1, "R-06: the shared state has no enemy on the field and H1 waiting")
    t.check(a["ok"] and bb["ok"], "both placements succeeded (A %s, B %s)" % [a["reason"], bb["reason"]])
    t.eq(a["attached"], -1, "A is not attached to any bongsu")
    t.eq(bb["attached"], B2, "B is attached to B2")
    t.eq(a["first"]["seen_by_s4"], 12, "A run: S4 sees all 12 on the first detection")
    t.eq(bb["first"]["seen_by_s4"], 12, "B run: S4 sees all 12 on the first detection")
    t.eq(a["first"]["h1_local"], 0, "A: the 12 are outside H1's local radius")
    t.eq(bb["first"]["h1_local"], 0, "B: the 12 are outside H1's local radius")
    t.eq(bb["first"]["z9_known"], 12, "B knows Z9 density 12 through the network")
    t.eq(a["first"]["z9_known"], 0, "A knows Z9 density 0")
    t.eq(a["shared_only"], 0, "A: zero shared-only volleys")
    t.ge(float(bb["shared_only"]), 1.0, "B: at least one shared-only volley (%d)" % bb["shared_only"])
    t.ge(float(bb["kills"] - a["kills"]), 6.0, "kills B - A >= 6 (%d - %d)" % [bb["kills"], a["kills"]])
    t.ge(a["core_damage"] - bb["core_damage"], 6.0, "core damage A - B >= 6 (%.0f - %.0f)" % [a["core_damage"], bb["core_damage"]])
    t.gt(bb["core_hp"], 0.0, "B core survives (%.0f)" % bb["core_hp"])
    t.note("F3 A: shots %d kills %d shared %d core dmg %.0f | B: shots %d kills %d shared %d core dmg %.0f" % [
        a["shots"], a["kills"], a["shared_only"], a["core_damage"], bb["shots"], bb["kills"], bb["shared_only"], bb["core_damage"]])


# ------------------------------------------------------------------------ F4 ---

func _f4_lose_stop_restart(t: RefCounted) -> void:
    t.case("F4 lose priority, frozen after the end, refused commands, restart resets everything")
    var b: Battle = _wp003()
    b.spawning_enabled = false
    b.waves.configure([], 5.0, 3)      # nothing scheduled -> WON is possible as soon as alive == 0
    t.check(b.waves.scheduled_complete(), "empty schedule counts as complete")
    # The "last enemy" already stands at the core while the outer is still the
    # target (it is not consumed there), so the collapse tick ends with alive 1.
    b.sim.force_spawn(SOUTH, CORE_GOAL)
    b.force_outer_hp(1.0, "F4")
    b.sim.force_spawn(SOUTH, OUTER_GOAL)
    b.step(_dt(b))
    t.eq(b.run.collapse_count, 1, "collapsed")
    t.eq(b.run.run_name(), "RUNNING", "still running: one enemy alive")
    b.force_core_hp(1.0, "F4 last-arrival lose")
    b.step(_dt(b))
    t.eq(b.sim.alive_count, 0, "last enemy consumed -> alive 0")
    t.eq(b.run.core_hp, 0.0, "core HP 0 in the same tick")
    t.eq(b.run.run_name(), "LOST", "LOST wins over WON when both conditions hit in one tick")
    var run_id: int = b.run.run_id
    var frozen: String = b.state_hash()
    var frozen_full: String = b.full_state_json()
    var steps_at_end: int = b.steps
    b.run_for(2.0)
    t.eq(b.state_hash(), frozen, "state unchanged for 120 ticks after the end")
    t.check(b.full_state_json() == frozen_full, "R-06: complete structured state unchanged for 120 ticks after the end")
    t.eq(b.steps, steps_at_end, "no tick advanced after the end")
    t.eq(b.place_recovery(TestMap.RECOVERY_B).reason, Placement.Reject.RUN_ENDED, "recovery refused after the end")
    t.eq(b.place_structure(K_S, Vector2i(44, 8)).reason, Placement.Reject.RUN_ENDED, "placement refused after the end")
    t.eq(b.remove_structure(S4).reason, Placement.Reject.RUN_ENDED, "removal refused after the end")
    t.check(not b.set_active(H2, true), "activation refused after the end")
    # Restart: everything back, new run id.
    b.restart()
    t.eq(b.run.run_id, run_id + 1, "run_id advanced")
    t.eq(b.run.run_name(), "RUNNING", "running again")
    t.eq(b.run.defense_name(), "OUTER_ACTIVE", "outer active again")
    t.eq(b.run.outer_hp, 360.0, "outer HP restored to 360 (D-032)")
    t.eq(b.run.outer_hp_max, 360.0, "outer HP max restored to 360")
    t.eq(b.run.core_hp, 60.0, "core HP restored")
    t.eq(b.placement.structures.size(), 18, "18 structures restored")
    t.eq(b.placement.detached.size(), 0, "no detached structure")
    t.eq(b.run.recovery_right, 0, "no recovery right")
    t.eq(b.sim.alive_count, 0, "no enemies")
    t.eq(b.sim.spawned_total, 0, "spawn counters reset")
    t.eq(b.waves.total_budget(), 1140, "wave table restored")
    t.eq(b.path.goal_cell, TestMap.OUTER_GOAL_CELL, "goal back on the outer stronghold")
    t.eq(b.run.events.size(), 1, "event log cleared (only run_start)")
    var all_active: bool = true
    for id: int in b.placement.structures:
        if not (b.placement.structures[id] as Placement.Structure).active:
            all_active = false
    t.check(all_active, "all structures active again")
    # WON then restart, and determinism after restart.
    var w: Battle = _wp003()
    w.spawning_enabled = false
    w.waves.configure([], 5.0, 3)
    w.step(_dt(w))
    t.eq(w.run.run_name(), "WON", "empty schedule + no enemies + core alive -> WON")
    var fw: String = w.state_hash()
    w.run_for(2.0)
    t.eq(w.state_hash(), fw, "WON state frozen for 120 ticks")
    w.restart()
    var r1: Battle = _wp003()
    r1.run_for(10.0)
    var r2: Battle = _wp003()
    r2.restart()
    r2.run_for(10.0)
    t.ne(r1.run.run_id, r2.run.run_id, "run ids differ")
    t.eq(r1.state_hash(), r2.state_hash(), "restarted run reproduces the fresh run (state hash excludes run_id)")
    t.check(r1.full_state_json() == r2.full_state_json(), "R-06: restarted run reproduces the fresh run in the COMPLETE structured state (run_id excluded)")
    var fresh_state: Dictionary = r1.full_state()
    t.check((fresh_state["enemies"] as Array).size() == r1.sim.alive_count and (fresh_state["structures"] as Array).size() == 18, "full_state lists every living enemy and all 18 structures")
