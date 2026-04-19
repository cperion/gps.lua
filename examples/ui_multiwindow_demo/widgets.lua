local ui = require("ui")
local demo_apply = require("demo_apply")

local T = ui.T
local tw = ui.tw
local b = ui.build
local recipes = ui.recipes

local M = {}

local function fg_main() return tw.fg.slate[50] end
local function fg_soft() return tw.fg.slate[300] end
local function fg_dim() return tw.fg.slate[400] end
local function bg_page() return tw.bg.slate[950] end
local function bg_panel() return tw.bg.slate[900] end
local function bg_panel_soft() return tw.bg.slate[800] end
local function border_subtle() return tw.border_color.slate[800] end
local function border_focus() return tw.border_color.sky[500] end
local function border_green() return tw.border_color.emerald[700] end
local function border_amber() return tw.border_color.amber[700] end

local function append_all(out, items)
    for i = 1, #items do out[#out + 1] = items[i] end
end

local function compose_bundle(node, bundles, extras)
    local bundle = {
        node = node,
        bundles = bundles or {},
    }

    function bundle:route_ui_event(ui_event)
        for i = 1, #self.bundles do
            local app_event = self.bundles[i]:route_ui_event(ui_event)
            if app_event ~= nil then return app_event end
        end
        return nil
    end

    function bundle:route_ui_events(ui_events)
        local out = {}
        for i = 1, #self.bundles do
            append_all(out, self.bundles[i]:route_ui_events(ui_events))
        end
        return out
    end

    if extras ~= nil then
        for k, v in pairs(extras) do bundle[k] = v end
    end

    return bundle
end

local function content_id(note_id, slot)
    return b.id("note:" .. note_id .. ":" .. slot)
end

local function content_text(note_id, slot, styles)
    return b.text_ref(content_id(note_id, slot), styles)
end

local function chip(label, border)
    return b.box {
        tw.px_2, tw.py_1, tw.rounded_full,
        tw.bg.slate[900], tw.border_1, border or border_subtle(),
        b.text { tw.text_xs, tw.font_semibold, fg_soft(), label },
    }
end

local function stat_card(label, value, note)
    return b.box {
        tw.flow, tw.gap_y_1,
        tw.p_3, tw.rounded_lg, tw.border_1, border_subtle(), bg_panel(),
        b.text { tw.text_xs, tw.font_semibold, fg_dim(), string.upper(label) },
        b.text { tw.text_lg, tw.font_semibold, fg_main(), tostring(value) },
        note and b.text { tw.text_sm, fg_dim(), note } or nil,
    }
end

local function action_button_recipe(id_string, label, accent_border, on_activate)
    local id = b.id(id_string)
    return recipes.activatable {
        id = id,
        child = b.box {
            b.id(id_string .. ":frame"),
            tw.px_3, tw.py_2,
            tw.rounded_md, tw.border_1, accent_border or border_subtle(),
            bg_panel(), tw.cursor_pointer,
            tw.hover(bg_panel_soft()),
            tw.active(bg_panel_soft()),
            b.text { tw.text_sm, tw.font_semibold, fg_main(), label },
        },
        on_activate = on_activate,
    }
end

local function note_row(note_ref, ctx)
    local border = ctx.dragged and tw.border_color.sky[400] or (ctx.selected and border_focus() or border_subtle())
    local bg = ctx.dragged and tw.bg.slate[700] or (ctx.selected and tw.bg.slate[800] or bg_panel())
    local prefix = "note:" .. note_ref.id

    return b.box {
        b.id(prefix .. ":row"),
        tw.flow, tw.gap_y_1,
        tw.p_3, tw.rounded_lg, tw.border_1, border, bg,
        ctx.dragged and tw.cursor_grabbing or tw.cursor_grab,
        tw.hover(bg_panel_soft()),
        tw.active(bg_panel_soft()),
        content_text(note_ref.id, "title", { tw.text_sm, tw.font_semibold, fg_main() }),
        content_text(note_ref.id, "subtitle", { tw.text_sm, fg_dim() }),
    }
end

local function note_slot(index, active)
    return b.box {
        tw.w_full, tw.h_px(8),
        tw.rounded_full,
        active and tw.bg.sky[400] or tw.bg.transparent,
    }
end

local function browser_list_recipe(state)
    local project = state.project
    local dragged_id = state.drag ~= T.MultiNotes.NoDrag and state.drag.id or nil
    local drop_index = state.drop ~= T.MultiNotes.NoDrop and state.drop.index or nil

    return recipes.reorderable_list {
        id = b.id("notes"),
        items = project.notes,
        key_of = function(note_ref)
            return note_ref.id
        end,
        selected_key = project.selected_note_id,
        dragged_key = dragged_id,
        drop_index = drop_index,
        row = function(note_ref, ctx)
            return note_row(note_ref, ctx)
        end,
        slot = function(index, active)
            return note_slot(index, active)
        end,
        on_select = function(key)
            return T.MultiNotes.SelectNote(key)
        end,
        on_drag_start = function(key)
            return T.MultiNotes.BeginDragNote(key)
        end,
        on_drag_preview = function(index)
            return T.MultiNotes.PreviewInsertAt(index)
        end,
        on_drag_clear_preview = function()
            return T.MultiNotes.ClearDropPreview
        end,
        on_drag_commit = function(index)
            return T.MultiNotes.CommitDragAt(index)
        end,
        on_drag_cancel = function()
            return T.MultiNotes.CancelDrag
        end,
    }
end

local function browser_sidebar(state, opts)
    opts = opts or {}
    local project = state.project
    local note = demo_apply.selected_note(state)
    local chars = note and #note.body or 0
    local words = 0
    if note then
        for _ in string.gmatch(note.body, "%S+") do words = words + 1 end
    end

    local new_button = action_button_recipe("action:new", "New Note", border_green(), function()
        return T.MultiNotes.NewNote
    end)
    local delete_button = action_button_recipe("action:delete", "Delete", border_amber(), function()
        return T.MultiNotes.DeleteSelected
    end)
    local list = browser_list_recipe(state)
    local scroll_view = recipes.scroll_view {
        id = b.id("browser-scroll"),
        axis = T.Style.ScrollY,
        reserve_track_space = "auto",
        scrollbar_visible = opts.scrollbar_visible == true,
        reserve_space_px = 16,
        thickness = 9,
        inset = 3,
        min_thumb_px = 28,
        track_rgba8 = 0x020617ff,
        track_opacity = 0.52,
        thumb_rgba8 = 0x334155ff,
        thumb_hover_rgba8 = 0x60a5faff,
        thumb_drag_rgba8 = 0x93c5fdff,
        thumb_opacity = 0.95,
        items = {
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0), tw.w_full,
            b.box { tw.w_full, tw.flow, tw.gap_y_2, list.node },
        },
    }
    local dragged_id = state.drag ~= T.MultiNotes.NoDrag and state.drag.id or nil

    return compose_bundle(b.box {
        tw.w_px(280), tw.min_w_px(280), tw.max_w_px(280),
        tw.basis_px(280), tw.grow_0, tw.shrink_0,
        tw.h_full,
        tw.flex, tw.col, tw.gap_y_4,
        tw.p_4,
        tw.rounded_xl, tw.border_1, border_subtle(), bg_panel(),
        b.text { tw.text_xl, tw.font_semibold, fg_main(), "Notes Browser" },
        b.text { tw.text_sm, fg_soft(), "Select notes, create new ones, and reorder them from this window." },
        b.box { tw.flex, tw.row, tw.wrap, tw.gap_2,
            new_button.node,
            delete_button.node,
        },
        b.box { tw.flex, tw.row, tw.wrap, tw.gap_2,
            chip(tostring(#project.notes) .. " notes", border_subtle()),
            chip(tostring(chars) .. " chars", border_green()),
            chip(tostring(words) .. " words", border_amber()),
            dragged_id and chip("drag " .. dragged_id, tw.border_color.sky[700]) or nil,
        },
        scroll_view.node,
    }, { new_button, delete_button, list, scroll_view }, {
        scroll_view = scroll_view,
    })
end

local function browser_detail(state)
    local note = demo_apply.selected_note(state)
    if note == nil then
        return b.box {
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
            tw.flow, tw.gap_y_4,
            tw.p_4,
            tw.rounded_xl, tw.border_1, border_subtle(), bg_panel(),
            b.text { tw.text_lg, tw.font_semibold, fg_main(), "No note selected" },
        }
    end

    return b.box {
        tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
        tw.flow, tw.gap_y_4,
        tw.p_4,
        tw.rounded_xl, tw.border_1, border_subtle(), bg_panel(),
        content_text(note.id, "title", { tw.text_xl, tw.font_semibold, fg_main() }),
        b.text { tw.text_sm, fg_soft(), "Preview of the selected note in the shared project state." },
        b.box {
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
            tw.rounded_xl, tw.border_1, border_subtle(), tw.bg.slate[950], tw.p_4,
            content_text(note.id, "body", { tw.text_base, fg_soft() }),
        },
    }
end

function M.browser_root(state, opts)
    local sidebar = browser_sidebar(state, opts)
    return compose_bundle(b.box {
        tw.w_full, tw.h_full,
        tw.flex, tw.col,
        tw.p_4, tw.gap_y_4,
        bg_page(),
        b.box {
            tw.flex, tw.row, tw.gap_4,
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
            sidebar.node,
            browser_detail(state),
        },
    }, { sidebar }, {
        scroll_view = sidebar.scroll_view,
        content_store = demo_apply.content_store(state),
    })
end

local function title_surface_recipe()
    return recipes.edit_surface {
        id = b.id("editor:title"),
        scroll_id = b.id("editor:title:scroll"),
        scroll_axis = T.Style.ScrollX,
        reserve_track_space = "auto",
        reserve_space_px = 16,
        thickness = 9,
        inset = 3,
        min_thumb_px = 28,
        track_rgba8 = 0x020617ff,
        hover_track_rgba8 = 0x0f172aff,
        focus_track_rgba8 = 0x0f172aff,
        track_opacity = 0.52,
        thumb_rgba8 = 0x334155ff,
        thumb_hover_rgba8 = 0x60a5faff,
        thumb_focus_rgba8 = 0x7dd3fcff,
        thumb_drag_rgba8 = 0x93c5fdff,
        thumb_opacity = 0.95,
        label = "Title",
        placeholder = "Untitled",
        min_h = 64,
        field_styles = tw.list {
            tw.w_full,
            tw.min_h_px(64),
            tw.rounded_xl,
            tw.border_1,
            border_subtle(),
            tw.bg.slate[950],
        },
    }
end

local function body_surface_recipe()
    return recipes.edit_surface {
        id = b.id("editor:body"),
        scroll_id = b.id("editor:body:scroll"),
        scroll_axis = T.Style.ScrollY,
        reserve_track_space = "auto",
        reserve_space_px = 16,
        thickness = 9,
        inset = 3,
        min_thumb_px = 28,
        track_rgba8 = 0x020617ff,
        hover_track_rgba8 = 0x0f172aff,
        focus_track_rgba8 = 0x0f172aff,
        track_opacity = 0.52,
        thumb_rgba8 = 0x334155ff,
        thumb_hover_rgba8 = 0x60a5faff,
        thumb_focus_rgba8 = 0x7dd3fcff,
        thumb_drag_rgba8 = 0x93c5fdff,
        thumb_opacity = 0.95,
        label = "Body",
        placeholder = "Write here...",
        min_h = 320,
        field_styles = tw.list {
            tw.w_full,
            tw.min_h_px(320),
            tw.rounded_xl,
            tw.border_1,
            border_subtle(),
            tw.bg.slate[950],
        },
    }
end

function M.editor_root(state, opts)
    opts = opts or {}
    local project = state.project
    local note = demo_apply.selected_note(state)
    local dirty = opts.dirty == true
    local title = opts.title_text or (note and note.title or "Untitled")
    local body = opts.body_text or (note and note.body or "")
    local title_surface = title_surface_recipe()
    local body_surface = body_surface_recipe()

    return compose_bundle(b.box {
        tw.w_full, tw.h_full,
        tw.flex, tw.col,
        tw.p_4, tw.gap_y_4,
        bg_page(),

        b.box {
            tw.flex, tw.row, tw.items_center, tw.justify_between,
            tw.p_4,
            tw.rounded_xl, tw.border_1, border_subtle(), bg_panel(),
            b.box { tw.flow, tw.gap_y_1,
                b.text { tw.text_xl, tw.font_semibold, fg_main(), "Note Editor" },
                b.text { tw.text_sm, fg_soft(), "Editing is attached to authored edit surfaces in this window." },
            },
            b.box { tw.flex, tw.row, tw.gap_2,
                chip(project.selected_note_id ~= "" and project.selected_note_id or "none", border_focus()),
                chip(dirty and "modified" or "live", border_green()),
            },
        },

        b.box {
            tw.flex, tw.row, tw.gap_4,
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0),

            b.box {
                tw.w_px(240), tw.h_full,
                tw.flow, tw.gap_y_4,
                tw.p_4,
                tw.rounded_xl, tw.border_1, border_subtle(), bg_panel(),
                stat_card("title chars", #title),
                stat_card("body chars", #body),
                stat_card("body lines", select(2, string.gsub(body, "\n", "\n")) + 1),
                b.text { tw.text_sm, fg_dim(), "Use the browser window to select notes. Draft edits stay local here and commit to shared state after idle or blur." },
            },

            b.box {
                tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
                tw.flow, tw.gap_y_4,
                title_surface.node,
                body_surface.node,
            },
        },
    }, {}, {
        title_surface = title_surface,
        body_surface = body_surface,
        content_store = demo_apply.content_store(state),
    })
end

return M
