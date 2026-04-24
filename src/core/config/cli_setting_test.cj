package metis.core.config

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class CliSettingManagerTest {
    @TestCase
    public func explicitTopLevelEmptyMemoryBackendDoesNotReviveLegacyProvider(): Unit {
        var setting = CliSetting()
        setting.memory.backend = ""
        setting.memoryProvider = "qmd"
        let root = JsonObject()
        let memory = JsonObject()
        memory.put("backend", JsonString(""))
        root.put("memory", memory)
        @Expect(CliSettingManager.resolvedMemoryProvider(setting, root: Some(root)), "local")
    }

    @TestCase
    public func explicitTopLevelMemoryBackendWinsOverLegacyProvider(): Unit {
        var setting = CliSetting()
        setting.memory.backend = ""
        setting.memoryProvider = "qmd"
        let root = JsonObject()
        let memory = JsonObject()
        memory.put("backend", JsonString("sqlite-fts+local-file"))
        root.put("memory", memory)
        @Expect(
            CliSettingManager.resolvedMemoryProvider(setting, root: Some(root)),
            "sqlite-fts+local-file"
        )
    }

    @TestCase
    public func legacyMemoryProviderStillWorksWithoutTopLevelMemoryBlock(): Unit {
        var setting = CliSetting()
        setting.memory.backend = ""
        setting.memoryProvider = "qmd"
        @Expect(CliSettingManager.resolvedMemoryProvider(setting), "qmd")
    }

    @TestCase
    public func resolvedPrimaryModelForSavePrefersNormalizedConfigPrimary(): Unit {
        var setting = CliSetting()
        setting.model = "ark:qwen3.5-plus"
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)
        @Expect(
            CliSettingManager.resolvedPrimaryModelForSave(setting, root),
            "dashscope:qwen3.6-plus"
        )
    }

    @TestCase
    public func resolvedPrimaryModelForSaveDoesNotInjectHardcodedDefault(): Unit {
        let setting = CliSetting()
        @Expect(CliSettingManager.resolvedPrimaryModelForSave(setting, JsonObject()), "")
    }

    @TestCase
    public func settingAssignmentDoesNotPersistWithoutExplicitPatch(): Unit {
        let testHome = "/tmp/metis-phase3-setting-assignment-no-save"
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
        MetisConfigManager.writeRoot(root)

        var updated = CliSettingManager.setting
        updated.model = "openai:gpt-5"
        CliSettingManager.setting = updated

        let persistedPrimary = MetisConfigManager.rawConfig().getOrThrow()
            .get("agents").getOrThrow().asObject()
            .get("defaults").getOrThrow().asObject()
            .get("model").getOrThrow().asObject()
            .get("primary").getOrThrow().asString().getValue()
        @Expect(persistedPrimary, "qwen/qwen3.6-plus")
        @Expect(CliSettingManager.setting.model, "openai:gpt-5")

        CliSettingManager.invalidate()
        @Expect(CliSettingManager.setting.model, "dashscope:qwen3.6-plus")

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}
