extends SceneTree
const Battle = preload("res://game/core/battle.gd")
const Config = preload("res://game/core/config.gd")
func _init():
    var cfg = Config.new()
    cfg.values["combat_enabled"] = false
    var b = Battle.new(cfg)
    b.spawning_enabled = false
    var slot = b.sim.force_spawn(0, Vector2(890.0, 760.1))
    b.step(cfg.get_num("fixed_dt"))
    var current = b.grid.world_to_index(Vector2(b.sim.pos_x[slot], b.sim.pos_y[slot]))
    var cached = b.sim.cell[slot]
    var anchor = Vector2i(44, 36)
    var occupied_now = b.placement.footprint_cells(anchor).has(current)
    var version = b.path.path_version
    var result = b.place_jangseung(anchor)
    print(JSON.stringify({"actual_cell":current,"cached_cell":cached,"footprint_contains_living_enemy":occupied_now,"placement_accepted":result.ok,"reason":b.placement.reject_name(result.reason),"path_version_before":version,"path_version_after":b.path.path_version,"enemy_position":[b.sim.pos_x[slot], b.sim.pos_y[slot]]}))
    quit(0)
