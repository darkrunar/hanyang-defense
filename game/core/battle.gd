extends RefCounted
## WP-001 battle orchestrator: owns the map, path field, enemies, zones and
## hwachas, and advances them on a fixed timestep.
##
## Nothing here touches the SceneTree, so the headless tests drive `step()`
## directly and the rendering layer only reads state.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const Placement := preload("res://game/core/placement.gd")
const Hwacha := preload("res://game/core/hwacha.gd")
const Config := preload("res://game/core/config.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

var config: Config = null
var grid: TerrainGrid = null
var path: PathNetwork = null
var sim: EnemySim = null
var density: DensityDetector = null
var placement: Placement = null
var hwacha: Hwacha = null

var sim_time: float = 0.0
var steps: int = 0
var combat_enabled: bool = true
var spawning_enabled: bool = true
var benchmark_hold_alive: bool = false

## Peak concurrent living enemies, i.e. the number AC-01 is about.
var peak_alive: int = 0
var peak_route_alive: PackedInt32Array = PackedInt32Array()


func _init(cfg: Config = null) -> void:
    config = cfg if cfg != null else Config.new()
    grid = TestMap.build_grid()
    path = TestMap.build_path(grid)
    density = TestMap.build_zones()
    placement = Placement.new(grid, path)
    hwacha = Hwacha.new()
    sim = EnemySim.new(grid, path, config.get_int("enemy_capacity"))
    peak_route_alive.resize(path.route_ids.size())
    reset()


func reset() -> void:
    grid.clear_structures()
    placement.reset()
    hwacha.reset()
    path.rebuild()
    _apply_tuning()
    sim.reset(config.get_int("seed"))
    combat_enabled = config.get_bool("combat_enabled")
    benchmark_hold_alive = config.get_bool("benchmark_hold_alive")
    spawning_enabled = true
    sim_time = 0.0
    steps = 0
    peak_alive = 0
    peak_route_alive.fill(0)
    _place_initial_hwachas()
    density.evaluate(sim)


func _apply_tuning() -> void:
    sim.base_speed = config.get_num("enemy_speed")
    sim.speed_jitter = config.get_num("enemy_speed_jitter")
    sim.lane_offset = config.get_num("enemy_lane_offset")
    sim.max_hp = config.get_num("enemy_hp")
    sim.goal_radius = config.get_num("goal_radius")


func _place_initial_hwachas() -> void:
    for h: Array in TestMap.HWACHAS:
        var res: Placement.Result = placement.try_place(
            Placement.Kind.HWACHA, Vector2i(h[1], h[2]), null, h[0]
        )
        if res.ok:
            placement.configure_hwacha(
                res.structure,
                config.get_num("hwacha_range"),
                config.get_num("hwacha_blast_radius"),
                config.get_num("hwacha_damage"),
                config.get_num("hwacha_cooldown")
            )
        else:
            push_error("Initial hwacha '%s' rejected: %s" % [
                h[0], Placement.reject_name(res.reason)
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
    if combat_enabled:
        hwacha.step(dt, placement, density, counts, sim)
    else:
        for s: Placement.Structure in placement.hwachas():
            s.last_zone = -1
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


# ------------------------------------------------------------------ commands ---

func place_jangseung(anchor: Vector2i) -> Placement.Result:
    return placement.try_place(Placement.Kind.JANGSEUNG, anchor, sim, "장승")


func place_hwacha(anchor: Vector2i) -> Placement.Result:
    var res: Placement.Result = placement.try_place(
        Placement.Kind.HWACHA, anchor, sim, "화차"
    )
    if res.ok:
        placement.configure_hwacha(
            res.structure,
            config.get_num("hwacha_range"),
            config.get_num("hwacha_blast_radius"),
            config.get_num("hwacha_damage"),
            config.get_num("hwacha_cooldown")
        )
    return res


func remove_at_world(p: Vector2) -> Placement.Result:
    var s: Placement.Structure = placement.structure_at_world(p)
    if s == null:
        return placement.remove(-1)
    return placement.remove(s.id)


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
            "target_zone": s.last_zone,
            "shots": s.shots_fired,
            "kills": s.kills,
        })
    return {
        "sim_time": sim_time,
        "steps": steps,
        "combat_enabled": combat_enabled,
        "alive": sim.alive_count,
        "peak_alive": peak_alive,
        "spawned_total": sim.spawned_total,
        "killed_total": sim.killed_total,
        "leaked_total": sim.leaked_total,
        "path_version": path.path_version,
        "jangseung_count": placement.count_of(Placement.Kind.JANGSEUNG),
        "hwacha_count": placement.count_of(Placement.Kind.HWACHA),
        "rejected_total": placement.rejected_total,
        "routes": routes,
        "zones": zones,
        "hwachas": guns,
    }
