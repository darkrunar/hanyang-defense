extends SceneTree
## WP-003 follow-up probe for GPT D-019..D-021 (read-only, no game-rule change):
##  * full fixture-B coordinates (every bongsu / sensor / hwacha centre)
##  * A (52,12) is beyond 180 px of EVERY inner bongsu; B (44,13) has exactly one
##    nearest bongsu within 180 and that bongsu's group contains a sensor that
##    can see Z9
##  * Z8 (950,560)/r70 and Z9 (950,410)/r50 geometry vs 중영, A, B, S4 and the
##    walkable cells inside each zone circle (enemies exist only on open cells)
##
##   godot --headless --path . --script res://results/evidence/wp-003/pre-review/zone_ab_probe.gd [-- --out=<abs>.json]

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TerrainGrid := preload("res://game/core/terrain_grid.gd")

const A_ANCHOR: Vector2i = Vector2i(52, 12)
const B_ANCHOR: Vector2i = Vector2i(44, 13)
const Z8: Vector2 = Vector2(950.0, 560.0)
const Z8_R: float = 70.0
const Z9: Vector2 = Vector2(950.0, 410.0)
const Z9_R: float = 50.0
const INNER: Rect2i = Rect2i(42, 6, 12, 17)   # x42..53, y6..22 inclusive


func _walkable_cells_in_circle(g: TerrainGrid, c: Vector2, r: float) -> Dictionary:
    var open: int = 0
    var wall: int = 0
    var cells: Array = []
    for cy: int in range(g.height):
        for cx: int in range(g.width):
            if g.cell_center(cx, cy).distance_to(c) <= r:
                if g.is_wall(cx, cy):
                    wall += 1
                else:
                    open += 1
                    cells.append([cx, cy])
    return {"open_cells": open, "wall_cells": wall, "open_list": cells}


func _initialize() -> void:
    var out_path: String = ""
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())
    var cfg: Config = Config.new()   # fixture B, wp002 rules
    var b: Battle = Battle.new(cfg)
    var g: TerrainGrid = b.grid
    var link: float = cfg.get_num("bongsu_link_range")
    var sensor_r: float = cfg.get_num("sensor_range")
    var local_r: float = cfg.get_num("hwacha_local_range")
    var fire_r: float = cfg.get_num("hwacha_range")
    var report: Dictionary = {"ranges": {"link": link, "sensor": sensor_r, "local": local_r, "fire": fire_r}}

    # --- full fixture-B table ---
    var table: Array = []
    for id: int in b.placement.structures:
        var s: Placement.Structure = b.placement.structures[id]
        var a: Vector2i = s.anchor
        table.append({"id": s.id, "kind": Placement.kind_name(s.kind), "label": s.label,
            "anchor": [a.x, a.y], "center": [s.center.x, s.center.y],
            "district": "inner" if INNER.has_point(a) and INNER.has_point(a + Vector2i(1, 1)) else "outer",
            "group": s.group_id, "attached_to": s.attached_to})
    report["fixture_b"] = table

    # --- A / B attachment checks against every bongsu (all, and inner-only) ---
    var checks: Dictionary = {}
    for name: String in ["A", "B"]:
        var anchor: Vector2i = A_ANCHOR if name == "A" else B_ANCHOR
        var c: Vector2 = b.placement.footprint_center(anchor)
        var dists: Array = []
        for s: Placement.Structure in b.placement.bongsus():
            var d: float = c.distance_to(s.center)
            var inner: bool = INNER.has_point(s.anchor) and INNER.has_point(s.anchor + Vector2i(1, 1))
            dists.append({"bongsu": s.label, "id": s.id, "inner": inner, "dist": d, "within_link": d <= link})
        dists.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["dist"] < y["dist"])
        var legal: bool = b.placement.preview(Placement.Kind.HWACHA, anchor, b.sim)
        checks[name] = {"anchor": [anchor.x, anchor.y], "center": [c.x, c.y], "legal_now": legal,
            "z9_center_dist": c.distance_to(Z9), "z9_nearest_point_dist": maxf(0.0, c.distance_to(Z9) - Z9_R),
            "z9_in_fire_range": c.distance_to(Z9) <= fire_r,
            "z9_locally_coverable": c.distance_to(Z9) <= local_r + Z9_R,
            "z8_center_dist": c.distance_to(Z8), "z8_in_fire_range": c.distance_to(Z8) <= fire_r,
            "bongsu_by_distance": dists}
    report["ab_checks"] = checks

    # --- S4 / inner bongsu group and Z9 visibility ---
    var s4: Placement.Structure = null
    for s: Placement.Structure in b.placement.sensors():
        if s.label.ends_with("S4"):
            s4 = s
    var inner_net: Dictionary = {}
    if s4 != null:
        inner_net = {"s4_center": [s4.center.x, s4.center.y], "s4_attached_to": s4.attached_to, "s4_group": s4.group_id,
            "s4_to_z9_center": s4.center.distance_to(Z9), "s4_sees_z9_center": s4.center.distance_to(Z9) <= sensor_r,
            "s4_sees_all_of_z9": s4.center.distance_to(Z9) + Z9_R <= sensor_r,
            "s4_to_z8_center": s4.center.distance_to(Z8), "s4_sees_z8_center": s4.center.distance_to(Z8) <= sensor_r}
    var b2: Placement.Structure = null
    var b3: Placement.Structure = null
    for s: Placement.Structure in b.placement.bongsus():
        if s.label.ends_with("B2"):
            b2 = s
        if s.label.ends_with("B3"):
            b3 = s
    if b2 != null and b3 != null:
        inner_net["b2_center"] = [b2.center.x, b2.center.y]
        inner_net["b3_center"] = [b3.center.x, b3.center.y]
        inner_net["b2_b3_dist"] = b2.center.distance_to(b3.center)
        inner_net["b2_b3_linked"] = b2.center.distance_to(b3.center) <= link
    report["inner_network"] = inner_net

    # --- 중영 vs Z8 / outer stronghold ---
    var jung: Placement.Structure = b.placement.hwachas()[0]
    var outer_goal: Vector2 = g.cell_center(47, 26)
    report["jungyeong"] = {"center": [jung.center.x, jung.center.y], "to_z8_center": jung.center.distance_to(Z8),
        "z8_in_fire_range": jung.center.distance_to(Z8) <= fire_r, "to_outer_goal": jung.center.distance_to(outer_goal),
        "outer_goal_local": jung.center.distance_to(outer_goal) <= local_r,
        "outer_goal_inside_z8": outer_goal.distance_to(Z8) <= Z8_R}

    # --- walkable cells inside Z8 / Z9 circles ---
    report["z8_cells"] = _walkable_cells_in_circle(g, Z8, Z8_R)
    report["z9_cells"] = _walkable_cells_in_circle(g, Z9, Z9_R)
    report["z8_cells"].erase("open_list")
    var z9_list: Array = report["z9_cells"]["open_list"]
    report["z9_cells"].erase("open_list")
    report["z9_open_cells_list"] = z9_list

    print(JSON.stringify(report, "  "))
    if out_path != "":
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify(report, "  "))
            f.close()
    quit(0)
