extends SceneTree
const H = preload("res://tests/test_play_flow.gd")
func _initialize():
    call_deferred("run")
func run():
    var s = H._new_scene(self, "user://wp005_capture_settings.cfg")
    H._start(s)
    H._frame(s, 720)
    s._overlay.show_cursor = false
    s._show_ranges = false
    s._show_zones = false
    s._show_detail = false
    s._detail.visible = false
    var checks = []
    for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
        DisplayServer.window_set_size(resolution)
        for mode in ["greybox","sample"]:
            s._overlay.art_mode = mode
            var before = s.battle.full_state_json()
            for i in range(3):
                s._process(0.016666667)
                await process_frame
            await RenderingServer.frame_post_draw
            var file = "res://results/evidence/wp-005/%s_%d.png" % [mode,resolution.y]
            root.get_texture().get_image().save_png(file)
            checks.append({"mode":mode,"height":resolution.y,"state_unchanged":before==s.battle.full_state_json()})
    H._force_collapse(s)
    s._overlay.art_mode = "sample"
    for i in range(3):
        s._process(0.016666667)
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://results/evidence/wp-005/sample_collapsed_720.png")
    var f = FileAccess.open("res://results/evidence/wp-005/render_checks.json",FileAccess.WRITE)
    f.store_string(JSON.stringify(checks,"  ")+"\n")
    H._drop(s)
    quit()
