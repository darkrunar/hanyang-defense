extends Node2D
## Static grey-box terrain. Drawn once; only redraws when asked.
## Background is wall colour; every carved open area is painted as ground with
## a thin edge, so the city reads as blocks and streets.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const ArtSet := preload("res://game/scenes/art_set.gd")

## WP-005 sample region (inclusive cells x30..65, y6..30: 광장·광화문·내곽).
## Only the drawing changes here; the grid, collisions and paths are shared.
const SAMPLE_RECT: Rect2i = Rect2i(30, 6, 36, 25)
## Art set for `--art=sample`; null keeps the grey-box drawing everywhere.
var art: ArtSet = null
var sample_tiles_drawn: Dictionary = {}

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
## WP-001/002 draw the single static goal here. WP-003 has two objectives whose
## state changes (outer -> core), drawn by the overlay instead; the main scene
## turns this off in waves mode so the labels never overlap or go stale.
var show_goal_marker: bool = true
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
    if art != null:
        _draw_sample_tiles()
    for g: Rect2 in _gates:
        draw_rect(g, COLOR_GATE, false, 2.0)
    if not show_goal_marker:
        return
    draw_circle(_goal_center, _goal_radius, COLOR_GOAL_RING)
    draw_rect(Rect2(_goal_center - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), COLOR_GOAL, true)
    draw_rect(Rect2(_goal_center - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), Color.BLACK, false, 2.0)
    draw_string(_font, _goal_center + Vector2(-40.0, -26.0), "핵심 시설 (목표)",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_GOAL)


## Sample-region tile plan (D-049), pure and cached: for every cell of
## SAMPLE_RECT which art element covers it. Ground variants by cell hash,
## edge tiles where a wall touches an open cell (frames 0..3 = wall to
## N/E/S/W, 4..7 = inner corners NE/SE/SW/NW), wall modules on wall cells
## that face a street, roof modules on the blocks behind them, the gate
## module on the 광화문 door. Items: [element, cell, frame]. Elements
## without a file are planned but not drawn (counted in `skipped`).
static func sample_plan(grid: TerrainGrid, rect: Rect2i = SAMPLE_RECT) -> Dictionary:
    var items: Array = []
    var counts: Dictionary = {"ground": 0, "edge": 0, "wall": 0, "roof": 0, "gate": 0}
    for cy: int in range(rect.position.y, rect.end.y):
        for cx: int in range(rect.position.x, rect.end.x):
            var cell: Vector2i = Vector2i(cx, cy)
            if grid.is_wall(cx, cy):
                var street: bool = _open(grid, cx - 1, cy) or _open(grid, cx + 1, cy) or _open(grid, cx, cy - 1) or _open(grid, cx, cy + 1)
                var el: String = "wall" if street else "roof"
                items.append([el, cell, 0])
                counts[el] += 1
                continue
            # Mostly the base tile; the three variants appear sparsely so the
            # floor does not read as a checkerboard (GPT review 2026-09-20 (2)).
            var hsh: int = posmod(cx * 73856093 ^ cy * 19349663, 16)
            items.append(["ground", cell, 0 if hsh < 11 else 1 + (hsh - 11) % 3])
            counts["ground"] += 1
            var sides: Array = [not _open(grid, cx, cy - 1), not _open(grid, cx + 1, cy), not _open(grid, cx, cy + 1), not _open(grid, cx - 1, cy)]
            for k: int in range(4):
                if sides[k]:
                    items.append(["edge", cell, k])
                    counts["edge"] += 1
            var diag: Array = [[1, -1, 4], [1, 1, 5], [-1, 1, 6], [-1, -1, 7]]
            for d: Array in diag:
                if not _open(grid, cx + d[0], cy + d[1]) and _open(grid, cx + d[0], cy) and _open(grid, cx, cy + d[1]):
                    items.append(["edge", cell, d[2]])
                    counts["edge"] += 1
    items.append(["gate", Vector2i(46, 15), 0])
    counts["gate"] += 1
    return {"items": items, "counts": counts, "rect": rect}


const COLOR_EDGE_FALLBACK: Color = Color(0.30, 0.24, 0.17, 0.9)


func _draw_edge_fallback(r: Rect2, frame: int) -> void:
    var w: float = 2.0
    match frame:
        0: draw_rect(Rect2(r.position, Vector2(r.size.x, w)), COLOR_EDGE_FALLBACK, true)
        1: draw_rect(Rect2(r.position + Vector2(r.size.x - w, 0.0), Vector2(w, r.size.y)), COLOR_EDGE_FALLBACK, true)
        2: draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - w), Vector2(r.size.x, w)), COLOR_EDGE_FALLBACK, true)
        3: draw_rect(Rect2(r.position, Vector2(w, r.size.y)), COLOR_EDGE_FALLBACK, true)
        4: draw_rect(Rect2(r.position + Vector2(r.size.x - 3.0, 0.0), Vector2(3.0, 3.0)), COLOR_EDGE_FALLBACK, true)
        5: draw_rect(Rect2(r.position + Vector2(r.size.x - 3.0, r.size.y - 3.0), Vector2(3.0, 3.0)), COLOR_EDGE_FALLBACK, true)
        6: draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 3.0), Vector2(3.0, 3.0)), COLOR_EDGE_FALLBACK, true)
        7: draw_rect(Rect2(r.position, Vector2(3.0, 3.0)), COLOR_EDGE_FALLBACK, true)


static func _open(grid: TerrainGrid, cx: int, cy: int) -> bool:
    return grid.in_bounds(cx, cy) and not grid.is_wall(cx, cy)


var _plan: Dictionary = {}


func _draw_sample_tiles() -> void:
    if _plan.is_empty():
        _plan = sample_plan(_grid)
    var cs: float = TerrainGrid.CELL_SIZE
    var frames: Dictionary = {
        "ground": art.frames("terrain_sample", "ground"), "edge": art.frames("terrain_sample", "edge"),
        "wall": art.frames("building_sample", "wall"), "roof": art.frames("building_sample", "roof"),
        "gate": art.frames("building_sample", "gate")}
    var drawn: Dictionary = {"ground": 0, "edge": 0, "edge_procedural": 0, "wall": 0, "roof": 0, "gate": 0, "skipped": 0}
    for it: Array in _plan["items"]:
        var el: String = it[0]
        var fr: ArtSet.Frames = frames[el]
        var cell: Vector2i = it[1]
        var cell_rect: Rect2 = Rect2(Vector2(cell) * cs, Vector2(cs, cs))
        if fr == null:
            if el == "edge":
                # D-052: until the edge tiles arrive, the wall contact is a
                # procedural dark line / corner dot from the same plan item.
                _draw_edge_fallback(cell_rect, int(it[2]))
                drawn["edge_procedural"] += 1
            else:
                drawn["skipped"] += 1
            continue
        match el:
            "ground", "edge":
                draw_texture_rect_region(fr.texture, cell_rect, fr.region(int(it[2])))
            "wall", "roof":
                _draw_module(fr, cell.x, cell.y, cell_rect)
            "gate":
                # the 광화문 door row (46..49, 15), module centred on it
                var c: Vector2 = Rect2(Vector2(46, 15) * cs, Vector2(4, 1) * cs).get_center()
                draw_texture_rect_region(fr.texture, Rect2(c - fr.pivot, Vector2(fr.frame_size)), fr.region(0))
        drawn[el] += 1
    sample_tiles_drawn = drawn


## A building module repeats across its cells like a pattern anchored at the
## world origin, so a module wider than one cell tiles without seams.
func _draw_module(module: ArtSet.Frames, cx: int, cy: int, cell_rect: Rect2) -> void:
    var cs: int = int(TerrainGrid.CELL_SIZE)
    var fw: int = module.frame_size.x
    var fh: int = module.frame_size.y
    var src: Rect2 = Rect2(Vector2(float((cx * cs) % maxi(fw, 1)), float((cy * cs) % maxi(fh, 1))), Vector2(cs, cs))
    draw_texture_rect_region(module.texture, cell_rect, src)
