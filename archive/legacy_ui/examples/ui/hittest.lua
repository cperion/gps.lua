-- examples/ui/hittest.lua
--
-- Hit-testing terminal on top of a flat-command runtime API.
-- Runtime contract:
--   slot:run({ x = ..., y = ... }) -> hit or nil

return function(RT)
    local T = RT.context("probe")
        :Define [[
            module Hit {
                Root = (Node* nodes) unique

                Node = Group(Node* children) unique
                     | Clip(number x, number y, number w, number h, Node* children) unique
                     | Transform(number tx, number ty, Node* children) unique
                     | Rect(number x, number y, number w, number h, string tag) unique
                     | Text(number x, number y, number w, number h, string tag) unique
            }
        ]]

    local function inside(px, py, x, y, w, h)
        return px >= x and py >= y and px < x + w and py < y + h
    end

    local function emit(out, cmd)
        out[#out + 1] = cmd
        return out
    end

    local function flatten_node(node, out)
        local kind = node.kind

        if kind == "Group" then
            for i = #node.children, 1, -1 do
                flatten_node(node.children[i], out)
            end

        elseif kind == "Clip" then
            emit(out, {
                kind = "PushClip",
                x = node.x,
                y = node.y,
                w = node.w,
                h = node.h,
            })
            for i = #node.children, 1, -1 do
                flatten_node(node.children[i], out)
            end
            emit(out, { kind = "PopClip" })

        elseif kind == "Transform" then
            emit(out, {
                kind = "PushTransform",
                tx = node.tx,
                ty = node.ty,
            })
            for i = #node.children, 1, -1 do
                flatten_node(node.children[i], out)
            end
            emit(out, { kind = "PopTransform" })

        elseif kind == "Rect" then
            emit(out, {
                kind = "Rect",
                x = node.x,
                y = node.y,
                w = node.w,
                h = node.h,
                tag = node.tag,
            })

        elseif kind == "Text" then
            emit(out, {
                kind = "Text",
                x = node.x,
                y = node.y,
                w = node.w,
                h = node.h,
                tag = node.tag,
            })

        else
            error("Hit: unknown node kind " .. tostring(kind), 2)
        end
    end

    function T.Hit.Root:probe()
        local out = {}
        for i = #self.nodes, 1, -1 do
            flatten_node(self.nodes[i], out)
        end
        return out
    end

    local function current_transform(ctx)
        local top = ctx:peek("transform")
        if top then return top[1], top[2] end
        return 0, 0
    end

    local function push_clip(ctx, x, y, w, h)
        local tx, ty = current_transform(ctx)
        local nx, ny, nw, nh = x + tx, y + ty, w, h
        local top = ctx:peek("clip")
        if top then
            local x2 = math.max(nx, top[1])
            local y2 = math.max(ny, top[2])
            local r2 = math.min(nx + nw, top[1] + top[3])
            local b2 = math.min(ny + nh, top[2] + top[4])
            nx, ny, nw, nh = x2, y2, math.max(0, r2 - x2), math.max(0, b2 - y2)
        end
        ctx:push("clip", { nx, ny, nw, nh })
    end

    local function visible_in_clip(ctx, query, x, y, w, h)
        local clip = ctx:peek("clip")
        if clip and not inside(query.x, query.y, clip[1], clip[2], clip[3], clip[4]) then
            return false
        end
        return inside(query.x, query.y, x, y, w, h)
    end

    local backend = RT.backend("examples.ui.hittest", {
        _meta = { arity = 1, stacks = { "transform", "clip" } },
        PushTransform = function(cmd, ctx)
            local tx, ty = current_transform(ctx)
            ctx:push("transform", { tx + cmd.tx, ty + cmd.ty })
        end,

        PopTransform = function(cmd, ctx)
            ctx:pop("transform")
        end,

        PushClip = function(cmd, ctx)
            push_clip(ctx, cmd.x, cmd.y, cmd.w, cmd.h)
        end,

        PopClip = function(cmd, ctx)
            ctx:pop("clip")
        end,

        Rect = function(cmd, ctx, _, query)
            local tx, ty = current_transform(ctx)
            local x, y = cmd.x + tx, cmd.y + ty
            if visible_in_clip(ctx, query, x, y, cmd.w, cmd.h) then
                return {
                    kind = "Rect",
                    tag = cmd.tag,
                    x = x,
                    y = y,
                    w = cmd.w,
                    h = cmd.h,
                }
            end
            return nil
        end,

        Text = function(cmd, ctx, _, query)
            local tx, ty = current_transform(ctx)
            local x, y = cmd.x + tx, cmd.y + ty
            if visible_in_clip(ctx, query, x, y, cmd.w, cmd.h) then
                return {
                    kind = "Text",
                    tag = cmd.tag,
                    x = x,
                    y = y,
                    w = cmd.w,
                    h = cmd.h,
                }
            end
            return nil
        end,
    })

    function T:new_slot()
        return RT.slot(backend)
    end

    T.backend = backend

    return T
end
