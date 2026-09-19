extends SceneTree
## Reproducible source slicing and runtime-size normalization. Originals preserved.
const SOURCE = "res://docs/art/source/wp005/"
const DEST = "res://assets/art/wp005/"
const ArtSet = preload("res://game/scenes/art_set.gd")

func save_asset(image: Image, folder: String, name: String) -> void:
    DirAccess.make_dir_recursive_absolute(DEST + folder)
    var err = image.save_png(DEST + folder + "/" + name + "_v01.png")
    assert(err == OK)

func opaque_bounds(image: Image) -> Rect2i:
    var copy = image.duplicate() as Image
    for y in range(copy.get_height()):
        for x in range(copy.get_width()):
            if copy.get_pixel(x, y).a < 0.1:
                copy.set_pixel(x, y, Color.TRANSPARENT)
    return copy.get_used_rect()

func _init() -> void:
    var facilities = {"hwacha_idle": "hwacha_idle", "jangseung_idle": "jangseung_idle", "bongsu_connected": "bongsu_active", "sensor_active": "sensor_active"}
    for name in ["hwacha_inactive", "jangseung_inactive", "bongsu_disconnected", "sensor_inactive"]:
        facilities[name] = name
    for name in facilities:
        var source = Image.load_from_file(SOURCE + facilities[name] + "_source_v01.png")
        var crop = source.get_region(opaque_bounds(source))
        var scale_factor = minf(36.0 / crop.get_width(), 36.0 / crop.get_height())
        crop.resize(maxi(1, roundi(crop.get_width() * scale_factor)), maxi(1, roundi(crop.get_height() * scale_factor)), Image.INTERPOLATE_NEAREST)
        var canvas = Image.create(40, 40, false, Image.FORMAT_RGBA8)
        canvas.fill(Color.TRANSPARENT)
        canvas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((40 - crop.get_width()) / 2, 38 - crop.get_height()))
        save_asset(canvas, "facilities", name)
    var terrain = Image.load_from_file(SOURCE + "terrain_sheet_source_v01.png")
    terrain.convert(Image.FORMAT_RGBA8)
    var tile_size = Vector2i(terrain.get_width() / 3, terrain.get_height() / 2)
    var ground = Image.create(80, 20, false, Image.FORMAT_RGBA8)
    for i in range(6):
        var tile = terrain.get_region(Rect2i(Vector2i(i % 3, i / 3) * tile_size, tile_size))
        tile.resize(20, 20, Image.INTERPOLATE_NEAREST)
        if i < 4:
            ground.blit_rect(tile, Rect2i(0, 0, 20, 20), Vector2i(i * 20, 0))
        else:
            save_asset(tile, "buildings", "building_sample_" + ("roof" if i == 4 else "wall"))
    save_asset(ground, "terrain", "terrain_sample_ground")
    var enemy = Image.load_from_file(SOURCE + "enemy_sheet_source_v01.png")
    var cell = Vector2i(enemy.get_width() / 6, enemy.get_height() / 2)
    var crops: Array[Image] = []
    var largest = Vector2i.ZERO
    for column in range(6):
        for row in range(2):
            var frame = enemy.get_region(Rect2i(Vector2i(column, row) * cell, cell))
            var crop = frame.get_region(opaque_bounds(frame))
            crops.append(crop)
            largest.x = maxi(largest.x, crop.get_width())
            largest.y = maxi(largest.y, crop.get_height())
    # One common scale retains the shrinking death pose instead of enlarging it.
    var enemy_scale = minf(12.0 / largest.x, 16.0 / largest.y)
    var geometry: Array = []
    for column in range(6):
        var strip = Image.create(24, 16, false, Image.FORMAT_RGBA8)
        strip.fill(Color.TRANSPARENT)
        for row in range(2):
            var crop = crops[column * 2 + row]
            var source_size = crop.get_size()
            crop.resize(maxi(1, roundi(crop.get_width() * enemy_scale)), maxi(1, roundi(crop.get_height() * enemy_scale)), Image.INTERPOLATE_NEAREST)
            if crop.get_width() > 12 or crop.get_height() > 16:
                push_error("Enemy frame exceeds its canvas")
                quit(1)
                return
            geometry.append({"state": ArtSet.ENEMY_STATES[column], "frame": row, "source_size": [source_size.x, source_size.y], "runtime_size": [crop.get_width(), crop.get_height()], "clipped": false})
            strip.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(row * 12 + (12 - crop.get_width()) / 2, 16 - crop.get_height()))
        save_asset(strip, "enemies", "enemy_basic_" + ArtSet.ENEMY_STATES[column])
    var art = ArtSet.new()
    var report = art.load_all()
    var file = FileAccess.open(DEST + "integration_manifest.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  ") + "\n")
    var proof = FileAccess.open(DEST + "enemy_geometry.json", FileAccess.WRITE)
    proof.store_string(JSON.stringify({"scale": enemy_scale, "canvas": [12, 16], "frames": geometry}, "  ") + "\n")
    print("SOURCE_IMPORT loaded=", report.loaded_count, " missing=", report.missing_count, " enemy_atlas=", report.enemy_atlas)
    quit(0 if report.loaded_count >= 17 and report.enemy_atlas else 1)
