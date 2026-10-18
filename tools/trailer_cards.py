#!/usr/bin/env python3
"""The trailer's title cards (tools/make_trailer.sh): a few words over a shot, and the end card
with the voxel title. Writes <tmp>/cards/*.png (1920x1080, transparent) and cards.txt, each card's
file and the seconds it shows, from the lengths of the shots already cut. Needs Pillow and ffprobe.

    python3 tools/trailer_cards.py <trailer work dir>"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_capsules  # noqa: E402

W, H = 1920, 1080
ORDER = ["gorilla", "forge", "duel", "elephant", "cyclops", "bear", "chicken"]
# The card over each shot (none over the opening blow: it speaks for itself).
CARDS = {
    "forge": "BUILD IT.",
    "duel": "SWING IT.",
    "elephant": "25 BEASTS AND MONSTERS",
    "cyclops": "UP TO 8 PLAYERS",
    "chicken": "WRECK EVERYTHING.",
}


def duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
    return float(out.decode().strip())


def card(text, path):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    font = ImageFont.truetype(make_capsules.FONT, 112)
    w = font.getlength(text)
    x, y = (W - w) / 2, H * 0.72
    # A soft dark band behind the words, then the words in old gold with a dark edge.
    band = Image.new("L", (W, H), 0)
    ImageDraw.Draw(band).rectangle([0, int(y - 40), W, int(y + 170)], fill=150)
    band = band.filter(ImageFilter.GaussianBlur(40))
    shade = Image.new("RGBA", (W, H), (8, 5, 3, 255))
    shade.putalpha(band)
    img = Image.alpha_composite(img, shade)
    d = ImageDraw.Draw(img)
    d.text((x, y), text, font=font, fill=make_capsules.GOLD_HI + (255,), stroke_width=6, stroke_fill=(20, 12, 6, 255))
    img.save(path)


def end_card(path):
    img = Image.new("RGBA", (W, H), (10, 7, 5, 255))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.2, H * 0.15, W * 0.8, H * 0.85], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    warm = Image.new("RGBA", (W, H), (120, 52, 18, 255))
    warm.putalpha(glow)
    img = Image.alpha_composite(img, warm)
    t = make_capsules.fit(make_capsules.voxel_title(700), int(W * 0.7), 300)
    img.paste(t, ((W - t.width) // 2, int(H * 0.42) - t.height // 2), t)
    d = ImageDraw.Draw(img)
    ry = int(H * 0.42) + t.height // 2 + 40
    d.rectangle([W // 2 - 260, ry, W // 2 + 260, ry + 6], fill=make_capsules.BLOOD)
    font = ImageFont.truetype(make_capsules.FONT, 72)
    line = "Wishlist on Steam"
    d.text(((W - font.getlength(line)) / 2, ry + 50), line, font=font, fill=make_capsules.GOLD_HI)
    img.save(path)


def main():
    tmp = sys.argv[1]
    cards = os.path.join(tmp, "cards")
    os.makedirs(cards, exist_ok=True)
    t = 0.0
    lines = []
    for i, shot in enumerate(ORDER):
        f = os.path.join(tmp, shot + ".mp4")
        if not os.path.exists(f) or os.path.getsize(f) == 0:
            continue
        dur = duration(f)
        if shot in CARDS:
            name = "card_%s.png" % shot
            card(CARDS[shot], os.path.join(cards, name))
            lines.append("%s %.2f %.2f" % (name, t + 0.3, t + dur - 0.2))
        t += dur
    end_card(os.path.join(cards, "end.png"))
    with open(os.path.join(cards, "cards.txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("cards: %d, the cut runs %.1f s before the end card" % (len(lines), t))


if __name__ == "__main__":
    main()
