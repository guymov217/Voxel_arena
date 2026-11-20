#!/usr/bin/env python3
"""make_app_icon.py: the game's icon in the forms each system wants, from icon.png (the crossed swords on a bronze shield)
and the logo (docs/store/capsules/logo_stacked.png). Run it again when either changes, and commit what it writes:

  art/icon/wrecksmith.ico     Windows, 16 to 256 px: the exe (and so its shortcuts, Installed apps and the taskbar), the installer
  art/icon/wrecksmith.icns    macOS: the .app
  tools/installer/welcome.bmp the installer's welcome and finish pages (164 x 314)
  tools/installer/header.bmp  the installer's header (150 x 57)
  art/splash.png              the picture shown while the game starts (project.godot: application/boot_splash), 1920 x 1080
  art/intro/emblem.png        the emblem alone, and
  art/intro/logo.png          the logo alone, each on a clear 1920 x 1080 frame in the place it has in splash.png:
                              the layers scripts/ui/intro.gd brings to life over splash.png

    python tools/make_app_icon.py        (Python 3 with Pillow: pip install pillow)
"""
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("This needs Pillow: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "icon.png"
LOGO = ROOT / "docs" / "store" / "capsules" / "logo_stacked.png"
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
BG_TOP = (0x2b, 0x1b, 0x10)
BG_BOTTOM = (0x0f, 0x09, 0x05)
GOLD = (0xa8, 0x7a, 0x3a)
SPLASH = ROOT / "art" / "splash.png"
INTRO = ROOT / "art" / "intro"
SPLASH_SIZE = (1920, 1080)
SPLASH_EDGE = (0x14, 0x0d, 0x08)   # the flat colour at the picture's edges; boot_splash/bg_color in project.godot is the same,
SPLASH_GLOW = (0x3b, 0x26, 0x15)   # so the bars of a window that is not 16:9 join the picture without a seam


def gradient(w, h):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return im


def fit(im, w, h):
    """The picture scaled to fit inside w x h, keeping its shape."""
    r = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * r)), max(1, int(im.height * r))), Image.LANCZOS)


def glow(w, h):
    """A flat SPLASH_EDGE colour with a soft round glow of SPLASH_GLOW in the middle."""
    mask = Image.radial_gradient("L").resize((w, h), Image.BICUBIC)   # 0 in the middle, 255 at the picture's edges
    mask = mask.point(lambda v: int(255 * (v / 255.0) ** 0.85))
    return Image.composite(Image.new("RGB", (w, h), SPLASH_EDGE), Image.new("RGB", (w, h), SPLASH_GLOW), mask)


def make_splash(icon, logo):
    """The boot splash: the emblem over the wordmark on the menus' dark brown, nothing else. And each of the two alone on a clear
    frame of the same size, in the same place, for the opening's animation (scripts/ui/intro.gd) to lay over the splash."""
    w, h = SPLASH_SIZE
    em = fit(icon, 300, 300)
    lg = fit(logo, 1100, 460)
    gap = 38
    y = (h - (em.height + gap + lg.height)) // 2
    em_at = ((w - em.width) // 2, y)
    lg_at = ((w - lg.width) // 2, y + em.height + gap)
    im = glow(w, h)
    im.paste(em, em_at, em)
    im.paste(lg, lg_at, lg)
    im.save(SPLASH, format="PNG", optimize=True)
    INTRO.mkdir(parents=True, exist_ok=True)
    for name, piece, at in (("emblem", em, em_at), ("logo", lg, lg_at)):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        layer.paste(piece, at)
        layer.save(INTRO / (name + ".png"), format="PNG", optimize=True)
    print("emblem: %dx%d at %s, its centre %s; logo: %dx%d at %s" % (em.width, em.height, em_at, (em_at[0] + em.width // 2, em_at[1] + em.height // 2),
                                                                      lg.width, lg.height, lg_at))


def make_steam_icons(icon):
    """The two small pictures Steamworks asks for besides the capsules (Graphical Assets): the community icon (184 x 184, JPG:
    the emblem on the menus' dark brown) and the client icon (32 x 32 .ico, the emblem alone). In docs/store/capsules/."""
    caps = ROOT / "docs" / "store" / "capsules"
    caps.mkdir(parents=True, exist_ok=True)
    tile = gradient(184, 184)
    em = fit(icon, 152, 152)
    tile.paste(em, ((184 - em.width) // 2, (184 - em.height) // 2), em)
    tile.convert("RGB").save(caps / "community_icon_184x184.jpg", format="JPEG", quality=95)
    icon.resize((32, 32), Image.LANCZOS).save(caps / "client_icon_32.ico", format="ICO", sizes=[(32, 32)])
    return [caps / "community_icon_184x184.jpg", caps / "client_icon_32.ico"]


def main():
    icon = Image.open(ICON).convert("RGBA")
    out = ROOT / "art" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    icon.save(out / "wrecksmith.ico", format="ICO", sizes=SIZES)
    icon.save(out / "wrecksmith.icns", format="ICNS")

    logo = Image.open(LOGO).convert("RGBA")
    box = logo.getbbox()
    if box:
        logo = logo.crop(box)
    inst = ROOT / "tools" / "installer"
    inst.mkdir(parents=True, exist_ok=True)

    # The welcome and finish pages: the emblem over the wordmark, on the dark brown the game's menus have.
    w, h = 164, 314
    welcome = gradient(w, h)
    em = fit(icon, 112, 112)
    welcome.paste(em, ((w - em.width) // 2, 34), em)
    lg = fit(logo, w - 20, 120)
    welcome.paste(lg, ((w - lg.width) // 2, 34 + 112 + 26), lg)
    ImageDraw.Draw(welcome).line([(14, 296), (w - 14, 296)], fill=(0xa8, 0x7a, 0x3a), width=2)
    welcome.save(inst / "welcome.bmp", format="BMP")

    # The header: the wordmark on the same brown.
    hw, hh = 150, 57
    header = gradient(hw, hh)
    lg = fit(logo, hw - 12, hh - 10)
    header.paste(lg, ((hw - lg.width) // 2, (hh - lg.height) // 2), lg)
    header.save(inst / "header.bmp", format="BMP")

    make_splash(icon, logo)
    store = make_steam_icons(icon)
    for p in (*store, out / "wrecksmith.ico", out / "wrecksmith.icns", inst / "welcome.bmp", inst / "header.bmp", SPLASH, INTRO / "emblem.png", INTRO / "logo.png"):
        print("wrote %s (%d bytes)" % (p.relative_to(ROOT), p.stat().st_size))


if __name__ == "__main__":
    main()
