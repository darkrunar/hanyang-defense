extends RefCounted
## Static grey-box terrain grid plus the structure occupancy layer.
##
## Pure data: no SceneTree, no nodes. Every WP-001 rule that depends on
## walkability reads this class, so the headless tests can drive it directly.

const CELL_SIZE: float = 20.0

var width: int = 0
var height: int = 0

## 1 = static terrain wall (never changes at runtime).
var _wall: PackedByteArray = PackedByteArray()
## Structure id occupying the cell, or -1. Only blocking structures are recorded.
var _structure: PackedInt32Array = PackedInt32Array()


func _init(w: int, h: int) -> void:
    width = w
    height = h
    var n: int = w * h
    _wall.resize(n)
    _wall.fill(1)  # solid by default; the map definition carves open areas
    _structure.resize(n)
    _structure.fill(-1)


func idx(cx: int, cy: int) -> int:
    return cy * width + cx


func cell_x(i: int) -> int:
    return i % width


func cell_y(i: int) -> int:
    return i / width


func in_bounds(cx: int, cy: int) -> bool:
    return cx >= 0 and cy >= 0 and cx < width and cy < height


## Carve a rectangle of cells open (inclusive bounds), clamped to the grid.
func carve_open(x0: int, y0: int, x1: int, y1: int) -> void:
    for cy: int in range(maxi(y0, 0), mini(y1, height - 1) + 1):
        for cx: int in range(maxi(x0, 0), mini(x1, width - 1) + 1):
            _wall[cy * width + cx] = 0


func fill_wall(x0: int, y0: int, x1: int, y1: int) -> void:
    for cy: int in range(maxi(y0, 0), mini(y1, height - 1) + 1):
        for cx: int in range(maxi(x0, 0), mini(x1, width - 1) + 1):
            _wall[cy * width + cx] = 1


func is_wall_i(i: int) -> bool:
    return _wall[i] == 1


func is_wall(cx: int, cy: int) -> bool:
    if not in_bounds(cx, cy):
        return true
    return _wall[cy * width + cx] == 1


func structure_at_i(i: int) -> int:
    return _structure[i]


func structure_at(cx: int, cy: int) -> int:
    if not in_bounds(cx, cy):
        return -1
    return _structure[cy * width + cx]


## Passable = open terrain and no blocking structure.
func is_passable_i(i: int) -> bool:
    return _wall[i] == 0 and _structure[i] == -1


func is_passable(cx: int, cy: int) -> bool:
    if not in_bounds(cx, cy):
        return false
    var i: int = cy * width + cx
    return _wall[i] == 0 and _structure[i] == -1


func set_structure_i(i: int, structure_id: int) -> void:
    _structure[i] = structure_id


func clear_structures() -> void:
    _structure.fill(-1)


func world_to_cell(p: Vector2) -> Vector2i:
    return Vector2i(int(floor(p.x / CELL_SIZE)), int(floor(p.y / CELL_SIZE)))


func world_to_index(p: Vector2) -> int:
    var cx: int = int(floor(p.x / CELL_SIZE))
    var cy: int = int(floor(p.y / CELL_SIZE))
    if cx < 0 or cy < 0 or cx >= width or cy >= height:
        return -1
    return cy * width + cx


func cell_center(cx: int, cy: int) -> Vector2:
    return Vector2((float(cx) + 0.5) * CELL_SIZE, (float(cy) + 0.5) * CELL_SIZE)


func index_center(i: int) -> Vector2:
    return Vector2((float(i % width) + 0.5) * CELL_SIZE, (float(i / width) + 0.5) * CELL_SIZE)


func world_size() -> Vector2:
    return Vector2(float(width) * CELL_SIZE, float(height) * CELL_SIZE)


func open_cell_count() -> int:
    var n: int = 0
    for i: int in range(_wall.size()):
        if _wall[i] == 0:
            n += 1
    return n
