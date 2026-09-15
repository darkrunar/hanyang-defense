extends RefCounted
## All WP-001 / WP-002 balance and scenario numbers in one place.
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
    # Benchmark-only: after every tick, refill to target_alive immediately so
    # the measured load never dips below the D-009 requirement. Off in play;
    # the --perf mode turns it on (GPT review R-02).
    "benchmark_hold_alive": false,

    # --- enemy ---
    "enemy_speed": 58.0,
    "enemy_speed_jitter": 0.22,
    "enemy_lane_offset": 7.0,
    "enemy_hp": 60.0,
    "enemy_draw_size": 9.0,
    "goal_radius": 26.0,

    # --- WP-002 bongsu network (D-012 / D-013) ---
    # targeting_mode: "wp002" = each hwacha only knows enemies inside its own
    # local detection radius plus what active sensors in its bongsu group see;
    # "wp001" = the original global-density targeting, kept for the WP-001
    # verification fixtures.
    "targeting_mode": "wp002",
    # fixture: initial structures. "b" = WP-002 fixture B (4 hwacha, 8 bongsu,
    # 4 sensors); "wp001" = the 4 WP-001 hwachas; "none" = empty field.
    "fixture": "b",
    "bongsu_link_range": 180.0,   # bongsu-bongsu edge and terminal attachment
    "sensor_range": 140.0,        # sensor centre -> living enemy position
    "hwacha_local_range": 100.0,  # hwacha centre -> living enemy position

    # --- WP-003 collapse / retreat (D-022..D-027) ---
    # zone_set: "wp001" = the 8 original zones; "wp003" = those + Z8/Z9.
    "zone_set": "wp001",
    # arrival_mode: "immediate" = an enemy inside the goal radius is consumed
    # during movement (WP-001/002); "after_fire" = arrivals are collected after
    # the hwachas have fired, so an enemy killed on the doorstep deals no damage.
    "arrival_mode": "immediate",
    # run_mode: "sandbox" = top-up spawning, no strongholds (WP-001/002);
    # "waves" = finite waves, stronghold HP, collapse, win/lose (WP-003).
    "run_mode": "sandbox",
    # district_rules: footprint must lie in one district; outer refused after collapse.
    "district_rules": false,
    "outer_hp": 120.0,
    "core_hp": 60.0,
    "arrival_damage": 1.0,
    "wave_gap_seconds": 5.0,
    # Benchmark-only (D-027): core HP is held, attempts are counted.
    "benchmark_core_invulnerable": false,

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


## The WP-001 verification configuration: global-density targeting and the
## four original hwachas, byte-for-byte the behaviour GPT approved in d9699aa.
static func for_wp001():
    var c = new()
    c.values["targeting_mode"] = "wp001"
    c.values["fixture"] = "wp001"
    return c


## The WP-003 contract (backlog/WP-003.md READY v1.0): fixture C (16 + 2 outer
## jangseung), 10 zones, arrival after fire, finite waves, districts.
static func for_wp003():
    var c = new()
    c.values["targeting_mode"] = "wp002"
    c.values["fixture"] = "c"
    c.values["zone_set"] = "wp003"
    c.values["arrival_mode"] = "after_fire"
    c.values["run_mode"] = "waves"
    c.values["district_rules"] = true
    c.values["combat_enabled"] = true
    return c


func get_str(key: String) -> String:
    return str(values[key])


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
    elif proto is String:
        values[key] = raw
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
