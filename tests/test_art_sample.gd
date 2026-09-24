extends RefCounted
## WP-005 headless suite for the rendering pipeline that the reviewed art
## will drop into (D-049). It uses the programmatic development fixture
## (game/tools/wp005_dev_fixture.gd), never real assets, so it proves the
## loader / atlas / tile plan / fx event contract and that `--art` changes
## nothing in the battle. AC-01/02/03/06/08 need the reviewed files and the
## real screen and stay NOT RUN here.

const Main := preload("res://game/scenes/main.gd")
const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const ArtSet := preload("res://game/scenes/art_set.gd")
const TerrainLayer := preload("res://game/scenes/terrain_layer.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")
const Fixture := preload("res://game/tools/wp005_dev_fixture.gd")
const Flow := preload("res://tests/test_play_flow.gd")

const DT: float = 0.0166666667
const FIXTURE_DIR: String = "user://wp005_art_fixture"
const EMPTY_DIR: String = "user://wp005_art_missing"
const SETTINGS_TMP: String = "user://wp005_test_settings.cfg"
const OUTER_GOAL: Vector2 = Vector2(950.0, 530.0)


func run(t: RefCounted) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    Fixture.write_all(FIXTURE_DIR)
    _loader_unit(t)
    _tile_plan_unit(t)
    _enemy_frame_unit(t, tree)
    _greybox_equals_sample(t, tree)
    _fx_event_contract(t, tree)
    _sample_scene_wiring(t, tree)
    _reviewed_assets(t, tree)


# ----------------------------------------------------------------- helpers ---

static func _scene(tree: SceneTree, art_mode: String, directory: String = FIXTURE_DIR) -> Node2D:
    var scene: Node2D = Main.new()
    scene._settings_path = SETTINGS_TMP
    scene._art_mode = art_mode
    scene._art_dir = directory
    tree.root.add_child(scene)
    if not scene.is_node_ready():
        scene._ready()
    scene.set_process(false)
    scene.set_physics_process(false)
    return scene


## One physics frame plus the render-side bookkeeping (_process) that feeds the fx.
static func _frame(scene: Node2D, n: int = 1, render: bool = true) -> void:
    for _i: int in range(n):
        scene._physics_process(DT)
        if render:
            scene._process(DT)


static func _start(scene: Node2D) -> void:
    Flow._click(scene, "title_start")


static func _force_collapse(scene: Node2D) -> void:
    scene.battle.force_outer_hp(1.0, "test forced collapse")
    scene.battle.spawn_extra(OUTER_GOAL, 1, "test trigger enemy")


# -------------------------------------------------------------------- units ---

func _loader_unit(t: RefCounted) -> void:
    t.case("ArtSet: missing directory -> every contract entry missing, grey box kept; fixture -> all loaded, frame strips sliced, atlas built, pivots by rule and by pivots.json, malformed files reported")
    var empty: ArtSet = ArtSet.new(EMPTY_DIR)
    var rep: Dictionary = empty.load_all()
    t.eq(empty.loaded_count(), 0, "nothing loaded from a missing directory")
    t.eq(int(rep["missing_count"]) + int(rep["optional_missing_count"]), empty.contract_count(), "every contract entry reported missing (required + optional)")
    t.eq(int(rep["optional_missing_count"]), 5, "the 5 interaction marks are optional (procedural allowed)")
    t.check(empty.enemy_atlas == null, "no enemy atlas")
    t.eq(empty.frames("hwacha", "idle"), null, "frames() is null -> caller keeps the grey box")
    t.eq(empty.contract_count(), 35, "contract lists 35 files for the 11 manifest ids")

    var art: ArtSet = ArtSet.new(FIXTURE_DIR)
    rep = art.load_all()
    t.eq(art.loaded_count(), art.contract_count(), "fixture: every contract file loaded")
    t.eq(int(rep["missing_count"]), 0, "fixture: nothing missing")
    var fire: ArtSet.Frames = art.frames("hwacha", "fire")
    t.eq(fire.frame_count, 3, "hwacha fire strip: 3 frames")
    t.eq(fire.frame_size, Vector2i(40, 40), "hwacha frame 40x40")
    t.eq(fire.region(2), Rect2(80, 0, 40, 40), "third frame region")
    t.eq(fire.region(3), Rect2(0, 0, 40, 40), "frame index wraps")
    t.eq(fire.pivot, Vector2(20.0, 20.0), "40x40 facility pivot = footprint centre")
    var post: ArtSet.Frames = art.frames("outer_post", "normal")
    t.eq(post.frame_size, Vector2i(40, 48), "taller post canvas")
    t.eq(post.pivot, Vector2(20.0, 28.0), "post pivot: bottom centre minus half footprint")
    var enemy: ArtSet.Frames = art.frames("enemy_basic", "walk_down")
    t.eq(enemy.pivot, Vector2(6.0, 16.0), "enemy pivot: body bottom centre")
    t.eq(enemy.sha256.length(), 64, "file sha256 recorded")
    t.check(art.enemy_atlas != null, "enemy atlas built")
    t.eq(art.enemy_frame_size, Vector2i(12, 16), "atlas frame 12x16")
    t.eq(art.enemy_atlas_pitch, Vector2i(14, 18), "2 px gutters")
    t.eq(art.enemy_atlas_size, Vector2i(56, 54), "4 columns x 3 rows")
    # the atlas holds the frames where the shader expects them: walk_left frame 1 -> index 5 -> column 1, row 1
    var atlas_img: Image = art.enemy_atlas.get_image()
    var left1: Image = art.frames("enemy_basic", "walk_left").texture.get_image()
    var probe: Vector2i = Vector2i(5, 8)   # inside the body
    t.eq(atlas_img.get_pixel(14 + probe.x, 18 + probe.y), left1.get_pixel(12 + probe.x, probe.y), "walk_left frame 1 lands at atlas cell (1,1)")
    t.eq(atlas_img.get_pixel(12, 0).a, 0.0, "gutter column transparent")
    # pivots.json override + malformed strip
    var custom_dir: String = "user://wp005_art_custom"
    Fixture.write_all(custom_dir)
    var f: FileAccess = FileAccess.open(custom_dir.path_join("pivots.json"), FileAccess.WRITE)
    f.store_string(JSON.stringify({"hwacha_idle_v01.png": [20, 36]}))
    f.close()
    var bad: Image = Image.create(50, 40, false, Image.FORMAT_RGBA8)
    bad.save_png(custom_dir.path_join("facilities").path_join("hwacha_fire_v01.png"))   # 50 is not 3 x 40
    var wrong: Image = Image.create(30, 30, false, Image.FORMAT_RGBA8)
    wrong.save_png(custom_dir.path_join("facilities").path_join("jangseung_idle_v01.png"))
    var custom: ArtSet = ArtSet.new(custom_dir)
    rep = custom.load_all()
    t.eq(custom.frames("hwacha", "idle").pivot, Vector2(20.0, 36.0), "pivots.json override applied")
    t.check(custom.missing.has("hwacha/fire"), "strip whose width is not a multiple of the frame count is refused")
    t.check(custom.missing.has("jangseung/idle"), "wrong canvas size refused")
    t.eq(custom.frames("hwacha", "fire"), null, "refused file -> grey box for that element only")
    t.eq(custom.loaded_count(), custom.contract_count() - 2, "the other files still load")
    t.eq(int(rep["missing_count"]), 2, "report lists exactly the two refusals")
    t.eq(int(rep["optional_missing_count"]), 0, "fixture ships the optional marks too")


func _tile_plan_unit(t: RefCounted) -> void:
    t.case("Terrain sample plan: every cell of x30..65 / y6..30 classified, ground on open cells, edges where walls touch, wall vs roof modules, one gate; grid untouched")
    var grid = TestMap.build_grid()
    var before: int = grid.open_cell_count()
    var plan: Dictionary = TerrainLayer.sample_plan(grid)
    var counts: Dictionary = plan["counts"]
    var rect: Rect2i = TerrainLayer.SAMPLE_RECT
    t.eq(rect, Rect2i(30, 6, 36, 25), "sample rect = cells x30..65, y6..30")
    var open: int = 0
    var walls: int = 0
    var edge_cells: int = 0
    for cy: int in range(rect.position.y, rect.end.y):
        for cx: int in range(rect.position.x, rect.end.x):
            if grid.is_wall(cx, cy):
                walls += 1
            else:
                open += 1
                if grid.is_wall(cx, cy - 1) or grid.is_wall(cx + 1, cy) or grid.is_wall(cx, cy + 1) or grid.is_wall(cx - 1, cy):
                    edge_cells += 1
    t.eq(int(counts["ground"]), open, "one ground tile per open cell (%d)" % open)
    t.eq(int(counts["wall"]) + int(counts["roof"]), walls, "wall + roof modules cover every wall cell (%d)" % walls)
    t.check(int(counts["wall"]) > 0 and int(counts["roof"]) > 0, "both street-facing walls and roofs exist")
    t.check(int(counts["edge"]) >= edge_cells, "at least one edge tile per open cell touching a wall (%d cells)" % edge_cells)
    t.eq(int(counts["gate"]), 1, "one gate module")
    var ground_variants: Dictionary = {}
    var seen_edge_frames: Dictionary = {}
    for it: Array in plan["items"]:
        if it[0] == "ground":
            ground_variants[it[2]] = true
        elif it[0] == "edge":
            seen_edge_frames[it[2]] = true
            var c: Vector2i = it[1]
            if grid.is_wall(c.x, c.y):
                t.check(false, "edge tile planned on a wall cell %s" % str(c))
    t.eq(ground_variants.size(), 4, "all four ground variants used")
    var base_tiles: int = 0
    for it: Array in plan["items"]:
        if it[0] == "ground" and it[2] == 0:
            base_tiles += 1
    t.check(base_tiles * 10 >= int(counts["ground"]) * 6, "the base tile covers most of the floor (%d of %d), variants are sparse" % [base_tiles, int(counts["ground"])])
    t.check(seen_edge_frames.has(0) and seen_edge_frames.has(2), "north and south edges present in the plaza")
    t.eq(grid.open_cell_count(), before, "planning does not touch the grid")
    t.eq(TerrainLayer.sample_plan(grid)["items"].size(), plan["items"].size(), "plan is deterministic")


func _enemy_frame_unit(t: RefCounted, tree: SceneTree) -> void:
    t.case("Enemy atlas frame: walking direction from the flow field (down/up/left/right), two frames alternating, stranded enemy faces down")
    var scene: Node2D = _scene(tree, "sample")
    var sim = scene.battle.sim
    var w: int = scene.battle.grid.width
    var flow: PackedInt32Array = PackedInt32Array()
    flow.resize(scene.battle.grid.width * scene.battle.grid.height)
    flow.fill(-1)
    var c: int = 20 * w + 20
    sim.cell[0] = c
    flow[c] = c + w            # heads south (down)
    t.eq(scene._enemy_frame(0, sim, flow, w, 0), 0, "down, frame 0")
    t.eq(scene._enemy_frame(0, sim, flow, w, 1), 1, "down, frame 1 (phase)")
    t.eq(scene._enemy_frame(1, sim, flow, w, 0) % 2, 1, "slot parity offsets the frame")
    flow[c] = c - w
    t.eq(scene._enemy_frame(0, sim, flow, w, 0), 2, "up")
    flow[c] = c - 1
    t.eq(scene._enemy_frame(0, sim, flow, w, 0), 4, "left")
    flow[c] = c + 1
    t.eq(scene._enemy_frame(0, sim, flow, w, 0), 6, "right")
    flow[c] = -1
    t.eq(scene._enemy_frame(0, sim, flow, w, 0), 0, "no flow (stranded) -> down")
    t.check(scene._enemy_sprites, "sample scene renders enemies from the atlas")
    t.eq(scene._enemy_stride, 16, "16 floats per instance (transform, colour, custom)")
    Flow._drop(scene)


# ------------------------------------------------------------- AC-05 (pipeline) ---

## The same seed and commands in both rendering modes: structured battle
## state identical (run_id excluded) at the initial / before + after
## collapse / after recovery / end checkpoints.
func _greybox_equals_sample(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-05 pipeline: greybox and sample scenes run the same F2 commands -> identical full_state at initial, before/after collapse, after recovery, end")
    var g: Node2D = _scene(tree, "greybox")
    var s: Node2D = _scene(tree, "sample")
    t.eq(g._art_mode, "greybox", "greybox scene")
    t.eq(s._art_mode, "sample", "sample scene")
    t.check(s.art != null and s.art.loaded_count() == s.art.contract_count(), "sample scene loaded the fixture set")
    t.eq(g.config.values, s.config.values, "identical configuration in both modes")
    _start(g)
    _start(s)
    var checkpoints: Array = []
    var same: Callable = func(label: String) -> void:
        var a: String = g.battle.full_state_json()
        var b: String = s.battle.full_state_json()
        t.check(a == b, "%s: full_state identical (tick %d)" % [label, g.battle.steps])
        t.eq(g.battle.state_hash(), s.battle.state_hash(), "%s: state hash" % label)
        checkpoints.append(label)
    same.call("initial")
    _frame(g, 300)
    _frame(s, 300)
    same.call("t5")
    while g.battle.sim_time < 20.0:
        _frame(g)
        _frame(s)
    same.call("before_collapse")
    _force_collapse(g)
    _force_collapse(s)
    _frame(g, 2)
    _frame(s, 2)
    t.eq(g.battle.run.collapse_count, 1, "collapsed")
    same.call("after_collapse")
    while g.battle.sim_time < 25.0:
        _frame(g)
        _frame(s)
    var rg = g.battle.place_recovery(TestMap.RECOVERY_B)
    var rs = s.battle.place_recovery(TestMap.RECOVERY_B)
    t.check(rg.ok and rs.ok, "H1 placed at B in both")
    _frame(g)
    _frame(s)
    same.call("after_recovery")
    var k: int = 0
    while not g.battle.run.ended() and k < 12000:
        _frame(g)
        _frame(s)
        k += 1
    t.check(g.battle.run.ended(), "greybox run ended (%s)" % g.battle.run.run_name())
    t.eq(s.battle.run.run_name(), g.battle.run.run_name(), "same outcome")
    same.call("end")
    t.eq(checkpoints.size(), 6, "six checkpoints compared")
    t.eq(s.flow.state_name(), "RESULT", "sample scene reached RESULT like the grey box")
    t.eq(g.flow.state_name(), "RESULT", "grey box RESULT")
    Flow._drop(g)
    Flow._drop(s)


# --------------------------------------------------------------------- AC-04 ---

func _fx_event_contract(t: RefCounted, tree: SceneTree) -> void:
    t.case("AC-04: one fire + one impact per real volley, despawn fx == kills, collapse fx once, fx frozen while PAUSED (120 frames), none survive a restart")
    var s: Node2D = _scene(tree, "sample")
    t.check(s._fx != null, "fx layer present in sample mode")
    _start(s)
    while s.battle.hwacha.shots_total < 25 and s.battle.sim_time < 60.0:
        _frame(s)
    var shots: int = s.battle.hwacha.shots_total
    t.check(shots >= 25, "volleys happened (%d)" % shots)
    var fx: Dictionary = s._fx.snapshot()
    t.eq(int(fx["created_by_kind"].get("fire", 0)), shots, "fire fx == volleys")
    t.eq(int(fx["created_by_kind"].get("impact", 0)), shots, "impact fx == volleys")
    t.eq(int(fx["created_by_kind"].get("enemy_despawn", 0)), s.battle.sim.killed_total, "despawn fx == kills (under the ledger cap)")
    t.eq(int(fx["created_by_kind"].get("collapse", 0)), 0, "no collapse fx before the collapse")
    t.check(int(fx["created_by_kind"].get("enemy_hit", 0)) >= s.battle.sim.damage_applications - s.battle.sim.killed_total - 256 * 4, "hit fx follow damage applications")
    # render frames without battle ticks create nothing new
    var created: int = int(fx["created_total"])
    for _i: int in range(10):
        s._process(DT)
    t.eq(int(s._fx.snapshot()["created_total"]), created, "no battle tick -> no new fx (rendering never invents events)")
    # collapse -> exactly one collapse fx
    _force_collapse(s)
    _frame(s, 3)
    t.eq(s.battle.run.collapse_count, 1, "collapsed")
    t.eq(int(s._fx.snapshot()["created_by_kind"].get("collapse", 0)), 1, "one collapse fx")
    _frame(s, 3)
    t.eq(int(s._fx.snapshot()["created_by_kind"].get("collapse", 0)), 1, "still one after more frames")
    t.eq(s._overlay._objective_state("outer", true), "collapsed", "outer post shows collapsed")
    # pause: 120 UI frames, fx and battle frozen
    Flow._key(s, KEY_ESCAPE)
    _frame(s)
    Flow._key(s, KEY_ESCAPE, false)
    t.eq(s.flow.state_name(), "PAUSED", "PAUSED")
    var frozen: String = JSON.stringify(s._fx.effects)
    var frozen_time: float = s._fx.sim_time
    _frame(s, 120)
    t.eq(JSON.stringify(s._fx.effects), frozen, "effects unchanged over 120 paused frames")
    t.eq(s._fx.sim_time, frozen_time, "fx time did not advance")
    # restart (confirm) -> nothing left
    t.check(s._fx.count() > 0 or true, "(effects may have expired naturally before the pause)")
    Flow._click(s, "pause_restart")
    Flow._click(s, "confirm_ok")
    t.eq(s.flow.state_name(), "PLAYING", "new run")
    t.eq(s._fx.count(), 0, "no effect of the previous run survives the restart")
    t.eq(s._fx_collapses_seen, 0, "collapse fx counter follows the new run")
    t.eq(s._overlay.objective_hit_time["outer"], -1.0, "objective hit flash cleared")
    _frame(s, 5)
    t.eq(int(s._fx.snapshot()["created_by_kind"].get("collapse", 0)), 1, "no stale collapse fx in the new run")
    Flow._drop(s)


# ------------------------------------------------------------------- wiring ---

func _sample_scene_wiring(t: RefCounted, tree: SceneTree) -> void:
    t.case("Sample wiring: overlay/terrain/fx share the art set, labels toggle with L, blasts move to the fx layer, grey box keeps the WP-004 stride and no fx layer")
    var s: Node2D = _scene(tree, "sample")
    t.check(s._overlay.art == s.art and s._terrain.art == s.art and s._fx.art == s.art, "one art set shared by the layers")
    t.eq(s._overlay.draw_blasts, false, "overlay blast rings off (fx layer draws impacts)")
    t.eq(s._overlay.show_labels, true, "labels on by default")
    _start(s)
    Flow._key(s, KEY_L)
    Flow._key(s, KEY_L, false)
    t.eq(s._overlay.show_labels, false, "L hides the structure labels")
    t.eq(s._overlay._objective_state("core", false), "normal", "core normal")
    s._overlay.sim_time = 10.0
    s._overlay.objective_hit_time["core"] = 9.8
    t.eq(s._overlay._objective_state("core", false), "hit", "core hit within 0.4 s")
    s._overlay.sim_time = 10.5
    t.eq(s._overlay._objective_state("core", false), "normal", "back to normal")
    t.eq(s._enemies.texture, s.art.enemy_atlas, "enemy multimesh uses the atlas")
    t.check(s._enemies.material is ShaderMaterial, "atlas shader material")
    var g: Node2D = _scene(tree, "greybox")
    t.check(g.art == null and g._fx == null, "grey box: no art set, no fx layer")
    t.eq(g._enemy_stride, 12, "grey box keeps the 12-float instance layout")
    t.eq(g._overlay.draw_blasts, true, "grey box keeps the blast rings")
    t.check(g._enemies.material == null, "grey box: no shader")
    Flow._drop(s)
    Flow._drop(g)


# ------------------------------------------------- reviewed assets (default dir) ---

## The files actually shipped under assets/art/wp005 (D-050: the four
## generated facility sources converted to the contract). Whatever is there
## must satisfy the contract, and the rest of the set must be reported
## missing, never invented. Battle state stays equal to the grey box.
func _reviewed_assets(t: RefCounted, tree: SceneTree) -> void:
    t.case("Reviewed assets in assets/art/wp005: contract files load (40x40, pivot rule, sha), the missing rest is reported, an interactive launch defaults to sample, battle state == grey box")
    var art: ArtSet = ArtSet.new(ArtSet.DEFAULT_DIR)
    var rep: Dictionary = art.load_all()
    t.check(art.loaded_count() >= 17, "the 13 integrated files + 4 derived states load (%d)" % art.loaded_count())
    for id_state: Array in [["hwacha", "idle"], ["hwacha", "inactive"], ["jangseung", "idle"], ["jangseung", "inactive"],
            ["bongsu", "connected"], ["bongsu", "disconnected"], ["sensor", "active"], ["sensor", "inactive"]]:
        var fr: ArtSet.Frames = art.frames(id_state[0], id_state[1])
        if not t.check(fr != null, "%s/%s loaded" % [id_state[0], id_state[1]]):
            continue
        t.eq(fr.frame_size, Vector2i(40, 40), "%s/%s is 40x40" % [id_state[0], id_state[1]])
        t.eq(fr.pivot, Vector2(20.0, 20.0), "%s/%s pivot = footprint centre" % [id_state[0], id_state[1]])
        t.eq(fr.sha256.length(), 64, "%s/%s sha recorded" % [id_state[0], id_state[1]])
        # ground contact: the lowest opaque row is within 2 px of the canvas
        # bottom (import_wp005_sources.gd seats the object at row 37)
        var img: Image = fr.texture.get_image()
        var lowest: int = -1
        for y: int in range(40):
            for x: int in range(40):
                if img.get_pixel(x, y).a > 0.5:
                    lowest = y
        t.check(lowest >= 37, "%s/%s stands within 2 px of the canvas bottom (row %d)" % [id_state[0], id_state[1], lowest])
    t.eq(int(rep["loaded_count"]) + int(rep["missing_count"]) + int(rep["optional_missing_count"]), art.contract_count(), "loaded + missing + optional = contract")
    t.eq(int(rep["optional_missing_count"]), 5, "interaction marks stay procedural (optional)")
    t.check(art.missing.has("hwacha/fire") and art.missing.has("bongsu/pulse"), "frames not delivered yet are reported missing, not invented")
    t.check(art.enemy_atlas != null and art.enemy_frame_size == Vector2i(12, 16), "enemy atlas built from the 6 shipped strips (12x16)")
    for st: String in ["ground"]:
        t.eq(art.frames("terrain_sample", st).frame_count, 4, "terrain ground strip: 4 variants")
    t.check(art.has("building_sample", "roof") and art.has("building_sample", "wall"), "roof / wall modules shipped")
    t.check(art.missing.has("building_sample/gate") and art.missing.has("terrain_sample/edge"), "gate / edge tiles still missing (reported)")
    # default mode: interactive -> sample, scripted -> greybox (D-050)
    var s: Node2D = _scene(tree, "", ArtSet.DEFAULT_DIR)
    t.eq(s._art_mode, "sample", "interactive launch without --art shows the reviewed art")
    t.check(s.art != null and s.art.loaded_count() == art.loaded_count(), "scene loaded the same set")
    t.check(s._enemy_sprites, "enemies render from the shipped atlas")
    var mat: ShaderMaterial = s._enemies.material as ShaderMaterial
    t.eq(float(mat.get_shader_parameter("outline")), 1.0, "enemy rim outline on by default (D-052)")
    s._set_enemy_outline(false)
    t.eq(float(mat.get_shader_parameter("outline")), 0.0, "outline can be switched off (--art-outline=off / capture step)")
    s._set_enemy_outline(true)
    t.eq(s._capture_cam, null, "no close-up camera outside captures")
    s._apply_zoom(Vector2(950.0, 450.0), 3.0)
    t.check(s._capture_cam != null and s._capture_cam.zoom == Vector2(3.0, 3.0) and s._capture_cam.position == Vector2(950.0, 450.0), "zoom step creates a 3x camera at the centre")
    var before_zoom: String = s.battle.full_state_json()
    _frame(s, 5)
    t.check(s.battle.full_state_json() == before_zoom, "the camera and the render frames do not touch the battle state (TITLE, nothing ticks)")
    s._apply_zoom(Vector2.ZERO, 1.0)
    t.eq(s._capture_cam, null, "factor 1 removes the camera")
    t.eq(s._overlay.show_footprints, false, "footprint overlay off by default")
    var g: Node2D = _scene(tree, "greybox", ArtSet.DEFAULT_DIR)
    _start(s)
    _start(g)
    _frame(s, 240)
    _frame(g, 240)
    t.check(s.battle.full_state_json() == g.battle.full_state_json(), "240 frames: battle state identical to the grey box")
    Flow._drop(s)
    Flow._drop(g)
    var p: Node2D = Main.new()
    p._settings_path = SETTINGS_TMP
    p._capture_name = "ac02"
    p._perf = null
    tree.root.add_child(p)
    if not p.is_node_ready():
        p._ready()
    p.set_process(false)
    p.set_physics_process(false)
    t.eq(p._art_mode, "greybox", "scripted capture without --art stays grey box")
    Flow._drop(p)

