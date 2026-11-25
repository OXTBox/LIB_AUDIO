# Brief: add sounds to the games (LIB_AUDIO next step 3), 24 Nov 2026

**TWO ENGINES:** pure xTalk Vibecode3D (XT) and the xt3d Raylib bridge extension (xRay). The game
scripts below run on both; `vibe_engine_xt3d` is a GENERATED script, never edit it. Edit only game scripts.

## The job
Each game in `~/projects/LIB_GAMES/Vibecode3D_Games/Vibecode3D_Play_<Game>.livecodescript` gets
`Sound.Play "<Name>"` calls at its real gameplay events. Canyon and Hunter already do it: look at
`Vibecode3D_Play_Canyon.livecodescript` (lines 257, 343, 393, 460, 486, 506) for the style.

The engine's `Sound.Play` sends the name to the hidden AUDIO stack (LIB_AUDIO), which gives every name a
sound from the kit. AUDIO finds a game's names by **reading the script text** for `Sound.Play "` + name +
`"`, so:
- write it **literally**: `Sound.Play "Pickup"`, never a variable, never `Sound.Play tName`, one space;
- use **only kit names** (a name the kit has gets a sound at once):
  `Blip Bounce Bullet Enemy Explode Hit Hurt Jump Lose Pickup PlayerCrash PlayerLaser Powerup Select
  Shoot Throw Thud Warp Win Zap`
  (PlayerLaser = the player fires; Bullet/Enemy = enemy fires/appears; Shoot = any other gun;
  Explode = something blows up; PlayerCrash = the player dies; Hit = player hits something; Hurt =
  player gets hurt; Pickup = collect; Powerup = upgrade/extra life; Jump; Bounce = ball/wall bounce;
  Thud = landing/heavy contact; Throw; Zap = energy/spell; Warp = level start/teleport; Win = level
  or match won; Lose = game over/match lost; Select = menu choice/toggle; Blip = small UI tick/score).
- aim for **4 to 8 different names** per game (at least 3), each where the event happens once.

## Rules
- Events only: a call happens when something happens (a shot leaves, a hit lands, a pickup is taken,
  the level is won). **Never** in a branch that is true frame after frame (holding a key, sitting on
  the ground, a timer above 0). If an event can fire many times in one frame (ten bullets hit at once),
  play it at most once that frame (a local flag / the frame number).
- Change nothing else: no gameplay, no renames, no reformatting, no music calls (music is handled by
  the engine and AUDIO). Keep the owner's naming: g global, b boolean, t temp, p param.
- Files are LF text, UTF-8. Edit with the Edit tool. **Edit only the games in your group.**
- **No git at all** (no add, commit, checkout, stash): several helpers edit the same repo at once.
  Opus commits after you report.
- Test: copy `~/projects/OXT-BEYOND/tests/t82_game_sounds.txt` to your scratchpad (name it with your
  group letter), change only the line ending `-- GAMES` to your games, and run
  `cd ~/projects/OXT-BEYOND/tests; python3 -I oxt_headless.py --engine both <your copy>`.
  Every game must pass "has 3+ sound names", "only kit names", "compiles"; "plays 600 frames" must
  pass where it passed before your edit (run it once first to know; some games need engine handlers the
  stand-ins lack, write those down). The INFO line shows what played in 600 bot frames.
  Also run any existing test in that folder that names your game (`grep -l <Game> t*.txt`), before and
  after; it must not get worse. Don't edit anything in OXT-BEYOND.

## Report (short)
Per game: the names and the event for each (e.g. `Pickup: coin taken (Coin.Take)`), the test results,
anything odd you saw (a bug, a game that would want a sound the kit lacks: say which, don't invent it).
