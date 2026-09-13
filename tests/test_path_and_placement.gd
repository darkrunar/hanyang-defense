extends RefCounted
## AC-02 / AC-03: rerouting, restoration, and the rejection rules.

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const TerrainGrid := preload("res://game/core/terrain_grid.gd")

const SOUTH: int = 0
const WEST: int = 1
const EAST: int = 2

const Z_SOUTH_WEST_LANE: int = 0
const Z_SOUTH_EAST_LANE: int = 1


static func _fresh(combat: bool = false, seed_value: int = 20260913) -> Battle:
    var cfg: Config = Config.new()
    cfg.values["combat_enabled"] = combat
    cfg.values["seed"] = seed_value
    return Battle.new(cfg)


func run(t: RefCounted) -> void:
    _ac02_reroute_and_restore(t)
    _ac03_reject_full_block(t)
    _ac03_reject_enemy_occupied(t)
    _ac03_occupancy_tracks_movement(t)
    _ac03_saturated_lane_refuses_placement(t)
    _ac03_reject_terrain_and_overlap(t)
    _stranded_enemy_recovers(t)


# --------------------------------------------------------------------- AC-02 ---

func _ac02_reroute_and_restore(t: RefCounted) -> void:
    t.case("AC-02 jangseung reroutes traffic and removal restores it")
    var west_anchor: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_west_lane"]

    # Reference run, same seed, no structure: both south lanes carry traffic.
    var ref_run: Battle = _fresh()
    ref_run.run_for(35.0)
    var ref_counts: PackedInt32Array = ref_run.density.evaluate(ref_run.sim)
    var ref_west: int = ref_counts[Z_SOUTH_WEST_LANE]
    var ref_east: int = ref_counts[Z_SOUTH_EAST_LANE]
    var ref_leaks: int = ref_run.sim.route_leaked[SOUTH]
    t.gt(float(ref_west), 0.0, "reference run: west lane carries traffic")
    t.gt(float(ref_east), 0.0, "reference run: east lane carries traffic")

    # Same seed, jangseung plugging the west lane. The lane is 2 cells wide and
    # the footprint is 2x2, so a single structure closes it completely.
    var b: Battle = _fresh()
    var base_version: int = b.path.path_version
    var res: Placement.Result = b.place_jangseung(west_anchor)
    t.check(res.ok, "placing a jangseung in the south-west lane is accepted")
    if not res.ok:
        t.note("refused: %s" % Placement.reject_name(res.reason))
        return
    t.eq(b.path.path_version, base_version + 1, "accepted placement bumps path_version")

    var blocked_cell: int = b.grid.idx(west_anchor.x, west_anchor.y)
    t.check(not b.path.is_reachable_index(blocked_cell), "blocked cell is impassable")
    t.check(b.path.route_reachable(SOUTH), "south route still reaches the goal")

    b.run_for(35.0)
    var after: PackedInt32Array = b.density.evaluate(b.sim)
    t.eq(after[Z_SOUTH_WEST_LANE], 0, "blocked west lane holds no enemies")
    t.gt(float(after[Z_SOUTH_EAST_LANE]), float(ref_east),
        "east lane absorbs the diverted flow (detour observed)")
    t.gt(float(b.sim.route_leaked[SOUTH]), 0.0,
        "south route still reaches the objective by the detour")
    t.note("t=35s west lane: reference=%d blocked=%d | east lane: reference=%d blocked=%d" % [
        ref_west, after[Z_SOUTH_WEST_LANE], ref_east, after[Z_SOUTH_EAST_LANE]
    ])
    t.note("south-route objective arrivals at t=35s: reference=%d detoured=%d" % [
        ref_leaks, b.sim.route_leaked[SOUTH]
    ])

    # Removal restores traffic. Removal has no occupancy rule, so it always works.
    var version_before_remove: int = b.path.path_version
    var rem: Placement.Result = b.placement.remove(res.structure.id)
    t.check(rem.ok, "jangseung removal succeeds")
    t.eq(b.path.path_version, version_before_remove + 1, "removal bumps path_version")
    t.check(b.path.is_reachable_index(blocked_cell), "removed cell is passable again")

    b.run_for(25.0)
    var restored: PackedInt32Array = b.density.evaluate(b.sim)
    t.gt(float(restored[Z_SOUTH_WEST_LANE]), 0.0,
        "west lane carries traffic again after removal")
    t.note("after removal west lane=%d east lane=%d" % [
        restored[Z_SOUTH_WEST_LANE], restored[Z_SOUTH_EAST_LANE]
    ])


# --------------------------------------------------------------------- AC-03 ---

func _ac03_reject_full_block(t: RefCounted) -> void:
    t.case("AC-03 a placement that would seal a route is refused, state intact")
    var b: Battle = _fresh()
    # Keep the field empty so the refusal can only come from the path rule.
    b.spawning_enabled = false

    var north: Vector2i = TestMap.AC_SCENARIO_ANCHORS["west_north_lane"]
    var south: Vector2i = TestMap.AC_SCENARIO_ANCHORS["west_south_lane"]

    var first: Placement.Result = b.place_jangseung(north)
    t.check(first.ok, "first jangseung plugs the west-north lane")
    t.check(b.path.route_reachable(WEST), "west route still connected via the south lane")

    var version_before: int = b.path.path_version
    var structures_before: int = b.placement.structures.size()
    var dist_before: PackedInt32Array = b.path.dist.duplicate()
    var flow_before: PackedInt32Array = b.path.flow.duplicate()

    var second: Placement.Result = b.place_jangseung(south)
    t.check(not second.ok, "second jangseung sealing the last west lane is refused")
    t.eq(second.reason, Placement.Reject.WOULD_BLOCK_ALL_PATHS, "rejection reason")

    t.eq(b.path.path_version, version_before, "refused placement does not bump path_version")
    t.eq(b.placement.structures.size(), structures_before, "refused placement adds no structure")
    t.check(b.path.dist == dist_before, "distance field unchanged after refusal")
    t.check(b.path.flow == flow_before, "flow field unchanged after refusal")
    var clear: bool = true
    for ci: int in b.placement.footprint_cells(south):
        if b.grid.structure_at_i(ci) != -1:
            clear = false
    t.check(clear, "every refused footprint cell is left clear")
    t.check(b.path.route_reachable(WEST), "west route is still reachable after the refusal")

    # The remaining legal lane keeps working.
    b.spawning_enabled = true
    b.run_for(30.0)
    t.gt(float(b.sim.route_alive[WEST]), 0.0, "west route keeps producing traffic")
    t.gt(float(b.sim.route_leaked[WEST]), 0.0, "west route still reaches the objective")


func _ac03_reject_enemy_occupied(t: RefCounted) -> void:
    t.case("AC-03 a cell occupied by a living enemy refuses a structure")
    var b: Battle = _fresh()
    b.spawning_enabled = false

    var anchor: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_east_lane"]
    var cells: PackedInt32Array = b.placement.footprint_cells(anchor)
    var target_cell: int = cells[0]
    var world: Vector2 = b.grid.index_center(target_cell)
    var slot: int = b.sim.force_spawn(SOUTH, world)
    t.check(slot >= 0, "test enemy placed inside the footprint")

    var version_before: int = b.path.path_version
    var structures_before: int = b.placement.structures.size()

    var res: Placement.Result = b.place_jangseung(anchor)
    t.check(not res.ok, "placement onto the occupied cell is refused")
    t.eq(res.reason, Placement.Reject.ENEMY_OCCUPIES_CELL, "rejection reason")
    t.eq(res.blocked_cell, target_cell, "refusal names the occupied cell")
    t.eq(b.path.path_version, version_before, "refusal does not bump path_version")
    t.eq(b.placement.structures.size(), structures_before, "refusal adds no structure")

    # Clear the occupant, then the same placement must succeed.
    var kills: int = b.sim.apply_blast(world, 10.0, 9999.0)
    t.eq(kills, 1, "occupant removed")
    var res2: Placement.Result = b.place_jangseung(anchor)
    t.check(res2.ok, "the same placement is accepted once the cell is clear")
    t.eq(b.path.path_version, version_before + 1, "accepted placement bumps path_version")


## GPT review R-01 regression: the occupancy answer must follow the position an
## enemy has at the END of the tick, on both the entering and the leaving edge.
func _ac03_occupancy_tracks_movement(t: RefCounted) -> void:
    t.case("AC-03 occupancy follows movement (R-01 regression, both edges)")
    var anchor: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_west_lane"]  # (44,36)
    var dt: float = Config.new().get_num("fixed_dt")

    # --- exact GPT reproduction: enemy just below the footprint steps into it ---
    var b: Battle = _fresh()
    b.spawning_enabled = false
    var slot: int = b.sim.force_spawn(SOUTH, Vector2(890.0, 760.1))
    b.step(dt)
    var now_cell: int = b.grid.world_to_index(Vector2(b.sim.pos_x[slot], b.sim.pos_y[slot]))
    var footprint: PackedInt32Array = b.placement.footprint_cells(anchor)
    t.check(footprint.has(now_cell), "after one tick the enemy stands inside the footprint (cell %d)" % now_cell)
    t.eq(b.sim.cell[slot], now_cell, "cached cell matches the post-move position")
    var version_before: int = b.path.path_version
    var structures_before: int = b.placement.structures.size()
    var res: Placement.Result = b.place_jangseung(anchor)
    t.check(not res.ok, "placement onto the just-entered cell is refused")
    t.eq(res.reason, Placement.Reject.ENEMY_OCCUPIES_CELL, "rejection reason")
    t.eq(b.path.path_version, version_before, "path_version unchanged by the refusal")
    t.eq(b.placement.structures.size(), structures_before, "no structure added by the refusal")
    t.check(b.path.is_reachable_index(footprint[0]), "footprint cells stay passable")

    # --- entering edge: a sub-pixel outside, one tick, then inside ---
    var b2: Battle = _fresh()
    b2.spawning_enabled = false
    var s2: int = b2.sim.force_spawn(SOUTH, Vector2(900.0, 760.05))
    b2.sim.speed[s2] = 30.0   # ~0.5 px per tick, so the crossing is a single tick
    var before: Placement.Result = b2.place_jangseung(anchor)
    t.check(before.ok, "enemy still outside: placement accepted")
    b2.placement.remove(before.structure.id)
    b2.step(dt)
    t.check(b2.sim.pos_y[s2] < 760.0, "enemy crossed the footprint edge this tick (y=%.3f)" % b2.sim.pos_y[s2])
    var after: Placement.Result = b2.place_jangseung(anchor)
    t.check(not after.ok and after.reason == Placement.Reject.ENEMY_OCCUPIES_CELL,
        "entering edge: refused on the very tick the enemy crosses in")

    # --- leaving edge: inside at the top edge, one tick north, then outside ---
    var b3: Battle = _fresh()
    b3.spawning_enabled = false
    var s3: int = b3.sim.force_spawn(SOUTH, Vector2(900.0, 720.2))  # inside, 0.2 px below the top edge
    b3.sim.speed[s3] = 30.0
    var inside: Placement.Result = b3.place_jangseung(anchor)
    t.check(not inside.ok and inside.reason == Placement.Reject.ENEMY_OCCUPIES_CELL,
        "leaving edge: refused while the enemy is still inside")
    b3.step(dt)
    t.check(b3.sim.pos_y[s3] < 720.0, "enemy left the footprint this tick (y=%.3f)" % b3.sim.pos_y[s3])
    var freed: Placement.Result = b3.place_jangseung(anchor)
    t.check(freed.ok, "leaving edge: accepted on the very tick the enemy steps out")
    t.eq(b3.path.path_version, 3, "accepted placement bumps path_version")

    # --- overlay/cursor and placement must agree, on a saturated field ---
    var b4: Battle = _fresh(true)
    b4.run_for(20.0)
    var disagreements: int = 0
    var checks: int = 0
    for y: int in range(31, 43):
        for lane_x: int in [44, 48]:
            var a: Vector2i = Vector2i(lane_x, y)
            var cells: PackedInt32Array = b4.placement.footprint_cells(a)
            var any_occupied: bool = false
            for ci: int in cells:
                if b4.sim.is_cell_occupied(ci):
                    any_occupied = true
            var r: Placement.Result = b4.place_jangseung(a)
            checks += 1
            if r.ok == any_occupied:
                disagreements += 1
            if r.ok:
                b4.placement.remove(r.structure.id)
    t.eq(disagreements, 0, "cursor-side occupancy and placement agree on all %d anchors" % checks)


func _ac03_saturated_lane_refuses_placement(t: RefCounted) -> void:
    t.case("AC-03 the occupancy rule under saturation (measured, known limitation)")
    var b: Battle = _fresh(true)
    b.run_for(30.0)
    t.ge(float(b.sim.alive_count), 1000.0, "field saturated before probing")

    var dt: float = b.config.get_num("fixed_dt")
    var attempts: int = 0
    var accepted: int = 0
    var occupied_refusals: int = 0
    var other_refusals: int = 0
    # Sweep every legal 2x2 anchor down both south lanes, 30 times over 3 s.
    for tick: int in range(30):
        for _i: int in range(6):
            b.step(dt)
        for lane_x: int in [44, 48]:
            for y: int in range(31, 43):
                var res: Placement.Result = b.placement.try_place(
                    Placement.Kind.JANGSEUNG, Vector2i(lane_x, y), b.sim, "probe"
                )
                attempts += 1
                if res.ok:
                    accepted += 1
                    b.placement.remove(res.structure.id)
                elif res.reason == Placement.Reject.ENEMY_OCCUPIES_CELL:
                    occupied_refusals += 1
                else:
                    other_refusals += 1

    t.eq(occupied_refusals + accepted, attempts,
        "every south-lane attempt is either accepted or refused for occupancy")
    t.eq(other_refusals, 0, "no other refusal reason appears on open lane cells")
    var rate: float = 100.0 * float(accepted) / float(attempts)
    # Measurement, not a guarantee (GPT review: do not quote a fixed rate).
    t.note("saturated south lanes: %d/%d anchors legal (%.2f%%) - measured, see P-007" % [
        accepted, attempts, rate
    ])
    t.eq(b.placement.count_of(Placement.Kind.JANGSEUNG), 0,
        "every probe structure was removed again, state left clean")


func _ac03_reject_terrain_and_overlap(t: RefCounted) -> void:
    t.case("AC-03 terrain, bounds and overlap refusals")
    var b: Battle = _fresh()
    b.spawning_enabled = false

    var wall_anchor: Vector2i = Vector2i(46, 36)  # the solid block between south lanes
    var r1: Placement.Result = b.place_jangseung(wall_anchor)
    t.check(not r1.ok, "placement on static terrain is refused")
    t.eq(r1.reason, Placement.Reject.TERRAIN_BLOCKED, "rejection reason")

    var oob: Placement.Result = b.place_jangseung(Vector2i(TestMap.WIDTH - 1, 10))
    t.check(not oob.ok, "placement crossing the grid edge is refused")
    t.eq(oob.reason, Placement.Reject.OUT_OF_BOUNDS, "rejection reason")

    var open_anchor: Vector2i = Vector2i(36, 20)  # open plaza ground
    var ok1: Placement.Result = b.place_jangseung(open_anchor)
    t.check(ok1.ok, "first structure on open ground accepted")
    var overlap: Placement.Result = b.place_jangseung(open_anchor)
    t.check(not overlap.ok, "overlapping structure is refused")
    t.eq(overlap.reason, Placement.Reject.STRUCTURE_OVERLAP, "rejection reason")

    # A hwacha never blocks traffic, so it can never be refused for pathing.
    var gun: Placement.Result = b.place_hwacha(Vector2i(40, 20))
    t.check(gun.ok, "hwacha placed on open ground")
    t.check(b.path.route_reachable(SOUTH) and b.path.route_reachable(WEST)
        and b.path.route_reachable(EAST), "all routes still reachable with a hwacha down")

    t.eq(b.placement.count_of(Placement.Kind.JANGSEUNG), 1,
        "exactly one jangseung survived the refusals")


func _stranded_enemy_recovers(t: RefCounted) -> void:
    t.case("an enemy standing on a cell that becomes impassable still moves")
    var b: Battle = _fresh()
    b.spawning_enabled = false
    var anchor: Vector2i = TestMap.AC_SCENARIO_ANCHORS["south_west_lane"]
    var cells: PackedInt32Array = b.placement.footprint_cells(anchor)

    # Place first, then teleport an enemy on top of the blocked cell.
    var res: Placement.Result = b.place_jangseung(anchor)
    t.check(res.ok, "jangseung placed")
    var world: Vector2 = b.grid.index_center(cells[0])
    var slot: int = b.sim.force_spawn(SOUTH, world)
    t.check(slot >= 0, "enemy teleported onto the blocked cell")
    var start: Vector2 = Vector2(b.sim.pos_x[slot], b.sim.pos_y[slot])
    b.run_for(2.0)
    var moved: float = Vector2(b.sim.pos_x[slot], b.sim.pos_y[slot]).distance_to(start)
    t.gt(moved, 5.0, "stranded enemy escapes instead of freezing (moved %.1f px)" % moved)
