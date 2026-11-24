# LIB_AUDIO: the plan

Opus, 23 Nov 2026, from the owner's words after p1-09 (sound and music back). Nothing is built yet.
**This waits for your read and your yes.** Your answers of 23 Nov are in "Settled" at the end.

## Why
Sound came back on 23 Nov (branches `sound-kit`), but the way it loads is the old one: when a game
opens, `Audio.Init` creates about 52 player objects, one after another in a repeat loop, and gives
each one its file. Giving a player its file is what Windows is slow at. A repeat loop does not let
anything else happen until it is finished, so the window hangs: "a very long and almost crash-like
delay". It also loads every file again for every game, even when the last game had the same ones.

## The idea, in your words
"In the beginning there was the word." A game only knows sound **names** (`Sound.Play "Explode"`).
A hidden **AUDIO** window keeps the players, already made, and fills them a little at a time
while people read, so the sounds can play before anything is seen.

## What the player sees
1. The Game Player opens. AUDIO opens with it, hidden. Nothing waits for it.
2. You click a game name. The words change for you to read. Behind them, AUDIO starts filling its
   players with that game's sounds, **one file per tick**.
3. The music can start while the level is still being built, behind the loading screen.
4. You press play. Sounds that are ready play. One that isn't ready yet is silent: no error, no wait.

A game with no AUDIO window, or a name with no sound, plays on in silence, with no bugs.

## What is in AUDIO
`LIB_AUDIO/livecode/AUDIO.livecode`, a saved stack (not script only), so what's in it is already made:
- **One pool of 100 hidden players** in one group. They are made once by me and saved, so opening the
  stack creates nothing.
- **A card per game**: the game's **words**, meaning its list of sound names, each with its file. The cards
  are made from the games list when AUDIO opens or the list is refreshed: text only, so that's instant.
- A card "Kit": every sound in the kit, for choosing.

**Why one pool and not 100 players on every card:** a group with backgroundBehavior shows on every card,
but it's **the same 100 players**. A player's file is not kept per card (as field text can be). If
card "Canyon" gives player 1 `boom.wav`, card "Hunter" has `boom.wav` too. So the cards hold the words,
and the one pool plays whichever game is chosen.

## The words (a game's sound list)
One line per name: `name <tab> file <tab> copies <tab> volume`, e.g.

    Explode       Sounds/Explode/Explode_44.wav   3    80
    PlayerLaser   Sounds/PlayerLaser/            10    70     (a folder: its files take turns)
    Music         Music/                          1    60     (the songs, one plays at a time)

- **Where names come from:** AUDIO reads the game's script for `Sound.Play "..."`, which is instant.
  A name the kit also has gets the kit's file. Any other name shows as empty for you to choose.
- **Where it's kept:** a text file per game, `Data/Sounds/Games/<Game>.txt`, so your choices last,
  are readable, and can go into git. The card shows it and edits it.
- **copies:** how many players that name may use at once (PlayerLaser 10 for fast fire, most 1-2).

## Filling the players: one per tick, never a loop
`Audio.Select "<Game>"` starts a cycle: `send "Audio.Fill" to me in 20 milliseconds`, again and
again, until the list is done. Each time, for the next line of the game's list:

1. **Is that file already in a player?** (a small index: file -> player). Yes: the name just takes
   that player. No disk at all. Go straight on to the next line in the same tick, because this costs nothing.
2. **No:** give a free player that file. That's the one disk read, and it gets the tick to itself.
3. **Did it open?** One look: the player's `duration` is above 0. Not a wait. If not (a missing
   file, a bad path), that name stays silent, the line is marked on the card, and the cycle goes on.

So going from Canyon to Hunter reads only the files Hunter has that Canyon didn't, which with the kit is
probably none. When the pool is full, players whose names the chosen game doesn't use are given
out again first.

`Audio.Done()` says when a game's list is complete; `Audio.Progress()` gives "12/40" for the loading
screen if we want it shown.

## Not over WSL
Reading over `\\wsl$` from Windows is the slowest path we have. Players read from the Windows side:
**`Documents/Data/Sounds`** (LIB_DATA), or **`Vibecode3D Common/Sounds`** in an install.
`LIB_SFX/kit` stays where the sounds are made; `Audio.SyncKit` copies new or changed kit files to
`Data/Sounds` (also one per tick). It runs after a re-bake, not every game.

## How a game and the engine use it
Nothing changes in the games: they keep calling `Sound.Play "Explode"`.
- The engine's `Sound.Play` passes to AUDIO when the AUDIO window is open, and is silent when it isn't.
- Music: `Audio.StartMusic` / `PauseMusic` / `StopMusic` the same way. The Game Player already calls them.
- The old `Audio.Init` loop (today's sound-kit branch) stays only until AUDIO works, then goes.

| Call | What it does |
|---|---|
| `Audio.Open` | opens AUDIO hidden; reads the games list, makes missing cards (text only) |
| `Audio.Select game` | shows that game's words; starts filling, one per tick |
| `Audio.Play name` | plays the next player of that name; silent if none or not ready |
| `Audio.Music "start" / "pause" / "stop"` | the songs of the chosen game |
| `Audio.Done()`, `Audio.Progress()` | filled yet?; "12/40" |
| `Audio.SyncKit` | copies the kit to the Data folder, one file per tick |
| `Audio.Show` | the AUDIO window, for choosing and appointing sounds |

## Steps
1. **Hidden-player test (small):** do players in an open but hidden stack make sound on Windows? Does
   `duration` come back right away? Does `start player` work while the stack stays hidden? The one
   thing that must be heard: I'll ask you to listen once.
2. **AUDIO.livecode:** the pool of 100, saved; cards from the games list; reading `Sound.Play` names;
   the word files in `Data/Sounds/Games`. Headless test.
3. **The fill cycle:** one per tick, the file -> player index, the duration check, reuse between
   games. Test: Canyon then Hunter reads nothing twice; the window answers clicks during the fill.
4. **Engine + Game Player:** `Sound.Play` / music through AUDIO; AUDIO opens with the Game Player;
   music during the loading screen. All the old game tests still pass.
5. **Choosing sounds (the window):** a game's words on the left, the kit on the right; click to hear,
   click to appoint; save.
6. **Later:** xRay (xt3d) plays the same words through raylib's mixer, so sounds overlap freely
   with no player counts; the kit copied into the V: install.

## Questions for you
1. **AUDIO as its own stack file** (`LIB_AUDIO/livecode/AUDIO.livecode`, opened by the Game Player,
   Vibecode3D and ComfyGames, one copy shared), or **a substack** inside each app's stack? I'd do its own
   file: one place to fix it, and every app gets it.
2. **Your choices in `Data/Sounds/Games/<Game>.txt`** (text, lasts, readable), or kept on the cards
   inside AUDIO.livecode (saved with the stack)? I'd do text files.
3. **100 players**: enough? With the kit, the largest game today uses about 50 with copies.
4. **Music** per game (each game's own songs), or one shared playlist with a game able to say otherwise?

## Settled (owner, 23 Nov)
- **Folders:** `Data/Sounds/<Category>/` is the shared kit (Laser, Explosion ... used over and over by
  every game, to keep the project light and lean). A game with sounds of its own, kept apart for a
  solo release, has `Data/Sounds/<Game>/<Category>/`. Its categories win over the shared ones of the same
  name; everything else comes from the shared kit. (Today's kit folder names become the categories.)
- **Players:** 100 is a start, not a ceiling. 100 empty players saved in a stack with one button was
  9 KB, so the pool can be much bigger ("10000 on one card, like an iPod"). A game may have 200 sounds,
  but not all in the same room/level: a game's words can be split by level, and the fill loads the
  level about to be played first.
- Corridor Lab worked great with the sound-kit branch.

Still open (my picks hold unless you say otherwise): AUDIO as its own stack file (Q1), your choices
as text files in `Data/Sounds/Games/` (Q2), and music: shared songs unless a game names its own (Q4).
