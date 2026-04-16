-- lsp/asdl.lua
--
-- ASDL schema for the Lua LSP.
--
-- This file is the architectural source of truth.
-- The comments here describe both the value layers and the intended pvm.phase
-- boundaries installed as methods on the handled ASDL type families.
--
-- Core rules:
--   1. All internal boundaries are pvm.phase boundaries.
--   2. There is no pvm.lower world here anymore.
--   3. Facts stream lazily; aggregates exist only when they are the intended
--      compiled layer or an unavoidable protocol boundary.
--   4. If a value matters to the system, it must be ASDL, not a plain Lua table.
--   5. One-yield phases are still phases. Cardinality does not create a second
--      execution model.
--
-- Reading convention used in comments:
--   X -> Y*   means a streaming phase yielding zero or more Y values
--   X -> Y    means a one-yield phase returning one Y via pvm.once(...)
--
-- Architectural rule for this file:
--   The persistent semantic unit is the authored Item.
--   File-level aggregates exist only as assemblies over per-item products.
--   If a file-level layer cannot be explained as assembly from item products,
--   it is architecturally suspect.
--
-- Important cached phase methods and assembly helpers (target architecture):
--
--   OpenDoc:lex()                     -> Token*
--   OpenDoc:lex_with_positions()      -> LexTok*
--   OpenDoc:parse()                   -> ParsedDoc
--
--   SemanticDoc:collect_doc_types()     -> DocEvent*
--   Item:collect_doc_types()          -> DocEvent*
--   Item:item_scope_events()          -> ScopeEvent*
--   SemanticDoc:file_scope_events()     -> ScopeEvent*
--   Item:item_type_env()              -> ItemTypeEnv
--   Item:item_symbol_index()          -> ItemSymbolIndex
--   Item:item_scope_summary()         -> ItemScopeSummary
--   Item:item_semantics()             -> ItemSemantics
--   Item:item_unknown_type_diagnostics(KnownTypeSet) -> Diagnostic*
--   SemanticDoc:scope_diagnostics()     -> Diagnostic*   -- assembly helper
--   SemanticDoc:diagnostics()           -> Diagnostic*   -- assembly helper
--
--   SemanticDoc:resolve_named_types()   -> TypeEnv       -- assembly helper
--   SemanticDoc:symbol_index()          -> SymbolIndex   -- assembly helper
--   SymbolIdQuery:definitions_of()    -> Occurrence*
--   SymbolIdQuery:references_of()     -> Occurrence*
--   SubjectQuery:symbol_for_anchor()  -> AnchorBinding
--   TypeNameQuery:type_target()       -> TypeTarget
--   SubjectQuery:goto_definition()    -> DefinitionResult
--   RefQuery:find_references()        -> Occurrence*
--   SubjectQuery:hover()              -> HoverInfo
--
--   SemanticDoc:typed_index()           -> TypedIndex
--   CompletionQuery:complete()        -> CompletionItem*
--   SemanticDoc:doc_symbol_facts()      -> DocSymbolFact*
--   SemanticDoc:doc_symbol_tree()       -> DocSymbolTree
--   SemanticDoc:signature_catalog()     -> SignatureEntry*
--   SignatureLookupQuery:signature_lookup() -> SignatureHelp
--   RenameQuery:rename()              -> RenameResult
--   RenamePrepareQuery:prepare_rename() -> RenamePrepareResult
--   FormatQuery:format_file()         -> FormatResult
--   CodeActionQuery:plan_code_actions() -> LspCodeAction*
--   LspSemanticTokenQuery:plan_semantic_tokens() -> LspSemanticTokenSpan*
--
-- Legacy list/product wrappers remain where current code still uses them or
-- where the external protocol wants a whole aggregate. They should not be used
-- as excuses to materialize internal intermediate layers eagerly.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local pvm = require("pvm")

local M = {}

local parts = {}
local function add(chunk)
    local out = {}
    for line in chunk:gmatch("([^\n]*\n?)") do
        if line == "" then break end
        if not line:match("^%s*%-%-") then
            out[#out + 1] = line
        end
    end
    parts[#parts + 1] = table.concat(out)
end

add [[
module Lua {
]]

-- Source / parsed document layer.
-- Parsing yields one coherent compiled document product.
add [[
    OpenDoc = (string uri, number version, string text) unique
    Token = (string kind, string value) unique
    AnchorRef = (string id) unique

    -- OpenDoc -> LexTok*
    LexTok = (Lua.Token token, number line, number col, number start_offset, number end_offset) unique

    Span = (Lua.LspRange range, number start_offset, number stop_offset) unique
    AnchorPoint = (Lua.AnchorRef anchor, string label, Lua.Span span) unique
    ParsedItem = (Lua.Item syntax, Lua.Span span) unique

    ParseStatus = ParseOk
                | ParseError(string message) unique

    -- OpenDoc -> ParsedDoc
    -- Parsing no longer splits syntax from coordinate metadata.
    ParsedDoc = (string uri, number version, string text, Lua.ParsedItem* items, Lua.AnchorPoint* anchors, Lua.ParseStatus status) unique
]]

-- Core syntax layer.
add [[
    ScopeKind = ScopeFile
              | ScopeFunction
              | ScopeIf
              | ScopeElse
              | ScopeWhile
              | ScopeRepeat
              | ScopeFor
              | ScopeDo
              | ScopeType

    DeclKind = DeclLocal
             | DeclParam

    SymbolKind = SymLocal
               | SymParam
               | SymGlobal
               | SymBuiltin
               | SymTypeClass
               | SymTypeAlias
               | SymTypeGeneric
               | SymTypeBuiltin

    AnchorRole = RoleDef
               | RoleUse

    DiagnosticCode = DiagUndefinedGlobal
                   | DiagUnknownType
                   | DiagRedeclareLocal
                   | DiagShadowingLocal
                   | DiagShadowingGlobal
                   | DiagUnusedLocal
                   | DiagUnusedParam

    NameOcc = OccDecl(Lua.DeclKind decl_kind, string name) unique
            | OccRef(string name) unique
            | OccWrite(string name) unique
            | OccScopeEnter(Lua.ScopeKind scope) unique
            | OccScopeExit(Lua.ScopeKind scope) unique

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
]]

-- Documentation/type language layer.
add [[
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

    -- ParsedDoc -> DocEvent*
    -- Streaming facts extracted from doc blocks.
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
]]

-- Semantic fact layers.
add [[
    -- Item -> ScopeEvent*
    -- ParsedDoc -> ScopeEvent* (assembled from Item -> ScopeEvent*)
    ScopeEvent = ScopeEnter(Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
               | ScopeExit(Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
               | ScopeDeclLocal(Lua.DeclKind decl_kind, string name, Lua.AnchorRef anchor) unique
               | ScopeDeclGlobal(string name, Lua.AnchorRef anchor) unique
               | ScopeRef(string name, Lua.AnchorRef anchor) unique
               | ScopeWrite(string name, Lua.AnchorRef anchor) unique

    ScopeLocalState = (string name, Lua.DeclKind decl_kind, number used, Lua.AnchorRef anchor) unique
    ScopeDiagFrame  = (Lua.ScopeKind scope, Lua.ScopeLocalState* locals) unique

    ScopeSymbolBinding = (string name, Lua.Symbol symbol) unique
    ScopeSymbolFrame   = (Lua.ScopeKind scope, string id, Lua.ScopeSymbolBinding* locals) unique

    TypeClassField = (string name, Lua.TypeExpr typ, boolean optional, Lua.AnchorRef anchor) unique
    TypeClass  = (string name, Lua.TypeExpr* extends, Lua.TypeClassField* fields, Lua.AnchorRef anchor) unique
    TypeAlias  = (string name, Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
    TypeGeneric = (string name, Lua.TypeExpr* bounds, Lua.AnchorRef anchor) unique

    -- Item -> ItemTypeEnv
    -- One-yield compiled type contribution for a single authored item.
    -- This is the primary persistent type unit; file-level TypeEnv is assembled
    -- from these item products.
    ItemTypeEnv = (Lua.TypeClass* classes, Lua.TypeAlias* aliases, Lua.TypeGeneric* generics) unique

    -- ParsedDoc -> TypeEnv
    -- One-yield compiled type environment assembled from ItemTypeEnv products.
    TypeEnv    = (Lua.TypeClass* classes, Lua.TypeAlias* aliases, Lua.TypeGeneric* generics) unique
    KnownTypeSet = (string* names) unique

    Symbol     = (string id, Lua.SymbolKind kind, string name, Lua.ScopeKind scope, string scope_id, Lua.AnchorRef decl_anchor) unique

    -- SymbolIdQuery -> Occurrence*
    -- RefQuery -> Occurrence*
    Occurrence = (string symbol_id, string name, Lua.SymbolKind kind, Lua.AnchorRef anchor) unique

    Unresolved = (string name, Lua.AnchorRef anchor) unique

    -- Item -> ItemSymbolIndex
    -- One-yield compiled symbolic product for a single authored item.
    ItemSymbolIndex = (Lua.Symbol* symbols, Lua.Occurrence* defs, Lua.Occurrence* uses, Lua.Unresolved* unresolved) unique

    ItemScopeOp = ItemScopeDeclareLocal(Lua.DeclKind decl_kind, string name, Lua.AnchorRef anchor, number used_in_item) unique
                | ItemScopeShadowCandidate(string name, Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
                | ItemScopeOuterRead(string name, Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
                | ItemScopeOuterWrite(string name, Lua.ScopeKind scope, Lua.AnchorRef anchor) unique

    -- Item -> ItemScopeSummary
    -- One-yield compiled scope/diagnostic interface for a single item.
    -- It contains only effects that cross the item boundary plus diagnostics
    -- decidable entirely within the item.
    ItemScopeSummary = (Lua.ItemScopeOp* ops, Lua.Diagnostic* diagnostics) unique

    -- Item -> ItemSemantics
    -- The per-item compiled semantic unit. File-level semantic answers are
    -- assembled from this product family.
    ItemSemantics = (Lua.ItemTypeEnv type_env, Lua.ItemSymbolIndex symbol_index, Lua.ItemScopeSummary scope_summary) unique

    -- ParsedDoc -> SemanticDoc
    -- One coherent compiled semantic product for a document snapshot.
    SemanticItem = (Lua.Item syntax, Lua.Span span, Lua.ItemSemantics semantics) unique

    -- ParsedDoc -> SymbolIndex
    -- One-yield compiled aggregate assembled from ItemSymbolIndex products.
    -- This is a query-facing assembly layer, not the semantic center.
    SymbolIndex = (Lua.Symbol* symbols, Lua.Occurrence* defs, Lua.Occurrence* uses, Lua.Unresolved* unresolved) unique

    -- SubjectQuery -> AnchorBinding
    AnchorBinding = AnchorSymbol(Lua.Symbol symbol, Lua.AnchorRole role) unique
                  | AnchorUnresolved(string name) unique
                  | AnchorMissing

    -- TypeNameQuery -> TypeTarget
    TypeTarget = TypeClassTarget(string name, Lua.AnchorRef anchor, Lua.TypeClass value) unique
               | TypeAliasTarget(string name, Lua.AnchorRef anchor, Lua.TypeAlias value) unique
               | TypeGenericTarget(string name, Lua.AnchorRef anchor, Lua.TypeGeneric value) unique
               | TypeBuiltinTarget(string name) unique
               | TypeTargetMissing

    DefinitionMeta = DefMetaSymbol(Lua.AnchorRole role, Lua.Symbol symbol, Lua.Occurrence* defs) unique
                   | DefMetaType(Lua.TypeTarget target) unique
                   | DefMetaUnresolved(string name) unique
                   | DefMetaMissing

    -- SubjectQuery -> DefinitionResult
    DefinitionResult = DefHit(Lua.AnchorRef anchor, Lua.DefinitionMeta meta) unique
                     | DefMiss(Lua.DefinitionMeta meta) unique

    -- SubjectQuery -> HoverInfo
    HoverInfo = HoverSymbol(Lua.AnchorRole role, string name, Lua.SymbolKind symbol_kind, Lua.ScopeKind scope, number defs, number uses, Lua.TypeExpr typ) unique
              | HoverType(string name, string detail, number fields) unique
              | HoverUnresolved(string name, string detail) unique
              | HoverMissing

    QuerySubject = QueryAnchor(Lua.AnchorRef anchor) unique
                 | QueryTypeName(string name) unique
                 | QueryMissing

    SymbolIdQuery = (Lua.SemanticDoc doc, string symbol_id) unique
    SubjectQuery  = (Lua.SemanticDoc doc, Lua.QuerySubject subject) unique
    RefQuery      = (Lua.SemanticDoc doc, Lua.QuerySubject subject, boolean include_declaration) unique
    TypeNameQuery = (Lua.SemanticDoc doc, string name) unique

    -- Item + KnownTypeSet -> Diagnostic*
    -- ParsedDoc -> Diagnostic* (assembled from scope state + per-item type diagnostics)
    Diagnostic    = (Lua.DiagnosticCode code, string message, string name, Lua.ScopeKind scope, Lua.AnchorRef anchor) unique

    SemanticDoc = (
        string uri,
        number version,
        string text,
        Lua.SemanticItem* items,
        Lua.AnchorPoint* anchors,
        Lua.ParseStatus status,
        Lua.TypeEnv type_env,
        Lua.SymbolIndex symbol_index,
        Lua.Diagnostic* diagnostics
    ) unique
]]

-- Type inference / editor feature semantic layers.
add [[
    -- ParsedDoc -> TypedIndex
    TypedSymbol = (Lua.Symbol symbol, Lua.TypeExpr typ) unique
    TypedIndex  = (Lua.TypedSymbol* symbols) unique

    CompletionQuery = (Lua.SemanticDoc doc, Lua.LspPos position, string prefix) unique

    -- CompletionQuery -> CompletionItem*
    CompletionItem = (string label, number kind, string detail, string sort_text, string insert_text) unique

    -- ParsedDoc -> DocSymbolFact*
    -- Streaming flat facts. Tree assembly is a later one-yield phase.
    DocSymbolFact = (string id, string parent_id, string name, string detail, number kind, Lua.AnchorRef anchor) unique

    -- Tree aggregate used at protocol boundary.
    DocSymbol     = (string name, string detail, number kind, Lua.AnchorRef anchor, Lua.DocSymbol* children) unique
    DocSymbolTree = (Lua.DocSymbol* items) unique

    ParamLabel    = (string label) unique
    SignatureInfo = (string label, Lua.ParamLabel* params, number active_param) unique

    -- ParsedDoc -> SignatureEntry*
    SignatureEntry = (string name, Lua.SignatureInfo* signatures) unique
    SignatureCatalog = (Lua.SignatureEntry* items) unique

    SignatureHelp = (Lua.SignatureInfo* signatures, number active_signature) unique
    SignatureQuery = (Lua.SemanticDoc doc, Lua.LspPos position) unique
    SignatureLookupQuery = (Lua.SemanticDoc doc, string callee, number active_param) unique

    LspFormattingOptions = (number tab_size, boolean insert_spaces, boolean trim_trailing_ws, boolean insert_final_newline) unique
    FormatQuery  = (Lua.SemanticDoc doc, Lua.LspFormattingOptions options, Lua.LspRange range, boolean has_range) unique
    FormatResult = (string text, Lua.LspRange range, boolean has_range) unique

    RenameEdit   = (Lua.AnchorRef anchor, Lua.LspRange range, string new_text) unique
    RenameResult = RenameOk(Lua.RenameEdit* edits) unique
                 | RenameFail(string reason) unique
    RenameQuery  = (Lua.SemanticDoc doc, Lua.AnchorRef anchor, string new_name) unique

    RenamePrepareResult = RenamePrepareHit(Lua.LspRange range) unique
                        | RenamePrepareMiss
    RenamePrepareQuery = (Lua.SemanticDoc doc, Lua.AnchorRef anchor) unique

    CodeActionQuery = (Lua.SemanticDoc doc, string uri, Lua.LspRange range, Lua.LspDiagnostic* diagnostics) unique
]]

-- LSP transport / protocol shapes.
add [[
    LspPos   = (number line, number character) unique
    LspRange = (Lua.LspPos start, Lua.LspPos stop) unique
    LspRangeQuery = (Lua.SemanticDoc doc, Lua.AnchorRef anchor) unique

    SemanticDocStore = (Lua.SemanticDoc* docs) unique
    SemanticDocQuery = (Lua.SemanticDocStore store, string uri) unique
    SemanticDocLookup = SemanticDocHit(Lua.SemanticDoc doc) unique
                     | SemanticDocMiss

    AnchorEntryKind = AnchorKindDef
                    | AnchorKindUse
                    | AnchorKindUnresolved
                    | AnchorKindTypeClass
                    | AnchorKindTypeField
                    | AnchorKindTypeAlias
                    | AnchorKindTypeGeneric

    -- ParsedDoc -> AnchorEntry*
    AnchorEntry     = (Lua.AnchorRef anchor, Lua.AnchorEntryKind kind, string name, Lua.LspRange range) unique
    LspPositionQuery = (Lua.SemanticDoc doc, Lua.LspPos position, Lua.AnchorEntryKind prefer_kind, boolean has_prefer) unique
    AnchorPick = AnchorPickHit(Lua.AnchorRef anchor, Lua.AnchorEntry entry) unique
               | AnchorPickMiss

    LspLocation     = (string uri, Lua.LspRange range) unique
    LspLocationList = (Lua.LspLocation* items) unique

    LspDiagnosticProviderInfo = (boolean inter_file_dependencies, boolean workspace_diagnostics) unique
    LspCapabilities = (number text_document_sync, boolean hover_provider, boolean definition_provider, boolean references_provider, boolean document_highlight_provider, Lua.LspDiagnosticProviderInfo diagnostic_provider, boolean completion_provider, boolean document_symbol_provider, boolean rename_provider, boolean signature_help_provider, boolean workspace_symbol_provider, boolean code_action_provider, boolean semantic_tokens_provider, boolean inlay_hint_provider, boolean formatting_provider) unique
    LspServerInfo   = (string name, string version) unique
    LspInitializeResult = (Lua.LspCapabilities capabilities, Lua.LspServerInfo server_info) unique

    LspDiagnosticReportKind = DiagReportFull
                            | DiagReportUnchanged

    LspDiagnostic       = (Lua.LspRange range, number severity, string source, string code, string message) unique
    LspDiagnosticList   = (Lua.LspDiagnostic* items) unique
    LspDiagnosticReport = (Lua.LspDiagnosticReportKind kind, Lua.LspDiagnostic* items, string uri, number version) unique

    LspMarkupKind = MarkupPlainText
                  | MarkupMarkdown

    LspMarkupContent = (Lua.LspMarkupKind kind, string value) unique
    LspHover = (Lua.LspMarkupContent contents, Lua.LspRange range) unique
    LspHoverResult = LspHoverHit(Lua.LspHover value) unique
                   | LspHoverMiss

    LspDocumentHighlight     = (Lua.LspRange range, number kind) unique
    LspDocumentHighlightList = (Lua.LspDocumentHighlight* items) unique

    LspCompletionItem = (string label, number kind, string detail, string sort_text, string insert_text, string documentation) unique
    LspCompletionList = (Lua.LspCompletionItem* items, boolean is_incomplete) unique

    LspDocumentSymbol     = (string name, string detail, number kind, Lua.LspRange range, Lua.LspRange selection_range, Lua.LspDocumentSymbol* children) unique
    LspDocumentSymbolList = (Lua.LspDocumentSymbol* items) unique

    LspWorkspaceSymbol     = (string name, number kind, string uri, Lua.LspRange range, string container_name) unique
    LspWorkspaceSymbolList = (Lua.LspWorkspaceSymbol* items) unique

    LspSignatureInfo = (string label, Lua.LspMarkupContent documentation, Lua.LspRange* param_ranges) unique
    LspSignatureHelp = (Lua.LspSignatureInfo* signatures, number active_signature, number active_parameter) unique

    LspTextEdit      = (Lua.LspRange range, string new_text) unique
    LspTextEditList  = (Lua.LspTextEdit* items) unique
    LspWorkspaceEdit = (Lua.LspTextEdit* edits, string uri) unique

    LspFoldingRangeKind = FoldComment
                        | FoldRegion
                        | FoldImports
    LspFoldingRange = (number start_line, number start_character, number end_line, number end_character, Lua.LspFoldingRangeKind kind) unique
    LspFoldingRangeList = (Lua.LspFoldingRange* items) unique

    LspSelectionRange = (Lua.LspRange range, Lua.LspRange* parents) unique
    LspSelectionRangeList = (Lua.LspSelectionRange* items) unique

    LspCodeLens = (Lua.LspRange range, string command_title, string command_id) unique
    LspCodeLensList = (Lua.LspCodeLens* items) unique

    LspColor = (number red, number green, number blue, number alpha) unique
    LspColorInfo = (Lua.LspRange range, Lua.LspColor color) unique
    LspColorInfoList = (Lua.LspColorInfo* items) unique

    LspCodeActionKind = CodeActionQuickFix
                      | CodeActionRefactor
                      | CodeActionSource
    LspCodeAction     = (string title, Lua.LspCodeActionKind kind, Lua.LspWorkspaceEdit edit) unique
    LspCodeActionList = (Lua.LspCodeAction* items) unique

    LspSemanticTokenType = SemTokNamespace
                         | SemTokType
                         | SemTokClass
                         | SemTokEnum
                         | SemTokInterface
                         | SemTokStruct
                         | SemTokTypeParameter
                         | SemTokParameter
                         | SemTokVariable
                         | SemTokProperty
                         | SemTokEnumMember
                         | SemTokEvent
                         | SemTokFunction
                         | SemTokMethod
                         | SemTokMacro
                         | SemTokKeyword
                         | SemTokModifier
                         | SemTokComment
                         | SemTokString
                         | SemTokNumber
                         | SemTokRegexp
                         | SemTokOperator
                         | SemTokDecorator
    LspSemanticTokenModifier = SemTokDeclaration
                             | SemTokDefinition
                             | SemTokReadonly
                             | SemTokStatic
                             | SemTokDeprecated
                             | SemTokAbstract
                             | SemTokAsync
                             | SemTokModification
                             | SemTokDocumentation
                             | SemTokDefaultLibrary
                             | SemTokGlobal

    -- LspSemanticTokenQuery -> LspSemanticTokenSpan*
    LspSemanticTokenSpan     = (number line, number start, number length, Lua.LspSemanticTokenType token_type, Lua.LspSemanticTokenModifier* token_modifiers) unique
    LspSemanticTokenSpanList = (Lua.LspSemanticTokenSpan* items) unique
    LspSemanticTokenQuery    = (Lua.SemanticDoc doc) unique
    LspSemanticTokens = (number* data) unique

    LspInlayHintKind = InlayType
                     | InlayParameter
    LspInlayHint     = (Lua.LspPos position, string label, Lua.LspInlayHintKind kind) unique
    LspInlayHintList = (Lua.LspInlayHint* items) unique

    LspWorkspaceDiagnosticKind = WsDiagFull
                               | WsDiagUnchanged

    LspWorkspaceDiagnosticItem = (string uri, number version, Lua.LspWorkspaceDiagnosticKind kind, Lua.LspDiagnostic* items) unique
    LspWorkspaceDiagnostic = (Lua.LspWorkspaceDiagnosticItem* items) unique
]]

-- Request / RPC layer.
add [[
    LspDocIdentifier  = (string uri) unique
    LspDocItem        = (string uri, number version, string text) unique
    LspVersionedDoc   = (string uri, number version) unique
    LspTextChange     = (string text, Lua.LspRange range, boolean has_range) unique
    LspReferenceContext = (boolean include_declaration) unique

    LspRequest = ReqDidOpen(Lua.LspDocItem doc) unique
               | ReqDidChange(Lua.LspVersionedDoc doc, Lua.LspTextChange* changes) unique
               | ReqDidClose(Lua.LspDocIdentifier doc) unique
               | ReqDidSave(Lua.LspDocIdentifier doc) unique
               | ReqHover(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqDefinition(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqDeclaration(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqImplementation(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqTypeDefinition(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqReferences(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject, Lua.LspReferenceContext context) unique
               | ReqDocumentHighlight(Lua.LspDocIdentifier doc, Lua.LspPos position, Lua.QuerySubject subject) unique
               | ReqDiagnostic(Lua.LspDocIdentifier doc) unique
               | ReqCompletion(Lua.LspDocIdentifier doc, Lua.LspPos position) unique
               | ReqCompletionResolve(Lua.LspCompletionItem item) unique
               | ReqDocumentSymbol(Lua.LspDocIdentifier doc) unique
               | ReqSignatureHelp(Lua.LspDocIdentifier doc, Lua.LspPos position) unique
               | ReqRename(Lua.LspDocIdentifier doc, Lua.LspPos position, string new_name) unique
               | ReqPrepareRename(Lua.LspDocIdentifier doc, Lua.LspPos position) unique
               | ReqCodeAction(Lua.LspDocIdentifier doc, Lua.LspRange range) unique
               | ReqCodeActionResolve(Lua.LspCodeAction action) unique
               | ReqSemanticTokensFull(Lua.LspDocIdentifier doc) unique
               | ReqSemanticTokensRange(Lua.LspDocIdentifier doc, Lua.LspRange range) unique
               | ReqInlayHint(Lua.LspDocIdentifier doc, Lua.LspRange range) unique
               | ReqFormatting(Lua.LspDocIdentifier doc, Lua.LspFormattingOptions options, Lua.LspRange range, boolean has_range) unique
               | ReqFoldingRange(Lua.LspDocIdentifier doc) unique
               | ReqSelectionRange(Lua.LspDocIdentifier doc, Lua.LspPos* positions) unique
               | ReqCodeLens(Lua.LspDocIdentifier doc) unique
               | ReqDocumentColor(Lua.LspDocIdentifier doc) unique
               | ReqWorkspaceSymbol(string query) unique
               | ReqWorkspaceDiagnostic
               | ReqExecuteCommand(string command, string* arguments) unique
               | ReqInvalid(string reason) unique

    LspAnchorQuery = (Lua.SemanticDoc doc, Lua.AnchorRef anchor, boolean include_declaration) unique

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
               | PayloadCompletionItem(Lua.LspCompletionItem value) unique
               | PayloadDocumentSymbolList(Lua.LspDocumentSymbolList value) unique
               | PayloadSignatureHelp(Lua.LspSignatureHelp value) unique
               | PayloadWorkspaceEdit(Lua.LspWorkspaceEdit value) unique
               | PayloadRange(Lua.LspRange value) unique
               | PayloadCodeActionList(Lua.LspCodeActionList value) unique
               | PayloadCodeAction(Lua.LspCodeAction value) unique
               | PayloadSemanticTokens(Lua.LspSemanticTokens value) unique
               | PayloadInlayHintList(Lua.LspInlayHintList value) unique
               | PayloadTextEditList(Lua.LspTextEditList value) unique
               | PayloadFoldingRangeList(Lua.LspFoldingRangeList value) unique
               | PayloadSelectionRangeList(Lua.LspSelectionRangeList value) unique
               | PayloadCodeLensList(Lua.LspCodeLensList value) unique
               | PayloadColorInfoList(Lua.LspColorInfoList value) unique
               | PayloadWorkspaceSymbolList(Lua.LspWorkspaceSymbolList value) unique
               | PayloadWorkspaceDiagnostic(Lua.LspWorkspaceDiagnostic value) unique
               | PayloadExecuteResult(string value) unique

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

M.SCHEMA = table.concat(parts)

function M.context()
    return pvm.context():Define(M.SCHEMA)
end

return M
