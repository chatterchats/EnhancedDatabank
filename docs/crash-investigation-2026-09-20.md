# September 20 crash report

Evidence: the supplied `enhanced_databank(1).log` and `UE4SS(4).log`, reporting
Enhanced Databank 1.0.4. The reporter's exact crashing action is unknown. Neither
file contains a fatal exception, native stack, or minidump. Log timestamps below
are reproduced as recorded, without timezone conversion.

## Observed sequence

- 05:29:12: automatic render completes with seven custom folders and 49 custom
  characters, plus one Default character.
- 05:29:15: another master activation renders the same folders successfully.
- 05:29:17: submenu navigation interrupts entry work; a hidden master is rejected.
- 05:29:25–37: other mods report a map change, mission initialization and save load.
- 05:29:42–46: another map change occurs and the Strategy main menu appears.
- 05:29:59.548: both Enhanced Databank and Character Share detect a Databank click.
- 05:29:59.715: Enhanced Databank's first entry check finds no valid master.
- 05:30:01.873: the last UE4SS line is an unrelated MXM health message. There is
  no subsequent stable-entry, render, or entry-expiry message in the supplied logs.

The first missing-master check is an expected bounded retry condition, not an
exception. The log ending does not establish which mod or native call crashed.
Both recorded renders completed, so this report does not demonstrate a failure
inside character-row generation.

## Reproduced code defect and patch

Enhanced Databank registers global `BP_OnHovered` and `BP_OnUnhovered` hooks.
Previously, every button event compared the event object with the retained Create
Folder button using `common.same_object`. For different wrappers, that helper
calls `GetFullName()` on both objects without validating them. The retained
button can belong to a screen destroyed during travel, so even hovering an
unrelated main-menu button could read the retired object. The pending entry
request does not have to reach rendering for this path to execute.

Hover dispatch now validates the supplied event object and matches its name
against the existing Lua registration map before accessing Databank state. An
unrelated event never inspects the retained Create Folder button or its glyph.
Matching events also reject invalid icon canvases before painting them.

`tests/hover_lifecycle_test.lua` uses the production identity helpers and hook
callbacks. It fails on the previous implementation because unrelated hover events
call the destroyed button's `GetFullName()`. It passes after the patch, along with
all seven existing Lua test files. It also checks invalid event contexts, fresh
controls after reentry, distinct wrappers for the same live button, hover/unhover
colors, and invalid glyphs. These mocks establish the stale access, not a native
crash reproduction or a guarantee that every stale native pointer is detectable.

The current UE4SS [RemoteObject documentation](https://github.com/ue4ss-re/re-ue4ss/blob/main/docs/lua-api/classes/remoteobject.md)
documents `IsValid`; the [UObject documentation](https://github.com/ue4ss-re/re-ue4ss/blob/main/docs/lua-api/classes/uobject.md)
documents `GetFullName` and native member access. Both were retrieved through
Context7 during this investigation. Lua error handling is not evidence that a
native object dereference is safe.

## Remaining validation

This is a candidate fix, not a confirmed diagnosis of the reporter's crash. Test
a fresh game launch, Databank entry and exit, mission/save loading, return to the
menu, hovering menu buttons, and repeated Databank entry with Character Share.
Also verify Create Folder, rename/delete glyph hover, and both supported tabs.

If it still crashes, obtain the crash report/minidump from that same run, both
mod logs, and the action immediately preceding the crash. Older local crash ZIPs
were not used as evidence for this report. The local test ZIP is named separately
from release packages and retains 1.0.4 metadata; no release was published.
