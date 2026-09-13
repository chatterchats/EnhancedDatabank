# Enhanced Databank

[![UE4SS](https://img.shields.io/badge/framework-UE4SS-6f42c1)](https://github.com/UE4SS-RE/RE-UE4SS)

Enhanced Databank is a UE4SS Lua mod for **Star Wars: Zero Company** that
unlocks native custom-character folder management in the Character Databank.

It uses the game's existing character-pool manager and Databank view models.
Folder identity, character ownership, persistence, and native empty-folder
cleanup remain owned by the game; the mod does not maintain a parallel folder
database or rewrite save files.

## Features

- Create native custom-character folders from the Databank.
- Rename player-created folders.
- Delete empty player-created folders while protecting the default Player
  Created pool.
- Move the selected custom character between Player Created and custom folders.
- Rebuild visible custom folders from authoritative native pool ownership.
- Use compact native-styled controls with Tabler-inspired icons drawn entirely
  from UMG primitives.
- Cooperate with Character Share's compact Import action when both mods are
  enabled.

Enhanced Databank currently affects the **Custom Characters** Databank page.
It does not add folders to the Astromech page.

## Requirements

- **Star Wars: Zero Company**
- A working [UE4SS](https://docs.ue4ss.com/dev/installation-guide.html)
  installation for the game with the delayed game-thread action API
  (`ExecuteInGameThreadWithDelay`, `RetriggerableExecuteInGameThreadWithDelay`,
  `MakeActionHandle`, `CancelDelayedAction`, `IsValidDelayedActionHandle`,
  `IsDelayedActionActive`, and `UnregisterHook`)

Hot reload retains both hook IDs and cancels owned actions during teardown.
When available, `ClearAllDelayedActions()` also clears this mod's leftover
actions at startup; set `EnhancedDatabankClearDelayedActionsOnReload = false`
before reloading to disable that optional sweep. Tracked-handle cancellation
still runs. Existing buttons are adopted during Databank reinitialization.
Restart the game once when upgrading from versions that did not retain hook
IDs; those older registrations cannot be recovered by the new registry.

The current metadata identifies Steam as the supported launcher and lists game
builds `25134257` and `24874058` as tested. Later builds may work but should be
treated as unverified until tested.

## Installation

### ZCOM Mod Manager

Install the Enhanced Databank release ZIP normally. The archive retains
`Enhanced Databank` as its top-level mod folder and includes metadata for ZCOM
Mod Manager and Zero Company Mod Command.

### Manual UE4SS installation

1. Install and verify UE4SS for Star Wars: Zero Company.
2. Extract the `Enhanced Databank` folder into:

   ```text
   SWZeroCompany/Binaries/Win64/ue4ss/Mods/
   ```

3. Confirm this entry point exists:

   ```text
   ue4ss/Mods/Enhanced Databank/Scripts/main.lua
   ```

4. If your UE4SS setup does not honor the packaged `enabled.txt`, add:

   ```text
   Enhanced Databank : 1
   ```

   to `ue4ss/Mods/mods.txt`.

## Using Enhanced Databank

Open **Character Databank** and select **Custom Characters**.

- Select the folder-plus action beside **Create New** to create a folder.
- Use the pencil action on a custom folder to rename it.
- Use the trash action to delete an empty custom folder.
- Select a character, choose **Move** beside the normal character actions, and
  select a destination pool.

Only empty custom folders can be deleted. The default Player Created pool is
protected. Moving the final character out of a custom folder may allow the game
to remove the empty folder as part of its native lifecycle.

## Character Share compatibility

Enhanced Databank and Character Share recognize each other's top action row.
When both are installed, **Create New**, compact **Import**, and compact
**Create Folder** occupy one flat row with separate hitboxes and normal native
spacing. The selected-character **Move** and **Share** actions also coexist in
the native detail action row.

## Troubleshooting

Enhanced Databank writes detailed diagnostics to `enhanced_databank.log` beside
the installed mod when that location is writable. `UE4SS.log` remains the
primary startup and crash log.

Support shortcuts:

| Shortcut | Action |
| --- | --- |
| `Shift+F7` | Rebuild folders from authoritative native pool ownership |
| `Shift+F8` | Remove Enhanced Databank UI and restore the stock presentation |

When reporting a reproducible issue, include the game build, UE4SS version,
other Databank mods, reproduction steps, and the relevant logs.

## Repository layout

```text
.
├── .github/workflows/release-nexus.yml
├── CHANGELOG.md
├── README.md
├── scripts/bump_version.py
└── src/Enhanced Databank/
    ├── Assets/
    ├── Scripts/
    ├── README.txt
    ├── THIRD_PARTY_NOTICES.txt
    ├── enabled.txt
    ├── modinfo.json
    └── zcom-mod.json
```

`src/Enhanced Databank` is the distributable mod directory. There is no build
or bundle step.

The reverse-engineering and stability notes used during development are kept in
[`Zero_Company_Databank_Modding_Guide.md`](Zero_Company_Databank_Modding_Guide.md).

## Development

Copy or link `src/Enhanced Databank` into the game's `ue4ss/Mods` directory,
then test changes on a supported game build. A Lua syntax check is useful, but
in-game verification is required because the mod interacts with generated
Blueprint classes and runtime UMG widget trees.

For changes to folders or movement, test at minimum:

- cold entry into the Databank;
- Default to custom, custom to Default, and custom to custom moves;
- moving the final character out of a folder;
- create, rename, and delete persistence after a restart;
- coexistence with Character Share; and
- repeated Databank entry without duplicate controls.

## Releasing

The manual **Release to Nexus Mods** workflow validates metadata, packages the
mod, retains the ZIP as a workflow artifact, and can publish it to Nexus Mods.

1. Add release notes beneath `## [Unreleased]` in
   [`CHANGELOG.md`](CHANGELOG.md).
2. Run the version helper with `patch`, `minor`, or `major`:

   ```bash
   ./scripts/bump_version.py patch
   ```

3. Verify the ZIP in ZCOM Mod Manager and with a clean manual installation.
4. For Nexus publishing, create the Nexus mod page and initial file, then add
   these repository secrets:

   - `NEXUSMODS_API_KEY`
   - `NEXUSMODS_MOD_ID`
   - `NEXUSMODS_FILE_ID`

5. Run the workflow from the repository's **Actions** tab. Disable its
   `publish_to_nexus` input for a package-only validation run.

The workflow packages `src/Enhanced Databank` as
`Enhanced Databank V#.#.#.zip`.

## Attribution

The UMG-drawn action glyphs follow the visual language of
[Tabler Icons](https://tabler.io/icons), licensed under MIT. See the packaged
`THIRD_PARTY_NOTICES.txt` for details.

## License

This repository does not currently include a project license. Unless one is
added, the source remains subject to applicable copyright law. Third-party
attributions remain governed by their respective licenses.
