extends RefCounted
## Hwacha targeting and area damage.
##
## SYSTEM_SPEC rules (WP-001, kept):
##  * a hwacha aims at the candidate zone with the most counted living enemies
##    among the zones whose centre is within its firing range (boundary inclusive)
##  * ties are broken by the stable zone id, ascending
##  * with no enemy in any in-range zone it does not fire, and does not burn the
##    cooldown either, so it fires the instant a target appears
##  * a volley damages each living enemy inside the blast once; a death is
##    counted once
##
## WP-002 (D-013): in "wp002" mode the counted enemies are only the ones THIS
## hwacha knows (local detection ∪ same-group active sensors), computed by
## BongsuNetwork every tick after movement and before firing. In "wp001" mode
## the global zone densities are used, byte-for-byte the WP-001 behaviour.

const Placement := preload("res://game/core/placement.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")
const BongsuNetwork := preload("res://game/core/bongsu_network.gd")

const MUZZLE_FLASH_TIME: float = 0.12


class Shot:
    extends RefCounted
    var hwacha_id: int = -1
    var zone_id: int = -1
    var aim: Vector2 = Vector2.ZERO
    var radius: float = 0.0
    var enemies_in_zone: int = 0
    var local_in_zone: int = 0     # WP-002: how many counted enemies were locally detected
    var shared_in_zone: int = 0    # WP-002: how many came only through the network
    var kills: int = 0
    var sim_time: float = 0.0


var shots_total: int = 0
var kills_total: int = 0
## WP-002: volleys whose target zone count came entirely from shared detections.
var shared_only_shots: int = 0
var last_shots: Array[Shot] = []
## [aim, radius] pairs waiting for the renderer; capped so headless runs never grow it.
var render_queue: Array = []
const RENDER_QUEUE_CAP: int = 256


func reset() -> void:
    shots_total = 0
    kills_total = 0
    shared_only_shots = 0
    last_shots.clear()
    render_queue.clear()


## Drain the pending shot visuals (renderer side).
func last_shots_for_render() -> Array:
    var out: Array = render_queue
    render_queue = []
    return out


## Pick the target zone for one hwacha. Returns the zone id or -1 for "hold fire".
## `counts` must be the per-zone counts this hwacha is allowed to use.
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


## One tick of targeting for every hwacha, in ascending id order.
## `network` is null in wp001 mode (global counts) and required in wp002 mode.
func step(
    dt: float,
    placement: Placement,
    density: DensityDetector,
    counts: PackedInt32Array,
    sim: EnemySim,
    network: BongsuNetwork = null,
    sim_time: float = 0.0
) -> Array[Shot]:
    last_shots.clear()
    var live_counts: PackedInt32Array = counts
    var scratch_local: PackedInt32Array = PackedInt32Array()
    for s: Placement.Structure in placement.hwachas():
        if s.muzzle_timer > 0.0:
            s.muzzle_timer = maxf(0.0, s.muzzle_timer - dt)
        # The cooldown always runs down; nothing about the network resets it.
        if s.cooldown_left > 0.0:
            s.cooldown_left = maxf(0.0, s.cooldown_left - dt)
            s.wait_reason = "재장전"
            continue
        if not s.active:
            s.last_zone = -1
            s.wait_reason = "비활성"
            continue

        var my_counts: PackedInt32Array
        if network != null:
            # WP-002: only what this hwacha knows, minus anything that died
            # since detection (kills by earlier hwachas this tick).
            my_counts = network.known_zone_counts(s, density, sim, scratch_local)
        else:
            my_counts = live_counts

        var zone_id: int = select_zone(s.center, s.fire_range, density.zones, my_counts)
        if zone_id < 0:
            s.last_zone = -1
            s.wait_reason = _hold_reason(s, density, my_counts)
            continue  # hold fire, keep the cooldown at zero

        var z: DensityDetector.Zone = density.zones[zone_id]
        var shot: Shot = Shot.new()
        shot.hwacha_id = s.id
        shot.zone_id = zone_id
        shot.aim = z.center
        shot.radius = s.blast_radius
        shot.enemies_in_zone = my_counts[zone_id]
        shot.sim_time = sim_time
        if network != null:
            shot.local_in_zone = scratch_local[zone_id]
            shot.shared_in_zone = my_counts[zone_id] - scratch_local[zone_id]
        else:
            shot.local_in_zone = my_counts[zone_id]
        shot.kills = sim.apply_blast(z.center, s.blast_radius, s.damage)

        s.cooldown_left = s.cooldown
        s.last_zone = zone_id
        s.last_aim = z.center
        s.last_target_local = shot.local_in_zone
        s.last_target_shared = shot.shared_in_zone
        s.wait_reason = ""
        s.shots_fired += 1
        s.kills += shot.kills
        s.muzzle_timer = MUZZLE_FLASH_TIME
        shots_total += 1
        kills_total += shot.kills
        if network != null and shot.local_in_zone == 0:
            shared_only_shots += 1
        last_shots.append(shot)
        if render_queue.size() < RENDER_QUEUE_CAP:
            render_queue.append([z.center, s.blast_radius])
        if network == null:
            # WP-001 mode: later hwachas must see the enemies this volley removed.
            live_counts = density.evaluate(sim)
    return last_shots


static func _hold_reason(s: Placement.Structure, density: DensityDetector, counts: PackedInt32Array) -> String:
    var any_known: bool = false
    var any_in_range: bool = false
    var r2: float = s.fire_range * s.fire_range
    for zi: int in range(density.zones.size()):
        if counts[zi] > 0:
            any_known = true
            var d: Vector2 = density.zones[zi].center - s.center
            if d.x * d.x + d.y * d.y <= r2:
                any_in_range = true
    if not any_known:
        return "표적 없음"
    if not any_in_range:
        return "알려진 표적이 사거리 밖"
    return "표적 없음"
