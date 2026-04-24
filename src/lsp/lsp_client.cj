package metis.lsp

import magic.dsl.jsonable
import magic.log.LogUtils

import metis.utils.Toml

import std.fs.{File, Path, exists, canonicalize, FSException}
import std.collection.{ArrayList, HashMap, map, filter, filterMap, collectArray}
import stdx.encoding.json.*

/**
 * LSP Client for communicating with Cangjie Language Server
 */
public class LSPClient {
    private let fileCache = FileCache()

    private let jsonRpcClient: JSONRPCClient

    private var initialized: Bool = false

    // Set when initialization
    // Standard LSP token types
    private var tokenTypes: Array<String> = []
    // Standard LSP token modifiers
    private var tokenModifiers: Array<String> = []

    private var capabilities: Option<ServerCapabilities> = None

    public init(serverPath: String, serverArgs!: Array<String> = Array<String>()) {
        this.jsonRpcClient = JSONRPCClient(serverPath, serverArgs: serverArgs)
    }

    /**
     * Initialize the LSP connection
     */
    public func initialize(root!: Path = Path(".")): Bool {
        let rootUri = this.pathToUri(root)
        try {
            if (this.initialized) {
                return true
            }

            // Construct the initialization parameter
            let initJo = JsonValue.fromStr(LSP_CLIENT_INIT_VALUE).asObject()
            initJo.put("rootUri", JsonString(rootUri))
            initJo.put(
                "initializationOptions",
                JsonObject(HashMap<String, JsonValue>([
                    (
                        "multiModuleOption",
                        JsonObject(HashMap([
                            (rootUri, this.parseMultiModuleOption(root))
                        ]))
                    )
                ]))
            )

            let result = this.jsonRpcClient.sendRequest("initialize", params: initJo)
            let initResult = InitializeResult.fromJsonValue(result)

            this.capabilities = initResult.capabilities
            this.tokenTypes = initResult.capabilities.semanticTokensProvider.legend.tokenTypes
            this.tokenModifiers = initResult.capabilities.semanticTokensProvider.legend.tokenModifiers

            // Send initialized notification
            this.jsonRpcClient.sendNotification("initialized")

            this.initialized = true
            LogUtils.info("LSP client initialized successfully")
            return true
        } catch (ex: Exception) {
            LogUtils.error("Failed to initialize LSP client: ${ex}")
            LogUtils.debug(ex)
            throw Exception("LSP initialization failed: ${ex.message}")
            return false
        }
    }

    public func isInitialized(): Bool {
        return this.initialized
    }

    /**
     * Parse the cjpm.toml as MultiModuleOption
     */
    private func parseMultiModuleOption(path: Path): JsonValue {
        if (!exists(path.join("cjpm.toml"))) {
            throw FSException("cjpm.toml not found in ${path}")
        }
        let toml = Toml(path.join("cjpm.toml"))
        MultiModuleOption(
            name: toml.get<String>("package.name"),
            package_requires: JsonObject(),
            requires: JsonObject()
        ).toJsonValue()
    }

    /**
     * Open a text document in the LSP server
     */
    public func openDocument(filePath: Path, version!: Int64 = 1): Unit {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }
            // Invalidate existing file cache before opening the document
            // to ensure we get the latest content
            this.fileCache.invalidateCache(filePath)

            let content = this.fileCache.getFileContent(filePath)

            let openDocumentParam = OpenDocumentParam(
                textDocument: TextDocument(
                    uri: this.pathToUri(filePath),
                    languageId: "Cangjie",
                    version: version,
                    text: content
                )
            )

            this.jsonRpcClient.sendNotification(
                "textDocument/didOpen",
                params: openDocumentParam.toJsonValue().asObject()
            )
            LogUtils.info("Opened document: ${filePath}")
        } catch (ex: Exception) {
            LogUtils.error("Failed to open document ${filePath}: ${ex}")
            throw Exception("Failed to open document: ${ex.message}")
        }
    }

    /**
     * Get document symbols
     */
    public func getDocumentSymbols(filePath: Path): Array<DocumentSymbol> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = DocumentSymbolParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                )
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/documentSymbol", params: (params.toJsonValue().asObject()))
            if (let JsonKind.JsArray <- result.kind()) {
                let symbols = Array<DocumentSymbol>.fromJsonValue(result)
                for (symbol in symbols) {
                    symbol.adaptToOneBased()
                }
                return symbols
            } else {
                LogUtils.debug("Failed to get document symbols for ${filePath}: ${result}")
                return []
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to get document symbols for ${filePath}: ${ex}")
            LogUtils.error(ex)
            return []
        }
    }

    /**
     * Get semantic tokens for a document
     * @param filePath Path to the document
     * @param external: Whether to get semantic tokens externally, which decodes the token positions to 1-based index
     */
    public func getSemanticTokens(filePath: Path, external!: Bool = true): Array<SemanticTokenInfo> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = SemanticTokensParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                )
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/semanticTokens/full", params: params.toJsonValue().asObject())
            let semanticTokens = SemanticTokensResult.fromJsonValue(result)

            let tokens = this.decodeSemanticTokens(filePath, semanticTokens.data)
            if (external) {
                for (token in tokens) {
                    token.adaptToOneBased()
                }
            }
            return tokens
        } catch (ex: Exception) {
            LogUtils.error("Failed to get semantic tokens for ${filePath}: ${ex}")
            return Array<SemanticTokenInfo>()
        }
    }

    private func decodeSemanticTokens(filePath: Path, data: Array<Int64>): Array<SemanticTokenInfo> {
        let tokens = ArrayList<SemanticTokenInfo>()

        if (data.size < 5) {
            return tokens.toArray()
        }

        var currentLine: Int64 = 0
        var currentChar: Int64 = 0

        var i: Int64 = 0
        while (i + 4 < data.size) {
            let deltaLine = data[i]
            let deltaChar = data[i + 1]
            let length = data[i + 2]
            let tokenType = data[i + 3]
            let tokenModifiersBitmask = data[i + 4]

            currentLine += deltaLine
            if (deltaLine > 0) {
                currentChar = deltaChar
            } else {
                currentChar += deltaChar
            }

            // Decode token modifiers
            let modifiers = ArrayList<String>()
            // Check each bit position in the tokenModifiers bitmask
            for (j in 0..32) { // Assume 32 bits max for modifiers
                if ((tokenModifiersBitmask & (1 << j)) != 0) {
                    if (j < this.tokenModifiers.size) {
                        modifiers.add(this.tokenModifiers[j])
                    }
                }
            }

            // Convert tokenType to string
            let tokenTypeStr = if (tokenType < this.tokenTypes.size) {
                this.tokenTypes[tokenType]
            } else {
                "unknown"
            }

            // Get the text for the token from the file content
            let text = this.fileCache.getFileRangeContent(
                filePath,
                Range(
                    start: Position(line: currentLine, character: currentChar),
                    end: Position(line: currentLine, character: currentChar + length)
                )
            )

            tokens.add(SemanticTokenInfo(
                line: currentLine,
                character: currentChar,
                length: length,
                tokenType: tokenTypeStr,
                tokenModifiers: modifiers.toArray(),
                text: text
            ))

            i += 5
        }
        return tokens.toArray()
    }

    /**
     * Get references for a specific position in a document
     * @param filePath Path to the document
     * @param line Line number (1-based)
     * @param character Character position (1-based)
     */
    public func getReferences(filePath: Path, line: Int64, character: Int64): Option<ReferenceResult> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = ReferenceParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                ),
                position: Position(line: line - 1, character: character - 1),
                context: ReferenceContext()
            )

            let response = this.jsonRpcClient.sendRequest("textDocument/references", params: params.toJsonValue().asObject())

            let locations = Array<Location>.fromJsonValue(response)

            let references = locations |> map { location: Location =>
                ReferenceInfo(
                    location: location.toOneBased(),
                    symbol: this.fileCache.getFileRangeContent(
                        this.uriToPath(location.uri), location.range
                    )
                )
            } |> collectArray

            return ReferenceResult(references: references)
        } catch (ex: Exception) {
            LogUtils.error("Failed to get references for ${filePath}:${line}:${character}: ${ex}")
            LogUtils.error(ex)
            return None
        }
    }

    /**
     * Get definitions for a specific position in a document
     * @param filePath Path to the document
     * @param line Line number (1-based)
     * @param character Character position (1-based)
     */
    public func getDefinitions(filePath: Path, line: Int64, character: Int64): Option<DefinitionResult> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = DefinitionParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                ),
                position: Position(line: line - 1, character: character - 1)
            )

            let response = this.jsonRpcClient.sendRequest("textDocument/definition", params: params.toJsonValue().asObject())
            let locations = match (response.kind()) {
                case JsonKind.JsArray =>
                    Array<Location>.fromJsonValue(response)
                case JsonKind.JsObject =>
                    [Location.fromJsonValue(response)]
                case _ => throw Exception("Invalid response kind for definition request: ${response}")
            }

            let definitions = locations |> map { location: Location =>
                DefinitionInfo(
                    location: location.toOneBased(),
                    symbol: this.fileCache.getFileRangeContent(
                        this.uriToPath(location.uri), location.range
                    )
                )
            } |> collectArray
            return DefinitionResult(definitions: definitions)
        } catch (ex: Exception) {
            LogUtils.error("Failed to get definitions for ${filePath}:${line}:${character}: ${ex}")
            LogUtils.error(ex)
            return None
        }
    }

    /**
     * Get semantic information for a specific line
     * @param line is 1-based
     */
    public func getSemanticInfo(filePath: Path, line: Int64): LineSemanticInfo {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            // Open the document
            this.openDocument(filePath)

            // Get all semantic tokens for the document
            let allSemanticTokens = this.getSemanticTokens(filePath)

            // Filter tokens for the specified line
            let filteredSemanticTokens = allSemanticTokens |>
                filter { token => token.line == (line) } |>
                collectArray

            // Get hover info for the beginning of the line
            let hoverInfos = filteredSemanticTokens |>
                filterMap { token => this.getHover(filePath, token.line, token.character) } |>
                collectArray

            return LineSemanticInfo(
                filePath: filePath.toString(),
                line: line,
                tokens: filteredSemanticTokens,
                hoverInfos: hoverInfos
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to get semantic info for ${filePath}:${line}: ${ex}")
            LogUtils.error(ex)
            // Return empty result on error
            return LineSemanticInfo(
                filePath: filePath.toString(),
                line: line,
                tokens: [],
                hoverInfos: []
            )
        }
    }

    /**
     * Get hover information at a specific position
     * @param line is 1-based
     * @param character is 1-based
     */
    public func getHover(filePath: Path, line: Int64, character: Int64): Option<HoverInfo> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = HoverParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                ),
                position: Position(
                    line: line - 1,
                    character: character - 1
                )
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/hover", params: (params.toJsonValue().asObject()))

            // Check if result is null (JSON null)
            // Since JsonValue doesn't have isNull(), we'll need to handle this differently
            // For now, assume the result is valid

            let hoverResult = HoverResult.fromJsonValue(result)
            var hoverContent = this.parseHoverContent(hoverResult.contents.value)

            let symbol = if (let Some(range) <- hoverResult.range) {
                this.fileCache.getFileRangeContent(filePath, range)
            } else {
                ""
            }
            return HoverInfo(
                line: line,
                character: character,
                contents: hoverContent,
                range: hoverResult.range.map { it => it.toOneBased() },
                symbol: symbol
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to get hover info for ${filePath}:${line}:${character}: ${ex}")
            return None
        }
    }

    private func parseHoverContent(jsonValue: JsonValue): String {
        let hoverContent = StringBuilder()
        match (jsonValue.kind()) {
            case JsonKind.JsString =>
                hoverContent.append(jsonValue.asString().getValue())
            case JsonKind.JsObject =>
                let markedString = MarkedString.fromJsonValue(jsonValue)
                match (markedString.language) {
                    case Some(language) =>
                        // hoverContent.append("```${language}\n")
                        hoverContent.append(markedString.value)
                        // hoverContent.append("\n```\n")
                    case _ =>
                        hoverContent.append(markedString.value)
                }
            case JsonKind.JsArray =>
                let allContent = ArrayList<String>()
                for (item in jsonValue.asArray().getItems()) {
                    allContent.add(this.parseHoverContent(item))
                }
                hoverContent.append(String.join(allContent.toArray(), delimiter: " "))
            case _ => throw UnsupportedException("Unreachable")
        }
        return hoverContent.toString()
    }


    /**
     * Check if the server supports semantic tokens
     */
    public func supportsSemanticTokens(): Bool {
        match (this.capabilities) {
            case Some(_) => return true
            case _ => false
        }
    }

    /**
     * Check if the server supports hover
     */
    public func supportsHover(): Bool {
        match (this.capabilities) {
            case Some(caps) => caps.hoverProvider
            case _ => false
        }
    }

    /**
     * Close the LSP connection
     */
    public func close(): Unit {
        if (!this.initialized) {
            return
        }
        this.fileCache.clearAll()
        this.jsonRpcClient.close()
        this.initialized = false
        this.capabilities = None
    }

    // Helper methods
    private func pathToUri(path: Path): String {
        let canonicalPath = canonicalize(path)
        return "file://${canonicalPath.toString()}"
    }

    private func uriToPath(uri: String): Path {
        return Path(uri.replace("file://", ""))
    }
}