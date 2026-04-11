-- lsp/asdl.lua
--
-- ASDL schema for the Lua LSP.
--
-- KEY DESIGN RULES:
--   1. AST nodes carry NO position → maximum ASDL interning
--   2. Every feature is an ASDL type flowing through a pvm boundary
--   3. Inferred types ARE TypeExpr — one type language, doc and inference unified
--
-- Clusters:
--   Source:    SourceFile, Token, AnchorRef
--   AST:       File, Item, Block, Stmt, Expr, LValue, FuncBody (no Range)
--   Doc:       DocBlock, DocTag, TypeExpr, FuncType (no Range)
--   Semantic:  ScopeEvent, Symbol, Occurrence, TypeEnv, Diagnostic
--   TypeInfer: TypedSymbol, TypedIndex, ExprType — pvm.lower per file
--   Complete:  CompletionItem, CompletionList — pvm.lower per query
--   DocSymbol: DocSymbol, DocSymbolList — pvm.phase per file
--   SigHelp:   ParamLabel, SignatureInfo, SignatureHelp — pvm.lower per query
--   Rename:    RenameEdit, RenameResult — pvm.lower per query
--   LSP/RPC:   everything else

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local pvm = require("pvm")

local M = {}

M.SCHEMA = [[
module Lua {

    SourceFile = (string uri, string text) unique
    Token = (string kind, string value) unique
    AnchorRef = (string id) unique

    NameOcc = OccDecl(string decl_kind, string name) unique
            | OccRef(string name) unique
            | OccWrite(string name) unique
            | OccScopeEnter(string scope) unique
            | OccScopeExit(string scope) unique

    File  = (string uri, Lua.Item* items) unique
    Item  = (Lua.DocBlock* docs, Lua.Stmt stmt) unique
    Block = (Lua.Item* items) unique

    CondBlock = (Lua.Expr cond, Lua.Block body) unique
    Name      = (string value) unique

    Stmt = LocalAssign(Lua.Name* names, Lua.Expr* values) unique
         | Assign(Lua.LValue* lhs, Lua.Expr* rhs) unique
         | LocalFunction(string name, Lua.FuncBody body) unique
         | Function(Lua.LValue name, Lua.FuncBody body) unique
         | Return(Lua.Expr* values) unique
         | CallStmt(Lua.Expr callee, Lua.Expr* args) unique
         | If(Lua.CondBlock* arms, Lua.Block else_block) unique
         | While(Lua.Expr cond, Lua.Block body) unique
         | Repeat(Lua.Block body, Lua.Expr cond) unique
         | ForNum(string name, Lua.Expr init, Lua.Expr limit, Lua.Expr step, Lua.Block body) unique
         | ForIn(Lua.Name* names, Lua.Expr* iter, Lua.Block body) unique
         | Do(Lua.Block body) unique
         | Break
         | Goto(string label) unique
         | Label(string label) unique

    LValue = LName(string name) unique
           | LField(Lua.Expr base, string key) unique
           | LIndex(Lua.Expr base, Lua.Expr key) unique
           | LMethod(Lua.Expr base, string method) unique

    Expr = Nil
         | True
         | False
         | Number(string value) unique
         | String(string value) unique
         | Vararg
         | NameRef(string name) unique
         | Field(Lua.Expr base, string key) unique
         | Index(Lua.Expr base, Lua.Expr key) unique
         | Call(Lua.Expr callee, Lua.Expr* args) unique
         | MethodCall(Lua.Expr recv, string method, Lua.Expr* args) unique
         | FunctionExpr(Lua.FuncBody body) unique
         | TableCtor(Lua.TableField* fields) unique
         | Unary(string op, Lua.Expr value) unique
         | Binary(string op, Lua.Expr lhs, Lua.Expr rhs) unique
         | Paren(Lua.Expr inner) unique

    TableField = ArrayField(Lua.Expr value) unique
               | PairField(Lua.Expr key, Lua.Expr value) unique
               | NameField(string key, Lua.Expr value) unique

    FuncBody = (Lua.Param* params, boolean vararg, Lua.Block body) unique
    Param    = PName(string name) unique

    DocBlock = (Lua.DocTag* tags) unique

    DocTag = ClassTag(string name, Lua.TypeExpr* extends) unique
           | FieldTag(string name, Lua.TypeExpr typ, boolean optional) unique
           | ParamTag(string name, Lua.TypeExpr typ) unique
           | ReturnTag(Lua.TypeExpr* values) unique
           | TypeTag(Lua.TypeExpr typ) unique
           | AliasTag(string name, Lua.TypeExpr typ) unique
           | GenericTag(string name, Lua.TypeExpr* bounds) unique
           | OverloadTag(Lua.FuncType sig) unique
           | CastTag(Lua.TypeExpr typ) unique
           | MetaTag(string name, string text) unique

    TypeExpr = TAny
             | TUnknown
             | TNil
             | TBoolean
             | TNumber
             | TString
             | TNamed(string name) unique
             | TLiteralString(string value) unique
             | TLiteralNumber(string value) unique
             | TUnion(Lua.TypeExpr* parts) unique
             | TIntersect(Lua.TypeExpr* parts) unique
             | TArray(Lua.TypeExpr item) unique
             | TMap(Lua.TypeExpr key, Lua.TypeExpr value) unique
             | TTuple(Lua.TypeExpr* items) unique
             | TFunc(Lua.FuncType sig) unique
             | TTable(Lua.TypeField* fields, boolean open) unique
             | TGeneric(string name) unique
             | TOptional(Lua.TypeExpr inner) unique
             | TVararg(Lua.TypeExpr inner) unique
             | TParen(Lua.TypeExpr inner) unique

    TypeField = (string name, Lua.TypeExpr typ, boolean optional) unique
    FuncType  = (Lua.TypeExpr* params, Lua.TypeExpr* returns, boolean vararg) unique

    DocEvent = DClass(string name, Lua.TypeExpr* extends, Lua.AnchorRef anchor) unique
             | DField(string name, Lua.TypeExpr typ, boolean optional, Lua.AnchorRef anchor) unique
             | DAlias(string name, Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
             | DGeneric(string name, Lua.TypeExpr* bounds, Lua.AnchorRef anchor) unique
             | DType(Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
             | DParam(string name, Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
             | DReturn(Lua.TypeExpr* values, Lua.AnchorRef anchor) unique
             | DOverload(Lua.FuncType sig, Lua.AnchorRef anchor) unique
             | DCast(Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
             | DMeta(string name, string text, Lua.AnchorRef anchor) unique

    ScopeEvent = ScopeEnter(string scope, Lua.AnchorRef anchor) unique
               | ScopeExit(string scope, Lua.AnchorRef anchor) unique
               | ScopeDeclLocal(string decl_kind, string name, Lua.AnchorRef anchor) unique
               | ScopeDeclGlobal(string name, Lua.AnchorRef anchor) unique
               | ScopeRef(string name, Lua.AnchorRef anchor) unique
               | ScopeWrite(string name, Lua.AnchorRef anchor) unique
    ScopeEventList = (Lua.ScopeEvent* items) unique

    ScopeLocalState = (string name, string decl_kind, number used, Lua.AnchorRef anchor) unique
    ScopeDiagFrame  = (string scope, Lua.ScopeLocalState* locals) unique

    ScopeSymbolBinding = (string name, Lua.Symbol symbol) unique
    ScopeSymbolFrame   = (string scope, string id, Lua.ScopeSymbolBinding* locals) unique

    TypeClassField = (string name, Lua.TypeExpr typ, boolean optional, Lua.AnchorRef anchor) unique
    TypeClass  = (string name, Lua.TypeExpr* extends, Lua.TypeClassField* fields, Lua.AnchorRef anchor) unique
    TypeAlias  = (string name, Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
    TypeGeneric = (string name, Lua.TypeExpr* bounds, Lua.AnchorRef anchor) unique
    TypeEnv    = (Lua.TypeClass* classes, Lua.TypeAlias* aliases, Lua.TypeGeneric* generics) unique

    Symbol     = (string id, string kind, string name, string scope, string scope_id, Lua.AnchorRef decl_anchor) unique
    Occurrence = (string symbol_id, string name, string kind, Lua.AnchorRef anchor) unique
    OccurrenceList = (Lua.Occurrence* items) unique
    Unresolved = (string name, Lua.AnchorRef anchor) unique
    SymbolIndex = (Lua.Symbol* symbols, Lua.Occurrence* defs, Lua.Occurrence* uses, Lua.Unresolved* unresolved) unique

    AnchorBinding = AnchorSymbol(Lua.Symbol symbol, string role) unique
                  | AnchorUnresolved(string name) unique
                  | AnchorMissing

    TypeTarget = TypeClassTarget(string name, Lua.AnchorRef anchor, Lua.TypeClass value) unique
               | TypeAliasTarget(string name, Lua.AnchorRef anchor, Lua.TypeAlias value) unique
               | TypeGenericTarget(string name, Lua.AnchorRef anchor, Lua.TypeGeneric value) unique
               | TypeBuiltinTarget(string name) unique
               | TypeTargetMissing

    DefinitionMeta = DefMetaSymbol(string role, Lua.Symbol symbol, Lua.Occurrence* defs) unique
                   | DefMetaType(Lua.TypeTarget target) unique
                   | DefMetaUnresolved(string name) unique
                   | DefMetaMissing

    DefinitionResult = DefHit(Lua.AnchorRef anchor, Lua.DefinitionMeta meta) unique
                     | DefMiss(Lua.DefinitionMeta meta) unique

    ReferenceResult = (Lua.Occurrence* refs) unique

    HoverInfo = HoverSymbol(string role, string name, string symbol_kind, string scope, number defs, number uses, Lua.TypeExpr typ) unique
              | HoverType(string name, string detail, number fields) unique
              | HoverUnresolved(string name, string detail) unique
              | HoverMissing

    QuerySubject = QueryAnchor(Lua.AnchorRef anchor) unique
                 | QueryTypeName(string name) unique
                 | QueryMissing

    SymbolIdQuery = (Lua.File file, string symbol_id) unique
    SubjectQuery  = (Lua.File file, Lua.QuerySubject subject) unique
    RefQuery      = (Lua.File file, Lua.QuerySubject subject, boolean include_declaration) unique
    TypeNameQuery = (Lua.File file, string name) unique

    Diagnostic    = (string code, string message, string name, string scope, Lua.AnchorRef anchor) unique
    DiagnosticSet = (Lua.Diagnostic* items) unique

    TypedSymbol = (Lua.Symbol symbol, Lua.TypeExpr typ) unique
    TypedIndex  = (Lua.TypedSymbol* symbols) unique

    CompletionQuery = (Lua.File file, Lua.LspPos position, string prefix) unique
    CompletionItem = (string label, number kind, string detail, string sort_text, string insert_text) unique
    CompletionList = (Lua.CompletionItem* items, boolean is_incomplete) unique

    DocSymbol     = (string name, string detail, number kind, Lua.AnchorRef anchor, Lua.DocSymbol* children) unique
    DocSymbolList = (Lua.DocSymbol* items) unique

    ParamLabel    = (string label) unique
    SignatureInfo = (string label, Lua.ParamLabel* params, number active_param) unique
    SignatureHelp = (Lua.SignatureInfo* signatures, number active_signature) unique
    SignatureQuery = (Lua.File file, Lua.LspPos position) unique

    RenameEdit   = (Lua.AnchorRef anchor, Lua.LspRange range, string new_text) unique
    RenameResult = RenameOk(Lua.RenameEdit* edits) unique
                 | RenameFail(string reason) unique
    RenameQuery  = (Lua.File file, Lua.AnchorRef anchor, string new_name) unique

    LspPos   = (number line, number character) unique
    LspRange = (Lua.LspPos start, Lua.LspPos stop) unique
    LspRangeQuery = (Lua.File file, Lua.AnchorRef anchor) unique

    ServerAnchorPoint = (Lua.AnchorRef anchor, Lua.LspRange range, string label) unique
    ServerMeta  = (Lua.ServerAnchorPoint* positions, string parse_error) unique
    ServerDoc   = (string uri, number version, string text, Lua.File file, Lua.ServerMeta meta) unique
    ServerDocStore = (Lua.ServerDoc* docs) unique
    ServerDocQuery = (Lua.ServerDocStore store, string uri) unique
    ServerDocLookup = ServerDocHit(Lua.ServerDoc doc) unique
                    | ServerDocMiss

    AnchorEntry     = (Lua.AnchorRef anchor, string kind, string name, Lua.LspRange range) unique
    AnchorEntryList = (Lua.AnchorEntry* items) unique
    LspPositionQuery = (Lua.File file, Lua.LspPos position, string prefer_kind) unique
    AnchorPick = AnchorPickHit(Lua.AnchorRef anchor, Lua.AnchorEntry entry) unique
               | AnchorPickMiss

    LspLocation     = (string uri, Lua.LspRange range) unique
    LspLocationList = (Lua.LspLocation* items) unique

    LspDiagnosticProviderInfo = (boolean inter_file_dependencies, boolean workspace_diagnostics) unique
    LspCapabilities = (number text_document_sync, boolean hover_provider, boolean definition_provider, boolean references_provider, boolean document_highlight_provider, Lua.LspDiagnosticProviderInfo diagnostic_provider, boolean completion_provider, boolean document_symbol_provider, boolean rename_provider, boolean signature_help_provider) unique
    LspServerInfo   = (string name, string version) unique
    LspInitializeResult = (Lua.LspCapabilities capabilities, Lua.LspServerInfo server_info) unique

    LspDiagnostic       = (Lua.LspRange range, number severity, string source, string code, string message) unique
    LspDiagnosticList   = (Lua.LspDiagnostic* items) unique
    LspDiagnosticReport = (string kind, Lua.LspDiagnostic* items, string uri, number version) unique

    LspMarkupContent = (string kind, string value) unique
    LspHover = (Lua.LspMarkupContent contents, Lua.LspRange range) unique
    LspHoverResult = LspHoverHit(Lua.LspHover value) unique
                   | LspHoverMiss

    LspDocumentHighlight     = (Lua.LspRange range, number kind) unique
    LspDocumentHighlightList = (Lua.LspDocumentHighlight* items) unique

    LspCompletionItem = (string label, number kind, string detail, string sort_text, string insert_text) unique
    LspCompletionList = (Lua.LspCompletionItem* items, boolean is_incomplete) unique

    LspDocumentSymbol     = (string name, string detail, number kind, Lua.LspRange range, Lua.LspRange selection_range, Lua.LspDocumentSymbol* children) unique
    LspDocumentSymbolList = (Lua.LspDocumentSymbol* items) unique

    LspSignatureInfo = (string label, Lua.LspMarkupContent documentation, Lua.LspRange* param_ranges) unique
    LspSignatureHelp = (Lua.LspSignatureInfo* signatures, number active_signature, number active_parameter) unique

    LspTextEdit     = (Lua.LspRange range, string new_text) unique
    LspWorkspaceEdit = (Lua.LspTextEdit* edits, string uri) unique

    LspDocIdentifier  = (string uri) unique
    LspDocItem        = (string uri, number version, string text) unique
    LspVersionedDoc   = (string uri, number version) unique
    LspTextChange     = (string text) unique
    LspReferenceContext = (boolean include_declaration) unique

    LspRequest = ReqDidOpen(Lua.LspDocItem doc) unique
               | ReqDidChange(Lua.LspVersionedDoc doc, Lua.LspTextChange* changes) unique
               | ReqDidClose(Lua.LspDocIdentifier doc) unique
               | ReqHover(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqDefinition(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqReferences(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject, Lua.LspReferenceContext context) unique
               | ReqDocumentHighlight(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqDiagnostic(Lua.LspDocIdentifier doc) unique
               | ReqCompletion(Lua.LspDocIdentifier doc, Lua.LspPos position) unique
               | ReqDocumentSymbol(Lua.LspDocIdentifier doc) unique
               | ReqSignatureHelp(Lua.LspDocIdentifier doc, Lua.LspPos position) unique
               | ReqRename(Lua.LspDocIdentifier doc, Lua.LspPos position, string new_name) unique
               | ReqPrepareRename(Lua.LspDocIdentifier doc, Lua.LspPos position) unique
               | ReqInvalid(string reason) unique

    LspAnchorQuery = (Lua.File file, Lua.AnchorRef anchor, boolean include_declaration) unique

    RpcId = RpcIdNumber(number value) unique
          | RpcIdString(string value) unique
          | RpcIdNull

    RpcPayload = PayloadNull
               | PayloadInitialize(Lua.LspInitializeResult value) unique
               | PayloadDiagnosticReport(Lua.LspDiagnosticReport value) unique
               | PayloadHoverResult(Lua.LspHoverResult value) unique
               | PayloadLocationList(Lua.LspLocationList value) unique
               | PayloadDocumentHighlightList(Lua.LspDocumentHighlightList value) unique
               | PayloadPublishDiagnostics(Lua.LspDiagnosticReport value) unique
               | PayloadCompletionList(Lua.LspCompletionList value) unique
               | PayloadDocumentSymbolList(Lua.LspDocumentSymbolList value) unique
               | PayloadSignatureHelp(Lua.LspSignatureHelp value) unique
               | PayloadWorkspaceEdit(Lua.LspWorkspaceEdit value) unique
               | PayloadRange(Lua.LspRange value) unique

    RpcIncoming = RpcInInitialize(Lua.RpcId id) unique
                | RpcInInitialized
                | RpcInShutdown(Lua.RpcId id) unique
                | RpcInExit
                | RpcInIgnore(string method) unique
                | RpcInLspRequest(Lua.RpcId id, Lua.LspRequest request) unique
                | RpcInLspNotification(Lua.LspRequest request) unique
                | RpcInInvalid(string reason) unique

    RpcOutgoing = RpcOutResult(Lua.RpcId id, Lua.RpcPayload payload) unique
                | RpcOutError(Lua.RpcId id, number code, string message, string data) unique
                | RpcOutNotification(string method, Lua.RpcPayload payload) unique
                | RpcOutNone
}
]]

function M.context()
    return pvm.context():Define(M.SCHEMA)
end

return M
