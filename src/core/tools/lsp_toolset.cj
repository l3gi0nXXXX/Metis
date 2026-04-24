package metis.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.jsonable.ToJsonValue

import metis.lsp.{LSPClient, DocumentSymbol}
import metis.core.config.CliConfig
import metis.core.tools.lsp_utils.LSPManager
import metis.io.PrintUtils

import std.fs.*
import std.collection.*
import stdx.encoding.json.*
import std.sync.{Mutex, Condition}
import std.time.DateTime

/**
 * LSP Toolset for code analysis using Language Server Protocol
 *
 * This toolset provides semantic code analysis capabilities by leveraging
 * the existing LSP client implementation.
 */
@toolset
public class LSPToolset {
    /**
     * Singleton LSP Manager instance
     */
    private static var _lspManager: Option<LSPManager> = None

    private static prop globalLSPManager: LSPManager {
        get() {
            if (let Some(manager) <- _lspManager) {
                return manager
            }
            LSPToolset.initialize()
            return LSPToolset._lspManager.getOrThrow()
        }
    }

    protected static func initialize(): Bool {
        try {
            LogUtils.info("🔧 New LSP Client...")
            let lspArgs = ["--enable-log=true", "--log-path=${CliConfig.logsDir.join("LSPServer.log")}"]
            let client = LSPClient("LSPServer", serverArgs: lspArgs)

            LogUtils.info("🔧 Initialize LSP Client, working dir: ${CliConfig.cwd.toString()}")
            client.initialize(root: CliConfig.cwd)

            LogUtils.info("✅ LSP Client initialized successfully")

            LSPToolset._lspManager = LSPManager(client)
            return true
        } catch (ex: Exception) {
            LogUtils.error("❌ LSP Client initialization failed: ${ex}")
            LogUtils.error("Error details: ${ex.message}")
            return false
        }
    }

    private func checkPath(filePath: String): Option<String> {
        if (!filePath.endsWith(".cj")) {
            return "Error: Currently only support Cangjie file (.cj extension)"
        }
        // Check if file path is absolute
        let path = Path(filePath)
        if (!path.isAbsolute()) {
            return "Error: File path must be absolute"
        }
        // Check if file exists
        if (!exists(path)) {
            return "Error: File does not exist: ${filePath}"
        }
        return None
    }

    @tool[
        description: """
Get all symbols (functions, classes, structs, etc.) in a file using LSP.
This tool provides a structured overview of the file's contents without reading the entire file.
Use this to quickly understand what's defined in a file before deciding what to read in detail.

Each symbol has the following property format:
Symbol name:
  kind: Symbol type (Class, Function, Method, Struct, Variable, etc.)
  detail: Additional details about the symbol
  range: Range of lines where the symbol is defined, format: startLine:startColumn--endLine:endColumn]
  children: Nested symbols (for classes, structs, etc.)
""",
        parameters: {
            filePath: "Absolute path to the source code file"
        }
    ]
    public func lspGetAllSymbols(filePath: String): String {
        if (let Some(error) <- this.checkPath(filePath)) {
            return error
        }

        PrintUtils.printTool("LSP All Symbols", shortMessage: filePath)

        try {
            let symbols = LSPToolset.globalLSPManager.getAllSymbols(filePath)
            LogUtils.debug(symbols)
            PrintUtils.printToolResult(symbols)
            return symbols
        } catch (e: Exception) {
            LogUtils.error("LSP getAllSymbolsInFile failed: ${e}")
            return "Error: ${e.message}.\nCaution: you should NOT use LSP tools any more!"
        }
    }

    @tool[
        description: """
Get symbols of a specific kind from a file.

Supported kinds:
- "class" or "Class" - Classes
- "function" or "Function" - Top-level functions
- "method" or "Method" - Class methods
- "enum" or "Enum" - Enumerations
- "interface" or "Interface" - Interfaces
- "struct" or "Struct" - Structs
- "variable" or "Variable" - Variables
- "constant" or "Constant" - Constants
""",
        parameters: {
            filePath: "Absolute path to the source code file",
            kind: "Symbol kind to filter (class, function, method, enum, interface, struct, variable, constant)"
        }
    ]
    public func lspFindSymbolsByKind(filePath: String, kind: String): String {
        if (let Some(error) <- this.checkPath(filePath)) {
            return error
        }

        PrintUtils.printTool("LSP Find", shortMessage: "${filePath}. ${kind}")

        try {
            let symbols = LSPToolset.globalLSPManager.findSymbolByKind(filePath, kind)
            LogUtils.debug(symbols)
            PrintUtils.printToolResult(symbols)
            return symbols
        } catch (e: Exception) {
            LogUtils.error("LSP findSymbolsByKind failed: ${e}")
            return "Error: ${e.message}.\nCaution: you should NOT use LSP tools any more!"
        }
    }

    @tool[
        description: """
Search for symbols by name in a file.

This tool helps you quickly locate specific symbols without reading the entire file.
Supports both exact and partial matching.
""",
        parameters: {
            filePath: "Absolute path to the source code file",
            symbolName: "Symbol name to search for (case-insensitive, supports partial match)",
            exactMatch: "Optional. Whether to use exact match (default: false)"
        }
    ]
    public func lspFindSymbolByName(filePath: String, symbolName: String, exactMatch: Option<Bool>): String {
        if (let Some(error) <- this.checkPath(filePath)) {
            return error
        }
        PrintUtils.printTool("LSP Find", shortMessage: "${filePath}. ${symbolName}")

        try {
            let useExactMatch = exactMatch ?? false
            let symbols = LSPToolset.globalLSPManager.findSymbolByName(filePath, symbolName, useExactMatch)
            LogUtils.debug(symbols)
            PrintUtils.printToolResult(symbols)
            return symbols
        } catch (e: Exception) {
            LogUtils.error("LSP findSymbolByName failed: ${e}")
            return "Error: ${e.message}.\nCaution: you should NOT use LSP tools any more!"
        }
    }

    @tool[
        description: """
Find where a symbol is used/referenced.

This tool finds the references of a symbol, which is at the specified location.
You must use other tools to get the symbol location first, such as the `lspGetAllSymbols`, `lspFindSymbolByKind`, `lspFindSymbolByName` etc., then use the line and column number of the symbol to get its references.
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file",
            line: "Line number of the symbol",
            column: "Column number of the symbol"
        }
    ]
    public func lspFindSymbolReference(filePath: String, line: Int64, column: Int64): String {
        if (let Some(error) <- this.checkPath(filePath)) {
            return error
        }

        PrintUtils.printTool("LSP References", shortMessage: "${line}:${column}")

        try {
            let references = LSPToolset.globalLSPManager.findSymbolReference(filePath, line, column)
            LogUtils.debug(references)
            PrintUtils.printToolResult(references)
            return references
        } catch (e: Exception) {
            LogUtils.error("LSP findSymbolReference failed: ${e}")
            return "Error: ${e.message}.\nCaution: you should NOT use LSP tools any more!"
        }
    }

    @tool[
        description: """
Get the definition of a symbol.

This tool finds the definition of a symbol, which is at the specified location.
You must use other tools to get the symbol location first, such as the `lspGetAllSymbols`, `lspFindSymbolByKind`, `lspFindSymbolByName` etc., then use the line and column number of the symbol to get its definition.
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file",
            line: "Line number of the symbol",
            column: "Column number of the symbol"
        }
    ]
    public func lspFindSymbolDefinition(filePath: String, line: Int64, column: Int64): String {
        if (let Some(error) <- this.checkPath(filePath)) {
            return error
        }

        PrintUtils.printTool("LSP Definition", shortMessage: "${line}:${column}")

        try {
            let definition = LSPToolset.globalLSPManager.findSymbolDefinition(filePath, line, column)
            LogUtils.debug(definition)
            PrintUtils.printToolResult(definition)
            return definition
        } catch (e: Exception) {
            LogUtils.error("LSP findSymbolDefinition failed: ${e}")
            return "Error: ${e.message}.\nCaution: you should NOT use LSP tools any more!"
        }
    }
}
