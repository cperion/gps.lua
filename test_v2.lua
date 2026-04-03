#!/usr/bin/env luajit
-- test_v2.lua — flat-command gps runtime test

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

local U = M.context():Define [[
    module UI {
        Root = (Node body) unique
        Node = Column(number spacing, Node* children) unique
             | Row(number spacing, Node* children) unique
             | Rect(string tag, number w, number h, number rgba8) unique
             | Text(string tag, number font_id, number rgba8, string text) unique
             | Clip(number w, number h, Node child) unique
             | Transform(number tx, number ty, Node child) unique
             | Group(Node* children) unique
    }
]]

local D = M.context():Define [[
    module D {
        Cmd = FillRect(number x, number y, number w, number h, number rgba8) unique
            | DrawText(number x, number y, number font_id, number rgba8, string text) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
            | PushTransform(number tx, number ty) unique
            | PopTransform unique
    }
]]

local H = M.context():Define [[
    module H {
        Cmd = HitRect(number x, number y, number w, number h, string tag) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
            | PushTransform(number tx, number ty) unique
            | PopTransform unique
    }
]]

-- ═══════════════════════════════════════════════════════════════
-- LAYOUT
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
    dc[#dc+1] = D.D.PopClip()
    hc[#hc+1] = H.H.PopClip()
end

function U.UI.Transform:measure() return self.child:measure() end
function U.UI.Transform:place(x, y, dc, hc)
    dc[#dc+1] = D.D.PushTransform(self.tx, self.ty)
    hc[#hc+1] = H.H.PushTransform(self.tx, self.ty)
    self.child:place(x, y, dc, hc)
    dc[#dc+1] = D.D.PopTransform()
    hc[#hc+1] = H.H.PopTransform()
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

function U.UI.Row:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        w = w + cw; if i > 1 then w = w + self.spacing end; if ch > h then h = ch end
    end; return w, h
end
function U.UI.Row:place(x, y, dc, hc)
    local cx = x
    for i = 1, #self.children do
        local c = self.children[i]; local cw = c:measure()
        c:place(cx, y, dc, hc); cx = cx + cw + self.spacing
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

function U.UI.Root:flatten()
    local dc, hc = {}, {}
    self.body:place(0, 0, dc, hc)
    return dc, hc
end

-- ═══════════════════════════════════════════════════════════════
-- BACKENDS
-- ═══════════════════════════════════════════════════════════════

local function next_pow2(n) local p = 1; while p < n do p = p * 2 end; return p end

M.backend("paint", {
    FillRect = function(cmd, ctx, _, g)
        g[#g+1] = { op = "rect", x = cmd.x, y = cmd.y, w = cmd.w, h = cmd.h }
    end,
    DrawText = {
        run = function(cmd, ctx, res, g)
            g[#g+1] = { op = "text", x = cmd.x, y = cmd.y, text = cmd.text, res_id = res and res.id }
        end,
        resource = {
            key = function(cmd) return cmd.font_id * 10000 + next_pow2(#cmd.text) end,
            alloc = function(cmd) return { id = math.random(99999) } end,
            release = function(res) res.released = true end,
        },
    },
    PushClip = function(cmd, ctx, _, g)
        ctx:push("clip", { cmd.x, cmd.y, cmd.w, cmd.h })
        g[#g+1] = { op = "push_clip" }
    end,
    PopClip = function(cmd, ctx, _, g)
        ctx:pop("clip"); g[#g+1] = { op = "pop_clip" }
    end,
    PushTransform = function(cmd, ctx, _, g)
        ctx:push("transform", { cmd.tx, cmd.ty })
        g[#g+1] = { op = "push_tf", tx = cmd.tx, ty = cmd.ty }
    end,
    PopTransform = function(cmd, ctx, _, g)
        ctx:pop("transform"); g[#g+1] = { op = "pop_tf" }
    end,
})

local function inside(qx, qy, x, y, w, h)
    return qx >= x and qy >= y and qx < x + w and qy < y + h
end

M.backend("hit", {
    HitRect = function(cmd, ctx, _, query)
        local tx, ty = 0, 0
        local ts = ctx.stacks.transform
        if ts then for i = 1, #ts do tx = tx + ts[i][1]; ty = ty + ts[i][2] end end
        local ax, ay = cmd.x + tx, cmd.y + ty
        local cs = ctx.stacks.clip
        if cs then
            for i = 1, #cs do
                if not inside(query.x, query.y, cs[i][1], cs[i][2], cs[i][3], cs[i][4]) then return nil end
            end
        end
        if inside(query.x, query.y, ax, ay, cmd.w, cmd.h) then return { tag = cmd.tag } end
    end,
    PushClip = function(cmd, ctx) ctx:push("clip", { cmd.x, cmd.y, cmd.w, cmd.h }) end,
    PopClip  = function(cmd, ctx) ctx:pop("clip") end,
    PushTransform = function(cmd, ctx) ctx:push("transform", { cmd.tx, cmd.ty }) end,
    PopTransform  = function(cmd, ctx) ctx:pop("transform") end,
})

-- ═══════════════════════════════════════════════════════════════
-- TEST 1: Basic flatten + paint + hit
-- ═══════════════════════════════════════════════════════════════

print("== Test 1: Basic ==")

local root = U.UI.Root(U.UI.Column(4, {
    U.UI.Rect("bg", 100, 30, 0xff0000ff),
    U.UI.Text("label", 1, 0xffffffff, "hello"),
}))

local dc, hc = root:flatten()
check("2 draw cmds", #dc == 2)
check("2 hit cmds", #hc == 2)
check("draw[1] FillRect", dc[1].kind == "FillRect")
check("draw[2] DrawText", dc[2].kind == "DrawText")
check("rect y=0", dc[1].y == 0)
check("text y=34", dc[2].y == 34)

local ps = M.slot("paint")
ps:update(dc)
local ops = {}; ps:run(ops)
check("paint 2 ops", #ops == 2)
check("text has resource", ops[2].res_id ~= nil)

local hs = M.slot("hit")
hs:update(hc)
check("hit rect", hs:run({ x = 50, y = 15 }) ~= nil)
check("hit text", hs:run({ x = 20, y = 40 }) ~= nil)
check("miss", hs:run({ x = 500, y = 500 }) == nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 2: M.lower() caching
-- ═══════════════════════════════════════════════════════════════

print("== Test 2: M.lower() ==")

local compile_draw = M.lower("draw", function(r) return (r:flatten()) end)
local compile_hit  = M.lower("hit",  function(r) local _,h = r:flatten(); return h end)

local dc1 = compile_draw(root)
local dc2 = compile_draw(root)
check("L1 hit", dc1 == dc2)
check("stats", compile_draw.stats().node_hits == 1)

-- different tree
local root2 = U.UI.Root(U.UI.Column(4, {
    U.UI.Rect("bg", 100, 30, 0xff0000ff),
    U.UI.Text("label", 1, 0xffffffff, "world"),
}))
local dc3 = compile_draw(root2)
check("miss on changed tree", dc3 ~= dc1)
check("stats after miss", compile_draw.stats().calls == 3 and compile_draw.stats().node_hits == 1)

-- same tree as root2 (interning)
local root3 = U.UI.Root(U.UI.Column(4, {
    U.UI.Rect("bg", 100, 30, 0xff0000ff),
    U.UI.Text("label", 1, 0xffffffff, "world"),
}))
check("interning", root3 == root2)
local dc4 = compile_draw(root3)
check("L1 hit via interning", dc4 == dc3)

-- ═══════════════════════════════════════════════════════════════
-- TEST 3: Clip + Transform stacks
-- ═══════════════════════════════════════════════════════════════

print("== Test 3: Stacks ==")

local clipped = U.UI.Root(
    U.UI.Clip(200, 100,
        U.UI.Transform(50, 25,
            U.UI.Rect("inner", 80, 40, 0x00ff00ff))))

local dcc, hcc = clipped:flatten()
check("5 draw cmds", #dcc == 5)
check("PushClip", dcc[1].kind == "PushClip")
check("PushTransform", dcc[2].kind == "PushTransform")
check("FillRect", dcc[3].kind == "FillRect")
check("PopTransform", dcc[4].kind == "PopTransform")
check("PopClip", dcc[5].kind == "PopClip")

local psc = M.slot("paint")
psc:update(dcc)
local opsc = {}; psc:run(opsc)
check("push_clip op", opsc[1].op == "push_clip")
check("push_tf op", opsc[2].op == "push_tf" and opsc[2].tx == 50)
check("rect op", opsc[3].op == "rect")
check("pop_tf op", opsc[4].op == "pop_tf")
check("pop_clip op", opsc[5].op == "pop_clip")

-- hit with transform
local hsc = M.slot("hit")
hsc:update(hcc)
local hit_in = hsc:run({ x = 60, y = 35 })
check("hit inside clip+transform", hit_in ~= nil and hit_in.tag == "inner")
local hit_out = hsc:run({ x = 5, y = 5 })
check("miss outside rect", hit_out == nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 4: Resource lifecycle
-- ═══════════════════════════════════════════════════════════════

print("== Test 4: Resources ==")

local ps4 = M.slot("paint")

local da = { D.D.DrawText(0, 0, 1, 0xff, "hello") }
ps4:update(da)
local oa = {}; ps4:run(oa)
local id_a = oa[1].res_id
check("alloc", id_a ~= nil and ps4.stats().res_allocs == 1)

-- same key (5 chars → cap=8, font=1) → reuse
local db = { D.D.DrawText(10, 10, 1, 0xff, "world") }
ps4:update(db)
local ob = {}; ps4:run(ob)
check("reuse same key", ob[1].res_id == id_a)
check("1 reuse", ps4.stats().res_reuses == 1)

-- different key (long text → bigger cap) → new alloc
local dc_long = { D.D.DrawText(0, 0, 1, 0xff, "a much longer string here!!") }
ps4:update(dc_long)
local oc = {}; ps4:run(oc)
check("new alloc", oc[1].res_id ~= id_a)
check("old released", ps4.stats().res_releases == 1)

ps4:close()
check("close releases", ps4.stats().res_releases == 2)

-- ═══════════════════════════════════════════════════════════════
-- TEST 5: Slot skip on same cmds
-- ═══════════════════════════════════════════════════════════════

print("== Test 5: Slot skip ==")

local ps5 = M.slot("paint")
ps5:update(da)
check("first update", ps5.stats().updates == 1 and ps5.stats().skipped == 0)
ps5:update(da)
check("skip on same", ps5.stats().updates == 2 and ps5.stats().skipped == 1)

-- ═══════════════════════════════════════════════════════════════
-- TEST 6: Multiple backends one tree
-- ═══════════════════════════════════════════════════════════════

print("== Test 6: Multiple backends ==")

local multi = U.UI.Root(U.UI.Row(0, {
    U.UI.Rect("a", 50, 50, 0xff0000ff),
    U.UI.Rect("b", 50, 50, 0x00ff00ff),
}))
local mdc, mhc = multi:flatten()
check("2 draw", #mdc == 2)
check("2 hit", #mhc == 2)

local mp = M.slot("paint"); mp:update(mdc)
local mh = M.slot("hit"); mh:update(mhc)

local mops = {}; mp:run(mops)
check("paint works", #mops == 2)
check("hit a", mh:run({ x = 25, y = 25 }) ~= nil)
check("hit b", mh:run({ x = 75, y = 25 }) ~= nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 7: M.with
-- ═══════════════════════════════════════════════════════════════

print("== Test 7: M.with ==")

local r1 = U.UI.Rect("x", 100, 50, 0xff0000ff)
local r2 = M.with(r1, { rgba8 = 0x00ff00ff })
check("changes field", r2.rgba8 == 0x00ff00ff)
check("preserves others", r2.tag == "x" and r2.w == 100)
check("new identity", r1 ~= r2)
check("same values = same", M.with(r1, { rgba8 = 0xff0000ff }) == r1)

-- ═══════════════════════════════════════════════════════════════
-- TEST 8: Report
-- ═══════════════════════════════════════════════════════════════

print("== Test 8: Report ==")

local report = M.report({ compile_draw, compile_hit, mp, mh })
check("report string", type(report) == "string" and #report > 0)
check("report has lower", report:find("draw") ~= nil)

-- ═══════════════════════════════════════════════════════════════
-- TEST 9: Verify old API is gone
-- ═══════════════════════════════════════════════════════════════

print("== Test 9: Old API removed ==")

check("no M.emit", M.emit == nil)
check("no M.compose", M.compose == nil)
check("no M.match", M.match == nil)
check("no M.leaf", M.leaf == nil)
check("no M.variant", M.variant == nil)
check("no M.state", M.state == nil)
check("no M.flat_slot", M.flat_slot == nil)
check("no M.is_compiled", M.is_compiled == nil)
check("no M.app", M.app == nil)

-- ═══════════════════════════════════════════════════════════════
-- DONE
-- ═══════════════════════════════════════════════════════════════

print("")
print(string.format("Results: %d passed, %d failed", pass, fail))
print(string.format("gps init.lua: flat-command runtime, %d public functions",
    6))
if fail > 0 then os.exit(1) end
