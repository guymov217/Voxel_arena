"""Makes the arena's tiling textures (art/textures/*.png): raked sand with grains and pebbles,
and ashlar stone for the wall and the stands. Each is seamless (built from periodic noise) and
comes as an albedo and a normal map. Run from the godot/ folder: python3 tools/gen_textures.py
"""
import os
import numpy as np
from PIL import Image

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "textures")
rng = np.random.default_rng(7)


def noise(scale, power=2.0, seed=None):
    """Periodic band-limited noise in [-1, 1]: white noise filtered in frequency space, so it
    tiles exactly. `scale` is the feature size in pixels."""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((N, N))
    f = np.fft.fftfreq(N)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx * fx + fy * fy) * scale
    filt = 1.0 / (1.0 + k ** power) * np.exp(-(k * 0.15) ** 2)
    filt[0, 0] = 0
    out = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    return out / (np.abs(out).max() + 1e-9)


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    if name.endswith(".webp"):
        img.save(os.path.join(OUT, name), quality=90, method=6)
    else:
        img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def blobs(count, rmin, rmax, seed):
    """Little rounded stones scattered with wrap-around: a height field and a mask with a
    random shade per stone."""
    r = np.random.default_rng(seed)
    h = np.zeros((N, N))
    shade = np.zeros((N, N))
    yy, xx = np.mgrid[0:N, 0:N]
    for _ in range(count):
        cx, cy = r.uniform(0, N, 2)
        rad = r.uniform(rmin, rmax)
        sq = r.uniform(0.6, 1.0)
        ang = r.uniform(0, np.pi)
        x0, x1 = int(cx - rad * 1.5), int(cx + rad * 1.5) + 1
        y0, y1 = int(cy - rad * 1.5), int(cy + rad * 1.5) + 1
        ys = np.arange(y0, y1) % N
        xs = np.arange(x0, x1) % N
        gx, gy = np.meshgrid(np.arange(x0, x1) - cx, np.arange(y0, y1) - cy)
        u = gx * np.cos(ang) + gy * np.sin(ang)
        v = (-gx * np.sin(ang) + gy * np.cos(ang)) / sq
        d = np.sqrt(u * u + v * v) / rad
        bump = np.clip(1.0 - d * d, 0.0, None) ** 0.6
        sub = h[np.ix_(ys, xs)]
        take = bump > sub
        sub[take] = bump[take]
        h[np.ix_(ys, xs)] = sub
        sh = shade[np.ix_(ys, xs)]
        sh[take] = r.uniform(-1, 1)
        shade[np.ix_(ys, xs)] = sh
    return h, shade


def sand():
    big = noise(260, seed=1)
    mid = noise(60, seed=2)
    grain = noise(1.6, power=1.2, seed=3)
    # Raked sand: shallow ripples along one way, their line wandering.
    yy, xx = np.mgrid[0:N, 0:N] / N
    warp = noise(180, seed=4) * 0.9
    ripple = np.sin((yy * 22 + warp) * 2 * np.pi)
    ripple = np.sign(ripple) * np.abs(ripple) ** 0.7
    peb_h, peb_s = blobs(260, 2.5, 7.0, 5)
    fine_h, fine_s = blobs(1400, 0.8, 2.2, 6)
    h = big * 2.0 + mid * 0.8 + ripple * 0.35 * (0.6 + 0.4 * mid) + grain * 0.35 + peb_h * 1.6 + fine_h * 0.5
    save(normal_map(h, 2.6), "sand_normal.png")
    base = np.array([0.82, 0.71, 0.53])
    patch = np.array([0.70, 0.56, 0.40])
    pale = np.array([0.90, 0.82, 0.66])
    t = np.clip(0.45 + big * 0.4 + mid * 0.12, 0, 1)[..., None]
    col = base * (1 - t) + patch * t
    col = col * (1 - np.clip(-ripple, 0, 1)[..., None] * 0.035) + pale * np.clip(ripple, 0, 1)[..., None] * 0.02
    col *= (1.0 + grain[..., None] * 0.13)
    stone = np.array([0.64, 0.57, 0.48])
    m = (peb_h > 0.05)[..., None]
    pc = stone * (1 + peb_s[..., None] * 0.22) * (0.8 + 0.3 * peb_h[..., None])
    col = np.where(m, pc, col)
    m2 = (fine_h > 0.1)[..., None]
    fc = col * (0.82 + fine_s[..., None] * 0.18)
    col = np.where(m2, fc, col)
    save(Image.fromarray((np.clip(col, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8)), "sand_albedo.png")


def ashlar():
    """Stone blocks in courses with sunk mortar joints, each block its own tint, the edges
    worn and the faces pitted."""
    rows = 8
    rh = N // rows
    h = np.zeros((N, N))
    tint = np.zeros((N, N, 3))
    r = np.random.default_rng(11)
    pit = noise(3, power=1.3, seed=12)
    wear = noise(24, seed=13)
    blot = noise(140, seed=14)
    for row in range(rows):
        y0 = row * rh
        # Block widths across the row, summing to N so the row wraps.
        widths = []
        while sum(widths) < N:
            widths.append(int(r.uniform(1.1, 2.2) * rh))
        widths[-1] -= sum(widths) - N
        if widths[-1] < rh * 0.6:
            widths[-2] += widths.pop()
        x = int(r.uniform(0, N))
        for w in widths:
            c = np.array([0.88, 0.83, 0.73]) * r.uniform(0.88, 1.04) + np.array([1.0, 0.7, 0.3]) * r.uniform(-0.02, 0.02)
            ys = np.arange(y0, y0 + rh)
            xs = np.arange(x, x + w) % N
            gy, gx = np.meshgrid(np.arange(rh), np.arange(w), indexing="ij")
            edge = np.minimum(np.minimum(gx, w - 1 - gx), np.minimum(gy, rh - 1 - gy)).astype(float)
            sub_wear = wear[np.ix_(ys, xs)]
            joint = 5.0 + sub_wear * 3.0
            face = np.clip((edge - joint) / 9.0, 0, 1) ** 0.6
            h[np.ix_(ys, xs)] = face * (1.0 + r.uniform(-0.15, 0.15))
            tint[np.ix_(ys, xs)] = c
            x += w
    h_full = h + pit * 0.07 + wear * 0.12 * (h > 0.05)
    save(normal_map(h_full, 3.2), "stone_normal.png")
    mortar = np.array([0.66, 0.6, 0.52])
    face = (h > 0.02)[..., None]
    col = np.where(face, tint, mortar)
    col *= (1.0 + pit[..., None] * 0.12 + blot[..., None] * 0.12)
    col *= (0.86 + 0.14 * np.clip(h, 0, 1)[..., None])
    save(Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)), "stone_albedo.png")


def cells(count, seed):
    """Distance to the nearest and second-nearest of `count` scattered points (wrapping): the
    gap between the two is small along the edges of the cells, where packed earth cracks."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, N, (count, 2))
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    d1 = np.full((N, N), 1e9, np.float32)
    d2 = np.full((N, N), 1e9, np.float32)
    for px, py in pts:
        dx = np.abs(xx - px); dx = np.minimum(dx, N - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        d1 = np.where(closer, d, d1)
    return d1, d2


def floor_sand():
    """The arena floor's sand, 4 m to a tile at 2 mm a pixel: grains of many colours (pale quartz,
    ochre, dark specks), wind ripples a hand apart, soft hollows; height in the alpha."""
    big = noise(700, seed=21)
    mid = noise(140, seed=22)
    small = noise(18, seed=23)
    grain = noise(1.3, power=1.1, seed=24)
    grain2 = noise(2.6, power=1.3, seed=25)
    yy, xx = np.mgrid[0:N, 0:N] / N
    warp = noise(400, seed=26) * 2.2 + noise(90, seed=27) * 0.35
    rip = np.sin((yy * 38 + xx * 6 + warp) * 2 * np.pi)
    rip = np.where(rip > 0, np.abs(rip) ** 0.6, -np.abs(rip) ** 1.6) * (0.55 + 0.45 * np.clip(mid * 1.5 + 0.5, 0, 1))
    peb_h, peb_s = blobs(420, 2.0, 6.0, 28)
    h = big * 1.4 + mid * 0.6 + small * 0.3 + rip * 0.22 + grain * 0.22 + peb_h * 0.9
    save(normal_map(h, 3.2), "floor_sand_normal.webp")
    base = np.array([0.80, 0.68, 0.50])
    warm = np.array([0.76, 0.58, 0.38])
    pale = np.array([0.90, 0.83, 0.69])
    t = np.clip(0.5 + big * 0.45 + mid * 0.2, 0, 1)[..., None]
    col = base * (1 - t) + warm * t
    col = col * (1 - np.clip(-rip, 0, 1)[..., None] * 0.025) + (pale - col) * np.clip(rip, 0, 1)[..., None] * 0.05
    col *= 1.0 + grain[..., None] * 0.16 + grain2[..., None] * 0.08
    r = np.random.default_rng(29)
    speck = r.random((N, N))
    col = np.where((speck > 0.985)[..., None], col * 0.45, col)                       # dark mineral grains
    col = np.where((speck < 0.012)[..., None], np.minimum(1, col * 1.25 + 0.06), col)  # bright quartz
    stone = np.array([0.62, 0.55, 0.47])
    m = (peb_h > 0.08)[..., None]
    col = np.where(m, stone * (1 + peb_s[..., None] * 0.25) * (0.75 + 0.35 * peb_h[..., None]), col)
    hn = (h - h.min()) / (h.max() - h.min())
    img = np.dstack([np.clip(col, 0, 1), hn[..., None]])
    save(Image.fromarray((img * 255).astype(np.uint8), "RGBA"), "floor_sand_albedo.webp")


def floor_earth():
    """Packed earth where the fighting tramples the sand away: darker, its crust cracked into
    plates, grit and small stones pressed into it, scuffs; height in the alpha."""
    big = noise(600, seed=31)
    mid = noise(110, seed=32)
    grain = noise(1.5, power=1.2, seed=33)
    d1, d2 = cells(160, 34)
    crack = np.clip(1.0 - (d2 - d1) / 4.5, 0, 1) ** 2 * np.clip(mid * 1.4 - 0.1, 0, 1)   # (only in patches)
    fine1, fine2 = cells(900, 35)
    hair = np.clip(1.0 - (fine2 - fine1) / 1.6, 0, 1) ** 3 * np.clip(mid + 0.2, 0, 1) * 0.6
    peb_h, peb_s = blobs(380, 1.5, 4.5, 36)
    mottle = noise(30, seed=38)
    scuff = np.clip(noise(60, seed=37) * 1.6 - 0.6, 0, 1)
    h = big * 1.0 + mid * 0.5 + grain * 0.18 - crack * 1.1 - hair * 0.5 + peb_h * 0.8 - scuff * 0.25
    save(normal_map(h, 3.6), "floor_earth_normal.webp")
    a = np.array([0.55, 0.42, 0.30])
    b = np.array([0.47, 0.35, 0.25])
    t = np.clip(0.5 + big * 0.5 + mid * 0.25, 0, 1)[..., None]
    col = a * (1 - t) + b * t
    col *= 1.0 + grain[..., None] * 0.14 + mottle[..., None] * 0.07
    col *= 1.0 - crack[..., None] * 0.3 - hair[..., None] * 0.15
    col = col * (1 - scuff[..., None] * 0.15) + np.array([0.70, 0.58, 0.43]) * scuff[..., None] * 0.15
    stone = np.array([0.50, 0.43, 0.35])
    m = (peb_h > 0.1)[..., None]
    col = np.where(m, stone * (1 + peb_s[..., None] * 0.25) * (0.7 + 0.4 * peb_h[..., None]), col)
    hn = (h - h.min()) / (h.max() - h.min())
    img = np.dstack([np.clip(col, 0, 1), hn[..., None]])
    save(Image.fromarray((img * 255).astype(np.uint8), "RGBA"), "floor_earth_albedo.webp")


if __name__ == "__main__":
    import sys
    if "floor" in sys.argv[1:]:
        N = 2048
        floor_sand()
        floor_earth()
    else:
        sand()
        ashlar()
