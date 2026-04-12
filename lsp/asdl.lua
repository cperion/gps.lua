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

    ScopeEvent = ScopeEnter(Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
               | ScopeExit(Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
               | ScopeDeclLocal(Lua.DeclKind decl_kind, string name, Lua.AnchorRef anchor) unique
               | ScopeDeclGlobal(string name, Lua.AnchorRef anchor) unique
               | ScopeRef(string name, Lua.AnchorRef anchor) unique
               | ScopeWrite(string name, Lua.AnchorRef anchor) unique
    ScopeEventList = (Lua.ScopeEvent* items) unique

    ScopeLocalState = (string name, Lua.DeclKind decl_kind, number used, Lua.AnchorRef anchor) unique
    ScopeDiagFrame  = (Lua.ScopeKind scope, Lua.ScopeLocalState* locals) unique

    ScopeSymbolBinding = (string name, Lua.Symbol symbol) unique
    ScopeSymbolFrame   = (Lua.ScopeKind scope, string id, Lua.ScopeSymbolBinding* locals) unique

    TypeClassField = (string name, Lua.TypeExpr typ, boolean optional, Lua.AnchorRef anchor) unique
    TypeClass  = (string name, Lua.TypeExpr* extends, Lua.TypeClassField* fields, Lua.AnchorRef anchor) unique
    TypeAlias  = (string name, Lua.TypeExpr typ, Lua.AnchorRef anchor) unique
    TypeGeneric = (string name, Lua.TypeExpr* bounds, Lua.AnchorRef anchor) unique
    TypeEnv    = (Lua.TypeClass* classes, Lua.TypeAlias* aliases, Lua.TypeGeneric* generics) unique

    Symbol     = (string id, Lua.SymbolKind kind, string name, Lua.ScopeKind scope, string scope_id, Lua.AnchorRef decl_anchor) unique
    Occurrence = (string symbol_id, string name, Lua.SymbolKind kind, Lua.AnchorRef anchor) unique
    OccurrenceList = (Lua.Occurrence* items) unique
    Unresolved = (string name, Lua.AnchorRef anchor) unique
    SymbolIndex = (Lua.Symbol* symbols, Lua.Occurrence* defs, Lua.Occurrence* uses, Lua.Unresolved* unresolved) unique

    AnchorBinding = AnchorSymbol(Lua.Symbol symbol, Lua.AnchorRole role) unique
                  | AnchorUnresolved(string name) unique
                  | AnchorMissing

    TypeTarget = TypeClassTarget(string name, Lua.AnchorRef anchor, Lua.TypeClass value) unique
               | TypeAliasTarget(string name, Lua.AnchorRef anchor, Lua.TypeAlias value) unique
               | TypeGenericTarget(string name, Lua.AnchorRef anchor, Lua.TypeGeneric value) unique
               | TypeBuiltinTarget(string name) unique
               | TypeTargetMissing

    DefinitionMeta = DefMetaSymbol(Lua.AnchorRole role, Lua.Symbol symbol, Lua.Occurrence* defs) unique
                   | DefMetaType(Lua.TypeTarget target) unique
                   | DefMetaUnresolved(string name) unique
                   | DefMetaMissing

    DefinitionResult = DefHit(Lua.AnchorRef anchor, Lua.DefinitionMeta meta) unique
                     | DefMiss(Lua.DefinitionMeta meta) unique

    ReferenceResult = (Lua.Occurrence* refs) unique

    HoverInfo = HoverSymbol(Lua.AnchorRole role, string name, Lua.SymbolKind symbol_kind, Lua.ScopeKind scope, number defs, number uses, Lua.TypeExpr typ) unique
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

    Diagnostic    = (Lua.DiagnosticCode code, string message, string name, Lua.ScopeKind scope, Lua.AnchorRef anchor) unique
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
    SignatureEntry = (string name, Lua.SignatureInfo* signatures) unique
    SignatureCatalog = (Lua.SignatureEntry* items) unique
    SignatureHelp = (Lua.SignatureInfo* signatures, number active_signature) unique
    SignatureQuery = (Lua.File file, Lua.LspPos position) unique
    SignatureLookupQuery = (Lua.File file, string callee, number active_param) unique

    LspFormattingOptions = (number tab_size, boolean insert_spaces, boolean trim_trailing_ws, boolean insert_final_newline) unique
    FormatQuery  = (Lua.File file, Lua.LspFormattingOptions options, Lua.LspRange range, boolean has_range) unique
    FormatResult = (string text, Lua.LspRange range, boolean has_range) unique

    RenameEdit   = (Lua.AnchorRef anchor, Lua.LspRange range, string new_text) unique
    RenameResult = RenameOk(Lua.RenameEdit* edits) unique
                 | RenameFail(string reason) unique
    RenameQuery  = (Lua.File file, Lua.AnchorRef anchor, string new_name) unique
    CodeActionQuery = (Lua.File file, string uri, Lua.LspRange range, Lua.LspDiagnostic* diagnostics) unique

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

    AnchorEntryKind = AnchorKindDef
                    | AnchorKindUse
                    | AnchorKindUnresolved
                    | AnchorKindTypeClass
                    | AnchorKindTypeField
                    | AnchorKindTypeAlias
                    | AnchorKindTypeGeneric

    AnchorEntry     = (Lua.AnchorRef anchor, Lua.AnchorEntryKind kind, string name, Lua.LspRange range) unique
    AnchorEntryList = (Lua.AnchorEntry* items) unique
    LspPositionQuery = (Lua.File file, Lua.LspPos position, Lua.AnchorEntryKind prefer_kind, boolean has_prefer) unique
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
    LspSemanticTokenSpan     = (number line, number start, number length, Lua.LspSemanticTokenType token_type, Lua.LspSemanticTokenModifier* token_modifiers) unique
    LspSemanticTokenSpanList = (Lua.LspSemanticTokenSpan* items) unique
    LspSemanticTokenQuery    = (Lua.File file, string uri, string text) unique
    LspSemanticTokens = (number* data) unique

    LspInlayHintKind = InlayType
                     | InlayParameter
    LspInlayHint     = (Lua.LspPos position, string label, Lua.LspInlayHintKind kind) unique
    LspInlayHintList = (Lua.LspInlayHint* items) unique

    LspWorkspaceDiagnosticKind = WsDiagFull
                               | WsDiagUnchanged

    LspWorkspaceDiagnosticItem = (string uri, number version, Lua.LspWorkspaceDiagnosticKind kind, Lua.LspDiagnostic* items) unique
    LspWorkspaceDiagnostic = (Lua.LspWorkspaceDiagnosticItem* items) unique

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

function M.context()
    return pvm.context():Define(M.SCHEMA)
end

return M
