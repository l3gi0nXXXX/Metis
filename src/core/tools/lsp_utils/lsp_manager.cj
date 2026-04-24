package metis.core.tools.lsp_utils

import metis.lsp.*
import std.fs.Path
import std.collection.{ArrayList, HashMap, filter, collectArray, enumerate}
import magic.log.LogUtils

/**
 * LSP Manager class that provides high-level operations for working with LSP client
 * Features file modification time based caching to improve performance
 */
public class LSPManager {
    private let client: LSPClient
    private let cache: LSPCache
    private var documentVersions: HashMap<String, Int64> = HashMap<String, Int64>()

    public init(client: LSPClient) {
        // Check if client is already initialized
        if (!client.isInitialized()) {
            throw Exception("LSP client must be initialized before LSPManager")
        }

        this.client = client
        this.cache = LSPCache()
    }

    /**
     * Open a document with proper version tracking
     * @param filePath Path to the file
     * @param forceNewVersion Force incrementing version even if already opened
     */
    private func openDocumentWithVersion(filePath: Path, forceNewVersion!: Bool = false): Int64 {
        let filePathStr = filePath.toString()

        if (!this.documentVersions.contains(filePathStr) || forceNewVersion) {
            let currentVersion = (this.documentVersions.get(filePathStr) ?? 0) + 1

            // Update the version
            this.documentVersions[filePathStr] = currentVersion

            // Open the document with the new version
            this.client.openDocument(filePath, version: currentVersion)
            LogUtils.debug("Opened document ${filePathStr} with version ${currentVersion}")
        }

        return this.documentVersions[filePathStr]
    }

    /**
     * Get all symbols of a file and build the result as a string
     * @param filePath Path to the file to analyze
     * @return String representation of all symbols in the file
     */
    public func getAllSymbols(filePath: String): String {
        let path = Path(filePath)
        let symbols = this.getAllSymbolsArray(path)
        if (symbols.isEmpty()) {
            return "No symbols found in ${filePath}"
        }
        return this.buildSymbolsString(symbols)
    }

    /**
     * Get all symbols of a file as an array (internal helper)
     * Uses caching to improve performance for repeated requests
     */
    private func getAllSymbolsArray(filePath: Path): Array<DocumentSymbol> {
        // Check cache first
        if (let Some(cachedSymbols) <- this.cache.getCachedSymbols(filePath)) {
            LogUtils.debug("Using cached symbols for ${filePath}")
            return cachedSymbols
        }

        // Open document with proper version
        this.openDocumentWithVersion(filePath)

        // Get symbols from LSP client
        let symbols = this.client.getDocumentSymbols(filePath)

        // Cache the results
        if (symbols.size > 0) {
            this.cache.cacheSymbols(filePath, symbols)
            LogUtils.debug("Cached ${symbols.size} symbols for ${filePath}")
        }

        return symbols
    }

    /**
     * Build a string representation of symbols array
     */
    private func buildSymbolsString(symbols: Array<DocumentSymbol>, indentLevel!: Int64 = 0): String {

        let result = StringBuilder()
        let indent = "  " * (indentLevel)

        for (symbol in symbols) {
            if (indentLevel == 0) {
                result.append("${symbol.name}:\n")
            } else {
                result.append("${indent}- ${symbol.name}:\n")
            }

            result.append("${indent}  kind: ${symbol.kindName}\n")
            if (let Some(detail) <- symbol.detail) {
                result.append("${indent}  detail: ${detail}\n")
            }
            result.append("${indent}  range: ${symbol.range.start.line}:${symbol.range.start.character}--${symbol.range.end.line}:${symbol.range.end.character}\n")

            // Recursively process children
            if (symbol.children.size > 0) {
                result.append("${indent}  children:\n")
                result.append(this.buildSymbolsString(symbol.children, indentLevel: indentLevel + 1))
            }
        }

        return result.toString()
    }

    /**
     * Search for symbols by name in a file
     * @param filePath Path to the file to search
     * @param symbolName Name of the symbol to search for
     * @param exactMatch Whether to match symbol name exactly (true) or partially (false)
     * @return String representation of matching symbols
     */
    public func findSymbolByName(filePath: String, symbolName: String, exactMatch: Bool): String {
        let path = Path(filePath)
        let symbols = this.getAllSymbolsArray(path)

        let matchingSymbols = ArrayList<DocumentSymbol>()

        this.findSymbolsByNameRecursive(symbols, symbolName: symbolName, exactMatch: exactMatch, results: matchingSymbols)

        if (matchingSymbols.isEmpty()) {
            return "Symbol '${symbolName}' not found in ${filePath}"
        }

        return this.buildSymbolsString(matchingSymbols.toArray())
    }

    /**
     * Recursive helper to find symbols by name
     */
    private func findSymbolsByNameRecursive(symbols: Array<DocumentSymbol>, symbolName!: String, exactMatch!: Bool, results!: ArrayList<DocumentSymbol>): Unit {
        for (symbol in symbols) {
            let matches = if (exactMatch) {
                symbol.name == symbolName
            } else {
                symbol.name.contains(symbolName)
            }

            if (matches) {
                results.add(symbol)
            }

            // Check children recursively
            if (symbol.children.size > 0) {
                this.findSymbolsByNameRecursive(symbol.children, symbolName: symbolName, exactMatch: exactMatch, results: results)
            }
        }
    }

    /**
     * Search for symbols by kind in a file
     * @param filePath Path to the file to search
     * @param kind Type of symbols to search for (Class, Struct, Enum, Interface, Variable, Function, Method, Constant)
     * @return String representation of matching symbols
     */
    public func findSymbolByKind(filePath: String, kind: String): String {
        let path = Path(filePath)
        let symbols = this.getAllSymbolsArray(path)

        let isValidKind = this.checkSymbolKind(kind)
        if (!isValidKind) {
            return "Unknown symbol kind: ${kind}. Valid kinds: Class, Struct, Enum, Interface, Variable, Function, Method, Constant"
        }

        let matchingSymbols = ArrayList<DocumentSymbol>()
        this.findSymbolsByKindRecursive(symbols, kind: kind, results: matchingSymbols)

        if (matchingSymbols.isEmpty()) {
            return "No symbols of kind '${kind}' found in ${filePath}"
        }

        return this.buildSymbolsString(matchingSymbols.toArray())
    }

    /**
     * Check if the symbol kind is valid, not all kinds are supported
     */
    private func checkSymbolKind(kind: String): Bool {
        match (kind.toAsciiLower()) {
            case "class" => true
            case "method" => true
            case "property" => true
            case "field" => true
            case "constructor" => true
            case "enum" => true
            case "interface" => true
            case "function" => true
            case "variable" => true
            case "constant" => true
            case "struct" => true
            case "event" => true
            case "operator" => true
            case _ => false
        }
    }

    /**
     * Recursive helper to find symbols by kind
     */
    private func findSymbolsByKindRecursive(symbols: Array<DocumentSymbol>, kind!: String, results!: ArrayList<DocumentSymbol>): Unit {
        for (symbol in symbols) {
            if (symbol.kindName == kind) {
                results.add(symbol)
            }

            // Check children recursively
            if (symbol.children.size > 0) {
                this.findSymbolsByKindRecursive(symbol.children, kind: kind, results: results)
            }
        }
    }

    /**
     * Find the definition of the symbol at the specified location
     * @param filePath Path to the file
     * @param line Line number (1-based index)
     * @param column Column number (1-based index)
     * @return String representation of the definition location
     */
    public func findSymbolDefinition(filePath: String, line: Int64, column: Int64): String {
        let path = Path(filePath)

        // Check cache first
        if (let Some(cachedResult) <- this.cache.getCachedDefinition(path, line, column)) {
            LogUtils.debug("Using cached definition for ${filePath}:${line}:${column}")
            return this.formatDefinitionResult(cachedResult)
        }

        // Open document with proper version
        this.openDocumentWithVersion(path)

        // Get definition from LSP client
        let result = this.client.getDefinitions(path, line, column)

        // Cache the result
        if (let Some(defResult) <- result) {
            this.cache.cacheDefinition(path, line, column, defResult)
        }

        return this.formatDefinitionResult(result)
    }

    /**
     * Format definition result as string
     */
    private func formatDefinitionResult(result: Option<DefinitionResult>): String {
        match (result) {
            case Some(defResult) =>
                if (defResult.definitions.isEmpty()) {
                    return "No definition found"
                }
                let resultStr = StringBuilder("Definition found at:\n")
                for ((i, definition) in enumerate(defResult.definitions)) {
                    resultStr.append("${i + 1}. Found ${definition.symbol} defined at ${this.formatLocation(definition.location)}")
                    if (i != defResult.definitions.size - 1) {
                        resultStr.append("\n")
                    }
                }
                return resultStr.toString()
            case None => "Failed to get definition"
        }
    }

    private func formatLocation(location: Location): String {
        let path = location.uri.replace("file://", "")
        return "${path}:${location.range.start.line}:${location.range.start.character}"
    }

    /**
     * Find the references of the symbol at the specified location
     * @param filePath Path to the file
     * @param line Line number (1-based index)
     * @param column Column number (1-based index)
     * @return String representation of all reference locations
     */
    public func findSymbolReference(filePath: String, line: Int64, column: Int64): String {
        let path = Path(filePath)

        // Check cache first
        if (let Some(cachedResult) <- this.cache.getCachedReferences(path, line, column)) {
            LogUtils.debug("Using cached references for ${filePath}:${line}:${column}")
            return this.formatReferenceResult(cachedResult)
        }

        // Open document with proper version
        this.openDocumentWithVersion(path)

        // Get references from LSP client
        let result = this.client.getReferences(path, line, column)

        // Cache the result
        if (let Some(refResult) <- result) {
            this.cache.cacheReferences(path, line, column, refResult)
        }

        return this.formatReferenceResult(result)
    }

    /**
     * Format reference result as string
     */
    private func formatReferenceResult(result: Option<ReferenceResult>): String {
        match (result) {
            case Some(refResult) =>
                if (refResult.references.isEmpty()) {
                    return "No references found"
                }
                let resultStr = StringBuilder("References found (${refResult.references.size} total):\n")
                for ((i, reference) in enumerate(refResult.references)) {
                    resultStr.append("${i + 1}. Found ${reference.symbol} referred at ${this.formatLocation(reference.location)}")
                    if (i != refResult.references.size - 1) {
                        resultStr.append("\n")
                    }
                }
                return resultStr.toString()
            case None => "Failed to get references"
        }
    }

    /**
     * Invalidate cache for a specific file
     * Call this when you know a file has been modified
     */
    public func invalidateFileCache(filePath: String): Unit {
        let path = Path(filePath)
        this.cache.invalidateFile(path)
        // Also remove version tracking to force new version on next open
        this.documentVersions.remove(filePath)
        LogUtils.debug("Invalidated cache for ${filePath}")
    }

    public func close(): Unit {
        this.client.close()
        this.clearAllCache()
        LogUtils.debug("LSP Manager closed")
    }

    /**
     * Clear all cached data
     */
    public func clearAllCache(): Unit {
        this.cache.clearAll()
        this.documentVersions.clear()
        LogUtils.debug("Cleared all LSP manager cache")
    }

    /**
     * Get cache statistics for debugging
     */
    public func getCacheStatistics(): String {
        let (symbolsCount, definitionsCount, referencesCount) = this.cache.getCacheStats()
        return "LSP Cache Statistics:\n" +
               "- Symbols: ${symbolsCount}\n" +
               "- Definitions: ${definitionsCount}\n" +
               "- References: ${referencesCount}\n" +
               "- Documents: ${this.documentVersions.size}"
    }
}