# Enhanced Databank

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Enhanced%20Databank-d98f40)](https://www.nexusmods.com/starwarszerocompany/mods/209)
[![UE4SS](https://img.shields.io/badge/framework-UE4SS-6f42c1)](https://github.com/UE4SS-RE/RE-UE4SS)

Enhanced Databank is a UE4SS Lua mod for **Star Wars: Zero Company** that
unlocks native custom-character folder management in the Character Databank.

It uses the game's own character-pool manager and Databank view models.
Folder identity, character ownership, persistence and empty-folder cleanup
stay with the game; the mod keeps no folder database of its own and never
rewrites save files.

## Features

- Create native custom-character folders from the Databank.
- Rename player-created folders.
- Delete empty player-created folders; the default Player Created pool is
  protected.
- Move the selected character between Player Created and custom folders.
- Rebuild the visible folders from the game's own pool ownership.
- Compact, native-styled controls with Tabler-inspired icons drawn entirely
  from UMG primitives.
- Shares its action row with Character Share's compact **Import** button when
  both mods are enabled.

Both the **Custom Characters** and **Astromech** pages are supported. Each has
its own folders and Player Created pool; characters move only between folders
of the same category.

## Using Enhanced Databank

Open the **Character Databank** and select **Custom Characters** or
**Astromech**.

- The folder-plus action beside **Create New** creates a folder.
- The pencil action on a custom folder renames it.
- The trash action deletes an empty custom folder.
- To move a character, select it, choose **Move** beside the normal character
  actions, and pick a destination.

Only empty custom folders can be deleted. Moving the last character out of a
custom folder may let the game remove the empty folder as part of its normal
lifecycle.

## Requirements

- **Star Wars: Zero Company**
- **UE4SS** for Zero Company, with the delayed game-thread action API
  (`ExecuteInGameThreadWithDelay`, `RetriggerableExecuteInGameThreadWithDelay`,
  `MakeActionHandle`, `CancelDelayedAction`, `IsValidDelayedActionHandle`,
  `IsDelayedActionActive` and `UnregisterHook`)

| Steam build | Status |
| --- | --- |
| [25134257](https://steamdb.info/app/2075800/patchnotes/) | Tested |
| 24874058 | Tested |

Steam is the tested launcher. Later builds may work but are unverified until
tested.

## Installation

Download the release ZIP from
[Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/209), not
GitHub's source-code archive. The ZIP keeps `Enhanced Databank` as its
top-level folder and includes metadata for both mod managers below.

### With a mod manager

- **[Zero Mod Manager](https://github.com/stellamarislabs/zero-mod-manager)**
  (formerly ZCOM Mod Manager): open **Install**, drop in the ZIP, then
  confirm Enhanced Databank is enabled under **Mods**.
- **[Zero Company Mod Command](https://github.com/EnvianMods/ZeroCompanyModCommand)**:
  drag the ZIP into the **Hangar Bay** and check that it's enabled.

### By hand

1. Install UE4SS for Star Wars: Zero Company.
2. Extract the `Enhanced Databank` folder into
   `SWZeroCompany/Binaries/Win64/ue4ss/Mods/`.
3. Check that `ue4ss/Mods/Enhanced Databank/Scripts/main.lua` exists. Install
   the whole `Scripts` folder; `main.lua` loads the other modules.
4. If your UE4SS setup ignores the packaged `enabled.txt`, add
   `Enhanced Databank : 1` to `ue4ss/Mods/mods.txt`.

### Updating and uninstalling

Close the game, then install the new ZIP the same way (by hand, copy it over
the old folder). To uninstall, disable or remove it in your mod manager, or
delete the `Enhanced Databank` folder.

## Compatibility

- **[Character Share](https://www.nexusmods.com/starwarszerocompany/mods/176):**
  designed to work together. **Create New**, compact **Import** and compact
  **Create Folder** share one flat row with separate hitboxes and native
  spacing; **Move** and **Share** share the selected-character row.

## Troubleshooting

Enhanced Databank writes details to `enhanced_databank.log` beside the
installed mod (when that folder is writable). `UE4SS.log` remains the main
startup and crash log.

| Shortcut | Action |
| --- | --- |
| `Shift+F7` | Rebuild folders from the game's own pool ownership |
| `Shift+F8` | Remove Enhanced Databank's UI and restore the stock Databank |

### Reporting a bug

Open an [issue](https://github.com/chatterchats/EnhancedDatabank/issues) with:

- the game build and UE4SS version;
- other Databank mods installed;
- the steps to reproduce it; and
- `enhanced_databank.log` and `UE4SS.log`.

`scripts/collect_debug_logs.sh` gathers the logs and the latest crash reports
(`--crashes COUNT`, 3 by default).

## Repository layout

```text
.
├── .github/workflows/release-nexus.yml   # manual Nexus release
├── CHANGELOG.md
├── README.md
├── Zero_Company_Databank_Modding_Guide.md  # historical Databank investigation
├── docs/
│   ├── architecture.md                   # modules, reload rules, local checks
│   ├── lifecycle-validation.md           # entry-driven initialization
│   ├── practical-ue4ss-ui-modding-notes.md
│   ├── nexus/description.bbcode          # mod page description
│   └── ...                               # investigations
├── media/                                # banner and main image
├── scripts/
│   ├── bump_version.py                   # version bump + changelog promotion
│   ├── collect_debug_logs.sh
│   └── nexus_changelog.py                # a release's notes as Nexus text
├── src/Enhanced Databank/                # the distributable mod folder
│   ├── Assets/
│   ├── Scripts/
│   ├── README.txt                        # player readme
│   ├── THIRD_PARTY_NOTICES.txt
│   ├── enabled.txt
│   ├── modinfo.json                      # Zero Company Mod Command
│   └── zcom-mod.json                     # Zero Mod Manager
└── tests/                                # LuaJIT and Python tests
```

`src/Enhanced Databank` is the distributable folder; there is no build or
bundle step. [Practical UE4SS UI Modding Notes](docs/practical-ue4ss-ui-modding-notes.md)
collects the UI findings shared with Character Share, Colors+ and related
work; the [Databank investigation](Zero_Company_Databank_Modding_Guide.md)
keeps the detailed experiments and stability history.

## Development

1. Clone the repository and copy or link `src/Enhanced Databank` into the
   game's `ue4ss/Mods` folder.
2. Run the tests from the repository root:

   ```bash
   for t in tests/*_test.lua; do luajit "$t" "src/Enhanced Databank/Scripts" || break; done
   for t in tests/*_test.py; do python3 "$t" || break; done
   ```

3. Test in game on a supported build: the mod works on generated Blueprint
   classes and live UMG widget trees that the tests only fake.

See [Script architecture](docs/architecture.md) for module responsibilities
and [Lifecycle validation](docs/lifecycle-validation.md) for entry-driven
initialization and its in-game status. For folder or move changes, test at
least:

- cold entry into both Databank categories and switching between them;
- Default to custom, custom to Default, and custom to custom moves;
- moving the last character out of a folder;
- create, rename and delete persistence after a restart, in both categories;
- switching categories while a folder dialog or deferred move is pending;
- coexistence with Character Share; and
- repeated Databank entry without duplicate controls.

**Hot reload.** The mod keeps its hook IDs and cancels its own delayed
actions on teardown. When available, `ClearAllDelayedActions()` also clears
leftovers at startup; set `EnhancedDatabankClearDelayedActionsOnReload = false`
before reloading to skip that sweep. Existing buttons are adopted when the
Databank reinitializes. Restart the game once when upgrading from versions
that didn't keep hook IDs.

## Releasing

The manually run **Release to Nexus Mods** workflow publishes a release; build
a local ZIP for package-only checks.

1. Add release notes under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
2. Bump the version with `patch`, `minor` or `major`:

   ```bash
   ./scripts/bump_version.py patch
   ```

3. Run the tests. Package `src/Enhanced Databank`, keeping the top-level
   `Enhanced Databank` folder, into `dist/Enhanced Databank V#.#.#.zip`, and
   check it with a mod manager and a clean manual install.
4. Run **Release to Nexus Mods** from the **Actions** tab. It needs the
   `NEXUSMODS_API_KEY` repository secret.

The workflow:

- requires `modinfo.json` and `zcom-mod.json` to hold the same `#.#.#`
  version, matching `local VERSION` in `main.lua`;
- reads that version's notes from `CHANGELOG.md`;
- packages `src/Enhanced Databank` as `Enhanced Databank V#.#.#.zip`; and
- uploads it to Nexus as `Enhanced Databank v#.#.#.zip`, finding the mod and
  its single active file through the API (exactly one active file is
  required).

## Contributing

Bug reports and focused pull requests are welcome through
[Issues](https://github.com/chatterchats/EnhancedDatabank/issues) and
[Pull Requests](https://github.com/chatterchats/EnhancedDatabank/pulls). Keep
folder identity, ownership and persistence with the game's native systems.

## Support

- Downloads: [Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/209)
- Changes: [`CHANGELOG.md`](CHANGELOG.md)
- Bugs and requests: [GitHub Issues](https://github.com/chatterchats/EnhancedDatabank/issues)

## Attribution

The UMG-drawn action glyphs follow the visual language of
[Tabler Icons](https://tabler.io/icons), licensed under MIT. See the packaged
`THIRD_PARTY_NOTICES.txt` for details.

## License

This repository does not currently include a project license. Unless one is
added, the source remains subject to applicable copyright law. Third-party
attributions remain governed by their respective licenses.
