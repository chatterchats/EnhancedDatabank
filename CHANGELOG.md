# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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

## [1.0.0] - 2026-09-13

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
