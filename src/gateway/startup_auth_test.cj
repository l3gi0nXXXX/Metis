package metis.gateway

import metis.core.config.{CliSettingManager, MetisConfigManager}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove, File}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class GatewayStartupAuthTest {
    @TestCase
    public func startupAuthPersistencePreservesExistingPrimaryModel(): Unit {
        let testHome = "/tmp/metis-phase1-startup-auth-preserves-model"
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
        root.put("session", JsonObject())
        root.put("wizard", JsonObject())

        MetisConfigManager.writeRoot(root)

        let configured = CliSettingManager.readGatewaySettings()
        let (_, generated, persisted) = gatewayPrepareStartupAuth(configured)
        @Expect(generated, true)
        @Expect(persisted, true)

        let persistedRoot = MetisConfigManager.rawConfig().getOrThrow()
        let persistedPrimary = persistedRoot
            .get("agents").getOrThrow().asObject()
            .get("defaults").getOrThrow().asObject()
            .get("model").getOrThrow().asObject()
            .get("primary").getOrThrow().asString().getValue()
        @Expect(persistedPrimary, "qwen/qwen3.6-plus")
        let persistedToken = persistedRoot
            .get("gateway").getOrThrow().asObject()
            .get("auth").getOrThrow().asObject()
            .get("token").getOrThrow().asString().getValue()
        @Expect(persistedToken.isEmpty(), false)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func startupAuthSkipsPersistenceWhenConfigIsInvalid(): Unit {
        let testHome = "/tmp/metis-phase3-startup-auth-invalid-config"
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

        let configured = CliSettingManager.readGatewaySettings()
        let (updated, generated, persisted) = gatewayPrepareStartupAuth(configured)
        @Expect(generated, true)
        @Expect(persisted, false)
        @Expect(updated.auth.token.isEmpty(), false)
        @Expect(String.fromUtf8(File.readFrom(path)), invalidConfig)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func startupAuthSkipsPersistenceWhenConfigIsIncomplete(): Unit {
        let testHome = "/tmp/metis-phase4-startup-auth-incomplete-config"
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
        let configured = CliSettingManager.readGatewaySettings()
        let (updated, generated, persisted) = gatewayPrepareStartupAuth(configured)
        @Expect(generated, true)
        @Expect(persisted, false)
        @Expect(updated.auth.token.isEmpty(), false)
        @Expect(String.fromUtf8(File.readFrom(MetisConfigManager.configPath())), before)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

}
