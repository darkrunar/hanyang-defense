extends SceneTree
const Economy = preload("res://game/core/economy.gd")
func _initialize() -> void:
    var e = Economy.new()
    e.enabled = true
    e.configure(240, 1, 80, {0:40}, 24)
    e.reset()
    e.reward_kills(1, 1, 0.016)
    e.reward_wave(0, 2, 0.033)
    e.charge(0, 3, 0.05, Vector2i(30,20), 5, "probe", "battle")
    print(JSON.stringify(e.events))
    quit()
