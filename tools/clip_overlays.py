#!/usr/bin/env python3
"""The text over a vertical clip (tools/make_clips.sh): the hook at the top, and the end card
(the voxel title and "Wishlist on Steam"). Transparent 1080x1920 PNGs. Needs Pillow.

    python3 tools/clip_overlays.py "<hook text>" <hook.png> <end.png>"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_capsules  # noqa: E402

W, H = 1080, 1920
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def wrap(text, font, width):
    lines, cur = [], ""
    for word in text.split():
        t = (cur + " " + word).strip()
        if font.getlength(t) <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def hook(text, path):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(SANS, 78)
    y = 250   # below TikTok's own top bar
    for line in wrap(text, font, W - 160):
        w = font.getlength(line)
        d.text(((W - w) / 2, y), line, font=font, fill=(255, 255, 255), stroke_width=7, stroke_fill=(0, 0, 0))
        y += 96
    img.save(path)


def end_card(path):
    img = Image.new("RGBA", (W, H), (8, 5, 3, 215))
    t = make_capsules.fit(make_capsules.voxel_title(400), W - 120, 300)
    img.paste(t, ((W - t.width) // 2, 760 - t.height // 2), t)
    d = ImageDraw.Draw(img)
    rule_y = 760 + t.height // 2 + 40
    d.rectangle([W // 2 - 190, rule_y, W // 2 + 190, rule_y + 5], fill=make_capsules.BLOOD)
    font = ImageFont.truetype(make_capsules.FONT, 64)
    line = "Wishlist on Steam"
    d.text(((W - font.getlength(line)) / 2, rule_y + 50), line, font=font, fill=make_capsules.GOLD_HI)
    img.save(path)


if __name__ == "__main__":
    hook(sys.argv[1], sys.argv[2])
    end_card(sys.argv[3])
