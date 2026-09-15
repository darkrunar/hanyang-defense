extends SceneTree
## WP-003 F1 timeline probe: runs the plain READY v1.0 F1 setup (18 structures,
## 10 zones, waves 1140, no input) and prints a per-second ledger so a FAIL can
## be explained with numbers: wave/state, alive, spawned, killed, outer/core
## arrivals, outer/core HP, per-hwacha shots.
##
##   godot --headless --path . --script res://game/tools/wp003_timeline.gd [-- --out=<abs>.json --limit=300]

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")


func _initialize() -> void:
    var out_path: String = ""
    var limit: float = 300.0
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())
        elif arg.begins_with("--limit="):
            limit = float(arg.substr("--limit=".length()))
    var cfg: Config = Config.for_wp003()
    var b: Battle = Battle.new(cfg)
    var dt: float = cfg.get_num("fixed_dt")
    var rows: Array = []
    var last_sec: int = -1
    var prev: Dictionary = {"killed": 0, "outer_arr": 0, "core_arr": 0, "spawned": 0}
    print("sec | wave state       | alive spawned | killed dKill | outerArr dOut | coreArr dCore | outerHP coreHP | run")
    while b.sim_time < limit and not b.run.ended():
        b.step(dt)
        var sec: int = int(floor(b.sim_time))
        if sec != last_sec:
            last_sec = sec
            var ws: Dictionary = b.waves.snapshot()
            var row: Dictionary = {
                "sec": sec, "wave": ws["wave_name"], "state": ws["state"], "alive": b.sim.alive_count,
                "spawned": b.sim.spawned_total, "killed": b.sim.killed_total,
                "outer_arrivals": b.run.outer_arrivals, "core_arrivals": b.run.core_arrivals,
                "outer_hp": b.run.outer_hp, "core_hp": b.run.core_hp, "defense": b.run.defense_name(),
                "run": b.run.run_name(), "collapse_tick": b.run.collapse_tick,
            }
            var shots: Array = []
            for h: Placement.Structure in b.placement.hwachas():
                shots.append([h.label, h.shots_fired, h.kills, h.active])
            row["hwachas"] = shots
            rows.append(row)
            print("%3d | %-3s %-12s | %5d %7d | %6d %5d | %8d %4d | %7d %5d | %7.0f %6.0f | %s/%s" % [
                sec, ws["wave_name"], ws["state"], b.sim.alive_count, b.sim.spawned_total,
                b.sim.killed_total, b.sim.killed_total - int(prev["killed"]),
                b.run.outer_arrivals, b.run.outer_arrivals - int(prev["outer_arr"]),
                b.run.core_arrivals, b.run.core_arrivals - int(prev["core_arr"]),
                b.run.outer_hp, b.run.core_hp, b.run.run_name(), b.run.defense_name()])
            prev = {"killed": b.sim.killed_total, "outer_arr": b.run.outer_arrivals, "core_arr": b.run.core_arrivals, "spawned": b.sim.spawned_total}
    var summary: Dictionary = {"ended_at": b.sim_time, "run": b.run.run_name(), "collapse_tick": b.run.collapse_tick,
        "collapse_sim_time": b.run.collapse_sim_time, "spawned": b.sim.spawned_total, "killed": b.sim.killed_total,
        "outer_arrivals": b.run.outer_arrivals, "core_arrivals": b.run.core_arrivals, "peak_alive": b.peak_alive,
        "outer_hp": b.run.outer_hp, "core_hp": b.run.core_hp, "waves": b.waves.snapshot(), "events": b.run.events}
    print(JSON.stringify(summary))
    if out_path != "":
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify({"rows": rows, "summary": summary}, "  "))
            f.close()
    quit(0)
