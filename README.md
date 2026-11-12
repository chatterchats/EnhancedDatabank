# Enhanced Databank

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Enhanced%20Databank-d98f40)](https://www.nexusmods.com/starwarszerocompany/mods/209)
[![UE4SS](https://img.shields.io/badge/framework-UE4SS-6f42c1)](https://github.com/UE4SS-RE/RE-UE4SS)
[![License: MIT](https://img.shields.io/badge/license-MIT-2f7d4f)](LICENSE)

A UE4SS Lua mod for **Star Wars: Zero Company** that unlocks the game's own custom-character
folders in the Character Databank: create, rename and delete folders, and move characters between
them, on both the Custom Characters and Astromech pages. Folder identity, ownership, persistence
and cleanup stay with the game's character-pool manager; the mod keeps no database of its own and
never rewrites saves. Players should download the release ZIP from
[Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/209) or the
[GitHub releases](https://github.com/chatterchats/EnhancedDatabank/releases); the mod page text is
in [`docs/nexus/`](docs/nexus/) and the in-ZIP player guide is `src/Enhanced Databank/README.txt`.

## Commands

`make help` lists everything. The usual loop: edit, `make test`, `make install`, restart the game.

| Target | Does |
| --- | --- |
| `make test` | the LuaJIT tests (mocked engine), no game needed; `T=lifecycle_test` for one |
| `make install` / `make uninstall` | link `src/Enhanced Databank` into the main install, or remove the link |
| `make package` | `dist/EnhancedDatabank-X.Y.Z.zip`, with `Enhanced Databank/` at its root |
| `make bump V=X.Y.Z` | set the version everywhere, date the changelog |
| `make release` | check, test, tag, push; CI publishes to GitHub and Nexus (mod 209) |
| `make debug-logs` | copy `UE4SS.log`, the mod log and the latest crash reports into `dev/debug/` (`CRASHES=n`, default 3) |
| `make check` / `make sync` | drift from the standard / fetch the latest shared files |

## Layout

The standard layout (see `../ModTemplate/STANDARD.md`). Specific to this repo:

- `src/Enhanced Databank/Scripts/`: `main.lua` and `startup.lua` boot the modules; `pool_*.lua`
  read and change pool ownership, `folder_ui.lua`, `databank_ui.lua` and `popup.lua` draw the
  controls. [docs/architecture.md](docs/architecture.md) has the module map.
- `src/Enhanced Databank/THIRD_PARTY_NOTICES.txt`: the Tabler Icons attribution (the glyphs are
  drawn from UMG primitives in Tabler's style; `Assets/folder-plus.*` is kept for reference).
- `docs/`: architecture, [lifecycle validation](docs/lifecycle-validation.md), the 2026-09-20
  crash investigation, the empty-default fix, the early
  [Databank modding guide](docs/databank-modding-guide.md) (some recipes superseded) and
  practical UE4SS UI notes.
- `dev/debug/`: gitignored output of `make debug-logs`.

## How it works

The mod drives the game's own character-pool manager and Databank view models: a folder is a
native pool, a move changes the character's native ownership, and the visible folders are
rebuilt from that ownership. Controls are compact native-styled buttons; Create Folder shares the
Create New row with [Character Share](https://www.nexusmods.com/starwarszerocompany/mods/176)'s
Import, and Move shares the selected-character row with its Share.

**Hot reload.** The mod keeps its hook IDs and cancels its own delayed actions on teardown;
`ClearAllDelayedActions()` clears leftovers at startup unless
`EnhancedDatabankClearDelayedActionsOnReload = false`. Existing buttons are adopted when the
Databank reinitializes.

## Testing in game

Restart the game after `make install`. The mod logs to `enhanced_databank.log` beside the
installed mod and to `UE4SS.log`. `Shift+F7` rebuilds the folders from pool ownership; `Shift+F8`
removes the mod's UI and restores the stock Databank.

For folder or move changes, test at least:

- cold entry into both Databank categories and switching between them;
- Default to custom, custom to Default, and custom to custom moves;
- moving the last character out of a folder;
- create, rename and delete persistence after a restart, in both categories;
- switching categories while a folder dialog or deferred move is pending;
- coexistence with Character Share; and
- repeated Databank entry without duplicate controls.

## License

[MIT](LICENSE), copyright 2026 Chatter Chats. The Tabler Icons attribution is in
`src/Enhanced Databank/THIRD_PARTY_NOTICES.txt`.
