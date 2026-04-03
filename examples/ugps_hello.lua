#!/usr/bin/env luajit
-- ugps_hello.lua — complete flat-command gps app in one file
--
-- This is the whole thing. No lovepaint.lua, no hittest.lua, no View layer.
-- Tree in. Flat out. One loop. One stack.

package.path = "./?.lua;./?/init.lua;" .. package.path
local M = require("gps")

-- ══════════════════════════════════════════════════════════════
-- 1. DEFINE YOUR TYPES
-- ══════════════════════════════════════════════════════════════

local U = M.context():Define [[
    module UI {
        Root = (Node body) unique
        Node = Column(number spacing, Node* children) unique
             | Row(number spacing, Node* children) unique
             | Rect(string tag, number w, number h, number rgba8) unique
             | Text(string tag, number font_id, number rgba8, string text) unique
             | Clip(number w, number h, Node child) unique
    }
]]

-- ══════════════════════════════════════════════════════════════
-- 2. DEFINE YOUR FLAT COMMANDS
-- ══════════════════════════════════════════════════════════════

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

-- ══════════════════════════════════════════════════════════════
-- 3. WRITE :place() — THE ONE RECURSIVE PASS
--    Each leaf appends to BOTH flat lists at once
-- ══════════════════════════════════════════════════════════════

local function tw(fid, text) return #text * 9 end
local function th(fid) return 18 end

function U.UI.Rect:measure() return self.w, self.h end
function U.UI.Rect:place(x, y, dc, hc)
    dc[#dc+1] = D.D.FillRect(x, y, self.w, self.h, self.rgba8)
    hc[#hc+1] = H.H.HitRect(x, y, self.w, self.h, self.tag)
end

function U.UI.Text:measure() return tw(self.font_id, self.text), th(self.font_id) end
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
        c:place(x, cy, dc, hc); cy = cy + ch + self.spacing
    end
end

function U.UI.Row:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        w = w + cw; if i > 1 then w = w + self.spacing end
        if ch > h then h = ch end
    end; return w, h
end
function U.UI.Row:place(x, y, dc, hc)
    local cx = x
    for i = 1, #self.children do
        local c = self.children[i]; local cw = c:measure()
        c:place(cx, y, dc, hc); cx = cx + cw + self.spacing
    end
end

function U.UI.Root:flatten()
    local dc, hc = {}, {}
    self.body:place(0, 0, dc, hc)
    return dc, hc
end

-- ══════════════════════════════════════════════════════════════
-- 4. REGISTER BACKENDS — what each command does at runtime
-- ══════════════════════════════════════════════════════════════

local function next_pow2(n) local p=1; while p<n do p=p*2 end; return p end

M.backend("paint", {
    FillRect = function(cmd, ctx, _, g)
        g.ops[#g.ops+1] = string.format("rect(%d,%d,%d,%d)", cmd.x, cmd.y, cmd.w, cmd.h)
    end,
    DrawText = {
        run = function(cmd, ctx, res, g)
            g.ops[#g.ops+1] = string.format("text(%d,%d,%q,res=%s)", cmd.x, cmd.y, cmd.text, res.id)
        end,
        resource = {
            key = function(cmd) return cmd.font_id * 10000 + next_pow2(#cmd.text) end,
            alloc = function(cmd) return { id = tostring(math.random(9999)) } end,
        },
    },
    PushClip = function(cmd, ctx, _, g)
        ctx:push("clip", {cmd.x, cmd.y, cmd.w, cmd.h})
        g.ops[#g.ops+1] = "push_clip"
    end,
    PopClip = function(cmd, ctx, _, g)
        ctx:pop("clip")
        g.ops[#g.ops+1] = "pop_clip"
    end,
})

local function inside(qx, qy, x, y, w, h)
    return qx >= x and qy >= y and qx < x + w and qy < y + h
end

M.backend("hit", {
    HitRect = function(cmd, ctx, _, query)
        -- check clip stack
        local cs = ctx.stacks.clip
        if cs then
            for i = 1, #cs do
                if not inside(query.x, query.y, cs[i][1], cs[i][2], cs[i][3], cs[i][4]) then
                    return nil
                end
            end
        end
        if inside(query.x, query.y, cmd.x, cmd.y, cmd.w, cmd.h) then
            return { tag = cmd.tag }
        end
    end,
    PushClip = function(cmd, ctx) ctx:push("clip", {cmd.x, cmd.y, cmd.w, cmd.h}) end,
    PopClip  = function(cmd, ctx) ctx:pop("clip") end,
})

-- ══════════════════════════════════════════════════════════════
-- 5. BUILD UI, FLATTEN, RUN
-- ══════════════════════════════════════════════════════════════

-- Build the tree (what the user authors)
local root = U.UI.Root(
    U.UI.Column(8, {
        U.UI.Text("title", 1, 0xffffffff, "Hello ugps!"),
        U.UI.Row(4, {
            U.UI.Rect("btn_a", 80, 30, 0xff3366ff),
            U.UI.Rect("btn_b", 80, 30, 0x33ff66ff),
            U.UI.Rect("btn_c", 80, 30, 0x6633ffff),
        }),
        U.UI.Clip(200, 40,
            U.UI.Text("clipped", 1, 0xffff00ff, "This text is clipped to 200px wide")
        ),
    })
)

-- Flatten: one tree walk → two flat command lists
local draw_cmds, hit_cmds = root:flatten()

print(string.format("Tree flattened: %d draw commands, %d hit commands", #draw_cmds, #hit_cmds))
print()

-- Show the flat draw commands
print("Draw commands:")
for i, cmd in ipairs(draw_cmds) do
    local fields = {}
    for _, f in ipairs(getmetatable(cmd).__fields or {}) do
        local v = cmd[f.name]
        if type(v) == "string" then fields[#fields+1] = f.name.."="..string.format("%q", v)
        elseif v ~= nil then fields[#fields+1] = f.name.."="..tostring(v) end
    end
    print(string.format("  [%d] %s(%s)", i, cmd.kind, table.concat(fields, ", ")))
end
print()

-- Install in slots and run
local paint_slot = M.slot("paint")
local hit_slot   = M.slot("hit")

paint_slot:update(draw_cmds)
hit_slot:update(hit_cmds)

-- Run paint
local g = { ops = {} }
paint_slot:run(g)
print("Paint output:")
for _, op in ipairs(g.ops) do print("  " .. op) end
print()

-- Run hit tests
local queries = {
    { x = 10, y = 5,  expect = "title" },
    { x = 10, y = 30, expect = "btn_a" },
    { x = 95, y = 30, expect = "btn_b" },
    { x = 10, y = 70, expect = "clipped" },  -- clip starts at y=64
    { x = 500, y = 500, expect = nil },
}

print("Hit tests:")
for _, q in ipairs(queries) do
    local hit = hit_slot:run(q)
    local tag = hit and hit.tag or "nil"
    local ok = tag == (q.expect or "nil")
    print(string.format("  (%d,%d) → %s %s", q.x, q.y, tag, ok and "✓" or "✗ expected "..tostring(q.expect)))
end
print()

-- Show resource management
print("Stats:")
print(M.report({ paint_slot, hit_slot }))
print()

-- Incremental update: change one text, resources reused
print("--- After changing title text ---")
local root2 = M.with(root, {
    body = U.UI.Column(8, {
        U.UI.Text("title", 1, 0xffffffff, "Hello ugps! (updated)"),
        U.UI.Row(4, {
            U.UI.Rect("btn_a", 80, 30, 0xff3366ff),
            U.UI.Rect("btn_b", 80, 30, 0x33ff66ff),
            U.UI.Rect("btn_c", 80, 30, 0x6633ffff),
        }),
        U.UI.Clip(200, 40,
            U.UI.Text("clipped", 1, 0xffff00ff, "This text is clipped to 200px wide")
        ),
    })
})

local dc2, hc2 = root2:flatten()
paint_slot:update(dc2)

local g2 = { ops = {} }
paint_slot:run(g2)

print(string.format("Commands: %d (was %d)", #dc2, #draw_cmds))
print("Stats after update:")
print(M.report({ paint_slot }))
