extends RefCounted
## All WP-001 balance and scenario numbers in one place.
##
## CLAUDE.md rule 4: balance values live in configuration data, not scattered in
## code, and every test scenario records its seed. Any field can be overridden on
## the command line (`--set key=value`) or from a JSON file (`--config=path`).

const DEFAULTS: Dictionary = {
    # --- scenario ---
    "seed": 20260913,
    "target_alive": 1000,        # concurrent living enemies to hold on the field
    "spawn_rate": 420.0,         # enemies per second while topping up
    "combat_enabled": true,      # false = hwachas hold fire (AC-01 counting run)
    "enemy_capacity": 6000,      # pool size; spawn stops when exhausted

    # --- enemy ---
    "enemy_speed": 58.0,
    "enemy_speed_jitter": 0.22,
    "enemy_lane_offset": 7.0,
    "enemy_hp": 60.0,
    "enemy_draw_size": 9.0,
    "goal_radius": 26.0,

    # --- hwacha ---
    "hwacha_range": 200.0,
    "hwacha_blast_radius": 55.0,
    "hwacha_damage": 34.0,     # 2 volleys kill a full-hp enemy
    "hwacha_cooldown": 0.8,    # short enough to land 2 volleys during lane transit

    # --- simulation ---
    "fixed_dt": 0.0166666667,    # 60 Hz fixed step
    "max_steps_per_frame": 4,
}


var values: Dictionary = {}


func _init() -> void:
    values = DEFAULTS.duplicate(true)


func get_num(key: String) -> float:
    return float(values[key])


func get_int(key: String) -> int:
    return int(values[key])


func get_bool(key: String) -> bool:
    var v: Variant = values[key]
    if v is bool:
        return v
    return float(v) != 0.0


func set_value(key: String, raw: String) -> bool:
    if not DEFAULTS.has(key):
        return false
    var proto: Variant = DEFAULTS[key]
    if proto is bool:
        values[key] = raw == "1" or raw.to_lower() == "true"
    elif proto is int:
        values[key] = int(raw)
    else:
        values[key] = float(raw)
    return true


func merge_json(path: String) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var text: String = FileAccess.get_file_as_string(path)
    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        return false
    for k: String in (parsed as Dictionary):
        if DEFAULTS.has(k):
            values[k] = (parsed as Dictionary)[k]
    return true


func to_dictionary() -> Dictionary:
    return values.duplicate(true)
