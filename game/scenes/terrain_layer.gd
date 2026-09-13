extends Node2D
## Static grey-box terrain. Drawn once; only redraws when asked.
## Background is wall colour; every carved open area is painted as ground with
## a thin edge, so the city reads as blocks and streets.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const COLOR_GROUND: Color = Color(0.13, 0.12, 0.11)
const COLOR_WALL: Color = Color(0.25, 0.22, 0.20)
const COLOR_EDGE: Color = Color(0.42, 0.35, 0.28)
const COLOR_GOAL: Color = Color(0.93, 0.78, 0.36)
const COLOR_GOAL_RING: Color = Color(0.93, 0.78, 0.36, 0.35)
const COLOR_GATE: Color = Color(0.65, 0.65, 0.72, 0.9)

var _grid: TerrainGrid = null
var _open_rects: Array[Rect2] = []
var _goal_center: Vector2 = Vector2.ZERO
var _goal_radius: float = 26.0
var _gates: Array[Rect2] = []
var _font: Font = null


func setup(grid: TerrainGrid, goal_center: Vector2, goal_radius: float) -> void:
    _grid = grid
    _font = ThemeDB.fallback_font
    _goal_center = goal_center
    _goal_radius = goal_radius
    _open_rects.clear()
    for r: Array in TestMap.OPEN_RECTS:
        _open_rects.append(Rect2(
            Vector2(r[0], r[1]) * TerrainGrid.CELL_SIZE,
            Vector2(r[2] - r[0] + 1, r[3] - r[1] + 1) * TerrainGrid.CELL_SIZE
        ))
    _gates.clear()
    for r: Array in TestMap.ROUTES:
        var a: Vector2i = r[2]
        var b: Vector2i = r[3]
        var top_left: Vector2 = Vector2(mini(a.x, b.x), mini(a.y, b.y)) * TerrainGrid.CELL_SIZE
        var size: Vector2 = Vector2(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1) * TerrainGrid.CELL_SIZE
        _gates.append(Rect2(top_left, size))
    queue_redraw()


func _draw() -> void:
    if _grid == null:
        return
    draw_rect(Rect2(Vector2.ZERO, _grid.world_size()), COLOR_WALL, true)
    for r: Rect2 in _open_rects:
        draw_rect(r, COLOR_GROUND, true)
    for r: Rect2 in _open_rects:
        draw_rect(r, COLOR_EDGE, false, 1.0)
    for g: Rect2 in _gates:
        draw_rect(g, COLOR_GATE, false, 2.0)
    draw_circle(_goal_center, _goal_radius, COLOR_GOAL_RING)
    draw_rect(Rect2(_goal_center - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), COLOR_GOAL, true)
    draw_rect(Rect2(_goal_center - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), Color.BLACK, false, 2.0)
    draw_string(_font, _goal_center + Vector2(-40.0, -26.0), "핵심 시설 (목표)",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_GOAL)
