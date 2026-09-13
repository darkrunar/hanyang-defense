extends RefCounted
## AC-04 / AC-05: density counting at known coordinates, and hwacha targeting.

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const Hwacha := preload("res://game/core/hwacha.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SOUTH: int = 0


static func _fresh(combat: bool = true) -> Battle:
    var cfg: Config = Config.for_wp001()
    cfg.values["combat_enabled"] = combat
    return Battle.new(cfg)


func run(t: RefCounted) -> void:
    _ac04_density_exact(t)
    _ac04_density_excludes_dead(t)
    _ac05_selects_densest_zone(t)
    _ac05_tie_breaks_on_zone_id(t)
    _ac05_holds_fire_when_empty(t)
    _ac05_blast_damage_counted_once(t)
    _ac05_cooldown_gates_fire_rate(t)


# --------------------------------------------------------------------- AC-04 ---

func _ac04_density_exact(t: RefCounted) -> void:
    t.case("AC-04 density counts known coordinates, boundary inclusive")
    var b: Battle = _fresh(false)
    b.spawning_enabled = false
    var d: DensityDetector = DensityDetector.new()
    var centre: Vector2 = Vector2(900.0, 750.0)
    var radius: float = 45.0
    d.add_zone("probe", centre, radius)

    # 3 clearly inside, 2 exactly on the boundary, 3 clearly outside.
    var inside: Array[Vector2] = [
        centre,
        centre + Vector2(10.0, 0.0),
        centre + Vector2(-20.0, 20.0),
    ]
    var boundary: Array[Vector2] = [
        centre + Vector2(radius, 0.0),        # +45 on x
        centre + Vector2(0.0, -radius),       # -45 on y
    ]
    var outside: Array[Vector2] = [
        centre + Vector2(radius + 0.5, 0.0),
        centre + Vector2(0.0, radius + 3.0),
        centre + Vector2(200.0, 200.0),
    ]
    for p: Vector2 in inside:
        b.sim.force_spawn(SOUTH, p)
    for p: Vector2 in boundary:
        b.sim.force_spawn(SOUTH, p)
    for p: Vector2 in outside:
        b.sim.force_spawn(SOUTH, p)

    t.eq(b.sim.alive_count, 8, "8 enemies placed at known coordinates")
    t.eq(d.count_in_zone(b.sim, 0), 5, "count = 3 inside + 2 exactly on the radius")
    t.eq(d.evaluate(b.sim)[0], 5, "batch evaluate matches the single-zone count")


func _ac04_density_excludes_dead(t: RefCounted) -> void:
    t.case("AC-04 dead enemies leave the density immediately")
    var b: Battle = _fresh(false)
    b.spawning_enabled = false
    var d: DensityDetector = DensityDetector.new()
    var centre: Vector2 = Vector2(900.0, 750.0)
    d.add_zone("probe", centre, 45.0)

    for i: int in range(6):
        b.sim.force_spawn(SOUTH, centre + Vector2(float(i) * 4.0 - 10.0, 0.0))
    t.eq(d.count_in_zone(b.sim, 0), 6, "all six counted while alive")

    var kills: int = b.sim.apply_blast(centre, 12.0, 9999.0)
    t.eq(kills, 6, "one lethal volley kills all six")
    t.eq(d.count_in_zone(b.sim, 0), 0, "density drops to zero, no dead enemy counted")
    t.eq(b.sim.killed_total, 6, "each death counted exactly once")
    t.eq(b.sim.alive_count, 0, "alive count consistent")


# --------------------------------------------------------------------- AC-05 ---

func _ac05_selects_densest_zone(t: RefCounted) -> void:
    t.case("AC-05 hwacha aims at the densest in-range zone and ignores out-of-range")
    var d: DensityDetector = DensityDetector.new()
    var gun: Vector2 = Vector2(1000.0, 1000.0)
    d.add_zone("near_light", gun + Vector2(100.0, 0.0), 40.0)   # Z0, in range
    d.add_zone("near_heavy", gun + Vector2(0.0, 150.0), 40.0)   # Z1, in range
    d.add_zone("far_heaviest", gun + Vector2(600.0, 0.0), 40.0) # Z2, out of range
    var counts: PackedInt32Array = PackedInt32Array([4, 9, 400])

    var picked: int = Hwacha.select_zone(gun, 200.0, d.zones, counts)
    t.eq(picked, 1, "picks the densest zone inside the firing range")

    counts = PackedInt32Array([12, 9, 400])
    picked = Hwacha.select_zone(gun, 200.0, d.zones, counts)
    t.eq(picked, 0, "follows the density when it moves to another in-range zone")

    # Boundary of the firing range counts as in range.
    var edge: DensityDetector = DensityDetector.new()
    edge.add_zone("exactly_at_range", gun + Vector2(200.0, 0.0), 40.0)
    t.eq(Hwacha.select_zone(gun, 200.0, edge.zones, PackedInt32Array([3])), 0,
        "a zone exactly at the range boundary is targetable")
    t.eq(Hwacha.select_zone(gun, 199.9, edge.zones, PackedInt32Array([3])), -1,
        "a zone just beyond the range is not")


func _ac05_tie_breaks_on_zone_id(t: RefCounted) -> void:
    t.case("AC-05 equal density ties break on the stable zone id")
    var d: DensityDetector = DensityDetector.new()
    var gun: Vector2 = Vector2(1000.0, 1000.0)
    d.add_zone("z0", gun + Vector2(-120.0, 0.0), 40.0)
    d.add_zone("z1", gun + Vector2(120.0, 0.0), 40.0)
    d.add_zone("z2", gun + Vector2(0.0, 120.0), 40.0)

    t.eq(Hwacha.select_zone(gun, 200.0, d.zones, PackedInt32Array([7, 7, 7])), 0,
        "three-way tie picks the lowest zone id")
    t.eq(Hwacha.select_zone(gun, 200.0, d.zones, PackedInt32Array([2, 7, 7])), 1,
        "tie among the leaders picks the lowest of those ids")
    # Repeat to show the choice is stable, not incidental.
    for i: int in range(5):
        if Hwacha.select_zone(gun, 200.0, d.zones, PackedInt32Array([7, 7, 7])) != 0:
            t.check(false, "tie-break is not stable across repeats")
            return
    t.check(true, "tie-break is stable across repeated evaluations")


func _ac05_holds_fire_when_empty(t: RefCounted) -> void:
    t.case("AC-05 no enemies means no shot, and the cooldown is not burned")
    var d: DensityDetector = DensityDetector.new()
    var gun: Vector2 = Vector2(1000.0, 1000.0)
    d.add_zone("z0", gun + Vector2(100.0, 0.0), 40.0)
    t.eq(Hwacha.select_zone(gun, 200.0, d.zones, PackedInt32Array([0])), -1,
        "an empty zone is never targeted")

    var b: Battle = _fresh(true)
    b.spawning_enabled = false
    b.run_for(5.0)
    t.eq(b.hwacha.shots_total, 0, "an empty field produces no shots")
    for s: Placement.Structure in b.placement.hwachas():
        t.eq(s.cooldown_left, 0.0, "hwacha #%d stays ready while holding fire" % s.id)

    # One enemy appears inside a covered zone: the very next step must fire.
    var z: DensityDetector.Zone = b.density.zones[0]
    b.sim.force_spawn(SOUTH, z.center)
    b.step(b.config.get_num("fixed_dt"))
    t.eq(b.hwacha.shots_total, 1, "fires on the first step after a target appears")


func _ac05_blast_damage_counted_once(t: RefCounted) -> void:
    t.case("AC-05 a volley damages each enemy once and counts each death once")
    var b: Battle = _fresh(false)
    b.spawning_enabled = false
    var centre: Vector2 = Vector2(900.0, 750.0)

    # 4 inside the blast, 1 exactly on the blast boundary, 2 outside.
    var radius: float = 55.0
    for i: int in range(4):
        b.sim.force_spawn(SOUTH, centre + Vector2(float(i) * 6.0 - 9.0, 0.0), 60.0)
    var edge_slot: int = b.sim.force_spawn(SOUTH, centre + Vector2(radius, 0.0), 60.0)
    var out_a: int = b.sim.force_spawn(SOUTH, centre + Vector2(radius + 1.0, 0.0), 60.0)
    var out_b: int = b.sim.force_spawn(SOUTH, centre + Vector2(300.0, 0.0), 60.0)
    t.eq(b.sim.alive_count, 7, "7 enemies staged")

    # First volley: 25 damage against hp 60, nobody should die.
    var kills1: int = b.sim.apply_blast(centre, radius, 25.0)
    t.eq(kills1, 0, "first volley kills nobody")
    t.eq(b.sim.hp[edge_slot], 35.0, "enemy exactly on the blast edge took damage once")
    t.eq(b.sim.hp[out_a], 60.0, "enemy just outside took no damage")
    t.eq(b.sim.hp[out_b], 60.0, "distant enemy took no damage")

    # Second volley: still alive at 10 hp.
    var kills2: int = b.sim.apply_blast(centre, radius, 25.0)
    t.eq(kills2, 0, "second volley still kills nobody")
    t.eq(b.sim.hp[edge_slot], 10.0, "damage accumulates once per volley")

    # Third volley kills the five in the blast, exactly once each.
    var kills3: int = b.sim.apply_blast(centre, radius, 25.0)
    t.eq(kills3, 5, "third volley kills the five inside the blast")
    t.eq(b.sim.killed_total, 5, "kill counter totals five, no double counting")
    t.eq(b.sim.alive_count, 2, "the two outside survive")

    # A repeat volley over corpses must do nothing.
    var kills4: int = b.sim.apply_blast(centre, radius, 25.0)
    t.eq(kills4, 0, "firing again over the dead adds no kills")
    t.eq(b.sim.killed_total, 5, "kill counter unchanged")


func _ac05_cooldown_gates_fire_rate(t: RefCounted) -> void:
    t.case("AC-05 cooldown gates the fire rate")
    var cfg: Config = Config.for_wp001()
    cfg.values["combat_enabled"] = true
    cfg.values["hwacha_cooldown"] = 1.0
    cfg.values["enemy_hp"] = 1.0e9   # never dies, so the target zone stays full
    cfg.values["enemy_speed"] = 0.0  # and never walks out of the zone
    var b: Battle = Battle.new(cfg)
    b.spawning_enabled = false

    var z: DensityDetector.Zone = b.density.zones[7]  # 광화문 어귀, covered by 화차·궁성
    for i: int in range(20):
        b.sim.force_spawn(SOUTH, z.center + Vector2(float(i % 5) * 4.0, float(i / 5) * 4.0))
    b.run_for(5.0)
    # 5 s at a 1 s cooldown: fires at t=0 then once per second -> 5 or 6 volleys.
    t.check(b.hwacha.shots_total >= 5 and b.hwacha.shots_total <= 6,
        "5 s at a 1 s cooldown produced %d volleys" % b.hwacha.shots_total)
