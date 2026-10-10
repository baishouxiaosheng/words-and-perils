"""Bake private_main_visual/wave_marks.png: hand-designed open-sea wave marks.

Anime / Wind Waker style sea is mostly flat colour with a few drawn white
marks: tapered crescents stacked in small sets, some ending in a curl. The
marks are drawn once here (seeded) and stored as a signed distance field so
the shader can threshold them crisply at any zoom and grow or shrink them.

Channels (tileable, 512 px for TILE world units):
  R  signed distance, .5 on the outline, > .5 inside, +-RANGE px across 0..1
  G  per-set random phase (nearest set), drives each set's appear/fade cycle
Usage: python tools/make_wave_marks.py
"""
import math, os, random
import cv2, numpy as np

SIZE = 512          # output pixels
UP = 4              # supersampling for drawing and the distance transform
TILE = 8.0          # world units covered by one tile
RANGE = 12.0        # output pixels of distance mapped to 0..1
SETS = 11           # mark sets per tile
SEED = 7

px_per_unit = SIZE * UP / TILE
rng = random.Random(SEED)
H = SIZE * UP


def arc_points(cx, cy, ang, length, radius, curl):
    """Centre line of one mark: an arc bending toward -y in the mark frame,
    optionally finishing in a tighter curl. Returns points and widths 0..1."""
    pts = []
    n = 64
    sweep = length / radius
    for i in range(n + 1):
        s = i / n
        a = -sweep / 2 + sweep * s
        x, y = radius * math.sin(a), radius * (1 - math.cos(a))
        pts.append((x, y, s))
    if curl:
        # continue from the end into a tight curl that turns back on itself
        a_end = sweep / 2
        ex, ey, _ = pts[-1]
        r2 = .17 * px_per_unit
        # spiral inward around a centre on the inside of the bend
        tx, ty = math.cos(a_end), math.sin(a_end)            # tangent at end
        nx, ny = -ty, tx                                     # inward normal
        ccx, ccy = ex + nx * r2, ey + ny * r2
        start = math.atan2(ey - ccy, ex - ccx)
        m = 40
        for i in range(1, m + 1):
            f = i / m
            rr = r2 * (1 - .5 * f)
            b = start + 3.6 * f
            pts.append((ccx + rr * math.cos(b), ccy + rr * math.sin(b), 1 + .5 * f))
    total = pts[-1][2]
    out = []
    ca, sa = math.cos(ang), math.sin(ang)
    for x, y, s in pts:
        u = s / total
        w = math.sin(math.pi * u) ** .75
        out.append((cx + x * ca - y * sa, cy + x * sa + y * ca, w))
    return out


def draw_mark(img, pts, wmax):
    for (x0, y0, w0), (x1, y1, w1) in zip(pts, pts[1:]):
        r = max(.0, (w0 + w1) / 2 * wmax)
        if r < .6:
            continue
        for ox in (-H, 0, H):
            for oy in (-H, 0, H):
                cv2.line(img, (int((x0 + ox) * 4), int((y0 + oy) * 4)), (int((x1 + ox) * 4), int((y1 + oy) * 4)),
                         255, thickness=max(1, int(round(2 * r))), lineType=cv2.LINE_AA, shift=2)


mask = np.zeros((H, H), np.uint8)
centres = []
# Sets are placed with a minimum spacing so the sea reads as scattered sets,
# never an even texture.
tries = 0
while len(centres) < SETS and tries < 5000:
    tries += 1
    c = (rng.uniform(0, H), rng.uniform(0, H))
    ok = True
    for d in centres:
        dx = min(abs(c[0] - d[0]), H - abs(c[0] - d[0]))
        dy = min(abs(c[1] - d[1]), H - abs(c[1] - d[1]))
        if dx * dx + dy * dy < (1.9 * px_per_unit) ** 2:
            ok = False
            break
    if ok:
        centres.append(c)

for cx, cy in centres:
    # x of the tile runs along the swell front; marks lie along it +-14 degrees
    ang = math.radians(rng.uniform(-14, 14))
    count = rng.choice([1, 2, 2, 3])
    length = rng.uniform(.55, 1.15) * px_per_unit
    radius = rng.uniform(1.8, 3.2) * px_per_unit
    wmax = rng.uniform(.045, .07) * px_per_unit
    curl = rng.random() < .45
    for k in range(count):
        # each further mark of a set sits behind the first, shorter and offset
        back = k * rng.uniform(.13, .19) * px_per_unit
        shift = rng.uniform(-.18, .18) * px_per_unit * k
        nx, ny = -math.sin(ang), math.cos(ang)
        tx, ty = math.cos(ang), math.sin(ang)
        pts = arc_points(cx + nx * back + tx * shift, cy + ny * back + ty * shift, ang,
                         length * (1 - .28 * k), radius, curl and k == 0)
        draw_mark(mask, pts, wmax * (1 - .2 * k))

# tileable distance: transform a 3x3 tiling and keep the centre
big = np.tile(mask, (3, 3))
inside = cv2.distanceTransform((big > 127).astype(np.uint8), cv2.DIST_L2, 5)[H:2 * H, H:2 * H]
outside = cv2.distanceTransform((big <= 127).astype(np.uint8), cv2.DIST_L2, 5)[H:2 * H, H:2 * H]
sdf = (inside - outside) / UP                       # output pixels, + inside
r = np.clip(.5 + sdf / (2 * RANGE), 0, 1)

# phase: nearest set centre (wrapped), one random value per set
ys, xs = np.mgrid[0:H:UP, 0:H:UP].astype(np.float32)
best = np.full(xs.shape, 1e18, np.float32)
phase = np.zeros(xs.shape, np.float32)
for i, (cx, cy) in enumerate(centres):
    dx = np.abs(xs - cx); dx = np.minimum(dx, H - dx)
    dy = np.abs(ys - cy); dy = np.minimum(dy, H - dy)
    d = dx * dx + dy * dy
    value = rng.random()
    phase = np.where(d < best, value, phase)
    best = np.minimum(best, d)

r_small = cv2.resize(r.astype(np.float32), (SIZE, SIZE), interpolation=cv2.INTER_AREA)
out = np.zeros((SIZE, SIZE, 3), np.uint8)
out[..., 2] = np.round(r_small * 255)               # cv2 writes BGR: R channel
out[..., 1] = np.round(phase * 255)
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, '..', 'private_main_visual', 'wave_marks.png')
cv2.imwrite(path, out)
print('wrote', os.path.normpath(path), 'sets', len(centres), 'coverage %.3f' % float((r_small > .5).mean()))
