extends RefCounted
## Battle orchestrator: owns the map, path field, enemies, zones, structures,
## the bongsu network, the hwachas and — in WP-003 "waves" mode — the run /
## defence-line state and the finite wave director. Advances on a fixed step.
##
## Nothing here touches the SceneTree; the headless tests drive `step()`.
##
## WP-003 tick order (backlog/WP-003.md §2, D-023): commands (already applied
## synchronously) -> spawn -> move -> densities / network / detection ->
## fire (or evaluate-only) -> arrivals of survivors, stronghold damage ->
## collapse if the outer HP hit 0 (once) -> win / lose -> benchmark top-up.
## WP-001/002 "sandbox" mode keeps the original tick (immediate arrivals).

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const Placement := preload("res://game/core/placement.gd")
const Hwacha := preload("res://game/core/hwacha.gd")
const BongsuNetwork := preload("res://game/core/bongsu_network.gd")
const RunState := preload("res://game/core/run_state.gd")
const WaveDirector := preload("res://game/core/wave_director.gd")
const Config := preload("res://game/core/config.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

var config: Config = null
var grid: TerrainGrid = null
var path: PathNetwork = null
var sim: EnemySim = null
var density: DensityDetector = null
var placement: Placement = null
var hwacha: Hwacha = null
var network: BongsuNetwork = null
var run: RunState = null
var waves: WaveDirector = null

var sim_time: float = 0.0
var steps: int = 0
var combat_enabled: bool = true
var spawning_enabled: bool = true
var benchmark_hold_alive: bool = false
## "wp002" (local + shared detection) or "wp001" (global densities).
var targeting_mode: String = "wp002"
## "sandbox" (WP-001/002) or "waves" (WP-003).
var run_mode: String = "sandbox"
var arrival_mode: String = "immediate"
var district_rules: bool = false
var _network_dirty: bool = true
## Target at the start of the current tick (arrivals are attributed to it).
var _tick_target_core: bool = false

## Peak concurrent living enemies, i.e. the number AC-01 is about.
var peak_alive: int = 0
var peak_route_alive: PackedInt32Array = PackedInt32Array()
## Structure-command bookkeeping for the evidence logs.
var commands_accepted: int = 0
var commands_rejected: int = 0
var activation_changes: int = 0


func _init(cfg: Config = null) -> void:
    config = cfg if cfg != null else Config.new()
    grid = TestMap.build_grid()
    path = TestMap.build_path(grid)
    density = TestMap.build_zones(config.get_str("zone_set"))
    placement = Placement.new(grid, path)
    hwacha = Hwacha.new()
    network = BongsuNetwork.new()
    run = RunState.new()
    waves = WaveDirector.new()
    sim = EnemySim.new(grid, path, config.get_int("enemy_capacity"))
    peak_route_alive.resize(path.route_ids.size())
    reset(true)


## Full reset: structures, network, enemies, run state, counters; then the
## configured fixture. `restart()` is the player-facing variant (new run_id).
func reset(keep_run_id: bool = true) -> void:
    grid.clear_structures()
    placement.reset()
    hwacha.reset()
    network.reset()
    _apply_tuning()
    run_mode = config.get_str("run_mode")
    arrival_mode = config.get_str("arrival_mode")
    district_rules = config.get_bool("district_rules")
    targeting_mode = config.get_str("targeting_mode")
    sim.arrival_mode = arrival_mode
    placement.district_fn = Callable(TestMap, "district_of_cell") if district_rules else Callable()
    placement.locked_district = -1
    # WP-003 starts on the outer stronghold; sandbox keeps the core as the goal.
    if run_mode == "waves":
        path.set_goal(TestMap.OUTER_GOAL_CELL.x, TestMap.OUTER_GOAL_CELL.y)
    else:
        path.set_goal(TestMap.GOAL_CELL.x, TestMap.GOAL_CELL.y)
    # path_version is bookkeeping: rebase it so a restarted run reproduces a
    # fresh one exactly (fresh: build_path=1, this rebuild=2 — unchanged for
    # the WP-001/002 evidence that quotes absolute values).
    path.path_version = 1
    path.rebuild()
    sim.reset(config.get_int("seed"))
    run.reset(config.get_num("outer_hp"), config.get_num("core_hp"), config.get_num("arrival_damage"), keep_run_id)
    run.core_invulnerable = config.get_bool("benchmark_core_invulnerable")
    waves.configure(TestMap.WAVES, config.get_num("wave_gap_seconds"), path.route_ids.size())
    waves.enabled = run_mode == "waves"
    combat_enabled = config.get_bool("combat_enabled")
    benchmark_hold_alive = config.get_bool("benchmark_hold_alive")
    spawning_enabled = true
    sim_time = 0.0
    steps = 0
    peak_alive = 0
    peak_route_alive.fill(0)
    commands_accepted = 0
    commands_rejected = 0
    activation_changes = 0
    _place_fixture(config.get_str("fixture"))
    _network_dirty = true
    refresh_network()
    density.evaluate(sim)
    network.detect(placement, sim)
    run.log_event(steps, sim_time, "run_start", {"fixture": config.get_str("fixture"), "run_mode": run_mode,
        "structures": placement.structures.size(), "outer_hp": run.outer_hp, "core_hp": run.core_hp,
        "goal": [path.goal_cell.x, path.goal_cell.y], "path_version": path.path_version})


## Player-facing restart: everything back to the initial data, new run_id so
## stale commands from the previous run can be recognised and refused.
func restart() -> void:
    reset(false)


func _apply_tuning() -> void:
    sim.base_speed = config.get_num("enemy_speed")
    sim.speed_jitter = config.get_num("enemy_speed_jitter")
    sim.lane_offset = config.get_num("enemy_lane_offset")
    sim.max_hp = config.get_num("enemy_hp")
    sim.goal_radius = config.get_num("goal_radius")
    network.link_range = config.get_num("bongsu_link_range")


func _place_fixture(name: String) -> void:
    match name:
        "wp001":
            for h: Array in TestMap.HWACHAS:
                _place_or_error(Placement.Kind.HWACHA, Vector2i(h[1], h[2]), h[0])
        "b", "c":
            var first_hwacha_id: int = -1
            for h: Array in TestMap.HWACHAS:
                var res: Placement.Result = _place_or_error(Placement.Kind.HWACHA, Vector2i(h[1], h[2]), h[0])
                if first_hwacha_id < 0 and res != null and res.ok:
                    first_hwacha_id = res.structure.id   # H1 중영: the recovery target (D-020)
            for b: Array in TestMap.FIXTURE_B_BONGSU:
                _place_or_error(Placement.Kind.BONGSU, Vector2i(b[1], b[2]), b[0])
            for s: Array in TestMap.FIXTURE_B_SENSORS:
                _place_or_error(Placement.Kind.SENSOR, Vector2i(s[1], s[2]), s[0])
            if name == "c":
                for j: Array in TestMap.FIXTURE_C_JANGSEUNG:
                    _place_or_error(Placement.Kind.JANGSEUNG, Vector2i(j[1], j[2]), j[0])
                run.recovery_target_id = first_hwacha_id
        "none":
            pass
        _:
            push_error("unknown fixture '%s'" % name)


func _place_or_error(kind: int, anchor: Vector2i, label: String) -> Placement.Result:
    var res: Placement.Result = place_structure(kind, anchor, label)
    if not res.ok:
        push_error("fixture %s '%s' at %s rejected: %s" % [
            Placement.kind_name(kind), label, str(anchor), Placement.reject_name(res.reason)
        ])
    return res


# ---------------------------------------------------------------- simulation ---

## One fixed simulation step. After WON / LOST nothing advances.
func step(dt: float) -> void:
    if run.ended():
        return
    _tick_target_core = run.defense == RunState.Defense.INNER_ONLY
    if spawning_enabled:
        if run_mode == "waves":
            waves.step(dt, steps, sim)
        else:
            sim.maintain(config.get_int("target_alive"), config.get_num("spawn_rate"), dt)
    sim.step_movement(dt)
    var counts: PackedInt32Array = density.evaluate(sim)
    refresh_network()
    network.detect(placement, sim)
    if combat_enabled:
        if targeting_mode == "wp001":
            hwacha.step(dt, placement, density, counts, sim, null, sim_time)
        else:
            hwacha.step(dt, placement, density, counts, sim, network, sim_time)
    else:
        hwacha.evaluate_only(dt, placement, density, counts, sim,
            null if targeting_mode == "wp001" else network)
    if arrival_mode == "after_fire":
        _process_arrivals()
    if run_mode == "waves":
        _update_run_end()
    if benchmark_hold_alive and spawning_enabled and not run.ended():
        # Benchmark supplement (R-02): top the field back up to the target at
        # the END of the tick, so a frame sampled between ticks always sees the
        # full concurrent load even right after a volley or a wave of arrivals.
        var deficit: int = config.get_int("target_alive") - sim.alive_count
        if deficit > 0:
            sim.spawn_round_robin(deficit)
    sim_time += dt
    steps += 1
    if sim.alive_count > peak_alive:
        peak_alive = sim.alive_count
    for r: int in range(peak_route_alive.size()):
        if sim.route_alive[r] > peak_route_alive[r]:
            peak_route_alive[r] = sim.route_alive[r]
    if run.ended():
        run.end_tick = steps
        run.end_sim_time = sim_time


## Survivors on the doorstep are consumed once and damage the tick-start target.
func _process_arrivals() -> void:
    var ids: PackedInt64Array = sim.collect_arrivals()
    if ids.is_empty():
        return
    var n: int = ids.size()
    if _tick_target_core:
        var dealt: float = run.damage_core(n)
        run.log_event(steps, sim_time, "core_damage", {"arrivals": n, "dealt": dealt, "core_hp": run.core_hp,
            "absorbed": run.core_invulnerable})
    else:
        var dealt: float = run.damage_outer(n)
        run.log_event(steps, sim_time, "outer_damage", {"arrivals": n, "dealt": dealt, "outer_hp": run.outer_hp})
        if run.outer_hp <= 0.0 and run.collapse_count == 0:
            _collapse()


## The collapse: exactly once, all in this tick, before the next decision.
func _collapse() -> void:
    run.collapse_count = 1
    run.collapse_tick = steps
    run.collapse_sim_time = sim_time
    run.defense = RunState.Defense.INNER_ONLY
    run.log_event(steps, sim_time, "collapse", {"outer_hp": run.outer_hp, "alive": sim.alive_count})

    # 1. Recovery right + detach H1 (same object, cooldown frozen while detached).
    var target: Placement.Structure = placement.get_structure(run.recovery_target_id)
    if target != null and placement.detach(target.id):
        run.recovery_right = 1
        run.log_event(steps, sim_time, "recovery_created", {"hwacha_id": target.id, "label": target.label,
            "cooldown_left": target.cooldown_left, "shots": target.shots_fired, "kills": target.kills})
    else:
        run.log_event(steps, sim_time, "recovery_failed", {"hwacha_id": run.recovery_target_id})

    # 2. Every other OUTER structure loses its function, keeps its footprint
    #    (jangseung keep blocking: D-023 / P-013).
    var deactivated: Array = []
    for id: int in placement.structures:
        var s: Placement.Structure = placement.structures[id]
        if s.district == TestMap.DISTRICT_OUTER and s.active:
            s.active = false
            deactivated.append(id)
    activation_changes += deactivated.size()
    placement.locked_district = TestMap.DISTRICT_OUTER
    run.log_event(steps, sim_time, "outer_deactivated_batch", {"count": deactivated.size(), "ids": deactivated})

    # 3. Target -> core, one path rebuild (path_version + 1). Enemies keep
    #    their positions and simply follow the new field from the next tick.
    var pv_before: int = path.path_version
    path.set_goal(TestMap.CORE_GOAL_CELL.x, TestMap.CORE_GOAL_CELL.y)
    path.rebuild()
    run.log_event(steps, sim_time, "target_changed", {"goal": [path.goal_cell.x, path.goal_cell.y],
        "path_version_before": pv_before, "path_version_after": path.path_version})

    # 4. Network: outer sources are gone from the next decision on.
    _network_dirty = true
    refresh_network()
    network.detect(placement, sim)


func _update_run_end() -> void:
    if run.core_hp <= 0.0:
        run.run = RunState.Run.LOST
        run.log_event(steps, sim_time, "run_lost", {"core_hp": run.core_hp, "alive": sim.alive_count})
        return
    if waves.scheduled_complete() and sim.alive_count == 0:
        run.run = RunState.Run.WON
        run.log_event(steps, sim_time, "run_won", {"outer_hp": run.outer_hp, "core_hp": run.core_hp,
            "collapse_count": run.collapse_count, "spawned": sim.spawned_total})


## Advance `seconds` of simulated time at the configured fixed step.
func run_for(seconds: float) -> void:
    var dt: float = config.get_num("fixed_dt")
    var n: int = int(round(seconds / dt))
    for _i: int in range(n):
        step(dt)


## Recompute the bongsu graph / attachments if a command changed structures.
func refresh_network() -> bool:
    if not _network_dirty:
        return false
    _network_dirty = false
    return network.rebuild(placement)


# ------------------------------------------------------------------ commands ---

func _refuse(reason: int) -> Placement.Result:
    var r: Placement.Result = Placement.Result.new()
    r.ok = false
    r.reason = reason
    placement.rejected_total += 1
    placement.last_result = r
    commands_rejected += 1
    return r


func place_structure(kind: int, anchor: Vector2i, label: String = "") -> Placement.Result:
    if run.ended():
        return _refuse(Placement.Reject.RUN_ENDED)
    if label == "":
        label = Placement.kind_label(kind)
    var res: Placement.Result = placement.try_place(kind, anchor, sim, label)
    if not res.ok:
        commands_rejected += 1
        return res
    commands_accepted += 1
    var s: Placement.Structure = res.structure
    match kind:
        Placement.Kind.HWACHA:
            placement.configure_hwacha(
                s,
                config.get_num("hwacha_range"),
                config.get_num("hwacha_blast_radius"),
                config.get_num("hwacha_damage"),
                config.get_num("hwacha_cooldown")
            )
            s.detect_range = config.get_num("hwacha_local_range")
        Placement.Kind.SENSOR:
            s.detect_range = config.get_num("sensor_range")
    if kind != Placement.Kind.JANGSEUNG:
        _network_dirty = true
        refresh_network()
    return res


func place_jangseung(anchor: Vector2i) -> Placement.Result:
    return place_structure(Placement.Kind.JANGSEUNG, anchor, "장승")


func place_hwacha(anchor: Vector2i) -> Placement.Result:
    return place_structure(Placement.Kind.HWACHA, anchor, "화차")


func place_bongsu(anchor: Vector2i) -> Placement.Result:
    return place_structure(Placement.Kind.BONGSU, anchor, "봉수대")


func place_sensor(anchor: Vector2i) -> Placement.Result:
    return place_structure(Placement.Kind.SENSOR, anchor, "혼천의")


func remove_structure(structure_id: int) -> Placement.Result:
    if run.ended():
        return _refuse(Placement.Reject.RUN_ENDED)
    var s: Placement.Structure = placement.get_structure(structure_id)
    var res: Placement.Result = placement.remove(structure_id)
    if not res.ok:
        commands_rejected += 1
        return res
    commands_accepted += 1
    if s != null and s.kind != Placement.Kind.JANGSEUNG:
        _network_dirty = true
        refresh_network()
    return res


func remove_at_world(p: Vector2) -> Placement.Result:
    var s: Placement.Structure = placement.structure_at_world(p)
    if s == null:
        return placement.remove(-1)
    return remove_structure(s.id)


## Debug "destroy"/"repair" stand-in (D-014). In waves mode a lost district
## can never be re-activated (D-023). Never touches the path field.
func set_active(structure_id: int, active: bool) -> bool:
    if run.ended():
        return false
    var s: Placement.Structure = placement.get_structure(structure_id)
    if s == null or s.active == active:
        return false
    if active and placement.locked_district >= 0 and s.district == placement.locked_district:
        commands_rejected += 1
        return false
    placement.set_active(structure_id, active)
    activation_changes += 1
    if s.kind != Placement.Kind.JANGSEUNG:
        _network_dirty = true
        refresh_network()
    return true


func toggle_active_at_world(p: Vector2) -> Placement.Structure:
    var s: Placement.Structure = placement.structure_at_world(p)
    if s == null:
        return null
    set_active(s.id, not s.active)
    return s


## WP-003 D-024: place the recovered H1 inside the inner district. The right
## is consumed only by a successful placement; refusals change nothing.
func place_recovery(anchor: Vector2i) -> Placement.Result:
    if run.ended():
        return _refuse(Placement.Reject.RUN_ENDED)
    if run.recovery_right <= 0:
        return _refuse(Placement.Reject.NO_RECOVERY_RIGHT)
    var res: Placement.Result = placement.restore(run.recovery_target_id, anchor, sim, TestMap.DISTRICT_INNER)
    if not res.ok:
        commands_rejected += 1
        run.log_event(steps, sim_time, "recovery_refused", {"anchor": [anchor.x, anchor.y],
            "reason": Placement.reject_name(res.reason)})
        return res
    commands_accepted += 1
    run.recovery_right = 0
    run.recovery_placed = true
    run.recovery_placed_tick = steps
    run.recovery_anchor = anchor
    _network_dirty = true
    refresh_network()
    network.detect(placement, sim)
    var s: Placement.Structure = res.structure
    run.log_event(steps, sim_time, "recovery_placed", {"hwacha_id": s.id, "anchor": [anchor.x, anchor.y],
        "attached_to": s.attached_to, "group": s.group_id, "cooldown_left": s.cooldown_left,
        "shots": s.shots_fired, "kills": s.kills})
    return res


## Cursor preview for the recovery placement (same rules, no side effects).
func preview_recovery(anchor: Vector2i) -> int:
    if run.ended():
        return Placement.Reject.RUN_ENDED
    if run.recovery_right <= 0:
        return Placement.Reject.NO_RECOVERY_RIGHT
    return placement.preview_restore(run.recovery_target_id, anchor, sim, TestMap.DISTRICT_INNER)


## Verification-only hook (F2 / F3 / perf): set the outer HP directly. Logged,
## never used by the game itself. The collapse still happens through real
## arrival damage.
func force_outer_hp(value: float, why: String) -> void:
    run.outer_hp = value
    run.forced_hp_writes += 1
    run.log_event(steps, sim_time, "verification_force_outer_hp", {"value": value, "why": why})


func force_core_hp(value: float, why: String) -> void:
    run.core_hp = value
    run.forced_hp_writes += 1
    run.log_event(steps, sim_time, "verification_force_core_hp", {"value": value, "why": why})


## Verification-only: spawn `count` enemies at a world position on route 0 and
## account for them as extra (outside the wave table).
func spawn_extra(world_pos: Vector2, count: int, why: String) -> PackedInt32Array:
    var slots: PackedInt32Array = PackedInt32Array()
    for _i: int in range(count):
        var s: int = sim.force_spawn(0, world_pos)
        if s >= 0:
            slots.append(s)
    waves.spawned_extra += slots.size()
    run.log_event(steps, sim_time, "verification_spawn_extra", {"count": slots.size(), "pos": [world_pos.x, world_pos.y], "why": why})
    return slots


# ------------------------------------------------------------------ readouts ---

func current_goal_world() -> Vector2:
    return grid.index_center(path.goal_index)


func district_counts() -> Dictionary:
    var out: Dictionary = {"inner_total": 0, "inner_active": 0, "outer_total": 0, "outer_active": 0,
        "detached": placement.detached.size(), "world": placement.structures.size()}
    for id: int in placement.structures:
        var s: Placement.Structure = placement.structures[id]
        var key: String = "inner" if s.district == TestMap.DISTRICT_INNER else "outer"
        out[key + "_total"] += 1
        if s.active:
            out[key + "_active"] += 1
    return out


func zone_counts() -> PackedInt32Array:
    return density.counts


func route_summary() -> String:
    var parts: PackedStringArray = PackedStringArray()
    for r: int in range(path.route_ids.size()):
        parts.append("%s %d" % [TestMap.route_display_name(r), sim.route_alive[r]])
    return " / ".join(parts)


## Hash of the whole simulation state, for "two runs are identical" checks.
func state_hash() -> String:
    var h: float = 0.0
    for s: int in sim.live_slots():
        h += sim.pos_x[s] * 0.37 + sim.pos_y[s] * 1.13 + sim.hp[s] * 0.011 + float(sim.gen[s])
    var parts: PackedStringArray = PackedStringArray()
    parts.append("%.3f" % h)
    parts.append(str(sim.alive_count))
    parts.append(str(sim.spawned_total))
    parts.append(str(sim.rng_state()))
    for st: Placement.Structure in placement.hwachas():
        parts.append("%d:%.4f:%d:%d:%s" % [st.id, st.cooldown_left, st.shots_fired, st.kills, str(st.active)])
    for id: int in placement.detached:
        var d: Placement.Structure = placement.detached[id]
        parts.append("D%d:%.4f:%d:%d" % [d.id, d.cooldown_left, d.shots_fired, d.kills])
    parts.append("%s/%s/%.1f/%.1f/%d" % [run.run_name(), run.defense_name(), run.outer_hp, run.core_hp, run.recovery_right])
    parts.append(str(path.path_version))
    parts.append(str(waves.snapshot()["remaining"]))
    return "|".join(parts)


func snapshot() -> Dictionary:
    var routes: Array = []
    for r: int in range(path.route_ids.size()):
        routes.append({
            "id": path.route_ids[r],
            "name": TestMap.route_display_name(r),
            "alive": sim.route_alive[r],
            "spawned": sim.route_spawned[r],
            "leaked": sim.route_leaked[r],
            "peak_alive": peak_route_alive[r],
            "reachable": path.route_reachable(r),
        })
    var zones: Array = []
    for zi: int in range(density.zones.size()):
        zones.append({
            "id": density.zones[zi].id,
            "name": density.zones[zi].name,
            "count": density.counts[zi],
        })
    var guns: Array = []
    for s: Placement.Structure in placement.hwachas():
        guns.append({
            "id": s.id,
            "label": s.label,
            "active": s.active,
            "district": s.district,
            "attached_to": s.attached_to,
            "group": s.group_id,
            "known_local": s.known_local,
            "known_shared": s.known_shared,
            "known_ids": network.known_ids(s.id),
            "target_zone": s.last_zone,
            "last_target_local": s.last_target_local,
            "last_target_shared": s.last_target_shared,
            "wait_reason": s.wait_reason,
            "cooldown_left": s.cooldown_left,
            "shots": s.shots_fired,
            "kills": s.kills,
        })
    var waiting: Array = []
    for id: int in placement.detached:
        var d: Placement.Structure = placement.detached[id]
        waiting.append({"id": d.id, "label": d.label, "cooldown_left": d.cooldown_left, "shots": d.shots_fired, "kills": d.kills})
    return {
        "sim_time": sim_time,
        "steps": steps,
        "targeting_mode": targeting_mode,
        "run_mode": run_mode,
        "arrival_mode": arrival_mode,
        "fixture": config.get_str("fixture"),
        "zone_set": config.get_str("zone_set"),
        "seed": config.get_int("seed"),
        "combat_enabled": combat_enabled,
        "alive": sim.alive_count,
        "peak_alive": peak_alive,
        "spawned_total": sim.spawned_total,
        "killed_total": sim.killed_total,
        "leaked_total": sim.leaked_total,
        "goal": [path.goal_cell.x, path.goal_cell.y],
        "path_version": path.path_version,
        "structure_count": placement.structures.size(),
        "active_count": _active_count(),
        "districts": district_counts(),
        "jangseung_count": placement.count_of(Placement.Kind.JANGSEUNG),
        "hwacha_count": placement.count_of(Placement.Kind.HWACHA),
        "bongsu_count": placement.count_of(Placement.Kind.BONGSU),
        "sensor_count": placement.count_of(Placement.Kind.SENSOR),
        "rejected_total": placement.rejected_total,
        "commands_accepted": commands_accepted,
        "commands_rejected": commands_rejected,
        "activation_changes": activation_changes,
        "shots_total": hwacha.shots_total,
        "shared_only_shots": hwacha.shared_only_shots,
        "candidate_evaluations": hwacha.candidate_evaluations,
        "damage_applications": sim.damage_applications,
        "routes": routes,
        "zones": zones,
        "hwachas": guns,
        "detached": waiting,
        "network": network.snapshot(placement),
        "run": run.snapshot(),
        "waves": waves.snapshot(),
    }


func _active_count() -> int:
    var n: int = 0
    for id: int in placement.structures:
        if (placement.structures[id] as Placement.Structure).active:
            n += 1
    return n
