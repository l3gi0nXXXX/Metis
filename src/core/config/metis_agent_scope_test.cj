package metis.core.config

import std.fs.{Directory, File, Path, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func scopeTestHome(name: String): Path {
    metisConfigTestTempHome("agent-scope-${name}")
}

private func scopeTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func scopeTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func scopeTestArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func scopeTestObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func scopePrepareDir(path: Path): Unit {
    try {
        if (exists(path)) {
            remove(path, recursive: true)
        }
    } catch (_: Exception) {
        ()
    }
    Directory.create(path, recursive: true)
}

private func scopeAgentConfigRoot(defaults!: JsonObject = JsonObject(), list!: JsonArray = JsonArray([])): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    if (defaults.size() > 0) {
        agents.put("defaults", defaults)
    }
    if (list.size() > 0) {
        agents.put("list", list)
    }
    if (agents.size() > 0) {
        root.put("agents", agents)
    }
    root
}

private func scopeModel(primary: String, fallbacks!: JsonArray = JsonArray([]), hasFallbacks!: Bool = true): JsonObject {
    let model = JsonObject()
    model.put("primary", JsonString(primary))
    if (hasFallbacks) {
        model.put("fallbacks", fallbacks)
    }
    model
}

private func scopeStringArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

@Test
public class MetisAgentScopeTest {
    @TestCase
    public func emptyConfigResolvesMainWithLegacyGeneralDiagnostic(): Unit {
        let home = scopeTestHome("empty")
        let workspace = home.join("workspace")
        let scope = MetisAgentScope.resolve(JsonObject(), homeRoot: home, defaultWorkspace: workspace)
        @Expect(scopeTestString(scope, "agentId"), "main")
        @Expect(scopeTestString(scope, "defaultAgentId"), "main")
        @Expect(scopeTestString(scope, "workspaceDir"), workspace.toString())
        @Expect(scopeTestString(scope, "agentDir"), home.join("agents").join("main").join("agent").toString())
        @Expect(scopeTestString(scope, "modelsJsonPath"), home.join("agents").join("main").join("agent").join("models.json").toString())
        @Expect(scopeTestString(scope, "authProfilesPath"), home.join("agents").join("main").join("agent").join("auth-profiles.json").toString())
        @Expect(scopeTestString(scope, "legacyAuthPath"), home.join("agents").join("main").join("agent").join("auth.json").toString())
        @Expect(scopeTestString(scope, "sessionsDir"), home.join("agents").join("main").join("sessions").toString())
        @Expect(scopeTestArray(scope, "diagnostics").toJsonString().contains("general-alias"), true)
        @Expect(scopeTestString(scope, "modelRef"), "")
    }

    @TestCase
    public func generalAliasUsesDefaultAgentSessionsDirWithoutCrossingIntoMain(): Unit {
        let home = scopeTestHome("general-alias-sessions")
        let workspace = home.join("workspace")
        let writer = JsonObject()
        writer.put("id", JsonString("writer"))
        writer.put("default", JsonBool(true))
        let list = JsonArray([])
        list.add(writer)
        let root = scopeAgentConfigRoot(list: list)

        let scope = MetisAgentScope.resolve(root, agentId: "general", homeRoot: home, defaultWorkspace: workspace)

        @Expect(scopeTestString(scope, "agentId"), "writer")
        @Expect(scopeTestString(scope, "agentIdSource"), "alias")
        @Expect(scopeTestString(scope, "sessionsDir"), home.join("agents").join("writer").join("sessions").toString())
        @Expect(scopeTestString(scope, "sessionsDir").contains("/agents/main/"), false)
        @Expect(scopeTestString(scope, "sessionsDir").contains("/agents/general/"), false)
    }

    @TestCase
    public func configuredGeneralAgentKeepsOwnSessionsDir(): Unit {
        let home = scopeTestHome("configured-general-sessions")
        let workspace = home.join("workspace")
        let mainEntry = JsonObject()
        mainEntry.put("id", JsonString("main"))
        mainEntry.put("default", JsonBool(true))
        let general = JsonObject()
        general.put("id", JsonString("general"))
        let list = JsonArray([])
        list.add(mainEntry)
        list.add(general)
        let root = scopeAgentConfigRoot(list: list)

        let scope = MetisAgentScope.resolve(root, agentId: "general", homeRoot: home, defaultWorkspace: workspace)

        @Expect(scopeTestString(scope, "agentId"), "general")
        @Expect(scopeTestString(scope, "agentIdSource"), "request")
        @Expect(scopeTestString(scope, "sessionsDir"), home.join("agents").join("general").join("sessions").toString())
    }

    @TestCase
    public func authProfileDiagnosticsReportMissingLegacyAndCopyPolicyWithoutLeakingSecrets(): Unit {
        let home = scopeTestHome("auth-profile-diagnostics")
        let workspace = home.join("workspace")
        let scope = MetisAgentScope.resolve(JsonObject(), homeRoot: home, defaultWorkspace: workspace)
        let missing = MetisAgentScope.authProfileDiagnostics(scope)

        @Expect(scopeTestString(missing, "authProfilesStatus"), "missing")
        @Expect(scopeTestBool(missing, "copyDefaultProfiles"), false)
        @Expect(scopeTestBool(missing, "copyRequiresExplicitConfirmation"), true)
        @Expect(scopeTestArray(missing, "risks").toJsonString().contains("auth-profiles-missing"), true)

        let agentDir = Path(scopeTestString(scope, "agentDir"))
        scopePrepareDir(agentDir)
        File.writeTo(agentDir.join("auth-profiles.json"), "{\"profiles\":[{\"id\":\"fixture\",\"apiKey\":\"fixture-api-key-value\"}]}".toArray())
        File.writeTo(agentDir.join("auth.json"), "{\"secret\":\"fixture-secret-value\"}".toArray())
        let present = MetisAgentScope.authProfileDiagnostics(scope)
        let rendered = present.toJsonString()

        @Expect(scopeTestString(present, "authProfilesStatus"), "present")
        @Expect(scopeTestString(present, "legacyAuthStatus"), "present")
        @Expect(scopeTestArray(present, "risks").toJsonString().contains("legacy-auth-json"), true)
        @Expect(rendered.contains("fixture-api-key-value"), false)
        @Expect(rendered.contains("fixture-secret-value"), false)
    }

    @TestCase
    public func singleAgentPreservesExplicitPathsAndRawPolicies(): Unit {
        let home = scopeTestHome("single")
        let defaults = JsonObject()
        defaults.put("workspace", JsonString(home.join("team").toString()))
        defaults.put("model", scopeModel("openai/gpt-4.1", fallbacks: scopeStringArray(["dashscope/qwen-max"])))
        defaults.put("skills", scopeStringArray(["read", "write"]))
        let defaultTools = JsonObject()
        defaultTools.put("allow", scopeStringArray(["fileRead"]))
        defaults.put("tools", defaultTools)
        defaults.put("thinkingDefault", JsonString("medium"))
        defaults.put("verboseDefault", JsonString("on"))
        let entry = JsonObject()
        entry.put("id", JsonString("Cangjie"))
        entry.put("default", JsonBool(true))
        entry.put("workspace", JsonString(home.join("cj-workspace").toString()))
        entry.put("agentDir", JsonString(home.join("custom-agent-dir").toString()))
        entry.put("model", scopeModel("local/cj", fallbacks: scopeStringArray(["openai/cj-fallback"])))
        entry.put("skills", scopeStringArray(["cangjie-docs"]))
        let tools = JsonObject()
        tools.put("allow", scopeStringArray(["grepSearch"]))
        entry.put("tools", tools)
        let identity = JsonObject()
        identity.put("name", JsonString("Cangjie Expert"))
        entry.put("identity", identity)
        let groupChat = JsonObject()
        groupChat.put("mentionRequired", JsonBool(true))
        entry.put("groupChat", groupChat)
        let subagents = JsonObject()
        subagents.put("allowAgents", scopeStringArray(["reviewer"]))
        entry.put("subagents", subagents)
        let memorySearch = JsonObject()
        memorySearch.put("enabled", JsonBool(true))
        entry.put("memorySearch", memorySearch)
        let sandbox = JsonObject()
        sandbox.put("mode", JsonString("workspace-write"))
        entry.put("sandbox", sandbox)
        entry.put("runtime", JsonObject())
        entry.put("fastModeDefault", JsonBool(true))
        let list = JsonArray([])
        list.add(entry)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(defaults: defaults, list: list), agentId: "cangjie", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(scope, "agentId"), "cangjie")
        @Expect(scopeTestString(scope, "workspaceDir"), home.join("cj-workspace").toString())
        @Expect(scopeTestString(scope, "agentDir"), home.join("custom-agent-dir").toString())
        let model = scope.get("model").getOrThrow().asObject()
        @Expect(scopeTestString(model, "primary"), "local/cj")
        @Expect(scopeTestArray(model, "fallbacks").toJsonString().contains("openai/cj-fallback"), true)
        @Expect(scopeTestString(model, "fallbacksEffectiveSource"), "agents.list[].model.fallbacks")
        @Expect(scopeTestString(scope, "modelRef"), "local/cj")
        @Expect(scopeTestString(scope, "modelRefSource"), "agents.list[].model.primary")
        let providerSummary = scopeTestObject(scope, "providerSummary")
        @Expect(scopeTestString(providerSummary, "providerId"), "local")
        let accountSummary = scopeTestObject(scope, "accountSummary")
        @Expect(scopeTestString(accountSummary, "status"), "not-configured")
        let runtimeDefaults = scope.get("runtimeDefaults").getOrThrow().asObject()
        @Expect(scopeTestString(runtimeDefaults, "thinkingDefault"), "medium")
        @Expect(scopeTestString(runtimeDefaults, "verboseDefault"), "on")
        @Expect(scopeTestBool(runtimeDefaults, "fastModeDefault"), true)
        @Expect(scope.get("raw").getOrThrow().asObject().toJsonString().contains("Cangjie Expert"), true)
        @Expect(scope.get("identityPolicy").getOrThrow().asObject().toJsonString().contains("agents.list[].identity"), true)
        @Expect(scope.get("skillsPolicy").getOrThrow().asObject().toJsonString().contains("cangjie-docs"), true)
        @Expect(scope.get("toolsPolicy").getOrThrow().asObject().toJsonString().contains("grepSearch"), true)
    }

    @TestCase
    public func multiAgentDefaultDuplicateAndInvalidIdsAreDiagnosed(): Unit {
        let home = scopeTestHome("multi")
        let defaults = JsonObject()
        defaults.put("workspace", JsonString(home.join("team").toString()))
        let list = JsonArray([])
        let first = JsonObject()
        first.put("id", JsonString("PM"))
        first.put("default", JsonBool(true))
        list.add(first)
        let second = JsonObject()
        second.put("id", JsonString("../Research Agent"))
        second.put("default", JsonBool(true))
        list.add(second)
        let duplicate = JsonObject()
        duplicate.put("id", JsonString("pm"))
        list.add(duplicate)
        let root = scopeAgentConfigRoot(defaults: defaults, list: list)
        let summary = MetisAgentScope.summary(root, homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(summary, "defaultAgentId"), "pm")
        @Expect(scopeTestArray(summary, "agents").size(), 2)
        let diagnostics = scopeTestArray(summary, "diagnostics").toJsonString()
        @Expect(diagnostics.contains("multiple-default-agents"), true)
        @Expect(diagnostics.contains("duplicate-agent-id"), true)
        @Expect(diagnostics.contains("invalid-agent-id"), true)
        let research = MetisAgentScope.resolve(root, agentId: "../Research Agent", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(research, "agentId"), "research-agent")
        @Expect(scopeTestString(research, "workspaceDir"), home.join("team").join("research-agent").toString())
        @Expect(scopeTestString(research, "agentDir"), home.join("agents").join("research-agent").join("agent").toString())
        @Expect(scopeTestString(research, "sessionsDir"), home.join("agents").join("research-agent").join("sessions").toString())
    }

    @TestCase
    public func explicitEmptyFallbacksDisableDefaultFallbacks(): Unit {
        let home = scopeTestHome("fallbacks")
        let defaults = JsonObject()
        defaults.put("model", scopeModel("openai/main", fallbacks: scopeStringArray(["openai/fallback"])))
        let entry = JsonObject()
        entry.put("id", JsonString("writer"))
        entry.put("model", scopeModel("openai/writer", fallbacks: JsonArray([])))
        let list = JsonArray([])
        list.add(entry)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(defaults: defaults, list: list), agentId: "writer", homeRoot: home, defaultWorkspace: home.join("workspace"))
        let model = scope.get("model").getOrThrow().asObject()
        @Expect(scopeTestArray(model, "fallbacks").size(), 0)
        @Expect(scopeTestBool(model, "fallbacksExplicitlyDisabled"), true)
        @Expect(scopeTestString(model, "fallbacksSource"), "agents.list[].model.fallbacks")
    }

    @TestCase
    public func unknownAgentFallsBackToDefaultsWithoutExpandingPolicies(): Unit {
        let home = scopeTestHome("unknown")
        let defaults = JsonObject()
        defaults.put("skills", scopeStringArray(["safe-skill"]))
        let tools = JsonObject()
        tools.put("allow", scopeStringArray(["safe-tool"]))
        defaults.put("tools", tools)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(defaults: defaults), agentId: "unknown", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(scope, "agentId"), "unknown")
        @Expect(scopeTestBool(scope, "configured"), false)
        @Expect(scope.get("skillsPolicy").getOrThrow().asObject().toJsonString().contains("safe-skill"), true)
        @Expect(scope.get("toolsPolicy").getOrThrow().asObject().toJsonString().contains("safe-tool"), true)
        @Expect(scopeTestArray(scope, "diagnostics").toJsonString().contains("unknown-agent"), true)
    }

    @TestCase
    public func workspaceIdentityFileFillsMissingConfigIdentityWithSources(): Unit {
        let home = scopeTestHome("identity")
        let workspace = home.join("workspace")
        scopePrepareDir(workspace)
        File.writeTo(
            workspace.join("IDENTITY.md"),
            "- name: File Name\n- emoji: F\n- theme: file-theme\n- avatar: images/avatar.png\n".toArray()
        )
        let defaults = JsonObject()
        defaults.put("workspace", JsonString(workspace.toString()))
        let entry = JsonObject()
        entry.put("id", JsonString("writer"))
        let identity = JsonObject()
        identity.put("name", JsonString("Config Name"))
        entry.put("identity", identity)
        let list = JsonArray([])
        list.add(entry)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(defaults: defaults, list: list), agentId: "writer", homeRoot: home, defaultWorkspace: workspace)
        let resolvedIdentity = scopeTestObject(scope, "identity")
        @Expect(scopeTestString(resolvedIdentity, "name"), "Config Name")
        @Expect(scopeTestString(resolvedIdentity, "nameSource"), "agents.list[].identity.name")
        @Expect(scopeTestString(resolvedIdentity, "emoji"), "F")
        @Expect(scopeTestString(resolvedIdentity, "emojiSource"), "workspace.IDENTITY.md")
        @Expect(scopeTestString(resolvedIdentity, "avatar"), workspace.join("images/avatar.png").normalize().toString())
        @Expect(scopeTestString(resolvedIdentity, "avatarSource"), "workspace.IDENTITY.md")
    }

    @TestCase
    public func identityAvatarTraversalIsDiagnosedAndNotResolved(): Unit {
        let home = scopeTestHome("avatar-escape")
        let workspace = home.join("workspace")
        let entry = JsonObject()
        entry.put("id", JsonString("artist"))
        let identity = JsonObject()
        identity.put("avatar", JsonString("../outside.png"))
        entry.put("identity", identity)
        let list = JsonArray([])
        list.add(entry)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(list: list), agentId: "artist", homeRoot: home, defaultWorkspace: workspace)
        let resolvedIdentity = scopeTestObject(scope, "identity")
        @Expect(resolvedIdentity.get("avatar").isSome(), false)
        let diagnostics = scopeTestArray(scope, "diagnostics").toJsonString()
        @Expect(diagnostics.contains("identity-avatar-escape"), true)
    }

    @TestCase
    public func identityAvatarUriSchemesAreCaseInsensitiveAndUnsupportedSchemesAreDiagnosed(): Unit {
        let home = scopeTestHome("avatar-uri")
        let dataWorkspace = home.join("data-workspace")
        scopePrepareDir(dataWorkspace)
        File.writeTo(dataWorkspace.join("IDENTITY.md"), "- avatar: DATA:image/png;base64,AAAA\n".toArray())

        let web = JsonObject()
        web.put("id", JsonString("web"))
        let webIdentity = JsonObject()
        webIdentity.put("avatar", JsonString("HTTPS://cdn.example.test/avatar.png"))
        web.put("identity", webIdentity)

        let dataAgent = JsonObject()
        dataAgent.put("id", JsonString("data"))
        dataAgent.put("workspace", JsonString(dataWorkspace.toString()))

        let bad = JsonObject()
        bad.put("id", JsonString("bad"))
        let badIdentity = JsonObject()
        badIdentity.put("avatar", JsonString("ftp://example.test/avatar.png"))
        bad.put("identity", badIdentity)

        let list = JsonArray([])
        list.add(web)
        list.add(dataAgent)
        list.add(bad)
        let root = scopeAgentConfigRoot(list: list)

        let webScope = MetisAgentScope.resolve(root, agentId: "web", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(scopeTestObject(webScope, "identity"), "avatar"), "HTTPS://cdn.example.test/avatar.png")

        let dataScope = MetisAgentScope.resolve(root, agentId: "data", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(scopeTestObject(dataScope, "identity"), "avatar"), "DATA:image/png;base64,AAAA")

        let badScope = MetisAgentScope.resolve(root, agentId: "bad", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestObject(badScope, "identity").get("avatar").isSome(), false)
        @Expect(scopeTestArray(badScope, "diagnostics").toJsonString().contains("identity-avatar-invalid"), true)
    }

    @TestCase
    public func relativePathTraversalFallsBackAndDiagnosticsMentionBoundary(): Unit {
        let home = scopeTestHome("path-escape")
        let workspace = home.join("workspace")
        let entry = JsonObject()
        entry.put("id", JsonString("runner"))
        entry.put("workspace", JsonString("../outside-workspace"))
        entry.put("agentDir", JsonString("../outside-agent"))
        let list = JsonArray([])
        let mainEntry = JsonObject()
        mainEntry.put("id", JsonString("main"))
        mainEntry.put("default", JsonBool(true))
        list.add(mainEntry)
        list.add(entry)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(list: list), agentId: "runner", homeRoot: home, defaultWorkspace: workspace)
        @Expect(scopeTestString(scope, "workspaceDir"), home.join("workspaces").join("runner").toString())
        @Expect(scopeTestString(scope, "agentDir"), home.join("agents").join("runner").join("agent").toString())
        let diagnostics = scopeTestArray(scope, "diagnostics").toJsonString()
        @Expect(diagnostics.contains("path-escape"), true)
        @Expect(diagnostics.contains("agents.list[].workspace"), true)
        @Expect(diagnostics.contains("agents.list[].agentDir"), true)
    }

    @TestCase
    public func tildePathsAreExpandedAndWorkspaceAgentDirOverlapIsDiagnosed(): Unit {
        let home = scopeTestHome("tilde")
        let entry = JsonObject()
        entry.put("id", JsonString("ops"))
        entry.put("workspace", JsonString("~/metis-ops"))
        entry.put("agentDir", JsonString("~/metis-ops/../metis-ops/.agent"))
        let list = JsonArray([])
        list.add(entry)
        let scope = MetisAgentScope.resolve(scopeAgentConfigRoot(list: list), agentId: "ops", homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(scope, "workspaceDir").contains("~"), false)
        @Expect(scopeTestString(scope, "agentDir").contains("~"), false)
        @Expect(scopeTestString(scope, "workspaceDir").endsWith("/metis-ops"), true)
        @Expect(scopeTestString(scope, "agentDir").endsWith("/metis-ops/.agent"), true)
        @Expect(scopeTestArray(scope, "diagnostics").toJsonString().contains("workspace-agentdir-overlap"), true)
    }

    @TestCase
    public func providerAndAccountSummaryReflectConfiguredProviderCredentials(): Unit {
        let home = scopeTestHome("provider-summary")
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("model", scopeModel("qwen:qwen-plus", fallbacks: scopeStringArray(["qwen:qwen-turbo"])))
        agents.put("defaults", defaults)
        root.put("agents", agents)
        let models = JsonObject()
        let providers = JsonObject()
        let qwen = JsonObject()
        qwen.put("apiKey", JsonString("test-key"))
        qwen.put("baseUrl", JsonString("https://example.test/v1"))
        providers.put("qwen", qwen)
        models.put("providers", providers)
        root.put("models", models)
        let scope = MetisAgentScope.resolve(root, homeRoot: home, defaultWorkspace: home.join("workspace"))
        @Expect(scopeTestString(scope, "modelRef"), "qwen:qwen-plus")
        let providerSummary = scopeTestObject(scope, "providerSummary")
        @Expect(scopeTestString(providerSummary, "providerId"), "qwen")
        @Expect(scopeTestBool(providerSummary, "configured"), true)
        let accountSummary = scopeTestObject(scope, "accountSummary")
        @Expect(scopeTestString(accountSummary, "status"), "configured")
        @Expect(scopeTestString(accountSummary, "source"), "models.providers.qwen")
        @Expect(scopeTestBool(accountSummary, "apiKeyConfigured"), true)
        @Expect(scopeTestBool(accountSummary, "baseUrlConfigured"), true)
    }
}
