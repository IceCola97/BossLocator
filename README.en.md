# Boss Locator

[English](README.en.md) | [简体中文](README.md)

> This project was created with AI assistance. See [AI-assisted development](#ai-assisted-development).

This is a Noita mod. Copy this directory to `mods/boss_locator` in the Noita
installation (the Lua paths use that folder name). It tracks the boss entities
listed in `files/config.lua` while they are loaded, stores the last observed
position in the current world save, and draws a screen marker (or an edge
arrow) for the current parallel world.

Enable or disable every entry under the mod settings page. The settings page
also reports whether the current world's boss is dead, absent from that world,
currently tracked, or only known from an earlier observation.

The settings page also offers a **"Scan save to sync real positions"** button:
it reads the entity chunks of the current save and records the position of
every boss it finds, so a save that was already being played before this mod
was enabled shows all boss positions right away. See
[Old save compatibility](#old-save-compatibility-scanning-a-save).

`mod.xml` declares `request_no_api_restrictions="1"`, because reading save
files needs Lua's `io.*` / `os.*`. Noita's own example mod.xml states the
requirement: "If a mod requires access to the full lua api e.g. os.* io.* it has
to request acesss via 'request_no_api_restrictions=\"1\"'." The scan only ever
**reads** saves and never writes to one. Setting the value back to `"0"` only
disables the scan (the button then reports the missing permission) and leaves
the rest of the mod working.

## Persistence model

Runtime observations are written with `GlobalsSetValue`, which is part of the
current world save. Keys are namespaced by the New Game+ count, parallel-world
index, and boss id. The engine's `GetParallelWorldPosition` result is used when
available, with the normal/NG+ world widths as a compatibility fallback. The
user-facing checkboxes are ordinary runtime mod settings and are kept separate
from save data.

Tracked entities receive a small `script_death` observer, while the scanner
also checks HP and applicable vanilla main-world death flags. An entity that
simply disappears is treated as a streamed chunk unload. Its cached position
is kept, so returning to the area can replace it with the loaded entity. A
confirmed death is sticky for that world and hides the marker. This is why the
mod never falls back to a default coordinate after an observed entity is
unloaded.

Repeatable types are handled separately. The two Parallel World shadow Bosses
and Sauvojen tuntija (which Monstrous Powder can create) record the most recent
defeated instance without permanently closing that Boss type. A later instance
can therefore become `alive`, and every currently loaded instance receives its
own marker. Epäalkemisti is excluded from this rule: destroying its Death Orb
is a final death for that world.

Epäalkemisti (the Non-alchemist) is represented as a resurrection-aware entry:
its 220-frame Death Orb phase is stored as `revive_pending`, not `dead`. The
orb being unloaded keeps that pending state and position; seeing the new living
entity changes it back to `alive`, while observing the orb at zero HP records a
confirmed death. The mod does not create its own timer. Vanilla's orb uses a
LuaComponent scheduled every 220 frames and respawns the Boss at the orb's
current transform. If the orb is streamed out, its entity data and transform
are saved with the chunk. On a later load, the vanilla component is authoritative
about whether the 220-frame callback resumes or fires immediately; either way,
the respawn location is the saved orb position, never a made-up default.

## Boss definitions

`files/config.lua` contains the boss list, filename/tag matchers, world policy,
resurrection metadata, and optional default coordinates. Vanilla entity
filenames and tags can change between game versions or be altered by another
mod, so the matchers are kept in one place. Filename/name matching is primary;
tags are used as extra checks where two entities share a filename. Default
coordinates are intentionally empty until verified against a specific game
data version; an unobserved boss is not shown at an invented location.

One entry was corrected against the actual game data while adding the scan:
Alkemistin Varjo (the Alchemist's Shadow) used to require the tag
`boss_parallel`, which does not exist in the vanilla entity data, so the entry
could never match - neither at runtime nor in a save scan. It is now identified
by the parallel-world entity itself,
`data/entities/animals/parallel/alchemist/parallel_alchemist.xml` (name
`$animal_parallel_alchemist`). Change that entry in `files/config.lua` if your
game version differs.

Kolmisilmän Koipi now requires the `boss` tag as well: the vanilla data also
contains `boss_limbs_physics.xml` (its physics body) and a copy below
`ending_placeholder/` under the same entity name, which used to be mistaken for
the same Boss.

No default coordinate is filled in and no save is ever modified. The scan
described above additionally reads the save the game is using, read only;
apart from that, state begins accumulating when this mod is enabled and the
relevant chunks are observed.

## Old save compatibility: scanning a save

The mod originally accumulated state only from the chunks it observed after
being enabled, so a save that was already being played was unknown to it. The
**"Scan save to sync real positions"** button in the settings page fixes that:
it reads every boss position the save already contains and records them.

### How to use it

1. Start a game (load a save). Outside a run the button is drawn disabled and
   says that a run is required.
2. Open Mod settings → Boss Locator and press "Scan save to sync real
   positions".
3. The result appears next to the button (slot, chunk count, how many boss
   positions were updated, failures) and as an in-game notification; the
   tooltip on the button carries the full report (save directory, entity
   count, matched boss names).

"Scan once when a save is loaded" can be enabled (off by default): it repeats
the scan about two seconds after every world load, which keeps a long running
old save up to date.

### What the scan does

1. **Locates the save directory** (`files/save_locator.lua`). Every path is
   derived at runtime; no drive letter or user name is hard coded:
   - candidate roots = the running game's **working directory** (relative
     paths, so they address the installation that is actually running) plus the
     user data directories the operating system reports (Windows
     `%USERPROFILE%\AppData\LocalLow\Nolla_Games_Noita`, Linux
     `$XDG_DATA_HOME` or `$HOME/.local/share/Nolla_Games_Noita`, macOS
     `$HOME/Library/Application Support/Nolla_Games_Noita`).
   - the slot (`save00`, `save01`, ...) is discovered as well: the slot the
     **game itself reports** (the run's statistic file path inside the active
     save, or a slot kept in the session numbers) wins, otherwise the **most
     recently written slot** does (the game keeps writing chunks into the slot
     it is playing), and `save00` is the default when nothing indicates
     otherwise. Multi-save mods that move a run to `save01` are therefore
     handled. The "Save slot to scan" setting overrides the detection; leaving
     it empty means automatic.
2. **Enumerates the entity chunks** (`files/save_fs.lua`). Cross-platform:
   Windows uses LuaJIT's `ffi` with `FindFirstFileA`, Linux and macOS use
   `io.popen` with `ls`. If neither is available the chunk names are probed
   with `io.open` instead (`entities_<index>.bin`, where the index is
   `chunk_x + chunk_y * 2000` - a relation that was verified against a real
   save), so the scan never depends on directory listing.
3. **Parses the entities** (`saves/save_scanner.lua` + `saves/entity_parser.lua`).
   Chunks are fastlz compressed; the mod ships the pure Lua
   `fastlz/fastlz.lua`, so no DLL is needed. The parser reads base data only
   (name, entity file path, tags, transform) and skips component payloads.
4. **Matches the bosses and records the positions.** Matching uses the same
   `files/config.lua` definitions as the runtime, but tightened for stored
   records: the entity file name stem has to be identical, or the entity name
   has to be identical, and tags are compared as whole tokens. A save also
   stores the boss' helper entities (`boss_centipede_minion.xml`,
   `orb_green_boss_dragon.xml`, ...), which a substring search would mistake
   for the boss itself.
5. Positions are written with `GlobalsSetValue` into the same records the
   runtime tracker uses. Records that are `dead`/`defeated` are skipped (a
   living boss cannot be told from a corpse in the stored base data, so a
   confirmed death is never "revived"), the other records become `unloaded`
   (position known, load state unknown), and the Non-alchemist's death orb
   becomes `revive_pending`. A boss that is absent from the save is left
   untouched.

The scan runs **one slice per frame** (about 12 chunks or 96 KB by default) and
shows "scanning x/y chunks" next to the button, so even a very large save never
freezes the game; the automatic scan advances the same way and does not slow a
world load down.

### Limits

- The positions are the ones written at the **last save**, not live positions;
  the runtime tracker refreshes them afterwards.
- Read only: no save file is ever modified, only this mod's `Globals` records
  are written.
- Stored records carry no component data, so health is unknown and a boss
  entity cannot be classified as alive or as a corpse - which is why a
  confirmed death stays sticky.

## Verification

`tests/` contains Lua 5.1 tests for persistence, parallel-world selection,
death callbacks, unload handling, and the resurrection transition race. The
small C# runner loads the `lua51.dll` shipped with Noita so the tests use the
same Lua generation as the game.

The save scanning tests run fully offline and write nothing:

- `tests/save_fs_test.lua`: the real file system layer (platform detection,
  path joining, directory listing, modification times, chunk index probing),
  using the sample save shipped with the repository as a read-only fixture.
- `tests/save_locator_test.lua`: an in memory file system describes several
  roots and slots and verifies "newest write wins", "the slot the game reports
  wins", "an override wins", and "a missing directory listing falls back to
  chunk index probing".
- `tests/save_sync_test.lua`: the scan end to end. It builds saves in the real
  binary format (big endian entity body, little endian size header, fastlz
  compression) and asserts which entities match and which do not, the
  parallel-world index, death stickiness, the cross context cache
  invalidation, and the disabled-button rules for the main menu and for a
  restricted Lua state.
- `tests/lua_bit_test.lua`: the pure Lua bit fallback agrees with LuaJIT's
  native `bit`, and both decompress the same fastlz stream to the same bytes.
- `tests/config_match_test.lua`: all 21 Boss definitions are checked against the
  name/tag/path values of the real vanilla entities (plus 16 look-alikes that
  share a name or a path element), so every definition matches its own entity
  and only its own, and no helper entity is mistaken for a Boss.

Run the whole suite from the repository root (`tests/Lua51Runner.csproj` loads
the `saves/lua51.dll` that ships with Noita, so a .NET SDK is required):

```powershell
dotnet run --project tests/Lua51Runner.csproj -- saves tests/syntax_test.lua tests/lua_bit_test.lua `
  tests/config_match_test.lua tests/state_test.lua tests/world_test.lua tests/locator_test.lua `
  tests/death_hook_test.lua tests/save_scanner_test.lua tests/save_fs_test.lua `
  tests/save_locator_test.lua tests/save_sync_test.lua
```

## AI-assisted development

This project was built with AI assistance. The AI helped
write the Lua mod code, the test suite, and the documentation. All engine
behavior assumptions are backed by the tests in `tests/` and by in-game
verification; anything that has not been verified against a specific game data
version is deliberately left empty rather than guessed.
