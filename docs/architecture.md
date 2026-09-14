# Script architecture

`main.lua` is the version declaration and composition root. It starts the reload
registry, allocates one context, and initializes the factories in dependency order.
All modules are shipped inside the existing `Scripts` directory; the release
workflow already packages that entire directory.

| Modules | Responsibility |
| --- | --- |
| `hook_registry.lua`, `actions.lua` | Own both hook IDs, guarded callbacks, delayed handles, cancellation, and reload teardown. |
| `common.lua`, `logging.lua`, `state.lua` | UObject helpers, per-instance logging, constants, mutable UI state, and callback slots. |
| `pool_authority.lua`, `pool_mutations.lua` | Read native ownership and apply native create/rename/delete/move operations. |
| `pool_widgets.lua`, `databank_ui.lua` | Render authoritative pools and coalesce screen refreshes. |
| `widget_helpers.lua`, `folder_icons.lua`, `folder_ui.lua` | Native widget composition, glyphs, folder controls, click/hover routing, and control adoption. |
| `popup.lua` | Native folder/move dialogs and their result routing and retirement. |
| `lifecycle.lua`, `startup.lua` | Lazy lifecycle-hook installation, activation fallback, mutation hooks, and startup wiring. |
| `selected_move_button.lua`, `debug_keybinds.lua` | Existing selected-character Move control and opt-in debug bindings. |

## Context and initialization

Factories have the signature `return function(ctx) ... end`. Private helpers remain
local to their module; cross-module functions and mutable values use explicit
`ctx.<namespace>.<name>` references. There is no shared Lua environment or copy of
mutable state in another module. In particular, do not cache a state field in a
local if another module can replace it.

The bootstrap allocates every namespace before defining functions. Callback slots
in `ctx.state` are filled during initialization; hooks and initial actions are
installed last in `startup.lua`, after those slots are populated. Mutually
dependent UI/dialog callbacks therefore resolve through the current context when
invoked, not through stale values captured before initialization finished.

Reloading invalidates the factory cache and constructs a fresh context. The
registry retires the preceding runtime first; old callbacks retain only their
retired context. `EnhancedDatabankActions` remains a compatibility alias to the
current action API. The legacy `reload_runtime.lua` import forwards to the registry.
No new UObject discovery, timers, ownership database, or save-writing path is
introduced by this split.

## Local checks

Run from the repository root:

```sh
luajit tests/reload_runtime_test.lua "src/Enhanced Databank/Scripts"
luajit tests/widget_reload_test.lua "src/Enhanced Databank/Scripts"
luajit tests/module_bootstrap_test.lua "src/Enhanced Databank/Scripts"
luajit tests/refresh_test.lua "src/Enhanced Databank/Scripts"
python3 tests/version_bump_test.py
```

These exercise the actual scheduler, registry, UI factories, bootstrap/reload
wiring, and version helper with mocked engine boundaries. They do not replace
in-game checks: enter/leave the Databank, create/rename/move/delete a folder, move
several characters, and check the shared Import/Create Folder row with Character
Share enabled.

The Lua tests also run with `lua5.4` in place of `luajit`.
