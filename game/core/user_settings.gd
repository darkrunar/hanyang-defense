extends RefCounted
## WP-004 §5 / D-041: persisted user settings. Only the window mode for now;
## sliders for features that do not exist are not created. A missing,
## malformed or out-of-range file yields the defaults and never blocks the
## launch; a failed save is reported so the session can continue with the
## value in memory. The path is injectable so tests and captures never touch
## the player's real file, and scripted verification modes do not load it.

const DEFAULT_PATH: String = "user://settings.cfg"
const SECTION: String = "display"
const KEY_WINDOW_MODE: String = "window_mode"
const WINDOW_MODES: Array[String] = ["windowed", "fullscreen"]
const DEFAULT_WINDOW_MODE: String = "windowed"

var path: String = DEFAULT_PATH
var window_mode: String = DEFAULT_WINDOW_MODE
## Outcome of the last load / save for the UI and the evidence log.
var last_load: Dictionary = {}
var last_save: Dictionary = {}


func _init(file_path: String = DEFAULT_PATH) -> void:
    path = file_path


static func is_valid_window_mode(v: String) -> bool:
    return v in WINDOW_MODES


## Load from `path`. Returns {ok, reason, window_mode}. reason: "loaded",
## "missing", "parse_error", "invalid_value", "missing_key".
func load() -> Dictionary:
    window_mode = DEFAULT_WINDOW_MODE
    var out: Dictionary = {"ok": false, "reason": "", "path": path, "window_mode": DEFAULT_WINDOW_MODE}
    if not FileAccess.file_exists(path):
        out["reason"] = "missing"
        last_load = out
        return out
    var cf: ConfigFile = ConfigFile.new()
    var err: int = cf.load(path)
    if err != OK:
        out["reason"] = "parse_error"
        out["error"] = error_string(err)
        last_load = out
        return out
    if not cf.has_section_key(SECTION, KEY_WINDOW_MODE):
        out["reason"] = "missing_key"
        last_load = out
        return out
    var v: Variant = cf.get_value(SECTION, KEY_WINDOW_MODE, DEFAULT_WINDOW_MODE)
    if not (v is String) or not is_valid_window_mode(v):
        out["reason"] = "invalid_value"
        out["raw"] = str(v)
        last_load = out
        return out
    window_mode = v
    out["ok"] = true
    out["reason"] = "loaded"
    out["window_mode"] = window_mode
    last_load = out
    return out


## Save to `path`. Returns {ok, error}. Never throws; the caller shows a notice on failure.
func save() -> Dictionary:
    var cf: ConfigFile = ConfigFile.new()
    cf.set_value(SECTION, KEY_WINDOW_MODE, window_mode)
    var err: int = cf.save(path)
    last_save = {"ok": err == OK, "error": error_string(err) if err != OK else "", "path": path, "window_mode": window_mode}
    return last_save


## Set + save in one step (the settings screen applies immediately).
func set_window_mode(v: String) -> Dictionary:
    if not is_valid_window_mode(v):
        return {"ok": false, "error": "invalid window mode '%s'" % v, "path": path, "window_mode": window_mode}
    window_mode = v
    return save()


func toggle_window_mode() -> Dictionary:
    return set_window_mode("fullscreen" if window_mode == "windowed" else "windowed")


func window_mode_label() -> String:
    return "전체화면" if window_mode == "fullscreen" else "창 모드"


func snapshot() -> Dictionary:
    return {"path": path, "window_mode": window_mode, "last_load": last_load.duplicate(), "last_save": last_save.duplicate()}
