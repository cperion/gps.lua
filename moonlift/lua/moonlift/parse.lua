package.path = "./?.lua;./?/init.lua;" .. package.path

local Lexer = require("moonlift.parse_lexer")
local Spans = require("moonlift.source_spans")

local M = {}

local SCALAR_TYPES = {
    void = "SurfTVoid",
    bool = "SurfTBool",
    i8 = "SurfTI8",
    i16 = "SurfTI16",
    i32 = "SurfTI32",
    i64 = "SurfTI64",
    u8 = "SurfTU8",
    u16 = "SurfTU16",
    u32 = "SurfTU32",
    u64 = "SurfTU64",
    f32 = "SurfTF32",
    f64 = "SurfTF64",
    index = "SurfTIndex",
}

local INTRINSICS = {
    popcount = "SurfPopcount",
    clz = "SurfClz",
    ctz = "SurfCtz",
    rotl = "SurfRotl",
    rotr = "SurfRotr",
    bswap = "SurfBswap",
    fma = "SurfFma",
    sqrt = "SurfSqrt",
    abs = "SurfAbs",
    floor = "SurfFloor",
    ceil = "SurfCeil",
    trunc_float = "SurfTruncFloat",
    round = "SurfRound",
    trap = "SurfTrap",
    assume = "SurfAssume",
}

local INFIX = {
    ["or"]  = { 10, 11, "SurfExprOr" },
    ["and"] = { 20, 21, "SurfExprAnd" },

    ["=="] = { 30, 31, "SurfExprEq" },
    ["~="] = { 30, 31, "SurfExprNe" },
    ["<"]  = { 30, 31, "SurfExprLt" },
    ["<="] = { 30, 31, "SurfExprLe" },
    [">"]  = { 30, 31, "SurfExprGt" },
    [">="] = { 30, 31, "SurfExprGe" },

    ["|"] = { 40, 41, "SurfExprBitOr" },
    ["~"] = { 50, 51, "SurfExprBitXor" },
    ["&"] = { 60, 61, "SurfExprBitAnd" },

    ["<<"]  = { 70, 71, "SurfExprShl" },
    [">>"]  = { 70, 71, "SurfExprAShr" },
    [">>>"] = { 70, 71, "SurfExprLShr" },

    ["+"] = { 80, 81, "SurfExprAdd" },
    ["-"] = { 80, 81, "SurfExprSub" },

    ["*"] = { 90, 91, "SurfExprMul" },
    ["/"] = { 90, 91, "SurfExprDiv" },
    ["%"] = { 90, 91, "SurfExprRem" },
}

local PREFIX_BP = 100

local function parse_error(tok, msg)
    error(Lexer.new_diag("parse", tok.line, tok.col, msg, tok.offset, tok.finish), 0)
end

local Parser = {}
Parser.__index = Parser

function Parser.new(Surf, tokens, span_index)
    return setmetatable({
        Surf = Surf,
        tokens = tokens,
        pos = 1,
        spans = span_index,
    }, Parser)
end

function Parser:peek(off)
    return self.tokens[self.pos + (off or 0)]
end

function Parser:kind(off)
    return self:peek(off).kind
end

function Parser:raw(off)
    return self:peek(off).raw
end

function Parser:is(kind, off)
    return self:kind(off) == kind
end

function Parser:bump()
    local tok = self:peek()
    self.pos = self.pos + 1
    return tok
end

function Parser:consume(kind)
    if self:is(kind) then
        return self:bump()
    end
    return nil
end

function Parser:expect(kind, msg)
    local tok = self:peek()
    if tok.kind ~= kind then
        parse_error(tok, msg or ("expected '" .. kind .. "', got '" .. tok.kind .. "'"))
    end
    return self:bump()
end

function Parser:skip_nl()
    while self:is("nl") do
        self:bump()
    end
end

function Parser:last()
    return self:peek(-1)
end

function Parser:record_span(path, first_tok, last_tok, tag)
    Spans.record(self.spans, path, first_tok, last_tok or self:last(), tag)
end

function Parser:with_span(path, tag, fn)
    local first = self:peek()
    local value = fn(self)
    self:record_span(path, first, self:last(), tag)
    return value
end

function Parser:scoped(base, suffix)
    if base == nil or base == "" then
        return suffix
    end
    return base .. "." .. suffix
end

function Parser:require_nl()
    if not self:consume("nl") then
        parse_error(self:peek(), "expected newline")
    end
    self:skip_nl()
end

function Parser:path_from_parts(parts)
    local out = {}
    for i = 1, #parts do
        out[i] = self.Surf.SurfName(parts[i])
    end
    return self.Surf.SurfPath(out)
end

function Parser:expr_from_parts(parts)
    local expr = self.Surf.SurfNameRef(parts[1])
    for i = 2, #parts do
        expr = self.Surf.SurfExprDot(expr, parts[i])
    end
    return expr
end

function Parser:parse_path_from_first(first)
    local parts = { first.raw }
    while self:consume(".") do
        parts[#parts + 1] = self:expect("ident", "expected identifier after '.'").raw
    end
    return self:path_from_parts(parts), parts
end

function Parser:parse_path()
    return self:parse_path_from_first(self:expect("ident", "expected identifier for path"))
end

function Parser:parse_type()
    local tok = self:peek()
    local scalar_ctor = SCALAR_TYPES[tok.kind]
    if scalar_ctor ~= nil then
        self:bump()
        return self.Surf[scalar_ctor]
    end
    if self:consume("&") then
        return self.Surf.SurfTPtr(self:parse_type())
    end
    if self:consume("[") then
        if self:consume("]") then
            return self.Surf.SurfTSlice(self:parse_type())
        end
        local count = self:parse_expr()
        self:expect("]")
        return self.Surf.SurfTArray(count, self:parse_type())
    end
    if self:consume("view") then
        self:expect("(")
        local elem = self:parse_type()
        self:expect(")")
        return self.Surf.SurfTView(elem)
    end
    if self:consume("func") then
        self:expect("(")
        local params = {}
        if not self:is(")") then
            repeat
                params[#params + 1] = self:parse_type()
            until not self:consume(",")
        end
        self:expect(")")
        self:expect("->")
        return self.Surf.SurfTFunc(params, self:parse_type())
    end
    if tok.kind == "ident" then
        local path = self:parse_path()
        return self.Surf.SurfTNamed(path)
    end
    parse_error(tok, "expected type")
end

function Parser:expr_to_place(expr)
    local kind = expr.kind
    if kind == "SurfNameRef" then
        return self.Surf.SurfPlaceName(expr.name)
    end
    if kind == "SurfPathRef" then
        return self.Surf.SurfPlacePath(expr.path)
    end
    if kind == "SurfExprDeref" then
        return self.Surf.SurfPlaceDeref(expr.value)
    end
    if kind == "SurfExprDot" then
        local base = self:expr_to_place(expr.base)
        if base == nil then return nil end
        return self.Surf.SurfPlaceDot(base, expr.name)
    end
    if kind == "SurfField" then
        local base = self:expr_to_place(expr.base)
        if base == nil then return nil end
        return self.Surf.SurfPlaceField(base, expr.name)
    end
    if kind == "SurfIndex" then
        return self.Surf.SurfPlaceIndex(expr.base, expr.index)
    end
    return nil
end

function Parser:parse_braced_entries(parse_one)
    local out = {}
    self:expect("{")
    self:skip_nl()
    if not self:is("}") then
        while true do
            out[#out + 1] = parse_one()
            self:skip_nl()
            if not self:consume(",") then break end
            self:skip_nl()
            if self:is("}") then break end
        end
    end
    self:skip_nl()
    self:expect("}")
    return out
end

function Parser:parse_field_init()
    local name = self:expect("ident", "expected field name").raw
    self:expect("=")
    return self.Surf.SurfFieldInit(name, self:parse_expr())
end

function Parser:parse_field_decl()
    local field_name = self:expect("ident", "expected field name").raw
    self:expect(":")
    return self.Surf.SurfFieldDecl(field_name, self:parse_type())
end

function Parser:parse_intrinsic_or_ref(first)
    if first.raw == "select" and self:is("(") then
        self:bump()
        local cond = self:parse_expr()
        self:expect(",")
        local then_expr = self:parse_expr()
        self:expect(",")
        local else_expr = self:parse_expr()
        self:expect(")")
        return self.Surf.SurfSelectExpr(cond, then_expr, else_expr)
    end
    if INTRINSICS[first.raw] ~= nil and self:is("(") then
        self:bump()
        local args = {}
        if not self:is(")") then
            repeat
                args[#args + 1] = self:parse_expr()
            until not self:consume(",")
        end
        self:expect(")")
        return self.Surf.SurfExprIntrinsicCall(self.Surf[INTRINSICS[first.raw]], args)
    end
    local path, parts = self:parse_path_from_first(first)
    if self:is("{") then
        return self.Surf.SurfAgg(
            self.Surf.SurfTNamed(path),
            self:parse_braced_entries(function() return self:parse_field_init() end)
        )
    end
    if #parts == 1 then
        return self.Surf.SurfNameRef(parts[1])
    end
    return self:expr_from_parts(parts)
end

function Parser:parse_cast_expr(kind)
    self:expect(kind)
    self:expect("<")
    local ty = self:parse_type()
    self:expect(">")
    self:expect("(")
    local value = self:parse_expr()
    self:expect(")")
    if kind == "cast" then return self.Surf.SurfExprCastTo(ty, value) end
    if kind == "trunc" then return self.Surf.SurfExprTruncTo(ty, value) end
    if kind == "zext" then return self.Surf.SurfExprZExtTo(ty, value) end
    if kind == "sext" then return self.Surf.SurfExprSExtTo(ty, value) end
    if kind == "bitcast" then return self.Surf.SurfExprBitcastTo(ty, value) end
    return self.Surf.SurfExprSatCastTo(ty, value)
end

function Parser:parse_if_expr()
    self:expect("if")
    local cond = self:parse_expr()
    self:expect("then")
    self:skip_nl()
    local then_expr = self:parse_expr()
    self:skip_nl()
    self:expect("else")
    self:skip_nl()
    local else_expr = self:parse_expr()
    self:skip_nl()
    self:expect("end")
    return self.Surf.SurfIfExpr(cond, then_expr, else_expr)
end

function Parser:parse_expr_block(terminators)
    local stmts = self:parse_stmt_block(terminators)
    if #stmts == 0 then
        parse_error(self:peek(), "expression block must contain a final expression")
    end
    local last = stmts[#stmts]
    if last.kind ~= "SurfExprStmt" then
        parse_error(self:peek(), "expression block must end with an expression")
    end
    stmts[#stmts] = nil
    return stmts, last.expr
end

function Parser:parse_switch_expr()
    self:expect("switch")
    local value = self:parse_expr()
    self:expect("do")
    self:require_nl()
    local arms = {}
    while self:is("case") do
        self:bump()
        local key = self:parse_expr()
        self:expect("then")
        self:require_nl()
        local body, result = self:parse_expr_block({ case = true, default = true, ["end"] = true })
        arms[#arms + 1] = self.Surf.SurfSwitchExprArm(key, body, result)
    end
    self:expect("default")
    self:expect("then")
    self:require_nl()
    local default_body, default_expr = self:parse_expr_block({ ["end"] = true })
    self:expect("end")
    if #default_body ~= 0 then
        parse_error(self:peek(-1), "switch expr default arm statements are not implemented yet in bootstrap parser")
    end
    return self.Surf.SurfSwitchExpr(value, arms, default_expr)
end

function Parser:parse_switch_stmt(path)
    self:expect("switch")
    local value = self:parse_expr()
    self:expect("do")
    self:require_nl()
    local arms = {}
    local arm_i = 0
    while self:is("case") do
        arm_i = arm_i + 1
        local arm_first = self:peek()
        self:bump()
        local key = self:parse_expr()
        self:expect("then")
        self:require_nl()
        local arm_path = path and self:scoped(path, "arm." .. arm_i) or nil
        arms[#arms + 1] = self.Surf.SurfSwitchStmtArm(
            key,
            self:parse_stmt_block({ case = true, default = true, ["end"] = true }, arm_path and self:scoped(arm_path, "body") or nil)
        )
        self:record_span(arm_path, arm_first)
    end
    local default_first = self:peek()
    self:expect("default")
    self:expect("then")
    self:require_nl()
    local default_body = self:parse_stmt_block({ ["end"] = true }, path and self:scoped(path, "default") or nil)
    self:expect("end")
    self:record_span(path and self:scoped(path, "default") or nil, default_first)
    return self.Surf.SurfSwitch(value, arms, default_body)
end

function Parser:parse_domain()
    if self:is("ident") and self:raw() == "range" and self:kind(1) == "(" then
        self:bump()
        self:expect("(")
        local first = self:parse_expr()
        if self:consume(",") then
            local second = self:parse_expr()
            self:expect(")")
            return self.Surf.SurfDomainRange2(first, second)
        end
        self:expect(")")
        return self.Surf.SurfDomainRange(first)
    end
    if self:is("ident") and self:raw() == "zip_eq" and self:kind(1) == "(" then
        self:bump()
        self:expect("(")
        local values = {}
        if not self:is(")") then
            repeat
                values[#values + 1] = self:parse_expr()
            until not self:consume(",")
        end
        self:expect(")")
        return self.Surf.SurfDomainZipEq(values)
    end
    return self.Surf.SurfDomainValue(self:parse_expr())
end

function Parser:parse_loop_carry_list(base_path)
    local carries = {}
    local i = 0
    repeat
        i = i + 1
        local first = self:peek()
        local name = self:expect("ident", "expected loop carry name").raw
        self:expect(":")
        local ty = self:parse_type()
        self:expect("=")
        carries[#carries + 1] = self.Surf.SurfLoopCarryInit(name, ty, self:parse_expr())
        self:record_span(base_path and self:scoped(base_path, tostring(i)) or nil, first)
    until not self:consume(",")
    return carries
end

function Parser:parse_loop_next_block(base_path)
    local nexts = {}
    local i = 0
    self:skip_nl()
    while not self:is("end") do
        i = i + 1
        local first = self:peek()
        local name = self:expect("ident", "expected loop next binding name").raw
        self:expect("=")
        nexts[#nexts + 1] = self.Surf.SurfLoopNextAssign(name, self:parse_expr())
        self:record_span(base_path and self:scoped(base_path, tostring(i)) or nil, first)
        if self:consume("nl") then
            self:skip_nl()
        elseif not self:is("end") then
            parse_error(self:peek(), "expected newline or 'end' after loop next assignment")
        end
    end
    return nexts
end

function Parser:parse_loop(is_expr, path)
    self:expect("loop")

    if self:is("ident") and self:kind(1) == "over" then
        local index_name = self:bump().raw
        self:expect("over")
        local domain = self:parse_domain()
        local carries = {}
        if self:consume(",") then
            carries = self:parse_loop_carry_list(path and self:scoped(path, "carries") or nil)
        end
        self:require_nl()
        local body = self:parse_stmt_block({ next = true }, path and self:scoped(path, "body") or nil)
        self:expect("next")
        self:require_nl()
        local nexts = self:parse_loop_next_block(path and self:scoped(path, "next") or nil)
        self:expect("end")
        if is_expr then
            self:expect("->")
            local result = self:parse_expr()
            return self.Surf.SurfLoopExprNode(
                self.Surf.SurfLoopOverExpr(index_name, domain, carries, body, nexts, result)
            )
        end
        return self.Surf.SurfLoopStmtNode(
            self.Surf.SurfLoopOverStmt(index_name, domain, carries, body, nexts)
        )
    end

    local carries = {}
    if not self:is("while") then
        carries = self:parse_loop_carry_list(path and self:scoped(path, "carries") or nil)
    end
    self:expect("while")
    local cond = self:parse_expr()
    self:require_nl()
    local body = self:parse_stmt_block({ next = true }, path and self:scoped(path, "body") or nil)
    self:expect("next")
    self:require_nl()
    local nexts = self:parse_loop_next_block(path and self:scoped(path, "next") or nil)
    self:expect("end")
    if is_expr then
        self:expect("->")
        local result = self:parse_expr()
        return self.Surf.SurfLoopExprNode(
            self.Surf.SurfLoopWhileExpr(carries, cond, body, nexts, result)
        )
    end
    return self.Surf.SurfLoopStmtNode(
        self.Surf.SurfLoopWhileStmt(carries, cond, body, nexts)
    )
end

function Parser:parse_block_expr()
    self:expect("do")
    self:require_nl()
    local stmts, result = self:parse_expr_block({ ["end"] = true })
    self:expect("end")
    return self.Surf.SurfBlockExpr(stmts, result)
end

function Parser:parse_array_lit()
    self:expect("[")
    self:expect("]")
    local elem_ty = self:parse_type()
    local elems = self:parse_braced_entries(function() return self:parse_expr() end)
    return self.Surf.SurfArrayLit(elem_ty, elems)
end

function Parser:parse_postfix(expr)
    while true do
        if self:consume("(") then
            local args = {}
            if not self:is(")") then
                repeat
                    args[#args + 1] = self:parse_expr()
                until not self:consume(",")
            end
            self:expect(")")
            expr = self.Surf.SurfCall(expr, args)
        elseif self:consume(".") then
            expr = self.Surf.SurfExprDot(expr, self:expect("ident", "expected field name").raw)
        elseif self:consume("[") then
            local index = self:parse_expr()
            self:expect("]")
            expr = self.Surf.SurfIndex(expr, index)
        else
            return expr
        end
    end
end

function Parser:parse_prefix_expr()
    local tok = self:peek()
    local kind = tok.kind

    if kind == "int" then
        self:bump()
        return self.Surf.SurfInt(tok.raw)
    end
    if kind == "float" then
        self:bump()
        return self.Surf.SurfFloat(tok.raw)
    end
    if kind == "true" then
        self:bump()
        return self.Surf.SurfBool(true)
    end
    if kind == "false" then
        self:bump()
        return self.Surf.SurfBool(false)
    end
    if kind == "nil" then
        self:bump()
        return self.Surf.SurfNil
    end
    if kind == "ident" then
        return self:parse_postfix(self:parse_intrinsic_or_ref(self:bump()))
    end
    if kind == "[" then
        return self:parse_array_lit()
    end
    if kind == "(" then
        self:bump()
        local expr = self:parse_expr()
        self:expect(")")
        return self:parse_postfix(expr)
    end
    if kind == "-" then
        self:bump()
        return self.Surf.SurfExprNeg(self:parse_expr_bp(PREFIX_BP))
    end
    if kind == "not" then
        self:bump()
        return self.Surf.SurfExprNot(self:parse_expr_bp(PREFIX_BP))
    end
    if kind == "~" then
        self:bump()
        return self.Surf.SurfExprBNot(self:parse_expr_bp(PREFIX_BP))
    end
    if kind == "*" then
        self:bump()
        return self.Surf.SurfExprDeref(self:parse_expr_bp(PREFIX_BP))
    end
    if kind == "&" then
        self:bump()
        local expr = self:parse_expr_bp(PREFIX_BP)
        local place = self:expr_to_place(expr)
        if place == nil then
            parse_error(tok, "address-of requires an assignable place")
        end
        return self.Surf.SurfExprRef(place)
    end
    if kind == "if" then
        return self:parse_if_expr()
    end
    if kind == "switch" then
        return self:parse_switch_expr()
    end
    if kind == "loop" then
        return self:parse_loop(true)
    end
    if kind == "do" then
        return self:parse_block_expr()
    end
    if kind == "cast" or kind == "trunc" or kind == "zext" or kind == "sext" or kind == "bitcast" or kind == "satcast" then
        return self:parse_cast_expr(kind)
    end
    parse_error(tok, "expected expression")
end

function Parser:parse_expr_bp(min_bp)
    local lhs = self:parse_prefix_expr()
    while true do
        local info = INFIX[self:kind()]
        if info == nil or info[1] < min_bp then
            return lhs
        end
        self:bump()
        local rhs = self:parse_expr_bp(info[2])
        lhs = self.Surf[info[3]](lhs, rhs)
    end
end

function Parser:parse_expr()
    return self:parse_expr_bp(0)
end

function Parser:return_is_void()
    local k = self:kind()
    return k == "nl" or k == "eof" or k == "end" or k == "else" or k == "elseif"
        or k == "case" or k == "default" or k == "next"
end

function Parser:parse_if_stmt_after_cond(cond, path)
    self:expect("then")
    self:require_nl()
    local then_body = self:parse_stmt_block({ ["elseif"] = true, ["else"] = true, ["end"] = true }, path and self:scoped(path, "then") or nil)
    if self:consume("elseif") then
        local else_if = self:parse_if_stmt_after_cond(self:parse_expr(), path and self:scoped(path, "elseif") or nil)
        return self.Surf.SurfIf(cond, then_body, { else_if })
    end
    local else_body = {}
    if self:consume("else") then
        self:require_nl()
        else_body = self:parse_stmt_block({ ["end"] = true }, path and self:scoped(path, "else") or nil)
    end
    self:expect("end")
    return self.Surf.SurfIf(cond, then_body, else_body)
end

function Parser:parse_stmt(path)
    local first = self:peek()
    local kind = first.kind
    local stmt

    if kind == "let" then
        self:bump()
        local name = self:expect("ident", "expected let binding name").raw
        self:expect(":")
        local ty = self:parse_type()
        self:expect("=")
        stmt = self.Surf.SurfLet(name, ty, self:parse_expr())
    elseif kind == "var" then
        self:bump()
        local name = self:expect("ident", "expected var binding name").raw
        self:expect(":")
        local ty = self:parse_type()
        self:expect("=")
        stmt = self.Surf.SurfVar(name, ty, self:parse_expr())
    elseif kind == "return" then
        self:bump()
        if self:return_is_void() then
            stmt = self.Surf.SurfReturnVoid
        else
            stmt = self.Surf.SurfReturnValue(self:parse_expr())
        end
    elseif kind == "break" then
        self:bump()
        if self:return_is_void() then
            stmt = self.Surf.SurfBreak
        else
            stmt = self.Surf.SurfBreakValue(self:parse_expr())
        end
    elseif kind == "continue" then
        self:bump()
        stmt = self.Surf.SurfContinue
    elseif kind == "if" then
        self:bump()
        stmt = self:parse_if_stmt_after_cond(self:parse_expr(), path)
    elseif kind == "switch" then
        stmt = self:parse_switch_stmt(path)
    elseif kind == "loop" then
        stmt = self:parse_loop(false, path)
    else
        local lhs = self:parse_expr()
        if self:consume("=") then
            local place = self:expr_to_place(lhs)
            if place == nil then
                parse_error(first, "left-hand side is not assignable")
            end
            stmt = self.Surf.SurfSet(place, self:parse_expr())
        else
            stmt = self.Surf.SurfExprStmt(lhs)
        end
    end

    self:record_span(path, first)
    return stmt
end

function Parser:parse_stmt_block(terminators, base_path)
    local out = {}
    local i = 0
    self:skip_nl()
    while not terminators[self:kind()] do
        if self:is("eof") then
            parse_error(self:peek(), "unexpected end of input inside block")
        end
        i = i + 1
        out[#out + 1] = self:parse_stmt(base_path and self:scoped(base_path, "stmt." .. i) or nil)
        if self:consume("nl") then
            self:skip_nl()
        elseif not terminators[self:kind()] then
            parse_error(self:peek(), "expected newline or block terminator")
        end
    end
    return out
end

function Parser:parse_param_list(base_path)
    local params = {}
    local i = 0
    if not self:is(")") then
        repeat
            i = i + 1
            local first = self:peek()
            local name = self:expect("ident", "expected parameter name").raw
            self:expect(":")
            params[#params + 1] = self.Surf.SurfParam(name, self:parse_type())
            self:record_span(base_path and self:scoped(base_path, tostring(i)) or nil, first)
        until not self:consume(",")
    end
    return params
end

function Parser:parse_result_type_or_void()
    if self:consume("->") then
        return self:parse_type()
    end
    return self.Surf.SurfTVoid
end

function Parser:parse_func_item(item_path)
    local first = self:peek()
    self:expect("func")
    local name = self:expect("ident", "expected function name").raw
    local func_path = "func." .. name
    self:expect("(")
    local params = self:parse_param_list(self:scoped(func_path, "param"))
    self:expect(")")
    local result = self:parse_result_type_or_void()
    self:require_nl()
    local body = self:parse_stmt_block({ ["end"] = true }, func_path)
    self:expect("end")
    self:record_span(item_path, first)
    self:record_span(func_path, first)
    return self.Surf.SurfItemFunc(self.Surf.SurfFunc(name, params, result, body))
end

function Parser:parse_extern_item(item_path)
    local first = self:peek()
    self:expect("extern")
    self:expect("func")
    local name = self:expect("ident", "expected extern function name").raw
    local func_path = "extern." .. name
    self:expect("(")
    local params = self:parse_param_list(self:scoped(func_path, "param"))
    self:expect(")")
    local result = self:parse_result_type_or_void()
    self:record_span(item_path, first)
    self:record_span(func_path, first)
    return self.Surf.SurfItemExtern(self.Surf.SurfExternFunc(name, name, params, result))
end

function Parser:parse_const_item(item_path)
    local first = self:peek()
    self:expect("const")
    local name = self:expect("ident", "expected const name").raw
    self:expect(":")
    local ty = self:parse_type()
    self:expect("=")
    self:record_span(item_path, first)
    self:record_span("const." .. name, first)
    return self.Surf.SurfItemConst(self.Surf.SurfConst(name, ty, self:parse_expr()))
end

function Parser:parse_static_item(item_path)
    local first = self:peek()
    self:expect("static")
    local name = self:expect("ident", "expected static name").raw
    self:expect(":")
    local ty = self:parse_type()
    self:expect("=")
    self:record_span(item_path, first)
    self:record_span("static." .. name, first)
    return self.Surf.SurfItemStatic(self.Surf.SurfStatic(name, ty, self:parse_expr()))
end

function Parser:parse_type_item(item_path)
    local first = self:peek()
    self:expect("type")
    local name = self:expect("ident", "expected type name").raw
    self:expect("=")
    self:expect("struct")
    local fields = self:parse_braced_entries(function() return self:parse_field_decl() end)
    self:record_span(item_path, first)
    self:record_span("type." .. name, first)
    return self.Surf.SurfItemType(self.Surf.SurfStruct(name, fields))
end

function Parser:parse_import_item(item_path)
    local first = self:peek()
    self:expect("import")
    local path, parts = self:parse_path()
    local module_name = table.concat(parts, ".")
    self:record_span(item_path, first)
    self:record_span("import." .. module_name, first)
    return self.Surf.SurfItemImport(self.Surf.SurfImport(path))
end

function Parser:parse_item(item_path)
    local kind = self:kind()
    if kind == "func" then return self:parse_func_item(item_path) end
    if kind == "extern" then return self:parse_extern_item(item_path) end
    if kind == "const" then return self:parse_const_item(item_path) end
    if kind == "static" then return self:parse_static_item(item_path) end
    if kind == "import" then return self:parse_import_item(item_path) end
    if kind == "type" then return self:parse_type_item(item_path) end
    parse_error(self:peek(), "expected top-level item")
end

function Parser:finish(kind_name, value)
    self:skip_nl()
    self:expect("eof", "expected end of input after " .. kind_name)
    return value
end

function M.Define(T)
    local Surf = T.MoonliftSurface

    local function new_parser(text, span_index)
        return Parser.new(Surf, Lexer.lex(text), span_index)
    end

    local function parse_module_with_spans(text)
        local spans = Spans.new(text)
        local p = new_parser(text, spans)
        local items = {}
        local first = p:peek()
        local item_i = 0
        p:skip_nl()
        while not p:is("eof") do
            item_i = item_i + 1
            items[#items + 1] = p:parse_item("item." .. item_i)
            if p:consume("nl") then
                p:skip_nl()
            elseif not p:is("eof") then
                parse_error(p:peek(), "expected newline or end of input after item")
            end
        end
        local module = Surf.SurfModule(items)
        Spans.record(spans, "module", first, p:last(), "module")
        return module, spans
    end

    local function parse_item_with_spans(text)
        local spans = Spans.new(text)
        local p = new_parser(text, spans)
        local first = p:peek()
        local item = p:finish("item", p:parse_item("item"))
        Spans.record(spans, "item", first, p:last(), "item")
        return item, spans
    end

    local function parse_expr_with_spans(text)
        local spans = Spans.new(text)
        local p = new_parser(text, spans)
        local first = p:peek()
        local expr = p:finish("expression", p:parse_expr())
        Spans.record(spans, "expr", first, p:last(), "expr")
        return expr, spans
    end

    local function parse_stmt_with_spans(text)
        local spans = Spans.new(text)
        local p = new_parser(text, spans)
        local first = p:peek()
        local stmt = p:finish("statement", p:parse_stmt("stmt"))
        Spans.record(spans, "stmt", first, p:last(), "stmt")
        return stmt, spans
    end

    local function parse_type_with_spans(text)
        local spans = Spans.new(text)
        local p = new_parser(text, spans)
        local first = p:peek()
        local ty = p:finish("type", p:parse_type())
        Spans.record(spans, "type", first, p:last(), "type")
        return ty, spans
    end

    local function parse_module(text)
        local value = parse_module_with_spans(text)
        return value
    end

    local function parse_item(text)
        local value = parse_item_with_spans(text)
        return value
    end

    local function parse_expr(text)
        local value = parse_expr_with_spans(text)
        return value
    end

    local function parse_stmt(text)
        local value = parse_stmt_with_spans(text)
        return value
    end

    local function parse_type(text)
        local value = parse_type_with_spans(text)
        return value
    end

    local function try_call(fn, text)
        local ok, result = xpcall(function() return fn(text) end, function(err)
            return Lexer.as_diag(err) or err
        end)
        if ok then
            return result, nil
        end
        return nil, result
    end

    return {
        lex = Lexer.lex,
        new_diag = Lexer.new_diag,
        as_diag = Lexer.as_diag,
        parse_module = parse_module,
        parse_item = parse_item,
        parse_expr = parse_expr,
        parse_stmt = parse_stmt,
        parse_type = parse_type,
        parse_module_with_spans = parse_module_with_spans,
        parse_item_with_spans = parse_item_with_spans,
        parse_expr_with_spans = parse_expr_with_spans,
        parse_stmt_with_spans = parse_stmt_with_spans,
        parse_type_with_spans = parse_type_with_spans,
        try_parse_module = function(text) return try_call(parse_module, text) end,
        try_parse_item = function(text) return try_call(parse_item, text) end,
        try_parse_expr = function(text) return try_call(parse_expr, text) end,
        try_parse_stmt = function(text) return try_call(parse_stmt, text) end,
        try_parse_type = function(text) return try_call(parse_type, text) end,
        spans = Spans,
    }
end

return M
