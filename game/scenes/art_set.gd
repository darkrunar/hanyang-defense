extends RefCounted
## WP-005 art set loader (D-049). Reads the reviewed game PNGs listed in
## docs/art/ASSET_MANIFEST.csv from `assets/art/wp005/` (or an injected
## directory), slices frame strips, builds the enemy atlas and reports what is
## missing. Rendering falls back to the grey-box drawing for every element
## that has no file, so `--art=sample` never depends on a complete set.
##
## File contract (docs/art/source/WP005_REQUEST.md): one RGBA PNG per state,
## `<asset_id>_<state>_v01.png`; a state with N frames is a horizontal strip
## of N equal frames (canvas width x N, no gutters). Pivots default to the
## bottom-centre-minus-half-footprint rule of ART_GUIDE and can be overridden
## per file in `pivots.json` ({"file.png": [px, py]}).

const DEFAULT_DIR: String = "res://assets/art/wp005"

## asset_id -> { state -> [subdir, frames, canvas Vector2i (0,0 = any)] }
const CONTRACT: Dictionary = {
    "terrain_sample": {
        "ground": ["terrain", 4, Vector2i(20, 20)],
        "edge": ["terrain", 8, Vector2i(20, 20)],
    },
    "building_sample": {
        "roof": ["buildings", 1, Vector2i(0, 0)],
        "wall": ["buildings", 1, Vector2i(0, 0)],
        "gate": ["buildings", 1, Vector2i(0, 0)],
    },
    "hwacha": {
        "idle": ["facilities", 1, Vector2i(40, 0)],
        "inactive": ["facilities", 1, Vector2i(40, 0)],
        "fire": ["facilities", 3, Vector2i(40, 0)],
    },
    "jangseung": {
        "idle": ["facilities", 1, Vector2i(40, 0)],
        "inactive": ["facilities", 1, Vector2i(40, 0)],
    },
    "bongsu": {
        "connected": ["facilities", 1, Vector2i(40, 0)],
        "disconnected": ["facilities", 1, Vector2i(40, 0)],
        "pulse": ["facilities", 2, Vector2i(40, 0)],
    },
    "sensor": {
        "active": ["facilities", 1, Vector2i(40, 0)],
        "inactive": ["facilities", 1, Vector2i(40, 0)],
    },
    "outer_post": {
        "normal": ["objectives", 1, Vector2i(0, 0)],
        "hit": ["objectives", 1, Vector2i(0, 0)],
        "collapsed": ["objectives", 1, Vector2i(0, 0)],
    },
    "core_post": {
        "normal": ["objectives", 1, Vector2i(0, 0)],
        "hit": ["objectives", 1, Vector2i(0, 0)],
        "collapsed": ["objectives", 1, Vector2i(0, 0)],
    },
    "enemy_basic": {
        "walk_down": ["enemies", 2, Vector2i(0, 0)],
        "walk_up": ["enemies", 2, Vector2i(0, 0)],
        "walk_left": ["enemies", 2, Vector2i(0, 0)],
        "walk_right": ["enemies", 2, Vector2i(0, 0)],
        "hit": ["enemies", 2, Vector2i(0, 0)],
        "despawn": ["enemies", 2, Vector2i(0, 0)],
    },
    "combat_fx": {
        "fire": ["fx", 3, Vector2i(0, 0)],
        "impact": ["fx", 3, Vector2i(0, 0)],
        "collapse": ["fx", 3, Vector2i(0, 0)],
    },
    "interaction_marks": {
        "link_ok": ["marks", 1, Vector2i(0, 0)],
        "link_cut": ["marks", 1, Vector2i(0, 0)],
        "recovery_wait": ["marks", 1, Vector2i(0, 0)],
        "place_ok": ["marks", 1, Vector2i(0, 0)],
        "place_bad": ["marks", 1, Vector2i(0, 0)],
    },
}

## Enemy atlas layout: frame index = ENEMY_FRAME[state] + frame
const ENEMY_STATES: Array[String] = ["walk_down", "walk_up", "walk_left", "walk_right", "hit", "despawn"]
const ENEMY_FRAME_BASE: Dictionary = {"walk_down": 0, "walk_up": 2, "walk_left": 4, "walk_right": 6, "hit": 8, "despawn": 10}
const ENEMY_FRAMES_TOTAL: int = 12
const ATLAS_GUTTER: int = 2
const ATLAS_COLUMNS: int = 4


class Frames:
    extends RefCounted
    var asset_id: String = ""
    var state: String = ""
    var path: String = ""
    var texture: Texture2D = null
    var frame_size: Vector2i = Vector2i.ZERO
    var frame_count: int = 0
    var pivot: Vector2 = Vector2.ZERO     # canvas px, anchored on the footprint centre
    var sha256: String = ""

    func region(frame: int) -> Rect2:
        var f: int = frame % maxi(frame_count, 1)
        return Rect2(Vector2(f * frame_size.x, 0), Vector2(frame_size))


var dir: String = DEFAULT_DIR
var version: String = "v01"
## asset_id -> state -> Frames (only the files that loaded)
var loaded: Dictionary = {}
## "asset_id/state" -> reason, for every contract entry without a usable file
var missing: Dictionary = {}
var pivots: Dictionary = {}
## Enemy atlas (built when all six enemy states loaded with one frame size)
var enemy_atlas: ImageTexture = null
var enemy_frame_size: Vector2i = Vector2i.ZERO
var enemy_atlas_size: Vector2i = Vector2i.ZERO
var enemy_atlas_pitch: Vector2i = Vector2i.ZERO


func _init(directory: String = DEFAULT_DIR) -> void:
    dir = directory


static func file_name(asset_id: String, state: String, ver: String = "v01") -> String:
    return "%s_%s_%s.png" % [asset_id, state, ver]


## Load every contract file that exists. Never raises: a missing or malformed
## file is reported in `missing` and the element keeps its grey-box drawing.
func load_all() -> Dictionary:
    loaded.clear()
    missing.clear()
    _load_pivots()
    for asset_id: String in CONTRACT.keys():
        var states: Dictionary = CONTRACT[asset_id]
        for state: String in states.keys():
            var spec: Array = states[state]
            var path: String = dir.path_join(str(spec[0])).path_join(file_name(asset_id, state, version))
            var fr: Frames = _load_frames(asset_id, state, path, int(spec[1]), spec[2])
            if fr == null:
                continue
            if not loaded.has(asset_id):
                loaded[asset_id] = {}
            loaded[asset_id][state] = fr
    _build_enemy_atlas()
    return report()


func _load_pivots() -> void:
    pivots = {}
    var p: String = dir.path_join("pivots.json")
    if not FileAccess.file_exists(p):
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
    if parsed is Dictionary:
        pivots = parsed


func _load_frames(asset_id: String, state: String, path: String, frames: int, canvas: Vector2i) -> Frames:
    var key: String = "%s/%s" % [asset_id, state]
    if not FileAccess.file_exists(path):
        missing[key] = "missing: %s" % path
        return null
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
    var img: Image = Image.new()
    if img.load_png_from_buffer(bytes) != OK:
        missing[key] = "not a PNG: %s" % path
        return null
    if img.get_width() % frames != 0:
        missing[key] = "width %d is not a multiple of %d frames: %s" % [img.get_width(), frames, path]
        return null
    var fw: int = img.get_width() / frames
    var fh: int = img.get_height()
    if canvas.x > 0 and fw != canvas.x:
        missing[key] = "frame width %d != %d: %s" % [fw, canvas.x, path]
        return null
    if canvas.y > 0 and fh != canvas.y:
        missing[key] = "frame height %d != %d: %s" % [fh, canvas.y, path]
        return null
    if img.get_format() != Image.FORMAT_RGBA8:
        img.convert(Image.FORMAT_RGBA8)
    var fr: Frames = Frames.new()
    fr.asset_id = asset_id
    fr.state = state
    fr.path = path
    fr.texture = ImageTexture.create_from_image(img)
    fr.frame_size = Vector2i(fw, fh)
    fr.frame_count = frames
    fr.sha256 = FileAccess.get_sha256(path)
    var fname: String = path.get_file()
    if pivots.has(fname) and pivots[fname] is Array and (pivots[fname] as Array).size() == 2:
        fr.pivot = Vector2(float(pivots[fname][0]), float(pivots[fname][1]))
    else:
        match asset_id:
            "enemy_basic":
                fr.pivot = Vector2(fw * 0.5, fh)            # body bottom centre (ART_GUIDE)
            "combat_fx", "terrain_sample", "interaction_marks", "building_sample":
                fr.pivot = Vector2(fw * 0.5, fh * 0.5)      # centred on the cell / event
            _:
                # Facilities and posts: the canvas bottom-centre minus half a
                # 40 px footprint sits on the footprint centre; a 40x40 canvas
                # is exactly the footprint (ART_GUIDE 크기·좌표).
                fr.pivot = Vector2(fw * 0.5, fh - 20.0)
    return fr


## One RGBA atlas with 2 px gutters: 4 columns x 3 rows of the enemy frame size.
func _build_enemy_atlas() -> void:
    enemy_atlas = null
    if not loaded.has("enemy_basic"):
        return
    var states: Dictionary = loaded["enemy_basic"]
    var size: Vector2i = Vector2i.ZERO
    for st: String in ENEMY_STATES:
        if not states.has(st):
            missing["enemy_basic/atlas"] = "atlas needs every enemy state; missing %s" % st
            return
        var fr: Frames = states[st]
        if size == Vector2i.ZERO:
            size = fr.frame_size
        elif fr.frame_size != size:
            missing["enemy_basic/atlas"] = "frame sizes differ (%s vs %s)" % [str(size), str(fr.frame_size)]
            return
    enemy_frame_size = size
    enemy_atlas_pitch = size + Vector2i(ATLAS_GUTTER, ATLAS_GUTTER)
    var rows: int = int(ceil(float(ENEMY_FRAMES_TOTAL) / float(ATLAS_COLUMNS)))
    enemy_atlas_size = Vector2i(ATLAS_COLUMNS * enemy_atlas_pitch.x, rows * enemy_atlas_pitch.y)
    var atlas: Image = Image.create(enemy_atlas_size.x, enemy_atlas_size.y, false, Image.FORMAT_RGBA8)
    atlas.fill(Color(0, 0, 0, 0))
    for st: String in ENEMY_STATES:
        var fr: Frames = states[st]
        var src: Image = fr.texture.get_image()
        for f: int in range(fr.frame_count):
            var idx: int = int(ENEMY_FRAME_BASE[st]) + f
            var dst: Vector2i = Vector2i((idx % ATLAS_COLUMNS) * enemy_atlas_pitch.x, int(idx / ATLAS_COLUMNS) * enemy_atlas_pitch.y)
            atlas.blit_rect(src, Rect2i(Vector2i(f * size.x, 0), size), dst)
    enemy_atlas = ImageTexture.create_from_image(atlas)


func has(asset_id: String, state: String) -> bool:
    return loaded.has(asset_id) and (loaded[asset_id] as Dictionary).has(state)


func frames(asset_id: String, state: String) -> Frames:
    if not has(asset_id, state):
        return null
    return loaded[asset_id][state]


func loaded_count() -> int:
    var n: int = 0
    for a: String in loaded.keys():
        n += (loaded[a] as Dictionary).size()
    return n


func contract_count() -> int:
    var n: int = 0
    for a: String in CONTRACT.keys():
        n += (CONTRACT[a] as Dictionary).size()
    return n


## Evidence record: what rendered from files and what fell back (manifest / captures).
func report() -> Dictionary:
    var files: Array = []
    for a: String in loaded.keys():
        for st: String in (loaded[a] as Dictionary).keys():
            var fr: Frames = loaded[a][st]
            files.append({"asset_id": a, "state": st, "path": fr.path, "frame_size": [fr.frame_size.x, fr.frame_size.y],
                "frames": fr.frame_count, "pivot": [fr.pivot.x, fr.pivot.y], "sha256": fr.sha256})
    var miss: Array = []
    var keys: Array = missing.keys()
    keys.sort()
    for k: String in keys:
        miss.append({"id": k, "reason": missing[k]})
    return {"dir": dir, "version": version, "loaded": files, "loaded_count": files.size(),
        "contract_count": contract_count(), "missing": miss, "missing_count": miss.size(),
        "enemy_atlas": enemy_atlas != null, "enemy_frame_size": [enemy_frame_size.x, enemy_frame_size.y]}
