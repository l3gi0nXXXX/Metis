package metis.gateway.core

import magic.jsonable.*

import metis.core.config.{MetisAgentScope, MetisPaths}

import std.collection.ArrayList
import std.fs.{File, Path, exists}
import std.regex.Regex
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private func teamString(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func teamBool(obj: JsonObject, key: String, fallback!: Bool = false): Bool {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func teamObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func teamArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func teamCloneObject(obj: JsonObject): JsonObject {
    try {
        JsonValue.fromStr(obj.toJsonString()).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

private func teamPathText(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    try {
        Path(trimmed).normalize().toString()
    } catch (_: Exception) {
        trimmed
    }
}

private func teamNormalizeAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return "default"
    }
    if (trimmed == "*") {
        return "*"
    }
    var value = Regex("[^a-z0-9_-]+").replaceAll(trimmed.toAsciiLower(), "-")
    value = Regex("^-+").replaceAll(value, "")
    value = Regex("-+$").replaceAll(value, "")
    if (value.size > 64) {
        value = value[..64]
    }
    if (value.isEmpty() || value == "__proto__" || value == "prototype" || value == "constructor") {
        return "default"
    }
    value
}

private func teamHasString(values: ArrayList<String>, value: String): Bool {
    for (i in 0..values.size) {
        if (values[i] == value) {
            return true
        }
    }
    false
}

private func teamAddUniqueString(values: ArrayList<String>, value: String): Unit {
    let normalized = value.trimAscii()
    if (!normalized.isEmpty() && !teamHasString(values, normalized)) {
        values.add(normalized)
    }
}

private func teamStringListJson(values: ArrayList<String>): JsonArray {
    let out = JsonArray([])
    for (i in 0..values.size) {
        out.add(JsonString(values[i]))
    }
    out
}

private func teamObjectArrayJson(values: Array<JsonObject>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(teamCloneObject(value))
    }
    out
}

private func teamFinding(
    code: String,
    severity: String,
    path: String,
    reason: String,
    impact: String,
    suggestion: String,
    agentId!: String = "",
    channel!: String = "",
    accountId!: String = "",
    manual!: Bool = true,
    writeTarget!: String = ""
): JsonObject {
    let out = JsonObject()
    out.put("code", JsonString(code))
    out.put("severity", JsonString(severity))
    out.put("path", JsonString(path))
    out.put("agentId", JsonString(agentId.trimAscii()))
    out.put("channel", JsonString(channel.trimAscii()))
    out.put("accountId", JsonString(accountId.trimAscii()))
    out.put("reason", JsonString(reason))
    out.put("impact", JsonString(impact))
    out.put("suggestion", JsonString(suggestion))
    out.put("manual", JsonBool(manual))
    out.put("writeTarget", JsonString(writeTarget.trimAscii()))
    return out
}

private func teamAddFinding(
    findings: JsonArray,
    code: String,
    severity: String,
    path: String,
    reason: String,
    impact: String,
    suggestion: String,
    agentId!: String = "",
    channel!: String = "",
    accountId!: String = "",
    manual!: Bool = true,
    writeTarget!: String = ""
): Unit {
    findings.add(teamFinding(code, severity, path, reason, impact, suggestion, agentId: agentId, channel: channel,
        accountId: accountId, manual: manual, writeTarget: writeTarget))
}

private func teamAgentIds(summary: JsonObject): ArrayList<String> {
    let ids = ArrayList<String>()
    let agents = teamArray(summary, "agents")
    for (i in 0..agents.size()) {
        let agent = try { agents[i].asObject() } catch (_: Exception) { JsonObject() }
        teamAddUniqueString(ids, teamString(agent, "agentId"))
    }
    return ids
}

private func teamAgentExists(ids: ArrayList<String>, rawAgentId: String): Bool {
    teamHasString(ids, MetisAgentScope.normalizeAgentId(rawAgentId))
}

private func teamMapScopeDiagnostic(findings: JsonArray, diagnostic: JsonObject): Unit {
    let code = teamString(diagnostic, "code")
    let agentId = teamString(diagnostic, "agentId")
    match (code) {
        case "multiple-default-agents" =>
            teamAddFinding(findings, "agent-team-multiple-default", "warning", "agents.list",
                teamString(diagnostic, "message", fallback: "Multiple agents are marked default=true."),
                "Default route fallback can pick the wrong agent.",
                "Keep exactly one default=true agent.", agentId: agentId)
        case "duplicate-agent-id" =>
            teamAddFinding(findings, "agent-team-duplicate-agent-id", "error", "agents.list",
                teamString(diagnostic, "message", fallback: "Duplicate agent id after normalization."),
                "One agent entry is ignored by scope resolution.",
                "Rename the duplicate agentId before enabling AgentTeam.", agentId: agentId)
        case "invalid-agent-id" =>
            teamAddFinding(findings, "agent-team-invalid-agent-id", "warning", "agents.list",
                teamString(diagnostic, "message", fallback: "Agent id is normalized before use."),
                "Runtime paths and bindings use the normalized id, not the raw id.",
                "Rename the agent id to its normalized value explicitly.", agentId: agentId)
        case "path-escape" =>
            teamAddFinding(findings, "agent-team-path-escape", "error", "agents",
                teamString(diagnostic, "message", fallback: "Agent path escapes its configured boundary."),
                "Workspace or agent runtime state can escape the expected root.",
                "Move the path under the configured workspace/state root.", agentId: agentId)
        case "dangerous-path" =>
            teamAddFinding(findings, "agent-team-dangerous-path", "error", "agents",
                teamString(diagnostic, "message", fallback: "Agent path resolves to a dangerous location."),
                "Runtime writes could target an unsafe location.",
                "Use an agent-specific directory under the Metis state root.", agentId: agentId)
        case "workspace-agentdir-overlap" =>
            teamAddFinding(findings, "agent-team-workspace-agentdir-overlap", "warning", "agents",
                teamString(diagnostic, "message", fallback: "workspaceDir and agentDir overlap."),
                "Runtime state, models, auth, and workspace files may be mixed.",
                "Keep agentDir outside workspaceDir.", agentId: agentId)
        case "identity-avatar-invalid" =>
            teamAddFinding(findings, "agent-team-identity-avatar-invalid", "warning", "agents.list[].identity.avatar",
                teamString(diagnostic, "message", fallback: "identity.avatar has an unsupported path or scheme."),
                "Control UI cannot safely render or resolve the avatar.",
                "Use a workspace-relative path, http(s) URL, or data URI.", agentId: agentId)
        case "identity-avatar-escape" =>
            teamAddFinding(findings, "agent-team-identity-avatar-escape", "error", "agents.list[].identity.avatar",
                teamString(diagnostic, "message", fallback: "identity.avatar escapes workspaceDir."),
                "Agent identity can reference files outside the workspace boundary.",
                "Move the avatar under the agent workspace or use a URL/data URI.", agentId: agentId)
        case _ => ()
    }
}

private func teamScanScopeDiagnostics(findings: JsonArray, summary: JsonObject): Unit {
    let diagnostics = teamArray(summary, "diagnostics")
    for (i in 0..diagnostics.size()) {
        let diagnostic = try { diagnostics[i].asObject() } catch (_: Exception) { JsonObject() }
        teamMapScopeDiagnostic(findings, diagnostic)
    }
    let agents = teamArray(summary, "agents")
    for (i in 0..agents.size()) {
        let agent = try { agents[i].asObject() } catch (_: Exception) { JsonObject() }
        let agentDiagnostics = teamArray(agent, "diagnostics")
        for (j in 0..agentDiagnostics.size()) {
            let diagnostic = try { agentDiagnostics[j].asObject() } catch (_: Exception) { JsonObject() }
            teamMapScopeDiagnostic(findings, diagnostic)
        }
    }
}

private func teamScanDuplicatePaths(findings: JsonArray, summary: JsonObject, field: String, code: String,
    label: String): Unit {
    let agents = teamArray(summary, "agents")
    for (i in 0..agents.size()) {
        let left = try { agents[i].asObject() } catch (_: Exception) { JsonObject() }
        let leftPath = teamPathText(teamString(left, field))
        if (leftPath.isEmpty()) {
            continue
        }
        for (j in i + 1..agents.size()) {
            let right = try { agents[j].asObject() } catch (_: Exception) { JsonObject() }
            let rightPath = teamPathText(teamString(right, field))
            if (leftPath == rightPath) {
                teamAddFinding(findings, code, "warning", "agents.list[].${field}",
                    "Multiple agents resolve to the same ${label}: ${leftPath}.",
                    "AgentTeam isolation expects each agent to own separate ${label}.",
                    "Split the ${label} or explicitly document the shared boundary.",
                    agentId: "${teamString(left, "agentId")},${teamString(right, "agentId")}")
            }
        }
    }
}

private func teamScanJsonFile(findings: JsonArray, pathText: String, agentId: String, missingCode: String,
    invalidCode: String, label: String): Unit {
    if (pathText.trimAscii().isEmpty()) {
        return
    }
    let path = Path(pathText)
    if (!exists(path)) {
        teamAddFinding(findings, missingCode, "warning", pathText,
            "${label} is missing for agent ${agentId}.",
            "The agent may fall back to shared model/auth settings instead of a per-agent view.",
            "Create ${label} under the agentDir or record an explicit shared configuration decision.",
            agentId: agentId)
        return
    }
    try {
        let _ = JsonValue.fromStr(String.fromUtf8(File.readFrom(path)))
    } catch (_: Exception) {
        teamAddFinding(findings, invalidCode, "error", pathText,
            "${label} exists but is not valid JSON.",
            "The agent-specific model/auth view cannot be loaded deterministically.",
            "Fix the JSON syntax or regenerate the per-agent file in a temporary migration run.",
            agentId: agentId)
    }
}

private func teamPolicyEnabled(raw: JsonObject, key: String): Bool {
    let policy = teamObject(raw, key)
    if (policy.size() == 0) {
        return false
    }
    if (teamBool(policy, "enabled", fallback: false)) {
        return true
    }
    let extraCollections = teamArray(policy, "extraCollections")
    let extraPaths = teamArray(policy, "extraPaths")
    extraCollections.size() > 0 || extraPaths.size() > 0
}

private func teamSubagentsWide(raw: JsonObject): Bool {
    let policy = teamObject(raw, "subagents")
    if (policy.size() == 0) {
        return false
    }
    let allowAgents = teamArray(policy, "allowAgents")
    allowAgents.size() == 0
}

private func teamScanAgentFilesAndPolicies(findings: JsonArray, summary: JsonObject, homeRoot: Path): Unit {
    let agents = teamArray(summary, "agents")
    let multiAgent = agents.size() > 1
    for (i in 0..agents.size()) {
        let agent = try { agents[i].asObject() } catch (_: Exception) { JsonObject() }
        let agentId = teamString(agent, "agentId")
        let agentDir = teamPathText(teamString(agent, "agentDir"))
        let legacyDir = teamPathText(homeRoot.join("agents").join(agentId).toString())
        if (!agentDir.isEmpty() && agentDir == legacyDir) {
            teamAddFinding(findings, "agent-team-legacy-agent-dir", "warning", "agents.list[].agentDir",
                "Agent ${agentId} uses the legacy agent root as agentDir: ${agentDir}.",
                "New AgentTeam agents should keep runtime config in <state>/agents/<agentId>/agent.",
                "Move per-agent models/auth under ${legacyDir}/agent and keep the old root read-only until migrated.",
                agentId: agentId)
        }
        teamScanJsonFile(findings, teamString(agent, "modelsJsonPath"), agentId, "agent-team-models-missing",
            "agent-team-models-invalid", "models.json")
        teamScanJsonFile(findings, teamString(agent, "authProfilesPath"), agentId, "agent-team-auth-profiles-missing",
            "agent-team-auth-profiles-invalid", "auth-profiles.json")
        let accountSummary = teamObject(agent, "accountSummary")
        let credentialSource = teamString(accountSummary, "source")
        let credentialStatus = teamString(accountSummary, "status")
        let modelRef = teamString(agent, "modelRef")
        if (!modelRef.isEmpty() && credentialStatus != "configured") {
            teamAddFinding(findings, "agent-team-provider-credential-missing", "warning", "agents.list[].model",
                "Agent ${agentId} model ${modelRef} has no configured provider credential in its source chain.",
                "The agent cannot use its configured model unless a later runtime injects credentials.",
                "Configure ${teamString(agent, "authProfilesPath")} or ${teamString(agent, "modelsJsonPath")} for this agent.",
                agentId: agentId)
        } else if (credentialSource.startsWith("models.providers.")) {
            teamAddFinding(findings, "agent-team-provider-credential-global-fallback", "notice", "models.providers",
                "Agent ${agentId} model ${modelRef} uses a global provider credential source.",
                "This preserves compatibility but is not an isolated per-agent credential view.",
                "Move the provider credential into the agentDir auth-profiles.json or models.json when isolation is required.",
                agentId: agentId)
        } else if (credentialSource.startsWith("env.")) {
            teamAddFinding(findings, "agent-team-provider-credential-env-fallback", "notice", "env",
                "Agent ${agentId} model ${modelRef} uses shell environment credential fallback.",
                "Environment fallback is process-wide and not isolated per agent.",
                "Prefer explicit per-agent auth-profiles.json for AgentTeam credentials.",
                agentId: agentId)
        }
        let legacyAuthPath = teamString(agent, "legacyAuthPath")
        if (!legacyAuthPath.trimAscii().isEmpty() && exists(Path(legacyAuthPath))) {
            teamAddFinding(findings, "agent-team-legacy-auth-json", "notice", legacyAuthPath,
                "Legacy auth.json exists under agentDir for agent ${agentId}.",
                "Metis keeps the file for compatibility but should not use it as the new AgentTeam auth target.",
                "Migrate explicit auth profiles to auth-profiles.json in a dry-run/temp migration first.",
                agentId: agentId, manual: true)
        }
        let raw = teamObject(agent, "raw")
        if (multiAgent && teamPolicyEnabled(raw, "memorySearch")) {
            teamAddFinding(findings, "agent-team-memory-cross-agent", "warning", "agents.list[].memorySearch",
                "memorySearch is enabled while multiple agents are configured.",
                "Search collections can become a cross-agent shared memory boundary.",
                "Add explicit per-agent memory collections or mark the sharing decision in config.",
                agentId: agentId)
        }
        if (teamSubagentsWide(raw)) {
            teamAddFinding(findings, "agent-team-subagent-wide", "warning", "agents.list[].subagents",
                "subagents is configured without allowAgents.",
                "The agent can delegate more broadly than the AgentTeam boundary expects.",
                "Set subagents.allowAgents to the intended member agents.",
                agentId: agentId)
        }
    }
}

private func teamChannelObject(root: JsonObject, channel: String): JsonObject {
    teamObject(teamObject(root, "channels"), channel)
}

private func teamChannelAccounts(root: JsonObject, channel: String): ArrayList<String> {
    let out = ArrayList<String>()
    let channelObj = teamChannelObject(root, channel)
    let accountIds = teamArray(channelObj, "accountIds")
    for (i in 0..accountIds.size()) {
        try {
            teamAddUniqueString(out, teamNormalizeAccountId(accountIds[i].asString().getValue()))
        } catch (_: Exception) {
            ()
        }
    }
    let accounts = teamArray(channelObj, "accounts")
    for (i in 0..accounts.size()) {
        let account = try { accounts[i].asObject() } catch (_: Exception) { JsonObject() }
        if (!teamBool(account, "enabled", fallback: true)) {
            continue
        }
        let id = if (!teamString(account, "accountId").isEmpty()) {
            teamString(account, "accountId")
        } else {
            teamString(account, "id")
        }
        teamAddUniqueString(out, teamNormalizeAccountId(id))
    }
    let defaultAccount = teamString(channelObj, "defaultAccountId")
    if (!defaultAccount.isEmpty()) {
        teamAddUniqueString(out, teamNormalizeAccountId(defaultAccount))
    }
    return out
}

private func teamBindingMatch(binding: JsonObject): JsonObject {
    let matchObj = teamObject(binding, "match")
    if (matchObj.size() > 0) {
        return matchObj
    }
    let legacy = JsonObject()
    let channel = teamString(binding, "channel")
    if (!channel.isEmpty()) {
        legacy.put("channel", JsonString(channel))
    }
    let accountId = teamString(binding, "accountId")
    if (!accountId.isEmpty()) {
        legacy.put("accountId", JsonString(accountId))
    }
    legacy
}

private func teamBindingType(binding: JsonObject): String {
    let typeName = teamString(binding, "type").toAsciiLower()
    if (typeName.isEmpty()) {
        return "route"
    }
    typeName
}

private func teamRouteBindingEnabled(binding: JsonObject): Bool {
    teamBindingType(binding) == "route" && teamBool(binding, "enabled", fallback: true)
}

private func teamBindingAgentId(binding: JsonObject): String {
    MetisAgentScope.normalizeAgentId(teamString(binding, "agentId"))
}

private func teamBindingAccount(binding: JsonObject): String {
    teamNormalizeAccountId(teamString(teamBindingMatch(binding), "accountId"))
}

private func teamBindingHasExplicitAccount(binding: JsonObject): Bool {
    !teamString(teamBindingMatch(binding), "accountId").isEmpty()
}

private func teamBindingKey(binding: JsonObject): String {
    let matchObj = teamBindingMatch(binding)
    let peer = teamObject(matchObj, "peer")
    let roles = teamArray(matchObj, "roles")
    var rolePart = ""
    for (i in 0..roles.size()) {
        try {
            let role = roles[i].asString().getValue().trimAscii().toAsciiLower()
            if (!role.isEmpty()) {
                if (!rolePart.isEmpty()) {
                    rolePart += ","
                }
                rolePart += role
            }
        } catch (_: Exception) {
            ()
        }
    }
    "${teamString(matchObj, "channel").toAsciiLower()}|${teamBindingAccount(binding)}|${teamString(peer, "kind").toAsciiLower()}|${teamString(peer, "id")}|${teamString(matchObj, "guildId")}|${teamString(matchObj, "teamId")}|${rolePart}"
}

private func teamScanBindings(findings: JsonArray, root: JsonObject, agentIds: ArrayList<String>): Unit {
    let bindings = teamArray(root, "bindings")
    for (i in 0..bindings.size()) {
        let binding = try { bindings[i].asObject() } catch (_: Exception) { JsonObject() }
        if (!teamRouteBindingEnabled(binding)) {
            continue
        }
        let agentId = teamBindingAgentId(binding)
        let matchObj = teamBindingMatch(binding)
        let channel = teamString(matchObj, "channel").toAsciiLower()
        if (!teamAgentExists(agentIds, agentId)) {
            teamAddFinding(findings, "agent-team-binding-unknown-agent", "error", "bindings.${i}.agentId",
                "Binding points to unknown agent ${agentId}.",
                "Messages matching this binding fall back to the default agent.",
                "Create the agent or update the binding agentId.",
                agentId: agentId, channel: channel)
        }
        if (!teamBindingHasExplicitAccount(binding) && teamChannelAccounts(root, channel).size > 1) {
            teamAddFinding(findings, "agent-team-binding-default-account-only", "warning", "bindings.${i}.match.accountId",
                "Binding omits accountId for a multi-account channel.",
                "Omitted accountId means the resolved default account, not every account.",
                "Use an explicit accountId for one bot or accountId=\"*\" for a deliberate channel-wide binding.",
                agentId: agentId, channel: channel)
        }
        for (j in i + 1..bindings.size()) {
            let other = try { bindings[j].asObject() } catch (_: Exception) { JsonObject() }
            if (!teamRouteBindingEnabled(other)) {
                continue
            }
            if (teamBindingKey(binding) != teamBindingKey(other)) {
                continue
            }
            if (teamBindingAgentId(binding) == teamBindingAgentId(other)) {
                teamAddFinding(findings, "agent-team-binding-duplicate", "notice", "bindings.${j}",
                    "Duplicate route binding with the same match and agent.",
                    "Binding apply will skip the duplicate.",
                    "Remove duplicate route bindings during a dry-run migration.",
                    agentId: teamBindingAgentId(other), channel: channel)
            } else {
                teamAddFinding(findings, "agent-team-binding-conflict", "error", "bindings.${j}",
                    "Route binding has the same match as an earlier binding but a different agent.",
                    "Resolver/apply cannot safely choose both agents for the same match.",
                    "Split the match by account, peer, topic, or team.",
                    agentId: teamBindingAgentId(other), channel: channel)
            }
        }
    }
}

private func teamChannelExplicitRouteAgents(root: JsonObject, channel: String, accounts: ArrayList<String>,
    unbound: ArrayList<String>, routeAgents: ArrayList<String>): Unit {
    let boundAccounts = ArrayList<String>()
    let bindings = teamArray(root, "bindings")
    var wildcardBound = false
    for (i in 0..bindings.size()) {
        let binding = try { bindings[i].asObject() } catch (_: Exception) { JsonObject() }
        if (!teamRouteBindingEnabled(binding)) {
            continue
        }
        let matchObj = teamBindingMatch(binding)
        if (teamString(matchObj, "channel").toAsciiLower() != channel) {
            continue
        }
        if (!teamBindingHasExplicitAccount(binding)) {
            continue
        }
        let account = teamBindingAccount(binding)
        if (account == "*") {
            wildcardBound = true
            teamAddUniqueString(routeAgents, teamBindingAgentId(binding))
            continue
        }
        teamAddUniqueString(boundAccounts, account)
        teamAddUniqueString(routeAgents, teamBindingAgentId(binding))
    }
    for (i in 0..accounts.size) {
        let account = accounts[i]
        if (!wildcardBound && !teamHasString(boundAccounts, account)) {
            unbound.add(account)
        }
    }
}

private func teamSessionDmScope(root: JsonObject): String {
    teamString(teamObject(root, "session"), "dmScope", fallback: "main").toAsciiLower()
}

private func teamScanMultiAccount(findings: JsonArray, root: JsonObject, statusRows: JsonArray): Unit {
    var emittedDmScope = false
    for (channel in ["telegram", "feishu", "lark", "qq"]) {
        let accounts = teamChannelAccounts(root, channel)
        if (accounts.size <= 1) {
            continue
        }
        let unbound = ArrayList<String>()
        let routeAgents = ArrayList<String>()
        teamChannelExplicitRouteAgents(root, channel, accounts, unbound, routeAgents)
        let status = JsonObject()
        status.put("channel", JsonString(channel))
        status.put("accounts", teamStringListJson(accounts))
        status.put("unboundAccounts", teamStringListJson(unbound))
        status.put("routeAgents", teamStringListJson(routeAgents))
        if (unbound.size > 0) {
            status.put("mode", JsonString("shared-implicit"))
            teamAddFinding(findings, "agent-team-multi-account-implicit-default", "warning", "channels.${channel}",
                "Multi-account channel ${channel} has accounts without explicit route bindings.",
                "Unbound accounts share the default agent and may share memory/session state.",
                "Add per-account bindings or an explicit shared accountId=\"*\" binding.",
                channel: channel, accountId: String.join(unbound.toArray(), delimiter: ","))
        } else if (routeAgents.size == 1) {
            status.put("mode", JsonString("shared-explicit"))
            status.put("sharedAgentId", JsonString(routeAgents[0]))
            teamAddFinding(findings, "agent-team-multi-account-explicit-shared", "notice", "bindings",
                "All ${channel} accounts are explicitly routed to the same agent ${routeAgents[0]}.",
                "This is a deliberate shared-agent configuration, not per-account isolation.",
                "Confirm this sharing boundary or split accounts across different agents.",
                agentId: routeAgents[0], channel: channel, manual: true)
        } else {
            status.put("mode", JsonString("isolated"))
        }
        statusRows.add(status)
        if (!emittedDmScope && teamSessionDmScope(root) != "per-account-channel-peer") {
            emittedDmScope = true
            teamAddFinding(findings, "agent-team-dm-scope-shared", "warning", "session.dmScope",
                "Multi-account direct messages are not scoped by account.",
                "The same user talking to different bots can reuse the same direct-message session.",
                "Set session.dmScope to \"per-account-channel-peer\" before enabling multi-bot AgentTeam.",
                channel: channel)
        }
    }
}

private func teamMemberAgentId(member: JsonValue): String {
    try {
        return MetisAgentScope.normalizeAgentId(member.asString().getValue())
    } catch (_: Exception) {
        ()
    }
    try {
        let obj = member.asObject()
        let id = if (!teamString(obj, "agentId").isEmpty()) { teamString(obj, "agentId") } else { teamString(obj, "id") }
        return MetisAgentScope.normalizeAgentId(id)
    } catch (_: Exception) {
        ()
    }
    ""
}

private func teamScanTeamArray(findings: JsonArray, teams: JsonArray, agentIds: ArrayList<String>, pathPrefix: String): Unit {
    for (i in 0..teams.size()) {
        let team = try { teams[i].asObject() } catch (_: Exception) { JsonObject() }
        let defaultAgentId = teamString(team, "defaultAgentId")
        if (!defaultAgentId.isEmpty() && !teamAgentExists(agentIds, defaultAgentId)) {
            teamAddFinding(findings, "agent-team-team-unknown-agent", "error", "${pathPrefix}.${i}.defaultAgentId",
                "Team defaultAgentId points to unknown agent ${defaultAgentId}.",
                "Team fallback routing cannot resolve the configured default member.",
                "Create the agent or update the team defaultAgentId.",
                agentId: MetisAgentScope.normalizeAgentId(defaultAgentId))
        }
        let members = teamArray(team, "members")
        for (j in 0..members.size()) {
            let memberId = teamMemberAgentId(members[j])
            if (!memberId.isEmpty() && !teamAgentExists(agentIds, memberId)) {
                teamAddFinding(findings, "agent-team-team-unknown-agent", "error", "${pathPrefix}.${i}.members.${j}",
                    "Team member points to unknown agent ${memberId}.",
                    "Alias/team routing can select a member that cannot run.",
                    "Create the member agent or remove it from the team.",
                    agentId: memberId)
            }
        }
    }
}

private func teamScanTeams(findings: JsonArray, root: JsonObject, agentIds: ArrayList<String>): Unit {
    teamScanTeamArray(findings, teamArray(root, "agentTeams"), agentIds, "agentTeams")
    let teamsObject = teamObject(root, "teams")
    if (teamsObject.size() > 0) {
        teamScanTeamArray(findings, teamArray(teamsObject, "list"), agentIds, "teams.list")
    }
    teamScanTeamArray(findings, teamArray(root, "teams"), agentIds, "teams")
}

private func teamSummary(findings: JsonArray): JsonObject {
    let summary = JsonObject()
    summary.put("findingCount", findings.size().toJsonValue())
    summary.put("ok", (findings.size() == 0).toJsonValue())
    return summary
}

private func teamConflictArrayJson(values: Array<GatewayAgentBindingConflict>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        let row = JsonObject()
        row.put("binding", teamCloneObject(value.binding))
        row.put("existingAgentId", JsonString(value.existingAgentId))
        out.add(row)
    }
    out
}

private func teamBindingApplyJson(result: GatewayAgentBindingApplyResult): JsonObject {
    let out = JsonObject()
    out.put("added", teamObjectArrayJson(result.added))
    out.put("updated", teamObjectArrayJson(result.updated))
    out.put("skipped", teamObjectArrayJson(result.skipped))
    out.put("conflicts", teamConflictArrayJson(result.conflicts))
    out.put("configPreview", teamCloneObject(result.config))
    return out
}

public func gatewayAgentTeamDoctorScan(
    root: JsonObject,
    homeRoot!: Path = MetisPaths.homeRootReadOnly(),
    defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
): JsonObject {
    let scanRoot = teamCloneObject(root)
    let summary = MetisAgentScope.summary(scanRoot, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
    let findings = JsonArray([])
    let multiAccountStatus = JsonArray([])
    let agentIds = teamAgentIds(summary)

    teamScanScopeDiagnostics(findings, summary)
    teamScanDuplicatePaths(findings, summary, "workspaceDir", "agent-team-duplicate-workspace", "workspace")
    teamScanDuplicatePaths(findings, summary, "agentDir", "agent-team-duplicate-agent-dir", "agentDir")
    teamScanAgentFilesAndPolicies(findings, summary, homeRoot)
    teamScanBindings(findings, scanRoot, agentIds)
    teamScanMultiAccount(findings, scanRoot, multiAccountStatus)
    teamScanTeams(findings, scanRoot, agentIds)

    let out = JsonObject()
    out.put("kind", JsonString("agent-team-doctor"))
    out.put("mode", JsonString("read-only"))
    out.put("readOnly", JsonBool(true))
    out.put("agentScope", summary)
    out.put("multiAccountStatus", multiAccountStatus)
    out.put("findings", findings)
    out.put("summary", teamSummary(findings))
    return out
}

public func gatewayAgentTeamMigrationDryRun(
    root: JsonObject,
    proposedBindings!: JsonArray = JsonArray([]),
    homeRoot!: Path = MetisPaths.homeRootReadOnly(),
    defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
): JsonObject {
    let scan = gatewayAgentTeamDoctorScan(root, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
    let rootCopy = teamCloneObject(root)
    let bindingApply = gatewayApplyAgentRouteBindings(rootCopy, proposedBindings)

    let out = JsonObject()
    out.put("kind", JsonString("agent-team-migration"))
    out.put("mode", JsonString("dry-run"))
    out.put("readOnly", JsonBool(true))
    out.put("doctor", scan)
    out.put("findings", scan.get("findings") ?? JsonArray([]))
    out.put("summary", scan.get("summary") ?? JsonObject())
    out.put("bindingApply", teamBindingApplyJson(bindingApply))
    return out
}
