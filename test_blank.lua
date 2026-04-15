package.path = "examples/ui_widget_demo/?.lua;examples/ui_widget_demo/?/init.lua;./?.lua;./?/init.lua;" .. package.path
local ui = require("ui")
local pvm = require("pvm")
local widgets = require("widgets")
local demo_apply = require("demo_apply")
local T = ui.T

local function P(s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, s950)
    return T.Theme.Palette(s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, s950)
end
local spacing = {}
for i = 1, 35 do spacing[i] = i end
local theme = T.Theme.T(
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0), P(0,0,0,0,0,0,0,0,0,0,0),
    P(0,0,0,0,0,0,0,0,0,0,0), 0xff, 0x00, 0,
    T.Theme.SpaceScale(unpack(spacing)),
    T.Theme.FontScale(12, 14, 16, 18, 20, 24, 30, 36, 48, 60),
    T.Theme.RadiusScale(0, 2, 4, 6, 8, 12, 16, 24, 9999),
    T.Theme.BorderScale(0, 1, 2, 4, 8),
    T.Theme.OpacityScale(0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100),
    T.Theme.Fonts(1, 2, 3, 4, 5)
)

local state = demo_apply.initial_state()
local compose_node = widgets.auth_root(state, 800, 600)
local auth = pvm.one(ui.compose.phase(compose_node))
local env = T.Env.Class(T.Env.Lg, T.Env.Dark, T.Env.MotionSafe, T.Env.D2x)
local layout = pvm.one(ui.lower.phase(auth, theme, env))

-- Just count how many layout nodes we generated
local count = 0
local function count_layout(n)
    if n == nil then return end
    count = count + 1
    if n.children then
        for i=1,#n.children do count_layout(n.children[i]) end
    end
end
count_layout(layout)
print("Layout nodes:", count)
print("Layout dump:", layout)
