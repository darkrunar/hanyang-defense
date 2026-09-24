extends Node2D
## WP-005 combat effects (D-049). One effect per real battle event (hwacha
## volley -> fire at the hwacha + impact at the aim; outer collapse -> collapse
## at the outer post; enemy hit / despawn -> short marks), advanced by battle
## simulation time only: a paused battle freezes every effect, a restart
## clears them all. Draws the `combat_fx` PNG strips when the art set has
## them, a small procedural shape otherwise, so the event contract can be
## verified before the files exist.

const ArtSet := preload("res://game/scenes/art_set.gd")

const KINDS: Array[String] = ["fire", "impact", "collapse", "enemy_hit", "enemy_despawn"]
## seconds of simulation time each effect lives
const LIFETIME: Dictionary = {"fire": 0.18, "impact": 0.30, "collapse": 0.90, "enemy_hit": 0.12, "enemy_despawn": 0.20}
const CAP: int = 512

const COLOR_FIRE: Color = Color(1.00, 0.62, 0.20, 0.95)
const COLOR_IMPACT: Color = Color(1.00, 0.72, 0.30, 0.60)
const COLOR_COLLAPSE: Color = Color(0.95, 0.30, 0.20, 0.80)
const COLOR_HIT: Color = Color(1.00, 0.90, 0.60, 0.90)
const COLOR_DESPAWN: Color = Color(0.55, 0.15, 0.10, 0.85)

var art: ArtSet = null
## [kind, position, t0 (sim time), radius]
var effects: Array = []
var sim_time: float = 0.0
var created_total: int = 0
var created_by_kind: Dictionary = {}
var dropped_over_cap: int = 0


func spawn(kind: String, pos: Vector2, radius: float = 0.0) -> void:
    if effects.size() >= CAP:
        dropped_over_cap += 1
        return
    effects.append([kind, pos, sim_time, radius])
    created_total += 1
    created_by_kind[kind] = int(created_by_kind.get(kind, 0)) + 1


## Called once per rendered frame with the battle's simulation time. Nothing
## moves while the time stands still (PAUSED / SETTINGS / CONFIRM / RESULT).
func advance(t: float) -> void:
    sim_time = t
    var i: int = 0
    while i < effects.size():
        var e: Array = effects[i]
        if t - float(e[2]) >= float(LIFETIME[e[0]]):
            effects.remove_at(i)
        else:
            i += 1
    queue_redraw()


func clear() -> void:
    effects.clear()
    queue_redraw()


func count() -> int:
    return effects.size()


func snapshot() -> Dictionary:
    return {"alive": effects.size(), "created_total": created_total, "created_by_kind": created_by_kind.duplicate(),
        "dropped_over_cap": dropped_over_cap, "sim_time": sim_time}


func _draw() -> void:
    for e: Array in effects:
        var kind: String = e[0]
        var pos: Vector2 = e[1]
        var age: float = sim_time - float(e[2])
        var life: float = float(LIFETIME[kind])
        var u: float = clampf(age / life, 0.0, 0.999)
        var fr: ArtSet.Frames = null
        if art != null:
            match kind:
                "fire", "impact", "collapse":
                    fr = art.frames("combat_fx", kind)
                "enemy_hit":
                    fr = art.frames("enemy_basic", "hit")
                "enemy_despawn":
                    fr = art.frames("enemy_basic", "despawn")
        if fr != null:
            var frame: int = int(u * fr.frame_count)
            draw_texture_rect_region(fr.texture, Rect2(pos - fr.pivot, Vector2(fr.frame_size)), fr.region(frame))
            continue
        var fade: float = 1.0 - u
        match kind:
            "fire":
                draw_circle(pos, 6.0 + 6.0 * u, Color(COLOR_FIRE.r, COLOR_FIRE.g, COLOR_FIRE.b, COLOR_FIRE.a * fade))
            "impact":
                var r: float = maxf(float(e[3]), 8.0) * (0.6 + 0.4 * u)
                draw_arc(pos, r, 0.0, TAU, 32, Color(COLOR_IMPACT.r, COLOR_IMPACT.g, COLOR_IMPACT.b, COLOR_IMPACT.a * fade), 3.0)
            "collapse":
                var r2: float = 30.0 + 90.0 * u
                draw_arc(pos, r2, 0.0, TAU, 48, Color(COLOR_COLLAPSE.r, COLOR_COLLAPSE.g, COLOR_COLLAPSE.b, COLOR_COLLAPSE.a * fade), 4.0)
                draw_arc(pos, r2 * 0.6, 0.0, TAU, 48, Color(COLOR_COLLAPSE.r, COLOR_COLLAPSE.g, COLOR_COLLAPSE.b, COLOR_COLLAPSE.a * fade * 0.6), 2.0)
            "enemy_hit":
                draw_rect(Rect2(pos - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), Color(COLOR_HIT.r, COLOR_HIT.g, COLOR_HIT.b, COLOR_HIT.a * fade), false, 1.5)
            "enemy_despawn":
                draw_circle(pos, 3.0 + 5.0 * u, Color(COLOR_DESPAWN.r, COLOR_DESPAWN.g, COLOR_DESPAWN.b, COLOR_DESPAWN.a * fade))
