extends SceneTree
## Headless map inspector: prints the grey-box layout as ASCII plus the
## reachability and lane-split facts the WP-001 scenarios depend on.
##
##   godot --headless --path . --script res://game/tools/dump_map.gd

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const Battle := preload("res://game/core/battle.gd")
const Placement := preload("res://game/core/placement.gd")


func _initialize() -> void:
    var b: Battle = Battle.new()
    var g: TerrainGrid = b.grid

    var hw_cells: Dictionary = {}
    for s: Placement.Structure in b.placement.hwachas():
        for ci: int in s.cells:
            hw_cells[ci] = true

    var spawn_cells: Dictionary = {}
    for r: int in range(b.path.route_spawn_cells.size()):
        for ci: int in b.path.route_spawn_cells[r]:
            spawn_cells[ci] = str(r)

    print("grid %d x %d cells, world %s, open cells = %d" % [
        g.width, g.height, str(g.world_size()), g.open_cell_count()
    ])
    print("goal cell %s  path_version=%d" % [str(TestMap.GOAL_CELL), b.path.path_version])
    print("")
    var header: String = "    "
    for cx: int in range(g.width):
        header += str(cx / 10) if cx % 10 == 0 else " "
    print(header)
    for cy: int in range(g.height):
        var row: String = "%3d " % cy
        for cx: int in range(g.width):
            var ci: int = g.idx(cx, cy)
            if Vector2i(cx, cy) == TestMap.GOAL_CELL:
                row += "@"
            elif hw_cells.has(ci):
                row += "H"
            elif spawn_cells.has(ci):
                row += spawn_cells[ci]
            elif g.is_wall(cx, cy):
                row += "#"
            elif b.path.dist[ci] >= b.path.UNREACHABLE:
                row += "!"
            else:
                row += "."
        print(row)
    print("")
    print("legend: # wall, . reachable open, ! open but unreachable, @ goal, H hwacha, 0/1/2 spawn cells")
    print("")

    for r: int in range(b.path.route_ids.size()):
        var cells: PackedInt32Array = b.path.route_spawn_cells[r]
        var ds: PackedStringArray = PackedStringArray()
        for ci: int in cells:
            ds.append(str(b.path.dist[ci]))
        print("route %d %s (%s): spawn cells=%d reachable=%s dist=[%s]" % [
            r, b.path.route_ids[r], TestMap.route_display_name(r),
            cells.size(), str(b.path.route_reachable(r)), ", ".join(ds)
        ])

    print("")
    for zi: int in range(b.density.zones.size()):
        var z := b.density.zones[zi]
        var ci: int = g.world_to_index(z.center)
        print("zone %d %-16s center=%s r=%.0f  cell open=%s" % [
            z.id, z.name, str(z.center), z.radius, str(not g.is_wall_i(ci))
        ])

    print("")
    for s: Placement.Structure in b.placement.hwachas():
        var covered: PackedStringArray = PackedStringArray()
        for zi: int in range(b.density.zones.size()):
            var z := b.density.zones[zi]
            if s.center.distance_to(z.center) <= s.fire_range:
                covered.append("Z%d(%.0f)" % [z.id, s.center.distance_to(z.center)])
        print("hwacha #%d %-10s center=%s range=%.0f covers [%s]" % [
            s.id, s.label, str(s.center), s.fire_range, ", ".join(covered)
        ])

    quit(0)
