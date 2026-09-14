# STAR WARS Zero Company — Character Databank Modding Guide

> **Status:** empirical reverse-engineering notes supporting **Enhanced Databank v1.0.0**. Historical `v9`–`v13` labels below refer only to internal pre-release experiments, not public releases.  
> **Observed game build:** `++ProjectBruno+Stable-CL-196985`  
> **Observed UE4SS build:** `v3.0.1 Beta #0`  
> **Primary scope:** the humanoid **Character Databank → Custom Characters** page, including native custom folders, Create/Rename/Delete Folder, and Move/Transfer Character UI.

This document is intended as a practical guide for modders working on Zero Company's Character Databank. It records the useful objects and native functions discovered so far, the architecture that has proven comparatively stable, and—most importantly—the approaches that have caused native UE4SS crashes.

The central lesson is simple:

> **Let the game own Databank data and shipping widgets. Use native APIs for mutations, authoritative game state for reconciliation, and the smallest possible UI decoration on top.**

---

## 1. What We Are Trying to Add

The current Enhanced Databank work is targeting four related capabilities:

1. **Create Folder**
   - Add a compact control beside the shipping `CREATE NEW` row.
   - Prompt for a name using native-style popup UI.
   - Create a real game-owned custom character pool.

2. **Rename Folder**
   - Add an edit action to player-created folder headers.
   - Validate the new name through the game's Databank ViewModel.
   - Rename the native pool rather than maintaining a mod-side alias.

3. **Delete Folder**
   - Add a delete action to player-created folder headers.
   - Protect the default/Player Created pool.
   - Require a custom folder to be empty before deletion.

4. **Move / Transfer Character**
   - Add a compact per-character transfer affordance.
   - Let the player select another custom folder or the default Player Created pool.
   - Move the character through the native `BitReactorCharacterPoolManager`.
   - Reconcile the UI from authoritative game state afterward.

The goal is for all of this to behave as though Zero Company itself had shipped folder management.

---

## 2. The Architecture That Has Worked Best

Treat the feature as four layers:

```text
BitReactorCharacterPoolManager
        │
        │ authoritative ownership / GUID membership
        ▼
BrunoCharacterDatabankViewModel + BrunoCharacterPoolViewModel
        │
        │ native create / rename / delete + UI-facing VMs
        ▼
Shipping Character Databank widgets
        │
        │ preserve stock default pool; create only required custom widgets
        ▼
Minimal mod-owned decorations
        └─ folder actions / transfer hit-zones / popup routing
```

The mod should **not** become another Databank database.

There should be:

- no sidecar folder ownership database;
- no hand-maintained copy of character-to-folder membership;
- no direct `.sav` editing for folder management;
- no persistent mod-side pool IDs when the game already owns those identities.

Instead, every render or reconciliation pass should ask the native manager what is true *now*.

---

## 3. Native Objects and Widgets Discovered

### 3.1 Character pool manager — authoritative state

The most important runtime object is:

```text
BitReactorCharacterPoolManager
```

Its `CharacterPools` collection has been the most reliable source for actual pool ownership.

Useful fields observed on pool data include:

```text
CharacterPoolName
CharacterPoolType
Characters
```

`Characters` is a map keyed by character GUID.

The current implementation normalizes this into an authoritative structure similar to:

```lua
state = {
    default_custom = {
        name = "...",
        pool_type = 4,
        guids = { [guid] = true },
        guid_order = { ... },
        count = 24,
    },
    custom_by_name = {
        ["Folder Name"] = { ... },
    },
    custom_order = { ... },
    manager = manager,
}
```

### 3.2 Pool type values observed

The implementation currently recognizes:

| Value | Pool type |
|---:|---|
| `0` | `Default_HawksCharacters` |
| `1` | `PlayerCreated_HawksCharacters` |
| `2` | `Default_AstromechCharacters` |
| `3` | `PlayerCreated_AstromechCharacters` |
| `4` | `Default_CustomCharacters` |
| `5` | `PlayerCreated_CustomCharacters` |

The Enhanced Databank implementation discussed here currently filters to types **4 and 5**.

Do not assume the humanoid implementation can simply be enabled for Astromechs or other Databank categories without separate validation.

---

## 4. Important Databank ViewModels

### `BrunoCharacterDatabankViewModel`

This is the useful high-level mutation surface for folder lifecycle operations.

Native functions currently used successfully include:

```text
IsNewPoolNameAvailable(...)
CreatePool(...)
RenamePool(...)
DeletePool(...)
```

The current implementation uses:

```lua
vm:IsNewPoolNameAvailable(FText(name))
vm:CreatePool(FText(name), 5)
vm:RenamePool(pool_vm, FText(new_name))
vm:DeletePool(pool_vm)
```

where `5` is `PlayerCreated_CustomCharacters` in the observed build.

### `BrunoCharacterPoolViewModel`

Useful observed properties/methods include:

```text
PoolName
PoolType
PoolCharacterViewModels
GetSaveFileNameForPool()
```

A pool ViewModel is useful for rendering, native folder UI, and native filename tooltip information.

It should **not** be treated as stronger authority than `BitReactorCharacterPoolManager` for character ownership.

---

## 5. Important Widget Paths

The following generated Blueprint events are useful lifecycle landmarks in the observed build:

```text
/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/
    WBP_CharacterBank_Master.WBP_CharacterBank_Master_C:BP_OnActivated

/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/
    WBP_CharacterBank_Page_CharacterList.WBP_CharacterBank_Page_CharacterList_C:BP_OnActivated

/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/
    WBP_CharacterBank_CreatedCharacterItem.WBP_CharacterBank_CreatedCharacterItem_C:BP_OnClicked

/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/
    WBP_CharacterBank_CreatedCharacterFolder.WBP_CharacterBank_CreatedCharacterFolder_C:BP_OnClicked
```

The current implementation also uses this native CommonUI fallback:

```text
/Script/CommonUI.CommonActivatableWidget:ActivateWidget
```

The Character List page exposes a shipping default pool widget through:

```text
CharacterPool
```

and the observed character stack inside a pool widget is:

```text
BitReactorStackBox_25
```

Treat generated field names such as `BitReactorStackBox_25` as **build-specific implementation details**. They are useful today, but should be isolated behind helper functions so a game update requires changing as little code as possible.

---

## 6. Lifecycle: Cold Load Is the Dangerous Case

A Databank page UObject can exist before all of its Blueprint classes, ViewModels, stock rows, and custom pool ViewModels are actually ready.

That means this pattern is unsafe:

```text
mod loads
→ find page object
→ immediately mutate/rebuild it
```

The current safer approach is:

1. Attempt to install lifecycle hooks.
2. If a generated Blueprint function is not loaded yet, defer and retry.
3. Observe `BP_OnActivated` when available.
4. Also keep `CommonActivatableWidget:ActivateWidget` as a native fallback.
5. Before the first catch-up render, verify that:
   - the humanoid page is live;
   - the shipping `CharacterPool` exists;
   - `BitReactorStackBox_25` exists;
   - stock rows have actually been created;
   - authoritative custom pools have matching discoverable pool ViewModels.
6. Only then schedule reconciliation.

A cold-load-safe hook installer is more important than shaving a few hundred milliseconds off initial decoration.

---

## 7. Authoritative Reconciliation Pattern

The preferred render model is not “remember what the mod did last time.”

It is:

```text
native mutation or Databank activation
        ↓
short delayed refresh
        ↓
read CharacterPoolManager authority
        ↓
resolve the live Databank page + pool ViewModels
        ↓
reconcile mod-created custom folder widgets
        ↓
decorate existing rows
```

Refreshes should be **coalesced** if another render is already running.

Do not let a late lifecycle hook, pool mutation, and page activation independently launch overlapping native UI rebuilds.

---

## 8. The Shipping Default Pool Is Special

This has been the most important crash-safety discovery.

### Do not regenerate the shipping Default Custom pool yourself

An earlier implementation manually invoked the generated Blueprint field-notify handler used to populate `PoolCharacterViewModels`:

```text
BndEvt__WBP_CharacterBank_CreatedCharactersPoolItem_
BrunoCharacterPoolViewModel_MDVMNode_ViewModelFieldNotify_1_
PoolCharacterViewModels(...)
```

That is acceptable for a mod-created custom pool widget when carefully controlled, but it proved unsafe when replayed on the **already-populated shipping Default pool** during cold entry.

The native call could enter UE4SS, destroy/recreate child widgets, and never return before an access violation.

### Current rule

For the default/Player Created pool:

> **Preserve the shipping widget and its shipping rows. Do not replay its row-generation handler.**

If a manager-direct move leaves exactly one now-non-authoritative Default row in
the stale VM array, changing only that row to `Collapsed` is a bounded exception.
Keep it attached so the native stack and stale typed-array indices remain aligned;
set it back to `Visible` if the character later returns to Default.

The same targeted visibility reconciliation must run after character deletion
and later Databank refreshes. Native bindings can make a stale moved/deleted row
visible again even though its GUID is absent from manager ownership. Compare each
existing Default VM row's GUID against the authoritative Default GUID set, and
only call `SetVisibility` for a non-authoritative row (or a row this mod previously
collapsed and must restore). Do not regenerate or remove the stock row.

Wait until the number of native stock rows matches the authoritative Default pool state, then decorate the existing rows.

The current log breadcrumb for this path is:

```text
Default Custom safe path: preserving shipping rows; nativeRows=N authoritativeVMRows=N
```

---

## 9. Mod-Created Custom Folder Widgets

Player-created pools are rendered using native pool widget classes rather than a completely custom replacement UI.

The current pattern is approximately:

1. Get the class from the shipping `CharacterPool` widget.
2. Create another instance through `WidgetBlueprintLibrary.Create`.
3. Bind its `BrunoCharacterPoolViewModel` through the MDVM library.
4. Apply the visible native pool name.
5. Set `HideIfEmpty=false` so newly-created empty folders remain visible.
6. Invoke the row population path for that **mod-created** pool widget.
7. Restore the expected pool context/tooltip behavior on generated rows.
8. Attach folder action controls at generation time.

The distinction matters:

- **shipping Default pool:** preserve and decorate;
- **mod-created custom folder widget:** controlled native generation is currently part of the renderer.

### Breadcrumb before dangerous native generation

Before invoking a generated row handler, log first:

```text
<folder> row apply begin: requested=N
```

If UE4SS crashes inside the generated Blueprint call, that breadcrumb identifies the exact folder even though Lua never regains control.

---

## 10. Folder Tooltips

Dynamically-created rows do not always inherit the same hidden MDViewModel context as shipping-generated rows.

For custom folder rows, the implementation has used three layers to restore native behavior:

1. replay the shipping parent → child pool context bridge;
2. replay the row's generated `BrunoCharacterPoolViewModel` ViewModel-changed handler;
3. explicitly populate the existing native tooltip box when the hidden binding still does not converge.

The useful save/display source is:

```text
BrunoCharacterPoolViewModel:GetSaveFileNameForPool()
```

and the existing row tooltip can be given a payload equivalent to:

```text
HeaderText = "FOLDER NAME"
BodyText   = <native pool save name>
```

Prefer feeding the existing native tooltip widget rather than replacing the game's tooltip presentation wholesale.

---

## 11. Create Folder

### Recommended flow

```text
click Create Folder
→ native-style popup
→ validate name
→ BrunoCharacterDatabankViewModel.CreatePool
→ native mutation occurs
→ mutation hook schedules authoritative reconciliation
```

Name validation:

```lua
local available = vm:IsNewPoolNameAvailable(FText(name))
```

Creation:

```lua
local pool = vm:CreatePool(FText(name), 5)
```

### Important rule

Do not create a parallel folder record in Lua or write the save manually.

If `CreatePool` succeeds, Zero Company owns persistence and identity from that point forward.

---

## 12. Rename Folder

Only player-created custom pools should receive the rename control.

The default/Player Created pool should remain protected.

Recommended flow:

```text
click Rename
→ native-style popup with current name
→ IsNewPoolNameAvailable(newName)
→ BrunoCharacterDatabankViewModel.RenamePool(poolVM, newName)
→ authoritative refresh
```

Native operation:

```lua
vm:RenamePool(pool_vm, FText(new_name))
```

Do not merely change the visible text. The folder name is native state and must be mutated natively.

---

## 13. Delete Folder

The current design deliberately refuses to delete a non-empty folder.

Before deletion, re-read authoritative manager state rather than trusting a character count captured when the button was rendered.

Recommended flow:

```text
click Delete
→ re-read CharacterPoolManager
→ confirm pool still exists
→ confirm authoritative character count == 0
→ confirm dialog
→ BrunoCharacterDatabankViewModel.DeletePool(poolVM)
→ authoritative refresh
```

Native operation:

```lua
vm:DeletePool(pool_vm)
```

The default pool is never a delete target.

---

## 14. Move / Transfer Character

This operation should be manager-driven.

The path that has best preserved single authoritative ownership is:

```text
BitReactorCharacterPoolManager:MoveCharacterToAnotherPool
```

### Before moving

Revalidate all of the following at click time:

- the target folder still exists;
- the character GUID still exists in authoritative manager state;
- the character's current source pool is rediscovered from authority;
- source and target are not the same pool.

Do not trust a row object's old source-folder pointer after folder collapse, rebuild, rename, or previous movement.

### Native call

The current implementation resolves the game's real GUID value and then calls:

```lua
manager:MoveCharacterToAnotherPool(guid_value, FText(target_pool_name))
```

After success, let the native mutation hook schedule the UI reconciliation.

### Valid destinations

For a humanoid custom character, the destination picker is built from current authority:

- the default Player Created pool;
- every other player-created custom folder;
- excluding the character's current pool.

---

## 15. Why Per-Row UI Has Been Difficult

Most of the instability in this project has not come from the native move API. It has come from attaching UI to character rows safely.

Several approaches have been tested.

### Approach that crashed: full cloned CommonUI button per row

Constructing a full native/CommonUI Blueprint button tree for every character row produced too much object churn during Databank activation.

A 24-character default pool is enough to make “just clone one native button per row” unsafe under UE4SS.

### Approach that crashed: generated row-created delegate hook

Hooking a generated `BitReactorStackBox` row-created delegate placed Lua directly in a fragile native widget-generation path and could crash as the first rows were created.

### Approach that was unsafe: polling row UObjects

Continuously polling hover state every few dozen milliseconds means retaining and dereferencing row UObjects after the game may have collapsed or rebuilt the folder.

That creates stale-UObject risk.

### Approach that still crashed: row-owned lightweight visual

The v13.9 stability rollback is:

- find an existing safe action host/overlay inside the native row;
- add a fixed-size native UMG `SizeBox` with a hit-test-invisible glyph;
- keep the visual row-owned and avoid reparenting the shipping row;
- do not construct a raw UMG `Button` or bind a multicast delegate during Databank activation.

No row is detached, wrapped, reordered, or used to rebuild the parent stack.

The v13.9 runtime completed both custom folders and four compact stock-row
visuals, then access-violated while beginning the fifth. Removing the raw Button
was necessary but did not make cumulative per-row UMG construction safe.

The v13.10 stability baseline therefore created no per-character Move UI at all
and completed a cold Databank entry successfully.

v13.11 keeps that row-safety rule and moves the affordance to the selected
character's native detail action row. It follows Character Share's proven model:
clone `Button_Edit` once, append one native spacer and one native TopNav button,
and let the shipping action-row visibility follow the current selection.

---

## 16. Stock Rows Need an Even Lighter Path

v13.4 proved that even “lightweight” can still be too expensive if every transfer glyph is built as a multi-object vector icon during the same activation render.

The default pool contained 24 long-lived shipping rows. The implementation successfully decorated two and then crashed inside native UE4SS while the next decoration was underway.

### v13.10 strategy

For shipping stock rows:

- preserve the native Default pool untouched;
- do not inspect, retain, rescan, or decorate its character rows;
- do not register per-character click or post-folder-click rescan hooks.

Custom-folder rows are also left without Move controls. Folder Create, Rename,
Delete, row population, and tooltip-context restoration remain enabled.

This gives a useful general rule:

> **UI complexity should scale inversely with the number and lifetime of shipping widgets being decorated.**

---

## 17. Click Routing

A visible `SizeBox` transfer hit-zone does not receive a click itself.

In the shipping row hierarchy, its pointer event bubbles into the native character-row button. The v13.6 screencast demonstrated this clearly: the MOVE CHARACTER tooltip appeared, but clicking opened the character editor.

Observing the CommonUI click stream is insufficient:

```text
/Script/CommonUI.CommonButtonBase:HandleButtonClicked
```

`RegisterHook` observes that call but does not cancel the shipping row's original behavior. Hover-state checks at click time also proved unreliable.

The v13.7-v13.8 route tried a native `/Script/UMG.Button` as the transfer surface. It consumed the pointer click and exposed `OnClicked` as a multicast delegate. UE4SS delegate binding used the button's harmless `ResetCursor` UFunction, with a global hook accepting only registered Move-button identities.

That route is unsafe on cold Databank entry. The final v13.8 breadcrumb showed
custom-row generation and tooltip restoration completing, followed by a native
access violation inside transfer-control installation before the first success
line. v13.9 removes both raw Button construction and delegate binding from the
row-decoration path.

The historical bridge intended to:

1. capture only stable/string data needed for the move;
2. schedule the Move dialog after the native click unwinds;
3. deduplicate against the row's generated `BP_OnClicked` fallback.

The row event can remain a fallback:

```text
WBP_CharacterBank_CreatedCharacterItem_C:BP_OnClicked
```

but it should not be the only route. v13.11 registers neither row path. Its one
detail button is routed through `CommonButtonBase:HandleButtonClicked`. The detail
`CharacterBankAuxVM_C.CharacterVM` is a `BrunoCharacterViewModel` and its pool-data
ID is not the authoritative manager key. v13.12 therefore reads
`AuxVM.SelectedCharacterButton` at click time and resolves that row's bound
`BrunoCharacterPoolCharacterViewModel`. That binding is correct, but its GUID
surfaces as an opaque generic UObject proxy. v13.13 attempted to match that proxy
by UObject identity against the typed pool arrays, but testing showed the proxy
and typed entry also have different identities. v13.14 instead finds the concrete
selected row's index in its pool and reads the exact typed ViewModel at that
position. Generated pools retain only their ordered typed render list; the stock
pool is read only after MOVE is clicked. The resulting GUID is still verified
against authoritative manager ownership before the destination picker opens.

---

## 18. Folder Collapse / Expand

Folder collapse can destroy or regenerate character row widgets.

Therefore:

- do not retain a long-lived assumption that the old row UObject is still live;
- do not perform a full authoritative rebuild *inside* the shipping folder click;
- wait for the native collapse/expand action to unwind;
- perform a delayed decoration rescan afterward.

Current useful hook:

```text
WBP_CharacterBank_CreatedCharacterFolder_C:BP_OnClicked
```

Its job should be small: **schedule a later rescan of current rows**, not rebuild the Databank itself.

---

## 19. CommonUI Hover / Visual State

Folder action controls currently use native hover/focus behavior where possible.

Useful CommonUI events include:

```text
/Script/CommonUI.CommonButtonBase:BP_OnHovered
/Script/CommonUI.CommonButtonBase:BP_OnUnhovered
```

A stable visual approach is to keep injected glyphs hit-test-invisible and let the native button or row continue to own pointer behavior.

Avoid high-frequency timers whose only purpose is to poll hover state on UObjects.

### Use owned game-thread delayed actions

The v1.0.0 pre-release build originally nested `ExecuteWithDelay` around
`ExecuteInGameThread`. Repeated Move dialogs eventually reproduced UE4SS's
callback-registry race:

```text
Lua::Registry::get_function_ref: Ref was not function
EXCEPTION_ACCESS_VIOLATION reading address 0x2
```

The crash occurred after several successful moves, while the next destination
dialog's delayed activation/repaint work was pending. The manager mutation had
not started. This matched the known `process_simple_actions` re-entry failure
caused by overlapping legacy callbacks.

Enhanced Databank now uses `ExecuteInGameThreadWithDelay` for one-shot work and
a `RetriggerableExecuteInGameThreadWithDelay` handle for authoritative refresh
coalescing. It also removed the 40 ms Create Folder hover polling chain in favor
of the existing `BP_OnHovered` / `BP_OnUnhovered` hooks.

General rule:

> Never compose `ExecuteWithDelay` and `ExecuteInGameThread` for Databank UI
> work. Use the owned delayed game-thread action API, coalesce repeated refreshes
> with a handle, and prefer native events over recurring polling.

---

## 20. Mutation Hooks Worth Watching

After any native operation that can change pools or membership, schedule reconciliation rather than attempting to surgically patch every visible widget yourself.

Useful observed mutation hooks include:

### Databank ViewModel

```text
/Script/Bruno.BrunoCharacterDatabankViewModel:CreatePool
/Script/Bruno.BrunoCharacterDatabankViewModel:RenamePool
/Script/Bruno.BrunoCharacterDatabankViewModel:DeletePool
/Script/Bruno.BrunoCharacterDatabankViewModel:MovePoolCharacterToPool
```

### Character Pool Manager

```text
/Script/BitReactorGame.BitReactorCharacterPoolManager:MoveCharacterToAnotherPool
/Script/BitReactorGame.BitReactorCharacterPoolManager:RenamePlayerCreatedCharacterPool
/Script/BitReactorGame.BitReactorCharacterPoolManager:DeletePlayerCreatedCharacterPool
```

These hooks are useful even if your own feature uses only one of the mutation surfaces, because another game path or another mod may mutate the same Databank.

The following higher-level operation exists:

```text
BrunoCharacterDatabankViewModel.MovePoolCharacterToPool(
    source BrunoCharacterPoolCharacterViewModel,
    destination BrunoCharacterPoolViewModel
)
```

v13.15 showed that this is **not safe to assume as the better mutation boundary**
for mod-created pool widgets. The call removed the source VM but did not add the
destination VM, while manager ownership still moved. The old convergence loop
then rebuilt all dynamic folders every 100 ms and crashed in UE4SS after nine
passes. v13.16 returns to the manager-direct GUID operation, performs no automatic
convergence retries, and handles a stale shipping Default row with one targeted
`Collapsed`/`Visible` change. It does not detach or regenerate that row.

Also avoid replaying the generated row-created and pool-ViewModel-changed handlers
merely to restore folder tooltip context. Their MDViewModel binding never matched
the intended pool in diagnostics, and both v13.15 crash dumps had the same UE4SS
GameThread stack while those per-row calls were being repeated.

---

## 21. UObject Lifetime Rules

This area deserves explicit rules because several crashes have had the shape of stale/native-invalid UObject access.

### Prefer storing

- GUID strings;
- pool-name strings;
- object path/name snapshots used only for identity comparison;
- current authoritative counts;
- short-lived references used during one game-thread callback.

### Be cautious storing

- character row UObjects;
- folder row UObjects;
- children of a stack the game can rebuild;
- popup widgets after close;
- dynamic widgets across an authoritative render.

### Before using a retained UObject

At minimum:

- unwrap/re-resolve it;
- confirm it is still non-nil;
- if possible, confirm its object identity/path still matches what was expected;
- prefer rediscovery from the current live page over trusting an old reference.

And never assume `pcall` can save you from an invalid native dereference. A Lua exception is catchable; a native UE4SS access violation is not.

---

## 22. Generated Blueprint Functions Are High-Risk Boundaries

A generated Blueprint event callable from Lua may look like a normal method, but some of these calls run large compiled widget graphs and can synchronously create/destroy many UObjects.

Treat calls such as this as a hazardous boundary:

```text
BndEvt__...PoolCharacterViewModels(...)
```

Recommended practice:

```lua
log("Folder X row apply begin: requested=" .. tostring(#rows))
-- enter generated/native Blueprint handler
...
log("Folder X rows applied ...")
```

If the second breadcrumb never appears and the crash dump shows UE4SS/native frames, the failure was likely inside that native boundary.

Do not conclude that `try_call` or `pcall` made the operation safe merely because the Lua code is wrapped.

---

## 23. Patterns to Avoid

### Do not manually write Databank save files

Use native create/move/rename/delete APIs whenever possible.

### Do not force the shipping Default pool to regenerate

It already owns its rows and native binding lifecycle.

### Do not detach and reparent shipping character rows

Especially do not clear and rebuild `BitReactorStackBox_25` merely to inject an action.

### Do not create a complex cloned Blueprint button per stock row

Twenty-plus simultaneous CommonUI widget trees are far more expensive and fragile than they look.

### Do not hook deep row-generation delegates unless absolutely necessary

Prefer post-generation reconciliation and minimal decoration.

### Do not poll row UObjects continuously

Collapsed/rebuilt folders make retained row references unsafe.

### Do not use visible pool labels as unquestioned ownership authority

The shipping Default widget's MDViewModel-facing name has not always matched the manager-side authoritative name cleanly enough for transfer ownership checks.

### Do not let renders overlap

Coalesce refresh requests while a render is active.

### Do not trust render-time state at action time

Revalidate folder existence, emptiness, GUID membership, and source ownership immediately before destructive/native mutations.

---

## 24. Logging That Makes Native Crashes Debuggable

For this sort of UE4SS work, breadcrumbs immediately *before* native boundaries are more useful than verbose success logging.

Recommended breadcrumbs include:

```text
=== AUTO DATABANK POOL RENDER ===
reason=...

Authoritative Default Custom characters=N
Authoritative player-created custom pools=N

Default Custom safe path: preserving shipping rows; nativeRows=N authoritativeVMRows=N

Default move decoration begin: row=N name='...' guid=...
Default move decoration complete: ...

'<folder>' row apply begin: requested=N
'<folder>' rows applied: requested=N renderedChildren=N

Move Character invoking CharacterPoolManager.MoveCharacterToAnotherPool: ...
Move Character manager call returned: result=... err=...
Default row visibility reconciled: index=... guid=... visibility=...
```

When a native crash occurs, the last completed breadcrumb tells you which unsafe boundary to inspect.

Do not over-interpret generic UE4SS messages such as callback garbage collection without correlating them with the last operation your mod actually entered.

---

## 25. Debug / Recovery Keybinds

The current implementation reserves:

```text
Shift+F7 — manual authoritative refresh
Shift+F8 — UI-only cleanup / raw stock restore
```

The cleanup path should be conservative.

In particular, it should remove mod-created dynamic UI but **not** replay the risky shipping Default pool row-generation handler.

A recovery action that itself rebuilds the most fragile native widget tree is not a recovery action.

---

## 26. Recommended Test Matrix

Do not validate Databank changes only on a hot reload.

### Cold-entry stability

- Fresh game launch.
- Enter Databank as the first relevant UI action.
- Confirm the page loads without first visiting another screen.
- Confirm all default rows eventually receive expected decoration.

### Default pool

- Default pool with a large number of characters.
- Scroll through all rows.
- Select normal row area.
- Hover/click Transfer area.
- Ensure Transfer does not accidentally become an ordinary character click only.

### Folder creation

- Create an empty folder.
- Verify it is visible immediately.
- Restart the game.
- Verify it persists.

### Folder rename

- Rename an empty folder.
- Rename a folder with characters.
- Attempt a duplicate name.
- Restart and verify persistence/content ownership.

### Folder deletion

- Attempt to delete a non-empty folder and verify it is blocked.
- Empty the folder.
- Delete it.
- Confirm the default pool can never be targeted.

### Character movement

Test all directions:

```text
Default → Custom
Custom  → Default
Custom A → Custom B
```

Also test:

- moving the final character out of a folder;
- moving a character immediately after rename;
- moving after collapse/expand;
- rapidly clicking different rows;
- opening and cancelling the destination picker;
- restarting after moves to confirm native persistence.

### Reconciliation

- Trigger `Shift+F7` repeatedly.
- Collapse and expand folders.
- Confirm no duplicate buttons/hit-zones accumulate.
- Confirm no characters appear in two folders at once.

### Coexistence

If Character Share or another Databank mod is enabled:

- enter Databank from a cold launch;
- import/export or otherwise mutate characters;
- verify Enhanced Databank catches the resulting native pool refresh;
- confirm both mods are not rebuilding the same shipping widget simultaneously.

For top-row actions, use a cooperative flat `HorizontalBox`. Detect an existing
mod-owned row before replacing `WBP_CharacterBankCreateNewBtn`; resize only the
shared Create New `SizeBox`, then append or visually position one fixed-width
action wrapper per mod. Enhanced Databank v1.0.0 and Character Share v1.0.3 use
64-unit compact actions with an 8-unit gap, so their Import and Create Folder
buttons never nest or overlap regardless of load order.

---

## 27. Extending This to Character Share / Enhanced Databank v2

The same stability rules should apply to future Databank actions such as Share, Import, sorting, or custom arrangement.

### For per-row Share actions

Prefer:

- a lightweight row-owned decoration;
- staged installation for a large default pool;
- CommonUI click routing;
- string/GUID snapshots rather than retained row UObjects;
- no rebuilding of shipping rows.

### For sorting / custom arrangement

First determine whether Zero Company has a native ordering primitive.

If it does, use it.

If it does not, distinguish carefully between:

- **presentation-only ordering**, which can be reconstructed each time; and
- **persistent Databank ordering**, which would require understanding the game's actual persistence model.

Do not infer a save structure and start rewriting `.sav` data simply because the UI exposes a list.

### For imported characters

After Character Share adds a character, let the native Databank/manager become authoritative first. Enhanced Databank should then reconcile from the manager rather than assuming the imported row already exists or has a stable UObject.

---

## 28. Suggested Module Boundaries for a Production Mod

The implementation grew from exploratory work. Future production cleanup would benefit from separating responsibilities without over-fragmenting them.

A practical shape would be:

```text
databank_authority.lua
    discover manager
    normalize pools
    resolve GUID ownership
    validation helpers

lifecycle.lua
    lazy hook install
    page readiness
    refresh coalescing

folders.lua
    create / rename / delete native calls
    folder header decoration

transfer.lua
    staged row decoration
    click routing
    destination picker
    Databank-VM native move

renderer.lua
    custom-pool widget reconciliation
    default-pool preservation

ui.lua
    shared popup helpers
    glyph construction
    hover/focus treatment

log.lua
    breadcrumbs / diagnostics
```

v13.8 began this split with two narrow runtime modules:

```text
move_button_bridge.lua
    v13.8 native UMG button delegate experiment (retained but inactive in v13.10)

debug_keybinds.lua
    Shift+F7 refresh / Shift+F8 cleanup registration

selected_move_button.lua
    one Edit-derived detail action / selected-VM authority resolution
```

This was required because Lua limits one function—including a file's main chunk—to 200 simultaneously active locals. A long monolithic script can be syntactically valid in a parser yet fail when UE4SS compiles the chunk. Compile-time validation should therefore use an actual Lua compiler, not only an AST parser.

Keep the “authority” layer free of UMG wherever possible. That makes it much easier to determine whether a bug is data ownership or merely widget presentation.

---

## 29. Practical Safety Checklist Before Adding a New Databank Feature

Before implementing a new action, answer these questions:

- **What native object already owns this data?**
- **Is there a native mutation function for it?**
- **Can I re-read authoritative state after the mutation instead of maintaining my own copy?**
- **Am I touching a shipping widget that the game may rebuild?**
- **Can the action be an overlay/decoration rather than a wrapper/reparent?**
- **How many UObjects will this create on a 24+ character pool?**
- **Can widget creation be staged across game-thread turns?**
- **Am I retaining row UObjects after collapse/expand?**
- **Am I invoking a generated Blueprint graph that can rebuild children?**
- **Did I log immediately before that native boundary?**
- **Can simultaneous refresh requests overlap?**
- **Do I revalidate destructive operations at click time?**
- **Does the feature survive a fresh launch, not merely Reload Mods?**

If several answers are uncomfortable, simplify the design before adding another hook.

---

## 30. Current Working Mental Model

The Character Databank is safest to mod when treated less like a static menu and more like a transient projection of native pool state.

The native manager owns the truth.

The Databank ViewModels expose supported mutations and UI-facing data.

The shipping UI is disposable: folders can expand, rows can be regenerated, and widget references can become stale.

A stable mod therefore behaves like a reconciler:

```text
observe
→ verify readiness
→ read authority
→ render/decorate minimally
→ mutate through native APIs
→ observe native mutation
→ reconcile again
```

That architecture has been substantially more reliable than attempting to “take over” the Databank widget tree.

---

## Appendix A — Quick Reference

### Authoritative object

```text
BitReactorCharacterPoolManager
└─ CharacterPools
```

### High-level Databank VM

```text
BrunoCharacterDatabankViewModel
├─ IsNewPoolNameAvailable
├─ CreatePool
├─ RenamePool
└─ DeletePool
```

### Move primitive

```text
BitReactorCharacterPoolManager:MoveCharacterToAnotherPool
```

### Humanoid lifecycle paths

```text
WBP_CharacterBank_Master_C:BP_OnActivated
WBP_CharacterBank_Page_CharacterList_C:BP_OnActivated
WBP_CharacterBank_CreatedCharacterItem_C:BP_OnClicked
WBP_CharacterBank_CreatedCharacterFolder_C:BP_OnClicked
CommonActivatableWidget:ActivateWidget
CommonButtonBase:HandleButtonClicked
```

### Important live widget properties

```text
page.CharacterPool
pool.BitReactorStackBox_25
```

### Debug keys

```text
Shift+F7  authoritative refresh
Shift+F8  UI-only cleanup / stock restore
```

---

## Appendix B — Stability History in One Page

| Revision idea | Outcome / lesson |
|---|---|
| Native folder renderer | Viable when game remains authority |
| Create Folder via native VM | Stable direction |
| Rename/Delete via native VM | Stable direction |
| Full per-row cloned CommonUI Move buttons | Too much native widget construction; crash-prone |
| Reparent/wrap native character rows | Avoid; destabilizes shipping hierarchy |
| Shared Move control with row polling | Reduced object count, but retained/polled row UObjects are risky |
| Generated stack row-created hook | Too deep in row-generation lifecycle; crash-prone |
| Hover-only row-owned transfer hit-zones | Tooltip works, but click falls through to the character editor |
| Force Default pool generated row handler | Cold-entry native crash; never do this |
| Preserve shipping Default rows | Correct direction |
| CommonUI click routing | Necessary because transfer area can bubble to the native row button |
| Rich icon on all 24 default rows in one render | Still too much construction; native crash after first rows |
| Stage stock decorations + two-widget stock control | Necessary, but v13.5 still touched the stock VM inside activation |
| Defer the entire stock reconciliation and re-resolve live UObjects | v13.6 prerequisite retained |
| Native UMG Move button with delegate routing | v13.7-v13.8 cold-entry native crash; removed in v13.9 |
| Split runtime bridges out of the main chunk | v13.8 fixes Lua's 200-local compile limit |
| Row-owned SizeBox transfer visual | v13.9 still native-crashed during the fifth stock-row decoration |
| Folder-only renderer with no per-row Move UI | v13.10 cold-entry stability validated |
| One selected-character detail-row Move action | v13.11 Character Share-derived direction |
| Selected row MDViewModel ownership bridge | v13.12 fixes detail-VM GUID mismatch and copies live button style enums |
| Typed pool-array identity match | v13.13 disproved: generic proxy and typed array entry have different UObject identities |
| Selected row position → typed pool entry | v13.14 resolves a real GUID/source on click without activation-time stock-row inspection |
| Databank VM native move | v13.15 disproved: source VM removed, destination VM missing, retry rebuild storm crashed |
| Stable manager move + targeted Default visibility | v13.16 restores one-pass rendering and never regenerates/detaches shipping rows |
| Cooperative flat top action row | The v1.0.0 release shares Create New width with Character Share's compact Import action instead of nesting mod-owned rows |

---

*These findings are build-specific and empirical. Treat generated Blueprint paths, numbered widget fields, and undocumented native behavior as provisional until revalidated after a game or UE4SS update.*
