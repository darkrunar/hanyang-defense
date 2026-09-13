extends SceneTree
## Measures how often a lane placement is legal while the lane is saturated.
##
##   godot --headless --path . --script res://game/tools/probe_occupancy.gd

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")


func _initialize() -> void:
    var cfg: Config = Config.new()
    cfg.values["combat_enabled"] = true
    var b: Battle = Battle.new(cfg)
    b.run_for(30.0)
    print("settled: alive=%d  %s" % [b.sim.alive_count, b.route_summary()])

    var dt: float = b.config.get_num("fixed_dt")
    var reasons: Dictionary = {}
    var attempts: int = 0
    var accepted: int = 0
    # Sweep every 2x2 anchor down both south lanes, once per simulated 0.1 s,
    # for 10 s of saturated traffic.
    for tick: int in range(100):
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

    print("lane placement attempts=%d accepted=%d (%.2f%%)" % [
        attempts, accepted, 100.0 * float(accepted) / float(attempts)
    ])
    for k: String in reasons:
        print("  refused %-24s %d" % [k, reasons[k]])
    quit(0)
