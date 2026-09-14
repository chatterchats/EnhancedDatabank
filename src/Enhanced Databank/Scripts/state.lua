-- Enhanced Databank: state.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: state.
return function(ctx)
    -- Shared row-generation state and late-bound dialog/decorator callbacks.
    -- All factories populate this context before startup installs hooks.
    ctx.state.folder_ui_state = nil

    ctx.state.show_move_character_dialog = nil

    ctx.state.decorate_current_character_rows = nil

    -- ---------------------------------------------------------------------------
    -- Create Folder control
    --
    -- Restores the native pool creation affordance without inventing a parallel
    -- folder model. The control is an icon-only clone of the shipping Create New
    -- button, with a Tabler-style folder-plus glyph loaded from this mod's Assets
    -- directory. The dialog calls the game's own IsNewPoolNameAvailable/CreatePool
    -- functions; persistence and empty-pool lifecycle remain fully native.
    -- ---------------------------------------------------------------------------

    ctx.state.CREATE_FOLDER_BUTTON_MARKER = "EnhancedDatabank_CreateFolderButton"

    ctx.state.CREATE_FOLDER_ROW_MARKER = "EnhancedDatabank_CreateFolderRow"

    ctx.state.CREATE_FOLDER_ICON_WIDTH = 64.0

    ctx.state.CREATE_FOLDER_GLYPH_SIZE = 28.0

    ctx.state.CREATE_FOLDER_GAP = 8.0

    ctx.state.RENAME_FOLDER_BUTTON_WIDTH = 48.0

    ctx.state.RENAME_FOLDER_BUTTON_HEIGHT = 44.0

    ctx.state.RENAME_FOLDER_GLYPH_SCALE = 1.5

    ctx.state.RENAME_FOLDER_GLYPH_SIZE = 22.0 * ctx.state.RENAME_FOLDER_GLYPH_SCALE

    ctx.state.RENAME_FOLDER_BUTTON_MARKER = "EnhancedDatabank_RenameFolderButton_"

    ctx.state.DELETE_FOLDER_BUTTON_MARKER = "EnhancedDatabank_DeleteFolderButton_"

    local MOVE_CHARACTER_BUTTON_MARKER = "EnhancedDatabank_MoveCharacterButton_"

    ctx.state.MOVE_CHARACTER_BUTTON_WIDTH = 48.0

    ctx.state.MOVE_CHARACTER_BUTTON_HEIGHT = 44.0

    ctx.state.MOVE_CHARACTER_RIGHT_PADDING = 54.0

    ctx.state.ENTRY_TEXT_CLASS_PATH =
        "/Game/Game/UI/Strategy/Customization/Widgets/CustomCharacter/"
        .. "WBP_CustomCharacter_EntryText.WBP_CustomCharacter_EntryText_C"

    ctx.state.GENERIC_POPUP_CLASS_PATH =
        "/Game/Game/UI/Common/WBP_GenericPopupMessage_Small."
        .. "WBP_GenericPopupMessage_Small_C"

    ctx.state.GENERIC_POPUP_FALLBACK_CLASS_PATH =
        "/Game/Game/UI/Common/WBP_GenericPopupMessage."
        .. "WBP_GenericPopupMessage_C"

    ctx.state.DIALOG_RESULT_PRIMARY = "br.Customization.Slot.Character.Info"

    ctx.state.DIALOG_RESULT_SECONDARY = "br.Customization.Slot.Character.Class"

    ctx.state.folder_ui_state = {
        pageIdentity = nil,
        page = nil,
        row = nil,
        button = nil,
        buttons = {},
        iconCanvas = nil,
        iconOverlay = nil,
        renameButtons = {},
        deleteButtons = {},
        moveButtons = {},
        moveRowActions = {},
        moveDestinationButtons = {},
        renderedPools = {},
        moveClickScheduled = false,
        pendingMove = nil,
    }

    ctx.state.folder_popup_state = {
        widget = nil,
        mode = nil,
        textBox = nil,
        resultActions = {},
        suppressResult = false,
        initialText = "",
        targetPoolVM = nil,
        targetPoolName = nil,
        targetCharacterGuid = nil,
        targetCharacterName = nil,
        sourcePoolName = nil,
    }

    ctx.state.folder_dialog_result_hook_registered = false

    ctx.state.folder_button_click_hook_registered = false

    ctx.state.action_hover_hooks_registered = false

    ctx.state.FOLDER_ICON_COLOR_NORMAL = { R = 0.78, G = 0.74, B = 0.76, A = 1.0 }

    ctx.state.FOLDER_ICON_COLOR_HOVER = { R = 0.10, G = 0.075, B = 0.085, A = 1.0 }

    ctx.state.FOLDER_ICON_COLOR = ctx.state.FOLDER_ICON_COLOR_NORMAL

    ctx.state.default_move_decor_generation = 0
end
