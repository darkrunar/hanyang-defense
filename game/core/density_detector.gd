extends RefCounted
## Candidate chokepoint zones and their live enemy counts.
##
## SYSTEM_SPEC rule: density is the number of LIVING enemies inside a circular
## radius, and an enemy exactly on the boundary counts. Dead enemies are already
## out of the sim's live list, so they can never be counted.

const EnemySim := preload("res://game/core/enemy_sim.gd")


class Zone:
    extends RefCounted
    var id: int = 0
    var name: String = ""
    var center: Vector2 = Vector2.ZERO
    var radius: float = 0.0

    func _init(zone_id: int, zone_name: String, c: Vector2, r: float) -> void:
        id = zone_id
        name = zone_name
        center = c
        radius = r


var zones: Array[Zone] = []
var counts: PackedInt32Array = PackedInt32Array()


func add_zone(zone_name: String, center: Vector2, radius: float) -> Zone:
    var z: Zone = Zone.new(zones.size(), zone_name, center, radius)
    zones.append(z)
    counts.resize(zones.size())
    return z


func zone_by_id(zone_id: int) -> Zone:
    if zone_id < 0 or zone_id >= zones.size():
        return null
    return zones[zone_id]


## Count living enemies inside one zone. Boundary inclusive (<=).
func count_in_zone(sim: EnemySim, zone_id: int) -> int:
    var z: Zone = zones[zone_id]
    var r2: float = z.radius * z.radius
    var cx: float = z.center.x
    var cy: float = z.center.y
    var n: int = 0
    for s: int in sim.live_slots():
        var dx: float = sim.pos_x[s] - cx
        var dy: float = sim.pos_y[s] - cy
        if dx * dx + dy * dy <= r2:
            n += 1
    return n


## Refresh every zone count in a single pass over the live enemies.
func evaluate(sim: EnemySim) -> PackedInt32Array:
    var zn: int = zones.size()
    counts.fill(0)
    var live: PackedInt32Array = sim.live_slots()
    var px: PackedFloat32Array = sim.pos_x
    var py: PackedFloat32Array = sim.pos_y
    for zi: int in range(zn):
        var z: Zone = zones[zi]
        var cx: float = z.center.x
        var cy: float = z.center.y
        var r2: float = z.radius * z.radius
        var n: int = 0
        for s: int in live:
            var dx: float = px[s] - cx
            var dy: float = py[s] - cy
            if dx * dx + dy * dy <= r2:
                n += 1
        counts[zi] = n
    return counts
