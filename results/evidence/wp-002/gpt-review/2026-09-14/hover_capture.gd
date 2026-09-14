extends SceneTree
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var scene = load("res://game/scenes/main.tscn").instantiate()
    root.add_child(scene)
    await create_timer(4.0).timeout
    scene._paused = true
    scene._overlay.show_cursor = true
    root.warp_mouse(Vector2(940,600))
    await create_timer(0.3).timeout
    scene._overlay.queue_redraw()
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var path = "res://results/evidence/wp-002/gpt-review/2026-09-14/hover_panel.png"
    var err = root.get_texture().get_image().save_png(path)
    print("HOVER_CAPTURE ", err)
    quit(int(err))
