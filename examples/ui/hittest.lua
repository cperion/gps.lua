-- examples/ui/hittest.lua
--
-- Minimal hit-testing terminal on top of mgps.
-- Runtime contract:
--   slot.callback({ x = ..., y = ... }) -> hit or nil

return function(M)
    local T = M.context("probe")
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

    local function rect_probe_gen(param, state, query)
        if inside(query.x, query.y, param.x, param.y, param.w, param.h) then
            return {
                kind = "Rect",
                tag = param.tag,
                x = param.x,
                y = param.y,
                w = param.w,
                h = param.h,
            }
        end
        return nil
    end

    local function text_probe_gen(param, state, query)
        if inside(query.x, query.y, param.x, param.y, param.w, param.h) then
            return {
                kind = "Text",
                tag = param.tag,
                x = param.x,
                y = param.y,
                w = param.w,
                h = param.h,
            }
        end
        return nil
    end

    local function probe_children_back_to_front(child_gens, param, state, query)
        for i = #child_gens, 1, -1 do
            local hit = child_gens[i](param[i], state[i], query)
            if hit ~= nil then return hit end
        end
        return nil
    end

    function T.Hit.Root:probe()
        local children, child_shapes = {}, {}
        for i = 1, #self.nodes do
            children[i] = self.nodes[i]:probe()
            child_shapes[i] = tostring(children[i].code_shape or self.nodes[i].kind or "child")
        end
        local out = M.compose(children, function(child_gens, param, state, query)
            return probe_children_back_to_front(child_gens, param, state, query)
        end)
        out.code_shape = "HitRoot(" .. table.concat(child_shapes, ",") .. ")"
        return out
    end

    function T.Hit.Group:probe()
        local children, child_shapes = {}, {}
        for i = 1, #self.children do
            children[i] = self.children[i]:probe()
            child_shapes[i] = tostring(children[i].code_shape or self.children[i].kind or "child")
        end
        local out = M.compose(children, function(child_gens, param, state, query)
            return probe_children_back_to_front(child_gens, param, state, query)
        end)
        out.code_shape = "HitGroup(" .. table.concat(child_shapes, ",") .. ")"
        return out
    end

    function T.Hit.Clip:probe()
        local children, child_shapes = {}, {}
        for i = 1, #self.children do
            children[i] = self.children[i]:probe()
            child_shapes[i] = tostring(children[i].code_shape or self.children[i].kind or "child")
        end
        local out = M.compose(children, function(child_gens, param, state, query)
            if not inside(query.x, query.y, param.x, param.y, param.w, param.h) then
                return nil
            end
            return probe_children_back_to_front(child_gens, param, state, query)
        end)
        out.param.x = self.x
        out.param.y = self.y
        out.param.w = self.w
        out.param.h = self.h
        out.code_shape = "HitClip(" .. table.concat(child_shapes, ",") .. ")"
        return out
    end

    function T.Hit.Transform:probe()
        local children, child_shapes = {}, {}
        for i = 1, #self.children do
            children[i] = self.children[i]:probe()
            child_shapes[i] = tostring(children[i].code_shape or self.children[i].kind or "child")
        end
        local out = M.compose(children, function(child_gens, param, state, query)
            local local_query = { x = query.x - param.tx, y = query.y - param.ty }
            return probe_children_back_to_front(child_gens, param, state, local_query)
        end)
        out.param.tx = self.tx
        out.param.ty = self.ty
        out.code_shape = "HitTransform(" .. table.concat(child_shapes, ",") .. ")"
        return out
    end

    function T.Hit.Rect:probe()
        return M.emit(
            rect_probe_gen,
            M.state.none(),
            {
                x = self.x,
                y = self.y,
                w = self.w,
                h = self.h,
                tag = self.tag,
            }
        )
    end

    function T.Hit.Text:probe()
        return M.emit(
            text_probe_gen,
            M.state.none(),
            {
                x = self.x,
                y = self.y,
                w = self.w,
                h = self.h,
                tag = self.tag,
            }
        )
    end

    return T
end
