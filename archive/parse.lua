-- gps/parse.lua — Primary parser API
--
-- Correct shape:
--   Grammar ASDL → compiled parser family → parse/emit/reduce/machine
--
-- GPS.parse is a facade over compiled parser families produced by GPS.grammar.
-- It may also accept a Grammar.Spec directly and compile it once per spec identity.
--
-- Usage:
--   local GPS = require("gps")
--   local P = GPS.grammar(spec)
--   local tree = GPS.parse(P, input)               -- tree mode (default)
--   local ok   = GPS.parse(P, input, "match")     -- recognizer
--   local val  = GPS.parse(P, input, actions)      -- reducer shortcut
--   local n    = GPS.parse(P, input, "emit", sink)
--
-- Low-level handwritten recursive descent lives in GPS.rd.

return function(GPS)
    local compiled_by_spec = setmetatable({}, { __mode = "k" })

    local function is_parser_family(x)
        return type(x) == "table" and rawget(x, "__gps_parser") == true
    end

    local function is_reducer_family(x)
        return type(x) == "table" and rawget(x, "__gps_reducer") == true
    end

    local function is_grammar_spec(x)
        local ctx = GPS.grammar.context()
        return ctx and ctx.Grammar and ctx.Grammar.Spec and ctx.Grammar.Spec:isclassof(x) or false
    end

    local function ensure_compiled(x)
        if is_parser_family(x) or is_reducer_family(x) then return x end
        if is_grammar_spec(x) then
            local hit = compiled_by_spec[x]
            if hit then return hit end
            local compiled = GPS.grammar(x)
            compiled_by_spec[x] = compiled
            return compiled
        end
        error("GPS.parse: expected compiled parser family, reducer family, or Grammar.Spec", 3)
    end

    local Api = {}

    function Api.compile(x)
        return ensure_compiled(x)
    end

    function Api.run(x, input_string, mode_or_actions, arg)
        local compiled = ensure_compiled(x)

        if is_reducer_family(compiled) then
            if mode_or_actions == nil or mode_or_actions == "tree" or mode_or_actions == "parse" then
                return compiled:parse(input_string)
            elseif mode_or_actions == "machine" then
                return compiled:machine(input_string)
            elseif mode_or_actions == "try" or mode_or_actions == "try_parse" then
                return compiled:try_parse(input_string)
            else
                error("GPS.parse: reducer family supports parse/try_parse/machine only", 2)
            end
        end

        if mode_or_actions == nil or mode_or_actions == "tree" or mode_or_actions == "parse" then
            return compiled:tree(input_string)
        end

        if mode_or_actions == "match" then
            return compiled:match(input_string)
        end

        if mode_or_actions == "emit" then
            return compiled:emit(input_string, arg)
        end

        if mode_or_actions == "try_emit" then
            return compiled:try_emit(input_string, arg)
        end

        if mode_or_actions == "try_tree" or mode_or_actions == "try_parse" then
            return compiled:try_tree(input_string)
        end

        if mode_or_actions == "reduce" then
            return compiled:reduce(input_string, arg)
        end

        if mode_or_actions == "try_reduce" then
            return compiled:try_reduce(input_string, arg)
        end

        if mode_or_actions == "machine" then
            return compiled:machine(input_string, arg and arg.mode, arg and arg.arg)
        end

        if type(mode_or_actions) == "table" then
            return compiled:reduce(input_string, mode_or_actions)
        end

        error("GPS.parse: unknown mode '" .. tostring(mode_or_actions) .. "'", 2)
    end

    function Api.try(x, input_string, mode_or_actions, arg)
        local ok, a, b = pcall(Api.run, x, input_string, mode_or_actions, arg)
        if ok then return true, a, b end
        return false, a
    end

    function Api.machine(x, input_string, mode, arg)
        local compiled = ensure_compiled(x)
        if is_reducer_family(compiled) then
            return compiled:machine(input_string)
        end
        return compiled:machine(input_string, mode, arg)
    end

    return setmetatable(Api, {
        __call = function(_, x, input_string, mode_or_actions, arg)
            return Api.run(x, input_string, mode_or_actions, arg)
        end,
    })
end
