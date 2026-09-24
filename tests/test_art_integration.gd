extends RefCounted
## Real on-disk assets, independent of the development fixture.
const Pipeline = preload("res://tests/test_art_sample.gd")
const Flow = preload("res://tests/test_play_flow.gd")
const ArtSet = preload("res://game/scenes/art_set.gd")
const TestMap = preload("res://game/maps/hanyang_test_map.gd")

func compare(t: RefCounted, g: Node2D, s: Node2D, scenario: String, point: String) -> void:
    t.check(g.battle.full_state_json() == s.battle.full_state_json(), "%s %s real assets: full_state identical" % [scenario, point])

func run(t: RefCounted) -> void:
    var tree = Engine.get_main_loop() as SceneTree
    var art = ArtSet.new()
    art.load_all()
    t.case("R-01/03 real assets: enemy bounds and inactive silhouettes")
    var geometry = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/wp005/enemy_geometry.json"))
    t.eq(geometry.frames.size(), 12, "all twelve enemy frames checked")
    for frame in geometry.frames:
        t.check(frame.runtime_size[0] <= 12 and frame.runtime_size[1] <= 16 and not frame.clipped, "%s/%s fits canvas without clipping" % [frame.state, frame.frame])
    for id in ["hwacha", "jangseung", "bongsu", "sensor"]:
        var off = "disconnected" if id == "bongsu" else "inactive"
        t.check(art.has(id, off), "%s inactive state exists" % id)
    for scenario in ["F1", "F2", "F4"]:
        t.case("AC-05 real asset " + scenario)
        var g = Pipeline._scene(tree, "greybox", ArtSet.DEFAULT_DIR)
        var s = Pipeline._scene(tree, "sample", ArtSet.DEFAULT_DIR)
        t.check(s.art.enemy_atlas != null and s.art.loaded_count() >= 17, "real resource set and enemy atlas loaded")
        t.eq(s._art_dir, ArtSet.DEFAULT_DIR, "uses production directory, not fixture")
        t.eq(g.config.values, s.config.values, "same configuration and seed")
        Pipeline._start(g)
        Pipeline._start(s)
        compare(t, g, s, scenario, "initial")
        while g.battle.sim_time < 20.0:
            Pipeline._frame(g)
            Pipeline._frame(s)
        compare(t, g, s, scenario, "before_collapse")
        if scenario != "F1":
            Pipeline._force_collapse(g)
            Pipeline._force_collapse(s)
            Pipeline._frame(g, 2)
            Pipeline._frame(s, 2)
            t.eq(s.battle.run.collapse_count, 1, "collapse occurred")
            compare(t, g, s, scenario, "after_collapse")
        while g.battle.sim_time < 25.0:
            Pipeline._frame(g)
            Pipeline._frame(s)
        if scenario == "F2":
            var a = g.battle.place_recovery(TestMap.RECOVERY_B)
            var b = s.battle.place_recovery(TestMap.RECOVERY_B)
            t.check(a.ok and b.ok, "same recovery accepted in both modes")
        elif scenario == "F4":
            for scene in [g, s]:
                scene.battle.force_core_hp(1.0, "F4 terminal comparison")
                scene.battle.spawn_extra(Vector2(950, 210), 1, "F4 last arrival")
        Pipeline._frame(g)
        Pipeline._frame(s)
        compare(t, g, s, scenario, "after_commands_t25")
        var ticks = 0
        while not g.battle.run.ended() and ticks < 12000:
            Pipeline._frame(g)
            Pipeline._frame(s)
            ticks += 1
        t.check(g.battle.run.ended() and s.battle.run.ended(), "both runs ended")
        t.eq(s.battle.run.run_name(), "LOST" if scenario == "F4" else "WON", "expected scenario outcome")
        compare(t, g, s, scenario, "end")
        Flow._drop(g)
        Flow._drop(s)
