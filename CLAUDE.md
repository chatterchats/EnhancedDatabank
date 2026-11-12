# EnhancedDatabank

@docs/agent-rules.md

Read README.md first: what the mod does, its layout and how it's tested.

## Rules for this repo

- The game owns folders and ownership. Never keep a folder database, write saves, or move a
  character between categories (Custom Characters and Astromech each have their own pools).
- The default Player Created pool is protected: never rename or delete it.
- Rebuild the visible folders from pool ownership; don't patch widgets in place.
- Keep the Create Folder control compatible with Character Share's Import in the same row.
- Check UObjects with `IsValid()` before using them; a stale Databank master crashed the game
  (docs/crash-investigation-2026-09-20.md).
