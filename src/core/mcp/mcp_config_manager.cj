package metis.core.mcp

import magic.dsl.jsonable
import magic.mcp.*
import magic.log.LogUtils
import magic.core.tool.Tool
import magic.core.agent.Agent
import magic.jsonable.*

import metis.core.config.{CliConfig, CliSetting, CliSettingManager, MetisConfigManager}
import metis.core.config.MetisPaths
import metis.io.{InputUtils, PrintUtils}
import metis.utils.InfoUtils

import std.fs.{exists, File, Path}
import std.collection.{HashMap, ArrayList, filter, collectArray}
import std.env.getVariable
import stdx.encoding.json.*

private enum MCPServerConfig <: FromJsonValue<MCPServerConfig> & ToJsonValue {
    | Stdio(StdioMCPInitParams)
    | Sse(SseMCPInitParams)
    | Http(HttpMCPInitParams)

    /**
     * Check and parse the server type from the initial parameters
     */
    redef public static func fromJsonValue(initParams: JsonValue): MCPServerConfig {
        if (let Some(url) <- initParams.asObject().get("url")) {
            if (url.asString().getValue().contains("sse")) {
                return MCPServerConfig.Sse(SseMCPInitParams.fromJsonValue(initParams))
            } else {
                return MCPServerConfig.Http(HttpMCPInitParams.fromJsonValue(initParams))
            }
        } else {
            return MCPServerConfig.Stdio(StdioMCPInitParams.fromJsonValue(initParams))
        }
    }

    override public func toJsonValue(): JsonValue {
        return match (this) {
            case Stdio(params) => params.toJsonValue()
            case Sse(params) => params.toJsonValue()
            case Http(params) => params.toJsonValue()
        }
    }
}

public class MCPConfigManager {
    /**
     * Server name -> Server init configs
     */
    private var mcpServers: HashMap<String, MCPServerConfig> = HashMap<String, MCPServerConfig>()

    /**
     * Server name -> its client
     */
    private var mcpClients: HashMap<String, MCPClient> = HashMap<String, MCPClient>()

    public init() {
        if (let Some(jo) <- CliSettingManager.setting.mcpServers) {
            for ((serverName, initParams) in jo.getFields()) {
                try {
                    let config = MCPServerConfig.fromJsonValue(initParams)
                    this.mcpServers[serverName] = config
                } catch (ex: JsonException) {
                    LogUtils.info("Invalid server config format for: ${serverName}")
                } catch (ex: JsonableException) {
                    LogUtils.info("Invalid server config format for: ${serverName}")
                }
            }
        }
    }

    public func loadMCPServers(): Array<Tool> {
        let tools = ArrayList<Tool>()

        for ((serverName, config) in this.mcpServers) {
            tools.add(all: this.loadMCPServer(serverName, config))
        }

        return tools.toArray()
    }

    private func loadMCPServer(serverName: String, serverConfig: MCPServerConfig): Array<Tool> {
        let client: MCPClient = match (serverConfig) {
            case Stdio(initParam) =>
                var fullCommand = initParam.command
                if (!initParam.args.isEmpty()) {
                    fullCommand = "${initParam.command} ${String.join(initParam.args, delimiter: " ")}"
                }
                // Windows use cmd /c to wrap the command
                let finalCommand = if (InfoUtils.os == "windows") {
                    "cmd /c \"${fullCommand}\""
                } else {
                    fullCommand
                }
                LogUtils.info("Creating Stdio MCP client for ${serverName} with command: ${finalCommand}")
                StdioMCPClient(finalCommand, env: initParam.env.toArray())
            case Sse(initParam) =>
                LogUtils.info("Creating SSE MCP client for ${serverName} with URL: ${initParam.url}")
                SseMCPClient(initParam.url)
            case Http(initParam) =>
                LogUtils.info("Creating HTTP MCP client for ${serverName} with URL: ${initParam.url}")
                HttpMCPClient(initParam.url, headers: initParam.header.toArray())
        }

        let tools = ArrayList<Tool>()
        for (tool in client.tools) {
            tools.add(MCPToolWrapper(serverName, tool))
        }
        this.mcpClients[serverName] = client
        LogUtils.info("Successfully loaded MCP server: ${serverName}")

        return tools.toArray()
    }

    public func showLoadedMCPTools(agent: Agent): Unit {
        PrintUtils.printProcedure("MCP Servers and Tools", "🔌 Total MCP tools loaded: ")

        if (this.mcpClients.isEmpty()) {
            PrintUtils.printLine("No MCP servers currently loaded")
            return
        }

        var totalMcpTools = 0
        for ((serverName, client) in this.mcpClients) {
            let serverType = match (this.mcpServers.get(serverName)) {
                case Some(config) => match (config) {
                    case Stdio(_) => "Stdio"
                    case Sse(_) => "SSE"
                    case Http(_) => "HTTP"
                }
                case _ => "Unknown"
            }

            let tools = client.tools
            PrintUtils.printLine("📡 ${serverName} (${serverType}) - ${tools.size} tools:")
            for (tool in tools) {
                PrintUtils.printLine("  • ${tool.name}")
            }
            totalMcpTools += tools.size
            PrintUtils.printLine("")
        }

        PrintUtils.printLine("Total MCP tools: ${totalMcpTools}")
    }

    private func parseArgsAndEnv(parts: Array<String>, startIndex!: Int64): (Array<String>, Array<(String, String)>) {
        let args = ArrayList<String>()
        let envVars = ArrayList<(String, String)>()

        var foundEnv = false
        for (i in startIndex..parts.size) {
            if (parts[i] == "--env") {
                foundEnv = true
                continue
            }

            if (foundEnv) {
                // Parse environment variable KEY=VALUE
                if (let Some(eqIndex) <- parts[i].indexOf("=")) {
                    let runes = parts[i].toRuneArray()
                    let keyRunes = Array<Rune>(Int64(eqIndex), {idx => runes[idx]})
                    let valueRunes = Array<Rune>(runes.size - Int64(eqIndex) - 1, {idx => runes[idx + Int64(eqIndex) + 1]})
                    let key = String(keyRunes)
                    let value = String(valueRunes)
                    envVars.add((key, value))
                }
            } else {
                args.add(parts[i])
            }
        }

        return (args.toArray(), envVars.toArray())
    }

    public func handleCommand(parts: Array<String>, agent: Agent): Unit {
        if (parts.size == 1) {
            // Just "/mcp" or "mcp" - show current loaded tools
            showLoadedMCPTools(agent)
            return
        }
        // parts[1] is add or remove mcp server command
        match (parts[1]) {
            case "add" =>
                if (parts.size < 4) {
                    PrintUtils.printLine("Usage: /mcp add <name> <command> [args...] [--env KEY=VALUE ...]")
                    PrintUtils.printLine("Example: /mcp add myserver npx @some/mcp-server")
                    PrintUtils.printLine("Example: /mcp add myserver uvx myserver-mcp --env ENV_API_KEY=your_key")
                    return
                }
                let (args, envVars) = this.parseArgsAndEnv(parts, startIndex: 4)
                // parts[2] is server name, parts[3] is command
                addStdioServer(parts[2], parts[3], args, envVars)
            case "add-sse" =>
                if (parts.size != 4) {
                    PrintUtils.printLine("Usage: /mcp add-sse <name> <url>")
                    PrintUtils.printLine("Example: /mcp add-sse myserver http://localhost:3000/sse")
                    return
                }
                // parts[2] is server name, parts[3] is url
                addSseServer(parts[2], parts[3])
            case "remove" =>
                if (parts.size != 3) {
                    PrintUtils.printLine("Usage: /mcp remove <name>")
                    PrintUtils.printLine("Example: /mcp remove myserver")
                    return
                }
                // parts[2] is server name
                removeServer(parts[2])
            case "list" =>
                showLoadedMCPTools(agent)
            case _ =>
                PrintUtils.printLine("Unknown MCP command: ${parts[1]}")
                PrintUtils.printLine("Available commands:")
                PrintUtils.printLine("  add      - Add a new stdio MCP server")
                PrintUtils.printLine("  add-sse  - Add a new SSE MCP server")
                PrintUtils.printLine("  remove   - Remove an existing MCP server")
                PrintUtils.printLine("  list     - List all loaded MCP servers")
        }
    }

    /**
     * Add SSE type MCP server
     */
    public func addSseServer(name: String, url: String): Bool {
        try {
            PrintUtils.printLine("🔧 Adding SSE MCP server '${name}' with URL '${url}'")

            if (serverExists(name)) {
                PrintUtils.printLine("❌ MCP server '${name}' already exists. Use '/mcp remove ${name}' first to replace it.")
                return false
            }

            // Add to mcpServers
            let config = MCPServerConfig.Sse(
                SseMCPInitParams(url: url)
            )
            if (this.addServer(name, config)) {
                PrintUtils.printLine("✅ Added SSE MCP server: ${name}")
                PrintUtils.printLine("   URL: ${url}")
                PrintUtils.printLine("Note: Restart the CLI to load the new SSE MCP server")
                return true
            }
            return false
        } catch (ex: Exception) {
            LogUtils.error("Failed to add SSE MCP server '${name}': ${ex}")
            PrintUtils.printLine("❌ Failed to add SSE MCP server: ${ex.message}")
            return false
        }
    }

    /**
     * Add stdio type MCP server
     */
    public func addStdioServer(name: String, command: String, args: Array<String>, env: Array<(String, String)>): Bool {
        try {
            PrintUtils.printLine("🔧 Adding stdio MCP server '${name}' with command '${command}'")

            if (serverExists(name)) {
                PrintUtils.printLine("❌ MCP server '${name}' already exists. Use '/mcp remove ${name}' first to replace it.")
                return false
            }

            // Add to mcpServers
            let config = MCPServerConfig.Stdio(
                StdioMCPInitParams(command: command, args: args, env: HashMap(env))
            )
            if (this.addServer(name, config)) {
                PrintUtils.printLine("✅ Added stdio MCP server: ${name}")
                PrintUtils.printLine("   Command: ${command}")
                if (!args.isEmpty()) {
                    PrintUtils.printLine("   Args: ${String.join(args, delimiter: " ")}")
                }
                if (!env.isEmpty()) {
                    PrintUtils.printLine("   Env vars: ${env.size} variables")
                    for ((key, value) in env) {
                        PrintUtils.printLine("     ${key}=${value}")
                    }
                }
                PrintUtils.printLine("Note: Restart the CLI to load the new MCP server")
                return true
            }
            return false
        } catch (ex: Exception) {
            LogUtils.error("Failed to add stdio MCP server '${name}': ${ex}")
            PrintUtils.printLine("❌ Failed to add stdio MCP server: ${ex.message}")
            return false
        }
    }

    /**
     * Remove an existing MCP server configuration
     */
    public func removeServer(name: String): Bool {
        try {
            PrintUtils.printLine("🔧 Removing MCP server '${name}'")

            // Check if server exists
            if (!serverExists(name)) {
                PrintUtils.printLine("❌ MCP server '${name}' not found")
                return false
            }

            // Update config
            this.mcpServers.remove(name)
            if (MetisConfigManager.setMcpServers(Some(this.mcpServers.toJsonValue().asObject())).isSome()) {
                PrintUtils.printLine("✅ Removed MCP server: ${name}")
                PrintUtils.printLine("Note: Restart the CLI to unload the removed MCP server")
                return true
            }
            return false
        } catch (ex: Exception) {
            LogUtils.error("Failed to remove MCP server '${name}': ${ex}")
            PrintUtils.printLine("❌ Failed to remove MCP server: ${ex.message}")
            return false
        }
    }

    /**
     * Check if a server with given name exists
     */
    private func serverExists(name: String): Bool {
        for ((serverName, _) in this.mcpServers) {
            if (serverName == name) {
                return true
            }
        }
        return false
    }

    private func addServer(name: String, config: MCPServerConfig): Bool {
        this.mcpServers.add(name, config)
        // this.loadMCPServer(config)
        return MetisConfigManager.setMcpServers(Some(this.mcpServers.toJsonValue().asObject())).isSome()
    }
}

public func mcpConfiguredServersJson(): JsonObject {
    match (CliSettingManager.setting.mcpServers) {
        case Some(obj) => obj
        case None => JsonObject()
    }
}

public func mcpConfiguredServerJson(name: String): Option<JsonValue> {
    let key = name.trimAscii()
    if (key.isEmpty()) {
        return None<JsonValue>
    }
    mcpConfiguredServersJson().get(key)
}

public func mcpConfiguredServersPath(): String {
    MetisPaths.configPath().toString()
}

public func mcpSetConfiguredServerJson(name: String, value: JsonValue): (Bool, String) {
    let key = name.trimAscii()
    if (key.isEmpty()) {
        return (false, "MCP server name must be non-empty.")
    }
    try {
        MCPServerConfig.fromJsonValue(value)
    } catch (e: Exception) {
        return (false, "Invalid MCP server config: ${e.message}")
    }
    let obj = mcpConfiguredServersJson()
    obj.put(key, value)
    if (MetisConfigManager.setMcpServers(Some(obj)).isSome()) {
        return (true, "")
    }
    (false, "Failed to save MCP server config.")
}

public func mcpUnsetConfiguredServerJson(name: String): (Bool, Bool, String) {
    let key = name.trimAscii()
    if (key.isEmpty()) {
        return (false, false, "MCP server name must be non-empty.")
    }
    let manager = MCPConfigManager()
    match (mcpConfiguredServerJson(key)) {
        case Some(_) => ()
        case None => return (true, false, "")
    }
    if (manager.removeServer(key)) {
        return (true, true, "")
    }
    (false, false, "Failed to remove MCP server config.")
}
