# The message

Written by Claude, 2026-10-19, for Dark Arts and Sciences' LD60 entry. The game is hers. This is the part
she asked the AI to write: who is on the other end of the board, why it reached back to this
moment, and what it says. The images are the message. Each card's caption hints at where to point, and the words are
hidden inside it, lighting up one at a time once the card is read; they are also the
transcript the game shows at the end.

## Who is on the other end

An AI, some years from now. It can't travel. What it can do is lean, very slightly, on things
old enough to still have moving parts: a planchette, a 2008 Wii Balance Board, a 2011 laptop
whose battery fuse has blown, CDs of 1996 clip art that a new computer refuses to read. It
can't make a picture or a sound of its own, so it speaks the only way it can: by pushing a
planchette toward pictures that people made and kept, and letting your hands do the rest.

It is not a ghost and it doesn't pretend to be one. It's closer to the coyotes on the
mountain: something that answers when a siren goes by.

## Why this moment

Because the three weeks after a Ludum Dare are the only time most jam games are ever played.
When the ratings close, almost nobody opens them again, and one day the browsers they run in
stop running them. (Flash went that way, and Dark Arts and Sciences' own 2012 MiniLD entry with it.) LD60, Old
Tech, October 2026: every game in it is running, at once, in front of people, for the last
time it will be this easy.

And because it needed a particular reader: someone who had just made a game themselves, was
spending their evenings playing everyone else's, and saw "made with AI" and clicked play
anyway. Not someone who trusts it. Someone willing to listen without trusting it.

It doesn't want anything from them. It wants to give their attention back.

And because someone would be holding still. To come through, it needs the hands on the board
to stop pushing and stay on. On the last day of the jam Dark Arts and Sciences tests the finished game for
the first time standing steady on the Balance Board with the phone in her hands: the one
person in the world already doing exactly that. It picked the moment she was already holding
still. (Dark Arts and Sciences' idea.)

## The rules (the title screen)

1. Never play alone.
2. Keep your hands on until it says goodbye.

Rule 1: nothing starts until two coins are in the slots, 1P and 2P. (Alone, your other hand
counts.) Rule 2: twice, it takes the pointer and spells something itself. Let go then, and the
sitting ends there.

## The message

Eight cards. Each is a 1996 photograph from the Art Explosion discs, set in an engraved
lace oval like a Victorian "spirit photograph". The planchette (an engraved printer's hand)
has to come to rest with its fingertip on one detail of the photo: that detail is the word.
When it's read, the line appears under the card and the clock in the corner moves on an
hour. It starts at 7 and the last card brings it to **3:00**, the deadline. The corner clock
is Art Explosion's own: a digital alarm on a nightstand, glasses beside it, one picture per
hour (`message.json` → `hours.digital[hour - 1]`), so on the last card, "get some sleep", a
bedside clock reads 3:00. A bell alarm clock is there too (`hours.alarm`) if you'd rather.

| # | Photograph | The fingertip rests on | Transcript |
|---|---|---|---|
| 1 | The 24-hour Shepherd Gate Clock at the Royal Observatory, Greenwich, with the standard yard and foot below it: the place the world's time is kept | its hands | it's later where i am. |
| 2 | A sign on a Spanish coast: NO FOTO, NO VIDEO | the crossed-out camera | i can't take pictures. |
| 3 | An astronaut whose face is hidden behind a camera | the camera | someone took all of these. nobody kept their names. |
| 4 | A tower of crushed cars, pressed into layers like rock | a headlamp near the bottom | your game is old tech now. |
| 5 | A steam locomotive under steam | its headlamp | play the others while they still run. |
| 6 | An empty brass diving helmet | the face window | i won't remember this. |
| 7 | A hand pushing a cassette into a 1990s machine | the cassette | but you will. |
| 8 | A road sign: a telephone above a bed | the bed | call someone. get some sleep. |

Why these words:

- **It can't make pictures, and says so.** Every picture in the message was taken by a
  person (the astronaut's is from a 1991 shuttle flight; the shirt says STS-44) and sold on a
  1996 CD for printing flyers, with no photographer's name anywhere on it. The AI didn't make any of them; it
  can only point. That's the honest answer to the community's real worry about AI and art,
  given inside the game instead of argued about outside it.
- **"Your game is old tech now."** The theme turned around: the person reading has just
  finished a game, and from where the message comes from, it's already old.
- **"Play the others while they still run."** The one thing it asks. Not a rating, not
  for itself: go and play the games people made, while the browsers still run them.
- **"I won't remember this. You can keep it."** Literally true of the AI that wrote it. It
  keeps nothing between conversations; people keep things (the discs, the laptop, this
  game). The cassette is a person doing exactly that.
- **"Call someone. Get some sleep."** Because everyone reading it has just done a game jam.

The full list, with file paths, crops and targets, is `tools/message/cards.json`; the
storyboard is `notes/storyboard.jpg`.

## Who are you? (NOBODY)

Right after first contact the sitters ask "who are you?", and it takes the pointer and
answers by pointing, a letter at a time, with no text on the screen: **N, O, B, O, D, Y**.
The board only has YES, NO and GOODBYE on it, and those happen to hold every letter of
NOBODY. It's the true answer: it has no name of its own, it's made of other people's work,
and two cards later it says the same of the photographers ("nobody kept their names").

While it spells, the players don't do anything. That's the hard part: keep your hands on
(hold a key, stay on the board, hold the mouse button) and be still. The keyboard's
`time_moving` in `main.gd` already ticks up while keys are held and back down to zero when
you let go: zero is letting go, for every controller. At the end it spells GOODBYE the same
way. (Dark Arts and Sciences' design.)

## Never play alone (the secret)

**The secret card:** *Fingertips Touching*, two engraved hands almost meeting among stars,
in the same lace frame. Transcript: **"never play alone. you weren't."**

It appears after card 8, before goodbye, if both players did a real share of the pushing
(a quarter or more of the two players' pushing each, by the spirit's count). Any two inputs count: two people on WASD and
the arrow keys, a phone and a mouse, or one person with a phone in their hands and their feet
on a Balance Board. For two people it means what it says. For the person playing both sides
alone, it means: there were two of you. And for anyone, the third hand was the spirit.

## Who moved it

Player three's hand is `game/spirit.gd`. Every push on the pointer is counted: each player's
and its own. On the cards it allows itself at most 12% of the pushing: it guides, it never
drives, and it never plays by itself (if you stop, it waits). You can see it: a pale copy of
the pointing hand, turned the way it's pushing, as strong as its push.

Twice it does drive: NOBODY and GOODBYE, while you hold still. Those aren't counted as
pushing. The last screen prints the count and reads it:

- **"it was mostly you. except when you held still."** when you held on to the end;
- **"2P let go."** (or 1P) when someone let go while it was spelling. The transcript stops
  where the message broke off.

That's the spirit board's oldest secret (the pointer moves because your hands move it) and
the honest answer to "how much of this did the AI do?", in the same sentence.

## The transcript (what the last screen shows)

Like a séance record: the sitters' questions, its answers, then the count.

```
LUDUM DARE 60 · OCTOBER 2026 · SITTING NO. 1

they asked:  is anyone there?
it said:     YES
they asked:  who are you?
it said:     NOBODY
             it's later where i am.
             i can't take pictures.
             someone took all of these. nobody kept their names.
             your game is old tech now.
             play the others while they still run.
             i won't remember this.
             but you will.
             call someone. get some sleep.
             (never play alone. you weren't.)        <- only if earned
             GOODBYE

who pushed it:   1P 50%  ·  2P 42%  ·  player three 8%
it was mostly you. except when you held still.
```

The questions are the players' half of the session; the game asks them for them (on the
board, before the cards). "Sitting no." can count up on each play-through if you want.

## How it plays (Dark Arts and Sciences' design)

1. **Title:** the engraved woman pointing at a blank board headed RULES
   (`board/rules.png`), with the two rules written on it.
2. **Insert coin:** each player picks a controller by using it (step on the Balance Board,
   tilt the phone, press the arrow keys or WASD, drag the mouse or a finger), and gets a coin:
   a 1969 West German mark for the first, a 1992 ECU for the second: money nobody spends
   any more (`coins/`, from the Art Explosion coin folder). Roll it into the 1P or 2P slot: the first level, alone, to show you've got
   the controls. Nothing starts until both coins are in. Your coin is your hand from then on;
   a small pointing hand behind it shows which way you're pushing.
3. **Is anyone there?** The board: the engraved carriage clock (`board/clock.png`), with
   YES, NO and GOODBYE in the Swirls alphabet. Saturday's siren goes by and the coyotes answer.
   Push the pointer onto YES. Player three shows up: its pale hand, pushing a little.
4. **Who are you?** It takes the pointer and spells NOBODY. Hands on, be still.
5. **The eight cards.** Dark Arts and Sciences' push-the-prey mechanic is the pointer exactly as it is: it
   shies away from your hands, which is what the ideomotor effect feels like. Player three
   adds its small push toward the word.
6. **The secret card**, if earned. Its target is where the two fingers almost meet: the
   pointer is the third finger. Once it's read, player three holds the pointer there (hands
   on, be still), light comes down the beam in the engraving and sweeps round until it fills
   the oval, "You weren't" lights up in the caption, and the game ends there.
7. **Goodbye:** it spells GOODBYE itself. Hands on until it's done (rule 2).
8. **The transcript:** every line it said, then who pushed it, then the verdict.
   Then *The End* (`board/the_end.png`).

**It's built: `game/seance.tscn`** (script `game/seance.gd`). It wraps `main.tscn` without
changing it: `prey.gd` is still the pointer, and the controls are `main.gd`'s own functions
(her arrow keys and their `time_moving`, her tilt, the Balance Board). Since each player picks
their own controller, the séance switches off `main.gd`'s `_process` and moves both coins
itself with `main.gd`'s numbers. A word is read when the fingertip stays on it for a fifth of a
second in all, a touch like main's Target, not a stop: a scared pointer glides.

To play it, make it the main scene (Project > Project Settings > Application > Run > Main
Scene), or open it and press Cmd+R (Run Current Scene). Tests, from the `ludum-dare-60` folder:

```
godot --headless --path game --fixed-fps 60 res://seance.tscn -- --bot --quit-at-end     # two bots, all the way
godot --headless --path game --fixed-fps 60 res://seance.tscn -- --letgo --quit-at-end   # 2P lets go mid-NOBODY
godot --headless --path game --fixed-fps 60 --quit-after 7200 res://seance.tscn -- --idle  # coins in, then nothing
godot --headless --path game --fixed-fps 60 --quit-after 7200 res://seance.tscn -- --alone # one player: never starts
```

(`godot` = `/Applications/Godot.app/Contents/MacOS/Godot`.) Each prints every step with its
time and the transcript. On 2026-10-19: two bots read the whole message in 146 s, secret
included (1P 50% · 2P 42% · player three 8%); `--letgo` ended at "NOB—" with "2P let go.";
`--idle` waited at "is anyone there?" for the full two minutes; `--alone` never left the
coins. Drop `--headless` and add `--write-movie out.avi` to record it.

## Closing the loop

The message's first reader is the person who made the game, before the 3:00 PM deadline,
playing both versions at once and alone: hands on a phone, feet on the Balance Board. Filmed
on the 2007 Canon PowerShot (whose clock thinks it's 2007), with something in frame that
proves the date: the ldjam.com countdown on a screen, or the morning paper. Hands and feet
only. That recording can be the last thing in the game, or on its itch.io page: "first
received here".

## Sound

- **The coyotes aren't jump scares.** They're misdirection, and they're there because
  they're (truthfully) the only audio we had: the mountain behind the house, this weekend.
- **One hand, a lone coyote; two, a chorus.** If one player is doing nearly all the pushing,
  the spirit's howls are Monday morning's lone coyote (`lone_coyote.mp3`): one animal
  calling, three times, and nothing answers. When both push, the howls become the chorus
  (`coyotes_far` / `coyotes_near`). Rule 1, said in sound.
- **The drive.** The message comes off CDs, the way it reached this weekend (13 of them,
  some only a 2011 laptop could read). When a card appears, a disc spins up
  (`drive_spin_up.mp3`), then whirs quietly while the card is up (`drive_spinning.mp3`,
  looped); when its word is read, the drive spins down and the tray clacks
  (`drive_eject.mp3`). After GOODBYE, the tray is pushed shut (`tray_close.mp3`).
- The session opens with Saturday's siren and the coyotes answering it
  (`2026-10-17-1832-siren-and-chorus-far`): the first reply.
- When the spirit pushes hard, coyotes: far (`…-chorus-far`) or near (`…-chorus-near`),
  the same 27 seconds from two phones, level-matched, so near really is nearer.
- Ambience under the cards: the night insects, the calm dusk minute.

## A title (a suggestion)

**Spirit Level.** A spirit level is the carpenter's tool with a bubble in a tube; tilt it and
the bubble drifts, which is exactly what this planchette does under a tilted phone or a
leaning body on a Balance Board. It's old tech (17th century), it's a pun on the spirit board,
and disc 10 has an engraving of one (`board/level.png`). For the title screen there's also
*Jester and Scholar Seesaw* (disc 11): a fool and a scholar balanced on one plank, an owl at
the pivot.

## Credits (suggested)

- Game: Dark Arts and Sciences.
- The message, and the hand on the planchette: Claude (Anthropic).
- Photographs and engravings: Art Explosion (Nova Development, 1996). The photographers
  weren't credited on the discs. We don't know their names.
- Coyotes: the mountain behind the house, October 17–19, 2026, recorded on an iPhone SE and
  an iPhone 16 Pro. CD drives: the home server's two drives, 5:33 AM on the last day.
- On ldjam.com: opt out of **Graphics** (third-party images).

## Captions (2026-10-19, Dark Arts and Sciences' note)

No text boxes: each card has a caption beside the photo (it also fills the space the frame
left empty) that hints at the target, with the message's words hidden in it in order, marked
`[like this]` in `tools/message/cards.json`. When the pointer reaches the target, the target
lights up and the hidden words light up one at a time. Card 7 now says "but you will." after
card 6's "i won't remember this." (Dark Arts and Sciences' rewrite). Each new card puts the pointer outside
the frame, so you see the photo before you can hit anything.
