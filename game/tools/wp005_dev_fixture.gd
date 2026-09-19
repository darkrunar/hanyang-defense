extends SceneTree
## WP-005 development fixture: programmatic placeholder PNGs in the exact
## file contract of ArtSet (docs/art/source/WP005_REQUEST.md), written to a
## user:// directory so the loader, the atlas, the fx and the capture pipeline
## can be exercised before the reviewed art exists. These are NOT game assets
## and never go to assets/art/wp005 or the manifest (D-049).
##
##   godot --headless --path . --script res://game/tools/wp005_dev_fixture.gd -- [--out=user://wp005_art_fixture]

const ArtSet := preload("res://game/scenes/art_set.gd")

const DEFAULT_OUT: String = "user://wp005_art_fixture"


func _initialize() -> void:
    var out: String = DEFAULT_OUT
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out = arg.substr("--out=".length())
    var written: Array = write_all(out)
    print("wp005 dev fixture: %d files under %s" % [written.size(), out])
    quit(0)


## Write every contract file. Returns the list of written paths.
static func write_all(dir: String) -> Array:
    var written: Array = []
    for asset_id: String in ArtSet.CONTRACT.keys():
        var states: Dictionary = ArtSet.CONTRACT[asset_id]
        for state: String in states.keys():
            var spec: Array = states[state]
            var sub: String = dir.path_join(str(spec[0]))
            DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sub))
            var frames: int = int(spec[1])
            var img: Image = _make(asset_id, state, frames)
            var path: String = sub.path_join(ArtSet.file_name(asset_id, state))
            if img.save_png(path) == OK:
                written.append(path)
    return written


static func _canvas(asset_id: String, state: String) -> Vector2i:
    match asset_id:
        "terrain_sample": return Vector2i(20, 20)
        "building_sample": return Vector2i(40, 40) if state != "gate" else Vector2i(80, 40)
        "enemy_basic": return Vector2i(12, 16)
        "combat_fx": return Vector2i(48, 48) if state == "collapse" else Vector2i(24, 24)
        "interaction_marks": return Vector2i(16, 16)
        "outer_post", "core_post": return Vector2i(40, 48)
        _: return Vector2i(40, 40)


static func _make(asset_id: String, state: String, frames: int) -> Image:
    var c: Vector2i = _canvas(asset_id, state)
    var img: Image = Image.create(c.x * frames, c.y, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    for f: int in range(frames):
        var ox: int = f * c.x
        match asset_id:
            "terrain_sample":
                if state == "ground":
                    var shades: Array = [Color(0.36, 0.30, 0.22), Color(0.34, 0.29, 0.21), Color(0.38, 0.32, 0.24), Color(0.33, 0.28, 0.20)]
                    _rect(img, ox, 0, c.x, c.y, shades[f])
                    if f == 2:
                        _rect(img, ox + 6, 8, 3, 2, Color(0.30, 0.26, 0.18))
                else:
                    # edge: a 3 px band on the wall side (0 N, 1 E, 2 S, 3 W) or a corner dot (4..7)
                    var col: Color = Color(0.55, 0.45, 0.32)
                    match f:
                        0: _rect(img, ox, 0, c.x, 3, col)
                        1: _rect(img, ox + c.x - 3, 0, 3, c.y, col)
                        2: _rect(img, ox, c.y - 3, c.x, 3, col)
                        3: _rect(img, ox, 0, 3, c.y, col)
                        4: _rect(img, ox + c.x - 4, 0, 4, 4, col)
                        5: _rect(img, ox + c.x - 4, c.y - 4, 4, 4, col)
                        6: _rect(img, ox, c.y - 4, 4, 4, col)
                        7: _rect(img, ox, 0, 4, 4, col)
            "building_sample":
                match state:
                    "roof":
                        _rect(img, ox, 0, c.x, c.y, Color(0.30, 0.22, 0.20))
                        for y: int in range(0, c.y, 5):
                            _rect(img, ox, y, c.x, 1, Color(0.22, 0.16, 0.15))
                    "wall":
                        _rect(img, ox, 0, c.x, c.y, Color(0.42, 0.36, 0.30))
                        for y: int in range(2, c.y, 6):
                            _rect(img, ox, y, c.x, 2, Color(0.36, 0.30, 0.25))
                    "gate":
                        _rect(img, ox, 0, c.x, c.y, Color(0.28, 0.20, 0.16))
                        _rect(img, ox + 8, 12, c.x - 16, c.y - 12, Color(0.55, 0.36, 0.20))
                        _rect(img, ox + c.x / 2 - 1, 12, 2, c.y - 12, Color(0.15, 0.10, 0.08))
            "hwacha":
                _rect(img, ox + 4, 12, 32, 24, Color(0.62, 0.42, 0.18))
                _rect(img, ox + 8, 4, 24, 10, Color(0.85, 0.55, 0.20) if state == "fire" else Color(0.50, 0.34, 0.16))
                if state == "inactive":
                    _rect(img, ox + 4, 12, 32, 24, Color(0.40, 0.40, 0.40))
                if state == "fire":
                    _rect(img, ox + 14, 0, 12 + f * 2, 4, Color(1.0, 0.7, 0.2))
            "jangseung":
                var body: Color = Color(0.55, 0.16, 0.14) if state == "idle" else Color(0.45, 0.42, 0.40)
                _rect(img, ox + 15, 2, 10, 36, body)
                _rect(img, ox + 12, 4, 16, 10, Color(0.85, 0.62, 0.40))
                _rect(img, ox + 15, 7, 3, 2, Color.BLACK)
                _rect(img, ox + 22, 7, 3, 2, Color.BLACK)
            "bongsu":
                _rect(img, ox + 10, 14, 20, 24, Color(0.50, 0.42, 0.34))
                if state != "disconnected":
                    _rect(img, ox + 15, 2 + (f * 2), 10, 12 - f * 2, Color(1.0, 0.75, 0.25))
                    _rect(img, ox + 17, 4 + (f * 2), 6, 6, Color(0.2, 0.9, 0.9))
            "sensor":
                var ring: Color = Color(0.35, 0.75, 0.95) if state == "active" else Color(0.45, 0.45, 0.45)
                _ring(img, ox + 20, 20, 14, 3, ring)
                _ring(img, ox + 20, 20, 7, 2, ring)
                _rect(img, ox + 17, 30, 6, 8, Color(0.4, 0.34, 0.28))
            "outer_post", "core_post":
                var base: Color = Color(0.95, 0.55, 0.20) if asset_id == "outer_post" else Color(0.95, 0.30, 0.30)
                match state:
                    "normal":
                        _rect(img, ox + 6, 10, 28, 38, base)
                        _rect(img, ox + 2, 4, 36, 8, base.darkened(0.3))
                    "hit":
                        _rect(img, ox + 6, 10, 28, 38, Color(1.0, 0.95, 0.85))
                        _rect(img, ox + 2, 4, 36, 8, base)
                    "collapsed":
                        _rect(img, ox + 6, 30, 28, 18, Color(0.30, 0.25, 0.22))
                        _rect(img, ox + 10, 24, 8, 6, Color(0.30, 0.25, 0.22))
            "enemy_basic":
                # bright head at the TOP, dark feet at the BOTTOM: a flipped
                # atlas is visible at a glance in the captures
                var tint: Color = Color(0.75, 0.20, 0.15)
                match state:
                    "walk_left": tint = Color(0.75, 0.35, 0.15)
                    "walk_right": tint = Color(0.60, 0.15, 0.35)
                    "walk_up": tint = Color(0.55, 0.20, 0.20)
                    "hit": tint = Color(1.0, 0.9, 0.6)
                    "despawn": tint = Color(0.35, 0.10, 0.08, 0.7 - 0.3 * f)
                _rect(img, ox + 3, 6, 6, 8, tint)
                _rect(img, ox + 4, 1, 4, 5, Color(0.95, 0.85, 0.70))
                _rect(img, ox + 2 + (f * 2), 14, 3, 2, Color(0.05, 0.05, 0.05))
                _rect(img, ox + 7 - (f * 2), 14, 3, 2, Color(0.05, 0.05, 0.05))
                if state == "walk_left":
                    _rect(img, ox + 1, 8, 2, 3, tint)
                elif state == "walk_right":
                    _rect(img, ox + 9, 8, 2, 3, tint)
            "combat_fx":
                var r: int = (c.x / 2 - 2) * (f + 1) / frames
                var col2: Color = Color(1.0, 0.65, 0.2, 0.9 - 0.25 * f)
                if state == "collapse":
                    col2 = Color(0.95, 0.3, 0.2, 0.9 - 0.25 * f)
                _ring(img, ox + c.x / 2, c.y / 2, r, 2, col2)
                if state == "fire":
                    _rect(img, ox + c.x / 2 - 2, c.y / 2 - 2, 4, 4, Color(1.0, 0.95, 0.7))
            "interaction_marks":
                var mc: Color = Color(0.2, 0.9, 0.9)
                match state:
                    "link_cut": mc = Color(0.9, 0.3, 0.3)
                    "recovery_wait": mc = Color(1.0, 0.85, 0.3)
                    "place_ok": mc = Color(0.4, 0.95, 0.45)
                    "place_bad": mc = Color(1.0, 0.3, 0.3)
                _ring(img, ox + 8, 8, 6, 2, mc)
                if state == "link_cut" or state == "place_bad":
                    _rect(img, ox + 4, 7, 8, 2, mc)
                else:
                    _rect(img, ox + 7, 5, 2, 6, mc)
    return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
    for yy: int in range(y, y + h):
        for xx: int in range(x, x + w):
            if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
                img.set_pixel(xx, yy, col)


static func _ring(img: Image, cx: int, cy: int, r: int, thick: int, col: Color) -> void:
    for yy: int in range(cy - r - 1, cy + r + 2):
        for xx: int in range(cx - r - 1, cx + r + 2):
            var d: float = Vector2(xx - cx, yy - cy).length()
            if d <= r and d > r - thick and xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
                img.set_pixel(xx, yy, col)
