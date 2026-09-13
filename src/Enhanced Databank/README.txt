Enhanced Databank v1.0.0
========================

Enhanced Databank unlocks native folder management for custom characters in
Star Wars: Zero Company.

Features
--------
- Create native custom-character folders from the Character Databank.
- Rename and delete player-created folders.
- Move the selected character between Player Created and custom folders.
- Preserve the game's native pool identity, persistence, and empty-folder
  cleanup behavior.
- Use compact, native-styled controls with UMG-drawn Tabler-inspired icons.
- Share the top action row cleanly with Character Share when both mods are
  enabled.

Installation
------------
Install the release ZIP with ZCOM Mod Manager, or place the complete
"Enhanced Databank" folder in:

  SWZeroCompany/Binaries/Win64/ue4ss/Mods/

The package includes enabled.txt. If your UE4SS setup does not honor it, add:

  Enhanced Databank : 1

to ue4ss/Mods/mods.txt.

Use
---
Open Character Databank and select Custom Characters.

- The folder-plus button beside Create New creates a folder.
- The pencil and trash buttons rename or delete custom folders.
- Select a character and use Move beside the normal character actions to pick
  another folder.

Only empty custom folders can be deleted. Player Created is protected. Moving
the final character out of a custom folder may allow the game to remove that
now-empty folder as part of its normal native behavior.

Requirements
------------
- Star Wars: Zero Company
- UE4SS with the delayed game-thread action API
  (ExecuteInGameThreadWithDelay, RetriggerableExecuteInGameThreadWithDelay,
  MakeActionHandle, CancelDelayedAction, IsValidDelayedActionHandle, and
  IsDelayedActionActive)

The Steam builds listed in the package metadata are the tested baseline. Other
game builds and launchers should be treated as unverified.

Troubleshooting
---------------
Enhanced Databank writes additional detail to enhanced_databank.log beside the
installed mod when that path is writable. UE4SS.log remains the primary startup
and crash log.

Support shortcuts:
- Shift+F7: authoritative Databank refresh
- Shift+F8: remove Enhanced Databank UI and restore the stock presentation

Third-party attribution is documented in THIRD_PARTY_NOTICES.txt.
