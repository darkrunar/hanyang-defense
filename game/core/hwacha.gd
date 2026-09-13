extends RefCounted
## Hwacha targeting and area damage.
##
## SYSTEM_SPEC rules:
##  * a hwacha aims at the candidate zone with the most living enemies among the
##    zones whose centre is within its firing range (boundary inclusive)
##  * ties are broken by the stable zone id, ascending
##  * with no enemy in any in-range zone it does not fire, and does not burn the
##    cooldown either, so it fires the instant a target appears
##  * a volley damages each living enemy inside the blast once; a death is
##    counted once

const Placement := preload("res://game/core/placement.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")

const MUZZLE_FLASH_TIME: float = 0.12


class Shot:
    extends RefCounted
    var hwacha_id: int = -1
    var zone_id: int = -1
    var aim: Vector2 = Vector2.ZERO
    var radius: float = 0.0
    var enemies_in_zone: int = 0
    var kills: int = 0


var shots_total: int = 0
var kills_total: int = 0
var last_shots: Array[Shot] = []
## [aim, radius] pairs waiting for the renderer; capped so headless runs never grow it.
var render_queue: Array = []
const RENDER_QUEUE_CAP: int = 256


func reset() -> void:
    shots_total = 0
    kills_total = 0
    last_shots.clear()
    render_queue.clear()


## Drain the pending shot visuals (renderer side).
func last_shots_for_render() -> Array:
    var out: Array = render_queue
    render_queue = []
    return out


## Pick the target zone for one hwacha. Returns the zone id or -1 for "hold fire".
## `counts` must be the current per-zone living enemy counts.
static func select_zone(
    hwacha_center: Vector2,
    fire_range: float,
    zones: Array,
    counts: PackedInt32Array
) -> int:
    var best_zone: int = -1
    var best_count: int = 0
    var r2: float = fire_range * fire_range
    for zi: int in range(zones.size()):
        var z: DensityDetector.Zone = zones[zi]
        var d: Vector2 = z.center - hwacha_center
        if d.x * d.x + d.y * d.y > r2:
            continue  # boundary inclusive: only strictly outside is skipped
        var c: int = counts[zi]
        if c <= 0:
            continue  # never aim at an empty zone
        if c > best_count:
            best_count = c
            best_zone = z.id
        elif c == best_count and best_zone >= 0 and z.id < best_zone:
            best_zone = z.id  # stable tie-break on ascending zone id
    return best_zone


func step(
    dt: float,
    placement: Placement,
    density: DensityDetector,
    counts: PackedInt32Array,
    sim: EnemySim
) -> Array[Shot]:
    last_shots.clear()
    var live_counts: PackedInt32Array = counts
    for s: Placement.Structure in placement.hwachas():
        if s.muzzle_timer > 0.0:
            s.muzzle_timer = maxf(0.0, s.muzzle_timer - dt)
        if s.cooldown_left > 0.0:
            s.cooldown_left = maxf(0.0, s.cooldown_left - dt)
            continue
        var zone_id: int = select_zone(s.center, s.fire_range, density.zones, live_counts)
        if zone_id < 0:
            s.last_zone = -1
            continue  # hold fire, keep the cooldown at zero
        var z: DensityDetector.Zone = density.zones[zone_id]
        var shot: Shot = Shot.new()
        shot.hwacha_id = s.id
        shot.zone_id = zone_id
        shot.aim = z.center
        shot.radius = s.blast_radius
        shot.enemies_in_zone = live_counts[zone_id]
        shot.kills = sim.apply_blast(z.center, s.blast_radius, s.damage)

        s.cooldown_left = s.cooldown
        s.last_zone = zone_id
        s.last_aim = z.center
        s.shots_fired += 1
        s.kills += shot.kills
        s.muzzle_timer = MUZZLE_FLASH_TIME
        shots_total += 1
        kills_total += shot.kills
        last_shots.append(shot)
        if render_queue.size() < RENDER_QUEUE_CAP:
            render_queue.append([z.center, s.blast_radius])
        # Later hwachas in the same tick must see the enemies this volley removed.
        live_counts = density.evaluate(sim)
    return last_shots
