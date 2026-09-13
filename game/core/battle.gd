extends RefCounted
## Battle orchestrator: owns the map, path field, enemies, zones, structures,
## the bongsu network and the hwachas, and advances them on a fixed timestep.
##
## Nothing here touches the SceneTree, so the headless tests drive `step()`
## directly and the rendering layer only reads state.
##
## Tick order (WP-002 contract): spawn -> move -> global zone densities ->
## network rebuild (if a command dirtied it) -> detection -> hwacha decisions
## -> benchmark top-up. Commands issued between ticks therefore take effect
## before the next firing decision, never after it.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const Placement := preload("res://game/core/placement.gd")
const Hwacha := preload("res://game/core/hwacha.gd")
const BongsuNetwork := preload("res://game/core/bongsu_network.gd")
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

var sim_time: float = 0.0
var steps: int = 0
var combat_enabled: bool = true
var spawning_enabled: bool = true
var benchmark_hold_alive: bool = false
## "wp002" (local + shared detection) or "wp001" (global densities).
var targeting_mode: String = "wp002"
var _network_dirty: bool = true

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
    density = TestMap.build_zones()
    placement = Placement.new(grid, path)
    hwacha = Hwacha.new()
    network = BongsuNetwork.new()
    sim = EnemySim.new(grid, path, config.get_int("enemy_capacity"))
    peak_route_alive.resize(path.route_ids.size())
    reset()


## Full reset: structures, network, enemies, counters; then the configured fixture.
func reset() -> void:
    grid.clear_structures()
    placement.reset()
    hwacha.reset()
    network.reset()
    path.rebuild()
    _apply_tuning()
    sim.reset(config.get_int("seed"))
    combat_enabled = config.get_bool("combat_enabled")
    benchmark_hold_alive = config.get_bool("benchmark_hold_alive")
    targeting_mode = config.get_str("targeting_mode")
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
        "b":
            for h: Array in TestMap.HWACHAS:
                _place_or_error(Placement.Kind.HWACHA, Vector2i(h[1], h[2]), h[0])
            for b: Array in TestMap.FIXTURE_B_BONGSU:
                _place_or_error(Placement.Kind.BONGSU, Vector2i(b[1], b[2]), b[0])
            for s: Array in TestMap.FIXTURE_B_SENSORS:
                _place_or_error(Placement.Kind.SENSOR, Vector2i(s[1], s[2]), s[0])
        "none":
            pass
        _:
            push_error("unknown fixture '%s'" % name)


func _place_or_error(kind: int, anchor: Vector2i, label: String) -> void:
    var res: Placement.Result = place_structure(kind, anchor, label)
    if not res.ok:
        push_error("fixture %s '%s' at %s rejected: %s" % [
            Placement.kind_name(kind), label, str(anchor), Placement.reject_name(res.reason)
        ])


# ---------------------------------------------------------------- simulation ---

## One fixed simulation step.
func step(dt: float) -> void:
    if spawning_enabled:
        sim.maintain(
            config.get_int("target_alive"),
            config.get_num("spawn_rate"),
            dt
        )
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
        for s: Placement.Structure in placement.hwachas():
            s.last_zone = -1
            s.wait_reason = "전투 비활성"
            if s.muzzle_timer > 0.0:
                s.muzzle_timer = maxf(0.0, s.muzzle_timer - dt)
    if benchmark_hold_alive and spawning_enabled:
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


## Advance `seconds` of simulated time at the configured fixed step.
func run_for(seconds: float) -> void:
    var dt: float = config.get_num("fixed_dt")
    var n: int = int(round(seconds / dt))
    for _i: int in range(n):
        step(dt)


## Recompute the bongsu graph / attachments if a command changed structures.
## Cheap, so commands also call it eagerly for immediate observability.
func refresh_network() -> bool:
    if not _network_dirty:
        return false
    _network_dirty = false
    return network.rebuild(placement)


# ------------------------------------------------------------------ commands ---

func place_structure(kind: int, anchor: Vector2i, label: String = "") -> Placement.Result:
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


## Debug "destroy"/"repair" stand-in (D-014). Never touches the path field.
func set_active(structure_id: int, active: bool) -> bool:
    var s: Placement.Structure = placement.get_structure(structure_id)
    if s == null or s.active == active:
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


# ------------------------------------------------------------------ readouts ---

func zone_counts() -> PackedInt32Array:
    return density.counts


func route_summary() -> String:
    var parts: PackedStringArray = PackedStringArray()
    for r: int in range(path.route_ids.size()):
        parts.append("%s %d" % [TestMap.route_display_name(r), sim.route_alive[r]])
    return " / ".join(parts)


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
    return {
        "sim_time": sim_time,
        "steps": steps,
        "targeting_mode": targeting_mode,
        "fixture": config.get_str("fixture"),
        "seed": config.get_int("seed"),
        "combat_enabled": combat_enabled,
        "alive": sim.alive_count,
        "peak_alive": peak_alive,
        "spawned_total": sim.spawned_total,
        "killed_total": sim.killed_total,
        "leaked_total": sim.leaked_total,
        "path_version": path.path_version,
        "structure_count": placement.structures.size(),
        "active_count": _active_count(),
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
        "routes": routes,
        "zones": zones,
        "hwachas": guns,
        "network": network.snapshot(placement),
    }


func _active_count() -> int:
    var n: int = 0
    for id: int in placement.structures:
        if (placement.structures[id] as Placement.Structure).active:
            n += 1
    return n
