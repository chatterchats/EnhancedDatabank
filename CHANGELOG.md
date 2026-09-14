# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1]

### Fixed

- Keep newly created characters visible when the Player Created pool was empty.
  Default-row reconciliation now resolves each native row through its unique
  rendered character name instead of assuming the stale typed ViewModel array
  and native widget stack retain identical indices.
- Fail open for unreadable or duplicate row names so reconciliation cannot hide
  a character whose native row identity is ambiguous.
- Force a uniquely resolved authoritative row back to `Visible` when native
  stack-box widget reuse carries over the previous occupant's `Collapsed` state.
  Treat duplicate transient ViewModel wrappers as safe when they share one GUID.

## [1.0.0] - 2026-09-13

### Changed

- Split the entry script into focused modules for action ownership, hook
  registration, logging, pool authority and mutations, folder controls and
  icons, native dialogs, Databank rendering, and lifecycle installation.
- Give each startup a fresh explicit module context, preserving shared state
  and reload cleanup without accumulating top-level Lua locals.
- Test the production module factories and full bootstrap/reload wiring
  directly, including surviving-widget adoption.

### Fixed

- Reconcile the shipping Default pool after refreshes by collapsing only rows
  whose GUID is no longer present in authoritative manager ownership. Deleted
  or moved characters can no longer reappear through a stale Default ViewModel,
  while the stock list is never regenerated, removed, reparented, or decorated.
- Restore visibility only for rows previously hidden by the mod when their GUID
  later becomes authoritative in Default again.

- Preserve the first callback on retriggerable refresh handles and read the
  latest reason when it fires. Paired master/page activation events no longer
  invalidate their only pending folder rebuild.
- Refresh custom folders after native character deletion through both
  DeletePoolCharacter and RemoveCharacterFromPool, without capturing the
  deleted UObject. Nested notifications coalesce into one deferred rebuild.
- Add regression coverage for UE4SS callback retention, deletion notifications,
  deleted-row filtering, and retired-runtime refreshes.

- Added reload teardown with a central hook registry retaining both UE4SS hook
  IDs, cancellation of every owned action (including refresh), and optional
  current-mod delayed-action clearing. Retired callbacks are disabled.
- Rebind debug keys without duplicate registrations, close the previous log,
  retire old popup content on the game thread, and restore existing Move/Create
  Folder controls and icon references during reinitialization.
- Added mocked reload and scheduler regression tests.
- Added an owned, cancellable delayed-action group for lifecycle-hook
  installation and cold-entry catch-up. Pending retries are now queried and
  cancelled when the installer restarts or an activation-owned render wins.
- Added fail-closed `IsValid()` checks for every UObject explicitly captured by
  delayed actions, including widgets, pool ViewModels, character ViewModels,
  and dynamically stored destination buttons. Stale callbacks now stop before
  touching released Unreal objects.
- Migrated all deferred UI and mutation work to UE4SS's owned delayed
  game-thread action system, avoiding the callback-registry race triggered by
  overlapping `ExecuteWithDelay` and `ExecuteInGameThread` work.
- Removed the continuously rescheduled Create Folder hover poll and routed its
  visual state through the existing event-driven CommonUI hover hooks.
- Coalesced refresh scheduling with a retriggerable action handle and reduced
  Move destination repainting to one delayed action per dialog.

## [1.0.0-rc1] - 2026-09-13

### Added

- Native custom-character folder creation, rename, and empty-folder deletion.
- Selected-character movement between Player Created and custom folders.
- Authoritative folder rendering from the game's character-pool manager.
- Native-styled UMG controls with Tabler-inspired folder, edit, delete, and move
  glyphs.
- Cooperative Databank action layouts for use alongside Character Share.
- ZCOM Mod Manager, Zero Company Mod Command, and manual UE4SS packaging
  metadata.
- A manual GitHub Actions workflow for release packaging and optional Nexus Mods
  publishing.
