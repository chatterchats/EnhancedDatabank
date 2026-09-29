# Empty Default action recovery

Reproduction: move every character from Default into custom folders, restart the
game, then select a custom-folder character. Default is absent and the whole
character action row is missing. Creating a new Default character restores it.
This reproduction was confirmed by the user on 2026-09-29.

The local game type dump exposes `CheckForPool`, `isPoolNotEmpty`, `ControlButtons`,
and the page-local `Selected Character Button`. It provides signatures, not the
Blueprint implementation. The Default-only gate is therefore the working cause
inferred from the reproduction, not a decompiled Blueprint finding.

`page_actions.lua` corrects that gate only while Default is empty and authoritative
custom-folder characters exist. It verifies that the page's selection is in a
currently rendered folder and its typed row GUID is still manager-owned before
showing the shared controls. Individual native buttons and their handlers remain
unchanged. No characters or folders are created, and no save data is modified.

Reconciliation runs after rendering and after the page's native pool check and
selected-button field notification. Hooks are installed only once the page is
resident and are owned by the existing reload-safe runtime. The UE4SS RegisterHook
documentation specifies that the second argument is a post callback for `/Game`
Blueprint functions. A populated Default pool retains native behavior.

## Validation

`luajit tests/page_actions_test.lua "src/Enhanced Databank/Scripts"` covers both
categories, cold entry, selection, repeated native checks, unrelated pages,
detached/deleted rows, cleared selection, last deletion, populated Default,
unavailable authority, invalid pages, and hook deduplication. Existing Lua tests
also pass. These mocks do not prove native Blueprint event ordering or layout.

In-game confirmation remains required:

1. Empty Default by moving its characters into a custom folder, then restart.
2. Select a folder character. Verify Edit, Delete, Activate/Deactivate, Move, and
   Share (when Character Share is installed) appear and operate normally.
3. Change selection, switch tabs, and close/reopen the Databank. Repeat with
   Astromechs, including starting on that tab.
4. Move a character back to Default; verify native actions still work. Empty
   Default again and verify custom-folder actions remain usable.
5. With a disposable test character, remove the last character and verify no
   actionable stale selection remains. Verify creating a character still works.

The test ZIP also includes the pre-existing, uncommitted hover-lifecycle fix in
this workspace; that change is not part of the empty-Default correction.
