extends SceneTree
## P-007 measurement: how often a lane placement is legal while the lane is
## saturated, and how long a player who holds the mouse on one anchor waits.
##
##   godot --headless --path . --script res://game/tools/probe_occupancy.gd [-- --out=<abs path.json>]

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const SWEEP_TICKS: int = 100          # 10 s at one sweep per 0.1 s
const HOLD_TRIALS: int = 20
const HOLD_MAX_SECONDS: float = 30.0


func _initialize() -> void:
    var out_path: String = ""
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())

    var cfg: Config = Config.for_wp001()
    cfg.values["combat_enabled"] = true
    var b: Battle = Battle.new(cfg)
    b.run_for(30.0)
    var dt: float = cfg.get_num("fixed_dt")
    print("settled: alive=%d  %s" % [b.sim.alive_count, b.route_summary()])

    # --- 1. instantaneous legality sweep over every south-lane anchor ---
    var reasons: Dictionary = {}
    var attempts: int = 0
    var accepted: int = 0
    for _tick: int in range(SWEEP_TICKS):
        for _i: int in range(6):
            b.step(dt)
        for lane_x: int in [44, 48]:
            for y: int in range(31, 43):
                var res: Placement.Result = b.placement.try_place(
                    Placement.Kind.JANGSEUNG, Vector2i(lane_x, y), b.sim, "probe"
                )
                attempts += 1
                if res.ok:
                    accepted += 1
                    b.placement.remove(res.structure.id)
                else:
                    var name: String = Placement.reject_name(res.reason)
                    reasons[name] = int(reasons.get(name, 0)) + 1
    var rate: float = 100.0 * float(accepted) / float(attempts)
    print("sweep: attempts=%d accepted=%d (%.2f%%)" % [attempts, accepted, rate])
    for k: String in reasons:
        print("  refused %-24s %d" % [k, reasons[k]])

    # --- 2. hold-to-place wait: retry one anchor every tick until accepted ---
    var anchors: Array = [
        TestMap.AC_SCENARIO_ANCHORS["south_west_lane"],
        TestMap.AC_SCENARIO_ANCHORS["south_east_lane"],
    ]
    var waits: Array = []
    var timeouts: int = 0
    var max_ticks: int = int(HOLD_MAX_SECONDS / dt)
    for trial: int in range(HOLD_TRIALS):
        var anchor: Vector2i = anchors[trial % anchors.size()]
        var ticks: int = 0
        var placed_id: int = -1
        while ticks < max_ticks:
            var res: Placement.Result = b.place_jangseung(anchor)
            if res.ok:
                placed_id = res.structure.id
                break
            b.step(dt)
            ticks += 1
        if placed_id >= 0:
            waits.append(float(ticks) * dt)
            # leave it standing for a moment so traffic re-routes, then remove
            for _i: int in range(60):
                b.step(dt)
            b.placement.remove(placed_id)
            for _i: int in range(120):
                b.step(dt)
        else:
            timeouts += 1
    var w_min: float = 0.0
    var w_max: float = 0.0
    var w_avg: float = 0.0
    if not waits.is_empty():
        w_min = waits[0]
        w_max = waits[0]
        for w: float in waits:
            w_min = minf(w_min, w)
            w_max = maxf(w_max, w)
            w_avg += w
        w_avg /= float(waits.size())
    print("hold-to-place: trials=%d placed=%d timeouts(>%ds)=%d wait s min/avg/max = %.2f / %.2f / %.2f" % [
        HOLD_TRIALS, waits.size(), int(HOLD_MAX_SECONDS), timeouts, w_min, w_avg, w_max
    ])

    if out_path != "":
        var report: Dictionary = {
            "seed": cfg.get_int("seed"),
            "settle_seconds": 30.0,
            "sweep_attempts": attempts,
            "sweep_accepted": accepted,
            "sweep_accept_rate_pct": rate,
            "sweep_refusals": reasons,
            "hold_trials": HOLD_TRIALS,
            "hold_placed": waits.size(),
            "hold_timeouts": timeouts,
            "hold_wait_seconds": waits,
            "hold_wait_min": w_min,
            "hold_wait_avg": w_avg,
            "hold_wait_max": w_max,
        }
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify(report, "  "))
            f.close()
            print("report written: %s" % out_path)
    quit(0)
