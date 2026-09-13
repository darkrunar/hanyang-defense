extends RefCounted
## WP-002 AC-01..AC-05, AC-07: bongsu graph, attachment, shared detection,
## disconnection, isolation, dedup, placement rules.

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SOUTH: int = 0
const K_J: int = Placement.Kind.JANGSEUNG
const K_H: int = Placement.Kind.HWACHA
const K_B: int = Placement.Kind.BONGSU
const K_S: int = Placement.Kind.SENSOR

const Z0: int = 0


## Empty field, WP-002 mode, no spawning, stationary enemies, combat on.
static func _field(combat: bool = true) -> Battle:
    var cfg: Config = Config.new()
    cfg.values["targeting_mode"] = "wp002"
    cfg.values["fixture"] = "none"
    cfg.values["combat_enabled"] = combat
    cfg.values["enemy_speed"] = 0.0
    var b: Battle = Battle.new(cfg)
    b.spawning_enabled = false
    return b


static func _dt(b: Battle) -> float:
    return b.config.get_num("fixed_dt")


## Fixture A: H (46,29), B (44,33), S (44,39), enemy at Z0 (900,750).
static func _fixture_a(combat: bool = true) -> Dictionary:
    var b: Battle = _field(combat)
    var f: Dictionary = TestMap.FIXTURE_A
    var h: Placement.Result = b.place_structure(K_H, f["hwacha"], "H")
    var bo: Placement.Result = b.place_structure(K_B, f["bongsu"], "B")
    var se: Placement.Result = b.place_structure(K_S, f["sensor"], "S")
    var slot: int = b.sim.force_spawn(SOUTH, f["enemy"])
    return {"b": b, "h": h.structure, "bongsu": bo.structure, "s": se.structure, "slot": slot}


func run(t: RefCounted) -> void:
    _ac01_links_and_groups(t)
    _ac01_attachment(t)
    _ac01_terminals_do_not_relay(t)
    _ac02_fixture_a_connection_enables_fire(t)
    _ac03_disconnect_before_next_shot(t)
    _ac03_source_loss_and_slot_reuse(t)
    _ac04_isolation_and_range(t)
    _ac05_no_amplification(t)
    _ac07_placement_rules(t)
    _determinism(t)


# --------------------------------------------------------------------- AC-01 ---

func _ac01_links_and_groups(t: RefCounted) -> void:
    t.case("AC-01 bongsu links: exact 180 boundary, just outside, chain, cycle, split, inactive")
    var b: Battle = _field(false)
    # Plaza is x 30..65, y 16..30 (open). Anchors on the 20 px grid.
    var a: Placement.Structure = b.place_structure(K_B, Vector2i(32, 18)).structure   # centre (660,380)
    var c: Placement.Structure = b.place_structure(K_B, Vector2i(41, 18)).structure   # (840,380): exactly 180 from a
    t.eq(b.network.link_count(), 1, "exactly 180 px is linked (boundary inclusive)")
    t.eq(a.group_id, c.group_id, "linked bongsu share a group")
    t.eq(a.group_id, a.id, "group id is the smallest bongsu id of the component")

    var d: Placement.Structure = b.place_structure(K_B, Vector2i(50, 19)).structure   # (1020,400): from c dx=180,dy=20 -> 181.1
    t.eq((b.network.edges[d.id] as Array).size(), 0, "181.1 px is not linked (just outside)")
    t.ne(d.group_id, a.group_id, "unlinked bongsu forms its own group")

    # Chain: e links to d only (multi-hop reaches a? no: d is isolated from c). Build e near d.
    var e: Placement.Structure = b.place_structure(K_B, Vector2i(58, 19)).structure   # (1180,400): 160 from d
    t.eq(e.group_id, d.group_id, "chain d-e forms one group")
    # Cycle: three mutually linked bongsu must not loop forever and form one group.
    var cyc: Battle = _field(false)
    var p: Placement.Structure = cyc.place_structure(K_B, Vector2i(34, 18)).structure  # (700,380)
    var q: Placement.Structure = cyc.place_structure(K_B, Vector2i(40, 18)).structure  # (820,380): 120
    var r: Placement.Structure = cyc.place_structure(K_B, Vector2i(37, 24)).structure  # (760,500): to p 134, to q 134
    t.eq(cyc.network.link_count(), 3, "triangle cycle has 3 edges")
    t.check(p.group_id == q.group_id and q.group_id == r.group_id, "cycle collapses into one group")
    t.eq(cyc.network.groups().size(), 1, "one group total")

    # Inactive node splits the chain.
    var split: Battle = _field(false)
    var s1: Placement.Structure = split.place_structure(K_B, Vector2i(32, 18)).structure  # (660,380)
    var s2: Placement.Structure = split.place_structure(K_B, Vector2i(40, 18)).structure  # (820,380): 160
    var s3: Placement.Structure = split.place_structure(K_B, Vector2i(48, 18)).structure  # (980,380): 160 from s2, 320 from s1
    t.eq(s1.group_id, s3.group_id, "s1 reaches s3 through s2 (multi-hop)")
    var v0: int = split.network.topology_version
    split.set_active(s2.id, false)
    t.check(split.network.topology_version > v0, "deactivating a relay changes the topology version")
    t.ne(s1.group_id, s3.group_id, "inactive relay splits the component")
    t.eq(s2.group_id, -1, "inactive bongsu has no group")
    t.eq(split.network.link_count(), 0, "no edges through an inactive node")
    split.set_active(s2.id, true)
    t.eq(s1.group_id, s3.group_id, "reactivation restores the component")


func _ac01_attachment(t: RefCounted) -> void:
    t.case("AC-01 terminal attachment: nearest, ties by id, none beyond 180, re-attach on change")
    var b: Battle = _field(false)
    var far: Placement.Structure = b.place_structure(K_B, Vector2i(32, 18)).structure   # (660,380)
    var near: Placement.Structure = b.place_structure(K_B, Vector2i(40, 18)).structure  # (820,380)
    var sensor: Placement.Structure = b.place_structure(K_S, Vector2i(44, 18)).structure  # (900,380): near 80, far 240
    t.eq(sensor.attached_to, near.id, "sensor attaches to the nearest bongsu")
    t.eq(sensor.group_id, near.group_id, "sensor inherits the group")
    var h: Placement.Structure = b.place_structure(K_H, Vector2i(36, 24)).structure       # (740,500): far 144.2, near 144.2 -> tie
    t.eq(h.attached_to, far.id, "equidistant bongsu: lowest id wins")
    var lonely: Placement.Structure = b.place_structure(K_S, Vector2i(62, 26)).structure  # (1260,540): near 466
    t.eq(lonely.attached_to, -1, "no bongsu within 180: unattached")
    t.eq(lonely.group_id, -1, "unattached terminal has no group")
    # Exactly 180 attaches; deactivate `near` -> sensor re-attaches to nothing (far is 240).
    b.set_active(near.id, false)
    t.eq(sensor.attached_to, -1, "re-attach after change: nearest active is out of range")
    t.eq(h.attached_to, far.id, "tie loser becomes the only candidate after the change")
    b.set_active(near.id, true)
    t.eq(sensor.attached_to, near.id, "re-attach after recovery")
    var edge: Battle = _field(false)
    var eb: Placement.Structure = edge.place_structure(K_B, Vector2i(32, 18)).structure    # (660,380)
    var es: Placement.Structure = edge.place_structure(K_S, Vector2i(41, 18)).structure    # (840,380): exactly 180
    t.eq(es.attached_to, eb.id, "terminal exactly at 180 px attaches")
    var es2: Placement.Structure = edge.place_structure(K_S, Vector2i(41, 20)).structure   # (840,420): 184.4
    t.eq(es2.attached_to, -1, "terminal at 184.4 px does not attach")


func _ac01_terminals_do_not_relay(t: RefCounted) -> void:
    t.case("AC-01 terminals never relay or merge groups")
    var b: Battle = _field(true)
    var left: Placement.Structure = b.place_structure(K_B, Vector2i(32, 18)).structure   # (660,380)
    var right: Placement.Structure = b.place_structure(K_B, Vector2i(48, 18)).structure  # (980,380): 320 apart
    var mid_sensor: Placement.Structure = b.place_structure(K_S, Vector2i(40, 18)).structure  # (820,380): 160 to both
    var mid_h: Placement.Structure = b.place_structure(K_H, Vector2i(40, 24)).structure  # (820,500): 200 to both -> none
    t.ne(left.group_id, right.group_id, "a sensor between two nets does not merge them")
    t.eq(mid_sensor.attached_to, left.id, "sensor attaches to exactly one bongsu (lowest id on tie)")
    t.eq(mid_h.attached_to, -1, "hwacha 200 px from both bongsu attaches to none")
    t.eq(b.network.groups().size(), 2, "two groups remain")
    # A hwacha attached to `right` must not see what the mid sensor (in `left`) sees.
    var hr: Placement.Structure = b.place_structure(K_H, Vector2i(52, 19)).structure     # (1060,400): right 82
    t.eq(hr.group_id, right.group_id, "hwacha attached to the right net")
    b.sim.force_spawn(SOUTH, Vector2(820.0, 300.0))   # 80 px from the mid sensor, 254 from hr
    b.step(_dt(b))
    t.eq(hr.known_shared, 0, "no shared detection crosses from the other group")
    t.eq(mid_sensor.group_id, left.group_id, "mid sensor belongs to the left group only")


# --------------------------------------------------------------------- AC-02 ---

func _ac02_fixture_a_connection_enables_fire(t: RefCounted) -> void:
    t.case("AC-02 fixture A: no fire disconnected, fire once connected, same position/seed/cooldown")
    var f: Dictionary = _fixture_a(true)
    var b: Battle = f["b"]
    var h: Placement.Structure = f["h"]
    var bongsu: Placement.Structure = f["bongsu"]
    var s: Placement.Structure = f["s"]
    var dist_h: float = h.center.distance_to(TestMap.FIXTURE_A["enemy"])
    t.check(dist_h > 100.0 and dist_h < 200.0, "enemy is outside local 100 and inside range 200 (%.2f px)" % dist_h)
    t.check(s.center.distance_to(TestMap.FIXTURE_A["enemy"]) <= 140.0, "enemy is inside the sensor range")
    t.eq(h.attached_to, bongsu.id, "H attached to B")
    t.eq(s.attached_to, bongsu.id, "S attached to B")

    # 1. B inactive: known 0, shots 0 over 3 s.
    b.set_active(bongsu.id, false)
    t.eq(h.cooldown_left, 0.0, "hwacha starts ready")
    b.run_for(3.0)
    t.eq(b.network.known_count(h.id), 0, "disconnected: hwacha knows nothing")
    t.eq(h.shots_fired, 0, "disconnected: no volley over 3 s")
    t.eq(h.wait_reason, "표적 없음", "wait reason reported")
    t.eq(h.cooldown_left, 0.0, "cooldown untouched while holding fire")

    # 2. B active: shared 1, first volley on the very next tick.
    b.set_active(bongsu.id, true)
    b.step(_dt(b))
    t.eq(h.known_shared, 1, "connected: one shared enemy")
    t.eq(h.known_local, 0, "connected: still zero local")
    t.eq(h.shots_fired, 1, "connected: fired on the first tick")
    t.eq(h.last_zone, Z0, "fired at Z0")
    t.eq(h.last_target_shared, 1, "target came through the network")
    t.eq(b.hwacha.shared_only_shots, 1, "counted as a shared-only volley")
    t.eq(b.sim.hp[f["slot"]], 60.0 - 34.0, "enemy took one volley (no damage bonus from the network)")


# --------------------------------------------------------------------- AC-03 ---

func _ac03_disconnect_before_next_shot(t: RefCounted) -> void:
    t.case("AC-03 disconnection is honoured before the next volley; local fire continues; recovery re-acquires")
    var f: Dictionary = _fixture_a(true)
    var b: Battle = f["b"]
    var h: Placement.Structure = f["h"]
    var bongsu: Placement.Structure = f["bongsu"]
    var dt: float = _dt(b)
    b.step(dt)
    t.eq(h.shots_fired, 1, "first volley through the network")
    # Disconnect while the cooldown runs; when ready again there must be no shot.
    b.set_active(bongsu.id, false)
    var cd_after_toggle: float = h.cooldown_left
    t.check(cd_after_toggle > 0.0, "cooldown is running after the volley")
    b.run_for(2.0)
    t.eq(h.shots_fired, 1, "no stale shared volley after disconnection (ready for >1 s)")
    t.eq(h.cooldown_left, 0.0, "cooldown ran down normally (not reset by the toggle)")
    t.eq(b.network.known_count(h.id), 0, "known set is empty while disconnected")
    # Local fire while disconnected. Fixture A's H (940,600) is >= 112 px from
    # every WP-001 candidate zone, so no enemy can be both local (<= 100) and
    # inside a zone for it. The contract's step 4 is therefore shown with an
    # auxiliary hwacha H2 standing in the east lane (Z1 is 30 px away), fed by
    # its own local enemy while the bongsu stays inactive.
    # H2 at (980,840): Z1 centre 90 px (local), fixture enemy at (900,750) 120 px (not local).
    var h2: Placement.Structure = b.place_structure(K_H, Vector2i(48, 41), "H2").structure   # (980,840)
    var local_slot: int = b.sim.force_spawn(SOUTH, Vector2(980.0, 750.0))                    # Z1 centre, 90 px from H2
    b.step(dt)
    t.eq(h2.group_id, -1, "H2 has no group while the bongsu is inactive")
    t.eq(h2.known_local, 1, "H2 detects the local enemy without any network")
    t.eq(h2.shots_fired, 1, "H2 fires locally while disconnected")
    t.eq(h2.last_target_local, 1, "…and the target was local")
    t.eq(h.shots_fired, 1, "fixture hwacha H still did not fire at the shared-only enemy")
    b.sim.apply_blast(Vector2(980.0, 750.0), 5.0, 9999.0)
    # Recovery: shared target re-acquired on the next ready tick.
    var shots_before: int = h.shots_fired
    b.set_active(bongsu.id, true)
    b.run_for(1.0)
    t.check(h.shots_fired > shots_before, "recovery: shared target re-acquired and fired (%d -> %d)" % [shots_before, h.shots_fired])
    t.check(b.sim.alive[local_slot] == 0, "local test enemy removed")
    t.check(h2.active, "H2 still active")


func _ac03_source_loss_and_slot_reuse(t: RefCounted) -> void:
    t.case("AC-03 last source gone -> dropped; another source keeps it; slot reuse is not confused")
    var b: Battle = _field(false)
    var bongsu: Placement.Structure = b.place_structure(K_B, Vector2i(44, 33)).structure   # (900,680)
    var h: Placement.Structure = b.place_structure(K_H, Vector2i(46, 29)).structure        # (940,600)
    var s1: Placement.Structure = b.place_structure(K_S, Vector2i(44, 39)).structure       # (900,800)
    var s2: Placement.Structure = b.place_structure(K_S, Vector2i(48, 37)).structure       # (980,760): to bongsu 113, to enemy 80.6
    var slot: int = b.sim.force_spawn(SOUTH, Vector2(900.0, 750.0))
    var id0: int = b.sim.enemy_id(slot)
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 1, "known through two sensors counts once")
    b.set_active(s1.id, false)
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 1, "other sensor keeps the target after one source is lost")
    b.set_active(s2.id, false)
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 0, "last source gone: target dropped immediately")
    b.set_active(s1.id, true)
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 1, "source back: target re-acquired")
    # Move the enemy out of sensor range: dropped without any command.
    b.sim.pos_x[slot] = 1300.0
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 0, "enemy left the sensor range: dropped")
    b.sim.pos_x[slot] = 900.0
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 1, "back in range: known again")
    # Death, then slot reuse elsewhere: the new individual must not inherit knowledge.
    b.sim.apply_blast(Vector2(900.0, 750.0), 5.0, 9999.0)
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 0, "dead enemy is not known")
    var slot2: int = b.sim.force_spawn(SOUTH, Vector2(1300.0, 500.0))   # far from every sensor
    t.eq(slot2, slot, "pool reused the same slot")
    t.ne(b.sim.enemy_id(slot2), id0, "reused slot has a new individual id")
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 0, "new individual in the reused slot is not known")
    t.check(not b.sim.is_id_alive(id0), "old id is dead even though the slot is alive again")
    t.eq(b.path.path_version, 2, "sensor/bongsu commands never touched the path field")


# --------------------------------------------------------------------- AC-04 ---

func _ac04_isolation_and_range(t: RefCounted) -> void:
    t.case("AC-04 other groups, out-of-range zones, partial observation, exact detection edges")
    # Detection edges: sensor 140 exact / 140.01 outside; hwacha local 100 exact / outside.
    var e: Battle = _field(false)
    var eb: Placement.Structure = e.place_structure(K_B, Vector2i(44, 33)).structure     # (900,680)
    var es: Placement.Structure = e.place_structure(K_S, Vector2i(44, 39)).structure     # (900,800)
    var eh: Placement.Structure = e.place_structure(K_H, Vector2i(46, 29)).structure     # (940,600)
    var on_edge: int = e.sim.force_spawn(SOUTH, Vector2(900.0 + 140.0, 800.0))
    var off_edge: int = e.sim.force_spawn(SOUTH, Vector2(900.0 + 140.5, 800.0))
    var loc_on: int = e.sim.force_spawn(SOUTH, Vector2(940.0, 700.0))            # exactly 100 from H
    var loc_off: int = e.sim.force_spawn(SOUTH, Vector2(940.0, 700.5))
    e.step(_dt(e))
    var seen: Dictionary = e.network.sensor_seen[es.id]
    t.check(seen.has(e.sim.enemy_id(on_edge)), "sensor sees an enemy exactly at 140 px")
    t.check(not seen.has(e.sim.enemy_id(off_edge)), "sensor does not see 140.5 px")
    var local: Dictionary = e.network.hwacha_local[eh.id]
    t.check(local.has(e.sim.enemy_id(loc_on)), "hwacha local detection exactly at 100 px")
    t.check(not local.has(e.sim.enemy_id(loc_off)), "hwacha local does not see 100.5 px")
    t.eq(eb.active, true, "bongsu still active")

    # Separate high-density net is ignored; shared target outside range is not fired at.
    var b: Battle = _field(true)
    var bongsu: Placement.Structure = b.place_structure(K_B, Vector2i(44, 33)).structure   # (900,680)
    var h: Placement.Structure = b.place_structure(K_H, Vector2i(46, 29)).structure        # (940,600)
    var s: Placement.Structure = b.place_structure(K_S, Vector2i(44, 39)).structure        # (900,800)
    # Other net far east: bongsu + sensor near Z6 (1460,580) with 5 enemies.
    var ob: Placement.Structure = b.place_structure(K_B, Vector2i(64, 26)).structure       # (1300,540)
    var os: Placement.Structure = b.place_structure(K_S, Vector2i(66, 24)).structure       # (1340,500): 56 to ob; to Z5 120
    for i: int in range(5):
        b.sim.force_spawn(SOUTH, Vector2(1460.0 + float(i) * 3.0, 500.0))   # Z5
    var mine: int = b.sim.force_spawn(SOUTH, Vector2(900.0, 750.0))   # Z0, 1 enemy
    t.ne(h.group_id, ob.group_id, "two separate groups")
    b.step(_dt(b))
    t.eq(h.known_shared, 1, "hwacha knows only its own group's single enemy")
    t.eq(h.last_zone, Z0, "fires at its own Z0 (1) not the other net's Z5 (5)")
    t.eq(h.shots_fired, 1, "one volley")
    t.check(os.group_id == ob.group_id and os.group_id != h.group_id, "other sensor is in the other group")
    t.eq(b.sim.alive[mine], 1, "enemy survives one volley (hp 60 > 34)")

    # Shared but out of range: sensor sees Z2 (940,1000) enemies; H range 200 to Z2 is 400 -> no fire.
    var c: Battle = _field(true)
    var cb: Placement.Structure = c.place_structure(K_B, Vector2i(44, 33)).structure       # (900,680)
    var ch: Placement.Structure = c.place_structure(K_H, Vector2i(46, 29)).structure       # (940,600)
    var cs: Placement.Structure = c.place_structure(K_S, Vector2i(44, 45)).structure       # (900,920): to cb 240 -> needs relay
    var cb2: Placement.Structure = c.place_structure(K_B, Vector2i(44, 41)).structure      # (900,840): cb 160, cs 80
    for i: int in range(3):
        c.sim.force_spawn(SOUTH, Vector2(940.0 + float(i) * 3.0, 1000.0))   # Z2 centre, 80 from cs
    c.step(_dt(c))
    t.eq(ch.group_id, cs.group_id, "sensor relayed through the second bongsu")
    t.eq(ch.known_shared, 3, "hwacha knows the three shared enemies")
    t.eq(ch.shots_fired, 0, "but Z2 is 400 px away: no volley beyond the firing range")
    t.eq(ch.wait_reason, "알려진 표적이 사거리 밖", "wait reason explains it")
    t.check(cb.active and cb2.active, "both relays active")

    # Partial observation: zone Z7 (960,310) r=70; sensor covers only part of it.
    var p: Battle = _field(false)
    var pb: Placement.Structure = p.place_structure(K_B, Vector2i(46, 17)).structure       # (940,360)
    var ph: Placement.Structure = p.place_structure(K_H, Vector2i(52, 19)).structure       # (1060,400): local 100 reaches x>=960 only near
    var ps: Placement.Structure = p.place_structure(K_S, Vector2i(41, 18)).structure       # (840,380): 140 reaches x<=980 at y=310? dist to (900,310)=92 ok, to (1020,310)=193 no
    var hidden: int = p.sim.force_spawn(SOUTH, Vector2(1020.0, 310.0))   # in Z7 (dist 60), 193 from sensor, 98.5 from H? (1060,400)->(1020,310)=98.5 -> local!
    p.sim.pos_x[hidden] = 1025.0   # (1025,310): H dist 96.6 still local; move further: use y=300
    p.sim.pos_y[hidden] = 300.0    # (1025,300)->H (1060,400): 105.9 -> outside local; Z7 dist 65.8 inside; sensor 201 outside
    var visible: int = p.sim.force_spawn(SOUTH, Vector2(900.0, 310.0))    # Z7 dist 60; sensor 92 -> seen
    p.step(_dt(p))
    var out_local: PackedInt32Array = PackedInt32Array()
    var counts: PackedInt32Array = p.network.known_zone_counts(ph, p.density, p.sim, out_local)
    t.eq(p.density.counts[7], 2, "global density of Z7 is 2")
    t.eq(counts[7], 1, "hwacha counts only the observed enemy in Z7 (no global leak)")
    t.check(pb.active and ps.active, "relay and sensor active")
    t.check(p.sim.alive[visible] == 1 and p.sim.alive[hidden] == 1, "both enemies alive")


# --------------------------------------------------------------------- AC-05 ---

func _ac05_no_amplification(t: RefCounted) -> void:
    t.case("AC-05 duplicate sensors / local overlap / cycles do not amplify; earlier kills excluded")
    var one: Dictionary = _run_dup_case(1)
    var two: Dictionary = _run_dup_case(2)
    var cyc: Dictionary = _run_dup_case(3)
    t.eq(two["known"], one["known"], "two sensors seeing the same enemies: same known count")
    t.eq(two["zone"], one["zone"], "same zone density")
    t.eq(two["shots"], one["shots"], "same number of volleys over the window")
    t.eq(two["kills"], one["kills"], "same kills")
    t.eq(cyc["known"], one["known"], "three bongsu in a cycle: no amplification")
    t.eq(cyc["shots"], one["shots"], "cycle: same volleys")
    t.note("dup case: known=%d zone=%d shots=%d kills=%d" % [one["known"], one["zone"], one["shots"], one["kills"]])

    # Local + shared overlap counts once.
    var b: Battle = _field(false)
    var bongsu: Placement.Structure = b.place_structure(K_B, Vector2i(44, 33)).structure   # (900,680)
    var h: Placement.Structure = b.place_structure(K_H, Vector2i(46, 29)).structure        # (940,600)
    var s: Placement.Structure = b.place_structure(K_S, Vector2i(44, 33 + 4)).structure    # (900,760)? anchor (44,37) -> centre (900,760); to bongsu 80
    var slot: int = b.sim.force_spawn(SOUTH, Vector2(930.0, 690.0))   # H dist 90.5 (local), S dist 76 (shared)
    b.step(_dt(b))
    t.eq(b.network.known_count(h.id), 1, "enemy seen locally and by a sensor counts once")
    t.eq(h.known_local, 1, "…as local")
    t.eq(h.known_shared, 0, "…and not again as shared")
    t.check(bongsu.active and s.active and b.sim.alive[slot] == 1, "setup intact")

    # Earlier hwacha's kills excluded for the later hwacha in the same tick.
    var k: Battle = _field(true)
    var kb: Placement.Structure = k.place_structure(K_B, Vector2i(44, 33)).structure       # (900,680)
    var h1: Placement.Structure = k.place_structure(K_H, Vector2i(46, 29)).structure       # (940,600) id lower
    var h2: Placement.Structure = k.place_structure(K_H, Vector2i(41, 29)).structure       # (840,600): to Z0 (900,750) 161.5 in range; bongsu 100
    var ks: Placement.Structure = k.place_structure(K_S, Vector2i(44, 39)).structure       # (900,800)
    for i: int in range(4):
        k.sim.force_spawn(SOUTH, Vector2(900.0 + float(i) * 2.0, 750.0), 1.0)   # hp 1: die on first volley
    k.step(_dt(k))
    t.eq(h1.shots_fired, 1, "first hwacha fired")
    t.eq(h1.kills, 4, "first hwacha killed all four")
    t.eq(h2.shots_fired, 0, "second hwacha saw no living enemy after the first volley")
    t.check(kb.active and ks.active, "setup intact")


static func _run_dup_case(variant: int) -> Dictionary:
    var b: Battle = _field(true)
    var bongsu: Placement.Structure = b.place_structure(K_B, Vector2i(44, 33)).structure   # (900,680)
    var h: Placement.Structure = b.place_structure(K_H, Vector2i(46, 29)).structure        # (940,600)
    b.place_structure(K_S, Vector2i(44, 39))                                               # (900,800)
    if variant >= 2:
        b.place_structure(K_S, Vector2i(41, 38))                                           # (840,780): to bongsu 116, to Z0 67
    if variant == 3:
        b.place_structure(K_B, Vector2i(40, 33))                                           # (820,680): 80 to bongsu
        b.place_structure(K_B, Vector2i(42, 37))                                           # (860,760): 89 / 89 -> cycle
    for i: int in range(6):
        b.sim.force_spawn(SOUTH, Vector2(895.0 + float(i) * 2.0, 750.0))
    b.step(_dt(b))
    var known: int = b.network.known_count(h.id)
    var out_local: PackedInt32Array = PackedInt32Array()
    var zone: int = b.network.known_zone_counts(h, b.density, b.sim, out_local)[Z0]
    b.run_for(2.0)
    return {"known": known, "zone": zone, "shots": h.shots_fired, "kills": h.kills, "bongsu": bongsu.id}


# --------------------------------------------------------------------- AC-07 ---

func _ac07_placement_rules(t: RefCounted) -> void:
    t.case("AC-07 bongsu/sensor placement: rejections, non-blocking, inactive keeps footprint, no path change")
    var b: Battle = _field(false)
    var pv: int = b.path.path_version
    var bo: Placement.Result = b.place_structure(K_B, Vector2i(44, 36))   # inside the south-west lane
    t.check(bo.ok, "bongsu placed inside a lane")
    t.eq(b.path.path_version, pv, "bongsu placement does not change the path version")
    t.check(b.path.route_reachable(SOUTH), "lane stays passable (non-blocking)")
    t.check(b.path.is_reachable_index(b.grid.idx(44, 36)), "footprint cell still reachable")
    var overlap: Placement.Result = b.place_structure(K_S, Vector2i(44, 36))
    t.eq(overlap.reason, Placement.Reject.STRUCTURE_OVERLAP, "sensor over the bongsu is refused")
    b.set_active(bo.structure.id, false)
    var overlap2: Placement.Result = b.place_structure(K_S, Vector2i(44, 37))
    t.eq(overlap2.reason, Placement.Reject.STRUCTURE_OVERLAP, "inactive structure keeps its footprint")
    t.eq(b.path.path_version, pv, "activation change does not change the path version")
    var terrain: Placement.Result = b.place_structure(K_S, Vector2i(46, 36))
    t.eq(terrain.reason, Placement.Reject.TERRAIN_BLOCKED, "sensor on the solid block is refused")
    var oob: Placement.Result = b.place_structure(K_B, Vector2i(95, 26))
    t.eq(oob.reason, Placement.Reject.OUT_OF_BOUNDS, "bongsu crossing the edge is refused")
    var occ_slot: int = b.sim.force_spawn(SOUTH, b.grid.cell_center(48, 36))
    var occ: Placement.Result = b.place_structure(K_B, Vector2i(48, 36))
    t.eq(occ.reason, Placement.Reject.ENEMY_OCCUPIES_CELL, "bongsu onto a living enemy is refused")
    t.check(not b.placement.preview(K_B, Vector2i(48, 36), b.sim), "preview agrees")
    b.sim.apply_blast(b.grid.cell_center(48, 36), 5.0, 9999.0)
    t.check(b.place_structure(K_B, Vector2i(48, 36)).ok, "accepted once the cell is clear")
    var before: int = b.placement.structures.size()
    t.check(b.remove_structure(bo.structure.id).ok, "removal succeeds")
    t.eq(b.placement.structures.size(), before - 1, "removal frees the entry")
    t.check(b.place_structure(K_S, Vector2i(44, 36)).ok, "removed footprint is placeable again")
    t.eq(b.path.path_version, pv, "none of this touched the path version")
    t.check(b.sim.alive[occ_slot] == 0, "test enemy cleared")
    # Unknown id handling.
    t.check(not b.set_active(9999, false), "unknown structure id is refused for activation")
    t.check(not b.remove_structure(9999).ok, "unknown structure id is refused for removal")


# -------------------------------------------------------------- determinism ---

func _determinism(t: RefCounted) -> void:
    t.case("same seed + same command sequence reproduce groups, known ids, shots (fixture B)")
    var a: Dictionary = _scripted(20260913)
    var b: Dictionary = _scripted(20260913)
    var c: Dictionary = _scripted(4242)
    t.eq(a["groups"], b["groups"], "groups reproduce")
    t.eq(a["known"], b["known"], "known ids per hwacha reproduce")
    t.eq(a["shots"], b["shots"], "shots reproduce")
    t.eq(a["shared_only"], b["shared_only"], "shared-only volleys reproduce")
    t.eq(a["kills"], b["kills"], "kills reproduce")
    t.ne(c["known"], a["known"], "a different seed differs")
    t.check(int(a["shared_only"]) > 0, "fixture B produces shared-only volleys (%d)" % int(a["shared_only"]))
    # Reset clears the network and restores the fixture.
    var cfg: Config = Config.new()
    cfg.values["seed"] = 20260913
    var r: Battle = Battle.new(cfg)
    r.run_for(5.0)
    r.place_structure(K_B, Vector2i(36, 24))
    r.set_active(r.placement.bongsus()[0].id, false)
    r.reset()
    t.eq(r.placement.structures.size(), 16, "reset restores exactly the 16 fixture structures")
    t.eq(r.sim.alive_count, 0, "reset clears enemies")
    t.eq(r.hwacha.shots_total, 0, "reset clears shot counters")
    t.eq(r.network.known_count(r.placement.hwachas()[0].id), 0, "reset clears known sets")
    var all_active: bool = true
    for id: int in r.placement.structures:
        if not (r.placement.structures[id] as Placement.Structure).active:
            all_active = false
    t.check(all_active, "reset restores activation")


static func _scripted(seed_value: int) -> Dictionary:
    var cfg: Config = Config.new()
    cfg.values["seed"] = seed_value
    var b: Battle = Battle.new(cfg)   # fixture B, wp002
    b.run_for(12.0)
    var b8: Placement.Structure = b.placement.bongsus()[7]
    b.set_active(b8.id, false)
    b.run_for(3.0)
    b.set_active(b8.id, true)
    b.run_for(5.0)
    var known: Array = []
    var shots: Array = []
    var kills: Array = []
    for h: Placement.Structure in b.placement.hwachas():
        known.append(b.network.known_ids(h.id))
        shots.append(h.shots_fired)
        kills.append(h.kills)
    return {
        "groups": b.network.groups(),
        "known": known,
        "shots": shots,
        "kills": kills,
        "shared_only": b.hwacha.shared_only_shots,
    }
