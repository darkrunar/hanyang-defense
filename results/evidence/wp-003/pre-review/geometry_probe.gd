extends SceneTree
## WP-003 DRAFT v0.2 pre-review probe (no game-rule change, read-only use of the
## current core). Checks the draft's proposed coordinates against the real map:
##  * outer stronghold cell (47,26), core cell (47,10): open? reachable from all entries?
##  * inner candidate region x42..53 / y6..22: open cells, legal 2x2 anchors,
##    how the current WP-001 zones and fixture B structures fall into it
##  * for each legal inner hwacha anchor: which candidate zones are within
##    firing range 200 and local 100, which fixture-B sensors within 140 of a
##    zone are attachable (180) from inner bongsu -> "does inner A/B geometry
##    have anything to shoot at" (P-010 lesson)
##  * a jangseung-preserved outer state still leaves every entry a path to the core
##
##   godot --headless --path . --script res://results/evidence/wp-003/pre-review/geometry_probe.gd [-- --out=<abs>.json]

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const TerrainGrid := preload("res://game/core/terrain_grid.gd")

const OUTER: Vector2i = Vector2i(47, 26)
const CORE: Vector2i = Vector2i(47, 10)
const INNER_X0: int = 42
const INNER_X1: int = 53
const INNER_Y0: int = 6
const INNER_Y1: int = 22


func _initialize() -> void:
    var out_path: String = ""
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())
    var report: Dictionary = {}

    var cfg: Config = Config.new()   # fixture B, wp002 (the state WP-003 inherits)
    var b: Battle = Battle.new(cfg)
    var g: TerrainGrid = b.grid

    # --- 1. proposed goals -------------------------------------------------
    var goals: Dictionary = {}
    for name: String in ["outer", "core"]:
        var c: Vector2i = OUTER if name == "outer" else CORE
        b.path.set_goal(c.x, c.y)
        b.path.rebuild()
        var per_route: Dictionary = {}
        for r: int in range(b.path.route_ids.size()):
            var cells: PackedInt32Array = b.path.route_spawn_cells[r]
            var dmin: int = b.path.UNREACHABLE
            for ci: int in cells:
                dmin = mini(dmin, b.path.dist[ci])
            per_route[b.path.route_ids[r]] = {"reachable": b.path.route_reachable(r), "min_cost": dmin}
        goals[name] = {"cell": [c.x, c.y], "open": not g.is_wall(c.x, c.y),
            "world": [g.cell_center(c.x, c.y).x, g.cell_center(c.x, c.y).y], "routes": per_route}
    report["goals"] = goals
    # restore core goal for the rest (draft: after collapse the core is the goal)
    b.path.set_goal(CORE.x, CORE.y)
    b.path.rebuild()

    # --- 2. inner region: open cells, legal anchors, zones, fixture B ---------
    var open_cells: int = 0
    var legal_anchors: Array = []
    for cy: int in range(INNER_Y0, INNER_Y1 + 1):
        for cx: int in range(INNER_X0, INNER_X1 + 1):
            if not g.is_wall(cx, cy):
                open_cells += 1
            var a: Vector2i = Vector2i(cx, cy)
            var cells: PackedInt32Array = b.placement.footprint_cells(a)
            if cells.is_empty():
                continue
            var ok: bool = true
            for ci: int in cells:
                var x: int = ci % g.width
                var y: int = int(ci / g.width)
                if g.is_wall_i(ci) or x > INNER_X1 or y > INNER_Y1:
                    ok = false
            if ok:
                legal_anchors.append([cx, cy])
    var zones_in_inner: Array = []
    for z in b.density.zones:
        var c: Vector2i = g.world_to_cell(z.center)
        var inside: bool = c.x >= INNER_X0 and c.x <= INNER_X1 and c.y >= INNER_Y0 and c.y <= INNER_Y1
        zones_in_inner.append({"id": z.id, "name": z.name, "center": [z.center.x, z.center.y], "cell": [c.x, c.y], "inside_inner": inside})
    var fixture_b: Array = []
    for id: int in b.placement.structures:
        var s: Placement.Structure = b.placement.structures[id]
        var inside_all: bool = true
        var inside_any: bool = false
        for ci: int in s.cells:
            var x: int = ci % g.width
            var y: int = int(ci / g.width)
            var ins: bool = x >= INNER_X0 and x <= INNER_X1 and y >= INNER_Y0 and y <= INNER_Y1
            inside_all = inside_all and ins
            inside_any = inside_any or ins
        fixture_b.append({"id": s.id, "kind": Placement.kind_name(s.kind), "label": s.label, "anchor": [s.anchor.x, s.anchor.y],
            "district": "inner" if inside_all else ("STRADDLES" if inside_any else "outer")})
    report["inner_region"] = {"bounds": [INNER_X0, INNER_Y0, INNER_X1, INNER_Y1], "open_cells": open_cells,
        "legal_2x2_anchors": legal_anchors.size(), "zones": zones_in_inner, "fixture_b": fixture_b}

    # --- 3. what can an inner hwacha shoot at? (P-010 lesson) ---------------
    var inner_hwacha_options: Array = []
    for a in legal_anchors:
        var center: Vector2 = b.placement.footprint_center(Vector2i(a[0], a[1]))
        var in_range: Array = []
        var in_local: Array = []
        for z in b.density.zones:
            var d: float = center.distance_to(z.center)
            if d <= cfg.get_num("hwacha_range"):
                in_range.append(z.id)
            # a zone is locally coverable if its circle intersects the local circle
            if d <= cfg.get_num("hwacha_local_range") + z.radius:
                in_local.append(z.id)
        # nearest fixture-B bongsu within 180 -> attachable?
        var attach: int = -1
        var best_d: float = 1e9
        for s: Placement.Structure in b.placement.bongsus():
            var d2: float = center.distance_to(s.center)
            if d2 <= cfg.get_num("bongsu_link_range") and d2 < best_d:
                best_d = d2
                attach = s.id
        if not in_range.is_empty():
            inner_hwacha_options.append({"anchor": a, "center": [center.x, center.y], "zones_in_range": in_range,
                "zones_locally_coverable": in_local, "attachable_bongsu": attach, "attach_dist": best_d if attach >= 0 else -1.0})
    report["inner_hwacha_options"] = inner_hwacha_options

    # --- 4. corridor width at the palace door (the only inner chokepoint) ----
    var door_open: int = 0
    for cx: int in range(g.width):
        if not g.is_wall(cx, 15):
            door_open += 1
    report["palace_door_open_cells_row15"] = door_open

    # --- 5. outer jangseung preserved: does every entry still reach the core?
    var jang: Array = []
    for anchor in [TestMap.AC_SCENARIO_ANCHORS["south_west_lane"], TestMap.AC_SCENARIO_ANCHORS["west_north_lane"]]:
        var res: Placement.Result = b.place_jangseung(anchor)
        jang.append({"anchor": [anchor.x, anchor.y], "ok": res.ok})
    var all_reach: bool = true
    for r: int in range(b.path.route_ids.size()):
        all_reach = all_reach and b.path.route_reachable(r)
    report["outer_jangseung_kept"] = {"placed": jang, "all_routes_reach_core": all_reach, "path_version": b.path.path_version}

    # --- 6. transit time from each gate to the core at base speed ------------
    var transit: Dictionary = {}
    for r: int in range(b.path.route_ids.size()):
        var dmin: int = b.path.UNREACHABLE
        for ci: int in b.path.route_spawn_cells[r]:
            dmin = mini(dmin, b.path.dist[ci])
        # cost units: 10 per orthogonal cell (20 px) -> px = cost * 2
        transit[b.path.route_ids[r]] = {"path_px": dmin * 2, "seconds_at_base_speed": float(dmin * 2) / cfg.get_num("enemy_speed")}
    report["transit_to_core_with_two_jangseung"] = transit

    print(JSON.stringify(report, "  "))
    if out_path != "":
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify(report, "  "))
            f.close()
            print("report written: %s" % out_path)
    quit(0)
