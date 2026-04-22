local ui = require("ui")
local tw = ui.tw

local M = {
    text = {},
    surface = {},
    ring = {},
    button = { frame = {}, label = {} },
    input = { frame = {}, value = {}, placeholder = {} },
    card = {},
    toolbar = {},
    list_item = { frame = {} },
}

M.text.section_title = tw.group {
    tw.text_2xl,
    tw.font_semibold,
    tw.tracking_tight,
    tw.fg.slate[900],
    tw.dark(tw.fg.slate[50]),
}

M.text.section_subtitle = tw.group {
    tw.text_sm,
    tw.fg.violet[700],
    tw.dark(tw.fg.violet[200]),
}

M.text.label = tw.group {
    tw.text_sm,
    tw.font_medium,
    tw.leading_none,
    tw.fg.slate[900],
    tw.dark(tw.fg.slate[100]),
}

M.text.body = tw.group {
    tw.text_sm,
    tw.fg.slate[500],
    tw.dark(tw.fg.slate[300]),
}

M.text.brand_title = tw.group {
    tw.text_lg,
    tw.font_semibold,
    tw.tracking_tight,
    tw.fg.slate[900],
    tw.dark(tw.fg.slate[50]),
}

M.text.brand_subtitle = tw.group {
    tw.text_xs,
    tw.fg.violet[700],
    tw.dark(tw.fg.violet[200]),
}

M.text.card_title = tw.group {
    tw.text_lg,
    tw.font_semibold,
    tw.leading_none,
    tw.tracking_tight,
    tw.fg.slate[900],
    tw.dark(tw.fg.slate[50]),
}

M.surface.app = tw.group {
    tw.bg.violet[50],
    tw.dark(tw.bg.slate[950]),
}

M.surface.panel = tw.group {
    tw.rounded_xl,
    tw.border_1,
    tw.border_color.violet[200],
    tw.bg.white,
    tw.dark {
        tw.border_color.slate[700],
        tw.bg.slate[900],
    },
}

M.surface.panel_soft = tw.group {
    tw.rounded_lg,
    tw.bg.violet[100],
    tw.dark(tw.bg.slate[800]),
}

M.surface.panel_muted = tw.group {
    tw.bg.violet[100],
    tw.hover(tw.bg.violet[200]),
    tw.active(tw.bg.violet[200]),
    tw.dark {
        tw.bg.slate[800],
        tw.hover(tw.bg.slate[700]),
        tw.active(tw.bg.slate[700]),
    },
}

M.ring.focus = tw.group {
    tw.focus(tw.border_2),
    tw.focus(tw.border_color.violet[500]),
    tw.dark(tw.focus(tw.border_color.violet[300])),
}

M.button.frame.base = tw.group {
    tw.flex,
    tw.row,
    tw.items_center,
    tw.justify_center,
    tw.rounded_md,
    tw.border_1,
    tw.border_color.transparent,
    tw.cursor_pointer,
}

M.button.frame.sm = tw.group { tw.px_3, tw.py_1 }
M.button.frame.md = tw.group { tw.px_4, tw.py_2 }
M.button.frame.lg = tw.group { tw.px_8, tw.py_3 }
M.button.frame.icon = tw.group { tw.w_px(40), tw.h_px(40) }

M.button.frame.primary = tw.group {
    tw.bg.violet[500],
    tw.hover(tw.bg.violet[400]),
    tw.active(tw.bg.violet[300]),
    tw.dark {
        tw.bg.violet[400],
        tw.hover(tw.bg.violet[300]),
        tw.active(tw.bg.violet[200]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.button.frame.secondary = tw.group {
    tw.bg.violet[100],
    tw.border_color.violet[200],
    tw.hover(tw.bg.violet[200]),
    tw.active(tw.bg.violet[200]),
    tw.dark {
        tw.bg.slate[800],
        tw.border_color.slate[700],
        tw.hover(tw.bg.slate[700]),
        tw.active(tw.bg.slate[700]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.button.frame.outline = tw.group {
    tw.border_color.violet[200],
    tw.hover(tw.bg.violet[100]),
    tw.active(tw.bg.violet[200]),
    tw.dark {
        tw.border_color.slate[700],
        tw.hover(tw.bg.slate[800]),
        tw.active(tw.bg.slate[700]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.button.frame.ghost = tw.group {
    tw.hover(tw.bg.violet[100]),
    tw.active(tw.bg.violet[200]),
    tw.dark {
        tw.hover(tw.bg.slate[800]),
        tw.active(tw.bg.slate[700]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.button.frame.destructive = tw.group {
    tw.bg.red[600],
    tw.hover(tw.bg.red[800]),
    tw.active(tw.bg.red[800]),
    tw.dark {
        tw.bg.red[900],
        tw.hover(tw.bg.red[800]),
        tw.active(tw.bg.red[800]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.button.label.base = tw.group {
    tw.font_medium,
    tw.leading_none,
}

M.button.label.sm = tw.group { tw.text_xs }
M.button.label.md = tw.group { tw.text_sm }
M.button.label.lg = tw.group { tw.text_base }
M.button.label.icon = tw.group { tw.text_lg }

M.button.label.primary = tw.group { tw.fg.white }
M.button.label.destructive = tw.group { tw.fg.white }
M.button.label.secondary = tw.group {
    tw.fg.slate[900],
    tw.dark(tw.fg.slate[50]),
}
M.button.label.outline = M.button.label.secondary
M.button.label.ghost = M.button.label.secondary

M.input.frame.base = tw.group {
    tw.flex,
    tw.row,
    tw.items_center,
    tw.w_full,
    tw.px_3,
    tw.py_2,
    tw.rounded_md,
    tw.border_1,
    tw.border_color.violet[200],
    tw.bg.white,
    tw.hover(tw.bg.violet[50]),
    tw.cursor_text,
    tw.dark {
        tw.border_color.slate[700],
        tw.bg.slate[950],
        tw.hover(tw.bg.slate[900]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.input.value.default = tw.group {
    tw.text_sm,
    tw.fg.slate[900],
    tw.dark(tw.fg.slate[50]),
}

M.input.placeholder.default = tw.group {
    tw.text_sm,
    tw.fg.slate[500],
    tw.dark(tw.fg.slate[400]),
}

M.card.frame = tw.group {
    M.surface.panel,
    tw.flow,
    tw.p_6,
}

M.card.header = tw.group {
    tw.flow,
    tw.gap_y_1_5,
    tw.mb_4,
}

M.card.body = tw.group {
    tw.flow,
    tw.gap_y_3,
}

M.card.footer = tw.group {
    tw.mt_4,
}

M.toolbar.frame = tw.group {
    tw.flex,
    tw.row,
    tw.wrap,
    tw.items_center,
    tw.gap_2,
}

M.toolbar.inset = tw.group {
    tw.p_1,
    tw.rounded_lg,
    tw.bg.violet[100],
    tw.dark(tw.bg.slate[800]),
}

M.list_item.frame.base = tw.group {
    tw.flex,
    tw.row,
    tw.items_center,
    tw.justify_between,
    tw.w_full,
    tw.px_3,
    tw.py_2,
    tw.rounded_md,
    tw.border_1,
    tw.border_color.transparent,
}

M.list_item.frame.interactive = tw.group {
    tw.cursor_pointer,
    tw.selected(tw.bg.violet[100]),
    tw.hover(tw.bg.violet[100]),
    tw.active(tw.bg.violet[200]),
    tw.dark {
        tw.selected(tw.bg.slate[800]),
        tw.hover(tw.bg.slate[800]),
        tw.active(tw.bg.slate[700]),
    },
    tw.disabled {
        tw.opacity_50,
        tw.cursor_not_allowed,
    },
}

M.list_item.title = tw.group {
    tw.text_sm,
    tw.font_medium,
    tw.fg.slate[500],
    tw.selected(tw.fg.slate[900]),
    tw.hover(tw.fg.slate[900]),
    tw.active(tw.fg.slate[900]),
    tw.dark {
        tw.fg.slate[300],
        tw.selected(tw.fg.slate[50]),
        tw.hover(tw.fg.slate[50]),
        tw.active(tw.fg.slate[50]),
    },
}

M.list_item.subtitle = tw.group {
    tw.text_xs,
    tw.fg.slate[500],
    tw.dark(tw.fg.slate[400]),
}

return M
