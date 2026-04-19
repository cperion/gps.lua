local common = require("ui.widgets._text_common")
local tw = require("ui.tw")

local M = {}

local DEFAULTS = {
    gap_y = 8,
    min_h = 180,
    styles = nil,
    label_styles = tw.list {
        tw.text_sm,
        tw.font_semibold,
        tw.fg.slate[300],
    },
    field_styles = tw.list {
        tw.rounded_xl,
        tw.border_1,
        tw.border_color.slate[800],
        tw.bg.slate[950],
    },
}

function M.node(opts)
    return common.build_shell(opts, DEFAULTS)
end

function M.draw(host, report, field, opts)
    return common.draw_overlay(host, report, field, opts)
end

function M.contains(result, x, y)
    return common.contains(result, x, y)
end

function M.local_point(result, x, y)
    return common.local_point(result, x, y)
end

return M
