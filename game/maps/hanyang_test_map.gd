extends RefCounted
## WP-001 grey-box test map: three gates into one shared defence objective.
##
## Grid is 96 x 54 cells at 20 px = 1920 x 1080 world units. The grid starts
## fully solid and open areas are carved, so anything not listed here is a wall.
##
## Layout (world y grows downward):
##
##   +----------------------------------------------------+
##   |                 [ 경복궁 compound ]                  |  y  6..14
##   |                   door x46..49                      |  y 15
##   |            [       중앙 광장 plaza      ]            |  y 16..30
##   |  서대문 ===lane N===|                |===lane N=== 동대문
##   |   corridor  [block] |     plaza      | [block]      |  y 24..29
##   |         ===lane S===|                |===lane S===  |
##   |                  | W |block| E |                    |  y 31..43
##   |                  [ 남대문 corridor ]                 |  y 44..53
##   +----------------------------------------------------+
##
## Each route enters a wide corridor that splits into two 2-cell lanes around a
## solid block and rejoins at the plaza. A 2x2 장승 fully plugs one lane, which
## is what makes AC-02 / AC-03 / AC-06 legible.

const TerrainGrid := preload("res://game/core/terrain_grid.gd")
const PathNetwork := preload("res://game/core/path_network.gd")
const DensityDetector := preload("res://game/core/density_detector.gd")
const Placement := preload("res://game/core/placement.gd")

const WIDTH: int = 96
const HEIGHT: int = 54

const GOAL_CELL: Vector2i = Vector2i(47, 10)

## Open rectangles, inclusive cell bounds: [x0, y0, x1, y1, name]
const OPEN_RECTS: Array = [
    [42, 6, 53, 14, "경복궁 compound"],
    [46, 15, 49, 15, "광화문 door"],
    [30, 16, 65, 30, "중앙 광장"],

    [44, 44, 49, 53, "남대문 corridor"],
    [44, 31, 45, 43, "남문 서편 골목"],
    [48, 31, 49, 43, "남문 동편 골목"],

    [0, 24, 15, 29, "서대문 corridor"],
    [16, 24, 29, 25, "서문 북편 골목"],
    [16, 28, 29, 29, "서문 남편 골목"],

    [80, 24, 95, 29, "동대문 corridor"],
    [66, 24, 79, 25, "동문 북편 골목"],
    [66, 28, 79, 29, "동문 남편 골목"],
]

## Route id, display name, and the spawn cells at the map edge.
const ROUTES: Array = [
    ["S_NAMDAEMUN", "남대문", Vector2i(44, 53), Vector2i(49, 53)],
    ["W_SEODAEMUN", "서대문", Vector2i(0, 24), Vector2i(0, 29)],
    ["E_DONGDAEMUN", "동대문", Vector2i(95, 24), Vector2i(95, 29)],
]

const ROUTE_COLORS: Array[Color] = [
    Color(0.86, 0.33, 0.30),   # 단청 red   - 남대문
    Color(0.36, 0.76, 0.72),   # 청록       - 서대문
    Color(0.90, 0.71, 0.30),   # 치자 amber - 동대문
]

## Candidate density zones: [name, center_x, center_y, radius]
## Lane zones use r=45 so that a zone covers its own 40 px lane and never
## reaches into the neighbouring lane across the solid block.
const ZONES: Array = [
    ["남문 서편 골목", 900.0, 750.0, 45.0],
    ["남문 동편 골목", 980.0, 750.0, 45.0],
    ["남대문 대로", 940.0, 1000.0, 70.0],
    ["서문 북편 골목", 460.0, 500.0, 45.0],
    ["서문 남편 골목", 460.0, 580.0, 45.0],
    ["동문 북편 골목", 1460.0, 500.0, 45.0],
    ["동문 남편 골목", 1460.0, 580.0, 45.0],
    ["광화문 어귀", 960.0, 310.0, 70.0],
]

## Starting hwachas: [label, anchor_x, anchor_y]. Placed on open plaza ground.
## A hwacha never blocks traffic, so these cannot disconnect a route.
const HWACHAS: Array = [
    ["화차·중영", 46, 29],
    ["화차·서영", 30, 25],
    ["화차·동영", 64, 25],
    ["화차·궁성", 46, 17],
]

## WP-002 fixture B (backlog/WP-002.md): 4 hwachas + 8 bongsu + 4 sensors,
## placed before any enemy spawns. Bongsu are listed B1..B8 in order; B8
## (44,33) is the only relay of the southern sensor (44,39).
const FIXTURE_B_BONGSU: Array = [
    ["봉수 B1", 34, 21], ["봉수 B2", 42, 21], ["봉수 B3", 50, 21], ["봉수 B4", 58, 21],
    ["봉수 B5", 34, 29], ["봉수 B6", 42, 29], ["봉수 B7", 58, 29], ["봉수 B8", 44, 33],
]
const FIXTURE_B_SENSORS: Array = [
    ["혼천의 S1", 30, 27], ["혼천의 S2", 62, 27], ["혼천의 S3", 44, 39], ["혼천의 S4", 47, 15],
]

## WP-002 fixture A (connection effect): one hwacha, one bongsu, one sensor,
## one stationary enemy at Z0 (900,750). H<->enemy 155.24 px (outside local
## 100, inside range 200), S<->enemy 50 px, H<->B 89.44 px, B<->S 120 px.
const FIXTURE_A: Dictionary = {
    "hwacha": Vector2i(46, 29),
    "bongsu": Vector2i(44, 33),
    "sensor": Vector2i(44, 39),
    "enemy": Vector2(900.0, 750.0),
    "local_enemy": Vector2(940.0, 690.0),   # 90 px south of H: inside local 100
}

## ---------------------------------------------------------------- WP-003 ---
## Fixed map data for backlog/WP-003.md READY v1.0 (D-019 / D-020 / D-022 /
## D-025). WP-001/002 data above is untouched.

## Two objectives: the outer stronghold and the core.
const OUTER_GOAL_CELL: Vector2i = Vector2i(47, 26)   # centre (950,530)
const CORE_GOAL_CELL: Vector2i = Vector2i(47, 10)    # centre (950,210)

## Inner district, inclusive cell bounds. Everything else walkable is outer.
const INNER_RECT: Rect2i = Rect2i(42, 6, 12, 17)      # x42..53, y6..22
const DISTRICT_OUTER: int = 0
const DISTRICT_INNER: int = 1

## WP-003 only: the 8 original zones plus Z8 / Z9 (D-019).
const WP003_EXTRA_ZONES: Array = [
    ["광장 남단", 950.0, 560.0, 70.0],   # Z8
    ["광화문 앞", 950.0, 410.0, 50.0],   # Z9
]

## Fixture C = fixture B (4 hwacha, 8 bongsu, 4 sensors, in that order) plus two
## outer jangseung. The recovery target is the FIRST hwacha placed (H1 중영);
## its stable id is captured at creation, never looked up by name later.
const FIXTURE_C_JANGSEUNG: Array = [
    ["장승 J1", 44, 36],
    ["장승 J2", 22, 24],
]

## Recovery placements used by the F2/F3/perf scenarios (D-022).
const RECOVERY_A: Vector2i = Vector2i(52, 12)   # (1060,260), no bongsu within 180
const RECOVERY_B: Vector2i = Vector2i(44, 13)   # (900,280), attaches to B2

## Finite waves (D-025): [south, west, east] counts and per-second rates.
const WAVES: Array = [
    {"name": "W1", "count": [60, 60, 60], "rate": [10.0, 10.0, 10.0]},
    {"name": "W2", "count": [120, 120, 120], "rate": [10.0, 10.0, 10.0]},
    {"name": "W3", "count": [360, 120, 120], "rate": [30.0, 10.0, 10.0]},
]
const WAVES_TOTAL: int = 1140

## F3 controlled spawn point (D-026): 12 enemies at (950,450).
const F3_SPAWN_POINT: Vector2 = Vector2(950.0, 450.0)
const F3_SPAWN_COUNT: int = 12


static func district_of_cell(cx: int, cy: int) -> int:
    if INNER_RECT.has_point(Vector2i(cx, cy)):
        return DISTRICT_INNER
    return DISTRICT_OUTER


static func district_name(d: int) -> String:
    return "내곽" if d == DISTRICT_INNER else "외곽"


## Reference anchors used by the scripted AC scenarios and the docs.
const AC_SCENARIO_ANCHORS: Dictionary = {
    "south_west_lane": Vector2i(44, 36),
    "south_east_lane": Vector2i(48, 36),
    "west_north_lane": Vector2i(22, 24),
    "west_south_lane": Vector2i(22, 28),
}


static func build_grid() -> TerrainGrid:
    var g: TerrainGrid = TerrainGrid.new(WIDTH, HEIGHT)
    for r: Array in OPEN_RECTS:
        g.carve_open(r[0], r[1], r[2], r[3])
    return g


static func build_path(g: TerrainGrid) -> PathNetwork:
    var p: PathNetwork = PathNetwork.new(g)
    p.set_goal(GOAL_CELL.x, GOAL_CELL.y)
    for r: Array in ROUTES:
        var a: Vector2i = r[2]
        var b: Vector2i = r[3]
        var cells: PackedInt32Array = PackedInt32Array()
        for cy: int in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
            for cx: int in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
                cells.append(g.idx(cx, cy))
        p.add_route(r[0], cells)
    p.rebuild()
    return p


static func build_zones(zone_set: String = "wp001") -> DensityDetector:
    var d: DensityDetector = DensityDetector.new()
    for z: Array in ZONES:
        d.add_zone(z[0], Vector2(z[1], z[2]), z[3])
    if zone_set == "wp003":
        for z: Array in WP003_EXTRA_ZONES:
            d.add_zone(z[0], Vector2(z[1], z[2]), z[3])
    return d


## Path network with the given goal cell (WP-003 starts on the outer stronghold).
static func build_path_to(g: TerrainGrid, goal: Vector2i) -> PathNetwork:
    var p: PathNetwork = PathNetwork.new(g)
    p.set_goal(goal.x, goal.y)
    for r: Array in ROUTES:
        var a: Vector2i = r[2]
        var b: Vector2i = r[3]
        var cells: PackedInt32Array = PackedInt32Array()
        for cy: int in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
            for cx: int in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
                cells.append(g.idx(cx, cy))
        p.add_route(r[0], cells)
    p.rebuild()
    return p


static func route_display_name(route_index: int) -> String:
    return ROUTES[route_index][1]


static func route_color(route_index: int) -> Color:
    return ROUTE_COLORS[route_index % ROUTE_COLORS.size()]


## Wall rectangles for rendering, derived from the open rectangles by scanning
## the finished grid into horizontal runs (cheap, and always matches the sim).
static func wall_runs(g: TerrainGrid) -> Array:
    var runs: Array = []
    for cy: int in range(g.height):
        var start: int = -1
        for cx: int in range(g.width + 1):
            var solid: bool = cx < g.width and g.is_wall(cx, cy)
            if solid and start < 0:
                start = cx
            elif not solid and start >= 0:
                runs.append(Rect2(
                    float(start) * TerrainGrid.CELL_SIZE,
                    float(cy) * TerrainGrid.CELL_SIZE,
                    float(cx - start) * TerrainGrid.CELL_SIZE,
                    TerrainGrid.CELL_SIZE
                ))
                start = -1
    return runs
