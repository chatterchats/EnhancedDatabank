# Star Wars: Zero Company — Practical UE4SS UI Modding Notes

## Purpose

> **September 19, 2026 release addendum:** Enhanced Databank v1.0.4 replaces the recurring startup search with bounded, entry-driven initialization. See [lifecycle validation](lifecycle-validation.md) for the CommonUI stack correction, regression coverage, and user-reported in-game result. The historical findings below retain their stated versions and evidence limits.

This guide summarizes UI work from **Character Share**, **Enhanced Databank**, **Colors+**, **SWZC Dev Panel**, and the **Tactical Info+ combat-log prototype**.

Updated September 18, 2026 against Character Share **v1.0.3 plus its unreleased entry-validation fix**, Enhanced Databank **v1.0.3** (`f527e41`), Colors+Probe findings through **v0.2.52**, SWZC Dev Panel **v0.2.0**, and the recorded combat-log UI tests. The supplied revision already included Colors+ through v0.2.52; this revision consolidates the additional project findings and corrects earlier generalizations. It does not imply a new successful game test.

The Character Share narrative is retained in sections 1–27, with qualifications where later work changed the recommendation. Sections 28–34 cover preview ownership and diagnostics; sections 35–49 add the Databank, discovery, input, reload, and performance findings. Sections 50–51 provide a test matrix and source index.

Generated class paths, numbered widget fields, enum values, and delayed-action capabilities are specific to the inspected game/UE4SS builds. Enhanced Databank's metadata lists game builds `25134257` and `24874058`; its historical discovery guide records `++ProjectBruno+Stable-CL-196985` and UE4SS `v3.0.1 Beta #0`. Those identifiers are not a compatibility guarantee for every feature below.

Evidence labels used in the additions:

* **Verified behavior** — observed in the stated in-game test, not a guarantee for every screen or game build.
* **Implemented / locally tested** — present in source or covered by mocked tests; native rendering, lifetime, and persistence need separate evidence.
* **Project-specific workaround** — successful within the recorded context; validate before adopting elsewhere.
* **Unresolved experiment** — not a working recipe or proof of a proposed cause.

It is not intended to be a complete Unreal Engine UI reference. Instead, it documents techniques that actually worked in Zero Company, approaches that caused instability, and a few patterns that should be useful to other mod authors adding or modifying game UI.

The biggest overall lesson was simple:

> **Work with the game’s existing UI instead of trying to replace it.**

Zero Company uses Unreal’s UMG and CommonUI systems heavily. Those systems maintain their own focus, navigation, activation, selection, and screen-stack state. A UI modification can look perfectly correct while quietly disrupting one of those systems and causing bugs later.

Character Share became much more reliable once it stopped treating the UI as a static widget tree and started treating it as a **live system with a lifecycle**.

---

# 1. Understanding the UI layers

There are two important pieces involved in most of the UI we touched.

**UMG** is Unreal’s widget system. Things such as horizontal boxes, vertical boxes, spacers, text blocks, buttons, overlays, and size boxes are UMG widgets.

**CommonUI** sits on top of that and handles things such as screen activation, navigation, controller/keyboard focus, bound action buttons, and popup stacks.

That distinction matters because modifying a UMG widget can have consequences in CommonUI.

For example, removing and recreating children in a panel may appear harmless from a layout perspective, but CommonUI may already have references to the original widgets for selection or focus.

That was the source of several of our early problems.

---

# 2. Prefer native game widgets over custom-looking replacements

The most successful approach was to **clone or create the same widget classes the game already uses**.

For Character Share:

* `IMPORT` uses the same widget class as the Databank's native **Create New** button:
  `WBP_CharacterBankCreateNewBtn_C`
* `SHARE` uses the same general action-button class as Edit/Delete/Activate:
  `WBP_BoundActionButton_C`
* Popup actions use:
  `WBP_CharacterDataBank_TopNavButton_C`
* Dialogs use the game's:
  `WBP_GenericPopupMessage_Small_C`

This has several advantages.

The game already supplies fonts, materials, animations, input behavior, button states, controller navigation, scaling, and visual styling. Reusing those means the new control naturally looks like part of the game instead of something drawn over the top of it.

It also reduces the number of assumptions your mod has to make.

A hand-built button might look correct at 1920×1080 with a mouse but fail with controller navigation, ultrawide layouts, UI scaling, or some CommonUI state.

A native-class button gives us a useful starting point, but it still needs the correct owner, instance configuration, bindings, and layout. Enhanced Databank later showed that constructing one such control per character row can be unstable even when one detail-row action works well; see section 41.

---

# 3. Do not rebuild native UI containers unless absolutely necessary

This was probably the most important lesson from the entire project.

Early Character Share versions experimented with things such as:

```text
ClearChildren()
re-add original widgets
insert our widget
```

or attempting operations such as:

```text
InsertChildAt()
ReplaceChildAt()
```

These approaches caused two separate classes of problems.

First, some UMG panel functions exposed through UE4SS did not behave like normal callable Lua methods. `InsertChildAt`, for example, surfaced as a `TrivialObject` in our environment rather than something reliably callable.

Second, and more importantly, rebuilding native containers disrupted game state.

The Character Databank could initially appear correct, but character selection would not work until leaving the screen and coming back. The visual tree existed, but the game had initialized its selection/navigation logic against a different structure.

The reliable strategy became:

> **Leave the game's original children alone. Append your own widgets and adjust only your own layout.**

For Character Share, that meant using the reliable `AddChild` path and then positioning the appended widget visually where we wanted it.

That sounds slightly inelegant compared with inserting at an exact index, but it proved dramatically safer.

---

# 4. Visual placement can be safer than structural placement

A useful workaround emerged from the lack of reliable `InsertChildAt`.

Rather than rearranging the game's children, Character Share appends its widget and applies a render translation so it appears in the desired position.

For the Create New / Import area, we measured the native layout and split the available width:

```text
original row width: 864
gap:                8
target width:       428 each
```

The mod then placed the new Import button visually alongside Create New without reconstructing the native list panel.

The important distinction is:

**Structural change**

```text
Game child 1
Game child 2
Game child 3

becomes

Game child 1
Our child
Game child 2
Game child 3
```

versus:

**Non-destructive visual change**

```text
Game child 1
Game child 2
Game child 3
Our child
```

with our child translated to where it should appear.

CommonUI still sees the native structure it initialized, while the player sees the desired layout.

That was a good tradeoff for the original Character Share layout. These dimensions are historical measurements, not layout constants for every installation. The later shared Create New / Import / Create Folder row uses an explicit cooperative layout; see section 40. Visual placement must still be checked for pointer hitboxes and keyboard/controller navigation.

---

# 5. UI creation must respect screen initialization

One of the harder bugs was the Databank working only **after leaving the screen and returning**.

The first time into the screen, selection would be broken. On the second visit, it worked.

This turned out to be a timing/lifecycle problem.

The Databank screen existed before it was necessarily safe to modify. A widget being discoverable does not mean CommonUI has finished initializing it.

The eventual solution was a **stable re-observation** approach.

When the player clicks the Strategy submenu item:

1. Character Share starts a short bounded check for the Databank.
2. It finds a candidate screen.
3. It does **not** modify it immediately.
4. It waits briefly and finds the same live screen again.
5. Only after seeing the same runtime object twice does integration begin.

In the logs this looked roughly like:

```text
Databank entry probe observed live candidate on attempt 1;
waiting for one stable re-observation.

Databank entry probe stabilized on attempt 2;
beginning UI integration.
```

That tiny delay eliminated a surprising number of problems in Character Share. **Project-specific workaround:** observing the same screen twice is a useful entry heuristic, not proof that every dependent object is ready.

Colors+ showed why the distinction matters: the screen may remain alive while its selected slot, customization fragments, preview actor, or material instances change. Deferred work must resolve and validate its actual target when it runs, not rely solely on the screen observed when it was queued.

The broader lesson is:

> **Object exists** and **object is ready** are not the same thing.

Character Share's current unreleased entry fix validates the Databank master **and its class** before class inspection. Non-nil is insufficient: a non-nil invalid wrapper could reach `GetClass` and access-violate. Keep discovery activation-based; adding `NotifyOnNewObject` observers inside Blueprint/widget construction is not an established replacement.

Enhanced Databank also returns the live page, stock widget, default VM, and scroll widget already resolved by one readiness check. Re-reading those reflected properties later in the same cold-activation callback was a reproduced fault boundary. Reuse validated short-lived results within that operation; reacquire after a deferred boundary or a native call capable of replacing them. “Reacquire” does not mean “repeat every engine lookup redundantly.”

---

# 6. Be careful querying transient CommonUI state

At one point we attempted to use activation checks such as `IsActivated()` while determining whether a Databank master was usable.

That caused intermittent crashes.

The safer approach was to avoid poking transient CommonUI state during that narrow initialization window and instead verify simpler conditions:

* Is the object valid?
* Is it attached?
* Is it visible?
* Is it the same runtime identity we observed previously?

The stable-object check was sufficient without interrogating every bit of CommonUI state.

When working through UE4SS, fewer engine calls during unstable transitions is generally better. This is a warning about the observed initialization window, not a universal ban on `IsActivated()`: current Enhanced Databank uses it on validated page candidates to recover the active category after reload, with activation events as fallback. That later use does not make early activation probing safe in every context.

---

# 7. Runtime identity matters

Zero Company often keeps UI objects alive and reuses them.

The Character Databank is a good example.

Leaving the screen does not necessarily mean its widget object is destroyed. When returning, the game may reuse the same `WBP_CharacterBank_Master_C`.

If a mod blindly installs its widgets every time the screen appears, that produces duplicate controls or stale callback mappings.

Character Share therefore tracks the actual runtime object identity of the Databank master.

When it encounters the same master again:

```text
Character Databank reusable runtime master detected;
adopting existing Character Share controls.
```

It reuses the already-installed controls.

If an entirely new master appears, stale mappings are discarded and integration starts fresh.

This is a useful general pattern:

```text
screen appears
    ↓
same runtime object?
    ├─ yes → reuse/adopt
    └─ no  → reset state and install
```

Do not assume that navigation means destruction/recreation. Conversely, a surviving screen does not imply that all objects beneath it survived.

For deferred Colors+ operations, retain scalar identity/context records and reacquire live objects before use. Validate their current owner, slot, and expected role. A runtime name or validity check alone is not proof that an object still represents the intended edit. Names are lookup aids, not native serial-number identities. Also, a requested clone name may never be applied: section 39 describes adopting a surviving control through its owned overlay instead.

---

# 8. Treat both pages of a multi-page screen independently

The Character Databank contains separate character-list pages for:

```text
OtherCharacterList
AstromechCharacterList
```

They look like tabs of one screen to the player, but internally they are separate live widget trees.

Installing a button into only the currently visible page is therefore not enough.

Character Share integrates into both pages when entering the Databank. Enhanced Databank uses a different valid implementation: one active page registry, with category-specific bindings and adoption of surviving controls when returning to a page. The requirement is correct per-page behavior, not necessarily eager installation into every page.

That avoided having button availability depend on which tab was active during setup.

The broader lesson:

> Tabs, switchers, and pages may each contain their own instances of controls that appear conceptually shared.

Inspect the actual tree rather than assuming a visual element exists only once.

---

# 9. Cloning a widget does not mean cloning its current visual state

This created the long-running Share-button orientation problem.

We created Share from the same class used by the native Edit button:

```text
WBP_BoundActionButton_C
```

But the clone did not inherit Edit's current configured appearance.

Native Edit was effectively:

```text
orientation = Right
size        = Default
type        = Default
```

while the new clone came up using its class defaults:

```text
orientation = Left
```

So the Share button looked backwards.

This is an important Unreal concept:

> Creating another object of the same class gives you the class defaults, not necessarily the live instance's configured state.

---

# 10. Prefer public style properties/functions over manipulating internal child widgets

We initially tried to force the Share visual by reaching inside the Bound Action Button's widget switcher.

The class contains things such as:

```text
WBP_Default_Right
WBP_Default_Left
ButtonSwitcher
SelectedButton
ButtonOrientation
ButtonSize
ButtonType
```

Manipulating the switcher and selected child directly was fragile and contributed to crashes.

The stable solution was much simpler:

```lua
button.ButtonOrientation = 1
button.ButtonSize = 0
button.ButtonType = 0
button:ApplyStyle()
```

The game itself then selected the appropriate visual.

This is a very useful rule:

> If a widget exposes a property plus an `ApplyStyle`, `UpdateStyle`, `Refresh`, or similar function, prefer that over manually changing its internal widget tree.

Let the Blueprint perform its own state transition.

---

# 11. Copy spacing from the UI rather than guessing

Once Share had the correct orientation, it was still visually too close to Activate.

The native action row contains `Spacer` widgets between its controls.

Instead of guessing at margins, Character Share finds the native spacer following Edit and clones its dimensions.

In the current game layout that spacer measured:

```text
24 px
```

A new `/Script/UMG.Spacer` is created and assigned the same size/layout values.

This gives us:

```text
EDIT   DELETE   ACTIVATE   SHARE
                       ↑
                same native rhythm
```

rather than a hand-tuned approximation.

That pattern generalizes nicely:

> When adding to an existing row, inspect and reuse the game's spacing rather than inventing your own.

It is more likely to remain visually consistent across resolutions and future changes.

---

# 12. CommonUI button callbacks can still be running after your hook fires

This produced one of the nastier late-development crashes.

Character Share hooks:

```text
CommonButtonBase:HandleButtonClicked
```

When Share was clicked, the mod immediately:

1. encoded the character;
2. created a popup;
3. pushed the popup into CommonUI.

The entire export completed successfully according to the log.

Then the game crashed.

The important realization was that **our hook firing did not mean the native button click had finished**.

`WBP_BoundActionButton` still had additional native/CommonUI work to perform after `HandleButtonClicked` returned.

By opening another CommonUI layer inside that callback, we were changing focus and screen-stack state while the original button was still processing itself.

The fix was to defer our action very slightly:

```text
button click
    ↓
record intended Share action
    ↓
return to native CommonUI
    ↓
native click finishes
    ↓
next game-thread tick
    ↓
perform export/open popup
```

That resolved the reproduced Share crash. It does not establish that all click-related crashes share that cause.

---

# 13. Apply the same rule consistently

Much later, during repeated error-code testing, Import produced a very similar crash.

The log stopped immediately after:

```text
Databank button clicked: IMPORT
IMPORT SESSION started
```

before the import popup was created.

We applied the same pattern:

> Do not open another CommonUI screen directly from inside a native button's click processing.

Import now also queues its action and opens the dialog on the following game-thread tick.

This gave us one of the most reusable patterns from the project:

```text
Native button event
      ↓
Mod sees event
      ↓
Queue work
      ↓
Native event returns
      ↓
Owned, cancellable game-thread delay
      ↓
Create/change CommonUI screens
```

For anything that opens or closes UI, deferring the operation is safer than doing everything synchronously from a click hook. The same applies to rebuilding a folder or removing the button that received the click. The diagrams describe ordering, not a guaranteed one-tick API contract.

**Important distinction:** running on the game thread and running after the native event has unwound are separate requirements. Do not assume that a game-thread dispatch primitive necessarily supplies the required deferral. Colors+ uses tracked delayed actions, then revalidates the current context inside the callback. A fixed delay is not a substitute for checking popup retirement or target readiness.

---

# 14. Native popup dialogs are worth reusing

Character Share originally needed several dialog types:

```text
Share code display
Import text entry
Duplicate choice
Rename text entry
Success/error notice
```

Instead of creating a new custom popup framework, we reuse:

```text
WBP_GenericPopupMessage_Small_C
```

This gives us a popup already integrated into:

* the CommonUI stack;
* game focus;
* controller navigation;
* game visual style;
* input blocking;
* screen scaling.

Character Share then adjusts the title/body/input field and replaces the actions with suitable native-style buttons.

This was much more reliable than building an independent overlay.

---

# 15. Reused popup instances must be reset

An interesting behavior of Zero Company's popup system is that the same popup object can be reused for several consecutive dialogs.

For example:

```text
Import
    ↓
Duplicate detected
    ↓
Rename
    ↓
Success
```

may all involve the same underlying popup widget being configured repeatedly.

Any UI elements injected by the mod therefore need to be removed/reset before configuring the next dialog.

Character Share explicitly clears its injected slots before each popup setup.

Otherwise stale buttons or state from the previous dialog can leak into the next one.

---

# 16. Let the native popup retire before acting on its result

A similar CommonUI timing rule applies when closing a dialog.

When a popup action is clicked, immediately creating the next popup can collide with the old one still being on the CommonUI stack.

The robust sequence became:

```text
User chooses RENAME
        ↓
Native popup begins closing
        ↓
Character Share records "duplicate_rename"
        ↓
Wait until the current dialog has retired
        ↓
Dispatch duplicate_rename
        ↓
Open Rename dialog
```

Logs during normal operation therefore contain messages such as:

```text
Popup TopNav click
Popup TopNav dispatch after native close
```

or, for native dialog results:

```text
Native dialog result captured
awaiting native stack retirement

Native dialog retired from CommonUI

Native dialog dispatch after retirement
```

This prevented popup chains from fighting the CommonUI layer stack.

---

# 17. A plain TopNav button turned out to be a very safe action control

During debugging we tried several button types.

`WBP_CharacterDataBank_TopNavButton_C` proved particularly reliable for dialog actions.

It was successfully used for:

```text
IMPORT
CANCEL
OVERWRITE
RENAME
OK
CLOSE
```

Because it already belongs to the Character Databank UI family, it also visually fits the surrounding interface.

One potentially useful pattern for future mods is therefore:

> For a modal action where you do not need the complexity of `WBP_BoundActionButton`, a native TopNav-style button may be the safer choice.

The Bound Action Button remains useful when matching a specific existing action row, but it carries more internal CommonUI behavior.

---

# 18. Keep callback routing separate from the widget itself

Character Share does not put a unique UE4SS hook on every individual button.

Instead, it registers a general CommonUI button click hook and maintains a mapping:

```text
runtime widget identity
        ↓
Character Share action
```

Conceptually:

```text
SomeWidget123 → databank_import
SomeWidget456 → databank_share
SomeWidget789 → duplicate_rename
```

The hook sees a click, determines whether that widget belongs to Character Share, and dispatches the corresponding action.

This was easier to manage than installing large numbers of separate native hooks.

It also made stale-widget cleanup important, which is why runtime screen generations and identity tracking became useful.

---

# 19. Assume widget internals can be missing

Another recurring lesson was not to assume that every child shown in a dump will exist in every instance.

At different points we encountered things such as:

```text
SizeBox_0 not present
expected helper/widget not available
different child counts
```

UI code should therefore be defensive.

Instead of:

```lua
widget.SizeBox_0:SetWidthOverride(...)
```

the safer pattern is conceptually:

```text
find expected child
    ↓
exists?
    ├─ yes → configure it
    └─ no  → skip/fallback/log
```

A missing decorative child should not prevent the entire mod UI from loading.

---

# 20. Object dumps are extremely useful, but live behavior matters more

UE4SS ObjectDump information was invaluable for learning widget structure.

It revealed fields and functions such as:

```text
ButtonOrientation
ButtonSize
ButtonType
ButtonSwitcher
SelectedButton
ApplyStyle
```

and helped identify where native spacers and action buttons lived.

But a dump tells you what exists, not necessarily **when it is safe to touch it**.

Several things that looked reasonable from static inspection caused runtime instability because the widget was in the middle of a CommonUI transition.

So a good workflow became:

```text
ObjectDump
    ↓
Understand structure
    ↓
Minimal runtime probe
    ↓
Log values without changing anything
    ↓
Only then modify
```

The Share orientation fix is a good example.

We first added a diagnostic build that logged the live native Edit/Delete/Activate state and the freshly-created Share state.

That showed clearly:

```text
native Edit:
orientation = Right

fresh Share:
orientation = Left
```

Once we knew the actual difference, the fix was tiny.

---

# 21. Diagnostic builds are better than guessing

A number of bugs were solved fastest by creating deliberately small "probe" builds.

Instead of changing five things and asking whether the UI looked better, we would log:

* class name;
* object identity;
* parent;
* child count;
* active switcher state;
* button orientation;
* measured width;
* selected widget;
* whether the page had been observed previously.

This produced actionable evidence.

For UI modding especially, a useful diagnostic log entry is more valuable than pages of speculative code changes.

The general pattern was:

```text
observe
→ measure
→ reproduce
→ change one thing
→ validate
```

rather than continually rebuilding the UI until something happened to work.

---

# 22. Log lifecycle boundaries, not just errors

The most useful Character Share logs were usually not exception messages.

They were breadcrumbs such as:

```text
Databank candidate observed
Databank stabilized
UI integration started
Share installed
Share clicked
Share queued
Share dispatched
Popup opened
Popup click
Popup retired
Next action dispatched
```

When a native crash occurs, Lua does not necessarily get a chance to print an error.

The **last successful breadcrumb** narrows the interval where execution stopped; it does not by itself prove the cause. A crash can occur after a call returns or during native work that the call triggered.

These breadcrumbs helped us investigate distinctions between:

```text
codec failure
```

from:

```text
popup creation failure
```

from:

```text
native button still unwinding
```

from:

```text
screen entry lifecycle crash
```

For UE4SS UI mods, detailed lifecycle logging during development is extremely worthwhile.

Colors+ extended this with paired `BEGIN` and `RETURN` records around individual native calls, correlated by runtime generation, trace window, and call ID. A missing return identifies a suspect boundary, not conclusive causation. Record Lua errors separately, and bound tracing by both duration and call count to avoid flooding logs during slider updates.

---

# 23. Avoid modifying native controls just to make your new control match

One early visual approach restyled the existing Edit/Delete/Activate buttons so they matched Share.

Technically that solved one appearance mismatch.

It was also the wrong direction.

A mod adding one button should not need to alter three unrelated native buttons.

The better solution was:

```text
preserve native UI
        +
make new control match native UI
```

This reduced the amount of game state we touched and made regressions much easier to reason about.

That principle should apply broadly:

> Modify only what your mod owns unless changing the native control is actually the feature.

---

# 24. A useful hierarchy for UI modifications

After all of the iterations, I'd roughly rank Zero Company UI modification techniques from safest to riskiest like this:

| Approach                                                             | Relative risk |
| -------------------------------------------------------------------- | ------------- |
| Read properties on freshly resolved, validated widgets in a stable context | Lower, not risk-free |
| Create one native-class widget owned by a stable current screen      | Lower; construction scale matters |
| Append one control to a stable action panel                          | Lower; not a license for per-row construction |
| Change properties on your own widget                                 | Low           |
| Apply render translation to your widget                              | Low           |
| Call the widget's own style/update functions                         | Low–moderate  |
| Change properties on native widgets                                  | Moderate      |
| Manipulate native WidgetSwitcher internals                           | Higher        |
| Reorder/remove existing native children                              | High          |
| Clear and reconstruct native CommonUI panels                         | Very high     |
| Modify CommonUI layers while a click/close event is still processing | Very high     |

That is not an Unreal-wide law; it describes relative risk observed during Character Share development, qualified by the later Colors+ work. Every row assumes appropriate thread, lifecycle, and ownership checks.

Even reads can touch stale native objects. `pcall` catches Lua errors; it does **not** protect against native access violations. Reacquire and validate targets, minimize calls during transitions, and do not treat successful earlier access as a lifetime guarantee.

---

# 25. Recommended pattern for adding a button to an existing Zero Company screen

If starting another UI mod tomorrow, I would use approximately this process:

```text
1. Find the screen/widget class with ObjectDump or runtime logging.

2. Enter the screen normally and record its actual runtime tree.

3. Identify the native widget you want your control to resemble.

4. Wait until the screen has stabilized before modifying it.

5. Create a widget using the game's native class where possible.

6. Add only your own widget; avoid removing/reordering game children.

7. Copy useful layout/style information from the nearby native controls.

8. Use public properties + ApplyStyle/Update functions rather than
   manipulating internal switchers.

9. Route button clicks through a small action mapping.

10. If the action opens/closes CommonUI, defer execution until the
    current native click has unwound.

11. If chaining dialogs, wait for the previous dialog to retire before
    pushing another.

12. Track runtime screen identity so reusable screens do not receive
    duplicate controls.

13. Log every important lifecycle boundary while developing.

14. Own and cancel delayed work; retire callbacks and mappings when
    their runtime generation or editing context ends.

15. Test hover, selection, cancellation, timeout, screen round trips,
    and object replacement independently.

16. For editing tools, test Apply, native Save/reopen, and full-restart
    persistence separately. They are not equivalent.

17. Once stable, remove or disable probe/debug instrumentation that is
    no longer useful. Keep useful lifecycle and failure records.
```

That pattern accounts for nearly every major failure we encountered.

---

# 26. What Character Share specifically taught us

The UI work started out looking fairly straightforward:

> Add an Import button, add a Share button, and show a few dialogs.

The difficult part was not drawing the controls.

It was learning how the game expects its interface to behave.

The problems we encountered included:

* character selection failing only on first entry;
* controls appearing correctly but interfering with CommonUI state;
* unreliable `InsertChildAt`;
* duplicated controls after screen re-entry;
* a cloned button having the opposite orientation from its native neighbor;
* spacing that looked subtly wrong despite using the same widget class;
* crashes caused by inspecting transient button/screen state;
* crashes occurring *after* a Share export had completely succeeded;
* crashes while repeatedly opening Import;
* popup actions firing before the previous popup had left the stack.

Almost none of those were traditional Lua errors.

They were **UI lifecycle errors**.

The eventual implementation became reliable because it consistently follows four rules:

> **Preserve native widgets.**
> **Wait for UI state to stabilize.**
> **Let native events finish before changing CommonUI state.**
> **Use the game's own widget classes and styling logic whenever possible.**

Those are probably the most valuable lessons to carry into future Zero Company UI mods.

---

# 27. Areas we still have not explored deeply

There are parts of Zero Company's UI system that Character Share did not need to investigate enough to document confidently.

For example, we have not done extensive work with:

* creating entirely new CommonActivatableWidget screens;
* adding permanent tabs to major game interfaces;
* drag-and-drop;
* ListView entry creation and recycling;
* entirely custom tooltip systems (native tooltip reuse has been explored);
* gamepad navigation graphs for entirely custom screens;
* Slate-level rendering;
* deep integration with shipping HUD/combat widgets (a separate combat-log overlay has been tested; see section 48);
* responsive custom layouts across every aspect ratio.

So I would keep this guide explicitly labeled as a **starting knowledge base**, not a complete UI SDK.

But for the very common case of:

> "I want to add controls and dialogs to an existing Zero Company menu"

we now have a pretty solid foundation.

---

# 28. Give each tool its own lifecycle

**Verified behavior in Colors+ testing:** the Color Picker closes when its customization context ends, while the SWZC Dev Panel can remain open across the Customization–Databank transition.

These windows have different responsibilities.

* The picker owns a preview for a particular selection. A slot/page change can invalidate that preview.
* The Dev Panel is a general-purpose launcher. Its continued visibility does not authorize an action against the previous screen.

Validate each Dev Panel action against the current context at dispatch time. Keeping the launcher open is useful for testing transitions; closing every mod window on every transition is not a universal safety requirement.

Similarly, a native swatch hover, a committed swatch selection, a return to the radial selector, and departure from the creator are different events. Decide explicitly which ends a draft preview, which replaces an applied edit, and which merely changes what is displayed.

---

# 29. Own delayed work, hooks, and runtime generations

**Implemented pattern in Colors+:** keep a registry of named delayed actions and hook registrations. Replacement work cancels the previous action for that purpose. Each callback checks that its runtime is still active before doing anything.

Useful ownership information includes:

* runtime generation;
* editing session or preview identity;
* action key and cancellation handle;
* registered hook identifiers;
* the source owner and slot the operation expects.

On retirement, disable old callback routing, cancel owned work, and unregister owned hooks. Cleanup failures should remain visible and tracked rather than being logged as successful teardown.

Do not retain a native object wrapper merely because a timer will need it later. Retain sufficient scalar identity/context information to reacquire and validate the target when the timer runs.

**Unresolved reload limitation:** Reload All Mods is not equivalent to closing and reopening a window. Testing with both DP and CP open produced a hang/crash even though other tested combinations worked. Some current skin operations explicitly refuse reload while an override is active. Do not advertise general reload safety from a successful isolated test; use a full restart when the current test protocol requires it.

---

# 30. Separate preview, Apply, and native Save

**Verified behavior:** these are distinct layers, not interchangeable descriptions of “the color changed.”

| Layer | Meaning | What must be tested |
| --- | --- | --- |
| Live preview | Temporary visual change | Cancel, timeout, selection change, context exit |
| Editor Apply | Edit retained for the current editing context | Hover restoration, radial round trip, replacement selection |
| Native Save | State accepted by the game's save flow | Reopen, then separately a full process restart |
| Display override | Temporary state on a displayed material instance | Material recreation and reapplication/restoration |

The skin investigation demonstrates the difference particularly well. In the labeled v0.2.51 snapshots:

* custom source RGB survived native Save and reopening the character, including source-fragment recreation;
* the displayed material also contained that RGB;
* the temporary displayed-material `Enable Tinting` override returned from 1 to 0.

Thus an unchanged-looking skin did not mean the RGB had been lost. The rendering switch was missing. Those specific captures did **not** establish full process-restart persistence.

Likewise, a source scalar that reads 1 before and after saving does not prove that it was serialized if the stock preset also supplies 1.

Inspect source state and displayed state independently. Property flags and generated header dumps help identify candidates, but do not establish the game's custom save/copy behavior. Generated empty implementation stubs are not the native implementation.

---

# 31. Restore only state you still own

**Implemented ownership pattern:** record original values and validated target identities before the first write. On cancellation or restoration, reacquire the target and confirm that it is still the object/state owned by the operation.

Do not overwrite:

* a later native swatch selection;
* an external change;
* a replacement slot or material instance;
* a new editing session that happens to use the same screen.

A recovery record should distinguish a successfully restored target from one that was replaced and deliberately left untouched. If recovery cannot be verified, report that explicitly and block further conflicting edits.

Colors+ also separates source-edit ownership from display availability. During a radial-selector round trip, the preview display may temporarily be unavailable or replaced while the source edit remains valid. That is not sufficient reason to erase the applied source RGB.

Use bounded rendering retries, and resume on a relevant context event rather than polling indefinitely at full intensity. Continue validating source ownership independently.

This is not a recommendation to invent a second save/discard system when native behavior already handles the tested source edits correctly.

---

# 32. Default selection may require a native handoff

**Project-specific workaround, verified in the tested Colors+ flow:** opening from Default temporarily selects an existing non-default swatch using the native selection flow, then previews the custom color.

That selection is a real editor-session change, not a harmless visual highlight. Record the previous selection before making it.

Cancellation and timeout restored Default in testing. Native hover/selection and departure from the relevant customization context must also be handled deliberately; do not force the temporary selection back after the player has made a newer intentional choice.

This technique is specific to the customization flow we tested. “Default” may represent different things in another slot or widget, so do not assume every default entry exposes a writable color fragment.

---

# 33. Mock tests do not validate native argument conversion

**Unresolved experiment: v0.2.52 skin target probe.**

The probe attempted to change a per-character scalar's material target from Outfit to the observed five-mesh layout, while preserving the parameter name, material names, scalar value, and RGB.

The setter returned, but the next validation failed:

```text
SET BEGIN | target=meshes
START FAILED | Skin material parameter changed
RESTORE FAILED | Skin material parameter changed
```

The probe never reached its verified active state. This is **not** evidence that a successfully installed target change has no visual effect.

Local mocked tests passed, but they did not prove that the native call transferred the structured argument as intended. The exact cause remains unresolved; do not present a particular marshalling explanation as established.

Lessons for future probes:

1. Verify every relevant field after a structured write, not just whether the call returned.
2. Preserve recovery information before writing.
3. Account for partial or unexpected mutation when designing restoration.
4. Do not let a strict normal-operation validator become the only path to recovering a partially changed target.
5. Keep recovery narrowly identity- and ownership-checked; do not bypass safeguards by writing to arbitrary objects.
6. If restoration cannot be verified, stop the experiment and avoid saving that session.

The v0.2.52 recovery path did not successfully handle the observed state. It needs repair before this probe becomes a reusable example. A changelog describing intended partial-failure recovery and passing mocks does not override the failed native observation.

---

# 34. Diagnostics must match the actual Lua runtime

**Verified diagnostic failure:** the first per-call tracing implementation used global `unpack`. It worked in the local test environment but was unavailable in-game, so the tracing code itself prevented the picker from opening.

The compatibility fix resolves the available unpack function explicitly:

```lua
local unpack_values = assert(table.unpack or unpack, "Lua unpack function unavailable")
```

When wrapping calls, also preserve the number of return values so nil-containing results are not silently changed.

More broadly:

* Test diagnostics in the actual game runtime, not only the local runner.
* Keep trace windows bounded by duration and call count.
* Pair native-call entry and return records.
* Identify runtime/session generations in logs.
* Distinguish Lua exceptions, failed validation, and missing native returns.
* Make clear whether a probe reached its active phase before interpreting a visual result.

Instrumentation should help isolate a failure without becoming a new unbounded workload or changing the behavior being investigated.

---

# 35. Let the native manager own Databank data

**Implemented pattern in Enhanced Databank:** use the native character-pool manager as ownership authority, the Databank ViewModels as mutation/rendering interfaces, and widgets as presentation.

```text
BitReactorCharacterPoolManager.CharacterPools
    → current pool types, names, and GUID membership
    → resolve matching typed ViewModels
    → render mod-created custom folders
    → reconcile the shipping Default presentation without regenerating it
```

`CharacterPoolName`, `CharacterPoolType`, and the GUID-keyed `Characters` map describe current ownership. A visible row, pool label, or cached ViewModel can disagree with that authority after a move or deletion.

The current native mutation split is:

| Operation | Surface used by Enhanced Databank |
| --- | --- |
| Validate a folder name | Databank VM `IsNewPoolNameAvailable` |
| Create a folder | Databank VM `CreatePool` with the captured category type |
| Rename a folder | Databank VM `RenamePool` |
| Delete an empty custom folder | Databank VM `DeletePool` |
| Move a character | Pool manager `MoveCharacterToAnotherPool` using the real GUID value |

These are observed project entry points, not interchangeable APIs. An earlier move through `BrunoCharacterDatabankViewModel.MovePoolCharacterToPool` moved manager ownership but removed the source VM without supplying the expected destination VM. The follow-up convergence loop repeatedly rebuilt folders and eventually crashed. The current implementation uses the manager-direct move and coalesced reconciliation.

Before mutation, re-read the character GUID, source pool, destination, category, and—when deleting—authoritative emptiness. Protect the default Player Created pool. Do not trust the state captured when the dialog opened.

Observe native mutations too: current hooks include `DeletePoolCharacter` and `RemoveCharacterFromPool`, alongside create/rename/delete/move operations. Their job is to request a later refresh. A deletion notification should not capture the deleted UObject for subsequent use.

Character Share v1.0.3 applies the same authority rule to import conflicts and overwrite targets. Deduplicate candidates by **saved character GUID**, not ViewModel identity: a moved character's stale Default copy is not a second character. Different GUIDs with the same name remain real conflicts. Ignore deleted GUIDs and refuse overwrite when identity, ownership, or the owning pool VM cannot be verified. Snapshot reads retain scalar values rather than long-lived candidates. See the [Character Share changelog](../../CharacterShare/CHANGELOG.md).

The mod maintains no parallel ownership database and does not rewrite save files. Native empty-folder cleanup can remove a folder after its last character leaves; distinguish that from a folder whose UI disappeared while the manager still owns it.

**Unresolved save-filename request:** a native folder rename is not proof that the physical `.sav` filename changes. `GetSaveFileNameForPool()` and `GetSaveSlotName()` are useful observation points, but the generated dumps do not reveal the naming/discovery implementation. Renaming files to `CharacterDatabank_<folder_name>.sav` remains an investigation, not a verified recipe.

Sources: [pool authority](../src/Enhanced%20Databank/Scripts/pool_authority.lua), [mutations](../src/Enhanced%20Databank/Scripts/pool_mutations.lua), and [lifecycle hooks](../src/Enhanced%20Databank/Scripts/lifecycle.lua).

---

# 36. A selected UI object is not necessarily the authoritative character

**Observed failure and implemented workaround:** the detail panel, selected row, generic MDVM proxy, and typed pool-character VM are different representations.

The detail `CharacterBankAuxVM_C.CharacterVM` is a `BrunoCharacterViewModel`; its pool-data ID did not resolve the intended manager key. Reading the selected row through `SelectedCharacterButton` found the right conceptual binding, but its generic proxy exposed an opaque GUID. Matching that proxy against typed pool entries by UObject identity also failed: the wrappers had different identities.

Enhanced Databank therefore resolves the selected physical row at action time, then uses the appropriate bridge:

* **Mod-generated custom folder:** map its row position to the exact ordered typed VM list supplied when that folder was rendered.
* **Shipping Default pool:** resolve the rendered `BitReactorRichTextBlock_73` name to a uniquely identified typed VM, then obtain its GUID.

The second path is necessary because native character creation can prepend the typed VM while appending the physical widget. Array index equality is not a reliable join for shipping rows.

The rendered name is only a constrained bridge. It is not permanent identity or ownership authority. Missing names or one name mapping to different GUIDs must refuse a Move action. Duplicate transient wrappers with the same name **and the same GUID** can be deduplicated safely within this resolver. The resulting GUID still has to exist in current manager ownership.

Keep the exact generated widget field behind a helper so a game update can change the bridge without rewriting action logic.

Source: [row identity helpers](../src/Enhanced%20Databank/Scripts/pool_authority.lua).

---

# 37. Reconcile shipping row visibility without rebuilding shipping rows

**Implemented in v1.0.1–v1.0.2; regression-tested with mocked engine boundaries:** preserve the shipping Default pool and its row objects. Do not replay its generated `PoolCharacterViewModels` row-generation handler, detach rows, or rebuild its stack.

The visibility problem had several forms:

* moved or deleted characters reappeared because a stale native ViewModel still described them;
* a new character inherited a reused row’s `Collapsed` state;
* after emptying Default and moving characters back, multiple physical rows represented the same GUID;
* a delayed visibility recovery could run after a second move changed ownership again.

The current reconciliation resolves physical rows using section 36, reads current manager authority, and chooses **one physical row per unambiguous authoritative GUID**. Prefer an already-visible native row over collapsed stale copies. Restore the chosen authoritative row to `Visible`, even if its hidden-state record belonged to a previous occupant; collapse known stale/non-authoritative rows and resolved duplicate copies.

When identity is unreadable or ambiguous, **leave native visibility alone**. This deliberately favors preserving a potentially valid character over hiding the wrong row. The same ambiguity must block a mutation, because a Move needs an exact target.

Immediate moves, native refreshes, and delayed recovery share reconciliation. A delayed callback must re-read current ownership; it must not blindly reveal the destination recorded by an earlier move.

This is a narrow exception to “modify only your own widgets.” It changes the visibility of a safely resolved shipping row to match native authority while retaining the game’s structural ownership.

Sources: [reconciliation](../src/Enhanced%20Databank/Scripts/databank_ui.lua), [move recovery](../src/Enhanced%20Databank/Scripts/pool_mutations.lua), and [regression scenarios](../tests/refresh_test.lua).

---

# 38. Categories belong to the operation, not whichever tab is now visible

**Implemented in Enhanced Databank v1.0.2:** humanoid Custom Characters and Astromechs use the same page/pool widget families but different data bindings.

| Binding | Custom Characters | Astromechs |
| --- | --- | --- |
| Master page field | `OtherCharacterList` | `AstromechCharacterList` |
| Default pool type | `4` | `2` |
| Player-created folder type | `5` | `3` |
| Default VM property | `DefaultCustomCharacterPoolViewModel` | `DefaultAstromechCharacterPoolViewModel` |
| Custom-folder VM array | `CustomCharacterPoolViewModels` | `AstromechCharacterPoolViewModel` |

The Astromech array name is singular. Do not generate reflected names by guessing a naming convention. The other observed pool types, `0` and `1`, belong to Hawks categories and are outside this implementation’s folder support.

Capture the category when opening a folder or Move dialog. Carry it through native popup retirement and deferred dispatch. Revalidate the relevant category’s live pools at execution time, even if the user switched tabs meanwhile. Never redirect the pending operation to the newly visible category; cross-category moves are rejected.

The renderer keeps one active page’s callback registry, clears its page-specific routing when switching, and adopts surviving controls on return. This supports both pages without assuming their widgets are shared.

The source and mocked tests establish these bindings and category guards. The recorded implementation task explicitly left full in-game Astromech rendering and restart persistence for validation; do not promote the feature announcement into proof of that entire test matrix.

Sources: [category bindings](../src/Enhanced%20Databank/Scripts/categories.lua) and [category tests](../tests/astromech_test.lua).

---

# 39. Idempotent installation must survive failed widget renaming

**Reported failure; implemented v1.0.3 fix:** Create Folder buttons multiplied when returning to a page. Create New also became progressively narrower.

The Lua registry was reset on a tab switch, but the previous button remained physically attached. The installer searched for its requested marker name. A Blueprint clone could retain its engine-generated UObject name when renaming was unavailable, so the name search missed it and installed another copy.

The current adoption sequence is:

1. Use the current registered control if it is still valid and attached.
2. Search the page for the intended button marker.
3. If absent, find the mod-owned `EnhancedDatabank_CreateFolderOverlay` and inspect its children for the expected native button class.
4. Re-register that actual button identity, recover its glyph references, and restore normal visual state.
5. Only create another control when no owned existing control is found.

Searching a known owned overlay matters. An unrestricted search for the button class could adopt the game’s Create New button or another mod’s control.

Adoption restores behavior as well as appearance: callback routing, hover routing, parent references, and icon state belong to the new runtime. It must not subtract another button-width from the shared layout.

The regression suite covers failed clone rename, repeated tab switches, a fresh Lua context with surviving widgets, Character Share present/absent, and append failure followed by retry. Those tests establish local idempotence; they cannot simulate every native lifetime transition.

Sources: [Create Folder installer](../src/Enhanced%20Databank/Scripts/folder_ui.lua) and [adoption tests](../tests/create_folder_control_test.lua).

---

# 40. Mods sharing a row need an explicit layout agreement

**Implemented Character Share / Enhanced Databank pattern:** use a flat action row with separate hitboxes:

```text
Create New | compact Import | compact Create Folder
```

Recognize the other mod’s owned row and width wrapper rather than nesting a new HorizontalBox inside the remaining Create New space. Current Enhanced Databank recognizes `CharacterShare_CreateImportRow`, `CharacterShare_CreateNewWidth`, and the older `CharacterShare_CreateNewHalf` wrapper.

Measure the available layout, reserve the new control’s width and native gap once, and keep each mod’s markers distinct. A fallback width is a compatibility fallback, not evidence of the actual viewport geometry.

Installation also needs failure ordering: build and successfully append the folder control **before** shrinking Character Share’s Create New wrapper. If attachment fails, a retry must not consume another slice of width. Adoption must leave the already-allocated width unchanged.

This qualifies the earlier “never wrap native controls” advice. The projects use a narrowly scoped, coordinated wrapper for the top Create New area. That success does not authorize wrapping or rebuilding shipping character rows or their navigation stack.

Test both mod installation orders, each mod alone, both Databank categories, re-entry, reload, and failed-install retry. Confirm the visible control and pointer hitbox agree. A screenshot alone does not validate navigation or hit testing.

Source: [cooperative row implementation](../src/Enhanced%20Databank/Scripts/folder_ui.lua).

---

# 41. One selected-character action proved safer than per-row actions

**Observed development results:** several per-row Move experiments crashed during cold Databank entry, including full CommonUI clones, raw UMG Buttons with delegate routing, and lightweight row-owned glyphs. In one recorded run, four stock-row decorations completed and the fifth did not.

The no-per-row-control baseline completed cold entry. The chosen design places one Move action in the selected character’s native detail action row, following Character Share’s single-action pattern.

The lesson is about the tested construction path and lifecycle, not a universal maximum widget count. “Native class,” “lightweight,” and “wrapped in `pcall`” do not establish that mass construction during activation is safe.

Click handling produced another useful distinction:

* A decorative SizeBox can show a tooltip without owning the click.
* Its click can reach the native character-row button and open the editor.
* Observing `CommonButtonBase:HandleButtonClicked` does not by itself suppress the original row action.
* A successful raw-button/delegate experiment elsewhere does not validate construction inside this fragile row-generation path.

Keep glyphs hit-test-invisible when a real native button is supposed to own input. Use existing CommonUI hover/unhover events for icon state instead of a fast recurring row-hover poll. Do not replay per-row generated context handlers just to repair a tooltip: the later Enhanced Databank renderer explicitly disabled those replays after stability failures.

Sources: [selected Move control](../src/Enhanced%20Databank/Scripts/selected_move_button.lua), [current renderer](../src/Enhanced%20Databank/Scripts/databank_ui.lua), and the historical [Databank investigation](../Zero_Company_Databank_Modding_Guide.md).

---

# 42. Scheduling semantics are part of correctness

**Observed failure and implemented migration:** repeated Move dialogs produced a UE4SS failure containing:

```text
Lua::Registry::get_function_ref: Ref was not function
EXCEPTION_ACCESS_VIOLATION reading address 0x2
```

The next dialog’s delayed UI work was pending; the manager move had not started. This was consistent with the legacy callback-registry/re-entry problem investigated at the time. It is not evidence that every crash with UE4SS frames has that cause.

Enhanced Databank replaced nested `ExecuteWithDelay` / `ExecuteInGameThread` work with the installed runtime’s owned delayed game-thread actions. Its declared requirements include `MakeActionHandle`, `ExecuteInGameThreadWithDelay`, `RetriggerableExecuteInGameThreadWithDelay`, cancellation, handle validity/activity queries, and hook unregistration. Check the actual installed runtime; the historical UE4SS version label alone is insufficient.

Three details matter beyond choosing an API:

1. **Retriggering retains the first callback in the tested contract.** Resetting an active refresh handle’s timer does not replace that closure. A new closure capturing a newer generation can leave the retained old closure invalidated, so the only pending refresh does nothing. Current code schedules one stable callback and stores the latest reason/context separately for it to read when it fires.
2. **Refreshes can be requested during a render.** Record one coalesced follow-up rather than entering another Blueprint rebuild. A coalesced follow-up is not the old unlimited “rebuild until VMs converge” loop.
3. **All deferred paths need ownership.** Track refresh, hook-install retries, initial catch-up, popup work, and repaint actions—not just user-facing previews. Cancel startup retries when activation-owned rendering takes over.

Enhanced Databank checks explicitly captured UObjects immediately before a delayed callback. Colors+ goes further in many paths by retaining scalar identities and resolving exact live targets on execution. Validity checks reduce some stale-reference failures but cannot prove context ownership or contain native faults.

Sources: [owned actions](../src/Enhanced%20Databank/Scripts/actions.lua), [refresh scheduler](../src/Enhanced%20Databank/Scripts/databank_ui.lua), and [scheduler tests](../tests/reload_runtime_test.lua). These describe the project’s implementation and tested contract, not a version-independent UE4SS API tutorial.

---

# 43. Reload-safe architecture needs both retired callbacks and surviving-widget adoption

**Implemented in Enhanced Databank:** a runtime registry retains both IDs returned by hook registration, guards every callback with a live-runtime flag, and owns delayed handles. Teardown retires routing, cancels work, unregisters hooks, closes the old log, and arranges owned UI cleanup on the game thread.

A partially successful hook installation must be retryable without registering the already-installed paths twice. Failed hook cleanup must remain recorded and block replacement registrations. Versions that never retained the old hook IDs need a full restart when upgrading; a new registry cannot reconstruct those missing IDs.

Keybind and console registration use persistent dispatchers whose handler is replaced for the current runtime. Re-registering the same key every reload can otherwise accumulate callbacks. The optional current-mod delayed-action sweep supplements tracked cancellation; it does not replace ownership or solve surviving-widget state.

Reload is two distinct problems:

```text
old Lua callbacks must stop
                +
old native widgets may still exist
```

Retiring callbacks without adoption leaves visible but inert controls. Adoption without retirement can route one click through multiple runtimes.

The module split also addressed Lua’s main-chunk local-variable limit. Factories receive one explicit `ctx`; all namespaces exist before initialization, callback slots are filled before hooks start, and mutable shared fields are read through the current context instead of copied into stale locals. Reload invalidates the factory cache and builds a fresh context.

Character Share uses the same owned-runtime approach. Its recorded contract distinguishes same-state reload, which can resume a known open Databank, from a full Lua-state restart, after which the Databank must be reopened through its menu to rebind controls. Installation must ship all runtime modules, not only `main.lua`.

This architecture is exercised by local bootstrap/reload tests. It does not supersede Colors+’s unresolved Reload All Mods failures or authorize reloading with an active override that its protocol requires restoring first.

Sources: [runtime registry](../src/Enhanced%20Databank/Scripts/hook_registry.lua), [module architecture](architecture.md), and [bootstrap tests](../tests/module_bootstrap_test.lua).

---

# 44. Discover the active palette through ownership, not a global widget scan

**Colors+ findings:** a visible-looking color grid and the auxiliary “current slot” can disagree. Captures showed a color selector while `CurrentCustomizationSlotVM` still named its parent Face Shape, Hair Style, Tattoo Style, or Lipstick Style. Refusing the Style fragment was not evidence that the player opened the wrong selector.

Global palette discovery also found multiple matching widgets whose UWidget parent chains did not reach the active page. A failed parent-chain walk is not sufficient to choose another arbitrary matching grid.

The implemented resolver starts from the exact active item page, follows the active `SlotWidgetSwitcher` child, verifies the page’s known panel reference, and traverses only that panel’s supported lists. It checks slot tags, game-instance/class context, equipped palette membership, and ambiguity, with explicit depth/node/child limits.

For a simple panel, the displayed `CurrentSlotTag` can resolve an exact child beneath `RootCustomizationSlotVM`; the auxiliary slot must belong to the same owned tree. Combined/list panels retain stricter exact-current-slot matching because several palettes can be visible. Discovery must not “repair” the auxiliary selection by writing to it.

**Verified checkpoint:** the user confirmed the v0.2.36 displayed-slot tests. Hair root used `.Color.Secondary` and tips `.Color.Primary` in the capture; labels must not be used to guess which tag to edit.

Later graph observations further qualified the resolver. Shared references are not automatically distinct candidates, and a repeated node is not necessarily a fatal layout defect. v0.2.44 records identities before descending, validates repeated nodes/tags, skips already-visited subtrees, and continues other branches to detect genuinely competing candidates. Do not remove ambiguity, ownership, or traversal bounds merely to tolerate a cycle.

Sources: [palette investigation](../../Colors%2B/docs/appearance-palette-testing.md), [displayed-slot test results](../../Colors%2B/docs/displayed-color-slot-testing.md), and [Colors+ changelog](../../Colors%2B/CHANGELOG.md).

---

# 45. A color fragment, a displayed material, and visible color are different evidence

The save investigation in section 30 is one instance of a broader distinction:

```text
source customization data
    → native preview/data handoff
    → linked displayed character
    → current mesh/material instances
    → effective visible shader result
```

A successful source setter does not prove that the visible character follows that source. Colors+’s preview work first established the native stock-swatch handoff, then verified the linked display before interpreting custom-color writes. After installation, setters, or refresh, reacquire the exact owned target: native calls can copy or replace fragments and preview links synchronously.

When extending support, preserve the whole validated fragment bundle. Tattoo work introduced multiple mesh targets; skin includes color, gameplay-tag/race, and tint-enable scalar context. Validate each expected target, including an explicitly absent optional mesh, instead of checking only the first mesh. Do not recolor a shared stock preset or modify companion fragments merely because the color fragment is writable.

Other recorded lessons:

* Convert picker sRGB values to the linear RGB representation expected by the tested fragments; preserve the intended alpha. Keep UI color values and native values distinguishable in logs.
* A real FName round trip changed `MI_EyeLeft` to `MI_Eyeleft`. Colors+ handles case-only differences for a narrow whitelist of reflected eye slot/parameter names. It does not lowercase arbitrary UObject identities or accept suffix/name changes.
* Eye vector writes changed Dark Brass and Albino visibly. Light Brown and Rodian Star Blue accepted vector writes/readback and restoration without the same visible effect. Later saturation/brightness scalar effects and restoration were confirmed for those textured presets. None of this establishes general eye RGB Apply/save support.
* Empty override arrays or zero recorded runtime switches do not prove the absence of inherited material behavior. Preserve explicit `false`, distinguish unreadable data from empty arrays, and record parameter association/index alongside names.
* A journal for a live experimental write should record identity, baseline, intended change, and restoration state **before** mutation. Recovery must validate its schema and process/session ownership. A file from a previous process is not permission to write to a newly discovered object with a similar name.

These findings narrow which targets are supported. They do not justify broadening a whitelist from one working material family to every customization slot.

Sources: [Colors+ changelog](../../Colors%2B/CHANGELOG.md), [eye observations](../../Colors%2B/docs/eyebrow-eye-testing.md), [native handoff](../../Colors%2B/docs/blue-first-handoff.md), and [lifetime review](../../Colors%2B/docs/lifetime-guide-review-2026-09-17.md).

---

# 46. A lost Lua widget reference does not prove the visible window is gone

**Observed Dev Panel failure:** the log reported the panel widget invalid and marked it closed, but the visible window remained. Another toggle could create another window. The cause of the invalid reference was not established.

The recovery pattern retains scalar paths for owned widgets, attempts bounded lookup, and blocks replacement construction while an old root remains unresolved. Confirmed destruction can complete cleanup; an actual removal failure must preserve enough identity to retry and prevent duplicates.

Colors+ also checks a freshly resolved, attached root before read/show/update operations. A latched context stop ends polling before more UI reads. Session checks after native calls prevent an old poll or error handler from rescheduling itself or closing a replacement picker created during re-entrant native work.

Do not call this proof of a garbage-collection fix. Do not introduce rooting or native-memory tricks based only on a disappearing wrapper.

Input ownership is separate from window lifetime. The initial Dev Panel explicitly chose UI-only input, blocked movement/camera, and drew a full-screen dimming layer. v0.2.0 implements a compact side panel, shared game/UI input, docking, and collapse, and removes delayed input resets that could overwrite a newer game menu’s state. Its local behavior tests passed; the recorded task left live appearance and interaction verification pending.

A general-purpose launcher can use shared input; a native modal dialog intentionally blocks interaction. Closing either should respect the current owner’s state. Avoid delayed unconditional “restore game input” work after navigation.

Sources: [first overlay failure](../../Tactical%20Info%2B/docs/combat-log-ui-test-2026-09-14/findings.md), [picker lifetime review](../../Colors%2B/docs/lifetime-guide-review-2026-09-17.md), and [Dev Panel source](../../SWZC%20Dev%20Panel/src/SWZCDevPanel/Scripts/).

---

# 47. Distinguish slow native work, missing data, and runaway rebuilds

**Recorded Enhanced Databank investigation:** four successful moves in one v1.0.1 log took approximately **0.95–1.22 seconds** from destination click to completed rendering. Roughly 200–260 ms was intentional deferral, 470–560 ms was inside the synchronous native move, and 150–300 ms involved refresh scheduling and folder reconstruction. These are session measurements, not performance guarantees.

Scheduling work later does not make the native call asynchronous. Full custom-folder reconstruction also scales with the number of folders and characters. Removing the safety delay does not solve the synchronous cost and can reintroduce the click-lifecycle failure.

Log separate boundaries for popup retirement, authority lookup, native mutation, and row generation before deciding what to optimize. Incremental or staged reconstruction is a possible future design; it is not a validated fix in the reviewed implementation.

**Unresolved disappearing-folder hypothesis:** the current renderer collects authoritative pools and available VMs, removes dynamic folder widgets, then skips any folder whose matching VM is unavailable. A transient VM gap could therefore erase its presentation until another successful refresh. The reviewed healthy log rendered both authoritative folders across 14 passes, so it did not reproduce the reporter’s failure.

Compare these counts and markers in an affected session:

* authoritative custom pools;
* matching discoverable pool VMs;
* successfully rendered folders and scroll children;
* missing-VM, binding, attachment, or row-generation failures.

Do not conflate this with the fixed Default-row visibility bug or the fixed duplicate Create Folder control. Preflighting all folder/VM matches before replacing existing UI, then using a bounded retry for incomplete data, is a proposed improvement. The older fast unlimited rebuild loop is explicitly a failed approach.

Evidence: recorded investigation in the task **Fix character creation in empty root**, current [renderer](../src/Enhanced%20Databank/Scripts/databank_ui.lua), and [debug log](../debug/UE4SS.log). The investigation did not establish the present status of remote issue reports.

---

# 48. A combat-log overlay has been tested, but shipping combat UI remains a separate area

**Verified v0.21.1 test:** the Tactical Info+ prototype rendered at 1920×1080; Dev Tools worked, repeated Show/Hide and Older/Latest actions dispatched, and no create/render failure or unresolved-root marker appeared in that capture.

The first failed Dev Panel test did **not** establish that the combat-log overlay had opened: its action counter and construction markers were absent. Diagnose action delivery before assigning a failure to a window that may never have been created.

The successful screenshot then taught a presentation lesson. The log held 14 rows, but wrapped text left later rows below the viewport. They had not been lost from the buffer. Updating a TextBlock does not establish that the ScrollBox moved to its latest entry.

v0.21.2 retains and reacquires the owned scroll widget, requests `ScrollToEnd` after updates, and advances history one entry at a time so variable-height rows remain reachable. Mock tests verify the requests; the resulting Slate layout still needs an in-game check.

A working standalone combat-log overlay does not establish safe mutation of shipping combat/HUD widgets, controller navigation for custom screens, or every viewport size.

Sources: [initial test](../../Tactical%20Info%2B/docs/combat-log-ui-test-2026-09-14/findings.md) and [follow-up](../../Tactical%20Info%2B/docs/combat-log-ui-followup-2026-09-14/findings.md).

---

# 49. Cross-mod launchers should pass requests, not native object references

**Implemented Dev Panel design:** participating UE4SS mods are optional peers with their own Lua states. The panel reads a data-only action manifest and increments counters in the participant’s state file. The participant’s client notices the request and invokes its own callback inside its own runtime.

The launcher should not retain another mod’s functions, widgets, or target UObjects. The receiving mod still owns game-thread scheduling, cancellation, target validation, and recovery. A visible button is not evidence that the participant is running or that its action reached a valid context.

Colors+ exposed practical client-lifecycle requirements:

* recreate the client with the current owned scheduler after reload;
* baseline counters so old clicks are not replayed as new requests;
* distinguish missing registry files from read errors, preserve other registrations, and avoid duplicates;
* retry a failed state parse without consuming the update as successfully handled;
* log delivery stages independently from backend mutation stages;
* let Stop/Cancel cancel queued starts, and check exclusions again at dispatch time.

The Colors+ client was revised locally; those changes do not imply the separately installed Dev Panel application or every copied integration helper was updated. The older integration reference is useful for the protocol, but its scheduling and missing-registry behavior must be checked against the actual client version.

An event-driven game UI and a bounded/owned file-request polling client serve different purposes. Removing unsafe per-row hover polling does not mean every polling mechanism is forbidden.

Sources: [Dev Panel integration contract](../../SWZC%20Dev%20Panel/src/SWZCDevPanel/DEV_PANEL_INTEGRATION.md), [Colors+ client changes](../../Colors%2B/CHANGELOG.md), and [control notes](../../Colors%2B/docs/dev-panel-controls.md).

---

# 50. Updated practical checklist and test matrix

The shared rule is to validate **identity, ownership, timing, and recovery** separately. Matching appearance is only one part of a UI modification.

| Area | Checks that answer different questions |
| --- | --- |
| Entry | Fresh process and first entry; repeat entry; late-loaded classes; empty and populated pools |
| Installation | Repeated setup; failed clone rename; surviving widgets with fresh Lua state; failed append and retry; stable widths/child counts |
| Categories | Both pages; switch tabs with a popup or mutation pending; reject cross-category targets |
| Selection | Native row click; exact Move target; duplicate names; reused collapsed rows; multiple physical rows for one GUID |
| Mutations | Create/rename/delete; all three move directions; final character out; second move before recovery; native deletion |
| Refresh | Paired activation events; retriggered handle; request during active render; unavailable pool VM; retired-runtime callback |
| Input | Real click versus tooltip/hover; keyboard/controller where supported; hitboxes; multiple windows; input after navigation |
| Preview | Default handoff; native hover; committed selection; Apply; reopen/Cancel; timeout; source/display replacement |
| Persistence | Native Save and reopen, then a separate full-process restart; source values and displayed rendering checked independently |
| Coexistence | Character Share alone, Enhanced Databank alone, both orders; Dev Panel present/absent; client delivery across reload |
| Scale/layout | Larger Databanks; wrapped text; scroll reachability; supported resolutions and UI scales |
| Failure recovery | Partial writes; failed restoration/removal/unregistration; canceled starts; no duplicate replacement windows |
| Reload | Same-state reinitialization, UE4SS Reload All Mods, and full restart treated as separate lifecycles |

Use syntax checks and production-module tests with mocked boundaries to verify routing, reconciliation, cancellation, and failure paths. Do not write a mock that merely copies the implementation’s assumptions: the retained-first-callback scheduler test and failed-rename adoption test are valuable precisely because they reproduce the unusual boundary behavior.

Only in-game evidence can establish native argument conversion, actual rendering, CommonUI/Slate interaction, UObject replacement, and save/restart behavior. A release entry or successful Lua test is not that evidence.

Keep bounded `BEGIN`/`RETURN`/error diagnostics around risky boundaries, with runtime/session/call identifiers. Character Share v1.0.3 writes a dedicated `character_share.log` while mirroring to UE4SS, adding UTC time and runtime/Databank/import generations. Independent logs with correlated generations are more useful than interleaved success messages alone. After stabilizing the feature, disable unnecessary probes while retaining useful lifecycle and failure records.

---

# 51. Source index and remaining boundaries

This revision reconciles the supplied Character Share/Colors+ notes with local source, changelogs, recorded findings, and task history available on September 18, 2026. No new game run or remote issue-status check was performed for this document.

| Evidence | What it supports |
| --- | --- |
| [Character Share changelog](../../CharacterShare/CHANGELOG.md) | GUID-based conflict handling, entry validation, owned workflows, and dedicated diagnostics |
| [Enhanced Databank changelog](../CHANGELOG.md) | Released implementation changes through v1.0.3 |
| [Enhanced Databank architecture](architecture.md) | Module responsibilities, reload wiring, category and row reconciliation tests |
| [Enhanced Databank scripts](../src/Enhanced%20Databank/Scripts/) and [tests](../tests/) | Current behavior and local regression coverage |
| [Historical Databank guide](../Zero_Company_Databank_Modding_Guide.md) | Failed experiments and empirical native boundaries; some early recipes are superseded here |
| [Colors+ practical notes](../../Colors%2B/docs/practical-ue4ss-ui-modding-notes.md) | Companion revision corresponding to the supplied guide |
| [Colors+ changelog](../../Colors%2B/CHANGELOG.md) and [skin persistence findings](../../Colors%2B/docs/skin-persistence-findings.md) | Versioned target, ownership, and save/reopen observations |
| [Colors+ lifetime review](../../Colors%2B/docs/lifetime-guide-review-2026-09-17.md) | Root attachment, re-entrant callbacks, replacement after setters, and diagnostic limits |
| [Dev Panel integration](../../SWZC%20Dev%20Panel/src/SWZCDevPanel/DEV_PANEL_INTEGRATION.md) | Optional-peer request protocol; client revisions must be checked separately |
| [Combat-log UI follow-up](../../Tactical%20Info%2B/docs/combat-log-ui-followup-2026-09-14/findings.md) | Confirmed overlay test and scrolling limitation |

Recorded tasks additionally used: **Fix duplicate folder creation**, **Add Astromech folder support**, **Fix character creation in empty root**, **Add save file renaming**, and **Improve SWZCDP usability**. Their reports are distinguished from direct code evidence and live-test findings throughout. Links into sibling projects assume the local `ZComMods` directory layout; keep the named/versioned evidence if distributing this file alone.

The remaining boundaries are explicit: full Astromech native validation is not established by its mocks; the disappearing-folder and performance investigations are not claimed fixed; save-file renaming is unproven; skin target-probe recovery failed in the recorded native test; skin-enable restart persistence and general eye RGB persistence are unproven; and reload safety is not universal across these mods.

This remains an empirical knowledge base for the tested Zero Company flows, not a complete Unreal or UE4SS UI SDK.
