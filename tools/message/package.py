"""Build the message's game files from tools/message/cards.json into game/message/.

  game/message/cards/card1.png ... card8.png, secret.png
      each 1996 photo composited into its engraved frame, transparent outside the frame
  game/message/planchette.png       the engraved pointing hand, opaque paper inside the ink
  game/message/board/*.png          the clock, the RULES easel, YES / NO / GOODBYE, THE END
  game/message/coins/coin_first.png, coin_second.png   the players' coins
  game/message/hours/<style>/hour_01.png ... hour_12.png   the corner clock, one per hour
  game/message/message.json         everything the game needs (also as message_data.gd, which
                                    a web export always includes): file paths, each card's target
                                    and the planchette's fingertip in image pixels, the words
  game/audio/*.mp3                  the coyotes and the siren (Godot imports MP3, not FLAC)

The clip art comes from assets/clipart/ (kept out of git: the discs' images are licensed for
use inside a product, not for handing out as files). Run on the maker's Mac:
  python3 tools/message/package.py        (needs Pillow, ffmpeg for the audio, Ghostscript for the clocks)
"""
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CLIP = ROOT / "assets" / "clipart"
FIELD = ROOT / "assets" / "audio" / "field" / "coyotes-2026-10-16" / "clips"
OUT = ROOT / "game" / "message"
AUDIO = ROOT / "game" / "audio"
PAPER = (240, 234, 220)
INK = (24, 20, 16)
CARD_HEIGHT = 560          # cards are drawn this tall (the game's viewport is 648 high)

BOARD = {
    "clock": "art-explosion-10/Traditional Images/Instruments, Tools, Gadgets/Clock 2",
    "rules": "art-explosion-10/Traditional Images/Broadsides & Word Frames/Rules",
    "level": "art-explosion-10/Traditional Images/Instruments, Tools, Gadgets/Level",
    "the_end": "art-explosion-11/Traditional Images/Letters (Part 2)/Words/Angel Shadow \"The End\"",
    "coyote": "art-explosion-10/Traditional Images/Animals/Mammal Designs/Other Mammal Designs/Coyote on Bough",
}
SOLID = {"the_end"}
LETTERS = {  # the "Swirls" alphabet, for YES, NO and GOODBYE
    "Y": "art-explosion-11/Traditional Images/Letters (Part 2)/Letters V - Z/Y - Swirls",
    "E": "art-explosion-10/Traditional Images/Letters (Part 1)/Letters E - G/E - Swirls",
    "S": "art-explosion-11/Traditional Images/Letters (Part 2)/Letters R - S/S - Swirls",
    "N": "art-explosion-11/Traditional Images/Letters (Part 2)/Letters M - N/N - Swirls",
    "O": "art-explosion-11/Traditional Images/Letters (Part 2)/Letters O - Q/O - Swirls",
    "G": "art-explosion-10/Traditional Images/Letters (Part 1)/Letters E - G/G - Swirls",
    "D": "art-explosion-10/Traditional Images/Letters (Part 1)/Letters C - D/D - Swirls",
    "B": "art-explosion-10/Traditional Images/Letters (Part 1)/Letters A - B/B - Swirls",
}
# The corner clock: Art Explosion 8's "Time" folder has a clip-art clock for every hour, as
# EPS (vector PostScript), rendered with Ghostscript. Default: the digital alarm on a
# nightstand, which reads 3:00 on the last card ("get some sleep"). Alternative: bell alarm.
TIME = "art-explosion-08/Clip Art/Time"
HOUR_STYLES = {"digital": "Digital Alarm - {:02d} o'Clock", "alarm": "{:02d} o'Clock - Alarm"}
HOUR_HEIGHT = 180

# The players' coins, from money nobody spends any more: the first player to pick a controller
# gets a 1969 West German mark, the second a 1992 ECU. They drop it in the 1P or 2P slot, then play with it (their hand on the board).
# Art Explosion 6 has a folder of coin drawings, as EPS.
COINS = {
    "first": "art-explosion-06/Clip Art/Money/Coins & Currency/Deutsche Mark 4",   # West Germany, 1969
    "second": "art-explosion-06/Clip Art/Money/Coins & Currency/ECU 1",            # the ECU, 1992: never in anyone's pocket
}
COIN_SIZE = 96

SOUNDS = {  # game name: source clip (see the clips' NOTES.md)
    "siren_and_coyotes": "2026-10-17-1832-siren-and-chorus-far.flac",
    "coyotes_far": "2026-10-17-1832-chorus-far.flac",
    "coyotes_near": "2026-10-17-1832-chorus-near.flac",
    "two_howls": "2026-10-18-2347-two-howls.flac",
    "night_insects": "2026-10-18-1929-night-insects-60s.flac",
    "dusk": "2026-10-16-1758-calm-ambience-60s.flac",
    "lone_coyote": "2026-10-19-0528-lone-coyote-three-howls.flac",
    "drive_spin_up": "2026-10-19-0533-cd-drive-spin-up.flac",
    "drive_spinning": "2026-10-19-0533-cd-drive-spinning-30s.flac",
    "drive_eject": "2026-10-19-0535-cd-drive-spin-down-eject.flac",
    "tray_close": "2026-10-19-0539-cd-tray-close.flac",
}


def gray(path: str, turn: int = 0) -> Image.Image:
    im = Image.open(CLIP / path).convert("L")
    return im.rotate(turn, expand=True, fillcolor=255) if turn else im


def flood(g: Image.Image, seeds) -> Image.Image:
    """L mask, 255 where white paper is connected to any seed point."""
    bw = g.point(lambda v: 255 if v > 128 else 0).convert("RGB")
    for s in seeds:
        if bw.getpixel(s) == (255, 255, 255):
            ImageDraw.floodfill(bw, s, (255, 0, 0), thresh=10)
    r, gg, _ = bw.split()
    return ImageChops.subtract(r, gg).point(lambda v: 255 if v > 128 else 0)


def corners(im: Image.Image):
    w, h = im.size
    return [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]


def cutout(g: Image.Image, holes=()) -> Image.Image:
    """An engraving as RGBA: ink, opaque paper inside, transparent outside (and in `holes`)."""
    outside = flood(g, corners(g))
    for hole in holes:
        outside = ImageChops.lighter(outside, hole)
    rgb = Image.merge("RGB", [g.point(lambda v, a=a, b=b: int(a + (b - a) * v / 255)) for a, b in zip(INK, PAPER)])
    out = rgb.convert("RGBA")
    out.putalpha(ImageChops.invert(outside))
    return out


def card_png(card: dict, spec: dict) -> tuple:
    """(RGBA card, target in card pixels)."""
    photo = Image.open(CLIP / card["image"]).convert("RGB")
    src, _, turn = spec["frame_portrait" if photo.height > photo.width else "frame_landscape"].partition("@")
    g = gray(src, int(turn or 0))
    window = flood(g, [(g.width // 2, g.height // 2)])
    frame = cutout(g, holes=[window])
    k = CARD_HEIGHT / frame.height
    frame = frame.resize((round(frame.width * k), CARD_HEIGHT), Image.LANCZOS)
    window = window.resize(frame.size, Image.NEAREST)
    x0, y0, x1, y1 = window.getbbox()
    ww, wh = x1 - x0, y1 - y0
    cx, cy, zoom = card.get("crop", [0.5, 0.5, 1.0])
    s = max(ww / photo.width, wh / photo.height) * zoom
    big = photo.resize((round(photo.width * s), round(photo.height * s)), Image.LANCZOS)
    pad = (0, 0)
    if big.width < ww or big.height < wh:
        # zoomed out past the oval: fill around the photo with the colour of its own edges
        edge = Image.new("RGB", (1, 1))
        edge = photo.crop((0, 0, photo.width, 4)).resize((1, 1), Image.LANCZOS).getpixel((0, 0))
        canvas = Image.new("RGB", (max(ww, big.width), max(wh, big.height)), edge)
        pad = ((canvas.width - big.width) // 2, (canvas.height - big.height) // 2)
        canvas.paste(big, pad)
        big = canvas
    ox = int(min(max(cx * big.width - ww / 2, 0), big.width - ww))
    oy = int(min(max(cy * big.height - wh / 2, 0), big.height - wh))
    layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    layer.paste(big.crop((ox, oy, ox + ww, oy + wh)), (x0, y0))
    layer.putalpha(window)
    layer.alpha_composite(frame)
    pw, ph = big.width - 2 * pad[0], big.height - 2 * pad[1]   # the photo itself, inside any fill
    target = [round(x0 + pad[0] + card["target"][0] * pw - ox), round(y0 + pad[1] + card["target"][1] * ph - oy)]
    return layer, target


def main() -> None:
    spec = json.loads((HERE / "cards.json").read_text())
    (OUT / "cards").mkdir(parents=True, exist_ok=True)
    (OUT / "board").mkdir(parents=True, exist_ok=True)
    AUDIO.mkdir(parents=True, exist_ok=True)
    data = {"about": "Generated by tools/message/package.py from tools/message/cards.json. "
                     "Coordinates are in the image's own pixels (top-left 0,0).",
            "cards": [], "secret": None, "board": {}, "letters": {}, "sounds": {}}

    for card in spec["cards"] + [dict(spec["secret"], secret=True)]:
        name = "secret" if card.get("secret") else f"card{card['n']}"
        im, target = card_png(card, spec)
        im.save(OUT / "cards" / f"{name}.png")
        if "target_px" in card:   # a spot in the card itself (the secret: where the fingers meet)
            target = card["target_px"]
        entry = {"image": f"res://message/cards/{name}.png", "size": list(im.size),
                 "target": target, "words": card["words"], "caption": card["caption"]}
        if "target_radius" in card:   # in card pixels; otherwise the game's READ_RADIUS
            entry["radius"] = card["target_radius"]
        if "beam_px" in card:
            entry["beam"] = card["beam_px"]
        if card.get("secret"):
            data["secret"] = entry
        else:
            entry.update(n=card["n"], hour=card["hour"])
            data["cards"].append(entry)

    hand = cutout(gray(spec["planchette"]))
    hand = hand.resize((240, round(240 * hand.height / hand.width)), Image.LANCZOS)
    hand.save(OUT / "planchette.png")
    alpha = hand.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    xs = [x for x in range(hand.width) for y in range(hand.height) if alpha.getpixel((x, y))]
    tip_x = max(xs)
    tip_y = round(sum(y for y in range(hand.height) if alpha.getpixel((tip_x, y))) /
                  max(1, sum(1 for y in range(hand.height) if alpha.getpixel((tip_x, y)))))
    data["planchette"] = {"image": "res://message/planchette.png", "size": list(hand.size),
                          "fingertip": [tip_x, tip_y], "points": "right"}

    for name, path in BOARD.items():
        g = gray(path)
        # a vignette with gaps in its border would leak: back it with paper instead
        im = cutout(g) if name not in SOLID else Image.merge("RGB", [g.point(
            lambda v, a=a, b=b: int(a + (b - a) * v / 255)) for a, b in zip(INK, PAPER)]).convert("RGBA")
        im.save(OUT / "board" / f"{name}.png")
        data["board"][name] = {"image": f"res://message/board/{name}.png", "size": list(im.size)}
    for letter, path in LETTERS.items():
        im = cutout(gray(path))
        im.save(OUT / "board" / f"letter_{letter}.png")
        data["letters"][letter] = f"res://message/board/letter_{letter}.png"

    (OUT / "coins").mkdir(parents=True, exist_ok=True)
    data["coins"] = {}
    for name, path in COINS.items():
        png = OUT / "coins" / f"coin_{name}.png"
        subprocess.run(["gs", "-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pngalpha", "-r300",
                        "-dEPSCrop", f"-sOutputFile={png}", str(CLIP / path)], check=True)
        im = Image.open(png)
        im = im.crop(im.getchannel("A").getbbox())
        k = COIN_SIZE / max(im.size)
        im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS).save(png)
        data["coins"][name] = f"res://message/coins/coin_{name}.png"

    data["hours"] = {}
    for style, pattern in HOUR_STYLES.items():
        (OUT / "hours" / style).mkdir(parents=True, exist_ok=True)
        data["hours"][style] = []
        for hour in range(1, 13):
            src = next((CLIP / TIME).rglob(pattern.format(hour)))
            png = OUT / "hours" / style / f"hour_{hour:02d}.png"
            subprocess.run(["gs", "-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pngalpha", "-r300",
                            "-dEPSCrop", f"-sOutputFile={png}", str(src)], check=True)
            im = Image.open(png)
            im.resize((round(im.width * HOUR_HEIGHT / im.height), HOUR_HEIGHT), Image.LANCZOS).save(png)
            data["hours"][style].append(f"res://message/hours/{style}/hour_{hour:02d}.png")

    for name, clip in SOUNDS.items():
        if not (FIELD / clip).exists():   # the field recordings aren't public: keep the shipped MP3
            print(f"no {clip}: keeping game/audio/{name}.mp3")
            data["sounds"][name] = f"res://audio/{name}.mp3"
            continue
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(FIELD / clip),
                        "-c:a", "libmp3lame", "-b:a", "192k", str(AUDIO / f"{name}.mp3")], check=True)
        data["sounds"][name] = f"res://audio/{name}.mp3"

    (OUT / "message.json").write_text(json.dumps(data, indent=2, ensure_ascii=False))
    # The same data as a script: Godot's default export ("all resources") leaves .json files
    # out of the web build, but a script always ships. The session reads this one.
    (OUT / "message_data.gd").write_text(
        "extends RefCounted\n## Generated by tools/message/package.py; edit tools/message/cards.json instead.\n"
        "const DATA := " + json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {OUT}/message.json, {len(data['cards'])} cards + secret, "
          f"{len(data['board'])} board pieces, {len(data['letters'])} letters, {len(data['sounds'])} sounds")


if __name__ == "__main__":
    main()
