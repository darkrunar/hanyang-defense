extends RefCounted
## WP-002 봉수망: relay graph, terminal attachment, and shared detection.
##
## Contract (backlog/WP-002.md, DECISIONS D-012 / D-013):
##  * only ACTIVE bongsu are nodes; two bongsu are linked when their centre
##    distance is <= link_range (boundary inclusive, no line-of-sight)
##  * a group is a connected component; its id is the smallest bongsu id in it
##  * each active sensor / hwacha attaches to the nearest active bongsu within
##    link_range (ties -> lowest bongsu id) and inherits that group; terminals
##    never relay and never link to each other, so they cannot merge groups
##  * every tick, each active sensor detects living enemies within its range;
##    a hwacha "knows" its own local detections plus the detections of every
##    active sensor in its group. Ids are individual (slot, generation) ids, so
##    duplicates from several sensors or local+shared overlap count once.
## Nothing is cached across ticks: a target that lost every source is gone
## before the next firing decision, by construction.

const Placement := preload("res://game/core/placement.gd")
const EnemySim := preload("res://game/core/enemy_sim.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")

var link_range: float = 180.0

## bongsu id -> Array[int] of linked bongsu ids (active only)
var edges: Dictionary = {}
## bongsu id -> group id
var bongsu_group: Dictionary = {}
## group id -> Array[int] of active sensor ids attached to that group
var group_sensors: Dictionary = {}
## Bumped only when the computed topology (edges + attachments) actually changes.
var topology_version: int = 0
## Every rebuild() call, whether or not anything changed.
var rebuilds: int = 0
var _last_signature: String = ""

## sensor id -> Dictionary { enemy_id: slot }
var sensor_seen: Dictionary = {}
## hwacha id -> Dictionary { enemy_id: slot } (local ∪ shared)
var hwacha_known: Dictionary = {}
## hwacha id -> Dictionary { enemy_id: true } for the local part only
var hwacha_local: Dictionary = {}
## WP-008 perf (D-055): zone membership per enemy slot as a bit mask, computed
## once per detection pass instead of once per hwacha per known enemy
## (measured: 12 active hwacha x 1,000 enemies spent 12.4 ms of a 16 ms tick
## in the per-hwacha distance loop). Same inequality, same counts.
var detect_serial: int = 0
var _zone_mask: PackedInt32Array = PackedInt32Array()
var _mask_serial: int = -1
var _mask_zones: int = -1


func reset() -> void:
    edges.clear()
    bongsu_group.clear()
    group_sensors.clear()
    sensor_seen.clear()
    hwacha_known.clear()
    hwacha_local.clear()
    topology_version = 0
    rebuilds = 0
    _last_signature = ""


# ------------------------------------------------------------ topology ---

static func _within(a: Vector2, b: Vector2, r: float) -> bool:
    var d: Vector2 = a - b
    return d.x * d.x + d.y * d.y <= r * r


## Recompute edges, groups and attachments from the current structures.
## Returns true when the topology changed.
func rebuild(placement: Placement) -> bool:
    rebuilds += 1
    edges.clear()
    bongsu_group.clear()
    group_sensors.clear()

    var nodes: Array = []
    for s: Placement.Structure in placement.bongsus():
        if s.active:
            nodes.append(s)
            edges[s.id] = []
    # Edges: O(n^2) over active bongsu (n is small by design: 8 in fixture B).
    for i: int in range(nodes.size()):
        var a: Placement.Structure = nodes[i]
        for j: int in range(i + 1, nodes.size()):
            var b: Placement.Structure = nodes[j]
            if _within(a.center, b.center, link_range):
                (edges[a.id] as Array).append(b.id)
                (edges[b.id] as Array).append(a.id)
    # Connected components, group id = min bongsu id in the component.
    for n: Placement.Structure in nodes:
        if bongsu_group.has(n.id):
            continue
        var stack: Array = [n.id]
        var comp: Array = []
        var seen: Dictionary = {n.id: true}
        while not stack.is_empty():
            var cur: int = stack.pop_back()
            comp.append(cur)
            for nb: int in edges[cur]:
                if not seen.has(nb):
                    seen[nb] = true
                    stack.append(nb)
        var gid: int = comp.min()
        for cid: int in comp:
            bongsu_group[cid] = gid
        group_sensors[gid] = []
    for n: Placement.Structure in nodes:
        n.group_id = bongsu_group[n.id]
        n.attached_to = -1
    for s: Placement.Structure in placement.bongsus():
        if not s.active:
            s.group_id = -1
            s.attached_to = -1

    # Terminal attachment: nearest active bongsu within range, ties -> lowest id.
    var terminals: Array = placement.sensors() + placement.hwachas()
    for t: Placement.Structure in terminals:
        t.attached_to = -1
        t.group_id = -1
        if not t.active:
            continue
        var best: Placement.Structure = null
        var best_d2: float = 0.0
        for n: Placement.Structure in nodes:   # nodes are in ascending id order
            var d: Vector2 = t.center - n.center
            var d2: float = d.x * d.x + d.y * d.y
            if d2 > link_range * link_range:
                continue
            if best == null or d2 < best_d2:
                best = n
                best_d2 = d2
        if best != null:
            t.attached_to = best.id
            t.group_id = best.group_id
            if t.kind == Placement.Kind.SENSOR:
                (group_sensors[t.group_id] as Array).append(t.id)

    var sig: String = _signature(placement)
    var changed: bool = sig != _last_signature
    if changed:
        topology_version += 1
        _last_signature = sig
    return changed


func _signature(placement: Placement) -> String:
    var parts: PackedStringArray = PackedStringArray()
    var ids: Array = edges.keys()
    ids.sort()
    for id: int in ids:
        var nb: Array = (edges[id] as Array).duplicate()
        nb.sort()
        parts.append("%d:%s" % [id, str(nb)])
    for t: Placement.Structure in placement.sensors() + placement.hwachas():
        parts.append("%d>%d" % [t.id, t.attached_to])
    return "|".join(parts)


func group_of(structure: Placement.Structure) -> int:
    return structure.group_id


func groups() -> Array:
    var out: Array = group_sensors.keys()
    out.sort()
    return out


func link_count() -> int:
    var n: int = 0
    for id: int in edges:
        n += (edges[id] as Array).size()
    return n / 2


# ------------------------------------------------------------ detection ---

## Per-tick detection. Must run after movement and after rebuild(), before
## the hwachas decide. Populates sensor_seen / hwacha_local / hwacha_known.
func detect(placement: Placement, sim: EnemySim) -> void:
    sensor_seen.clear()
    hwacha_known.clear()
    hwacha_local.clear()
    detect_serial += 1
    var live: PackedInt32Array = sim.live_slots()
    var px: PackedFloat32Array = sim.pos_x
    var py: PackedFloat32Array = sim.pos_y

    for sensor: Placement.Structure in placement.sensors():
        if not sensor.active or sensor.group_id < 0:
            continue   # a sensor without a group shares nothing (WP-002 contract)
        var seen: Dictionary = {}
        var cx: float = sensor.center.x
        var cy: float = sensor.center.y
        var r2: float = sensor.detect_range * sensor.detect_range
        for s: int in live:
            var dx: float = px[s] - cx
            var dy: float = py[s] - cy
            if dx * dx + dy * dy <= r2:
                seen[sim.enemy_id(s)] = s
        sensor_seen[sensor.id] = seen

    for h: Placement.Structure in placement.hwachas():
        var local: Dictionary = {}
        var known: Dictionary = {}
        if h.active:
            var cx: float = h.center.x
            var cy: float = h.center.y
            var r2: float = h.detect_range * h.detect_range
            for s: int in live:
                var dx: float = px[s] - cx
                var dy: float = py[s] - cy
                if dx * dx + dy * dy <= r2:
                    var id: int = sim.enemy_id(s)
                    local[id] = true
                    known[id] = s
            if h.group_id >= 0 and group_sensors.has(h.group_id):
                for sid: int in group_sensors[h.group_id]:
                    var seen: Dictionary = sensor_seen.get(sid, {})
                    for id: int in seen:
                        known[id] = seen[id]   # duplicates collapse on the id key
        hwacha_local[h.id] = local
        hwacha_known[h.id] = known
        h.known_local = local.size()
        h.known_shared = known.size() - local.size()


## Zone counts of the enemies THIS hwacha knows, skipping any that died since
## detection (so a kill by an earlier hwacha in the same tick is excluded).
## Also returns how many of the counted enemies in each zone are local.
func known_zone_counts(h: Placement.Structure, density: DensityDetector, sim: EnemySim,
        out_local: PackedInt32Array) -> PackedInt32Array:
    var zn: int = density.zones.size()
    var counts: PackedInt32Array = PackedInt32Array()
    counts.resize(zn)
    counts.fill(0)
    out_local.resize(zn)
    out_local.fill(0)
    var known: Dictionary = hwacha_known.get(h.id, {})
    var local: Dictionary = hwacha_local.get(h.id, {})
    if zn > 31:
        # More zones than mask bits: the original per-enemy distance loop.
        for id: int in known:
            var s: int = known[id]
            if not sim.is_id_alive(id):
                continue
            var ex: float = sim.pos_x[s]
            var ey: float = sim.pos_y[s]
            for zi: int in range(zn):
                var z: DensityDetector.Zone = density.zones[zi]
                var dx: float = ex - z.center.x
                var dy: float = ey - z.center.y
                if dx * dx + dy * dy <= z.radius * z.radius:
                    counts[zi] += 1
                    if local.has(id):
                        out_local[zi] += 1
        return counts
    _ensure_zone_masks(density, sim)
    for id: int in known:
        var s: int = known[id]
        if not sim.is_id_alive(id):
            continue
        var m: int = _zone_mask[s]
        if m == 0:
            continue
        var is_local: bool = local.has(id)
        var zi: int = 0
        while m != 0:
            if m & 1:
                counts[zi] += 1
                if is_local:
                    out_local[zi] += 1
            m >>= 1
            zi += 1
    return counts


## Zone bit mask of every living slot for the current detection pass
## (positions do not change between detect() and the hwacha decisions).
func _ensure_zone_masks(density: DensityDetector, sim: EnemySim) -> void:
    var zn: int = density.zones.size()
    if _mask_serial == detect_serial and _mask_zones == zn and _zone_mask.size() == sim.capacity:
        return
    if _zone_mask.size() != sim.capacity:
        _zone_mask.resize(sim.capacity)
    _zone_mask.fill(0)
    var px: PackedFloat32Array = sim.pos_x
    var py: PackedFloat32Array = sim.pos_y
    var live: PackedInt32Array = sim.live_slots()
    for zi: int in range(zn):
        var z: DensityDetector.Zone = density.zones[zi]
        var cx: float = z.center.x
        var cy: float = z.center.y
        var r2: float = z.radius * z.radius
        var bit: int = 1 << zi
        for s: int in live:
            var dx: float = px[s] - cx
            var dy: float = py[s] - cy
            if dx * dx + dy * dy <= r2:
                _zone_mask[s] |= bit
    _mask_serial = detect_serial
    _mask_zones = zn


func known_count(hwacha_id: int) -> int:
    return (hwacha_known.get(hwacha_id, {}) as Dictionary).size()


func known_ids(hwacha_id: int) -> Array:
    var out: Array = (hwacha_known.get(hwacha_id, {}) as Dictionary).keys()
    out.sort()
    return out


func snapshot(placement: Placement) -> Dictionary:
    var bongsu: Array = []
    for b: Placement.Structure in placement.bongsus():
        var nb: Array = (edges.get(b.id, []) as Array).duplicate()
        nb.sort()
        bongsu.append({"id": b.id, "label": b.label, "active": b.active, "group": b.group_id, "links": nb})
    var terminals: Array = []
    for t: Placement.Structure in placement.sensors() + placement.hwachas():
        terminals.append({
            "id": t.id, "kind": Placement.kind_name(t.kind), "label": t.label, "active": t.active,
            "attached_to": t.attached_to, "group": t.group_id,
            "known_local": t.known_local, "known_shared": t.known_shared,
        })
    return {
        "link_range": link_range,
        "topology_version": topology_version,
        "rebuilds": rebuilds,
        "groups": groups(),
        "link_count": link_count(),
        "bongsu": bongsu,
        "terminals": terminals,
    }
