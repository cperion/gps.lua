-- uvm_json.lua — handwritten and spec/plan-generated coarse JSON families for UVM

return function(uvm)
    local has_ffi, ffi = pcall(require, "ffi")
    local pvm = require("pvm")
    local Quote = require("quote")
    local S = uvm.status

    local M = {}

    local C_SPACE = 32; local C_TAB = 9; local C_NL = 10; local C_CR = 13
    local C_QUOTE = 34; local C_BSLASH = 92
    local C_LBRACE = 123; local C_RBRACE = 125
    local C_LBRACK = 91; local C_RBRACK = 93
    local C_COLON = 58; local C_COMMA = 44
    local C_MINUS = 45; local C_PLUS = 43; local C_DOT = 46
    local C_0 = 48; local C_9 = 57
    local C_t = 116; local C_f = 102; local C_n = 110
    local C_e = 101; local C_E = 69

    local ESCAPES = {
        [110] = "\n", [114] = "\r", [116] = "\t", [98] = "\b", [102] = "\f",
        [34] = "\"", [92] = "\\", [47] = "/",
    }

    local default_types
    local default_spec_types
    local default_plan_types
    local raw_buf, raw_cap = nil, 0
    local raw_asdl_buf, raw_asdl_cap = nil, 0

    local function need_ffi()
        if not has_ffi then error("uvm.json requires ffi/LuaJIT", 3) end
        return ffi
    end

    local function check_trailing(buf, pos, len)
        while pos < len do
            local b = buf[pos]
            if b ~= C_SPACE and b ~= C_TAB and b ~= C_NL and b ~= C_CR then
                error("trailing garbage at " .. tostring(pos), 3)
            end
            pos = pos + 1
        end
        return pos
    end

    local function is_ws(b) return b == C_SPACE or b == C_TAB or b == C_NL or b == C_CR end
    local function skip_ws(buf, pos, len)
        while pos < len and is_ws(buf[pos]) do pos = pos + 1 end
        return pos
    end

    local function decode_string(buf, pos, len, src)
        pos = pos + 1
        local start = pos
        local has_esc = false
        while pos < len do
            local b = buf[pos]
            if b == C_QUOTE then
                if not has_esc then
                    return pos + 1, src:sub(start + 1, pos)
                end
                local parts = {}
                local seg_start = start
                local i = start
                while i < pos do
                    if buf[i] == C_BSLASH then
                        parts[#parts + 1] = src:sub(seg_start + 1, i)
                        i = i + 1
                        local esc = ESCAPES[buf[i]]
                        parts[#parts + 1] = esc or string.char(buf[i])
                        i = i + 1
                        seg_start = i
                    else
                        i = i + 1
                    end
                end
                parts[#parts + 1] = src:sub(seg_start + 1, pos)
                return pos + 1, table.concat(parts)
            elseif b == C_BSLASH then
                has_esc = true
                pos = pos + 2
            else
                pos = pos + 1
            end
        end
        error("unterminated string", 3)
    end

    local function decode_number(buf, pos, len, src)
        local start = pos
        if buf[pos] == C_MINUS then pos = pos + 1 end
        if buf[pos] == C_0 then
            pos = pos + 1
        else
            while pos < len and buf[pos] >= C_0 and buf[pos] <= C_9 do pos = pos + 1 end
        end
        if pos < len and buf[pos] == C_DOT then
            pos = pos + 1
            while pos < len and buf[pos] >= C_0 and buf[pos] <= C_9 do pos = pos + 1 end
        end
        if pos < len and (buf[pos] == C_e or buf[pos] == C_E) then
            pos = pos + 1
            if pos < len and (buf[pos] == C_PLUS or buf[pos] == C_MINUS) then pos = pos + 1 end
            while pos < len and buf[pos] >= C_0 and buf[pos] <= C_9 do pos = pos + 1 end
        end
        return pos, tonumber(src:sub(start + 1, pos))
    end

    local decode_table_value
    decode_table_value = function(buf, pos, len, src)
        pos = skip_ws(buf, pos, len)
        if pos >= len then error("unexpected end", 3) end
        local b = buf[pos]
        if b == C_QUOTE then
            return decode_string(buf, pos, len, src)
        elseif b == C_LBRACE then
            pos = skip_ws(buf, pos + 1, len)
            local obj = {}
            if buf[pos] == C_RBRACE then return pos + 1, obj end
            while true do
                pos = skip_ws(buf, pos, len)
                local key; pos, key = decode_string(buf, pos, len, src)
                pos = skip_ws(buf, pos, len)
                if buf[pos] ~= C_COLON then error("expected ':' at " .. tostring(pos), 3) end
                pos = pos + 1
                local val; pos, val = decode_table_value(buf, pos, len, src)
                obj[key] = val
                pos = skip_ws(buf, pos, len)
                if buf[pos] == C_RBRACE then return pos + 1, obj end
                if buf[pos] ~= C_COMMA then error("expected ',' at " .. tostring(pos), 3) end
                pos = pos + 1
            end
        elseif b == C_LBRACK then
            pos = skip_ws(buf, pos + 1, len)
            local arr = {}
            if buf[pos] == C_RBRACK then return pos + 1, arr end
            local n = 0
            while true do
                local val; pos, val = decode_table_value(buf, pos, len, src)
                n = n + 1; arr[n] = val
                pos = skip_ws(buf, pos, len)
                if buf[pos] == C_RBRACK then return pos + 1, arr end
                if buf[pos] ~= C_COMMA then error("expected ',' at " .. tostring(pos), 3) end
                pos = pos + 1
            end
        elseif b == C_t then
            return pos + 4, true
        elseif b == C_f then
            return pos + 5, false
        elseif b == C_n then
            return pos + 4, nil
        elseif b == C_MINUS or (b >= C_0 and b <= C_9) then
            return decode_number(buf, pos, len, src)
        end
        error("unexpected char " .. string.char(b) .. " at " .. tostring(pos), 3)
    end

    local function source_of(param, source_key)
        if type(param) == "string" then return param end
        if type(param) ~= "table" then error("json param must be a string or table", 3) end
        return assert(param[source_key], "missing json source field '" .. tostring(source_key) .. "'")
    end

    local function alloc_buffer(src)
        local _ffi = need_ffi()
        local len = #src
        local buf = _ffi.new("uint8_t[?]", len)
        _ffi.copy(buf, src, len)
        return buf, len
    end

    function M.raw_decode(src)
        local _ffi = need_ffi()
        local len = #src
        if len > raw_cap then raw_buf = _ffi.new("uint8_t[?]", len); raw_cap = len end
        _ffi.copy(raw_buf, src, len)
        local pos, val = decode_table_value(raw_buf, 0, len, src)
        check_trailing(raw_buf, pos, len)
        return val
    end

    function M.decoder(opts)
        opts = opts or {}
        local source_key = opts.source_key or "source"
        return uvm.family({
            name = opts.name or "json.table",
            statuses = opts.statuses or { [S.YIELD] = true, [S.HALT] = true },
            init = function(param, _seed)
                local src = source_of(param, source_key)
                local buf, len = alloc_buffer(src)
                return { buf = buf, len = len, src = src, pos = 0, done = false }
            end,
            step = function(_param, state)
                if state.done then return nil, S.HALT end
                local pos, val = decode_table_value(state.buf, state.pos, state.len, state.src)
                state.pos = check_trailing(state.buf, pos, state.len)
                state.done = true
                return state, S.YIELD, val
            end,
        })
    end

    function M.define_types(ctx, module_name)
        module_name = module_name or "Json"
        ctx = ctx or uvm.context()
        ctx:Define(string.format([[module %s {
    Value = Str(string value) unique
          | Num(number value) unique
          | Bool(boolean value) unique
          | Null
          | Arr(%s.Value* items) unique
          | Obj(%s.Pair* pairs) unique
    Pair = (string key, %s.Value value) unique
}]], module_name, module_name, module_name, module_name))
        return ctx
    end

    local function default_json_types()
        if not default_types then default_types = M.define_types() end
        return default_types
    end

    -- Compile-time JSON modeling is intentionally split in two:
    --   UJsonSpec = authored specialization choices (table vs ASDL output, etc.)
    --   UJsonPlan = lowered parser/code-shape decisions consumed by Quote codegen
    -- This keeps ASDL focused on cacheable specialization identity, not generic
    -- parser-expression algebra.
    local function default_json_spec_types()
        if not default_spec_types then
            default_spec_types = uvm.context():Define [[
                module UJsonSpec {
                    EmitPolicy = EmitTable
                               | EmitAsdl(string module_name,
                                          table ctx) unique
                    Spec = Json(UJsonSpec.EmitPolicy emit) unique
                }
            ]]
        end
        return default_spec_types
    end

    local function default_json_plan_types()
        if not default_plan_types then
            default_plan_types = uvm.context():Define [[
                module UJsonPlan {
                    EmitPolicy = EmitTable
                               | EmitAsdl(string module_name,
                                          table ctx) unique
                    ObjectMode = BuildObjectDirect
                               | BuildPairList
                    Plan = JsonPlan(UJsonPlan.EmitPolicy emit,
                                    UJsonPlan.ObjectMode object_mode) unique
                }
            ]]
        end
        return default_plan_types
    end

    local function json_spec_module(ctx)
        ctx = ctx or default_json_spec_types()
        return ctx.UJsonSpec, ctx
    end

    local function json_plan_module(ctx)
        ctx = ctx or default_json_plan_types()
        return ctx.UJsonPlan, ctx
    end

    local function json_constructors(ctx, module_name)
        ctx = ctx or default_json_types()
        module_name = module_name or "Json"
        local J = assert(ctx[module_name], "missing JSON ASDL module '" .. tostring(module_name) .. "'")
        return {
            Str = J.Str,
            Num = J.Num,
            Bool = J.Bool,
            Null = J.Null,
            Arr = J.Arr,
            Obj = J.Obj,
            Pair = J.Pair,
            module = J,
            ctx = ctx,
        }
    end

    function M.spec_types(ctx)
        return ctx or default_json_spec_types()
    end

    function M.plan_types(ctx)
        return ctx or default_json_plan_types()
    end

    -- Authored compile specs.

    function M.spec_table(ctx)
        local JS = json_spec_module(ctx)
        return JS.Json(JS.EmitTable)
    end

    function M.spec_asdl(opts)
        opts = opts or {}
        local JS = json_spec_module(opts.spec_types)
        local ctx = opts.types or opts.ctx or default_json_types()
        local module_name = opts.module_name or "Json"
        return JS.Json(JS.EmitAsdl(module_name, ctx))
    end

    -- Lower authored JSON compile specs to parser-plan/code-shape ASDL.
    local lower_json_spec = pvm.lower("uvm.json.lower_spec", function(spec)
        local JS = json_spec_module()
        local JP = json_plan_module()
        local emit = spec.emit
        local emit_mt = getmetatable(emit)
        if emit == JS.EmitTable then
            return JP.JsonPlan(JP.EmitTable, JP.BuildObjectDirect)
        elseif emit_mt == JS.EmitAsdl then
            return JP.JsonPlan(JP.EmitAsdl(emit.module_name, emit.ctx), JP.BuildPairList)
        end
        error("unknown json spec emit policy", 2)
    end, { input = "table" })

    local function make_asdl_decoder(C)
        local decode_asdl_value
        decode_asdl_value = function(buf, pos, len, src)
            pos = skip_ws(buf, pos, len)
            if pos >= len then error("unexpected end", 3) end
            local b = buf[pos]
            if b == C_QUOTE then
                local s; pos, s = decode_string(buf, pos, len, src)
                return pos, C.Str(s)
            elseif b == C_LBRACE then
                pos = skip_ws(buf, pos + 1, len)
                local pairs = {}
                if buf[pos] == C_RBRACE then return pos + 1, C.Obj(pairs) end
                local n = 0
                while true do
                    pos = skip_ws(buf, pos, len)
                    local key; pos, key = decode_string(buf, pos, len, src)
                    pos = skip_ws(buf, pos, len)
                    if buf[pos] ~= C_COLON then error("expected ':' at " .. tostring(pos), 3) end
                    pos = pos + 1
                    local val; pos, val = decode_asdl_value(buf, pos, len, src)
                    n = n + 1; pairs[n] = C.Pair(key, val)
                    pos = skip_ws(buf, pos, len)
                    if buf[pos] == C_RBRACE then return pos + 1, C.Obj(pairs) end
                    if buf[pos] ~= C_COMMA then error("expected ',' at " .. tostring(pos), 3) end
                    pos = pos + 1
                end
            elseif b == C_LBRACK then
                pos = skip_ws(buf, pos + 1, len)
                local items = {}
                if buf[pos] == C_RBRACK then return pos + 1, C.Arr(items) end
                local n = 0
                while true do
                    local val; pos, val = decode_asdl_value(buf, pos, len, src)
                    n = n + 1; items[n] = val
                    pos = skip_ws(buf, pos, len)
                    if buf[pos] == C_RBRACK then return pos + 1, C.Arr(items) end
                    if buf[pos] ~= C_COMMA then error("expected ',' at " .. tostring(pos), 3) end
                    pos = pos + 1
                end
            elseif b == C_t then
                return pos + 4, C.Bool(true)
            elseif b == C_f then
                return pos + 5, C.Bool(false)
            elseif b == C_n then
                return pos + 4, C.Null
            elseif b == C_MINUS or (b >= C_0 and b <= C_9) then
                local num; pos, num = decode_number(buf, pos, len, src)
                return pos, C.Num(num)
            end
            error("unexpected char " .. string.char(b) .. " at " .. tostring(pos), 3)
        end
        return decode_asdl_value
    end

    function M.raw_decode_asdl(src, opts)
        opts = opts or {}
        local C = json_constructors(opts.types or opts.ctx, opts.module_name)
        local decode_asdl_value = make_asdl_decoder(C)
        local _ffi = need_ffi()
        local len = #src
        if len > raw_asdl_cap then raw_asdl_buf = _ffi.new("uint8_t[?]", len); raw_asdl_cap = len end
        _ffi.copy(raw_asdl_buf, src, len)
        local pos, val = decode_asdl_value(raw_asdl_buf, 0, len, src)
        check_trailing(raw_asdl_buf, pos, len)
        return val
    end

    function M.asdl_decoder(opts)
        opts = opts or {}
        local source_key = opts.source_key or "source"
        local C = json_constructors(opts.types or opts.ctx, opts.module_name)
        local decode_asdl_value = make_asdl_decoder(C)
        local fam = uvm.family({
            name = opts.name or "json.asdl",
            statuses = opts.statuses or { [S.YIELD] = true, [S.HALT] = true },
            init = function(param, _seed)
                local src = source_of(param, source_key)
                local buf, len = alloc_buffer(src)
                return { buf = buf, len = len, src = src, done = false }
            end,
            step = function(_param, state)
                if state.done then return nil, S.HALT end
                local pos, val = decode_asdl_value(state.buf, 0, state.len, state.src)
                check_trailing(state.buf, pos, state.len)
                state.done = true
                return state, S.YIELD, val
            end,
        })
        fam.json_types = C.ctx
        fam.json_module = C.module
        return fam
    end

    -- Compile a lowered JSON plan to a specialized decoder.
    local function compile_json_plan(plan)
        local JP = json_plan_module()
        local emit = plan.emit
        local emit_mt = getmetatable(emit)
        local object_direct = plan.object_mode == JP.BuildObjectDirect
        local q = Quote()
        local _ffi = q:val(need_ffi(), "ffi")
        local _skip_ws = q:val(skip_ws, "skip_ws")
        local _decode_string = q:val(decode_string, "decode_string")
        local _decode_number = q:val(decode_number, "decode_number")
        local _check_trailing = q:val(check_trailing, "check_trailing")
        local _shared = q:val({ buf = nil, cap = 0 }, "shared")

        local emit_table = (emit == JP.EmitTable)
        local C = nil
        if not emit_table then
            assert(emit_mt == JP.EmitAsdl, "unknown json plan emit policy")
            C = json_constructors(emit.ctx, emit.module_name)
        end

        local parse_value = q:sym("parse_value")
        local parse_object = q:sym("parse_object")
        local parse_array = q:sym("parse_array")
        q("local %s, %s, %s", parse_value, parse_object, parse_array)

        q("%s = function(buf, pos, len, src)", parse_object)
        q("  pos = %s(buf, pos + 1, len)", _skip_ws)
        if object_direct then
            q("  local obj = {}")
            q("  if buf[pos] == %d then return pos + 1, obj end", C_RBRACE)
            q("  while true do")
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    local key; pos, key = %s(buf, pos, len, src)", _decode_string)
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    if buf[pos] ~= %d then error(\"expected ':' at \" .. tostring(pos), 2) end", C_COLON)
            q("    pos = pos + 1")
            q("    local val; pos, val = %s(buf, pos, len, src)", parse_value)
            q("    obj[key] = val")
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    if buf[pos] == %d then return pos + 1, obj end", C_RBRACE)
            q("    if buf[pos] ~= %d then error(\"expected ',' at \" .. tostring(pos), 2) end", C_COMMA)
            q("    pos = pos + 1")
            q("  end")
        else
            local Pair = q:val(C.Pair, "Pair")
            local Obj = q:val(C.Obj, "Obj")
            q("  local pairs = {}")
            q("  if buf[pos] == %d then return pos + 1, %s(pairs) end", C_RBRACE, Obj)
            q("  local n = 0")
            q("  while true do")
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    local key; pos, key = %s(buf, pos, len, src)", _decode_string)
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    if buf[pos] ~= %d then error(\"expected ':' at \" .. tostring(pos), 2) end", C_COLON)
            q("    pos = pos + 1")
            q("    local val; pos, val = %s(buf, pos, len, src)", parse_value)
            q("    n = n + 1; pairs[n] = %s(key, val)", Pair)
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    if buf[pos] == %d then return pos + 1, %s(pairs) end", C_RBRACE, Obj)
            q("    if buf[pos] ~= %d then error(\"expected ',' at \" .. tostring(pos), 2) end", C_COMMA)
            q("    pos = pos + 1")
            q("  end")
        end
        q("end")

        q("%s = function(buf, pos, len, src)", parse_array)
        q("  pos = %s(buf, pos + 1, len)", _skip_ws)
        if emit_table then
            q("  local arr = {}")
            q("  if buf[pos] == %d then return pos + 1, arr end", C_RBRACK)
            q("  local n = 0")
            q("  while true do")
            q("    local val; pos, val = %s(buf, pos, len, src)", parse_value)
            q("    n = n + 1; arr[n] = val")
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    if buf[pos] == %d then return pos + 1, arr end", C_RBRACK)
            q("    if buf[pos] ~= %d then error(\"expected ',' at \" .. tostring(pos), 2) end", C_COMMA)
            q("    pos = pos + 1")
            q("  end")
        else
            local Arr = q:val(C.Arr, "Arr")
            q("  local items = {}")
            q("  if buf[pos] == %d then return pos + 1, %s(items) end", C_RBRACK, Arr)
            q("  local n = 0")
            q("  while true do")
            q("    local val; pos, val = %s(buf, pos, len, src)", parse_value)
            q("    n = n + 1; items[n] = val")
            q("    pos = %s(buf, pos, len)", _skip_ws)
            q("    if buf[pos] == %d then return pos + 1, %s(items) end", C_RBRACK, Arr)
            q("    if buf[pos] ~= %d then error(\"expected ',' at \" .. tostring(pos), 2) end", C_COMMA)
            q("    pos = pos + 1")
            q("  end")
        end
        q("end")

        q("%s = function(buf, pos, len, src)", parse_value)
        q("  pos = %s(buf, pos, len)", _skip_ws)
        q("  if pos >= len then error(\"unexpected end\", 2) end")
        q("  local b = buf[pos]")
        q("  if b == %d then", C_QUOTE)
        q("    local s; pos, s = %s(buf, pos, len, src)", _decode_string)
        if emit_table then
            q("    return pos, s")
        else
            q("    return pos, %s(s)", q:val(C.Str, "Str"))
        end
        q("  elseif b == %d then", C_LBRACE)
        q("    return %s(buf, pos, len, src)", parse_object)
        q("  elseif b == %d then", C_LBRACK)
        q("    return %s(buf, pos, len, src)", parse_array)
        q("  elseif b == %d then", C_t)
        if emit_table then q("    return pos + 4, true") else q("    return pos + 4, %s(true)", q:val(C.Bool, "Bool")) end
        q("  elseif b == %d then", C_f)
        if emit_table then q("    return pos + 5, false") else q("    return pos + 5, %s(false)", q:val(C.Bool, "Bool")) end
        q("  elseif b == %d then", C_n)
        if emit_table then q("    return pos + 4, nil") else q("    return pos + 4, %s", q:val(C.Null, "Null")) end
        q("  elseif b == %d or (b >= %d and b <= %d) then", C_MINUS, C_0, C_9)
        q("    local n; pos, n = %s(buf, pos, len, src)", _decode_number)
        if emit_table then q("    return pos, n") else q("    return pos, %s(n)", q:val(C.Num, "Num")) end
        q("  end")
        q("  error(\"unexpected char \" .. string.char(b) .. \" at \" .. tostring(pos), 2)")
        q("end")

        q("return function(src)")
        q("  local len = #src")
        q("  if len > %s.cap then %s.buf = %s.new(\"uint8_t[?]\", len); %s.cap = len end", _shared, _shared, _ffi, _shared)
        q("  %s.copy(%s.buf, src, len)", _ffi, _shared)
        q("  local pos, val = %s(%s.buf, 0, len, src)", parse_value, _shared)
        q("  %s(%s.buf, pos, len)", _check_trailing, _shared)
        q("  return val")
        q("end")

        local fn, src = q:compile("=(uvm.json.generated)")
        return { decode = fn, source = src, plan = plan }
    end

    local compile_json_plan_lower = pvm.lower("uvm.json.compile_plan", compile_json_plan, { input = "table" })

    local function resolve_generated_json(spec)
        local plan = lower_json_spec(spec)
        local generated = compile_json_plan_lower(plan)
        return plan, generated
    end

    local function make_generated_family(opts, default_name, generated)
        local source_key = opts.source_key or "source"
        return uvm.family({
            name = opts.name or default_name,
            statuses = opts.statuses or { [S.YIELD] = true, [S.HALT] = true },
            init = function(_param, _seed) return { done = false } end,
            step = function(param, state)
                if state.done then return nil, S.HALT end
                local val = generated.decode(source_of(param, source_key))
                state.done = true
                return state, S.YIELD, val
            end,
        })
    end

    function M.generated(opts)
        opts = opts or {}
        local spec = opts.spec or M.spec_table()
        local plan, generated = resolve_generated_json(spec)
        generated.spec = spec
        generated.plan = plan
        return generated
    end

    function M.generated_decoder(opts)
        opts = opts or {}
        local spec = opts.spec or M.spec_table()
        local plan, generated = resolve_generated_json(spec)
        local fam = make_generated_family(opts, "json.table.generated", generated)
        fam.source = generated.source
        fam.generated_spec = spec
        fam.generated_plan = plan
        return fam
    end

    function M.generated_asdl_decoder(opts)
        opts = opts or {}
        local spec = opts.spec or M.spec_asdl(opts)
        local plan, generated = resolve_generated_json(spec)
        local emit = spec.emit
        local fam = make_generated_family(opts, "json.asdl.generated", generated)
        fam.source = generated.source
        fam.generated_spec = spec
        fam.generated_plan = plan
        fam.json_types = opts.types or opts.ctx or emit.ctx
        fam.json_module = fam.json_types and fam.json_types[emit.module_name] or nil
        return fam
    end

    return M
end
