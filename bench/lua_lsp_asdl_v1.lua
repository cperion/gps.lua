-- bench/lua_lsp_asdl_v1.lua
--
-- First ASDL draft for a Lua + LuaLS-style semantic model.
-- Exposes:
--   local M = require("bench.lua_lsp_asdl_v1")
--   local CTX = M.context()
--   M.smoke()  -- constructor sanity check

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local pvm = require("pvm")

local M = {}

M.SCHEMA = [[
module LuaLsp {
    Pos = (number line, number character) unique
    Range = (LuaLsp.Pos start, LuaLsp.Pos stop, number start_byte, number stop_byte) unique
    Anchor = (string kind, string label, LuaLsp.Range range) unique

    Token = (string kind, string lexeme, LuaLsp.Range range) unique
    Cst = (string kind, LuaLsp.Range range, LuaLsp.Cst* children) unique
    ParseCell = (string rule, number token_index, boolean ok, number next_token, LuaLsp.Cst node) unique
    ParseForest = (LuaLsp.Cst root, LuaLsp.ParseCell* cells) unique
    Source = (string text, LuaLsp.Token* tokens, LuaLsp.ParseForest parse) unique

    File = (string uri, LuaLsp.Item* items) unique
    Document = (string uri, number version, LuaLsp.Source source, LuaLsp.File file, LuaLsp.Anchor* anchors) unique

    AnchorRef = (string id) unique

    DocEvent = DClass(string name, LuaLsp.TypeExpr* extends, LuaLsp.AnchorRef anchor) unique
             | DField(string name, LuaLsp.TypeExpr typ, boolean optional, LuaLsp.AnchorRef anchor) unique
             | DAlias(string name, LuaLsp.TypeExpr typ, LuaLsp.AnchorRef anchor) unique
             | DGeneric(string name, LuaLsp.TypeExpr* bounds, LuaLsp.AnchorRef anchor) unique
             | DType(LuaLsp.TypeExpr typ, LuaLsp.AnchorRef anchor) unique
             | DParam(string name, LuaLsp.TypeExpr typ, LuaLsp.AnchorRef anchor) unique
             | DReturn(LuaLsp.TypeExpr* values, LuaLsp.AnchorRef anchor) unique
             | DOverload(LuaLsp.FuncType sig, LuaLsp.AnchorRef anchor) unique
             | DCast(LuaLsp.TypeExpr typ, LuaLsp.AnchorRef anchor) unique
             | DMeta(string name, string text, LuaLsp.AnchorRef anchor) unique

    ScopeEvent = ScopeEnter(string scope, LuaLsp.AnchorRef anchor) unique
               | ScopeExit(string scope, LuaLsp.AnchorRef anchor) unique
               | ScopeDeclLocal(string decl_kind, string name, LuaLsp.AnchorRef anchor) unique
               | ScopeDeclGlobal(string name, LuaLsp.AnchorRef anchor) unique
               | ScopeRef(string name, LuaLsp.AnchorRef anchor) unique
               | ScopeWrite(string name, LuaLsp.AnchorRef anchor) unique
    ScopeEventList = (LuaLsp.ScopeEvent* items) unique

    ScopeLocalState = (string name, string decl_kind, number used, LuaLsp.AnchorRef anchor) unique
    ScopeDiagFrame = (string scope, LuaLsp.ScopeLocalState* locals) unique

    ScopeSymbolBinding = (string name, LuaLsp.Symbol symbol) unique
    ScopeSymbolFrame = (string scope, string id, LuaLsp.ScopeSymbolBinding* locals) unique

    TypeClassField = (string name, LuaLsp.TypeExpr typ, boolean optional, LuaLsp.AnchorRef anchor) unique
    TypeClass = (string name, LuaLsp.TypeExpr* extends, LuaLsp.TypeClassField* fields, LuaLsp.AnchorRef anchor) unique
    TypeAlias = (string name, LuaLsp.TypeExpr typ, LuaLsp.AnchorRef anchor) unique
    TypeGeneric = (string name, LuaLsp.TypeExpr* bounds, LuaLsp.AnchorRef anchor) unique
    TypeEnv = (LuaLsp.TypeClass* classes, LuaLsp.TypeAlias* aliases, LuaLsp.TypeGeneric* generics) unique

    Symbol = (string id, string kind, string name, string scope, string scope_id, LuaLsp.AnchorRef decl_anchor) unique
    Occurrence = (string symbol_id, string name, string kind, LuaLsp.AnchorRef anchor) unique
    OccurrenceList = (LuaLsp.Occurrence* items) unique
    Unresolved = (string name, LuaLsp.AnchorRef anchor) unique
    SymbolIndex = (LuaLsp.Symbol* symbols, LuaLsp.Occurrence* defs, LuaLsp.Occurrence* uses, LuaLsp.Unresolved* unresolved) unique

    AnchorBinding = AnchorSymbol(LuaLsp.Symbol symbol, string role) unique
                  | AnchorUnresolved(string name) unique
                  | AnchorMissing

    TypeTarget = TypeClassTarget(string name, LuaLsp.AnchorRef anchor, LuaLsp.TypeClass value) unique
               | TypeAliasTarget(string name, LuaLsp.AnchorRef anchor, LuaLsp.TypeAlias value) unique
               | TypeGenericTarget(string name, LuaLsp.AnchorRef anchor, LuaLsp.TypeGeneric value) unique
               | TypeBuiltinTarget(string name) unique
               | TypeTargetMissing

    DefinitionMeta = DefMetaSymbol(string role, LuaLsp.Symbol symbol, LuaLsp.Occurrence* defs) unique
                   | DefMetaType(LuaLsp.TypeTarget target) unique
                   | DefMetaUnresolved(string name) unique
                   | DefMetaMissing

    DefinitionResult = DefHit(LuaLsp.AnchorRef anchor, LuaLsp.DefinitionMeta meta) unique
                     | DefMiss(LuaLsp.DefinitionMeta meta) unique

    ReferenceResult = (LuaLsp.Occurrence* refs) unique

    HoverInfo = HoverSymbol(string role, string name, string symbol_kind, string scope, number defs, number uses) unique
              | HoverType(string name, string detail, number fields) unique
              | HoverUnresolved(string name, string detail) unique
              | HoverMissing

    QuerySubject = QueryAnchor(LuaLsp.AnchorRef anchor) unique
                 | QueryTypeName(string name) unique
                 | QueryMissing

    SymbolIdQuery = (LuaLsp.File file, string symbol_id) unique
    SubjectQuery = (LuaLsp.File file, LuaLsp.QuerySubject subject) unique
    RefQuery = (LuaLsp.File file, LuaLsp.QuerySubject subject, boolean include_declaration) unique
    TypeNameQuery = (LuaLsp.File file, string name) unique

    LspPos = (number line, number character) unique
    LspRange = (LuaLsp.LspPos start, LuaLsp.LspPos stop) unique
    LspRangeQuery = (LuaLsp.File file, LuaLsp.AnchorRef anchor) unique

    ServerAnchorPoint = (LuaLsp.AnchorRef anchor, LuaLsp.LspRange range, string label) unique
    ServerMeta = (LuaLsp.ServerAnchorPoint* positions, string parse_error) unique
    ServerDoc = (string uri, number version, string text, LuaLsp.File file, LuaLsp.ServerMeta meta) unique
    ServerDocStore = (LuaLsp.ServerDoc* docs) unique
    ServerDocQuery = (LuaLsp.ServerDocStore store, string uri) unique
    ServerDocLookup = ServerDocHit(LuaLsp.ServerDoc doc) unique
                    | ServerDocMiss

    LspDocIdentifier = (string uri) unique
    LspDocItem = (string uri, number version, string text) unique
    LspVersionedDoc = (string uri, number version) unique
    LspTextChange = (string text) unique
    LspReferenceContext = (boolean include_declaration) unique

    LspRequest = ReqDidOpen(LuaLsp.LspDocItem doc) unique
               | ReqDidChange(LuaLsp.LspVersionedDoc doc, LuaLsp.LspTextChange* changes) unique
               | ReqDidClose(LuaLsp.LspDocIdentifier doc) unique
               | ReqHover(LuaLsp.LspDocIdentifier doc, LuaLsp.LspPos position, LuaLsp.QuerySubject subject) unique
               | ReqDefinition(LuaLsp.LspDocIdentifier doc, LuaLsp.LspPos position, LuaLsp.QuerySubject subject) unique
               | ReqReferences(LuaLsp.LspDocIdentifier doc, LuaLsp.LspPos position, LuaLsp.QuerySubject subject, LuaLsp.LspReferenceContext context) unique
               | ReqDocumentHighlight(LuaLsp.LspDocIdentifier doc, LuaLsp.LspPos position, LuaLsp.QuerySubject subject) unique
               | ReqDiagnostic(LuaLsp.LspDocIdentifier doc) unique
               | ReqInvalid(string reason) unique

    AnchorEntry = (LuaLsp.AnchorRef anchor, string kind, string name, LuaLsp.LspRange range) unique
    AnchorEntryList = (LuaLsp.AnchorEntry* items) unique
    LspPositionQuery = (LuaLsp.File file, LuaLsp.LspPos position, string prefer_kind) unique
    AnchorPick = AnchorPickHit(LuaLsp.AnchorRef anchor, LuaLsp.AnchorEntry entry) unique
              | AnchorPickMiss

    LspLocation = (string uri, LuaLsp.LspRange range) unique
    LspLocationList = (LuaLsp.LspLocation* items) unique

    LspDiagnosticProviderInfo = (boolean inter_file_dependencies, boolean workspace_diagnostics) unique
    LspCapabilities = (number text_document_sync, boolean hover_provider, boolean definition_provider, boolean references_provider, boolean document_highlight_provider, LuaLsp.LspDiagnosticProviderInfo diagnostic_provider) unique
    LspServerInfo = (string name, string version) unique
    LspInitializeResult = (LuaLsp.LspCapabilities capabilities, LuaLsp.LspServerInfo server_info) unique

    LspDiagnostic = (LuaLsp.LspRange range, number severity, string source, string code, string message) unique
    LspDiagnosticList = (LuaLsp.LspDiagnostic* items) unique
    LspDiagnosticReport = (string kind, LuaLsp.LspDiagnostic* items, string uri, number version) unique

    LspMarkupContent = (string kind, string value) unique
    LspHover = (LuaLsp.LspMarkupContent contents, LuaLsp.LspRange range) unique
    LspHoverResult = LspHoverHit(LuaLsp.LspHover value) unique
                   | LspHoverMiss

    LspDocumentHighlight = (LuaLsp.LspRange range, number kind) unique
    LspDocumentHighlightList = (LuaLsp.LspDocumentHighlight* items) unique

    LspAnchorQuery = (LuaLsp.File file, LuaLsp.AnchorRef anchor, boolean include_declaration) unique

    RpcId = RpcIdNumber(number value) unique
          | RpcIdString(string value) unique
          | RpcIdNull

    RpcPayload = PayloadNull
               | PayloadInitialize(LuaLsp.LspInitializeResult value) unique
               | PayloadDiagnosticReport(LuaLsp.LspDiagnosticReport value) unique
               | PayloadHoverResult(LuaLsp.LspHoverResult value) unique
               | PayloadLocationList(LuaLsp.LspLocationList value) unique
               | PayloadDocumentHighlightList(LuaLsp.LspDocumentHighlightList value) unique
               | PayloadPublishDiagnostics(LuaLsp.LspDiagnosticReport value) unique

    RpcIncoming = RpcInInitialize(LuaLsp.RpcId id) unique
                | RpcInInitialized
                | RpcInShutdown(LuaLsp.RpcId id) unique
                | RpcInExit
                | RpcInIgnore(string method) unique
                | RpcInLspRequest(LuaLsp.RpcId id, LuaLsp.LspRequest request) unique
                | RpcInLspNotification(LuaLsp.LspRequest request) unique
                | RpcInInvalid(string reason) unique

    RpcOutgoing = RpcOutResult(LuaLsp.RpcId id, LuaLsp.RpcPayload payload) unique
                | RpcOutError(LuaLsp.RpcId id, number code, string message, string data) unique
                | RpcOutNotification(string method, LuaLsp.RpcPayload payload) unique
                | RpcOutNone

    Diagnostic = (string code, string message, string name, string scope, LuaLsp.AnchorRef anchor) unique
    DiagnosticSet = (LuaLsp.Diagnostic* items) unique

    Item = (LuaLsp.DocBlock* docs, LuaLsp.Stmt stmt) unique

    Block = (LuaLsp.Item* items) unique
    CondBlock = (LuaLsp.Expr cond, LuaLsp.Block body) unique
    Name = (string value) unique

    Stmt = LocalAssign(LuaLsp.Name* names, LuaLsp.Expr* values) unique
         | Assign(LuaLsp.LValue* lhs, LuaLsp.Expr* rhs) unique
         | LocalFunction(string name, LuaLsp.FuncBody body) unique
         | Function(LuaLsp.LValue name, LuaLsp.FuncBody body) unique
         | Return(LuaLsp.Expr* values) unique
         | CallStmt(LuaLsp.Expr callee, LuaLsp.Expr* args) unique
         | If(LuaLsp.CondBlock* arms, LuaLsp.Block else_block) unique
         | While(LuaLsp.Expr cond, LuaLsp.Block body) unique
         | Repeat(LuaLsp.Block body, LuaLsp.Expr cond) unique
         | ForNum(string name, LuaLsp.Expr init, LuaLsp.Expr limit, LuaLsp.Expr step, LuaLsp.Block body) unique
         | ForIn(LuaLsp.Name* names, LuaLsp.Expr* iter, LuaLsp.Block body) unique
         | Do(LuaLsp.Block body) unique
         | Break
         | Goto(string label) unique
         | Label(string label) unique

    LValue = LName(string name) unique
           | LField(LuaLsp.Expr base, string key) unique
           | LIndex(LuaLsp.Expr base, LuaLsp.Expr key) unique

    Expr = Nil
         | Bool(boolean value) unique
         | Number(string lexeme) unique
         | String(string value) unique
         | Vararg
         | NameRef(string name) unique
         | Field(LuaLsp.Expr base, string key) unique
         | Index(LuaLsp.Expr base, LuaLsp.Expr key) unique
         | Call(LuaLsp.Expr callee, LuaLsp.Expr* args) unique
         | MethodCall(LuaLsp.Expr recv, string method, LuaLsp.Expr* args) unique
         | FunctionExpr(LuaLsp.FuncBody body) unique
         | TableCtor(LuaLsp.TableField* fields) unique
         | Unary(string op, LuaLsp.Expr value) unique
         | Binary(string op, LuaLsp.Expr lhs, LuaLsp.Expr rhs) unique
         | Paren(LuaLsp.Expr inner) unique

    TableField = ArrayField(LuaLsp.Expr value) unique
               | PairField(LuaLsp.Expr key, LuaLsp.Expr value) unique
               | NameField(string key, LuaLsp.Expr value) unique

    FuncBody = (LuaLsp.Param* params, boolean vararg, LuaLsp.Block body) unique
    Param = PName(string name) unique

    DocBlock = (LuaLsp.DocTag* tags) unique
    DocTag = ClassTag(string name, LuaLsp.TypeExpr* extends) unique
           | FieldTag(string name, LuaLsp.TypeExpr typ, boolean optional) unique
           | ParamTag(string name, LuaLsp.TypeExpr typ) unique
           | ReturnTag(LuaLsp.TypeExpr* values) unique
           | TypeTag(LuaLsp.TypeExpr typ) unique
           | AliasTag(string name, LuaLsp.TypeExpr typ) unique
           | GenericTag(string name, LuaLsp.TypeExpr* bounds) unique
           | OverloadTag(LuaLsp.FuncType sig) unique
           | CastTag(LuaLsp.TypeExpr typ) unique
           | MetaTag(string name, string text) unique

    TypeExpr = Any
             | Unknown
             | TNil
             | TBoolean
             | TNumber
             | TString
             | TNamed(string name) unique
             | TLiteralString(string value) unique
             | TLiteralNumber(string value) unique
             | TUnion(LuaLsp.TypeExpr* parts) unique
             | TIntersect(LuaLsp.TypeExpr* parts) unique
             | TArray(LuaLsp.TypeExpr item) unique
             | TMap(LuaLsp.TypeExpr key, LuaLsp.TypeExpr value) unique
             | TTuple(LuaLsp.TypeExpr* items) unique
             | TFunc(LuaLsp.FuncType sig) unique
             | TTable(LuaLsp.TypeField* fields, boolean open) unique
             | TGeneric(string name) unique
             | TOptional(LuaLsp.TypeExpr inner) unique
             | TVararg(LuaLsp.TypeExpr inner) unique
             | TParen(LuaLsp.TypeExpr inner) unique

    TypeField = (string name, LuaLsp.TypeExpr typ, boolean optional) unique
    FuncType = (LuaLsp.TypeExpr* params, LuaLsp.TypeExpr* returns, boolean vararg) unique
}
]]

function M.context()
    return pvm.context():Define(M.SCHEMA)
end

function M.smoke()
    local C = M.context().LuaLsp

    local t_number = C.TNumber()
    local t_string = C.TString()
    local t_union = C.TUnion({ t_number, t_string })

    local tags = {
        C.ClassTag("User", {}),
        C.FieldTag("id", t_number, false),
        C.FieldTag("name", t_string, false),
        C.ParamTag("x", t_union),
        C.ReturnTag({ t_string }),
    }

    local docs = C.DocBlock(tags)
    local stmt = C.LocalAssign({ C.Name("x") }, { C.Number("42") })
    local item = C.Item({ docs }, stmt)
    local file = C.File("file:///demo.lua", { item })

    local p0 = C.Pos(0, 0)
    local p1 = C.Pos(0, 10)
    local r = C.Range(p0, p1, 0, 10)
    local tok = C.Token("identifier", "x", r)
    local cst = C.Cst("chunk", r, {})
    local parse = C.ParseForest(cst, {})
    local src = C.Source("local x=42", { tok }, parse)
    local anchor = C.Anchor("decl", "x", r)
    local doc = C.Document("file:///demo.lua", 1, src, file, { anchor })

    assert(file.uri == "file:///demo.lua")
    assert(file.items[1].docs[1].tags[1].kind == "ClassTag")
    assert(file.items[1].stmt.kind == "LocalAssign")
    assert(doc.file == file)
    assert(doc.source.parse.root.kind == "chunk")

    return doc
end

return M
