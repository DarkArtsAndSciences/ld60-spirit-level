"""Render the message as a storyboard: one panel per card, the way the game should show it.

Each panel: the 1996 photo inside the engraved beaded oval (a "spirit photograph"), the
engraved pointing hand (the planchette) with its fingertip on the card's target, the hour
the corner clock shows after the card is read, and the transcript line.

Reads tools/message/cards.json; writes notes/storyboard.jpg. Clip art is read from
assets/clipart/ (kept out of git), so this runs on the maker's Mac only.
Run with any Python that has Pillow:  python3 storyboard.py
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CLIP = ROOT / "assets" / "clipart"
PAPER = (240, 234, 220)
INK = (24, 20, 16)


def clip(path: str) -> Image.Image:
    return Image.open(CLIP / path)


def engraving(path: str) -> Image.Image:
    """A 1-bit engraving as RGBA: black ink, transparent paper."""
    im = clip(path).convert("L")
    alpha = ImageOps.invert(im)
    out = Image.new("RGBA", im.size, INK + (0,))
    out.putalpha(alpha)
    return out


def font(size: int) -> ImageFont.FreeTypeFont:
    for name in ("/System/Library/Fonts/Supplemental/Georgia Italic.ttf",
                 "/System/Library/Fonts/Supplemental/Georgia.ttf"):
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def window_mask(frame_gray: Image.Image) -> Image.Image:
    """The frame's blank middle, found by flood-filling white from the centre: L mode, 255 inside."""
    bw = frame_gray.point(lambda v: 255 if v > 128 else 0).convert("RGB")
    ImageDraw.floodfill(bw, (bw.width // 2, bw.height // 2), (255, 0, 0), thresh=10)
    r, g, _ = bw.split()
    return ImageChops.subtract(r, g).point(lambda v: 255 if v > 128 else 0)   # filled = red


FRAMES = {}


def frame_for(path: str):
    """(ink RGBA, window mask L, window bbox) for an engraved frame, cached.
    A path ending in "@90" is that frame turned a quarter turn (a portrait twin)."""
    if path not in FRAMES:
        src, _, turn = path.partition("@")
        gray = clip(src).convert("L")
        ink = engraving(src)
        if turn:
            gray, ink = gray.rotate(int(turn), expand=True, fillcolor=255), ink.rotate(int(turn), expand=True)
        mask = window_mask(gray)
        FRAMES[path] = (ink, mask, mask.getbbox())
    return FRAMES[path]


def wrap(text: str, f, width: int, d) -> list:
    words, lines, line = text.split(), [], ""
    for w in words:
        t = (line + " " + w).strip()
        if d.textlength(t, font=f) > width and line:
            lines.append(line)
            line = w
        else:
            line = t
    return lines + [line]


def panel(card: dict, spec: dict, hand: Image.Image, W=640, H=600) -> Image.Image:
    p = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(p)
    photo = clip(card["image"]).convert("RGB")
    portrait = photo.height > photo.width
    ink, mask, box = frame_for(spec["frame_portrait" if portrait else "frame_landscape"])
    # scale the frame to fit the panel's picture area
    area_w, area_h = W - 40, 420
    k = min(area_w / ink.width, area_h / ink.height)
    fw, fh = int(ink.width * k), int(ink.height * k)
    fx, fy = (W - fw) // 2, 14
    ink_s, mask_s = ink.resize((fw, fh)), mask.resize((fw, fh))
    bx0, by0, bx1, by1 = [int(v * k) for v in box]
    ww, wh = bx1 - bx0, by1 - by0
    # the photo covers the window, centred on the card's crop point
    cx, cy, zoom = card.get("crop", [0.5, 0.5, 1.0])
    scale = max(ww / photo.width, wh / photo.height) * zoom
    big = photo.resize((max(1, int(photo.width * scale)), max(1, int(photo.height * scale))), Image.LANCZOS)
    ox = int(min(max(cx * big.width - ww / 2, 0), big.width - ww))
    oy = int(min(max(cy * big.height - wh / 2, 0), big.height - wh))
    layer = Image.new("RGB", (fw, fh), PAPER)
    layer.paste(big.crop((ox, oy, ox + ww, oy + wh)), (bx0, by0))
    p.paste(Image.composite(layer, Image.new("RGB", (fw, fh), PAPER), mask_s), (fx, fy))
    p.paste(ink_s, (fx, fy), ink_s)
    # the target in photo fractions -> panel pixels
    tx = fx + bx0 + card["target"][0] * big.width - ox
    ty = fy + by0 + card["target"][1] * big.height - oy
    side = card.get("hand_from", "right")
    h = hand.resize((130, int(130 * hand.height / hand.width)))
    if side == "left":
        h = ImageOps.mirror(h)
        hx, hy = int(tx) - 2, int(ty - h.height * 0.30)
    else:
        hx, hy = int(tx - h.width) + 2, int(ty - h.height * 0.30)
    p.paste(h, (hx, hy), h)
    d.ellipse((tx - 5, ty - 5, tx + 5, ty + 5), outline=(200, 30, 30), width=2)
    f = font(25)
    y = fy + fh + 30
    for line in wrap(card["words"], f, W - 60, d):
        d.text((W // 2, y), line, font=f, fill=INK, anchor="mm")
        y += 32
    label = f"card {card['n']}  ·  the clock reads {card['hour']}:00" if "n" in card else "the secret: two players"
    d.text((W // 2, y + 8), label, font=font(15), fill=(110, 100, 90), anchor="mm")
    return p


def main() -> None:
    spec = json.loads((HERE / "cards.json").read_text())
    hand = engraving(spec["planchette"])
    cards = spec["cards"] + ([spec["secret"]] if "secret" in spec else [])
    panels = [panel(c, spec, hand) for c in cards]
    cols = 3
    rows = math.ceil(len(panels) / cols)
    W, H = panels[0].size
    sheet = Image.new("RGB", (cols * W, rows * H), PAPER)
    for i, pnl in enumerate(panels):
        sheet.paste(pnl, ((i % cols) * W, (i // cols) * H))
    out = ROOT / "notes" / "storyboard.jpg"
    sheet.save(out, quality=88)
    print(out)


if __name__ == "__main__":
    main()
