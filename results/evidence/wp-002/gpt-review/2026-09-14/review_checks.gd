extends SceneTree
const Battle = preload("res://game/core/battle.gd")
const Config = preload("res://game/core/config.gd")
const Placement = preload("res://game/core/placement.gd")
class CountingNetwork extends "res://game/core/bongsu_network.gd":
    var candidate_calls: int = 0
    var detect_calls: int = 0
    func detect(p, s) -> void:
        detect_calls += 1
        super.detect(p, s)
    func known_zone_counts(h, d, s, loc) -> PackedInt32Array:
        candidate_calls += 1
        return super.known_zone_counts(h, d, s, loc)
func _initialize() -> void:
    var cfg = Config.new()
    cfg.values["fixture"] = "none"
    var b = Battle.new(cfg)
    b.spawning_enabled = false
    b.place_bongsu(Vector2i(44,33))
    b.place_hwacha(Vector2i(46,29))
    b.place_sensor(Vector2i(44,39))
    var attempts: Array = []
    for entry in [[Placement.Kind.SENSOR,Vector2i(41,38)], [Placement.Kind.BONGSU,Vector2i(40,33)], [Placement.Kind.BONGSU,Vector2i(42,37)]]:
        var r = b.place_structure(entry[0], entry[1])
        attempts.append({"anchor":str(entry[1]),"ok":r.ok,"reason":Placement.reject_name(r.reason)})
    print("DUP_FIXTURE ",JSON.stringify({"attempts":attempts,"sensors":b.placement.sensors().size(),"bongsus":b.placement.bongsus().size(),"links":b.network.link_count()}))
    var perf_cfg = Config.new()
    perf_cfg.values["combat_enabled"] = false
    perf_cfg.values["benchmark_hold_alive"] = true
    var pb = Battle.new(perf_cfg)
    var counter = CountingNetwork.new()
    pb.network = counter
    pb._network_dirty = true
    pb.run_for(1.0)
    print("MOVE_WORKLOAD ",JSON.stringify({"steps":pb.steps,"alive":pb.sim.alive_count,"detect_calls":counter.detect_calls,"candidate_calls":counter.candidate_calls,"combat_enabled":pb.combat_enabled}))
    quit(0)
