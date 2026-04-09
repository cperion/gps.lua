#!/usr/bin/env luajit
-- test_ugps.lua — comprehensive test for the flat-command gps runtime

package.path = "./?.lua;./?/init.lua;" .. package.path

local M = require("gps")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. name) end
end

-- ═══════════════════════════════════════════════════════════════
-- SCHEMAS
-- ═══════════════════════════════════════════════════════════════

-- User domain: a small UI
local U = M.context():Define [[
    module UI {
        Root = (Node body) unique
        Node = Column(number spacing, Node* children) unique
             | Rect(string tag, number w, number h, number rgba8) unique
             | Text(string tag, number font_id, number rgba8, string text) unique
             | Clip(number w, number h, Node child) unique
             | Transform(number tx, number ty, Node child) unique
             | Group(Node* children) unique
             | Spacer(number w, number h) unique
    }
]]

-- Flat draw commands
local D = M.context():Define [[
    module Draw {
        Cmd = FillRect(number x, number y, number w, number h, number rgba8) unique
            | DrawText(number x, number y, number font_id, number rgba8, string text) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
            | PushTransform(number tx, number ty) unique
            | PopTransform unique
    }
]]

-- Flat hit commands
local H = M.context():Define [[
    module Hit {
        Cmd = Rect(number x, number y, number w, number h, string tag) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
            | PushTransform(number tx, number ty) unique
            | PopTransform unique
    }
]]

-- ═══════════════════════════════════════════════════════════════
-- LAYOUT — :measure() and :place()
-- ═══════════════════════════════════════════════════════════════

local function text_w(fid, text) return #text * 8 end
local function text_h(fid) return 16 end

function U.UI.Rect:measure() return self.w, self.h end
function U.UI.Rect:place(x, y, dc, hc)
    dc[#dc+1] = D.Draw.FillRect(x, y, self.w, self.h, self.rgba8)
    hc[#hc+1] = H.Hit.Rect(x, y, self.w, self.h, self.tag)
end

function U.UI.Text:measure() return text_w(self.font_id, self.text), text_h(self.font_id) end
function U.UI.Text:place(x, y, dc, hc)
    local w, h = self:measure()
    dc[#dc+1] = D.Draw.DrawText(x, y, self.font_id, self.rgba8, self.text)
    hc[#hc+1] = H.Hit.Rect(x, y, w, h, self.tag)
end

function U.UI.Spacer:measure() return self.w, self.h end
function U.UI.Spacer:place() end

function U.UI.Clip:measure() return self.w, self.h end
function U.UI.Clip:place(x, y, dc, hc)
    dc[#dc+1] = D.Draw.PushClip(x, y, self.w, self.h)
    hc[#hc+1] = H.Hit.PushClip(x, y, self.w, self.h)
    self.child:place(x, y, dc, hc)
    dc[#dc+1] = D.Draw.PopClip()
    hc[#hc+1] = H.Hit.PopClip()
end

function U.UI.Transform:measure() return self.child:measure() end
function U.UI.Transform:place(x, y, dc, hc)
    dc[#dc+1] = D.Draw.PushTransform(self.tx, self.ty)
    hc[#hc+1] = H.Hit.PushTransform(self.tx, self.ty)
    self.child:place(x, y, dc, hc)
    dc[#dc+1] = D.Draw.PopTransform()
    hc[#hc+1] = H.Hit.PopTransform()
end

function U.UI.Column:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end
        h = h + ch; if i > 1 then h = h + self.spacing end
    end; return w, h
end
function U.UI.Column:place(x, y, dc, hc)
    local cy = y
    for i = 1, #self.children do
        local c = self.children[i]; local _, ch = c:measure()
        c:place(x, cy, dc, hc)
        cy = cy + ch + self.spacing
    end
end

function U.UI.Group:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end; if ch > h then h = ch end
    end; return w, h
end
function U.UI.Group:place(x, y, dc, hc)
    for i = 1, #self.children do self.children[i]:place(x, y, dc, hc) end
end

-- Root:flatten — one tree walk, two flat outputs
function U.UI.Root:flatten()
    local dc, hc = {}, {}
    self.body:place(0, 0, dc, hc)
    return dc, hc
end

-- ═══════════════════════════════════════════════════════════════
-- BACKENDS
-- ═══════════════════════════════════════════════════════════════

local function next_pow2(n) local p = 1; while p < n do p = p * 2 end; return p end

-- Paint backend: records ops into a log for testing
local paint_ops = {}

local paint = M.backend("paint", {
    FillRect = function(cmd, ctx, _, g)
        g[#g+1] = { op = "rect", x = cmd.x, y = cmd.y, w = cmd.w, h = cmd.h,
                     rgba8 = cmd.rgba8, tx = ctx:depth("transform") }
    end,
    DrawText = {
        run = function(cmd, ctx, resource, g)
            g[#g+1] = { op = "text", x = cmd.x, y = cmd.y, text = cmd.text,
                         res_id = resource and resource.id or nil, tx = ctx:depth("transform") }
        end,
        resource = {
            key = function(cmd) return cmd.font_id * 10000 + next_pow2(#cmd.text) end,
            alloc = function(cmd)
                local id = math.random(100000)
                return { id = id, cap = next_pow2(#cmd.text), font_id = cmd.font_id }
            end,
            release = function(res) res.released = true end,
        },
    },
    PushClip = function(cmd, ctx, _, g)
        ctx:push("clip", { cmd.x, cmd.y, cmd.w, cmd.h })
        g[#g+1] = { op = "push_clip", x = cmd.x, y = cmd.y, w = cmd.w, h = cmd.h }
    end,
    PopClip = function(cmd, ctx, _, g)
        ctx:pop("clip")
        g[#g+1] = { op = "pop_clip" }
    end,
    PushTransform = function(cmd, ctx, _, g)
        ctx:push("transform", { cmd.tx, cmd.ty })
        g[#g+1] = { op = "push_tf", tx = cmd.tx, ty = cmd.ty }
    end,
    PopTransform = function(cmd, ctx, _, g)
        ctx:pop("transform")
        g[#g+1] = { op = "pop_tf" }
    end,
})

-- Hit backend: returns first hit
local function inside(qx, qy, x, y, w, h)
    return qx >= x and qy >= y and qx < x + w and qy < y + h
end

local hit = M.backend("hit", {
    Rect = function(cmd, ctx, _, query)
        local tx, ty = 0, 0
        -- accumulate transforms from stack
        local ts = ctx.stacks and ctx.stacks.transform
        if ts then
            for i = 1, #ts do tx = tx + ts[i][1]; ty = ty + ts[i][2] end
        end
        local ax, ay = cmd.x + tx, cmd.y + ty
        -- check clip
        local cs = ctx.stacks and ctx.stacks.clip
        if cs then
            for i = 1, #cs do
                local c = cs[i]
                if not inside(query.x, query.y, c[1], c[2], c[3], c[4]) then
                    return nil
                end
            end
        end
        if inside(query.x, query.y, ax, ay, cmd.w, cmd.h) then
            return { tag = cmd.tag, x = ax, y = ay, w = cmd.w, h = cmd.h }
        end
    end,
    PushClip = function(cmd, ctx)
        ctx:push("clip", { cmd.x, cmd.y, cmd.w, cmd.h })
    end,
    PopClip = function(cmd, ctx)
        ctx:pop("clip")
    end,
    PushTransform = function(cmd, ctx)
        ctx:push("transform", { cmd.tx, cmd.ty })
    end,
    PopTransform = function(cmd, ctx)
        ctx:pop("transform")
    end,
})

-- ═══════════════════════════════════════════════════════════════
-- TEST 1: Basic flatten + paint
-- ═══════════════════════════════════════════════════════════════

print("== Test 1: Basic flatten + paint ==")

local root = U.UI.Root(
    U.UI.Column(4, {
        U.UI.Rect("bg", 100, 30, 0xff0000ff),
        U.UI.Text("label", 1, 0xffffffff, "hello"),
    })
)

local dc, hc = root:flatten()

check("flatten produces draw cmds", #dc == 2)
check("flatten produces hit cmds", #hc == 2)
check("draw[1] is FillRect", dc[1].kind == "FillRect")
check("draw[2] is DrawText", dc[2].kind == "DrawText")
check("hit[1] is Rect", hc[1].kind == "Rect")
check("hit[2] is Rect", hc[2].kind == "Rect")

-- positions resolved by layout
check("rect at y=0", dc[1].y == 0)
check("text at y=34", dc[2].y == 34)  -- 30 + spacing 4

local ps = M.slot("paint")
ps:update(dc)

local ops = {}
ps:run(ops)

check("paint produced 2 ops", #ops == 2)
check("paint op1 is rect", ops[1].op == "rect")
check("paint op2 is text", ops[2].op == "text")
check("text has resource", ops[2].res_id ~= nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 2: Hit testing
-- ═══════════════════════════════════════════════════════════════

print("== Test 2: Hit testing ==")

local hs = M.slot("hit")
hs:update(hc)

local hit1 = hs:run({ x = 50, y = 15 })
check("hit on rect", hit1 ~= nil and hit1.tag == "bg")

local hit2 = hs:run({ x = 20, y = 40 })  -- x=20 is within text width of 40
check("hit on text", hit2 ~= nil and hit2.tag == "label")

local hit3 = hs:run({ x = 200, y = 200 })
check("miss returns nil", hit3 == nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 3: Interning / identity caching
-- ═══════════════════════════════════════════════════════════════

print("== Test 3: Interning ==")

-- Same tree → same flatten output (ASDL interning)
local root2 = U.UI.Root(
    U.UI.Column(4, {
        U.UI.Rect("bg", 100, 30, 0xff0000ff),
        U.UI.Text("label", 1, 0xffffffff, "hello"),
    })
)
check("same tree is same object", root == root2)

local dc2, hc2 = root2:flatten()
-- individual commands should be same interned objects
check("cmd identity preserved", dc[1] == dc2[1])
check("cmd identity preserved 2", dc[2] == dc2[2])

-- ═══════════════════════════════════════════════════════════════
-- TEST 4: Slot skip on same commands
-- ═══════════════════════════════════════════════════════════════

print("== Test 4: Slot caching ==")

local ps2 = M.slot("paint")
ps2:update(dc)
local s1 = ps2:stats()
check("first update counts", s1.updates == 1 and s1.skipped == 0)

ps2:update(dc)  -- same list
local s2 = ps2:stats()
check("second update skipped", s2.updates == 2 and s2.skipped == 1)

-- ═══════════════════════════════════════════════════════════════
-- TEST 5: Resource lifecycle
-- ═══════════════════════════════════════════════════════════════

print("== Test 5: Resource lifecycle ==")

local ps3 = M.slot("paint")

-- initial: "hello" → cap=8, font=1 → key=10008
local dc_a = { D.Draw.DrawText(0, 0, 1, 0xff, "hello") }
ps3:update(dc_a)
local ops_a = {}; ps3:run(ops_a)
local res_id_a = ops_a[1].res_id
check("resource allocated", res_id_a ~= nil)
local st_a = ps3:stats()
check("1 alloc", st_a.res_allocs == 1)

-- same key: "world" (5 chars, same bucket) → should reuse
local dc_b = { D.Draw.DrawText(10, 10, 1, 0xff, "world") }
ps3:update(dc_b)
local ops_b = {}; ps3:run(ops_b)
local res_id_b = ops_b[1].res_id
check("resource reused (same key)", res_id_b == res_id_a)
local st_b = ps3:stats()
check("1 alloc 1 reuse", st_b.res_allocs == 1 and st_b.res_reuses == 1)

-- different key: "a very long string" (18 chars → cap=32) → new alloc, old released
local dc_c = { D.Draw.DrawText(0, 0, 1, 0xff, "a very long string") }
ps3:update(dc_c)
local ops_c = {}; ps3:run(ops_c)
local res_id_c = ops_c[1].res_id
check("resource changed (new key)", res_id_c ~= res_id_a)
local st_c = ps3:stats()
check("2 allocs 1 reuse 1 release", st_c.res_allocs == 2 and st_c.res_reuses == 1 and st_c.res_releases == 1)

-- close releases remaining
ps3:close()
local st_d = ps3:stats()
check("close releases", st_d.res_releases == 2)

-- ═══════════════════════════════════════════════════════════════
-- TEST 6: Clip + Transform (stack behavior)
-- ═══════════════════════════════════════════════════════════════

print("== Test 6: Clip + Transform (stacks) ==")

local clipped = U.UI.Root(
    U.UI.Clip(200, 100,
        U.UI.Transform(50, 25,
            U.UI.Rect("inner", 80, 40, 0x00ff00ff)
        )
    )
)

local dc_clip, hc_clip = clipped:flatten()
check("clip produces 5 draw cmds", #dc_clip == 5)
check("cmd order: PushClip", dc_clip[1].kind == "PushClip")
check("cmd order: PushTransform", dc_clip[2].kind == "PushTransform")
check("cmd order: FillRect", dc_clip[3].kind == "FillRect")
check("cmd order: PopTransform", dc_clip[4].kind == "PopTransform")
check("cmd order: PopClip", dc_clip[5].kind == "PopClip")

local ps_clip = M.slot("paint")
ps_clip:update(dc_clip)
local ops_clip = {}
ps_clip:run(ops_clip)

check("5 paint ops", #ops_clip == 5)
check("push_clip op", ops_clip[1].op == "push_clip")
check("push_tf op", ops_clip[2].op == "push_tf" and ops_clip[2].tx == 50)
check("rect inside transform", ops_clip[3].op == "rect" and ops_clip[3].tx == 1) -- transform depth = 1
check("pop_tf op", ops_clip[4].op == "pop_tf")
check("pop_clip op", ops_clip[5].op == "pop_clip")

-- hit test: query inside clip + transform
local hs_clip = M.slot("hit")
hs_clip:update(hc_clip)

-- inner rect is at x=0+50=50, y=0+25=25, 80×40
-- clip is at 0,0,200,100
local hit_in = hs_clip:run({ x = 60, y = 35 })
check("hit inside clip+transform", hit_in ~= nil and hit_in.tag == "inner")

-- outside transform bounds but inside clip
local hit_out = hs_clip:run({ x = 5, y = 5 })
check("miss outside rect", hit_out == nil)

-- outside clip entirely
local hit_outside = hs_clip:run({ x = 300, y = 300 })
check("miss outside clip", hit_outside == nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 7: Incremental update — partial resource reuse
-- ═══════════════════════════════════════════════════════════════

print("== Test 7: Incremental update ==")

local ps_inc = M.slot("paint")

-- 3 text items
local dc_inc1 = {
    D.Draw.DrawText(0,  0, 1, 0xff, "aaa"),   -- cap=4, key=10004
    D.Draw.DrawText(0, 20, 1, 0xff, "bbb"),   -- cap=4, key=10004
    D.Draw.DrawText(0, 40, 2, 0xff, "ccc"),   -- cap=4, key=20004
}
ps_inc:update(dc_inc1)
local ops_i1 = {}; ps_inc:run(ops_i1)
local id_1 = ops_i1[1].res_id
local id_2 = ops_i1[2].res_id
local id_3 = ops_i1[3].res_id
check("3 distinct resources", id_1 ~= nil and id_2 ~= nil and id_3 ~= nil)
check("same-key resources differ", id_1 ~= id_2) -- same key but different slots

local si1 = ps_inc:stats()
check("3 allocs initially", si1.res_allocs == 3)

-- change only the second text's content (same cap → same key → reuse)
local dc_inc2 = {
    D.Draw.DrawText(0,  0, 1, 0xff, "aaa"),   -- same
    D.Draw.DrawText(0, 20, 1, 0xff, "BBB"),   -- same key, different content
    D.Draw.DrawText(0, 40, 2, 0xff, "ccc"),   -- same
}
ps_inc:update(dc_inc2)
local ops_i2 = {}; ps_inc:run(ops_i2)

local si2 = ps_inc:stats()
check("3 reuses on payload-only change", si2.res_reuses == 3)
check("still only 3 allocs total", si2.res_allocs == 3)

-- ═══════════════════════════════════════════════════════════════
-- TEST 8: Multiple backends from one tree
-- ═══════════════════════════════════════════════════════════════

print("== Test 8: Multiple backends ==")

local multi_root = U.UI.Root(
    U.UI.Column(0, {
        U.UI.Rect("a", 100, 50, 0xff0000ff),
        U.UI.Rect("b", 100, 50, 0x00ff00ff),
    })
)

local mdc, mhc = multi_root:flatten()

-- one tree walk produced both
check("draw cmds from multi", #mdc == 2)
check("hit cmds from multi", #mhc == 2)

local mp = M.slot("paint"); mp:update(mdc)
local mh = M.slot("hit");  mh:update(mhc)

local mops = {}; mp:run(mops)
check("paint runs independently", #mops == 2)

local mhit = mh:run({ x = 50, y = 25 })
check("hit first rect", mhit ~= nil and mhit.tag == "a")

local mhit2 = mh:run({ x = 50, y = 75 })
check("hit second rect", mhit2 ~= nil and mhit2.tag == "b")

-- ═══════════════════════════════════════════════════════════════
-- TEST 9: Report
-- ═══════════════════════════════════════════════════════════════

print("== Test 9: Report ==")

local report = M.report({ mp, mh })
check("report is a string", type(report) == "string")
check("report mentions slots", report:find("slot%[1%]") ~= nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 10: M.with structural update
-- ═══════════════════════════════════════════════════════════════

print("== Test 10: M.with ==")

local r1 = U.UI.Rect("x", 100, 50, 0xff0000ff)
local r2 = M.with(r1, { rgba8 = 0x00ff00ff })
check("with changes field", r2.rgba8 == 0x00ff00ff)
check("with preserves others", r2.tag == "x" and r2.w == 100 and r2.h == 50)
check("with produces new identity", r1 ~= r2)

local r3 = M.with(r1, { rgba8 = 0xff0000ff }) -- same values
check("with same values = same identity", r1 == r3)

-- ═══════════════════════════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════════════════════════

print("")
print(string.format("Results: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
