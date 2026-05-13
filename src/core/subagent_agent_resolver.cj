package metis.core

import magic.prelude.*

import metis.core.config.{CliConfig, MetisConfigManager}
import metis.utils.loadMarkdown

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Path, exists}
import stdx.encoding.json.{JsonArray, JsonObject}

public class GatewaySubagentAgentSpec {
    public var found: Bool = false
    public var agentId: String = ""
    public var source: String = ""
    public var agentDir: String = ""
    public var name: String = ""
    public var description: String = ""
    public var model: String = ""
    public var tools: Array<String> = []
    public var background: Bool = true
    public var isolation: String = ""
    public var maxTurns: Int64 = -1
    public var error: String = ""

    public init() {}
}

private func gatewaySubagentNormalizeAgentLookupId(value: String): String {
    value.trimAscii().toAsciiLower().replace("-", "_").replace(" ", "_")
}

private func gatewaySubagentMetadataString(metadata: HashMap<String, String>, key: String): String {
    match (metadata.get(key)) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
}

private func gatewaySubagentJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewaySubagentConfigEntries(): JsonArray {
    MetisConfigManager.initializeIfMissing()
    match (MetisConfigManager.rawConfig()) {
        case Some(root) =>
            try {
                let agents = root.get("agents").getOrThrow().asObject()
                agents.get("list").getOrThrow().asArray()
            } catch (_e: Exception) {
                JsonArray([])
            }
        case None => JsonArray([])
    }
}

private func gatewaySubagentParseBool(value: String, defaultValue: Bool): Bool {
    match (value.trimAscii().toAsciiLower()) {
        case "true" | "yes" | "1" | "on" => true
        case "false" | "no" | "0" | "off" => false
        case _ => defaultValue
    }
}

private func gatewaySubagentParseCsv(value: String): Array<String> {
    let out = ArrayList<String>()
    for (part in value.split(",")) {
        let item = part.trimAscii()
        if (!item.isEmpty()) {
            out.add(item)
        }
    }
    out.toArray()
}

private func gatewaySubagentCustomAgentMatches(requested: String, agentDir: Path, name: String, id: String, agentId: String): Bool {
    let normalized = gatewaySubagentNormalizeAgentLookupId(requested)
    if (normalized.isEmpty()) {
        return false
    }
    let candidates = [
        id,
        agentId,
        name,
        agentDir.fileName
    ]
    for (candidate in candidates) {
        if (gatewaySubagentNormalizeAgentLookupId(candidate) == normalized) {
            return true
        }
    }
    false
}

private func gatewaySubagentCustomSpec(agentDir: Path, requestedAgentId: String, resolvedAgentId!: String = ""): GatewaySubagentAgentSpec {
    let spec = GatewaySubagentAgentSpec()
    let (metadata, _) = loadMarkdown(agentDir.join("AGENT.md"))
    let metadataName = gatewaySubagentMetadataString(metadata, "name")
    let metadataId = gatewaySubagentMetadataString(metadata, "id")
    let metadataAgentId = gatewaySubagentMetadataString(metadata, "agentId")
    let fallbackAgentId = if (!resolvedAgentId.trimAscii().isEmpty()) {
        resolvedAgentId.trimAscii()
    } else {
        requestedAgentId.trimAscii()
    }
    spec.found = true
    spec.source = "custom"
    spec.agentDir = agentDir.toString()
    spec.agentId = if (!metadataAgentId.isEmpty()) {
        metadataAgentId
    } else if (!metadataId.isEmpty()) {
        metadataId
    } else if (!fallbackAgentId.isEmpty()) {
        fallbackAgentId
    } else {
        metadataName
    }
    spec.name = if (!metadataName.isEmpty()) { metadataName } else { spec.agentId }
    spec.description = gatewaySubagentMetadataString(metadata, "description")
    spec.model = gatewaySubagentMetadataString(metadata, "model")
    spec.tools = gatewaySubagentParseCsv(gatewaySubagentMetadataString(metadata, "tools"))
    spec.background = gatewaySubagentParseBool(gatewaySubagentMetadataString(metadata, "background"), true)
    spec.isolation = gatewaySubagentMetadataString(metadata, "isolation")
    let maxTurnsText = gatewaySubagentMetadataString(metadata, "maxTurns")
    if (!maxTurnsText.isEmpty()) {
        spec.maxTurns = try { Int64.parse(maxTurnsText) } catch (_: Exception) { -1 }
    }
    spec
}

public func gatewaySubagentResolveAgent(agentId: String): GatewaySubagentAgentSpec {
    let requested = agentId.trimAscii()
    let builtin = gatewaySubagentNormalizeBuiltinAgentId(requested)
    if (gatewaySubagentIsBuiltinAgent(builtin)) {
        let spec = GatewaySubagentAgentSpec()
        spec.found = true
        spec.agentId = builtin
        spec.source = "builtin"
        spec.name = builtin
        spec.description = gatewaySubagentBuiltinRolePrompt(builtin)
        spec.background = true
        return spec
    }

    let entries = gatewaySubagentConfigEntries()
    for (i in 0..entries.size()) {
        let entry = try { entries[i].asObject() } catch (_e: Exception) { JsonObject() }
        let configuredId = gatewaySubagentJsonString(entry, "id")
        let configuredName = gatewaySubagentJsonString(entry, "name")
        let agentDirText = gatewaySubagentJsonString(entry, "agentDir")
        if (configuredId.isEmpty() || agentDirText.isEmpty()) {
            continue
        }
        let configuredAgentDir = Path(agentDirText)
        let agentMd = configuredAgentDir.join("AGENT.md")
        if (!exists(agentMd)) {
            continue
        }
        let (metadata, _) = loadMarkdown(agentMd)
        let name = gatewaySubagentMetadataString(metadata, "name")
        let id = gatewaySubagentMetadataString(metadata, "id")
        let metadataAgentId = gatewaySubagentMetadataString(metadata, "agentId")
        if (
            gatewaySubagentNormalizeAgentLookupId(requested) == gatewaySubagentNormalizeAgentLookupId(configuredId) ||
            gatewaySubagentNormalizeAgentLookupId(requested) == gatewaySubagentNormalizeAgentLookupId(configuredName) ||
            gatewaySubagentCustomAgentMatches(requested, configuredAgentDir, name, id, metadataAgentId)
        ) {
            return gatewaySubagentCustomSpec(configuredAgentDir, requested, resolvedAgentId: configuredId)
        }
    }

    for (agentDir in CliConfig.subagentDirs) {
        var resolvedAgentDir = agentDir
        var resolvedAgentId = agentDir.fileName
        var agentMd = resolvedAgentDir.join("AGENT.md")
        if (!exists(agentMd)) {
            let nested = agentDir.join("agent")
            let nestedManifest = nested.join("AGENT.md")
            if (exists(nestedManifest)) {
                resolvedAgentDir = nested
                resolvedAgentId = agentDir.fileName
                agentMd = nestedManifest
            }
        }
        if (!exists(agentMd)) {
            continue
        }
        let (metadata, _) = loadMarkdown(agentMd)
        let name = gatewaySubagentMetadataString(metadata, "name")
        let id = gatewaySubagentMetadataString(metadata, "id")
        let metadataAgentId = gatewaySubagentMetadataString(metadata, "agentId")
        if (
            gatewaySubagentNormalizeAgentLookupId(requested) == gatewaySubagentNormalizeAgentLookupId(resolvedAgentId) ||
            gatewaySubagentCustomAgentMatches(requested, resolvedAgentDir, name, id, metadataAgentId)
        ) {
            return gatewaySubagentCustomSpec(resolvedAgentDir, requested, resolvedAgentId: resolvedAgentId)
        }
    }

    let missing = GatewaySubagentAgentSpec()
    missing.agentId = if (requested.isEmpty()) { builtin } else { requested }
    missing.error = "unknown subagent agent: ${missing.agentId}"
    missing
}

public func gatewaySubagentBuildCustomPrompt(task: String, cwd: String, sessionKey: String, spec: GatewaySubagentAgentSpec): String {
    let lines = ArrayList<String>()
    lines.add("Custom subagent: ${spec.name}")
    if (!spec.description.trimAscii().isEmpty()) {
        lines.add("Description: ${spec.description.trimAscii()}")
    }
    lines.add("Project path: ${cwd.trimAscii()}")
    lines.add("Session key: ${sessionKey.trimAscii()}")
    lines.add("")
    lines.add("Task:")
    lines.add(task.trimAscii())
    String.join(lines.toArray(), delimiter: "\n")
}
