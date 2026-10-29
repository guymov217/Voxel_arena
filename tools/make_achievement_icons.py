"""Steam achievement icons (achieved and locked) for scripts/game/achievements.gd.

A struck bronze coin on the HUD's iron and blood: a raised rim of beads, a sunk field, and the
achievement's sign in gold relief (a gladius with a drop of blood, the headsman's axe, a paw,
the emperor's crown, the bout in numerals, the rudis...). The locked one is the same coin worn
grey. Drawn at 4x and brought down, so the edges are smooth.

    python3 tools/make_achievement_icons.py   ->  art/achievements/<id>.png, <id>_locked.png (64x64,
                                                   for Steamworks), the same at 256 in 256/, and
                                                   art/achievements/sheet.png (all of them)
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "achievements")
FONT = os.path.join(ROOT, "art", "fonts", "Cinzel.ttf")
N = 1024  # drawn at 4x
C = N // 2

GOLD = (224, 181, 97)
GOLD_HI = (255, 226, 150)
GOLD_LO = (120, 82, 32)
FIELD = (74, 24, 18)     # blood-dark field
FIELD_LO = (38, 12, 10)
RIM = (150, 104, 48)
WOOD = (176, 120, 66)
BLOOD = (170, 22, 18)


def poly(d, pts, fill=255):
    d.polygon([(C + x, C + y) for x, y in pts], fill=fill)


def rot(pts, a, cx=0, cy=0):
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def blade(d, a, L=330, w=46, guard=120, grip=110, ox=0, oy=0):
    """A gladius pointing along angle a (0 = up), hilt at the centre's far side."""
    pts = [(-w / 2, 40), (-w / 2, -L + 70), (0, -L), (w / 2, -L + 70), (w / 2, 40)]
    poly(d, rot([(x + ox, y + oy) for x, y in pts], a, ox, oy))
    poly(d, rot([(x + ox, y + oy) for x, y in [(-guard / 2, 40), (guard / 2, 40), (guard / 2, 70), (-guard / 2, 70)]], a, ox, oy))
    poly(d, rot([(x + ox, y + oy) for x, y in [(-18, 70), (18, 70), (18, 70 + grip), (-18, 70 + grip)]], a, ox, oy))
    poly(d, rot([(x + ox, y + oy) for x, y in [(-34, 70 + grip), (34, 70 + grip), (34, 100 + grip), (-34, 100 + grip)]], a, ox, oy))


def ellipse(d, x, y, rx, ry, fill=255):
    d.ellipse([C + x - rx, C + y - ry, C + x + rx, C + y + ry], fill=fill)


def numeral(d, text, size=300, y=0):
    f = ImageFont.truetype(FONT, size)
    bb = d.textbbox((0, 0), text, font=f)
    d.text((C - (bb[0] + bb[2]) / 2, C + y - (bb[1] + bb[3]) / 2), text, font=f, fill=255)


def laurel(d, r=300, leaves=11):
    """A laurel wreath: two branches up from the bottom, leaves in pairs along the stem."""
    for side in (-1, 1):
        for i in range(leaves):
            # from the bottom (a = pi/2 below the centre) round each side to near the top
            a = math.pi / 2 + side * (0.35 + 2.3 * i / (leaves - 1))
            x, y = math.cos(a) * r, math.sin(a) * r
            tang = a + side * math.pi / 2          # along the stem, the way it grows
            for k, off in ((0, 1.0), (1, -1.0)):   # a leaf each side of the stem
                lean = tang + off * 0.55 * side
                leaf = [(0, 0), (30, -46), (0, -120), (-30, -46)]
                poly(d, rot([(px + x, py + y) for px, py in leaf], lean + math.pi / 2, x, y))
        d.arc([C - r, C - r, C + r, C + r], 110 if side > 0 else -60, 240 if side > 0 else 70, fill=255, width=16)


GLYPHS = {}


def glyph(fn):
    GLYPHS[fn.__name__] = fn
    return fn


@glyph
def first_blood(d, extra):
    blade(d, 0.0, oy=-10)
    # the drop, off the point, in the blood colour (drawn on the extra layer)
    e = ImageDraw.Draw(extra)
    ellipse(e, 150, 150, 52, 52)
    poly(e, [(150 - 50, 140), (150, 40), (150 + 50, 140)])


@glyph
def headsman(d, extra):
    # The headsman's axe: a long haft, and a broad bearded blade on its upper end.
    a = 0.3
    poly(d, rot([(-22, -320), (22, -320), (22, 330), (-22, 330)], a))
    head = [(14, -300), (120, -330), (250, -360), (300, -220), (280, -60), (200, -20), (120, -90), (14, -110)]
    poly(d, rot(head, a))
    numeral(d, "X", 140, 230)


@glyph
def beast_slayer(d, extra):
    ellipse(d, 0, 90, 170, 140)
    for x, y, r in [(-190, -90, 66), (-75, -200, 70), (75, -200, 70), (190, -90, 66)]:
        ellipse(d, x, y, r, r * 1.2)


@glyph
def boss(d, extra):
    # The emperor's crown of points over a band.
    poly(d, [(-280, 160), (-280, 40), (-300, -170), (-170, -20), (-90, -240), (0, -40), (90, -240), (170, -20), (300, -170), (280, 40), (280, 160)])
    for x in (-300, -90, 90, 300):
        ellipse(d, x, -200 if abs(x) < 200 else -175, 34, 34)
    ellipse(d, 0, -60, 30, 30, 0)


@glyph
def eight_bouts(d, extra):
    numeral(d, "VIII", 330)


@glyph
def halfway(d, extra):
    numeral(d, "XXXII", 250)


@glyph
def rudis(d, extra):
    e = ImageDraw.Draw(extra)
    blade(e, 0.0, L=340, w=60, guard=90, oy=-10)


@glyph
def rudis_again(d, extra):
    e = ImageDraw.Draw(extra)
    blade(e, -0.62, L=320, w=56, guard=86)
    blade(e, 0.62, L=320, w=56, guard=86)


@glyph
def jupiter_hand(d, extra):
    poly(d, [(60, -340), (-160, 20), (-10, 20), (-90, 340), (180, -60), (30, -60), (130, -340)])


@glyph
def trained(d, extra):
    # A cuirass: shoulders, the chest's muscles, the waist.
    poly(d, [(-250, -240), (-120, -290), (-60, -230), (60, -230), (120, -290), (250, -240), (230, -40), (190, 180), (150, 290), (-150, 290), (-190, 180), (-230, -40)])
    for sx in (-1, 1):
        d.arc([C + sx * 115 - 115, C - 190, C + sx * 115 + 115, C + 30], 20 if sx < 0 else 40, 140 if sx < 0 else 160, fill=0, width=22)
    d.line([C, C - 200, C, C + 260], fill=0, width=18)
    for y in (90, 170):
        d.line([C - 120, C + y, C + 120, C + y], fill=0, width=14)


@glyph
def smith(d, extra):
    # The anvil, and the hammer over it.
    poly(d, [(-300, 40), (190, 40), (300, -10), (260, 90), (130, 110), (110, 210), (190, 290), (-190, 290), (-110, 210), (-130, 110), (-300, 100)])
    poly(d, rot([(-20, -330), (20, -330), (20, -40), (-20, -40)], -0.6, 0, -100))
    poly(d, rot([(-110, -360), (90, -360), (90, -260), (-110, -260)], -0.6, 0, -100))


@glyph
def armourer(d, extra):
    # A gladiator's galea: the bowl, the crest, the brim, the grille.
    ellipse(d, 0, -20, 230, 230)
    poly(d, [(-300, 80), (300, 80), (260, 140), (-260, 140)])
    poly(d, [(-60, -340), (60, -340), (40, -240), (-40, -240)])
    d.rectangle([C - 200, C + 120, C + 200, C + 300], fill=255)
    for x in range(-150, 151, 60):
        d.rectangle([C + x - 12, C + 140, C + x + 12, C + 280], fill=0)


@glyph
def lifted(d, extra):
    # Brothers in arms: two blades crossed over each other, a small shield where they meet.
    blade(d, -0.7, L=360, w=44, guard=96, grip=90, oy=60)
    blade(d, 0.7, L=360, w=44, guard=96, grip=90, oy=60)
    ellipse(d, 0, 40, 92, 92)
    ellipse(d, 0, 40, 64, 64, 0)
    ellipse(d, 0, 40, 34, 34)


@glyph
def javelin(d, extra):
    a = 0.8
    poly(d, rot([(-14, -260), (14, -260), (14, 360), (-14, 360)], a))
    poly(d, rot([(-48, -250), (0, -380), (48, -250), (0, -210)], a))
    for k in range(3):
        y = 60 + k * 90
        d.line([C - 330 + k * 40, C + y - 40, C - 160 + k * 40, C + y - 200], fill=255, width=16)


@glyph
def darling(d, extra):
    laurel(d, r=290, leaves=9)
    # a rose thrown into the sand
    for k in range(6):
        a = k * math.pi / 3
        ellipse(d, math.cos(a) * 60, math.sin(a) * 60 - 10, 62, 62)
    ellipse(d, 0, -10, 50, 50, 0)
    ellipse(d, 0, -10, 32, 32)


def relief(mask, base, hi, lo):
    """A gold (or any metal) relief from a mask: lit from the top left."""
    m = mask.filter(ImageFilter.GaussianBlur(3))
    light = ImageChops.subtract(m, ImageChops.offset(m, 10, 10))
    dark = ImageChops.subtract(m, ImageChops.offset(m, -10, -10))
    img = Image.new("RGB", (N, N), base)
    grad = Image.linear_gradient("L").resize((N, N)).rotate(45)
    img = Image.composite(Image.new("RGB", (N, N), hi), img, grad.point(lambda v: int(v * 0.35)))
    img = Image.composite(Image.new("RGB", (N, N), hi), img, light)
    img = Image.composite(Image.new("RGB", (N, N), lo), img, dark)
    return img, m


def coin(id_, locked=False):
    img = Image.new("RGB", (N, N), (16, 10, 8))
    d = ImageDraw.Draw(img)
    # the coin's rim and its beads
    rim_m = Image.new("L", (N, N), 0)
    rd = ImageDraw.Draw(rim_m)
    rd.ellipse([20, 20, N - 20, N - 20], fill=255)
    rd.ellipse([100, 100, N - 100, N - 100], fill=0)
    for k in range(40):
        a = k * math.tau / 40
        x, y = C + math.cos(a) * 452, C + math.sin(a) * 452
        rd.ellipse([x - 14, y - 14, x + 14, y + 14], fill=0)
    # the sunk field, darker at its edge
    field = Image.new("RGB", (N, N), FIELD)
    vign = Image.new("L", (N, N), 0)
    ImageDraw.Draw(vign).ellipse([140, 140, N - 140, N - 140], fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(90))
    field = Image.composite(field, Image.new("RGB", (N, N), FIELD_LO), vign)
    fm = Image.new("L", (N, N), 0)
    ImageDraw.Draw(fm).ellipse([96, 96, N - 96, N - 96], fill=255)
    img.paste(field, (0, 0), fm)
    rim, _ = relief(rim_m, RIM, GOLD_HI, GOLD_LO)
    img.paste(rim, (0, 0), rim_m)
    # the sign
    gm = Image.new("L", (N, N), 0)
    em = Image.new("L", (N, N), 0)
    GLYPHS[id_](ImageDraw.Draw(gm), em)
    # its shadow on the field
    sh = ImageChops.offset(ImageChops.add(gm, em), 14, 18).filter(ImageFilter.GaussianBlur(10))
    img = Image.composite(Image.new("RGB", (N, N), (10, 4, 3)), img, sh.point(lambda v: int(v * 0.8)))
    g, gmb = relief(gm, GOLD, GOLD_HI, GOLD_LO)
    img.paste(g, (0, 0), gm)
    if em.getbbox():
        wood = id_.startswith("rudis")
        e, _ = relief(em, WOOD if wood else BLOOD, (230, 180, 120) if wood else (230, 80, 70), (90, 52, 24) if wood else (80, 6, 6))
        img.paste(e, (0, 0), em)
    if locked:
        grey = img.convert("L").point(lambda v: int(v * 0.55 + 12))
        img = Image.merge("RGB", (grey, grey, grey))
    # cut round, on black (Steam shows the square)
    out = Image.new("RGB", (N, N), (12, 9, 8) if not locked else (14, 14, 14))
    cm = Image.new("L", (N, N), 0)
    ImageDraw.Draw(cm).ellipse([18, 18, N - 18, N - 18], fill=255)
    out.paste(img, (0, 0), cm)
    return out.resize((256, 256), Image.LANCZOS)


def ids():
    src = open(os.path.join(ROOT, "scripts", "game", "achievements.gd")).read()
    import re
    block = src[src.index("const LIST"):]
    return re.findall(r'^\t"(\w+)": \{', block, re.M)


def main():
    os.makedirs(os.path.join(OUT, "256"), exist_ok=True)
    names = ids()
    missing = [n for n in names if n not in GLYPHS]
    if missing:
        sys.exit("no sign drawn for: %s" % missing)
    tiles = []
    for n in names:
        a, l = coin(n), coin(n, True)
        # Steamworks takes 64x64 (a lit and a grey one); the 256 ones are kept for anything larger.
        a.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, n + ".png"))
        l.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, n + "_locked.png"))
        a.save(os.path.join(OUT, "256", n + ".png"))
        l.save(os.path.join(OUT, "256", n + "_locked.png"))
        tiles.append((n, a, l))
    cols = 5
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 280, rows * 330), (28, 22, 18))
    sd = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT, 18)
    for i, (n, a, l) in enumerate(tiles):
        x, y = (i % cols) * 280 + 12, (i // cols) * 330 + 10
        sheet.paste(a, (x, y))
        sheet.paste(l.resize((64, 64)), (x + 192, y + 192))
        sd.text((x, y + 262), n, font=f, fill=(230, 200, 140))
    sheet.save(os.path.join(OUT, "sheet.png"))
    print("wrote %d icons (and locked) to %s" % (len(tiles), OUT))


if __name__ == "__main__":
    main()
