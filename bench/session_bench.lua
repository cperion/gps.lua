#!/usr/bin/env luajit
--
-- session_bench.lua — Realistic session simulation for mgps
--
-- The honest question for a retained-mode UI system is NOT:
--   "How fast is a cache hit?" (trivially fast, meaningless to measure)
--   "How fast is cold build vs Clay?" (unfair: different paradigm)
--
-- The honest question IS:
--   "In a realistic interactive session, what is the total CPU work
--    spent on UI compilation, and how does that compare to an
--    immediate-mode system that rebuilds every frame?"
--
-- This benchmark simulates a realistic session:
--   - 3600 frames (60 seconds at 60fps)
--   - User events arrive at realistic rates
--   - Different event types: hover (frequent), click (moderate),
--     typing (burst), idle (common)
--   - After each event, we rebuild the ASDL source, recompile, and
--     execute the machine (slot.callback) — all three phases
--
-- We measure WALL-CLOCK TIME of the entire session, which includes:
--   - ASDL tree construction (build_ui)
--   - Full lowering pipeline (layout → view → backend IR → terminal)
--   - Machine execution (slot.callback into a counting backend)
--
-- For Clay comparison, the equivalent is:
--   3600 × (Clay_BeginLayout + build + Clay_EndLayout + walk render commands)
--
-- This is the apples-to-apples number: total CPU cost of UI for N frames.

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local M = require("gps")

-- ═══════════════════════════════════════════════════════════════
-- TIMER
-- ═══════════════════════════════════════════════════════════════

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } bench_ts;
    int clock_gettime(int, bench_ts *);
]]
local CLOCK_MONOTONIC = 1
local ts = ffi.new("bench_ts")
local function now()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

-- ═══════════════════════════════════════════════════════════════
-- MOCK TEXT METRICS (identical to clay bench)
-- ═══════════════════════════════════════════════════════════════

local function tw(sz, text) return #text * sz * 0.6 end
local function th(sz) return sz * 1.2 end

-- ═══════════════════════════════════════════════════════════════
-- SCHEMAS
-- ═══════════════════════════════════════════════════════════════

local U = M.context("view"):Define [[
    module UI {
        Root = (Node body) unique
        Node = Column(number sp, Node* ch) unique
             | Row(number sp, Node* ch) unique
             | Pad(number l, number t, number r, number b, Node child) unique
             | Rect(string tag, number w, number h, number rgba) unique
             | Text(string tag, number sz, number rgba, string text) unique
             | Group(Node* ch) unique
    }
]]

local V = M.context("paint_ast"):Define [[
    module View {
        Root = (VNode* nodes) unique
        VNode = Box(number x, number y, number w, number h, number rgba) unique
              | Label(number x, number y, number sz, number rgba, string text) unique
              | Group(VNode* ch) unique
    }
]]

local P = M.context("draw"):Define [[
    module Paint {
        Frame = (PNode* nodes) unique
        PNode = RectFill(number x, number y, number w, number h, number rgba) unique
              | DrawText(number x, number y, number sz, number rgba, string text) unique
              | Group(PNode* ch) unique
    }
]]

-- ═══════════════════════════════════════════════════════════════
-- LAYOUT
-- ═══════════════════════════════════════════════════════════════

function U.UI.Rect:measure() return self.w, self.h end
function U.UI.Rect:place(x,y) return { V.View.Box(x,y,self.w,self.h,self.rgba) } end
function U.UI.Text:measure() return tw(self.sz,self.text), th(self.sz) end
function U.UI.Text:place(x,y) return { V.View.Label(x,y,self.sz,self.rgba,self.text) } end
function U.UI.Group:measure()
    local w,h = 0,0
    for i=1,#self.ch do local cw,ch2 = self.ch[i]:measure(); if cw>w then w=cw end; if ch2>h then h=ch2 end end
    return w,h
end
function U.UI.Group:place(x,y)
    local o={}; for i=1,#self.ch do local n=self.ch[i]:place(x,y); for j=1,#n do o[#o+1]=n[j] end end; return o
end
function U.UI.Column:measure()
    local w,h = 0,0
    for i=1,#self.ch do local cw,ch2=self.ch[i]:measure(); if cw>w then w=cw end; h=h+ch2; if i>1 then h=h+self.sp end end
    return w,h
end
function U.UI.Column:place(x,y)
    local o,cy={},y
    for i=1,#self.ch do local c=self.ch[i]; local _,ch2=c:measure(); local n=c:place(x,cy); for j=1,#n do o[#o+1]=n[j] end; cy=cy+ch2+self.sp end
    return o
end
function U.UI.Row:measure()
    local w,h = 0,0
    for i=1,#self.ch do local cw,ch2=self.ch[i]:measure(); w=w+cw; if i>1 then w=w+self.sp end; if ch2>h then h=ch2 end end
    return w,h
end
function U.UI.Row:place(x,y)
    local o,cx={},x
    for i=1,#self.ch do local c=self.ch[i]; local cw=c:measure(); local n=c:place(cx,y); for j=1,#n do o[#o+1]=n[j] end; cx=cx+cw+self.sp end
    return o
end
function U.UI.Pad:measure()
    local cw,ch = self.child:measure(); return self.l+cw+self.r, self.t+ch+self.b
end
function U.UI.Pad:place(x,y) return self.child:place(x+self.l, y+self.t) end

-- ═══════════════════════════════════════════════════════════════
-- VIEW → PAINT
-- ═══════════════════════════════════════════════════════════════

function V.View.Root:paint_ast()
    local o={}; for i=1,#self.nodes do o[i]=self.nodes[i]:paint_ast() end; return P.Paint.Frame(o)
end
function V.View.Box:paint_ast() return P.Paint.RectFill(self.x,self.y,self.w,self.h,self.rgba) end
function V.View.Label:paint_ast() return P.Paint.DrawText(self.x,self.y,self.sz,self.rgba,self.text) end
function V.View.Group:paint_ast()
    local o={}; for i=1,#self.ch do o[i]=self.ch[i]:paint_ast() end; return P.Paint.Group(o)
end

-- ═══════════════════════════════════════════════════════════════
-- TERMINAL
-- ═══════════════════════════════════════════════════════════════

local function rect_gen(p,s,g) g.rects=g.rects+1; return g end
local function text_gen(p,s,g) g.texts=g.texts+1; return g end
local function next_pow2(n) local p=1; while p<n do p=p*2 end; return p end

function P.Paint.RectFill:draw()
    return M.emit(rect_gen, M.state.none(), {x=self.x,y=self.y,w=self.w,h=self.h,rgba=self.rgba})
end
function P.Paint.DrawText:draw()
    return M.emit(text_gen,
        M.state.resource("TextBlob",{cap=next_pow2(#self.text),sz=self.sz}),
        {x=self.x,y=self.y,sz=self.sz,rgba=self.rgba,text=self.text})
end
function P.Paint.Group:draw()
    local c={}; for i=1,#self.ch do c[i]=self.ch[i]:draw() end; return M.compose(c)
end
function P.Paint.Frame:draw()
    local c={}; for i=1,#self.nodes do c[i]=self.nodes[i]:draw() end; return M.compose(c)
end

local compile = M.lower("compile", function(root)
    local view = V.View.Root(root.body:place(0,0))
    return view:paint_ast():draw()
end)

-- ═══════════════════════════════════════════════════════════════
-- APPLICATION STATE + BUILD
-- ═══════════════════════════════════════════════════════════════

local function rgba(r,g,b,a)
    return math.floor(r*255+0.5)*16777216 + math.floor(g*255+0.5)*65536
         + math.floor(b*255+0.5)*256 + math.floor(a*255+0.5)
end

local BG      = rgba(0.08,0.09,0.11,1)
local ROW_A   = rgba(0.14,0.15,0.18,1)
local ROW_B   = rgba(0.12,0.13,0.16,1)
local FG      = rgba(0.92,0.93,0.95,1)
local HOVER   = rgba(0.30,0.40,0.60,1)
local ACTIVE  = rgba(0.40,0.55,0.90,1)

local function build_ui(state)
    local rows = {}
    for i = 1, state.n do
        local bg = (i % 2 == 0) and ROW_A or ROW_B
        if i == state.hover then bg = HOVER end
        if i == state.active then bg = ACTIVE end
        local label = state.labels[i]
        rows[i] = U.UI.Group({
            U.UI.Rect("row"..i, 600, th(15)+12, bg),
            U.UI.Pad(6,6,6,6,
                U.UI.Text("label"..i, 15, FG, label)
            ),
        })
    end
    return U.UI.Root(
        U.UI.Pad(10,10,10,10,
            U.UI.Column(2, rows)
        )
    )
end

-- ═══════════════════════════════════════════════════════════════
-- SESSION SIMULATION
-- ═══════════════════════════════════════════════════════════════

local function run_session(n_items, n_frames, seed)
    -- Deterministic PRNG
    local rng_state = seed or 12345
    local function rng()
        rng_state = (rng_state * 1103515245 + 12345) % 2147483648
        return rng_state
    end
    local function rng_range(lo, hi)
        return lo + (rng() % (hi - lo + 1))
    end

    -- Initial state
    local state = {
        n = n_items,
        hover = 0,
        active = 0,
        labels = {},
    }
    for i = 1, n_items do
        state.labels[i] = string.format("Item %d — initial content", i)
    end

    -- Build initial tree
    local slot = M.slot()
    local root = build_ui(state)
    compile.reset()
    slot:update(compile(root))

    -- Counting backend
    local gfx = { rects = 0, texts = 0 }
    local function reset_gfx() gfx.rects = 0; gfx.texts = 0 end

    -- Counters
    local builds = 0        -- how many times we called build_ui
    local compiles = 0      -- how many times compile actually ran (not cached)
    local executes = 0      -- how many times slot.callback ran
    local source_changes = 0
    local cache_hits = 0

    local t_build = 0       -- wall time in build_ui
    local t_compile = 0     -- wall time in compile + slot:update
    local t_exec = 0        -- wall time in slot.callback

    for frame = 1, n_frames do
        local changed = false
        local r = rng() % 100

        if r < 40 then
            -- 40% idle: nothing changes
        elseif r < 70 then
            -- 30% hover: move hover to random row
            local new_hover = rng_range(1, n_items)
            if new_hover ~= state.hover then
                state.hover = new_hover
                changed = true
            end
        elseif r < 85 then
            -- 15% click: set active
            local new_active = rng_range(1, n_items)
            if new_active ~= state.active then
                state.active = new_active
                changed = true
            end
        else
            -- 15% type: change one label's text
            local idx = rng_range(1, n_items)
            state.labels[idx] = string.format("Item %d — edited frame %d", idx, frame)
            changed = true
        end

        if changed then
            source_changes = source_changes + 1
        end

        -- BUILD: always rebuild the ASDL tree
        -- (this is what an app does: reconstruct declarative description)
        local tb0 = now()
        root = build_ui(state)
        local tb1 = now()
        t_build = t_build + (tb1 - tb0)
        builds = builds + 1

        -- COMPILE: run through lowering pipeline
        local tc0 = now()
        local old_calls = compile.stats().calls
        slot:update(compile(root))
        local tc1 = now()
        t_compile = t_compile + (tc1 - tc0)
        compiles = compiles + 1
        local new_calls = compile.stats().calls
        if compile.stats().node_hits > (old_calls > 0 and compile.stats().node_hits - 1 or -1) then
            -- rough: if the call resulted in a node_hit, it was cached
        end

        -- EXECUTE: run the machine
        local te0 = now()
        reset_gfx()
        slot.callback(gfx)
        local te1 = now()
        t_exec = t_exec + (te1 - te0)
        executes = executes + 1
    end

    local stats = compile.stats()
    slot:close()

    return {
        n_items = n_items,
        n_frames = n_frames,
        source_changes = source_changes,
        builds = builds,

        t_build_us = t_build * 1e6,
        t_compile_us = t_compile * 1e6,
        t_exec_us = t_exec * 1e6,
        t_total_us = (t_build + t_compile + t_exec) * 1e6,

        avg_build_us = t_build / n_frames * 1e6,
        avg_compile_us = t_compile / n_frames * 1e6,
        avg_exec_us = t_exec / n_frames * 1e6,
        avg_total_us = (t_build + t_compile + t_exec) / n_frames * 1e6,

        compile_calls = stats.calls,
        node_hits = stats.node_hits,
        code_misses = stats.code_misses,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- MAIN
-- ═══════════════════════════════════════════════════════════════

local n_items = tonumber(arg[1]) or 100
local n_frames = tonumber(arg[2]) or 3600

print(string.format("session_bench: %d items, %d frames (%.0fs at 60fps)", n_items, n_frames, n_frames/60))
print(string.format("Simulating: 40%% idle, 30%% hover, 15%% click, 15%% type"))
print("")

-- Warmup: run a short session to warm JIT
run_session(n_items, 200, 99999)

-- Real run
local r = run_session(n_items, n_frames, 42)

print("── mgps session results ──")
print("")
print(string.format("  source changes:    %d / %d frames (%.0f%%)",
    r.source_changes, r.n_frames, r.source_changes/r.n_frames*100))
print(string.format("  compile node_hits: %d / %d calls (%.1f%%)",
    r.node_hits, r.compile_calls, r.node_hits/r.compile_calls*100))
print("")
print(string.format("  phase            total (ms)    avg/frame (µs)    %% of total"))
print(string.format("  ─────            ──────────    ──────────────    ──────────"))
print(string.format("  build_ui      %10.2f    %14.2f    %8.1f%%",
    r.t_build_us/1000, r.avg_build_us, r.t_build_us/r.t_total_us*100))
print(string.format("  compile       %10.2f    %14.2f    %8.1f%%",
    r.t_compile_us/1000, r.avg_compile_us, r.t_compile_us/r.t_total_us*100))
print(string.format("  exec          %10.2f    %14.2f    %8.1f%%",
    r.t_exec_us/1000, r.avg_exec_us, r.t_exec_us/r.t_total_us*100))
print(string.format("  ─────────────────────────────────────────────────────────"))
print(string.format("  TOTAL         %10.2f    %14.2f    %8.1f%%",
    r.t_total_us/1000, r.avg_total_us, 100.0))
print("")
print(string.format("  frame budget @ 60fps: 16,667 µs"))
print(string.format("  mgps avg/frame:       %.2f µs  (%.4f%% of budget)", r.avg_total_us, r.avg_total_us/16667*100))
print("")

-- For comparison: what Clay would cost
-- Clay costs the same every frame regardless of changes
-- Use the numbers from clay_bench (flat_list 100 items ≈ 289 µs/frame)
-- Scale linearly for item count (Clay is ~2.85 µs/item for flat_list)
local clay_per_item_us = 2.85  -- from bench/clay_bench flat_list measurements
local clay_per_frame = clay_per_item_us * n_items
local clay_total = clay_per_frame * n_frames

print(string.format("── estimated clay comparison (from clay_bench measurements) ──"))
print("")
print(string.format("  clay per-frame (est): %.0f µs  (constant, every frame)", clay_per_frame))
print(string.format("  clay total (est):     %.2f ms  (%.0f frames × %.0f µs)",
    clay_total/1000, n_frames, clay_per_frame))
print(string.format("  mgps total:           %.2f ms", r.t_total_us/1000))
print("")
if r.t_total_us < clay_total then
    print(string.format("  mgps used %.1f%% of what Clay would use (%.1f× less total CPU)",
        r.t_total_us/clay_total*100, clay_total/r.t_total_us))
else
    print(string.format("  mgps used %.1f%% more than Clay would (%.1f× more total CPU)",
        (r.t_total_us/clay_total - 1)*100, r.t_total_us/clay_total))
end
print("")
print(string.format("  BUT NOTE: this comparison is structurally unfair."))
print(string.format("  Clay is optimized C. mgps is LuaJIT."))
print(string.format("  A fair language-level comparison would need mgps in C/Terra."))
print(string.format("  What this DOES show: the retained architecture's caching"))
print(string.format("  advantage over immediate-mode, even across a language gap."))
