"""WP-005 graphics measurements (D-052 evaluation): per-asset colour count,
saturation, luminance, edge luminance, bottom margin; tile seam differences;
enemy / facility contrast against the ground tiles, the grey-box corridor and
the shader outline colour; contact sheets. Writes results/evidence/wp-005/graphics_eval/.

    python scripts/graphics_eval_wp005.py
"""
import io, json, os, glob, colorsys
from PIL import Image, ImageDraw
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace(os.sep, '/') + '/'
A = base + 'assets/art/wp005/'
C = base + 'results/evidence/wp-005/captures/'
P = base + 'results/evidence/wp-005/playtest/'
OUT = base + 'results/evidence/wp-005/graphics_eval/'
os.makedirs(OUT, exist_ok=True)

def lum(rgb):
    r, g, b = [c / 255.0 for c in rgb[:3]]
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def contrast(l1, l2):
    a, b = max(l1, l2), min(l1, l2)
    return (a + 0.05) / (b + 0.05)

def stats(img, frame=None):
    im = img.convert('RGBA')
    if frame is not None:
        im = im.crop(frame)
    px = [p for p in (im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()) if p[3] >= 128]
    if not px:
        return None
    cols = set(p[:3] for p in px)
    sats = [colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)[1] for p in px]
    lums = [lum(p) for p in px]
    # outline: opaque pixels adjacent to transparent -> dark?
    w, h = im.size
    data = im.load()
    edge = []
    for y in range(h):
        for x in range(w):
            p = data[x, y]
            if p[3] < 128:
                continue
            nb = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            if any(not (0 <= nx < w and 0 <= ny < h) or data[nx, ny][3] < 128 for nx, ny in nb):
                edge.append(lum(p))
    bb = im.getbbox()
    return {'opaque_px': len(px), 'colours': len(cols), 'sat_mean': round(sum(sats) / len(sats), 3),
            'lum_mean': round(sum(lums) / len(lums), 3), 'lum_min': round(min(lums), 3), 'lum_max': round(max(lums), 3),
            'edge_lum_mean': round(sum(edge) / len(edge), 3) if edge else None, 'edge_px': len(edge),
            'bbox': bb, 'bottom_margin': (h - bb[3]) if bb else None, 'size': [w, h]}

report = {'assets': {}, 'contrast': {}, 'tiles': {}, 'screen': {}}
# --- per asset (first frame of each strip)
frames = {'terrain_sample_ground': 4, 'enemy_basic': 2, 'hwacha_fire': 3, 'bongsu_pulse': 2}
for f in sorted(glob.glob(A + '*/*.png')):
    name = os.path.basename(f)
    im = Image.open(f)
    n = 1
    for k, v in frames.items():
        if name.startswith(k):
            n = v
    fw = im.width // n
    per = []
    for i in range(n):
        per.append(stats(im, (i * fw, 0, (i + 1) * fw, im.height)))
    report['assets'][name] = {'frames': n, 'frame_size': [fw, im.height], 'per_frame': per}

# --- tile seams (ground variants, roof, wall): mean abs diff between opposite edges
def seam(im):
    im = im.convert('RGB')
    w, h = im.size
    l = [im.getpixel((0, y)) for y in range(h)]
    r = [im.getpixel((w - 1, y)) for y in range(h)]
    t = [im.getpixel((x, 0)) for x in range(w)]
    b = [im.getpixel((x, h - 1)) for x in range(w)]
    d = lambda a, c: sum(abs(p[i] - q[i]) for p, q in zip(a, c) for i in range(3)) / (3 * len(a))
    return {'lr': round(d(l, r), 1), 'tb': round(d(t, b), 1)}
g = Image.open(A + 'terrain/terrain_sample_ground_v01.png')
for i in range(4):
    report['tiles']['ground_%d' % i] = seam(g.crop((i * 20, 0, (i + 1) * 20, 20)))
report['tiles']['roof'] = seam(Image.open(A + 'buildings/building_sample_roof_v01.png'))
report['tiles']['wall'] = seam(Image.open(A + 'buildings/building_sample_wall_v01.png'))
gl = [stats(g, (i * 20, 0, (i + 1) * 20, 20))['lum_mean'] for i in range(4)]
report['tiles']['ground_lum_variants'] = gl

# --- contrast: enemy body vs ground tile / greybox corridor / outline colour
enemy = report['assets']['enemy_basic_walk_down_v01.png']['per_frame'][0]
ground_l = sum(gl) / 4
corridor = lum((int(0.13 * 255), int(0.12 * 255), int(0.11 * 255)))
outline = lum((int(0.93 * 255), int(0.88 * 255), int(0.78 * 255)))
report['contrast'] = {
    'enemy_body_lum': enemy['lum_mean'], 'ground_lum': round(ground_l, 3), 'corridor_lum': round(corridor, 3), 'outline_lum': round(outline, 3),
    'enemy_vs_ground': round(contrast(enemy['lum_mean'], ground_l), 2), 'enemy_vs_corridor': round(contrast(enemy['lum_mean'], corridor), 2),
    'outline_vs_corridor': round(contrast(outline, corridor), 2), 'outline_vs_ground': round(contrast(outline, ground_l), 2),
}
for fac in ['hwacha_idle', 'hwacha_inactive', 'jangseung_idle', 'jangseung_inactive', 'bongsu_connected', 'bongsu_disconnected', 'sensor_active', 'sensor_inactive']:
    s = report['assets'][fac + '_v01.png']['per_frame'][0]
    report['contrast'][fac + '_vs_ground'] = round(contrast(s['lum_mean'], ground_l), 2)

# --- screen-size facts
report['screen'] = {'enemy_1080p_px': [12, 16], 'enemy_720p_px': [8, 10.7], 'facility_1080p_px': 40, 'facility_720p_px': 26.7, 'tile_720p_px': 13.3}

# --- contact sheets
def sheet(items, out, scale=4, pad=8, label_h=14):
    ims = []
    for label, im in items:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        canvas = Image.new('RGB', (im.width, im.height + label_h), (40, 36, 32))
        canvas.paste(im, (0, label_h))
        ImageDraw.Draw(canvas).text((2, 1), label, fill=(230, 220, 200))
        ims.append(canvas)
    W = sum(i.width for i in ims) + pad * (len(ims) + 1)
    H = max(i.height for i in ims) + pad * 2
    out_im = Image.new('RGB', (W, H), (40, 36, 32))
    x = pad
    for i in ims:
        out_im.paste(i, (x, pad))
        x += i.width + pad
    out_im.save(out)

# assets sheet: facilities pairs + enemy strips + tiles
items = []
for fac in ['hwacha_idle', 'hwacha_inactive', 'jangseung_idle', 'jangseung_inactive', 'bongsu_connected', 'bongsu_disconnected', 'sensor_active', 'sensor_inactive']:
    items.append((fac, Image.open(A + 'facilities/%s_v01.png' % fac).convert('RGBA')))
sheet(items, OUT + 'sheet_facilities_x4.png', scale=4)
items = [(st, Image.open(A + 'enemies/enemy_basic_%s_v01.png' % st).convert('RGBA')) for st in ['walk_down', 'walk_up', 'walk_left', 'walk_right', 'hit', 'despawn']]
sheet(items, OUT + 'sheet_enemies_x8.png', scale=8)
items = [('ground x4', g.convert('RGBA')), ('roof', Image.open(A + 'buildings/building_sample_roof_v01.png').convert('RGBA')), ('wall', Image.open(A + 'buildings/building_sample_wall_v01.png').convert('RGBA'))]
sheet(items, OUT + 'sheet_tiles_x6.png', scale=6)

# context crops: 1080p plaza (assets_b_collapse) and 720p (playtest_720 T3), dense outline on/off
def crop_scaled(path, box, scale):
    im = Image.open(path).convert('RGB').crop(box)
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)
ctx = [
    ('1080p 광장 붕괴 후 (assets_b)', crop_scaled(C + 'wp005_assets_b_collapse_t20.5.png', (600, 300, 1000, 620), 2)),
    ('720p 같은 장면 (playtest_720 T3)', crop_scaled(P + 'wp005_playtest_720_T3_collapse_nolabels.png', (400, 200, 667, 413), 3)),
]
sheet(ctx, OUT + 'sheet_context_1080_vs_720.png', scale=1, label_h=16)
dense_on = crop_scaled(C + 'wp005_dense_a2_1000_nolabels_t15.png', (880, 480, 1200, 620), 3)
dense_off = crop_scaled(C + 'wp005_dense_a3_1000_nooutline_t15.png', (880, 480, 1200, 620), 3)
corr_on = crop_scaled(C + 'wp005_dense_a2_1000_nolabels_t15.png', (1330, 470, 1600, 600), 3)
corr_off = crop_scaled(C + 'wp005_dense_a3_1000_nooutline_t15.png', (1330, 470, 1600, 600), 3)
sheet([('테두리 on · 광장', dense_on), ('테두리 off · 광장', dense_off), ('테두리 on · 통로(회색상자)', corr_on), ('테두리 off · 통로', corr_off)], OUT + 'sheet_outline_on_off_x3.png', scale=1, label_h=16)
closeup = [('3배 근접 광장 (closeup_a2)', crop_scaled(C + 'wp005_closeup_a2_plaza_x3_t15.png', (560, 300, 1360, 800), 1)),
           ('3배 근접 점유 격자 (closeup_a)', crop_scaled(C + 'wp005_closeup_a_plaza_x3_footprints_t15.png', (560, 300, 1360, 800), 1))]
sheet(closeup, OUT + 'sheet_closeup_x3.png', scale=1, label_h=16)
json.dump(report, io.open(OUT + 'measurements.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(json.dumps({'contrast': report['contrast'], 'tiles': report['tiles']}, ensure_ascii=False, indent=1))
for k, v in report['assets'].items():
    p = v['per_frame'][0]
    print(k, v['frame_size'], 'colours', p['colours'], 'sat', p['sat_mean'], 'lum', p['lum_mean'], 'edge_lum', p['edge_lum_mean'], 'bottom_margin', p['bottom_margin'])
