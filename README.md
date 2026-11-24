# LIB_AUDIO

The hidden **AUDIO** stack: a pool of ready-made players, a card of words per game (sound name ->
file), the files given to players **one per tick**, so nothing freezes. The plan, with the owner's
answers: [PLAN.md](PLAN.md).

| File | What it is |
|---|---|
| `livecode/AUDIO.livecode` | the saved stack: card "Kit" with group "Pool" (100 hidden players), background group "View" (fields Title, Words). 5 KB. Made by `Audio.Build` |
| `livecode/lib_audio.livecodescript` | `Audio.*`: Open, Refresh, Select, Fill, Play, Music, Close ... (header lists them) |
| `tests/t79_lib_audio.txt` | 25 checks, headless (OXT-Beyond + 9.6.3): `cd OXT-BEYOND/tests; python3 -I oxt_headless.py --engine both t79_lib_audio.txt` (its copy there is the one run) |

Sounds come from the Data folder: `Sounds/<Category>/`, a game's own `Sounds/<Game>/<Category>/`,
`Sounds/Music/`, the chosen words in `Sounds/Games/<Game>.txt`.

Measured on Windows (OXT-Beyond, 23 Nov 2026): open 0.5 s, 62 game cards 0.67 s, choosing Canyon
returns in 6 ms, its 27 files fill in 1.9 s one per tick, Hunter after it reads no file again.

Traps found:
- The pool stays on card 1 only, and AUDIO stays on card 1 while hidden: every card that shows 100
  players sets them all up again on Windows (about 0.4 s a card).
- OXT-Beyond keeps the first copy of a library: `start using` does not read a changed file again.
  `stop using` + `delete stack "lib_audio"` first.

## Licence

GPL-3.0 (see `LICENSE`), because the xTalk work here is built on the GPL-licensed LiveCode Community 9 engine. Copyright (c) 2026 xAction.

The Python files (`.py`) and other material that is not xTalk are also offered under the MIT licence, Copyright (c) 2026 xAction: you may use them under either licence.
