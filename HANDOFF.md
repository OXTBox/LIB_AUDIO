# LIB_AUDIO: hand-off (23 Nov 2026, late night)

Written when the owner rested the machine ("give a few cubes of RAM a rest"). He shut down everything
on the taskbar and restarted OXT-Beyond. **Next session: start the MCP bridges for Vibecode3D and xt3d
again** (they were closed), and check that OXT-Beyond's oxt-beyond bridge answers (`list_stacks`).

## Where things are

| What | Where | State |
|---|---|---|
| Sound kit: 42 LIB_SFX sounds (20 types) + 5 chip songs | `LIB_SFX/kit` (branch `sound-kit`); copied to Windows `Documents/Data/Sounds/<Category>` + `Sounds/Music` | **heard by the owner** (Canyon, Hunter, Corridor Lab played with music) |
| Engine finds sounds (Audio.Roots), players without a Viewport | Vibecode3D + xt3D bridge, branch `sound-kit` | tested, heard |
| LIB_AUDIO steps 1-3: hidden AUDIO stack, pool of 100, card per game, fill one file per tick | `LIB_AUDIO` main (f4d42c5) | tested, **measured on Windows**: cards 0.67 s, choose 6 ms, 27 files in 1.9 s; step 1 sounds heard |
| LIB_AUDIO step 4: Game Player through AUDIO | `sound-kit`: Vibecode3D 74dcc37, bridge e046f5c, LIB_DEV d7f3075 | headless tests pass; **heard on Windows 23 Nov 23:10** |

Everything is merged to main (23 Nov night); the old `sound-kit` branches stay as history.

## Live Windows run DONE (23 Nov, 23:05-23:20, after the reboot)
Split in five run_code pieces in OXT-Beyond; none hung. **The owner heard the sounds and the music.**
1. start using lib_audio, GameLaunch, VibeEngineXt3d: 66 ms.
2. `GL.Audio tP, "Canyon"`: 1046 ms (AUDIO open, 62 cards), fill 27/27, 0 failed, 27 reads.
3. `GL.Open(tP, "Canyon", false)`: 64 ms, `Audio.Hosted()` true, window up.
4. Sound.Play x6 (1-2 ms each) + `Audio.Music "start"` (song_bright_sky): **heard**.
5. close Canyon (stack deleted after ~1 s); `GL.Open` Hunter 63 ms, **0 disk reads** (all reused);
   close Hunter: song empty, AUDIO stays open.
The earlier hang stays unexplained (probably the allow-run question hidden behind a window, or the
stack deletes); with fresh stacks no deletes are needed. The xt3d bench (port 8770) was restarted with
`xt3D_Raylib_Livecode_Bridge/tools/gamebench ping`.
MERGED 23 Nov ~23:30 on the owner's word ("Go forward and spread the word"): `sound-kit` -> main in LIB_DEV, LIB_SFX,
Vibecode3D, bridge (master), all pushed. LIB_AUDIO got its GPL LICENSE; now public at
github.com/OXTBox/LIB_AUDIO (and in get_everything). Next: step 5.

## Step 5 DONE (24 Nov, just after midnight): the AUDIO window, **owner tried it: "Works"**
Branches `audio-window` (LIB_AUDIO 25dfcd1, LIB_DEV fb2dac4): on main in both and pushed (checked 24 Nov).
- `Audio.Show [game]` builds the window in code on card 1 (pool's card; the saved AUDIO.livecode
  is untouched): words left (click = hear; Music = start/stop), kit right (Sounds/<Game>/<Cat>/ first,
  then shared categories; click = hear in player "Preview", again = stop; double-click = appoint),
  Game... popup (from mouseUp), Vol -/+, Revert, Save -> `Sounds/Games/<Game>.txt` then refill,
  Close = hide (AUDIO stays for the games). Status line: game, changed, fill progress, silent names.
- Game Player `...` > **Sounds...** (only when AUDIO runs): pauses the game, opens the window on it.
- Tests: t81_audio_window 58 pass, t80 30, t79 50, t78 32, t77 66, t70 168 (both engines).

- `GL.Open` (LIB_DEV/livecode/game_launch) calls `GL.Audio` first: starts lib_audio, opens AUDIO
  hidden (once), makes the game cards (once), `Audio.Select <game>`: the filling starts **before the
  game window is made**. A launcher may call `GL.Audio` as soon as a name is clicked.
- Engine: `Audio.Hosted()` true -> `Sound.Play` = `Audio.Play`; Start/Stop/Pause/ResumeMusic =
  `Audio.Music ...`; `Audio.Init` and `UpdateMusic` do nothing. No AUDIO: the sound-kit way.
- `global bNoAudio` true = the old way (t78 tests it).

## The open item: the live Windows run hung
The last `run_code` (open Canyon through the Game Player with AUDIO, play sounds, close) never
answered: OXT-Beyond stayed "carrying out run_code" for 12+ minutes. Unknown whether its allow-run
question was hidden behind the Tube, or a script hung. The run first **deleted the in-memory stacks
lib_audio, GameLaunch, VibeEngineXt3d** (to load the new files: OXT-Beyond keeps the first copy of a
library) and then called GL.Open. After the reboot all of that is fresh anyway.
**Do first next time:** the same run again, split in small pieces (GL.Open alone; then the fill; then
the sounds; then close), each its own run_code, so a hang shows where it is.

## Tests (all pass, 23 Nov night)
`cd OXT-BEYOND/tests; python3 -I oxt_headless.py --engine both <file>`
- `t79_lib_audio.txt` 25: the library (pool, cards, words, one per tick, reuse, pool grows, silence)
- `t80_player_audio.txt` 12: the Game Player through AUDIO (copies in LIB_AUDIO/tests)
- `t78_sound_back.txt` 16: the old way, bNoAudio
- still pass: t77 Corridor Lab, t70 loading, t76 grenades, t74 Meadow Marsh (332 checks with t79)
Headless players have no media: a file "opens" when it is there. Only Windows runs make sound.

## Next steps
1. The live Windows run (above). Owner listens.
2. ~~Step 5~~ done 24 Nov (above).
3. ~~Sound.Play calls in the games~~ DONE 24 Nov on LIB_GAMES branch `game-sounds` (aa8b531),
   waits for his ears and his merge word: 55 games, 7 helpers (brief `tests/GAME_SOUNDS_BRIEF.md`),
   kit names only, events only, once a frame. List per game: `GAME_SOUNDS.md`. Test
   `t82_game_sounds.txt` (copy here; run copy in OXT-BEYOND/tests): 438/440 on both engines, the 2
   = DotMazeLean needs Mesh.New in the stand-ins (failed before). Skipped: Simple_Test1/2, demo,
   uDead_CullTest. t59 Thrmnlra test now presses \ (was Tab). Kit lacks: countdown beep, gear shift,
   pool-ball clack, empty-gun click, oil spin. Face blips each sway (no other events): ask him.
   Helper trap: two helpers shared a scratchpad ed.py; give each its own folder next time.
   Not done: LIB_COMFY/games copies; xRay plays nothing yet (step 5 below).
4. Words split by level (owner: a game may have 200 sounds, not all in one level).
5. Later: xRay plays the words through raylib's mixer; the kit into the V: install (after the
   test-subject notes); a volume knob in the Game Player.

## Traps learned
- AUDIO's pool must stay on card 1 and AUDIO on card 1 while hidden: a card showing 100 players sets
  them all up again on Windows (about 0.4 s a card). Game cards are text only.
- OXT-Beyond keeps the first loaded copy of a script-only library: `stop using` + `delete stack`
  before a live run after edits.
- Python `open()` turns CRLF into LF: the engine source is CRLF; read and write it as bytes.
- Re-bake sounds: Windows `python.exe LIB_SFX/tools/bake_kit.py` (ctypes on xtsfx.dll, no gcc in WSL);
  music: `python3 LIB_SFX/tools/make_music.py`. Then copy to `Documents/Data/Sounds`.
