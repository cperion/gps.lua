#!/usr/bin/env luajit
-- test_flat_slot.lua — test the new M.backend + M.flat_slot in mgps

package.path = "./?.lua;./?/init.lua;" .. package.path
local M = require("gps")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. name) end
end

-- ═══════════════════════════════════════════════════════════════
-- Define user ASDL + flat command ASDL
-- ═══════════════════════════════════════════════════════════════

local U = M.context():Define [[
    module UI {
        Root = (Node body) unique
        Node = Column(number spacing, Node* children) unique
             | Rect(string tag, number w, number h, number rgba8) unique
             | Text(string tag, number font_id, number rgba8, string text) unique
             | Clip(number w, number h, Node child) unique
    }
]]

local D = M.context():Define [[
    module D {
        Cmd = FillRect(number x, number y, number w, number h, number rgba8) unique
            | DrawText(number x, number y, number font_id, number rgba8, string text) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
    }
]]

local H = M.context():Define [[
    module H {
        Cmd = HitRect(number x, number y, number w, number h, string tag) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
    }
]]

-- ═══════════════════════════════════════════════════════════════
-- Layout: :place() appends flat commands (the one recursive pass)
-- ═══════════════════════════════════════════════════════════════

function U.UI.Rect:measure() return self.w, self.h end
function U.UI.Rect:place(x, y, dc, hc)
    dc[#dc+1] = D.D.FillRect(x, y, self.w, self.h, self.rgba8)
    hc[#hc+1] = H.H.HitRect(x, y, self.w, self.h, self.tag)
end

function U.UI.Text:measure() return #self.text * 8, 16 end
function U.UI.Text:place(x, y, dc, hc)
    local w, h = self:measure()
    dc[#dc+1] = D.D.DrawText(x, y, self.font_id, self.rgba8, self.text)
    hc[#hc+1] = H.H.HitRect(x, y, w, h, self.tag)
end

function U.UI.Clip:measure() return self.w, self.h end
function U.UI.Clip:place(x, y, dc, hc)
    dc[#dc+1] = D.D.PushClip(x, y, self.w, self.h)
    hc[#hc+1] = H.H.PushClip(x, y, self.w, self.h)
    self.child:place(x, y, dc, hc)
    dc[#dc+1] = D.D.PopClip
    hc[#hc+1] = H.H.PopClip
end

function U.UI.Column:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end; h = h + ch; if i > 1 then h = h + self.spacing end
    end; return w, h
end
function U.UI.Column:place(x, y, dc, hc)
    local cy = y
    for i = 1, #self.children do
        local c = self.children[i]; local _, ch = c:measure()
        c:place(x, cy, dc, hc); cy = cy + ch + self.spacing
    end
end

function U.UI.Root:flatten()
    local dc, hc = {}, {}
    self.body:place(0, 0, dc, hc)
    return dc, hc
end

-- ═══════════════════════════════════════════════════════════════
-- Register backends
-- ═══════════════════════════════════════════════════════════════

local function next_pow2(n) local p=1; while p<n do p=p*2 end; return p end

M.backend("paint", {
    FillRect = function(cmd, ctx, _, g)
        g[#g+1] = { op="rect", x=cmd.x, y=cmd.y, w=cmd.w, h=cmd.h }
    end,
    DrawText = {
        run = function(cmd, ctx, res, g)
            g[#g+1] = { op="text", x=cmd.x, y=cmd.y, text=cmd.text, res_id=res and res.id }
        end,
        resource = {
            key = function(cmd) return cmd.font_id * 10000 + next_pow2(#cmd.text) end,
            alloc = function(cmd) return { id = math.random(99999) } end,
            release = function(res) res.released = true end,
        },
    },
    PushClip = function(cmd, ctx, _, g)
        ctx:push("clip", { cmd.x, cmd.y, cmd.w, cmd.h })
        g[#g+1] = { op="push_clip" }
    end,
    PopClip = function(cmd, ctx, _, g)
        ctx:pop("clip")
        g[#g+1] = { op="pop_clip" }
    end,
})

local function inside(qx, qy, x, y, w, h)
    return qx >= x and qy >= y and qx < x + w and qy < y + h
end

M.backend("hit", {
    HitRect = function(cmd, ctx, _, query)
        local cs = ctx.stacks.clip
        if cs then
            for i = 1, #cs do
                local c = cs[i]
                if not inside(query.x, query.y, c[1], c[2], c[3], c[4]) then return nil end
            end
        end
        if inside(query.x, query.y, cmd.x, cmd.y, cmd.w, cmd.h) then
            return { tag = cmd.tag }
        end
    end,
    PushClip = function(cmd, ctx) ctx:push("clip", { cmd.x, cmd.y, cmd.w, cmd.h }) end,
    PopClip  = function(cmd, ctx) ctx:pop("clip") end,
})

-- ═══════════════════════════════════════════════════════════════
-- TEST 1: Flat path with M.lower() caching
-- ═══════════════════════════════════════════════════════════════

print("== Test 1: M.lower() + flat_slot ==")

local compile_draw = M.lower("draw", function(root)
    local dc, _ = root:flatten()
    return dc
end)
local compile_hit = M.lower("hit", function(root)
    local _, hc = root:flatten()
    return hc
end)

local root = U.UI.Root(
    U.UI.Column(4, {
        U.UI.Rect("bg", 100, 30, 0xff0000ff),
        U.UI.Text("label", 1, 0xffffffff, "hello"),
    })
)

-- First compile
local dc = compile_draw(root)
local hc = compile_hit(root)
check("draw cmds produced", type(dc) == "table" and #dc == 2)
check("hit cmds produced", type(hc) == "table" and #hc == 2)

-- Second compile: same root → L1 cache hit
local dc2 = compile_draw(root)
check("L1 cache hit", dc2 == dc)  -- exact same table
local ds = compile_draw.stats()
check("node_hits = 1", ds.node_hits == 1)

-- flat_slot paint
local ps = M.flat_slot("paint")
ps:update(dc)
local ops = {}
ps:run(ops)
check("paint produced ops", #ops == 2)
check("text has resource", ops[2].res_id ~= nil)

-- flat_slot hit
local hs = M.flat_slot("hit")
hs:update(hc)
local hit1 = hs:run({ x = 50, y = 15 })
check("hit on rect", hit1 ~= nil and hit1.tag == "bg")
local hit2 = hs:run({ x = 20, y = 40 })
check("hit on text", hit2 ~= nil and hit2.tag == "label")
local hit3 = hs:run({ x = 500, y = 500 })
check("miss", hit3 == nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 2: Incremental update — M.lower() caches subtree
-- ═══════════════════════════════════════════════════════════════

print("== Test 2: Incremental caching ==")

-- Same tree → same compile result (L1)
local root_same = U.UI.Root(
    U.UI.Column(4, {
        U.UI.Rect("bg", 100, 30, 0xff0000ff),
        U.UI.Text("label", 1, 0xffffffff, "hello"),
    })
)
check("interning works", root_same == root)

local dc3 = compile_draw(root_same)
check("L1 hit on same tree", dc3 == dc)

-- Different tree → recompile, but slot reuses resources
local root_changed = U.UI.Root(
    U.UI.Column(4, {
        U.UI.Rect("bg", 100, 30, 0xff0000ff),
        U.UI.Text("label", 1, 0xffffffff, "world"),  -- changed text
    })
)
check("changed tree is different", root_changed ~= root)

local dc4 = compile_draw(root_changed)
check("recompile produces new cmds", dc4 ~= dc)
check("still 2 cmds", #dc4 == 2)

ps:update(dc4)
local ops2 = {}
ps:run(ops2)
check("text resource reused (same key)", ops2[2].res_id == ops[2].res_id)

-- ═══════════════════════════════════════════════════════════════
-- TEST 3: Clip/Push/Pop stacks
-- ═══════════════════════════════════════════════════════════════

print("== Test 3: Clip stacks ==")

local clipped = U.UI.Root(
    U.UI.Clip(200, 100,
        U.UI.Rect("inner", 80, 40, 0x00ff00ff)
    )
)
local dcc, hcc = clipped:flatten()
-- PushClip, FillRect, PopClip = 3 draw cmds
check("clip produces 3 draw cmds", #dcc == 3)

local psc = M.flat_slot("paint")
psc:update(dcc)
local opsc = {}
psc:run(opsc)
check("push_clip op", opsc[1].op == "push_clip")
check("rect op", opsc[2].op == "rect")
check("pop_clip op", opsc[3].op == "pop_clip")

-- ═══════════════════════════════════════════════════════════════
-- TEST 4: Old path still works (backward compat)
-- ═══════════════════════════════════════════════════════════════

print("== Test 4: Old M.emit + M.slot still works ==")

local function old_gen(param, state, g)
    g[#g+1] = { op = "old_rect", x = param.x }
    return g
end

local T = M.context("paint"):Define [[
    module V { Node = Rect(number x) unique }
]]
function T.V.Rect:paint()
    return M.emit(old_gen, M.state.none(), { x = self.x })
end

local old_slot = M.slot()
local node = T.V.Rect(42)
old_slot:update(node:paint())
local old_ops = {}
old_slot.callback(old_ops)
check("old path works", #old_ops == 1 and old_ops[1].x == 42)

-- ═══════════════════════════════════════════════════════════════
-- TEST 5: Resource lifecycle
-- ═══════════════════════════════════════════════════════════════

print("== Test 5: Resource lifecycle ==")

local ps5 = M.flat_slot("paint")
local dc_a = { D.D.DrawText(0, 0, 1, 0xff, "short") }
ps5:update(dc_a)
local ops_a = {}; ps5:run(ops_a)
local st = ps5.stats()
check("1 alloc", st.res_allocs == 1)

-- same key → reuse
local dc_b = { D.D.DrawText(10, 10, 1, 0xff, "abcde") }  -- 5 chars, same bucket
ps5:update(dc_b)
check("1 reuse", ps5.stats().res_reuses == 1)

-- different key → new alloc, old released
local dc_c = { D.D.DrawText(0, 0, 1, 0xff, "a very long string here!") }  -- 24 chars, bigger bucket
ps5:update(dc_c)
check("2 allocs", ps5.stats().res_allocs == 2)
check("1 release", ps5.stats().res_releases == 1)

ps5:close()
check("close releases", ps5.stats().res_releases == 2)

-- ═══════════════════════════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════════════════════════

print("")
print(string.format("Results: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
