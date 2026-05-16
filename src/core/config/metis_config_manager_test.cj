package metis.core.config

import magic.config.Config
import magic.jsonable.*

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove, File}
import std.collection.ArrayList
import std.convert.Parsable
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

@Test
public class MetisConfigManagerTest {
    @TestCase
    public func normalizeModelRefRewritesLegacyArkQwenProviderToDashscopeRuntime(): Unit {
        @Expect(
            MetisConfigManager.normalizeModelRef("ark:qwen3.5-plus"),
            "dashscope:qwen3.5-plus"
        )
    }

    @TestCase
    public func canonicalModelRefRewritesLegacyArkQwenProviderToQwen(): Unit {
        @Expect(
            MetisConfigManager.canonicalModelRef("ark:qwen3.5-plus"),
            "qwen:qwen3.5-plus"
        )
    }

    @TestCase
    public func normalizeConfigPathValuePreservesMetisHomePaths(): Unit {
        @Expect(
            MetisConfigManager.normalizeConfigPathValue("~/.metis/memory/{agentId}.sqlite"),
            "~/.metis/memory/{agentId}.sqlite"
        )
    }

    @TestCase
    public func defaultHomeRootUsesMetisDirectory(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-default-home-root").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("HOME")
        let oldUserProfile = getVariable("USERPROFILE")
        let oldStateHome = getVariable("METIS_HOME")
        setVariable("HOME", testHome)
        setVariable("USERPROFILE", testHome)
        setVariable("METIS_HOME", "")

        let expected = Path(testHome).join(".metis").toString()
        @Expect(MetisPaths.homeRoot().toString(), expected)

        match (oldHome) {
            case Some(value) => setVariable("HOME", value)
            case None => setVariable("HOME", "")
        }
        match (oldUserProfile) {
            case Some(value) => setVariable("USERPROFILE", value)
            case None => setVariable("USERPROFILE", "")
        }
        match (oldStateHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
    }

    @TestCase
    public func defaultConfigPathUsesMetisJson(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-default-config-path").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("HOME")
        let oldUserProfile = getVariable("USERPROFILE")
        let oldStateHome = getVariable("METIS_HOME")
        setVariable("HOME", testHome)
        setVariable("USERPROFILE", testHome)
        setVariable("METIS_HOME", "")
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let expected = Path(testHome).join(".metis").join("metis.json").toString()
        @Expect(MetisConfigManager.configPath().toString(), expected)

        match (oldHome) {
            case Some(value) => setVariable("HOME", value)
            case None => setVariable("HOME", "")
        }
        match (oldUserProfile) {
            case Some(value) => setVariable("USERPROFILE", value)
            case None => setVariable("USERPROFILE", "")
        }
        match (oldStateHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func initializeIfMissingDoesNotInjectHardcodedPrimaryModel(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase1-no-default-primary").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        MetisConfigManager.initializeIfMissing()

        let root = MetisConfigManager.rawConfig().getOrThrow()
        let agents = root.get("agents").getOrThrow().asObject()
        let defaults = agents.get("defaults").getOrThrow().asObject()
        @Expect(defaults.get("model").isNone(), true)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setGatewaySettingsPreservesExistingPrimaryModelAndWizardState(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase1-gateway-preserves-model").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        defaults.put("workspace", JsonString("/tmp/project"))
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)

        let wizard = JsonObject()
        let onboard = JsonObject()
        onboard.put("defaultModelRef", JsonString("qwen/qwen3.6-plus"))
        wizard.put("onboard", onboard)
        root.put("wizard", wizard)
        root.put("session", JsonObject())

        MetisConfigManager.writeRoot(root)

        var updated = GatewayUserSettings()
        updated.auth.mode = "password"
        updated.auth.password = "secret"
        updated.session.dmScope = "raw"
        MetisConfigManager.setGatewaySettings(updated)

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        let persistedPrimary = persisted
            .get("agents").getOrThrow().asObject()
            .get("defaults").getOrThrow().asObject()
            .get("model").getOrThrow().asObject()
            .get("primary").getOrThrow().asString().getValue()
        @Expect(persistedPrimary, "qwen/qwen3.6-plus")
        let persistedWizard = persisted
            .get("wizard").getOrThrow().asObject()
            .get("onboard").getOrThrow().asObject()
            .get("defaultModelRef").getOrThrow().asString().getValue()
        @Expect(persistedWizard, "qwen/qwen3.6-plus")
        let persistedGateway = persisted.get("gateway").getOrThrow().asObject()
        @Expect(
            persistedGateway.get("auth").getOrThrow().asObject().get("mode").getOrThrow().asString().getValue(),
            "password"
        )
        @Expect(
            persisted.get("session").getOrThrow().asObject().get("dmScope").getOrThrow().asString().getValue(),
            "raw"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func migrateLegacyIfNeededDoesNotMoveLegacyMetaNamespaceToMetis(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-no-legacy-meta-namespace-migration").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let meta = JsonObject()
        let legacy = JsonObject()
        let legacyWizard = JsonObject()
        legacyWizard.put("lastWorkspace", JsonString("/tmp/legacy-project"))
        legacy.put("wizard", legacyWizard)
        let metis = JsonObject()
        let metisWizard = JsonObject()
        metisWizard.put("homeRoot", JsonString("/tmp/.metis"))
        metis.put("wizard", metisWizard)
        meta.put("cangjieclaw", legacy)
        meta.put("metis", metis)
        root.put("meta", meta)

        MetisConfigManager.writeRoot(root)
        MetisConfigManager.invalidate()
        MetisConfigManager.migrateLegacyIfNeeded()

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        let persistedMeta = persisted.get("meta").getOrThrow().asObject()
        let persistedLegacyWizard = persistedMeta
            .get("cangjieclaw").getOrThrow().asObject()
            .get("wizard").getOrThrow().asObject()
        @Expect(persistedLegacyWizard.get("lastWorkspace").getOrThrow().asString().getValue(), "/tmp/legacy-project")
        let wizard = persistedMeta.get("metis").getOrThrow().asObject().get("wizard").getOrThrow().asObject()
        @Expect(wizard.get("lastWorkspace").isNone(), true)
        @Expect(wizard.get("homeRoot").getOrThrow().asString().getValue(), "/tmp/.metis")

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setGatewaySettingsFailsClosedWhenConfigIsInvalid(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase3-invalid-config-no-gateway-persist").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let invalidConfig = "{\n" +
            "  \"agents\": {\"defaults\": {\"model\": {\"primary\": \"qwen/qwen3.6-plus\"}}},\n" +
            "  \"gateway\": {\"auth\": {\"mode\": \"token\"}},\n" +
            "  \"session\": {}\n" +
            "}\n" +
            "\"\n"
        let path = MetisConfigManager.configPath()
        File.writeTo(path, invalidConfig.toArray())

        var threw = false
        try {
            let _ = MetisConfigManager.setGatewaySettings(GatewayUserSettings())
        } catch (_: Exception) {
            threw = true
        }
        @Expect(threw, true)
        @Expect(String.fromUtf8(File.readFrom(path)), invalidConfig)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setGatewaySettingsFailsClosedWhenConfigIsParseableButMissingAgentsDefaults(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase4-incomplete-config-no-gateway-persist").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        root.put("agents", JsonObject())
        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let before = String.fromUtf8(File.readFrom(MetisConfigManager.configPath()))
        var threw = false
        try {
            let _ = MetisConfigManager.setGatewaySettings(GatewayUserSettings())
        } catch (_: Exception) {
            threw = true
        }
        @Expect(threw, true)
        @Expect(String.fromUtf8(File.readFrom(MetisConfigManager.configPath())), before)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setPrimaryModelRefPreservesExistingGatewayTokenAndWorkspace(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-model-preserves-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)

        let session = JsonObject()
        session.put("dmScope", JsonString("agent"))
        root.put("session", session)

        MetisConfigManager.writeRoot(root)

        let nextModel = MetisConfigManager.setPrimaryModelRef("openai:gpt-5")
        @Expect(nextModel, "openai:gpt-5")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        let persistedPrimary = persisted
            .get("agents").getOrThrow().asObject()
            .get("defaults").getOrThrow().asObject()
            .get("model").getOrThrow().asObject()
            .get("primary").getOrThrow().asString().getValue()
        @Expect(persistedPrimary, "openai/gpt-5")
        let persistedWorkspace = persisted
            .get("agents").getOrThrow().asObject()
            .get("defaults").getOrThrow().asObject()
            .get("workspace").getOrThrow().asString().getValue()
        @Expect(persistedWorkspace, "/tmp/project")
        let persistedGatewayToken = persisted
            .get("gateway").getOrThrow().asObject()
            .get("auth").getOrThrow().asObject()
            .get("token").getOrThrow().asString().getValue()
        @Expect(persistedGatewayToken, "keep-me")
        @Expect(
            persisted.get("session").getOrThrow().asObject().get("dmScope").getOrThrow().asString().getValue(),
            "agent"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setImageModelRefPreservesPrimaryModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-image-model-preserves-primary-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("deepseek/deepseek-v4-pro"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)
        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("token", JsonString("keep-token"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        MetisConfigManager.writeRoot(root)

        let nextModel = MetisConfigManager.setImageModelRef("qwen/qwen-vl-max")
        let nextFallbacks = MetisConfigManager.setImageFallbackModelRefs(["openai/gpt-4o", "openai:gpt-4o"])

        @Expect(nextModel, "qwen:qwen-vl-max")
        @Expect(nextFallbacks.size, 1)
        @Expect(nextFallbacks[0], "openai:gpt-4o")
        @Expect(MetisConfigManager.readImageModel().getOrThrow(), "dashscope:qwen-vl-max")
        @Expect(MetisConfigManager.readImageFallbackModels()[0], "openai:gpt-4o")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "deepseek/deepseek-v4-pro"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-token"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setFallbackModelRefsPreservesExistingPrimaryModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-fallbacks-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let nextFallbacks = MetisConfigManager.setFallbackModelRefs([
            "openai:gpt-5-mini",
            "dashscope:qwen3.5-plus",
            "openai:gpt-5-mini"
        ])
        @Expect(nextFallbacks.size, 2)
        @Expect(nextFallbacks[0], "openai:gpt-5-mini")
        @Expect(nextFallbacks[1], "qwen:qwen3.5-plus")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        let persistedModel = persisted
            .get("agents").getOrThrow().asObject()
            .get("defaults").getOrThrow().asObject()
            .get("model").getOrThrow().asObject()
        @Expect(
            persistedModel.get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        let fallbacks = persistedModel.get("fallbacks").getOrThrow().asArray()
        @Expect(fallbacks.size(), 2)
        @Expect(fallbacks[0].asString().getValue(), "openai/gpt-5-mini")
        @Expect(fallbacks[1].asString().getValue(), "qwen/qwen3.5-plus")
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setSkillsEnabledPreservesExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-skills-preserves-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)

        let skills = JsonObject()
        skills.put("enabled", false.toJsonValue())
        root.put("skills", skills)
        root.put("session", JsonObject())

        MetisConfigManager.writeRoot(root)

        let nextEnabled = MetisConfigManager.setSkillsEnabled(true)
        @Expect(nextEnabled, true)

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(
            persisted.get("skills").getOrThrow().asObject().get("enabled").getOrThrow().asBool().getValue(),
            true
        )
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setSkillsEntriesPreservesExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-skills-entries-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)

        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let entries = JsonObject()
        let review = JsonObject()
        review.put("enabled", false.toJsonValue())
        review.put("apiKey", JsonString("abc"))
        entries.put("review", review)
        let nextEntries = MetisConfigManager.setSkillsEntries(Some(entries))
        @Expect(nextEntries.isSome(), true)

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        let persistedEntries = persisted.get("skills").getOrThrow().asObject().get("entries").getOrThrow().asObject()
        @Expect(
            persistedEntries.get("review").getOrThrow().asObject().get("enabled").getOrThrow().asBool().getValue(),
            false
        )
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setMcpServersPreservesExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-mcp-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let mcpServers = JsonObject()
        let demo = JsonObject()
        demo.put("command", JsonString("npx"))
        demo.put("args", JsonArray([JsonString("@demo/server")]))
        mcpServers.put("demo", demo)
        let nextServers = MetisConfigManager.setMcpServers(Some(mcpServers))
        @Expect(nextServers.isSome(), true)

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        let persistedMcp = persisted.get("mcpServers").getOrThrow().asObject()
        @Expect(
            persistedMcp.get("demo").getOrThrow().asObject().get("command").getOrThrow().asString().getValue(),
            "npx"
        )
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        CliSettingManager.invalidate()
        let loaded = CliSettingManager.setting.mcpServers.getOrThrow()
        @Expect(
            loaded.get("demo").getOrThrow().asObject().get("command").getOrThrow().asString().getValue(),
            "npx"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setLanguagePreservesExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-language-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let nextLanguage = MetisConfigManager.setLanguage("cangjie")
        @Expect(nextLanguage, "cangjie")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(persisted.get("language").getOrThrow().asString().getValue(), "cangjie")
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        CliSettingManager.invalidate()
        @Expect(CliSettingManager.setting.language, "cangjie")

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setCollectDataPreservesExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-collect-data-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let nextValue = MetisConfigManager.setCollectData(true)
        @Expect(nextValue, true)

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(persisted.get("collectData").getOrThrow().asBool().getValue(), true)
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setFastModelRefPreservesExistingPrimaryModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-fast-model-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let nextFastModel = MetisConfigManager.setFastModelRef("dashscope:qwen3.5-plus")
        @Expect(nextFastModel, "qwen:qwen3.5-plus")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(
            persisted.get("fastModel").getOrThrow().asString().getValue(),
            "qwen/qwen3.5-plus"
        )
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setTemperatureAndModelLimitsPreserveExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-runtime-tuning-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let nextTemperature = MetisConfigManager.setTemperature(0.7)
        let nextInput = MetisConfigManager.setDefaultModelInputLimit(4096)
        let nextOutput = MetisConfigManager.setDefaultModelOutputLimit(2048)
        @Expect(nextTemperature, 0.7)
        @Expect(nextInput, 4096)
        @Expect(nextOutput, 2048)

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(Float64.parse(persisted.get("temperature").getOrThrow().toJsonString()), 0.7)
        @Expect(
            persisted.get("defaultModelInputLimit").getOrThrow().asInt().getValue(),
            4096
        )
        @Expect(
            persisted.get("defaultModelOutputLimit").getOrThrow().asInt().getValue(),
            2048
        )
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func setMemoryBackendPreservesExistingModelAndGateway(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-memory-backend-preserve-model-gateway").toString()
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/project"))
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("keep-me"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("skills", JsonObject())
        root.put("session", JsonObject())
        MetisConfigManager.writeRoot(root)

        let nextBackend = MetisConfigManager.setMemoryBackend("sqlite-fts+local-file")
        @Expect(nextBackend, "sqlite-fts+local-file")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(
            persisted.get("memory").getOrThrow().asObject().get("backend").getOrThrow().asString().getValue(),
            "sqlite-fts+local-file"
        )
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "qwen/qwen3.6-plus"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "keep-me"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    /*
    @TestCase
    public func applyPersistedFieldsMaterializesRuntimeEnvAliasesWithoutOverwritingExistingValues(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase2-runtime-env-bridge").toString()
        Directory.create(testHome, recursive: true)
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("qwen:qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let models = JsonObject()
        let providers = JsonObject()
        let qwen = JsonObject()
        qwen.put("apiKey", JsonString("cfg-key"))
        qwen.put("baseUrl", JsonString("https://cfg.example/v1"))
        providers.put("qwen", qwen)
        models.put("providers", providers)
        root.put("models", models)

        let oldPrimaryApiKey = Config.env["QWEN_API_KEY"] ?? ""
        let oldPrimaryBaseUrl = Config.env["QWEN_BASE_URL"] ?? ""
        let oldAliasApiKey = Config.env["DASHSCOPE_API_KEY"] ?? ""
        let oldAliasBaseUrl = Config.env["DASHSCOPE_BASE_URL"] ?? ""
        Config.env["QWEN_API_KEY"] = "sentinel-key"
        Config.env["QWEN_BASE_URL"] = "sentinel-url"
        Config.env["DASHSCOPE_API_KEY"] = ""
        Config.env["DASHSCOPE_BASE_URL"] = ""

        MetisConfigManager.writeRoot(root)
        MetisConfigManager.applyPersistedFieldsToCliConfig()

        @Expect(MetisConfigManager.readProviderApiKey("qwen"), "cfg-key")
        @Expect(MetisConfigManager.readProviderBaseUrl("qwen"), "https://cfg.example/v1")
        @Expect(Config.env["QWEN_API_KEY"] ?? "", "sentinel-key")
        @Expect(Config.env["QWEN_BASE_URL"] ?? "", "sentinel-url")
        @Expect(Config.env["DASHSCOPE_API_KEY"] ?? "", "cfg-key")
        @Expect(Config.env["DASHSCOPE_BASE_URL"] ?? "", "https://cfg.example/v1")

        Config.env["QWEN_API_KEY"] = oldPrimaryApiKey
        Config.env["QWEN_BASE_URL"] = oldPrimaryBaseUrl
        Config.env["DASHSCOPE_API_KEY"] = oldAliasApiKey
        Config.env["DASHSCOPE_BASE_URL"] = oldAliasBaseUrl
    }
    */

    /*
    @TestCase
    public func readToolApiKeysFromMetisJson(): Unit {
        let testHome = metisConfigTestTempHome("metis-phase3-tool-api-keys").toString()
        Directory.create(testHome, recursive: true)
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()

        let root = JsonObject()
        let tools = JsonObject()
        let context7 = JsonObject()
        context7.put("apiKey", JsonString("ctx-key"))
        tools.put("context7", context7)
        let search = JsonObject()
        let tavily = JsonObject()
        tavily.put("apiKey", JsonString("tvly-key"))
        search.put("tavily", tavily)
        tools.put("search", search)
        root.put("tools", tools)

        MetisConfigManager.writeRoot(root)

        @Expect(MetisConfigManager.readContext7ApiKey(), "ctx-key")
        @Expect(MetisConfigManager.readTavilyApiKey(), "tvly-key")
    }
    */

    @TestCase
    public func resolveAgentMemorySearchFallsBackToDefaults(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let memorySearch = JsonObject()
        memorySearch.put("provider", JsonString("qmd"))
        memorySearch.put("enabled", true.toJsonValue())
        defaults.put("memorySearch", memorySearch)
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        @Expect(
            resolved.get("provider").getOrThrow().asString().getValue(),
            "qmd"
        )
        @Expect(resolved.get("enabled").getOrThrow().asBool().getValue(), true)
        @Expect(
            MetisConfigManager.resolveAgentMemorySearchScopeFromRoot(root, "general"),
            "agents.defaults.memorySearch"
        )
    }

    @TestCase
    public func resolveAgentMemorySearchOverlaysAgentOverride(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("qmd"))
        defaultMemorySearch.put("enabled", true.toJsonValue())
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        overrideMemorySearch.put("provider", JsonString("local"))
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        @Expect(
            resolved.get("provider").getOrThrow().asString().getValue(),
            "local"
        )
        @Expect(resolved.get("enabled").getOrThrow().asBool().getValue(), true)
        @Expect(
            MetisConfigManager.resolveAgentMemorySearchScopeFromRoot(root, "general"),
            "agents.list[].memorySearch"
        )
    }

    @TestCase
    public func resolveAgentMemorySearchPreservesExplicitDisable(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("qmd"))
        defaultMemorySearch.put("enabled", true.toJsonValue())
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        overrideMemorySearch.put("enabled", false.toJsonValue())
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        @Expect(
            resolved.get("provider").getOrThrow().asString().getValue(),
            "qmd"
        )
        @Expect(resolved.get("enabled").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func resolveAgentMemorySearchMergesFallbackPathsAndQmdCollections(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("qmd"))
        defaultMemorySearch.put("fallback", JsonString("local"))
        defaultMemorySearch.put("extraPaths", JsonArray([JsonString("/docs"), JsonString("/shared")]))
        let defaultQmd = JsonObject()
        defaultQmd.put("extraCollections", JsonArray([JsonString("team"), JsonString("ops")]))
        defaultMemorySearch.put("qmd", defaultQmd)
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        overrideMemorySearch.put("fallback", JsonString("voyage"))
        overrideMemorySearch.put("extraPaths", JsonArray([JsonString("/shared"), JsonString("/project")]))
        let overrideQmd = JsonObject()
        overrideQmd.put("extraCollections", JsonArray([JsonString("ops"), JsonString("project")]))
        overrideMemorySearch.put("qmd", overrideQmd)
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        @Expect(
            resolved.get("fallback").getOrThrow().asString().getValue(),
            "voyage"
        )
        let extraPaths = resolved.get("extraPaths").getOrThrow().asArray()
        @Expect(extraPaths.size(), 3)
        @Expect(extraPaths[0].asString().getValue(), "/docs")
        @Expect(extraPaths[1].asString().getValue(), "/shared")
        @Expect(extraPaths[2].asString().getValue(), "/project")
        let qmd = resolved.get("qmd").getOrThrow().asObject()
        let collections = qmd.get("extraCollections").getOrThrow().asArray()
        @Expect(collections.size(), 3)
        @Expect(collections[0].asString().getValue(), "team")
        @Expect(collections[1].asString().getValue(), "ops")
        @Expect(collections[2].asString().getValue(), "project")
    }

    @TestCase
    public func resolveAgentMemorySearchOverridesModelAndRemoteConfig(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("openai"))
        defaultMemorySearch.put("model", JsonString("text-embedding-3-small"))
        let defaultRemote = JsonObject()
        defaultRemote.put("baseUrl", JsonString("https://default.example/v1"))
        defaultRemote.put("apiKey", JsonString("default-key"))
        let defaultHeaders = JsonObject()
        defaultHeaders.put("x-source", JsonString("default"))
        defaultRemote.put("headers", defaultHeaders)
        defaultMemorySearch.put("remote", defaultRemote)
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        overrideMemorySearch.put("model", JsonString("text-embedding-3-large"))
        let overrideRemote = JsonObject()
        overrideRemote.put("baseUrl", JsonString("https://override.example/v1"))
        let overrideHeaders = JsonObject()
        overrideHeaders.put("x-source", JsonString("override"))
        overrideRemote.put("headers", overrideHeaders)
        overrideMemorySearch.put("remote", overrideRemote)
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        @Expect(
            resolved.get("model").getOrThrow().asString().getValue(),
            "text-embedding-3-large"
        )
        let remote = resolved.get("remote").getOrThrow().asObject()
        @Expect(
            remote.get("baseUrl").getOrThrow().asString().getValue(),
            "https://override.example/v1"
        )
        @Expect(
            remote.get("headers").getOrThrow().asObject().get("x-source").getOrThrow().asString().getValue(),
            "override"
        )
        @Expect(remote.get("apiKey").isSome(), false)
    }

    @TestCase
    public func resolveAgentMemorySearchOverridesLocalAndHybridConfig(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("local"))
        let defaultLocal = JsonObject()
        defaultLocal.put("modelPath", JsonString("/models/default.gguf"))
        defaultLocal.put("modelCacheDir", JsonString("/cache/default"))
        defaultMemorySearch.put("local", defaultLocal)
        let defaultHybrid = JsonObject()
        defaultHybrid.put("enabled", true.toJsonValue())
        defaultHybrid.put("vectorWeight", 0.7.toJsonValue())
        let defaultMmr = JsonObject()
        defaultMmr.put("enabled", false.toJsonValue())
        defaultHybrid.put("mmr", defaultMmr)
        let defaultQuery = JsonObject()
        defaultQuery.put("hybrid", defaultHybrid)
        defaultMemorySearch.put("query", defaultQuery)
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        let overrideLocal = JsonObject()
        overrideLocal.put("modelPath", JsonString("/models/override.gguf"))
        overrideMemorySearch.put("local", overrideLocal)
        let overrideHybrid = JsonObject()
        overrideHybrid.put("textWeight", 0.4.toJsonValue())
        let overrideDecay = JsonObject()
        overrideDecay.put("enabled", true.toJsonValue())
        overrideDecay.put("halfLifeDays", 14.toJsonValue())
        overrideHybrid.put("temporalDecay", overrideDecay)
        let overrideQuery = JsonObject()
        overrideQuery.put("hybrid", overrideHybrid)
        overrideMemorySearch.put("query", overrideQuery)
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        let local = resolved.get("local").getOrThrow().asObject()
        @Expect(local.get("modelPath").getOrThrow().asString().getValue(), "/models/override.gguf")
        @Expect(local.get("modelCacheDir").isSome(), false)
        let hybrid = resolved.get("query").getOrThrow().asObject().get("hybrid").getOrThrow().asObject()
        @Expect(hybrid.get("textWeight").getOrThrow().asFloat().getValue(), 0.4)
        @Expect(hybrid.get("vectorWeight").isSome(), false)
        let temporalDecay = hybrid.get("temporalDecay").getOrThrow().asObject()
        @Expect(temporalDecay.get("enabled").getOrThrow().asBool().getValue(), true)
        @Expect(temporalDecay.get("halfLifeDays").getOrThrow().asInt().getValue(), 14)
    }

    @TestCase
    public func resolveAgentMemorySearchOverridesStoreAndSyncConfig(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("local"))
        let defaultStore = JsonObject()
        defaultStore.put("driver", JsonString("sqlite"))
        defaultStore.put("path", JsonString("~/.metis/memory/{agentId}.sqlite"))
        let defaultVector = JsonObject()
        defaultVector.put("enabled", true.toJsonValue())
        defaultStore.put("vector", defaultVector)
        defaultMemorySearch.put("store", defaultStore)
        let defaultSync = JsonObject()
        defaultSync.put("watch", true.toJsonValue())
        let defaultSessions = JsonObject()
        defaultSessions.put("deltaBytes", 100000.toJsonValue())
        defaultSync.put("sessions", defaultSessions)
        defaultMemorySearch.put("sync", defaultSync)
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        let overrideStore = JsonObject()
        overrideStore.put("path", JsonString("/tmp/agent-memory.sqlite"))
        let overrideFts = JsonObject()
        overrideFts.put("tokenizer", JsonString("trigram"))
        overrideStore.put("fts", overrideFts)
        overrideMemorySearch.put("store", overrideStore)
        let overrideSync = JsonObject()
        overrideSync.put("watch", false.toJsonValue())
        let overrideSessions = JsonObject()
        overrideSessions.put("deltaMessages", 25.toJsonValue())
        overrideSync.put("sessions", overrideSessions)
        overrideMemorySearch.put("sync", overrideSync)
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        let store = resolved.get("store").getOrThrow().asObject()
        @Expect(store.get("path").getOrThrow().asString().getValue(), "/tmp/agent-memory.sqlite")
        @Expect(store.get("driver").isSome(), false)
        @Expect(store.get("fts").getOrThrow().asObject().get("tokenizer").getOrThrow().asString().getValue(), "trigram")
        let sync = resolved.get("sync").getOrThrow().asObject()
        @Expect(sync.get("watch").getOrThrow().asBool().getValue(), false)
        @Expect(sync.get("onSessionStart").isSome(), false)
        let sessions = sync.get("sessions").getOrThrow().asObject()
        @Expect(sessions.get("deltaMessages").getOrThrow().asInt().getValue(), 25)
        @Expect(sessions.get("deltaBytes").isSome(), false)
    }

    @TestCase
    public func resolveAgentMemorySearchMergesOutputDimensionalityAndMultimodal(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let defaultMemorySearch = JsonObject()
        defaultMemorySearch.put("provider", JsonString("openai"))
        defaultMemorySearch.put("outputDimensionality", 1536.toJsonValue())
        let defaultMultimodal = JsonObject()
        defaultMultimodal.put("enabled", false.toJsonValue())
        defaultMultimodal.put("modalities", JsonArray([JsonString("image")]))
        defaultMultimodal.put("maxFileBytes", 10000000.toJsonValue())
        defaultMemorySearch.put("multimodal", defaultMultimodal)
        defaults.put("memorySearch", defaultMemorySearch)
        agents.put("defaults", defaults)

        let list = ArrayList<JsonValue>()
        let entry = JsonObject()
        entry.put("id", JsonString("general"))
        let overrideMemorySearch = JsonObject()
        overrideMemorySearch.put("outputDimensionality", 3072.toJsonValue())
        let overrideMultimodal = JsonObject()
        overrideMultimodal.put("enabled", true.toJsonValue())
        overrideMultimodal.put("modalities", JsonArray([JsonString("all")]))
        overrideMemorySearch.put("multimodal", overrideMultimodal)
        entry.put("memorySearch", overrideMemorySearch)
        list.add(entry)
        agents.put("list", JsonArray(list.toArray()))
        root.put("agents", agents)

        let resolved = MetisConfigManager.resolveAgentMemorySearchFromRoot(root, "general").getOrThrow()
        @Expect(resolved.get("outputDimensionality").getOrThrow().asInt().getValue(), 3072)
        let multimodal = resolved.get("multimodal").getOrThrow().asObject()
        @Expect(multimodal.get("enabled").getOrThrow().asBool().getValue(), true)
        @Expect(multimodal.get("modalities").getOrThrow().asArray()[0].asString().getValue(), "all")
        @Expect(multimodal.get("maxFileBytes").getOrThrow().asInt().getValue(), 10000000)
    }
}
