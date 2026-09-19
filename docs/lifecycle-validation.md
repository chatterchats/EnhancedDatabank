# Activation-driven Databank initialization

The old startup installer searched for a live master twice every 400 ms until
both Blueprint activation hooks were installed. It also started separate catch-up
render retries when individual hooks became available. The new installer has no
recurring startup task.

The primary cold-entry trigger follows Character Share: the existing native
`CommonButtonBase:HandleButtonClicked` hook routes only transient
`WBP_AnimatedSubMenuListButton_C` buttons to entry handling. Other Strategy submenu
selections cancel outstanding entry/render work. Only a button whose live
`ButtonTextBlock:GetText()` contains `DATABANK` (case-insensitive) starts discovery.
This label filter matches Character Share's English-label behavior; localized
labels or entry paths that bypass this button require separate in-game validation.

Discovery makes at most six owned checks after the click (150, 150, 200, 300, 450,
and 650 ms delays). It requires the same live master to be visible on two
consecutive observations before touching its page tree or installing hooks. It
never calls `IsActivated()` on the master: Character Share documents native crashes
from that call during entry. The selected page is resolved after master readiness.

CommonUI `ActivateWidget` post-hooks remain a secondary trigger and accept only
transient Databank master widgets or the supported `OtherCharacterList` / `AstromechCharacterList` instances of
`WBP_CharacterBank_Page_CharacterList_C`. Unrelated widgets, CDOs and unsupported
pages return before discovery, widget-tree reads or delayed work. The callbacks
unwrap their context immediately; they do not retain a `RemoteUnrealParam`.

For an activation callback, one owned request waits 120 ms for activation to
unwind, then installs resident Blueprint activation/deactivation hooks and checks the active page's stock tree,
ViewModels and authoritative pools. Missing initialization retries every 100 ms,
up to 20 attempts total, including any click-entry checks. A successful readiness
check queues one render through the existing retriggerable refresh handle. Empty Default pools
are valid. Partial hook registration can keep retrying within the same budget
without queuing another render.

Menu-entry, master/page and Blueprint/CommonUI notifications merge into that
request without extending its budget. Deactivation or a new page retires it and cancels its action
group. Request identity checks also invalidate already-dispatched callbacks and
queued activation renders. Blueprint deactivation hooks cover subsequent entries
where C++ bypasses the native CommonUI UFunction. Existing registry teardown still
owns every hook ID pair and action; no asynchronous UObject work was introduced.

After UI cleanup, startup makes exactly one master lookup on the game thread. An
already-visible master with an active supported page enters the same initialization
path, recovering either tab after same-state or fresh-state script reload. An absent or closed master stops
there. A later activation can start a new request after a close or tab transition.

## API evidence inspected (2026-09-19)

The installed runtime was read without modifying the game installation:

- `SWZeroCompany/Binaries/Win64/ue4ss/UE4SS.dll`, SHA-256
  `8cb45c18230547a1ead97bfeb34a2b5ef710b778890ddfc01877a7e9c61a07f4`.
  Its embedded overload diagnostics confirm `MakeActionHandle()`,
  `ExecuteInGameThreadWithDelay(handle, delayMs, callback)`,
  `RetriggerableExecuteInGameThreadWithDelay(handle, delayMs, callback)`,
  `CancelDelayedAction(handle)`, validity/activity queries, current-mod blanket
  cleanup, and `UnregisterHook(path, preId, postId)`.
- Installed `Mods/shared/types/CommonUI.lua` declares `ActivateWidget`,
  `DeactivateWidget` and `IsActivated`. Installed master and character-list type
  dumps both declare `BP_OnActivated` and `BP_OnDeactivated`. The master exposes
  both supported page properties with the same character-list class.
- Existing installed logs confirm registration of the native CommonUI activation
  hook and both Blueprint activation hooks for the original polling version. The
  failed CommonUI-only replacement's latest log contains startup registration but
  no lazy-hook installation or render. This, together with the reported default-only
  screen, exposed the missing entry path. CommonUI registration alone is insufficient.
- Character Share's `Scripts/lifecycle.lua:handle_strategy_submenu_click` and
  `Scripts/button_hooks.lua` provide the menu-click trigger; its
  `Scripts/widget_helpers.lua` provided the original visibility/stability approach.
  The installed submenu type dump confirms `ButtonTextBlock`; installed UMG types
  confirm the parent/visibility methods. The existing installed log confirms the
  shared native `HandleButtonClicked` hook registration. No second button hook or
  new engine API registration is introduced.
- Current upstream [RegisterHook documentation](https://github.com/UE4SS-RE/RE-UE4SS/blob/main/docs/lua-api/global-functions/registerhook.md),
  fetched through Context7, confirms that functions must be resident, native
  `/Script/` hooks use the third argument for post-callbacks, Blueprint hooks use
  the second, and both returned IDs are needed for unregistration. Installed DLL
  overloads were checked separately because delayed-action extensions are build
  specific.

## Parent/viewport readiness correction

The subsequent in-game log shows two recognized submenu clicks, each followed by
entry-probe expiry, then a successful manual Shift-F7 render. The installed
lifecycle and button-hook files matched source. This establishes that entry was
blocked before hook installation, rather than failing in the pool renderer. The
old expiry message did not record which readiness condition rejected the master.

The adaptation had introduced a stricter requirement than Character Share:
`GetParent():IsValid()` or `IsInViewport()` had to be true. That is unsuitable for
CommonUI stack content. Epic's [UWidget API](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/UMG/UWidget)
defines `GetParent` as returning a `UPanelWidget`; installed type dumps declare
`UCommonActivatableWidgetContainerBase` as a `UWidget`, not a panel. The game's
`WBP_OverallUILayout` uses BitReactor/CommonUI widget stacks. A displayed stack
widget need not have a UMG panel parent or be directly attached to the viewport.
A mock with that supported shape reproduces the rejection; no live parent-value
capture from the failing run was available.

Entry now uses live/transient identity and visibility, with the existing stable
observations and active-page/tree/ViewModel checks. It does not inspect panel
parent or direct viewport membership. Startup recovery additionally requires an
active supported page so a visible but closed cached master cannot arm retries.
Changed wait conditions and the final rejected entry condition are logged within
the existing finite budget; there is still no recurring idle search.

## Regression coverage

`tests/lifecycle_test.lua` loads the real bootstrap, registry, scheduler,
categories, readiness checks, pool authority and renderer against mocked engine
objects and widget-construction boundaries. It checks:

- Idle startup drains after one recovery probe; unrelated CommonUI events perform
  no discovery and schedule nothing.
- Click-only cold entry, with no CommonUI callbacks and no master at click time,
  waits for visibility and two stable observations, installs hooks and renders.
  Click-only reentry handles reused widgets without deactivation callbacks.
- Unrelated/empty submenu labels perform no discovery; navigation cancels stale
  callbacks; a Databank click producing no master exhausts six checks and stops.
- Stack-hosted masters with a null UObject parent wrapper or literal nil parent,
  and false direct viewport membership, still initialize. A visible cached master
  with no active page does not start recovery. Probe expiry logs the failing check.
- Cold entry installs hooks once, waits for missing stock widgets and custom pool
  VMs, then renders the correct custom pools/character rows exactly once.
- Native and Blueprint event bursts, warm reentry, both categories, empty Default
  pools and Astromech entry with no Custom page.
- Partial hook-registration failures, finite readiness exhaustion, later page
  activation, tab supersession, close before render, and invalid UObjects.
- Same-state teardown, stale callback delivery, fresh-state recovery, and reload
  with a closed surviving master.

Refresh tests also check guard replacement on the stable callback and native
mutation coalescing without retaining an old activation guard. Existing widget,
folder-control, category/mutation and reload tests remain applicable.

## In-game status and follow-up checks

On September 19, 2026, the user reported that the parent/viewport correction
appeared to fix automatic Databank loading. This is an in-game report for the
corrected entry path, separate from the mocked regression coverage. No new
MangoHud capture was supplied, so this release does not claim a measured frametime
improvement or completion of the full category/reload/coexistence matrix.

The following checks remain useful when validating the release package:

1. Cold launch and stay in menus/gameplay without opening Databank. Compare
   MangoHud captures with the prior recurring 440–500 ms spikes.
2. Open Databank for the first time. Confirm the submenu-click and stable-entry
   messages appear in the log and the four lazy Blueprint hooks install, then one
   authoritative render completes.
   Test entering Custom Characters and Astromechs first, including empty pools.
   No CommonUI activation callback is required for this first entry.
3. Reopen repeatedly, switch tabs, and close immediately during first entry.
   Confirm correct folders/rows, stable control counts, no stale rebuild after
   close, and no continuing initialization attempts while closed.
4. Reload scripts while closed and while each supported tab is open, including
   UE4SS Reload All Mods. Confirm one recovery render and no duplicate hooks or
   controls. Repeat create/rename/move/delete flows with Character Share enabled.
5. Repeat gameplay captures after leaving Databank and compare logs/frame pacing.
