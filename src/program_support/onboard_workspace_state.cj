package metis.program_support

import metis.core.config.MetisPaths

import stdx.encoding.json.JsonObject

private func supportEnsureObject(root: JsonObject, key: String): JsonObject {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asObject()
            } catch (_e: Exception) {
                let obj = JsonObject()
                root.put(key, obj)
                obj
            }
        case None =>
            let obj = JsonObject()
            root.put(key, obj)
            obj
    }
}

private func supportReadString(root: JsonObject, key: String): String {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asString().getValue()
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func supportNormalizeWorkspacePath(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return MetisPaths.workspaceRoot().toString()
    }
    if (trimmed == "~" || trimmed == "~/" || trimmed == "~/.") {
        return MetisPaths.workspaceRoot().toString()
    }
    trimmed
}

public func programSupportOnboardWorkspacePromptState(root: JsonObject): (String, String, String, Bool) {
    let agents = supportEnsureObject(root, "agents")
    let defaults = supportEnsureObject(agents, "defaults")
    let currentDirectory = supportNormalizeWorkspacePath(MetisPaths.workspaceRoot().toString())
    let configuredWorkspace = supportReadString(defaults, "workspace").trimAscii()
    let normalizedConfigured = if (configuredWorkspace.isEmpty()) {
        ""
    } else {
        supportNormalizeWorkspacePath(configuredWorkspace)
    }
    let effectiveWorkspace = if (normalizedConfigured.isEmpty()) {
        currentDirectory
    } else {
        normalizedConfigured
    }
    let showConfiguredOption = !normalizedConfigured.isEmpty() && normalizedConfigured != currentDirectory
    (currentDirectory, normalizedConfigured, effectiveWorkspace, showConfiguredOption)
}
