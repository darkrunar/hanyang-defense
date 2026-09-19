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

const FacilityArt = preload("res://game/scenes/facility_art.gd")
var art_mode: String = "greybox"
var facility_art: FacilityArt = null

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
## Scripted stand-in for the placement cursor (WP-003 recovery preview).
var preview_override: Vector2i = Vector2i(-1, -1)

const COLOR_INNER: Color = Color(1.00, 0.85, 0.30, 0.9)
const COLOR_INNER_FILL: Color = Color(1.00, 0.85, 0.30, 0.06)
const COLOR_OUTER_LOST: Color = Color(0.5, 0.1, 0.1, 0.10)
const COLOR_GOAL_OUTER: Color = Color(0.95, 0.55, 0.20)
const COLOR_GOAL_CORE: Color = Color(0.95, 0.30, 0.30)
const COLOR_HP_BG: Color = Color(0.1, 0.1, 0.1, 0.8)
const COLOR_HP_OUTER: Color = Color(0.95, 0.60, 0.20)
const COLOR_HP_CORE: Color = Color(0.95, 0.30, 0.30)


func _draw() -> void:
    if battle == null:
        return
    if art_mode == "sample" and facility_art == null:
        facility_art = FacilityArt.new()
    var counts: PackedInt32Array = battle.density.counts
    var targeted: Dictionary = {}
    for s: Placement.Structure in battle.placement.hwachas():
        if s.last_zone >= 0 and battle.combat_enabled:
            targeted[s.last_zone] = true

    if battle.run_mode == "waves":
        _draw_wp003_layer()

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
        if art_mode != "sample" or not facility_art.draw_facility(self, s):
            draw_rect(r, COLOR_JANGSEUNG, true)
            draw_rect(Rect2(s.center - Vector2(5.0, 18.0), Vector2(10.0, 36.0)), COLOR_JANGSEUNG_POST, true)
            draw_rect(r, Color.BLACK, false, 2.0)
        draw_string(font, s.center + Vector2(-16.0, -24.0), "장승", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)

    for s: Placement.Structure in battle.placement.bongsus():
        var col: Color = COLOR_BONGSU if s.active else COLOR_INACTIVE
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        if art_mode != "sample" or not facility_art.draw_facility(self, s):
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
        if art_mode != "sample" or not facility_art.draw_facility(self, s):
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
        if art_mode != "sample" or not facility_art.draw_facility(self, s):
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
        if battle.run_mode == "waves":
            _draw_recovery_ghost(anchor)
        else:
            var ok: bool = battle.placement.preview(place_mode, anchor, battle.sim)
            var top_left: Vector2 = Vector2(anchor) * TerrainGrid.CELL_SIZE
            draw_rect(Rect2(top_left, Vector2(40.0, 40.0)), COLOR_GHOST_OK if ok else COLOR_GHOST_BAD, false, 2.0)
        _draw_hover_panel(mouse)
    else:
        if preview_override.x >= 0 and battle.run_mode == "waves":
            _draw_recovery_ghost(preview_override)
        if hover_override != Vector2.INF:
            _draw_hover_panel(hover_override)


## WP-003: inner district outline, the two objectives with HP bars, the lost
## outer tint after the collapse, and the waiting (detached) H1 marker.
func _draw_wp003_layer() -> void:
    var r: Rect2i = TestMap.INNER_RECT
    var rect: Rect2 = Rect2(Vector2(r.position) * TerrainGrid.CELL_SIZE, Vector2(r.size) * TerrainGrid.CELL_SIZE)
    var rs := battle.run
    if rs.defense == 1:
        # outer district lost: tint everything outside the inner rect
        draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), COLOR_OUTER_LOST, true)
    draw_rect(rect, COLOR_INNER_FILL, true)
    draw_rect(rect, COLOR_INNER, false, 3.0 if rs.recovery_right > 0 else 1.5)
    draw_string(font, rect.position + Vector2(6.0, -6.0), "내곽 (회수 화차 배치 가능 구역)" if rs.recovery_right > 0 else "내곽",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_INNER)
    # objectives
    var outer_c: Vector2 = battle.grid.cell_center(TestMap.OUTER_GOAL_CELL.x, TestMap.OUTER_GOAL_CELL.y)
    var core_c: Vector2 = battle.grid.cell_center(TestMap.CORE_GOAL_CELL.x, TestMap.CORE_GOAL_CELL.y)
    _draw_objective(outer_c, "외곽 거점", rs.outer_hp, rs.outer_hp_max, COLOR_GOAL_OUTER, COLOR_HP_OUTER, rs.defense == 0, false)
    # The core's bar and label go ABOVE its marker: the legal recovery anchors
    # (A / B) lie right below it and must stay readable (R-07).
    _draw_objective(core_c, "핵심 시설", rs.core_hp, rs.core_hp_max, COLOR_GOAL_CORE, COLOR_HP_CORE, rs.defense == 1, true)
    # waiting H1
    if rs.recovery_right > 0:
        var d: Placement.Structure = battle.placement.get_any(rs.recovery_target_id)
        if d != null:
            var p: Vector2 = Vector2(rect.position.x + rect.size.x + 30.0, rect.position.y + 40.0)
            draw_rect(Rect2(p - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), COLOR_HWACHA, true)
            draw_rect(Rect2(p - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), COLOR_INNER, false, 2.0)
            draw_string(font, p + Vector2(28.0, -6.0), "%s 회수 대기 1/1" % d.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_INNER)
            draw_string(font, p + Vector2(28.0, 12.0), "재장전 잔여 %.2fs 동결 · 발사 %d · 처치 %d" % [d.cooldown_left, d.shots_fired, d.kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT)


func _draw_objective(c: Vector2, name: String, hp: float, hp_max: float, col: Color, bar: Color, is_target: bool, above: bool) -> void:
    draw_arc(c, battle.sim.goal_radius, 0.0, TAU, 32, col, 2.5 if is_target else 1.0)
    if is_target:
        draw_arc(c, battle.sim.goal_radius + 6.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.5), 1.0)
    var w: float = 120.0
    var origin: Vector2
    var text_pos: Vector2
    if above:
        origin = c + Vector2(-w * 0.5, -battle.sim.goal_radius - 20.0)
        text_pos = origin + Vector2(0.0, -6.0)
    else:
        origin = c + Vector2(-w * 0.5, battle.sim.goal_radius + 10.0)
        text_pos = origin + Vector2(0.0, 24.0)
    draw_rect(Rect2(origin, Vector2(w, 10.0)), COLOR_HP_BG, true)
    if hp_max > 0.0:
        draw_rect(Rect2(origin, Vector2(w * clampf(hp / hp_max, 0.0, 1.0), 10.0)), bar, true)
    draw_string(font, text_pos, "%s HP %.0f/%.0f%s" % [name, hp, hp_max, "  ◀ 현재 목표" if is_target else ""],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _draw_recovery_ghost(anchor: Vector2i) -> void:
    var reason: int = battle.preview_recovery(anchor)
    var top_left: Vector2 = Vector2(anchor) * TerrainGrid.CELL_SIZE
    var ok: bool = reason == Placement.Reject.NONE
    draw_rect(Rect2(top_left, Vector2(40.0, 40.0)), COLOR_GHOST_OK if ok else COLOR_GHOST_BAD, false, 2.0)
    var txt: String = "배치 가능" if ok else Placement.reject_name(reason)
    draw_string(font, top_left + Vector2(0.0, -6.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_GHOST_OK if ok else COLOR_GHOST_BAD)


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