package metis.gateway.core

import std.fs.{Directory, File, Path, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func doctorTestHome(name: String): Path {
    Path("/tmp").join("metis-agent-team-doctor-test").join(name)
}

private func doctorPrepareDir(path: Path): Unit {
    try {
        if (exists(path)) {
            remove(path, recursive: true)
        }
    } catch (_: Exception) {
        ()
    }
    Directory.create(path, recursive: true)
}

private func doctorString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func doctorArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func doctorObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func doctorHasCode(findings: JsonArray, code: String): Bool {
    for (i in 0..findings.size()) {
        let finding = try { findings[i].asObject() } catch (_: Exception) { JsonObject() }
        if (doctorString(finding, "code") == code) {
            return true
        }
    }
    false
}

private func doctorFindingsHaveNoWriteTargets(findings: JsonArray): Bool {
    for (i in 0..findings.size()) {
        let finding = try { findings[i].asObject() } catch (_: Exception) { JsonObject() }
        if (!doctorString(finding, "writeTarget").isEmpty()) {
            return false
        }
    }
    true
}

private func doctorConfigHasBindingType(config: JsonObject, typeName: String): Bool {
    let bindings = doctorArray(config, "bindings")
    for (i in 0..bindings.size()) {
        let binding = try { bindings[i].asObject() } catch (_: Exception) { JsonObject() }
        if (doctorString(binding, "type") == typeName) {
            return true
        }
    }
    false
}

private func doctorAgent(id: String, workspace: String, isDefault!: Bool = false, agentDir!: String = ""): JsonObject {
    let row = JsonObject()
    row.put("id", JsonString(id))
    row.put("workspace", JsonString(workspace))
    if (isDefault) {
        row.put("default", JsonBool(true))
    }
    if (!agentDir.trimAscii().isEmpty()) {
        row.put("agentDir", JsonString(agentDir))
    }
    row
}

private func doctorChannel(defaultAccountId: String, accounts: Array<String>): JsonObject {
    let channel = JsonObject()
    channel.put("defaultAccountId", JsonString(defaultAccountId))
    let accountIds = JsonArray([])
    for (account in accounts) {
        accountIds.add(JsonString(account))
    }
    channel.put("accountIds", accountIds)
    return channel
}

private func doctorRouteBinding(agentId: String, channel: String, accountId!: String = "", typeName!: String = "route",
    enabled!: Bool = true): JsonObject {
    let binding = JsonObject()
    if (!typeName.isEmpty()) {
        binding.put("type", JsonString(typeName))
    }
    binding.put("agentId", JsonString(agentId))
    binding.put("enabled", JsonBool(enabled))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString(channel))
    if (!accountId.isEmpty()) {
        matchObj.put("accountId", JsonString(accountId))
    }
    binding.put("match", matchObj)
    binding
}

private func doctorRiskConfig(home: Path): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let list = JsonArray([])
    let sharedWorkspace = home.join("shared-workspace").toString()
    let mainAgent = doctorAgent("main", sharedWorkspace, isDefault: true)
    let memorySearch = JsonObject()
    memorySearch.put("enabled", JsonBool(true))
    mainAgent.put("memorySearch", memorySearch)
    let subagents = JsonObject()
    subagents.put("enabled", JsonBool(true))
    mainAgent.put("subagents", subagents)
    list.add(mainAgent)
    list.add(doctorAgent("Ops Agent", sharedWorkspace, isDefault: true, agentDir: home.join("agents").join("ops-agent").toString()))
    agents.put("list", list)
    root.put("agents", agents)

    let channels = JsonObject()
    channels.put("telegram", doctorChannel("bot-a", ["bot-a", "bot-b"]))
    root.put("channels", channels)
    let session = JsonObject()
    session.put("dmScope", JsonString("main"))
    root.put("session", session)

    let bindings = JsonArray([])
    bindings.add(doctorRouteBinding("main", "telegram", accountId: "bot-a"))
    bindings.add(doctorRouteBinding("missing-agent", "telegram", accountId: "bot-z"))
    bindings.add(doctorRouteBinding("main", "telegram"))
    root.put("bindings", bindings)

    let teams = JsonArray([])
    let team = JsonObject()
    team.put("id", JsonString("support"))
    team.put("defaultAgentId", JsonString("missing-default"))
    let members = JsonArray([])
    members.add(JsonString("ghost"))
    team.put("members", members)
    teams.add(team)
    root.put("agentTeams", teams)
    root
}

@Test
public class GatewayAgentTeamDoctorTest {
    @TestCase
    public func scanReportsAgentTeamRisksWithoutWritingConfig(): Unit {
        let home = doctorTestHome("scan-risk")
        doctorPrepareDir(home)
        let root = doctorRiskConfig(home)
        let mainAgentDir = home.join("agents").join("main").join("agent")
        doctorPrepareDir(mainAgentDir)
        File.writeTo(mainAgentDir.join("auth.json"), "{\"profiles\":[]}".toArray())
        let before = root.toJsonString()

        let report = gatewayAgentTeamDoctorScan(root, homeRoot: home, defaultWorkspace: home.join("workspace"))
        let findings = doctorArray(report, "findings")

        @Expect(doctorString(report, "mode"), "read-only")
        @Expect(root.toJsonString(), before)
        @Expect(doctorFindingsHaveNoWriteTargets(findings), true)
        @Expect(doctorHasCode(findings, "agent-team-multiple-default"), true)
        @Expect(doctorHasCode(findings, "agent-team-duplicate-workspace"), true)
        @Expect(doctorHasCode(findings, "agent-team-legacy-agent-dir"), true)
        @Expect(doctorHasCode(findings, "agent-team-models-missing"), true)
        @Expect(doctorHasCode(findings, "agent-team-auth-profiles-missing"), true)
        @Expect(doctorHasCode(findings, "agent-team-legacy-auth-json"), true)
        @Expect(doctorHasCode(findings, "agent-team-binding-unknown-agent"), true)
        @Expect(doctorHasCode(findings, "agent-team-binding-default-account-only"), true)
        @Expect(doctorHasCode(findings, "agent-team-multi-account-implicit-default"), true)
        @Expect(doctorHasCode(findings, "agent-team-dm-scope-shared"), true)
        @Expect(doctorHasCode(findings, "agent-team-team-unknown-agent"), true)
        @Expect(doctorHasCode(findings, "agent-team-memory-cross-agent"), true)
        @Expect(doctorHasCode(findings, "agent-team-subagent-wide"), true)
    }

    @TestCase
    public func migrationDryRunReportsBindingApplyWithoutChangingConfig(): Unit {
        let home = doctorTestHome("dry-run")
        doctorPrepareDir(home)
        let root = JsonObject()
        let agents = JsonObject()
        let list = JsonArray([])
        list.add(doctorAgent("main", home.join("main-workspace").toString(), isDefault: true))
        list.add(doctorAgent("ops", home.join("ops-workspace").toString()))
        list.add(doctorAgent("reviewer", home.join("review-workspace").toString()))
        agents.put("list", list)
        root.put("agents", agents)
        let channels = JsonObject()
        channels.put("telegram", doctorChannel("bot-a", ["bot-a", "bot-b"]))
        root.put("channels", channels)
        let existing = JsonArray([])
        existing.add(doctorRouteBinding("main", "telegram"))
        existing.add(doctorRouteBinding("ops-acp", "telegram", accountId: "bot-b", typeName: "acp"))
        root.put("bindings", existing)
        let before = root.toJsonString()

        let proposed = JsonArray([])
        proposed.add(doctorRouteBinding("main", "telegram", accountId: "bot-a"))
        proposed.add(doctorRouteBinding("main", "telegram", accountId: "bot-a"))
        proposed.add(doctorRouteBinding("ops", "telegram", accountId: "bot-a"))
        proposed.add(doctorRouteBinding("reviewer", "telegram", accountId: "bot-b"))
        proposed.add(doctorRouteBinding("ops-acp", "telegram", accountId: "bot-b", typeName: "acp"))
        proposed.add(doctorRouteBinding("ops", "telegram", accountId: "bot-c", enabled: false))

        let report = gatewayAgentTeamMigrationDryRun(root, proposedBindings: proposed, homeRoot: home,
            defaultWorkspace: home.join("workspace"))
        let bindingApply = doctorObject(report, "bindingApply")

        @Expect(doctorString(report, "mode"), "dry-run")
        @Expect(root.toJsonString(), before)
        @Expect(doctorArray(bindingApply, "updated").size(), 1)
        @Expect(doctorArray(bindingApply, "skipped").size(), 3)
        @Expect(doctorArray(bindingApply, "conflicts").size(), 1)
        @Expect(doctorArray(bindingApply, "added").size(), 1)
        @Expect(doctorConfigHasBindingType(doctorObject(bindingApply, "configPreview"), "acp"), true)
    }

    @TestCase
    public func scanReportsPerAgentCredentialFallbackToGlobalProvider(): Unit {
        let home = doctorTestHome("credential-source-global-fallback")
        doctorPrepareDir(home)
        let agentDir = home.join("agents").join("pm").join("agent")
        doctorPrepareDir(agentDir)
        File.writeTo(agentDir.join("models.json"), "{\"providers\":{}}".toArray())
        File.writeTo(agentDir.join("auth-profiles.json"), "{\"profiles\":[]}".toArray())

        let root = JsonObject()
        let agents = JsonObject()
        let list = JsonArray([])
        let pm = doctorAgent("pm", home.join("workspace").toString(), isDefault: true, agentDir: agentDir.toString())
        pm.put("model", JsonString("qwen:qwen-plus"))
        list.add(pm)
        agents.put("list", list)
        root.put("agents", agents)
        let models = JsonObject()
        let providers = JsonObject()
        let qwen = JsonObject()
        qwen.put("apiKey", JsonString("global-secret"))
        providers.put("qwen", qwen)
        models.put("providers", providers)
        root.put("models", models)

        let report = gatewayAgentTeamDoctorScan(root, homeRoot: home, defaultWorkspace: home.join("workspace"))
        let rendered = report.toJsonString()

        @Expect(doctorHasCode(doctorArray(report, "findings"), "agent-team-provider-credential-global-fallback"), true)
        @Expect(rendered.contains("global-secret"), false)
    }
}
