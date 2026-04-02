#!/usr/bin/env luajit
--
-- mgps_bench.lua — mgps benchmark harness, parity workloads with clay_bench.c
--
-- Four workloads, matching the clay benchmark:
--   1. flat_list      — N rows with text+tag
--   2. text_heavy     — N text-only rows
--   3. nested_panels  — G groups × 6 cards each
--   4. inspector_mini — toolbar + 3-panel + detail rows
--
-- What we measure:
--   (a) ASDL build    — constructing the interned UI tree
--   (b) layout        — resolving positions (:measure + :place)
--   (c) backend_ir    — projecting to paint IR
--   (d) compile       — emitting gen/state/param (terminal lowering)
--   (e) full_pipeline — (a) through (d) end to end
--   (f) incremental   — recompile with one leaf changed
--
-- Usage:
--   luajit bench/mgps_bench.lua [workload] [count] [iterations]

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local M = require("gps")

-- ═══════════════════════════════════════════════════════════════
-- MOCK TEXT METRICS (same formula as clay benchmark)
-- ═══════════════════════════════════════════════════════════════

local function text_width(font_size, text)
    return #text * font_size * 0.6
end
local function text_height(font_size)
    return font_size * 1.2
end

-- ═══════════════════════════════════════════════════════════════
-- UI SCHEMA
-- ═══════════════════════════════════════════════════════════════

local U = M.context("view")
    :Define [[
        module UI {
            Root = (Node body) unique
            Node = Column(number spacing, Node* children) unique
                 | Row(number spacing, Node* children) unique
                 | Padding(number left, number top, number right, number bottom, Node child) unique
                 | FixedWidth(number w, Node child) unique
                 | FixedSize(number w, number h) unique
                 | Rect(string tag, number w, number h, number rgba8) unique
                 | Text(string tag, number font_size, number rgba8, string text) unique
                 | Group(Node* children) unique
        }
    ]]

-- ═══════════════════════════════════════════════════════════════
-- VIEW SCHEMA
-- ═══════════════════════════════════════════════════════════════

local V = M.context("paint_ast")
    :Define [[
        module View {
            Root = (VNode* nodes) unique
            VNode = Box(number x, number y, number w, number h, number rgba8) unique
                  | Label(number x, number y, number font_size, number rgba8, string text) unique
                  | Group(VNode* children) unique
        }
    ]]

-- ═══════════════════════════════════════════════════════════════
-- PAINT BACKEND IR
-- ═══════════════════════════════════════════════════════════════

local P = M.context("draw")
    :Define [[
        module Paint {
            Frame = (PNode* nodes) unique
            PNode = RectFill(number x, number y, number w, number h, number rgba8) unique
                  | DrawText(number x, number y, number font_size, number rgba8, string text) unique
                  | Group(PNode* children) unique
        }
    ]]

-- ═══════════════════════════════════════════════════════════════
-- LAYOUT
-- ═══════════════════════════════════════════════════════════════

function U.UI.Rect:measure()
    return self.w, self.h
end
function U.UI.Rect:place(x, y)
    return { V.View.Box(x, y, self.w, self.h, self.rgba8) }
end

function U.UI.Text:measure()
    return text_width(self.font_size, self.text), text_height(self.font_size)
end
function U.UI.Text:place(x, y)
    return { V.View.Label(x, y, self.font_size, self.rgba8, self.text) }
end

function U.UI.FixedSize:measure()
    return self.w, self.h
end
function U.UI.FixedSize:place(x, y)
    return {}
end

function U.UI.FixedWidth:measure()
    local _, ch = self.child:measure()
    return self.w, ch
end
function U.UI.FixedWidth:place(x, y)
    return self.child:place(x, y)
end

function U.UI.Group:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end
        if ch > h then h = ch end
    end
    return w, h
end
function U.UI.Group:place(x, y)
    local out = {}
    for i = 1, #self.children do
        local nodes = self.children[i]:place(x, y)
        for j = 1, #nodes do out[#out+1] = nodes[j] end
    end
    return out
end

function U.UI.Column:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end
        h = h + ch
        if i > 1 then h = h + self.spacing end
    end
    return w, h
end
function U.UI.Column:place(x, y)
    local out = {}
    local cy = y
    for i = 1, #self.children do
        local child = self.children[i]
        local _, ch = child:measure()
        local nodes = child:place(x, cy)
        for j = 1, #nodes do out[#out+1] = nodes[j] end
        cy = cy + ch + self.spacing
    end
    return out
end

function U.UI.Row:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        w = w + cw
        if i > 1 then w = w + self.spacing end
        if ch > h then h = ch end
    end
    return w, h
end
function U.UI.Row:place(x, y)
    local out = {}
    local cx = x
    for i = 1, #self.children do
        local child = self.children[i]
        local cw = child:measure()
        local nodes = child:place(cx, y)
        for j = 1, #nodes do out[#out+1] = nodes[j] end
        cx = cx + cw + self.spacing
    end
    return out
end

function U.UI.Padding:measure()
    local cw, ch = self.child:measure()
    return self.left + cw + self.right, self.top + ch + self.bottom
end
function U.UI.Padding:place(x, y)
    return self.child:place(x + self.left, y + self.top)
end

-- ═══════════════════════════════════════════════════════════════
-- VIEW → PAINT IR
-- ═══════════════════════════════════════════════════════════════

function V.View.Root:paint_ast()
    local out = {}
    for i = 1, #self.nodes do out[i] = self.nodes[i]:paint_ast() end
    return P.Paint.Frame(out)
end

function V.View.Box:paint_ast()
    return P.Paint.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
end

function V.View.Label:paint_ast()
    return P.Paint.DrawText(self.x, self.y, self.font_size, self.rgba8, self.text)
end

function V.View.Group:paint_ast()
    local out = {}
    for i = 1, #self.children do out[i] = self.children[i]:paint_ast() end
    return P.Paint.Group(out)
end

-- ═══════════════════════════════════════════════════════════════
-- TERMINAL — emit gen/state/param
-- ═══════════════════════════════════════════════════════════════

local function rect_fill_gen(param, state, g)
    g.rect_count = g.rect_count + 1
    return g
end

local function draw_text_gen(param, state, g)
    g.text_count = g.text_count + 1
    return g
end

local function next_pow2(n)
    local p = 1
    while p < n do p = p * 2 end
    return p
end

function P.Paint.RectFill:draw()
    return M.emit(
        rect_fill_gen,
        M.state.none(),
        { x = self.x, y = self.y, w = self.w, h = self.h, rgba8 = self.rgba8 }
    )
end

function P.Paint.DrawText:draw()
    return M.emit(
        draw_text_gen,
        M.state.resource("TextBlob", {
            cap = next_pow2(#self.text),
            font_size = self.font_size,
        }),
        { x = self.x, y = self.y, font_size = self.font_size, rgba8 = self.rgba8, text = self.text }
    )
end

function P.Paint.Group:draw()
    local children = {}
    for i = 1, #self.nodes do children[i] = self.nodes[i]:draw() end
    return M.compose(children)
end

function P.Paint.Frame:draw()
    local children = {}
    for i = 1, #self.nodes do children[i] = self.nodes[i]:draw() end
    return M.compose(children)
end

-- ═══════════════════════════════════════════════════════════════
-- FULL PIPELINE
-- ═══════════════════════════════════════════════════════════════

local compile_paint = M.lower("full_pipeline", function(root)
    local view = V.View.Root(root.body:place(0, 0))
    return view:paint_ast():draw()
end)

-- ═══════════════════════════════════════════════════════════════
-- WORKLOAD BUILDERS
-- ═══════════════════════════════════════════════════════════════

local function rgba(r, g, b, a)
    local ri = math.floor(r * 255 + 0.5)
    local gi = math.floor(g * 255 + 0.5)
    local bi = math.floor(b * 255 + 0.5)
    local ai = math.floor(a * 255 + 0.5)
    return ri * 16777216 + gi * 65536 + bi * 256 + ai
end

local function build_flat_list(n)
    local rows = {}
    for i = 1, n do
        local name = string.format("Row %d", i - 1)
        local tag = string.format("Tag %d", (i - 1) % 16)
        rows[i] = U.UI.Row(8, {
            U.UI.Text("name", 15, rgba(0.92, 0.93, 0.95, 1), name),
            U.UI.Rect("tag_bg", text_width(13, tag) + 8, text_height(13) + 8, rgba(0.17, 0.24, 0.34, 1)),
        })
    end
    return U.UI.Root(
        U.UI.Padding(8, 8, 8, 8,
            U.UI.Column(2, rows)
        )
    )
end

local function build_text_heavy(n)
    local rows = {}
    for i = 1, n do
        local text = string.format("Text row %d with a modest amount of content for measurement.", i - 1)
        rows[i] = U.UI.Padding(4, 4, 4, 4,
            U.UI.Text("text", 15, rgba(0.92, 0.93, 0.95, 1), text)
        )
    end
    return U.UI.Root(
        U.UI.Padding(10, 10, 10, 10,
            U.UI.Column(4, rows)
        )
    )
end

local function build_nested_panels(g)
    local groups = {}
    for gi = 1, g do
        local cards = {}
        for i = 1, 6 do
            local title = string.format("Card %d.%d", gi - 1, i - 1)
            cards[i] = U.UI.Padding(6, 6, 6, 6,
                U.UI.Column(4, {
                    U.UI.Text("title", 15, rgba(0.96, 0.97, 0.98, 1), title),
                    U.UI.Text("body", 13, rgba(0.70, 0.74, 0.80, 1), "Nested panel content"),
                })
            )
        end
        groups[gi] = U.UI.Padding(8, 8, 8, 8,
            U.UI.Column(6, cards)
        )
    end
    return U.UI.Root(
        U.UI.Padding(8, 8, 8, 8,
            U.UI.Row(8, groups)
        )
    )
end

local function build_inspector_mini(n)
    -- Toolbar
    local tabs = {}
    for i = 1, 3 do
        local label = string.format("Tab %d", i - 1)
        tabs[i] = U.UI.Padding(6, 6, 6, 6,
            U.UI.Text("tab", 14, rgba(1, 1, 1, 1), label)
        )
    end
    local toolbar = U.UI.Row(6, tabs)

    -- Assets
    local assets = {}
    assets[1] = U.UI.Text("assets_title", 18, rgba(0.96, 0.97, 0.98, 1), "Assets")
    for i = 1, n do
        local label = string.format("Asset %d", i - 1)
        assets[i + 1] = U.UI.Padding(5, 5, 5, 5,
            U.UI.Text("asset", 14, rgba(0.92, 0.93, 0.95, 1), label)
        )
    end
    local assets_panel = U.UI.FixedWidth(260,
        U.UI.Padding(8, 8, 8, 8,
            U.UI.Column(4, assets)
        )
    )

    -- Center
    local center = U.UI.Column(8, {
        U.UI.Text("preview_title", 20, rgba(0.96, 0.97, 0.98, 1), "Preview"),
        U.UI.FixedSize(320, 180),
    })

    -- Inspector
    local inspector_rows = {}
    inspector_rows[1] = U.UI.Text("insp_title", 18, rgba(0.96, 0.97, 0.98, 1), "Inspector")
    for i = 1, 12 do
        local lhs = string.format("Field %d", i - 1)
        local rhs = string.format("%d", 100 + (i - 1) * 7)
        inspector_rows[i + 1] = U.UI.Row(6, {
            U.UI.Text("lhs", 14, rgba(0.92, 0.93, 0.95, 1), lhs),
            U.UI.Text("rhs", 14, rgba(0.72, 0.80, 0.96, 1), rhs),
        })
    end
    local inspector_panel = U.UI.FixedWidth(240,
        U.UI.Padding(8, 8, 8, 8,
            U.UI.Column(4, inspector_rows)
        )
    )

    return U.UI.Root(
        U.UI.Padding(10, 10, 10, 10,
            U.UI.Column(10, {
                toolbar,
                U.UI.Row(10, {
                    assets_panel,
                    center,
                    inspector_panel,
                }),
            })
        )
    )
end

-- ═══════════════════════════════════════════════════════════════
-- TIMING
-- ═══════════════════════════════════════════════════════════════

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } bench_timespec;
    int clock_gettime(int, bench_timespec *);
]]
local CLOCK_MONOTONIC = jit.os == "Linux" and 1 or 6  -- 6 for macOS
local ts_buf = ffi.new("bench_timespec")

local function now_sec()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts_buf)
    return tonumber(ts_buf.tv_sec) + tonumber(ts_buf.tv_nsec) * 1e-9
end

-- ═══════════════════════════════════════════════════════════════
-- BENCHMARK RUNNER
-- ═══════════════════════════════════════════════════════════════

local function count_nodes(root)
    -- count leaf view nodes produced
    local view = V.View.Root(root.body:place(0, 0))
    local n = 0
    local function walk(nodes)
        for i = 1, #nodes do
            local v = nodes[i]
            n = n + 1
            if v.children then walk(v.children) end
        end
    end
    walk(view.nodes)
    return n
end

local function run_bench(name, build_fn, count, iters)
    -- Phase 0: build tree once, count output
    local root = build_fn(count)
    local view_nodes = count_nodes(root)

    -- Warmup
    for w = 1, 10 do
        compile_paint.reset()
        compile_paint(root)
    end

    -- Phase 1: full pipeline (cold — no cache)
    local t0 = now_sec()
    for i = 1, iters do
        compile_paint.reset()
        compile_paint(root)
    end
    local cold_elapsed = now_sec() - t0
    local cold_us = cold_elapsed / iters * 1e6

    -- Phase 2: full pipeline (hot — cache hits)
    compile_paint.reset()
    compile_paint(root)  -- prime cache
    local t1 = now_sec()
    for i = 1, iters do
        compile_paint(root)  -- same interned tree → L1 hit
    end
    local hot_elapsed = now_sec() - t1
    local hot_us = hot_elapsed / iters * 1e6

    -- Phase 3: incremental — rebuild with one leaf changed
    local inc_us = 0
    do
        compile_paint.reset()
        compile_paint(root)  -- prime

        -- Build a slightly modified tree (change one text)
        local function make_modified()
            if name == "flat_list" or name == "text_heavy" then
                -- We reconstruct with one changed row
                return build_fn(count)  -- different string → new root but mostly shared children
            else
                return build_fn(count)
            end
        end

        -- Alternate between two trees to measure incremental
        local root_a = root
        local root_b_base = build_fn(count)  -- same structure, re-interned → same objects!
        -- Force a real change: modify count slightly
        local root_b
        if count > 1 then
            root_b = build_fn(count)  -- with interning this is same as root_a
        end

        -- For a real incremental test, change one value
        -- The easiest: rebuild the tree but with count+1, then back
        local root_alt = build_fn(count + 1)

        compile_paint.reset()
        compile_paint(root)
        local t2 = now_sec()
        for i = 1, iters do
            if i % 2 == 0 then
                compile_paint(root)
            else
                compile_paint(root_alt)
            end
        end
        local inc_elapsed = now_sec() - t2
        inc_us = inc_elapsed / iters * 1e6
    end

    return {
        name = name,
        count = count,
        view_nodes = view_nodes,
        cold_us = cold_us,
        hot_us = hot_us,
        inc_us = inc_us,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- MAIN
-- ═══════════════════════════════════════════════════════════════

local workload = arg[1] or "all"
local count = tonumber(arg[2]) or 100
local iters = tonumber(arg[3]) or 1000

local tests = {
    { "flat_list",      build_flat_list },
    { "text_heavy",     build_text_heavy },
    { "nested_panels",  build_nested_panels },
    { "inspector_mini", build_inspector_mini },
}

print(string.format("mgps_bench  count=%d  iters=%d", count, iters))
print(string.format("%-20s %10s %12s %12s %12s %12s",
    "workload", "nodes", "cold_us", "hot_us", "increm_us", "cold_iter/s"))

for _, t in ipairs(tests) do
    local name, fn = t[1], t[2]
    if workload == "all" or workload == name then
        local r = run_bench(name, fn, count, iters)
        print(string.format("%-20s %10d %12.2f %12.2f %12.2f %12.0f",
            r.name, r.view_nodes, r.cold_us, r.hot_us, r.inc_us, 1e6 / r.cold_us))
    end
end

-- Print cache stats from the last run
print("")
print("Cache stats (last run):")
print(M.report({ compile_paint }))
