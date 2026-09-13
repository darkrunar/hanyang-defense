extends Node2D
## Dynamic debug overlay drawn above the enemies: density zones, structures,
## hwacha ranges and volleys, route labels and the placement cursor ghost.

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
const COLOR_HWACHA_FIRE: Color = Color(1.00, 0.55, 0.15, 0.85)
const COLOR_BLAST: Color = Color(1.00, 0.70, 0.30, 0.55)
const COLOR_GHOST_OK: Color = Color(0.40, 0.95, 0.45, 0.55)
const COLOR_GHOST_BAD: Color = Color(1.00, 0.30, 0.30, 0.55)
const COLOR_TEXT: Color = Color(0.92, 0.90, 0.85)

var battle: Battle = null
var font: Font = null
var show_zones: bool = true
var show_ranges: bool = true
var show_cursor: bool = true
var place_mode: int = 0
var recent_shots: Array = []   # [aim, radius, age]


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

    for s: Placement.Structure in battle.placement.jangseungs():
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        draw_rect(r, COLOR_JANGSEUNG, true)
        draw_rect(Rect2(s.center - Vector2(5.0, 18.0), Vector2(10.0, 36.0)), COLOR_JANGSEUNG_POST, true)
        draw_rect(r, Color.BLACK, false, 2.0)
        draw_string(font, s.center + Vector2(-16.0, -24.0), "장승", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)

    for s: Placement.Structure in battle.placement.hwachas():
        if show_ranges:
            draw_arc(s.center, s.fire_range, 0.0, TAU, 64, COLOR_HWACHA_RANGE, 1.0)
        var r: Rect2 = Rect2(s.center - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
        draw_rect(r, COLOR_HWACHA, true)
        draw_rect(r, Color.BLACK, false, 2.0)
        draw_circle(s.center + Vector2(-12.0, 14.0), 5.0, Color.BLACK)
        draw_circle(s.center + Vector2(12.0, 14.0), 5.0, Color.BLACK)
        if s.last_zone >= 0 and battle.combat_enabled:
            draw_line(s.center, s.last_aim, COLOR_HWACHA_FIRE, 3.0 if s.muzzle_timer > 0.0 else 1.0)
        draw_string(font, s.center + Vector2(-30.0, -24.0), s.label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)

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
        var anchor: Vector2i = battle.placement.anchor_for_world(get_global_mouse_position())
        var cells: PackedInt32Array = battle.placement.footprint_cells(anchor)
        var ok: bool = not cells.is_empty()
        if ok:
            for ci: int in cells:
                if battle.grid.is_wall_i(ci) or battle.placement.structure_at_cell(ci) != null \
                        or battle.sim.is_cell_occupied(ci):
                    ok = false
                    break
        var top_left: Vector2 = Vector2(anchor) * TerrainGrid.CELL_SIZE
        draw_rect(Rect2(top_left, Vector2(40.0, 40.0)), COLOR_GHOST_OK if ok else COLOR_GHOST_BAD, false, 2.0)
