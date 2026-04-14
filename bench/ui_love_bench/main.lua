package.path = "../?.lua;../?/init.lua;../../?.lua;../../?/init.lua;./?.lua;./?/init.lua;" .. package.path

love = love or {}

local pvm = require("pvm")
local ui = require("ui")

local T = ui.T
local tw = ui.tw
local b = ui.build

local TEXT_SYSTEM = "ui-love-bench"
local VIEW_W = 1280
local VIEW_H = 800
local ENV_CLASS = T.Env.Class(T.Env.Lg, T.Env.Dark, T.Env.MotionSafe, T.Env.D2x)
local SOLVE_ENV = T.Solve.Env(VIEW_W, VIEW_H, {})

local THEME
local DRIVER
local RESULTS

local function P(s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, s950)
    return T.Theme.Palette(s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, s950)
end

local function make_theme()
    local spacing = {}
    for i = 1, 35 do spacing[i] = i end
    return T.Theme.T(
        P(0xf8fafcff, 0xf1f5f9ff, 0xe2e8f0ff, 0xcbd5e1ff, 0x94a3b8ff, 0x64748bff, 0x475569ff, 0x334155ff, 0x1e293bff, 0x0f172aff, 0x020617ff),
        P(0xf9fafbff, 0xf3f4f6ff, 0xe5e7ebff, 0xd1d5dbff, 0x9ca3afff, 0x6b7280ff, 0x4b5563ff, 0x374151ff, 0x1f2937ff, 0x111827ff, 0x030712ff),
        P(0xfafafaff, 0xf4f4f5ff, 0xe4e4e7ff, 0xd4d4d8ff, 0xa1a1aaff, 0x71717aff, 0x52525bff, 0x3f3f46ff, 0x27272aff, 0x18181bff, 0x09090bff),
        P(0xfafafaff, 0xf5f5f5ff, 0xe5e5e5ff, 0xd4d4d4ff, 0xa3a3a3ff, 0x737373ff, 0x525252ff, 0x404040ff, 0x262626ff, 0x171717ff, 0x0a0a0aff),
        P(0xfafaf9ff, 0xf5f5f4ff, 0xe7e5e4ff, 0xd6d3d1ff, 0xa8a29eff, 0x78716cff, 0x57534eff, 0x44403cff, 0x292524ff, 0x1c1917ff, 0x0c0a09ff),
        P(0xfef2f2ff, 0xfee2e2ff, 0xfecacaff, 0xfca5a5ff, 0xf87171ff, 0xef4444ff, 0xdc2626ff, 0xb91c1cff, 0x991b1bff, 0x7f1d1dff, 0x450a0aff),
        P(0xfff7edff, 0xffedd5ff, 0xfed7aaff, 0xfdba74ff, 0xfb923cff, 0xf97316ff, 0xea580cff, 0xc2410cff, 0x9a3412ff, 0x7c2d12ff, 0x431407ff),
        P(0xfffbebff, 0xfef3c7ff, 0xfde68aff, 0xfcd34dff, 0xfbbf24ff, 0xf59e0bff, 0xd97706ff, 0xb45309ff, 0x92400eff, 0x78350fff, 0x451a03ff),
        P(0xfefce8ff, 0xfef9c3ff, 0xfef08aff, 0xfde047ff, 0xfacc15ff, 0xeab308ff, 0xca8a04ff, 0xa16207ff, 0x854d0eff, 0x713f12ff, 0x422006ff),
        P(0xf7fee7ff, 0xecfccbff, 0xd9f99dff, 0xbef264ff, 0xa3e635ff, 0x84cc16ff, 0x65a30dff, 0x4d7c0fff, 0x3f6212ff, 0x365314ff, 0x1a2e05ff),
        P(0xf0fdf4ff, 0xdcfce7ff, 0xbbf7d0ff, 0x86efacff, 0x4ade80ff, 0x22c55eff, 0x16a34aff, 0x15803dff, 0x166534ff, 0x14532dff, 0x052e16ff),
        P(0xecfdf5ff, 0xd1fae5ff, 0xa7f3d0ff, 0x6ee7b7ff, 0x34d399ff, 0x10b981ff, 0x059669ff, 0x047857ff, 0x065f46ff, 0x064e3bff, 0x022c22ff),
        P(0xf0fdfaff, 0xccfbf1ff, 0x99f6e4ff, 0x5eead4ff, 0x2dd4bfff, 0x14b8a6ff, 0x0d9488ff, 0x0f766eff, 0x115e59ff, 0x134e4aff, 0x042f2eff),
        P(0xecfeffff, 0xcffafeff, 0xa5f3fcff, 0x67e8f9ff, 0x22d3eeff, 0x06b6d4ff, 0x0891b2ff, 0x0e7490ff, 0x155e75ff, 0x164e63ff, 0x083344ff),
        P(0xf0f9ffff, 0xe0f2feff, 0xbae6fdff, 0x7dd3fcff, 0x38bdf8ff, 0x0ea5e9ff, 0x0284c7ff, 0x0369a1ff, 0x075985ff, 0x0c4a6eff, 0x082f49ff),
        P(0xeff6ffff, 0xdbeafeff, 0xbfdbfeff, 0x93c5fdff, 0x60a5faff, 0x3b82f6ff, 0x2563ebff, 0x1d4ed8ff, 0x1e40afff, 0x1e3a8aff, 0x172554ff),
        P(0xeef2ffff, 0xe0e7ffff, 0xc7d2feff, 0xa5b4fcff, 0x818cf8ff, 0x6366f1ff, 0x4f46e5ff, 0x4338caff, 0x3730a3ff, 0x312e81ff, 0x1e1b4bff),
        P(0xf5f3ffff, 0xede9feff, 0xddd6feff, 0xc4b5fdff, 0xa78bfaff, 0x8b5cf6ff, 0x7c3aedff, 0x6d28d9ff, 0x5b21b6ff, 0x4c1d95ff, 0x2e1065ff),
        P(0xfaf5ffff, 0xf3e8ffff, 0xe9d5ffff, 0xd8b4feff, 0xc084fcff, 0xa855f7ff, 0x9333eaff, 0x7e22ceff, 0x6b21a8ff, 0x581c87ff, 0x3b0764ff),
        P(0xfdf4ffff, 0xfae8ffff, 0xf5d0feff, 0xf0abfcff, 0xe879f9ff, 0xd946efff, 0xc026d3ff, 0xa21cafff, 0x86198fff, 0x701a75ff, 0x4a044eff),
        P(0xfdf2f8ff, 0xfce7f3ff, 0xfbcfe8ff, 0xf9a8d4ff, 0xf472b6ff, 0xec4899ff, 0xdb2777ff, 0xbe185dff, 0x9d174dff, 0x831843ff, 0x500724ff),
        P(0xfff1f2ff, 0xffe4e6ff, 0xfecdd3ff, 0xfda4afff, 0xfb7185ff, 0xf43f5eff, 0xe11d48ff, 0xbe123cff, 0x9f1239ff, 0x881337ff, 0x4c0519ff),
        0xffffffff,
        0x000000ff,
        0x00000000,
        T.Theme.SpaceScale(unpack(spacing)),
        T.Theme.FontScale(12, 14, 16, 18, 20, 24, 30, 36, 48, 60),
        T.Theme.RadiusScale(0, 2, 4, 6, 8, 12, 16, 24, 9999),
        T.Theme.BorderScale(0, 1, 2, 4, 8),
        T.Theme.OpacityScale(0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100),
        T.Theme.Fonts(1, 2, 3, 4, 5)
    )
end

local function install_fonts()
    local fonts = {
        [1] = love.graphics.newFont(14),
        [2] = love.graphics.newFont(16),
        [3] = love.graphics.newFont(18),
        [4] = love.graphics.newFont(24),
    }
    ui.text.register(TEXT_SYSTEM, ui.text_love.new({ fonts = fonts }))
    DRIVER = ui.runtime_love.new({ fonts = fonts })
end

local function reset_phases()
    ui.lower.phase:reset()
    ui.normalize.normalize_phase:reset()
    ui.resolve.phase:reset()
    ui.measure.phase:reset()
    ui.measure.text_layout_phase:reset()
    ui.render.phase:reset()
end

local function bench_us(iters, fn)
    for _ = 1, math.min(10, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = love.timer.getTime()
    for _ = 1, iters do fn() end
    return (love.timer.getTime() - t0) * 1e6 / iters
end

local function changed_suffix(serial)
    if serial == nil then return "" end
    return " #" .. serial
end

local function build_row(i, changed, serial)
    local title
    if changed == i then
        title = "changed item " .. i .. changed_suffix(serial)
    else
        title = "item " .. i
    end
    return b.with_input(b.id("row:" .. i), T.Interact.ActivateTarget,
        b.box {
            b.id("row-card:" .. i),
            tw.flow,
            tw.gap_y_2,
            tw.p_3,
            tw.rounded_lg,
            tw.border_1,
            tw.border_color.slate[700],
            tw.bg.slate[900],
            b.text { tw.text_base, tw.font_semibold, tw.fg.white, title },
            b.text { tw.text_sm, tw.fg.slate[300], "row detail text for Love benchmark item " .. i },
        })
end

local function workload_flat_list(n, changed, serial)
    local rows = {}
    for i = 1, n do
        rows[i] = build_row(i, changed, serial)
    end
    return b.box {
        b.id("root"), tw.flow, tw.w_px(VIEW_W), tw.h_px(VIEW_H), tw.bg.slate[950], tw.p_4, tw.gap_y_2,
        b.text { tw.text_xl, tw.font_semibold, tw.fg.white, "flat list" },
        b.box { b.id("list"), tw.flow, tw.gap_y_2, b.fragment(rows) },
    }
end

local LOREM = "Love-backed UI benchmark text wrapping through ui.text_love with enough words to force real wrapping and width measurement."

local function workload_text_heavy(n, changed, serial)
    local items = {}
    for i = 1, n do
        local content = LOREM .. " paragraph=" .. i
        if changed == i then content = content .. " changed" .. changed_suffix(serial) end
        items[i] = b.box {
            b.id("p:" .. i), tw.flow, tw.p_3, tw.rounded_md, tw.border_1, tw.border_color.slate[800], tw.bg.slate[900],
            b.text { tw.text_base, tw.fg.slate[100], content },
        }
    end
    return b.box {
        b.id("root"), tw.flow, tw.w_px(VIEW_W), tw.h_px(VIEW_H), tw.bg.slate[950], tw.p_4, tw.gap_y_3,
        b.text { tw.text_xl, tw.font_semibold, tw.fg.white, "text heavy" },
        b.fragment(items),
    }
end

local function workload_nested_panels(n, changed, serial)
    local groups = {}
    local per = 6
    for g = 1, n do
        local cards = {}
        for j = 1, per do
            local idx = (g - 1) * per + j
            local label
            if changed == idx then
                label = "changed card " .. idx .. changed_suffix(serial)
            else
                label = "card " .. idx
            end
            cards[j] = b.box {
                b.id("card:" .. idx), tw.flow, tw.p_3, tw.rounded_lg, tw.border_1, tw.border_color.slate[800], tw.bg.slate[900],
                b.text { tw.text_base, tw.font_semibold, tw.fg.white, label },
                b.text { tw.text_sm, tw.fg.slate[300], "nested panel payload" },
            }
        end
        groups[g] = b.box {
            b.id("group:" .. g), tw.flow, tw.gap_y_2, tw.p_3, tw.rounded_xl, tw.border_1, tw.border_color.slate[700], tw.bg.slate[950],
            b.text { tw.text_lg, tw.font_semibold, tw.fg.sky[300], "group " .. g },
            b.box { b.id("row:" .. g), tw.flex, tw.row, tw.wrap, tw.gap_3, b.fragment(cards) },
        }
    end
    return b.box {
        b.id("root"), tw.flow, tw.w_px(VIEW_W), tw.h_px(VIEW_H), tw.bg.slate[950], tw.p_4, tw.gap_y_4,
        b.text { tw.text_xl, tw.font_semibold, tw.fg.white, "nested panels" },
        b.fragment(groups),
    }
end

local workloads = {
    { name = "flat_list", n = 120, iters = 20, build = workload_flat_list, changed = function(n) return math.floor(n / 2) end },
    { name = "text_heavy", n = 80, iters = 16, build = workload_text_heavy, changed = function(n) return math.floor(n / 2) end },
    { name = "nested_panels", n = 24, iters = 12, build = workload_nested_panels, changed = function(n) return math.floor((n * 6) / 2) end },
}

local function lower_one(auth)
    return pvm.one(ui.lower.phase(auth, THEME, ENV_CLASS))
end

local function render_ops(layout)
    return pvm.drain(ui.render.root(layout, SOLVE_ENV, TEXT_SYSTEM))
end

local function full_run(auth)
    local layout = lower_one(auth)
    DRIVER:reset()
    return ui.runtime.run(DRIVER, {
        pointer_x = -1,
        pointer_y = -1,
        scrolls = {},
    }, ui.render.root(layout, SOLVE_ENV, TEXT_SYSTEM))
end

local function run_workload(spec)
    local changed_idx = spec.changed(spec.n)
    local inc_variant_count = math.max(12, math.min(48, spec.n * (spec.name == "nested_panels" and 2 or 1)))
    local auth_base = spec.build(spec.n, nil)
    local auth_inc = {}
    for i = 1, inc_variant_count do
        auth_inc[i] = spec.build(spec.n, changed_idx, i)
    end
    local inc_pos = 0
    local function next_inc_auth()
        inc_pos = inc_pos + 1
        if inc_pos > #auth_inc then inc_pos = 1 end
        return auth_inc[inc_pos]
    end
    local layout = lower_one(auth_base)
    local op_count = #render_ops(layout)

    local cold = bench_us(spec.iters, function()
        reset_phases()
        full_run(auth_base)
    end)

    reset_phases()
    full_run(auth_base)
    local hot = bench_us(spec.iters, function()
        full_run(auth_base)
    end)

    reset_phases()
    full_run(auth_base)
    local inc = bench_us(spec.iters, function()
        full_run(next_inc_auth())
    end)

    return {
        name = spec.name,
        n = spec.n,
        iters = spec.iters,
        op_count = op_count,
        cold = cold,
        hot = hot,
        inc = inc,
        report = pvm.report_string({
            ui.normalize.normalize_phase,
            ui.resolve.phase,
            ui.lower.phase,
            ui.measure.text_layout_phase,
            ui.measure.phase,
            ui.render.phase,
        }),
    }
end

function love.load()
    love.graphics.setBackgroundColor(0.03, 0.05, 0.08, 1)
    THEME = make_theme()
    install_fonts()
end

function love.draw()
    if RESULTS == nil then
        local out = {}
        for i = 1, #workloads do
            reset_phases()
            out[i] = run_workload(workloads[i])
        end
        RESULTS = out

        print("ui Love bench (real ui.text_love + ui.runtime_love)")
        print("")
        for i = 1, #RESULTS do
            local r = RESULTS[i]
            print(string.format("%s n=%d iters=%d ops=%d", r.name, r.n, r.iters, r.op_count))
            print(string.format("  full cold         %9.2f us/op", r.cold))
            print(string.format("  full hot          %9.2f us/op", r.hot))
            print(string.format("  full incremental  %9.2f us/op", r.inc))
            print(r.report)
            print("")
        end
        love.event.quit()
        return
    end
end
