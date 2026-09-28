# Boss Locator

This is a Safe API Noita mod. Copy this directory to `mods/boss_locator` in the
Noita installation (the Lua paths use that folder name). It tracks the boss
entities listed in `files/config.lua` while they are loaded, stores the last
observed position in the current world save, and draws a screen marker (or an
edge arrow) for the current parallel world.

Enable or disable every entry under the mod settings page. The settings page
also reports whether the current world's boss is dead, absent from that world,
currently tracked, or only known from an earlier observation.

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

No unsafe file permission is requested. Existing saves are not scanned from
disk; state begins accumulating when this mod is enabled and the relevant
chunks are observed.

## Verification

`tests/` contains Lua 5.1 tests for persistence, parallel-world selection,
death callbacks, unload handling, and the resurrection transition race. The
small C# runner loads the `lua51.dll` shipped with Noita so the tests use the
same Lua generation as the game.
