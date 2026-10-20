# Spirit Level

A spirit board that speaks in 1996 clip art. Never play alone.

Ludum Dare 60 (theme: Old Tech), Jam entry, October 2026. Made in Godot 4.7 by Dark Arts and
Sciences, with Claude (Anthropic), who wrote the message and plays the third hand on the
pointer. [Play it on itch.io](ITCH_URL) · [Ludum Dare page](LDJAM_URL)

## What's here, and what isn't

- `game/`: the Godot project. `main.gd` and `prey.gd` are the core mechanic (your hand, the
  pointer that runs from it); `seance.gd` is the session around it (coins, board, cards,
  transcript; the main scene is `seance.tscn`); `spirit.gd` is player three; `board_input.gd`
  is the Balance Board autoload.
- `game/audio/`: the game's sounds (coyotes and CD drives, recorded during the jam).
- `tools/message/`: `cards.json` is the message, card by card, with each caption's hidden
  words in `[brackets]`; `package.py` builds the game's pictures from the clip-art discs.
- `tools/balance-board/`: the Wii Balance Board bridge (see below).
- `notes/STORY.md`: who is on the other end, and why this moment.

**Not included: the pictures.** They're Art Explosion clip art (Nova Development, 1996),
licensed for use inside a product, not for handing out as files. So `game/message/` has the
message's data but none of its images, and the project won't run until you rebuild them, or
play the published build instead. The original field recordings aren't included either, only
the MP3s the game uses.

## Rebuilding the pictures

You need the 13 Art Explosion CDs (Mac HFS discs; a modern Mac can't mount them).

1. Copy each disc's contents to `assets/clipart/art-explosion-01` … `art-explosion-13`.
   On Linux: `mount -t hfs -o ro,loop,offset=4608 disc.img /mnt`. File names on the discs
   are Mac Roman; `tools/clipart-cds/untar_macroman.py` converts a tar of them.
2. Install Pillow (`pip install Pillow`) and Ghostscript (for the EPS clocks and coins).
3. `python3 tools/message/package.py` writes `game/message/`.

## Playing on a Wii Balance Board

There's no Wii here, only a Balance Board, so the game reads it through an old Mac.

1. **A Mac that can pair the board.** Tested on a 2011 MacBook Air running OS X 10.11.
   macOS 12 and later can't connect to it at all (see `BoardTest.swift` for why).
2. **Build the reader** on that Mac:
   `clang -fobjc-arc -O2 -framework Foundation -framework IOBluetooth -framework IOKit -o boardbridge tools/balance-board/boardbridge.m`
   (`build-air.sh` does this over ssh, for Xcode 7.2's toolchain.) Run `./boardbridge`,
   press the red sync button under the board's battery cover, and it prints a line per
   reading.
3. **Run the server** on the Mac you'll play on:
   - the reader on the same Mac: `python3 tools/balance-board/board_server.py --local ./boardbridge`
   - the reader on another Mac, as `~/boardbridge/boardbridge`:
     `python3 tools/balance-board/board_server.py --ssh HOST`

   http://localhost:8765/ is a test page: a dot that follows your balance.
4. **Run the game** from Godot, or a web export served from `localhost`. The game only looks
   for the board on localhost, so the itch.io page can't use one. At the coin slots, step on
   the board to pick it.

## Testing

`godot --headless --path game --fixed-fps 60 res://seance.tscn -- --bot --quit-at-end` plays
it through with two bots and prints the transcript. Also `--letgo`, `--idle`, `--alone`,
`--keys`, `--keys --mouse` (see the top of `seance.gd`).
