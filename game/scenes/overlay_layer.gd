extends Node2D
## Dynamic debug overlay drawn above the enemies: density zones, structures,
## hwacha ranges and volleys, the bongsu network (links, attachments, sensor
## and local detection radii), route labels, the placement cursor ghost and
## a hover panel for the structure under the cursor (WP-002 AC-07).

const Battle := preload("res://game/core/battle.gd")
const Placement := preload("res://game/core/placement.gd")
const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const COLOR_ZONE: Color = Color(0.55, 0.80, 1.00, 0.55)
const COLOR_ZONE_TARGETED: Color = Color(1.00, 0.45, 0.25, 0.95)
const COLOR_JANGSEUNG: Color = Color(0.55, 0.16, 0.14)
const COLOR_JANGSEUNG_POST: Color = Color(0.85, 0.62, 0.40)
const COLOR_HWACHA: Color = Color(0.72, 0.52, 0.22)
const COLOR_HWACHA_RANGE: Color = Color(0.72, 0.52, 0.22, 0.22)
const COLOR_HWACHA_LOCAL: Color = Color(0.95, 0.80, 0.40, 0.35)
const COLOR_HWACHA_FIRE: Color = Color(1.00, 0.55, 0.15, 0.85)
const COLOR_BLAST: Color = Color(1.00, 0.70, 0.30, 0.55)
const COLOR_BONGSU: Color = Color(0.85, 0.35, 0.20)
const COLOR_BONGSU_FLAME: Color = Color(1.00, 0.75, 0.25)
const COLOR_SENSOR: Color = Color(0.35, 0.75, 0.95)
const COLOR_SENSOR_RANGE: Color = Color(0.35, 0.75, 0.95, 0.30)
const COLOR_LINK: Color = Color(1.00, 0.60, 0.25, 0.85)
const COLOR_ATTACH: Color = Color(0.70, 0.85, 1.00, 0.55)
const COLOR_INACTIVE: Color = Color(0.45, 0.45, 0.45)
const COLOR_GHOST_OK: Color = Color(0.40, 0.95, 0.45, 0.55)
const COLOR_GHOST_BAD: Color = Color(1.00, 0.30, 0.30, 0.55)
const COLOR_TEXT: Color = Color(0.92, 0.90, 0.85)
const COLOR_PANEL: Color = Color(0.0, 0.0, 0.0, 0.72)

var battle: Battle = null
var font: Font = null
var show_zones: bool = true
var show_ranges: bool = true
var show_cursor: bool = true
var place_mode: int = 0
var recent_shots: Array = []   # [aim, radius, age]
## Scripted captures have no real cursor; set this to a world position to draw
## the hover panel for the structure there (Vector2.INF = none).
var hover_override: Vector2 = Vector2.INF


func _draw() -> void:
    if battle == null:
        return
    var counts: PackedInt32Array = battle.density.counts
    var targeted: Dictionary = {}
    for s: Placement.Structure in battle.placement.hwachas():
        if s.last_zone >= 0 and battle.combat_enabled:
            targeted[s.last_zone] = true

    if show_zones:
        for z: DensityDetector.Zone in battle.density.zones:
            var col: Color = COLOR_ZONE_TARGETED if targeted.has(z.id) else COLOR_ZONE
            draw_arc(z.center, z.radius, 0.0, TAU, 40, col, 1.5)
            draw_string(font, z.center + Vector2(-16.0, -z.radius - 6.0),
                "Z%d:%d" % [z.id, counts[z.id]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

    # --- bongsu network: links first (under everything), then attachments ---
    var net := battle.network
    for b: Placement.Structure in battle.placement.bongsus():
        if not net.edges.has(b.id):
            continue
        for nb_id: int in net.edges[b.id]:
            if nb_id > b.id:
                var nb: Placement.Structure = battle.placement.get_structure(nb_id)
                if nb != null:
                    draw_line(b.center, nb.center, COLOR_LINK, 2.0)
    for t: Placement.Structure in battle.placement.sensors() + battle.placement.hwachas():
        if t.attached_to >= 0:
            var b: Placement.Structure = battle.placement.get_structure(t.attached_to)
            if b != null:
                _draw_dashed(t.center, b.center, COLOR_ATTACH, 1.0, 8.0)

    for s: Placement.Structure in battle.placement.jangseungs():
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        draw_rect(r, COLOR_JANGSEUNG, true)
        draw_rect(Rect2(s.center - Vector2(5.0, 18.0), Vector2(10.0, 36.0)), COLOR_JANGSEUNG_POST, true)
        draw_rect(r, Color.BLACK, false, 2.0)
        draw_string(font, s.center + Vector2(-16.0, -24.0), "장승", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)

    for s: Placement.Structure in battle.placement.bongsus():
        var col: Color = COLOR_BONGSU if s.active else COLOR_INACTIVE
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        draw_rect(r, col, true)
        draw_rect(r, Color.BLACK, false, 2.0)
        if s.active:
            draw_circle(s.center + Vector2(0.0, -8.0), 7.0, COLOR_BONGSU_FLAME)
        if show_ranges and s.active:
            draw_arc(s.center, net.link_range, 0.0, TAU, 64, Color(COLOR_LINK.r, COLOR_LINK.g, COLOR_LINK.b, 0.10), 1.0)
        draw_string(font, s.center + Vector2(-30.0, -24.0), "%s g%s" % [s.label, str(s.group_id) if s.group_id >= 0 else "-"],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col if s.active else COLOR_INACTIVE)

    for s: Placement.Structure in battle.placement.sensors():
        var col: Color = COLOR_SENSOR if s.active else COLOR_INACTIVE
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        draw_rect(r, col, true)
        draw_rect(r, Color.BLACK, false, 2.0)
        draw_arc(s.center, 11.0, 0.0, TAU, 24, Color.BLACK, 2.0)
        draw_arc(s.center, 6.0, 0.0, TAU, 16, Color.BLACK, 2.0)
        if show_ranges and s.active and s.group_id >= 0:
            draw_arc(s.center, s.detect_range, 0.0, TAU, 64, COLOR_SENSOR_RANGE, 1.5)
        draw_string(font, s.center + Vector2(-34.0, -24.0), "%s g%s" % [s.label, str(s.group_id) if s.group_id >= 0 else "-"],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

    for s: Placement.Structure in battle.placement.hwachas():
        var col: Color = COLOR_HWACHA if s.active else COLOR_INACTIVE
        if show_ranges and s.active:
            draw_arc(s.center, s.fire_range, 0.0, TAU, 64, COLOR_HWACHA_RANGE, 1.0)
            if battle.targeting_mode == "wp002":
                draw_arc(s.center, s.detect_range, 0.0, TAU, 48, COLOR_HWACHA_LOCAL, 1.5)
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        draw_rect(r, col, true)
        draw_rect(r, Color.BLACK, false, 2.0)
        draw_circle(s.center + Vector2(-12.0, 14.0), 5.0, Color.BLACK)
        draw_circle(s.center + Vector2(12.0, 14.0), 5.0, Color.BLACK)
        if s.last_zone >= 0 and battle.combat_enabled and s.active:
            draw_line(s.center, s.last_aim, COLOR_HWACHA_FIRE, 3.0 if s.muzzle_timer > 0.0 else 1.0)
        var tag: String = s.label
        if battle.targeting_mode == "wp002":
            tag += " g%s L%d/S%d" % [str(s.group_id) if s.group_id >= 0 else "-", s.known_local, s.known_shared]
        draw_string(font, s.center + Vector2(-30.0, -24.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT if s.active else COLOR_INACTIVE)

    for shot: Array in recent_shots:
        var age: float = shot[2]
        var a: float = 1.0 - age / 0.35
        draw_arc(shot[0], shot[1] * (0.6 + 0.4 * (1.0 - a)), 0.0, TAU, 32,
            Color(COLOR_BLAST.r, COLOR_BLAST.g, COLOR_BLAST.b, COLOR_BLAST.a * a), 3.0)

    for i: int in range(TestMap.ROUTES.size()):
        var a: Vector2i = TestMap.ROUTES[i][2]
        var b: Vector2i = TestMap.ROUTES[i][3]
        var mid: Vector2 = (Vector2(a) + Vector2(b) + Vector2.ONE) * 0.5 * TerrainGrid.CELL_SIZE
        var label_pos: Vector2 = mid
        if a.y == TestMap.HEIGHT - 1:
            label_pos += Vector2(-36.0, -30.0)
        elif a.x == 0:
            label_pos += Vector2(6.0, -80.0)
        else:
            label_pos += Vector2(-96.0, -80.0)
        draw_string(font, label_pos, "%s %d" % [TestMap.ROUTES[i][1], battle.sim.route_alive[i]],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TestMap.route_color(i))

    if show_cursor:
        var mouse: Vector2 = get_global_mouse_position()
        var anchor: Vector2i = battle.placement.anchor_for_world(mouse)
        var ok: bool = battle.placement.preview(place_mode, anchor, battle.sim)
        var top_left: Vector2 = Vector2(anchor) * TerrainGrid.CELL_SIZE
        draw_rect(Rect2(top_left, Vector2(40.0, 40.0)), COLOR_GHOST_OK if ok else COLOR_GHOST_BAD, false, 2.0)
        _draw_hover_panel(mouse)
    elif hover_override != Vector2.INF:
        _draw_hover_panel(hover_override)


func _draw_dashed(a: Vector2, b: Vector2, col: Color, width: float, dash: float) -> void:
    var len: float = a.distance_to(b)
    if len < 1.0:
        return
    var dir: Vector2 = (b - a) / len
    var pos: float = 0.0
    while pos < len:
        var seg: float = minf(dash, len - pos)
        draw_line(a + dir * pos, a + dir * (pos + seg), col, width)
        pos += dash * 2.0


## Hover panel: the structure under the cursor with its network state,
## detection sources, target source and wait reason (AC-07).
func _draw_hover_panel(mouse: Vector2) -> void:
    var s: Placement.Structure = battle.placement.structure_at_world(mouse)
    if s == null:
        return
    var lines: PackedStringArray = PackedStringArray()
    lines.append("%s #%d  %s" % [s.label, s.id, "활성" if s.active else "비활성 (T로 전환)"])
    match s.kind:
        Placement.Kind.BONGSU:
            var nb: Array = (battle.network.edges.get(s.id, []) as Array).duplicate()
            nb.sort()
            lines.append("그룹 %s · 간선 %s · 중계 180px" % [str(s.group_id) if s.group_id >= 0 else "없음", str(nb)])
        Placement.Kind.SENSOR:
            var seen: int = (battle.network.sensor_seen.get(s.id, {}) as Dictionary).size()
            lines.append("부착 봉수대 %s · 그룹 %s · 탐지 %.0fpx · 감지 %d" % [
                str(s.attached_to) if s.attached_to >= 0 else "없음",
                str(s.group_id) if s.group_id >= 0 else "없음", s.detect_range, seen])
        Placement.Kind.HWACHA:
            lines.append("부착 봉수대 %s · 그룹 %s · 로컬 %.0fpx · 사거리 %.0fpx" % [
                str(s.attached_to) if s.attached_to >= 0 else "없음",
                str(s.group_id) if s.group_id >= 0 else "없음", s.detect_range, s.fire_range])
            lines.append("인지 적: 로컬 %d + 공유 %d · 재장전 %.2fs" % [s.known_local, s.known_shared, s.cooldown_left])
            if s.last_zone >= 0:
                var src: String = "로컬" if s.last_target_shared == 0 else ("공유" if s.last_target_local == 0 else "로컬+공유")
                lines.append("표적 Z%d (%s, 적 %d) · 발사 %d · 처치 %d" % [
                    s.last_zone, src, s.last_target_local + s.last_target_shared, s.shots_fired, s.kills])
            else:
                lines.append("대기: %s · 발사 %d · 처치 %d" % [s.wait_reason if s.wait_reason != "" else "-", s.shots_fired, s.kills])
        Placement.Kind.JANGSEUNG:
            lines.append("통행 차단 · 경로 버전 %d" % battle.path.path_version)
    var w: float = 0.0
    for l: String in lines:
        w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
    var origin: Vector2 = mouse + Vector2(24.0, -10.0)
    if origin.x + w + 16.0 > 1920.0:
        origin.x = mouse.x - w - 40.0
    draw_rect(Rect2(origin, Vector2(w + 16.0, 8.0 + 18.0 * lines.size())), COLOR_PANEL, true)
    for i: int in range(lines.size()):
        draw_string(font, origin + Vector2(8.0, 18.0 + 18.0 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)
    # attachment line highlighted for the hovered terminal
    if s.attached_to >= 0:
        var b: Placement.Structure = battle.placement.get_structure(s.attached_to)
        if b != null:
            draw_line(s.center, b.center, Color(1.0, 1.0, 1.0, 0.9), 2.0)