extends RefCounted
## Pilot textures only. Read-only rendering: never alters placement or simulation.
const Placement = preload("res://game/core/placement.gd")
static var textures: Dictionary = {}
static var regions: Dictionary = {}

func _init() -> void:
    if not textures.is_empty():
        return
    for pair in [[Placement.Kind.HWACHA, "hwacha"], [Placement.Kind.JANGSEUNG, "jangseung"], [Placement.Kind.BONGSU, "bongsu"], [Placement.Kind.SENSOR, "sensor"]]:
        var tex: Texture2D = load("res://assets/art/wp005/facilities/%s.png" % pair[1])
        if tex == null:
            continue
        textures[pair[0]] = tex
        var img: Image = tex.get_image()
        # Inspect alpha to select the opaque subject, preserving the original PNG.
        var lo := Vector2i(img.get_width(), img.get_height())
        var hi := Vector2i.ZERO
        for y in range(img.get_height()):
            for x in range(img.get_width()):
                if img.get_pixel(x, y).a > 0.5:
                    lo = lo.min(Vector2i(x,y))
                    hi = hi.max(Vector2i(x,y))
        regions[pair[0]] = Rect2(Vector2(lo), Vector2(hi - lo + Vector2i.ONE))

func draw_facility(canvas: CanvasItem, s: Placement.Structure) -> bool:
    if not textures.has(s.kind):
        return false
    var source: Rect2 = regions[s.kind]
    var scale_factor: float = minf(36.0 / source.size.x, 36.0 / source.size.y)
    var size: Vector2 = (source.size * scale_factor).round()
    var dest := Rect2((s.center + Vector2(-size.x * 0.5, 18.0 - size.y)).round(), size)
    canvas.draw_texture_rect_region(textures[s.kind], dest, source, Color.WHITE if s.active else Color(0.35,0.35,0.35))
    # Cross marker conveys disabled state without relying on tint alone.
    if not s.active:
        var p: Vector2 = s.center + Vector2(12,10)
        canvas.draw_line(p, p + Vector2(6,6), Color(0.8,0.7,0.6), 2)
        canvas.draw_line(p + Vector2(6,0), p + Vector2(0,6), Color(0.8,0.7,0.6), 2)
    return true
