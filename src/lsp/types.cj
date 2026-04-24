package metis.lsp

import magic.dsl.jsonable
import magic.jsonable.*

import std.fs.Path
import stdx.encoding.json.*
import std.collection.*

/**
 * LSP Request Message - JSON-RPC 2.0 Request
 */
@jsonable
struct LSPRequest {
    public var jsonrpc: String = "2.0"
    public var id: Int64
    public var method: String
    public var params: Option<JsonObject> = None
}

/**
 * Result of response is a JSON value; however, we cannot let JsonValue as Jsonable,
 * so, we introduce a wrap type here
 */
struct LSPResult <: Jsonable<LSPResult> {
    public let value: JsonValue

    public init(value: JsonValue) {
        this.value = value
    }

    override public func toJsonValue(): JsonValue {
        this.value
    }

    redef public static func fromJsonValue(json: JsonValue): LSPResult {
        LSPResult(json)
    }

    redef public static func getTypeSchema(): TypeSchema {
        TypeSchema.Obj([])
    }
}

/**
 * LSP Response Message - JSON-RPC 2.0 Response
 */
@jsonable
struct LSPResponse {
    public var jsonrpc: String = "2.0"
    public var id: Int64
    public var result: Option<LSPResult> = None
    public var error: Option<LSPError> = None
}

/**
 * LSP Error Information
 */
@jsonable
struct LSPError {
    public var code: Int64
    public var message: String
    public var data: Option<JsonObject> = None
}

/**
 * LSP Notification Message - JSON-RPC 2.0 Notification
 */
@jsonable
struct LSPNotification {
    public var jsonrpc: String = "2.0"
    public var method: String
    public var params: Option<JsonObject> = None
}

/**
 * LSP Position in a text document
 */
@jsonable
public struct Position {
    public var line: Int64
    public var character: Int64

    public func toOneBased(): Position {
        Position(line: this.line + 1, character: this.character + 1)
    }
}

/**
 * LSP Range in a text document
 */
@jsonable
public struct Range {
    public var start: Position
    public var end: Position

    public func toOneBased(): Range {
        Range(start: this.start.toOneBased(), end: this.end.toOneBased())
    }
}

/**
 * LSP Text Document Identifier
 */
@jsonable
struct TextDocumentIdentifier {
    public var uri: String
}

/**
 * LSP Text Document Item for didOpen notification
 */
@jsonable
struct TextDocument {
    public var uri: String
    public var languageId: String
    public var version: Int64
    public var text: String
}

@jsonable
struct OpenDocumentParam {
    public var textDocument: TextDocument
}

/**
 * LSP Initialize Parameters
 */
@jsonable
struct InitializeParams {
    public var rootPath: String
    public var rootUri: String
}

@jsonable
struct MultiModuleOption {
    public var name: String
    public var package_requires: JsonObject
    public var requires: JsonObject
}

/**
 * LSP Client Capabilities
 */
@jsonable
struct ClientCapabilities {
    public var textDocument: Option<TextDocumentClientCapabilities> = None
}

/**
 * LSP Text Document Client Capabilities
 */
@jsonable
struct TextDocumentClientCapabilities {
    public var semanticTokens: Option<SemanticTokensClientCapabilities> = None
    public var hover: Option<HoverClientCapabilities> = None
    public var documentSymbol: Option<DocumentSymbolClientCapabilities> = None
}

/**
 * LSP Semantic Tokens Client Capabilities
 */
@jsonable
struct SemanticTokensClientCapabilities {
    public var dynamicRegistration: Bool
    public var requests: Option<SemanticTokensClientCapabilitiesRequests> = None
}

/**
 * LSP Semantic Tokens Client Capabilities Requests
 */
@jsonable
struct SemanticTokensClientCapabilitiesRequests {
    public var full: Option<SemanticTokensFullOptions> = None
}

/**
 * LSP Semantic Tokens Full Options
 */
@jsonable
struct SemanticTokensFullOptions {
    public var delta: Bool
}

/**
 * LSP Hover Client Capabilities
 */
@jsonable
struct HoverClientCapabilities {
    public var dynamicRegistration: Bool
    public var contentFormat: Option<Array<String>> = None
}

/**
 * LSP Document Symbol Client Capabilities
 */
@jsonable
struct DocumentSymbolClientCapabilities {
    public var dynamicRegistration: Bool
    public var symbolKind: Option<DocumentSymbolClientCapabilitiesSymbolKind> = None
}

/**
 * LSP Document Symbol Client Capabilities Symbol Kind
 */
@jsonable
struct DocumentSymbolClientCapabilitiesSymbolKind {
    public var valueSet: Option<Array<Int64>> = None
}

/**
 * LSP Client Info
 */
@jsonable
struct ClientInfo {
    public var name: String = "cj-lsp"
    public var version: Option<String> = "0.1.0"
}

/**
 * LSP Initialize Result
 */
@jsonable
struct InitializeResult {
    public var capabilities: ServerCapabilities
}

/**
 * LSP Server Capabilities
 */
@jsonable
struct ServerCapabilities {
    public var semanticTokensProvider: SemanticTokensServerCapabilities
    public var hoverProvider: Bool = false
    public var documentSymbolProvider: Bool = false
}

/**
 * LSP Semantic Tokens Server Capabilities
 */
@jsonable
struct SemanticTokensServerCapabilities {
    public var legend: SemanticTokensLegend
    public var full: SemanticTokensFullOptions
    public var range: Bool
}

/**
 * LSP Semantic Tokens Legend
 */
@jsonable
struct SemanticTokensLegend {
    public var tokenTypes: Array<String>
    public var tokenModifiers: Array<String>
}

//------------------------------------------------------
/**
 * LSP Semantic Tokens Parameters
 */
@jsonable
struct SemanticTokensParams {
    public var textDocument: TextDocumentIdentifier
}

/**
 * LSP Semantic Tokens Result
 */
@jsonable
struct SemanticTokensResult {
    public var data: Array<Int64>
}

/**
 * Individual semantic token information
 */
@jsonable
public class SemanticTokenInfo {
    public var line: Int64
    public var character: Int64
    public var length: Int64
    public var tokenType: String
    public var tokenModifiers: Array<String>
    public var text: String

    func adaptToOneBased(): Unit {
        this.line = this.line + 1
        this.character = this.character + 1
    }
}
//------------------------------------------------------

/**
 * LSP Hover Parameters
 */
@jsonable
struct HoverParams {
    public var textDocument: TextDocumentIdentifier
    public var position: Position
    public var workDoneToken: Option<JsonObject> = None
}

/**
 * LSP Hover Result
 */
@jsonable
struct HoverResult {
    public var contents: LSPResult
    public var range: Option<Range> = None
}

/**
 * Hover information for a specific position
 */
@jsonable
public struct HoverInfo {
    public var line: Int64
    public var character: Int64
    public var contents: String
    public var range: Option<Range> = None
    public let symbol: String
}

/**
 * LSP Marked String for hover content
 */
@jsonable
struct MarkedString {
    public var language: Option<String> = None
    public var value: String
}

//------------------------------------------------------

/**
 * LSP Document Symbol Parameters
 */
@jsonable
struct DocumentSymbolParams {
    public var textDocument: TextDocumentIdentifier
}

/**
 * LSP Document Symbol
 */
@jsonable
public class DocumentSymbol {
    public var name: String
    public var detail: Option<String> = None
    public var kind: Int64
    public var range: Range
    public var selectionRange: Range
    public var children: Array<DocumentSymbol> = []

    func toString(): String {
        let strBuilder = StringBuilder("${this.name} (${this.kindName})\n")
        match (this.detail) {
            case Some(detail) => strBuilder.append("  - Detail: ${detail}\n")
            case _ => ()
        }
        strBuilder.append("  - Range: ${this.range.start.line}:${this.range.start.character} - ${this.range.end.line}:${this.range.end.character}\n")
        return strBuilder.toString()
    }

    func adaptToOneBased(): Unit {
        this.range = this.range.toOneBased()
        this.selectionRange = this.selectionRange.toOneBased()
        for (child in this.children) {
            child.adaptToOneBased()
        }
    }

    // Helper function to get symbol kind name
    public prop kindName: String {
        get() {
            match (this.kind) {
                case 1 => "File"
                case 2 => "Module"
                case 3 => "Namespace"
                case 4 => "Package"
                case 5 => "Class"
                case 6 => "Method"
                case 7 => "Property"
                case 8 => "Field"
                case 9 => "Constructor"
                case 10 => "Enum"
                case 11 => "Interface"
                case 12 => "Function"
                case 13 => "Variable"
                case 14 => "Constant"
                case 15 => "String"
                case 16 => "Number"
                case 17 => "Boolean"
                case 18 => "Array"
                case 19 => "Object"
                case 20 => "Key"
                case 21 => "Null"
                case 22 => "EnumMember"
                case 23 => "Struct"
                case 24 => "Event"
                case 25 => "Operator"
                case 26 => "TypeParameter"
                case _ => "Unknown"
            }
        }
    }
}

//------------------------------------------------------

/**
 * LSP Text Document Position Parameters
 */
@jsonable
struct DefinitionParams {
    public var textDocument: TextDocumentIdentifier
    public var position: Position
}

@jsonable
public class Location {
    public let uri: String
    public var range: Range

    func toOneBased(): Location {
        return Location(uri: this.uri, range: this.range.toOneBased())
    }
}

@jsonable
public struct DefinitionInfo {
    public let location: Location
    public let symbol: String
}

/**
 * LSP Definition Result
 */
@jsonable
public struct DefinitionResult {
    public let definitions: Array<DefinitionInfo>
}

//------------------------------------------------------

/**
 * LSP Reference Parameters
 */
@jsonable
struct ReferenceParams {
    public var textDocument: TextDocumentIdentifier
    public var position: Position
    public var context: ReferenceContext
}

@jsonable
struct ReferenceContext {
    /**
     * Include the declaration of the current symbol.
     */
    public var includeDeclaration: Bool = false
}

@jsonable
public struct ReferenceResult {
    public let references: Array<ReferenceInfo>
}

@jsonable
public struct ReferenceInfo {
    public let location: Location
    public let symbol: String
}

//------------------------------------------------------

/**
 * Semantic Information Result for getSemanticInfo function
 */
@jsonable
public struct LineSemanticInfo {
    public var filePath: String
    public var line: Int64
    public var tokens: Array<SemanticTokenInfo>
    public var hoverInfos: Array<HoverInfo>
}
