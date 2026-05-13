package metis.core.skills

import metis.core.config.{MetisConfigManager, MetisPaths, CliSettingManager}
import magic.jsonable.*
import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, OpenMode, Path, canonicalize, exists, remove}
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}
import std.unittest.testmacro.*

@Test
public class SkillsRuntimeParityTest {
    @BeforeAll
    public func isolateMetisHome(): Unit {
        setVariable("METIS_HOME", "/tmp/metis-skills-runtime-parity-test-home")
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    private func clearTestSkill(skillDir: Path): Unit {
        SkillsPrompt.invalidate()
        if (exists(skillDir)) {
            remove(skillDir, recursive: true)
        }
    }

    @TestCase
    public func hasKnownSkill(): Unit {
        @Expect(SkillsPrompt.hasSkillName("weather"), true)
    }

    @TestCase
    public func descriptorsContainWeather(): Unit {
        let list = SkillsPrompt.listSkillDescriptors()
        var found = false
        for (d in list) {
            if (d.name.toAsciiLower().trimAscii() == "weather") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func availableSkillsMetadataShape(): Unit {
        let txt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt()
        if (CliSettingManager.readSkillsEnabled()) {
            @Expect(txt.contains("<available_skills>"), true)
            @Expect(txt.contains("<skill name=\""), true)
            @Expect(txt.contains("location=\""), true)
        } else {
            @Expect(txt.trimAscii().isEmpty(), true)
        }
    }

    @TestCase
    public func decideForcedSkill(): Unit {
        let d = SkillsPrompt.decideForInput("anything", Some("weather"))
        if (CliSettingManager.readSkillsEnabled()) {
            @Expect(d.forced, true)
            @Expect(d.selectedSkillName ?? "", "weather")
        } else {
            @Expect(d.selectedSkillName.isNone(), true)
        }
    }

    @TestCase
    public func decideNoneForUnknownSlashLikeInput(): Unit {
        let d = SkillsPrompt.decideForInput("/abctest foo", None)
        @Expect(d.selectedSkillName.isNone(), true)
    }

    @TestCase
    public func workspaceRootDefaultsToProcessCwd(): Unit {
        let expected = try {
            canonicalize(Path(".")).toString()
        } catch (_: Exception) {
            Path(".").toString()
        }
        @Expect(MetisPaths.workspaceRoot().toString(), expected)
    }

    @TestCase
    public func sourceTagsDifferentiateManagedAgentAndWorkspace(): Unit {
        @Expect(skillsSourceTagForLocation(skillsManagedDir().join("demo").join("SKILL.md").toString()), "metis-managed")
        @Expect(skillsSourceTagForLocation(skillsPersonalAgentsDir().join("demo").join("SKILL.md").toString()), "agents-skills-personal")
        @Expect(skillsSourceTagForLocation(skillsProjectAgentsDir().join("demo").join("SKILL.md").toString()), "agents-skills-project")
        @Expect(skillsSourceTagForLocation(skillsWorkspaceDir().join("demo").join("SKILL.md").toString()), "metis-workspace")
    }

    @TestCase
    public func agentSkillResolutionFallsBackToDefaultsAndExplicitlyOverrides(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("skills", JsonArray([JsonString("weather"), JsonString("memory")]))
        agents.put("defaults", defaults)
        let list = JsonArray([])
        let general = JsonObject()
        general.put("id", JsonString("general"))
        general.put("skills", JsonArray([JsonString("weather")]))
        list.add(general)
        let cangjie = JsonObject()
        cangjie.put("id", JsonString("cangjie"))
        cangjie.put("skills", JsonArray([]))
        list.add(cangjie)
        agents.put("list", list)
        root.put("agents", agents)

        let planner = MetisConfigManager.resolveAgentSkillsFromRoot(root, "planner")
        @Expect(planner.isSome(), true)
        @Expect(planner.getOrThrow().size, 2)
        @Expect(planner.getOrThrow()[0], "weather")
        @Expect(planner.getOrThrow()[1], "memory")

        let generalSkills = MetisConfigManager.resolveAgentSkillsFromRoot(root, "general").getOrThrow()
        @Expect(generalSkills.size, 1)
        @Expect(generalSkills[0], "weather")

        let cangjieSkills = MetisConfigManager.resolveAgentSkillsFromRoot(root, "cangjie").getOrThrow()
        @Expect(cangjieSkills.size, 0)

        @Expect(MetisConfigManager.resolveAgentSkillsScopeFromRoot(root, "planner"), "default")
        @Expect(MetisConfigManager.resolveAgentSkillsScopeFromRoot(root, "unknown-agent"), "default")
        @Expect(MetisConfigManager.resolveAgentSkillsFromRoot(root, "unknown-agent").getOrThrow().size, 2)
        @Expect(MetisConfigManager.resolveAgentSkillsScopeFromRoot(root, "general"), "explicit")
        @Expect(MetisConfigManager.resolveAgentSkillsScopeFromRoot(root, "cangjie"), "explicit")
    }

    @TestCase
    public func promptMetadataAppliesRuntimeSkillFilterAfterAgentFilter(): Unit {
        let allowedDir = skillsWorkspaceDir().join("skills-runtime-route-allowed")
        let deniedDir = skillsWorkspaceDir().join("skills-runtime-route-denied")
        try {
            clearTestSkill(allowedDir)
            clearTestSkill(deniedDir)
            Directory.create(allowedDir, recursive: true)
            Directory.create(deniedDir, recursive: true)
            File.writeTo(
                allowedDir.join("SKILL.md"),
                ("---\n" +
                    "name: route-allowed\n" +
                    "description: runtime route allowed skill\n" +
                    "---\n# route-allowed\n").toArray()
            )
            File.writeTo(
                deniedDir.join("SKILL.md"),
                ("---\n" +
                    "name: route-denied\n" +
                    "description: runtime route denied skill\n" +
                    "---\n# route-denied\n").toArray()
            )
            let root = JsonObject()
            let agents = JsonObject()
            let entry = JsonObject()
            entry.put("id", JsonString("writer"))
            entry.put("skills", JsonArray([JsonString("route-allowed"), JsonString("route-denied")]))
            agents.put("list", JsonArray([entry]))
            root.put("agents", agents)
            File.writeTo(MetisConfigManager.configPath(), root.toJsonString().toArray())
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            SkillsPrompt.invalidate()

            let txt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt(
                agentId: "writer",
                runtimeSkillNames: ["route-allowed"]
            )
            @Expect(txt.contains("route-allowed"), true)
            @Expect(txt.contains("route-denied"), false)
            @Expect(SkillsPrompt.decideForInput("please use route-denied", None<String>, agentId: "writer",
                runtimeSkillNames: ["route-allowed"]).selectedSkillName.isNone(), true)
        } finally {
            clearTestSkill(allowedDir)
            clearTestSkill(deniedDir)
            try { remove(MetisConfigManager.configPath()) } catch (_: Exception) { () }
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            SkillsPrompt.invalidate()
        }
    }

    @TestCase
    public func metadataControlsSlashAndPromptVisibility(): Unit {
        let hiddenSlashDir = skillsWorkspaceDir().join("skills-runtime-hidden-slash")
        let hiddenPromptDir = skillsWorkspaceDir().join("skills-runtime-hidden-prompt")
        try {
            clearTestSkill(hiddenSlashDir)
            clearTestSkill(hiddenPromptDir)
            Directory.create(hiddenSlashDir, recursive: true)
            Directory.create(hiddenPromptDir, recursive: true)
            File.writeTo(
                hiddenSlashDir.join("SKILL.md"),
                ("---\n" +
                    "name: hidden-slash\n" +
                    "description: hidden slash skill\n" +
                    "user-invocable: false\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"hidden-slash-key\",\"primaryEnv\":\"HIDDEN_SLASH_KEY\",\"always\":true,\"os\":[\"darwin\"]}}\n" +
                    "---\n# hidden-slash\n").toArray()
            )
            File.writeTo(
                hiddenPromptDir.join("SKILL.md"),
                ("---\n" +
                    "name: hidden-prompt\n" +
                    "description: hidden prompt skill\n" +
                    "disable-model-invocation: true\n" +
                    "metadata: {\"metis\":{\"requires\":{\"env\":[\"PROMPT_KEY\"],\"bins\":[\"curl\"],\"anyBins\":[\"git\"],\"config\":[\"browser.enabled\"]},\"install\":[{\"id\":\"brew\",\"kind\":\"brew\",\"formula\":\"gh\",\"bins\":[\"gh\"]}]}}\n" +
                    "---\n# hidden-prompt\n").toArray()
            )
            SkillsPrompt.invalidate()

            @Expect(SkillsPrompt.hasSkillName("hidden-slash"), false)

            let list = SkillsPrompt.listSkillDescriptors()
            var slashFound = false
            var promptFound = false
            for (d in list) {
                if (d.name == "hidden-slash") {
                    slashFound = true
                    @Expect(d.skillKey, "hidden-slash-key")
                    @Expect(d.primaryEnv, "HIDDEN_SLASH_KEY")
                    @Expect(d.always, true)
                    @Expect(d.requiredOs.size, 1)
                    @Expect(d.userInvocable, false)
                }
                if (d.name == "hidden-prompt") {
                    promptFound = true
                    @Expect(d.disableModelInvocation, true)
                    @Expect(d.requiredEnv.size, 1)
                    @Expect(d.requiredBins.size, 1)
                    @Expect(d.requiredAnyBins.size, 1)
                    @Expect(d.requiredConfig.size, 1)
                    @Expect(d.installSpecs.size, 1)
                }
            }
            @Expect(slashFound, true)
            @Expect(promptFound, true)

            let txt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt()
            @Expect(txt.contains("hidden-prompt"), false)
        } finally {
            clearTestSkill(hiddenSlashDir)
            clearTestSkill(hiddenPromptDir)
        }
    }

    @TestCase
    public func importedLegacyNamespaceMetadataIsCanonicalizedOnLoad(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-legacy-metadata")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: legacy-metadata\n" +
                    "description: imported legacy skill\n" +
                    "metadata: {\"legacy\":{\"skillKey\":\"legacy-skill-key\",\"primaryEnv\":\"LEGACY_SECRET\",\"requires\":{\"env\":[\"LEGACY_SECRET\"]}}}\n" +
                    "---\n# legacy-metadata\n").toArray()
            )
            SkillsPrompt.invalidate()

            let list = SkillsPrompt.listSkillDescriptors()
            var found = false
            for (d in list) {
                if (d.name == "legacy-metadata") {
                    found = true
                    @Expect(d.skillKey, "legacy-skill-key")
                    @Expect(d.primaryEnv, "LEGACY_SECRET")
                    @Expect(d.requiredEnv.size, 1)
                }
            }
            @Expect(found, true)
            let migrated = String.fromUtf8(File.readFrom(skillDir.join("SKILL.md")))
            @Expect(migrated.contains("\"metis\""), true)
            @Expect(migrated.contains("\"legacy\""), false)
        } finally {
            clearTestSkill(skillDir)
        }
    }

    @TestCase
    public func canonicalMetadataWinsWhenLegacyAndCanonicalBlocksBothExist(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-canonical-wins")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: canonical-wins\n" +
                    "description: canonical metadata wins\n" +
                    "metadata: {\"legacy\":{\"skillKey\":\"legacy-key\",\"primaryEnv\":\"LEGACY_SECRET\"},\"metis\":{\"skillKey\":\"canonical-key\",\"primaryEnv\":\"CANONICAL_SECRET\",\"requires\":{\"env\":[\"CANONICAL_SECRET\"]}}}\n" +
                    "---\n# canonical-wins\n").toArray()
            )
            SkillsPrompt.invalidate()

            let list = SkillsPrompt.listSkillDescriptors()
            var found = false
            for (d in list) {
                if (d.name == "canonical-wins") {
                    found = true
                    @Expect(d.skillKey, "canonical-key")
                    @Expect(d.primaryEnv, "CANONICAL_SECRET")
                    @Expect(d.requiredEnv.size, 1)
                }
            }
            @Expect(found, true)
        } finally {
            clearTestSkill(skillDir)
        }
    }

    @TestCase
    public func availableSkillsMetadataCapsInjectedEntries(): Unit {
        let created = ArrayList<Path>()
        try {
            for (i in 0..13) {
                let skillDir = skillsWorkspaceDir().join("skills-runtime-cap-${i}")
                created.add(skillDir)
                clearTestSkill(skillDir)
                Directory.create(skillDir, recursive: true)
                File.writeTo(
                    skillDir.join("SKILL.md"),
                    ("---\n" +
                        "name: cap-skill-${i}\n" +
                        "description: cap skill number ${i}\n" +
                        "---\n# cap-skill-${i}\n").toArray()
                )
            }
            SkillsPrompt.invalidate()
            let txt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt()
            var count = 0
            var start = 0
            let needle = "<skill name=\""
            while (true) {
                match (txt[start..].indexOf(needle)) {
                    case Some(idx) =>
                        count += 1
                        start += idx + needle.size
                    case None => break
                }
            }
            @Expect(count <= 12, true)
        } finally {
            for (skillDir in created) {
                clearTestSkill(skillDir)
            }
        }
    }

    @TestCase
    public func skillEntrySettingsResolveBySkillKeyAndExposeConfiguredFields(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-configured-entry")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: configured-entry\n" +
                    "description: configured entry skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"configured-entry-key\",\"primaryEnv\":\"CONFIGURED_ENTRY_KEY\"}}\n" +
                    "---\n# configured-entry\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("enabled", false.toJsonValue())
            entry.put("apiKey", JsonString("resolved-skill-key"))
            let envObj = JsonObject()
            envObj.put("CUSTOM_ENV", JsonString("present"))
            entry.put("env", envObj)
            let configObj = JsonObject()
            configObj.put("endpoint", JsonString("https://example.invalid"))
            entry.put("config", configObj)
            entries.put("configured-entry-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            let list = SkillsPrompt.listSkillDescriptors()
            var found = false
            for (d in list) {
                if (d.name != "configured-entry") {
                    continue
                }
                found = true
                @Expect(d.skillKey, "configured-entry-key")
                @Expect(d.enabled, false)
                @Expect(d.configuredApiKey, "resolved-skill-key")
                @Expect(d.configuredEnv.isSome(), true)
                @Expect(d.configuredConfig.isSome(), true)
                break
            }
            @Expect(found, true)
        } finally {
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestSkill(skillDir)
        }
    }

    @TestCase
    public func skillEntryEnabledBySkillKeyAppliesToLoadAndMatchPaths(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-key-gated")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: key-gated-skill\n" +
                    "description: key gated skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"key-gated-entry\"}}\n" +
                    "---\n# key-gated-skill\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("enabled", false.toJsonValue())
            entries.put("key-gated-entry", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            @Expect(SkillsPrompt.isSkillEnabledByName("key-gated-skill"), false)

            let statusLines = SkillsPrompt.listSkillStatusLines()
            var foundStatus = false
            for (line in statusLines) {
                if (line.contains("key-gated-skill")) {
                    foundStatus = true
                    @Expect(line.contains("enabled=false"), true)
                }
            }
            @Expect(foundStatus, true)

            let decision = SkillsPrompt.decideForInput("please use key-gated-skill", Some("key-gated-skill"))
            @Expect(decision.selectedSkillName ?? "", "key-gated-skill")
            @Expect(decision.selectedSkillEnabled, false)

            let matchState = SkillsPrompt.resolveSkillMatchStateForInput("please use key-gated-skill")
            @Expect(matchState.isSome(), true)
            @Expect(matchState.getOrThrow().skillName, "key-gated-skill")
            @Expect(matchState.getOrThrow().enabled, false)
        } finally {
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestSkill(skillDir)
        }
    }

    @TestCase
    public func semanticOnlySkillDescriptionDoesNotTriggerSelection(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-semantic-only")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: market-radar\n" +
                    "description: Look up live stock prices and market trends\n" +
                    "---\n# market-radar\n").toArray()
            )
            SkillsPrompt.invalidate()

            let decision = SkillsPrompt.decideForInput("帮我看看今天特斯拉股价怎么样", None)
            @Expect(decision.selectedSkillName.isNone(), true)
            @Expect(decision.reason, "none")

            let resolved = SkillsPrompt.resolveSkillNameForInput("帮我看看今天特斯拉股价怎么样")
            @Expect(resolved.isNone(), true)

            let matchState = SkillsPrompt.resolveSkillMatchStateForInput("帮我看看今天特斯拉股价怎么样")
            @Expect(matchState.isNone(), true)
        } finally {
            clearTestSkill(skillDir)
        }
    }

    /*
    @TestCase
    public func runtimeEnvOverridesApplyAndRevertForConfiguredSkillKey(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-env-override")
        let baselinePrimary = getVariable("RUNTIME_PRIMARY_SECRET") ?? ""
        let baselineCustom = getVariable("RUNTIME_CUSTOM_ENV") ?? ""
        try {
            setVariable("RUNTIME_PRIMARY_SECRET", "")
            setVariable("RUNTIME_CUSTOM_ENV", "")
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: runtime-env-skill\n" +
                    "description: runtime env skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"runtime-env-key\",\"primaryEnv\":\"RUNTIME_PRIMARY_SECRET\"}}\n" +
                    "---\n# runtime-env-skill\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("apiKey", JsonString("runtime-secret"))
            let envObj = JsonObject()
            envObj.put("RUNTIME_CUSTOM_ENV", JsonString("runtime-custom"))
            entry.put("env", envObj)
            entries.put("runtime-env-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            let revert = SkillsPrompt.applyRuntimeEnvOverridesForSkill("runtime-env-skill")
            @Expect(getVariable("RUNTIME_PRIMARY_SECRET") ?? "", "runtime-secret")
            @Expect(getVariable("RUNTIME_CUSTOM_ENV") ?? "", "runtime-custom")

            revert()
            @Expect(getVariable("RUNTIME_PRIMARY_SECRET") ?? "", "")
            @Expect(getVariable("RUNTIME_CUSTOM_ENV") ?? "", "")
        } finally {
            setVariable("RUNTIME_PRIMARY_SECRET", baselinePrimary)
            setVariable("RUNTIME_CUSTOM_ENV", baselineCustom)
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestSkill(skillDir)
        }
    }
    */

    @TestCase
    public func requiresEnvAcceptsConfiguredSkillSettingsBeforeShellEnv(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-requires-env-config")
        let baselinePrimary = getVariable("REQUIRES_ENV_PRIMARY") ?? ""
        let baselineExtra = getVariable("REQUIRES_ENV_EXTRA") ?? ""
        try {
            setVariable("REQUIRES_ENV_PRIMARY", "")
            setVariable("REQUIRES_ENV_EXTRA", "")
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: requires-env-configured\n" +
                    "description: requires env from configured settings\n" +
                    "requires_env: REQUIRES_ENV_PRIMARY, REQUIRES_ENV_EXTRA\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"requires-env-configured-key\",\"primaryEnv\":\"REQUIRES_ENV_PRIMARY\"}}\n" +
                    "---\n# requires-env-configured\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("apiKey", JsonString("configured-primary-secret"))
            let envObj = JsonObject()
            envObj.put("REQUIRES_ENV_EXTRA", JsonString("configured-extra-secret"))
            entry.put("env", envObj)
            entries.put("requires-env-configured-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            @Expect(SkillsPrompt.hasSkillName("requires-env-configured"), true)

            let list = SkillsPrompt.listSkillDescriptors()
            var found = false
            for (d in list) {
                if (d.name != "requires-env-configured") {
                    continue
                }
                found = true
                @Expect(d.skillKey, "requires-env-configured-key")
                @Expect(d.configuredApiKey, "configured-primary-secret")
                @Expect(d.configuredEnv.isSome(), true)
                break
            }
            @Expect(found, true)
        } finally {
            setVariable("REQUIRES_ENV_PRIMARY", baselinePrimary)
            setVariable("REQUIRES_ENV_EXTRA", baselineExtra)
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestSkill(skillDir)
        }
    }

    /*
    @TestCase
    public func watcherRefreshesPromptSnapshotWhenSkillFileChanges(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-watch-refresh")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: watch-refresh-skill\n" +
                    "description: first description\n" +
                    "---\n# watch-refresh-skill\n").toArray()
            )
            SkillsPrompt.invalidate()

            var firstFound = false
            for (d in SkillsPrompt.listSkillDescriptors()) {
                if (d.name == "watch-refresh-skill") {
                    firstFound = true
                    @Expect(d.description, "first description")
                }
            }
            @Expect(firstFound, true)

            sleep(Duration.millisecond * 700)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: watch-refresh-skill\n" +
                    "description: updated description\n" +
                    "---\n# watch-refresh-skill\n").toArray()
            )

            var refreshed = false
            for (d in SkillsPrompt.listSkillDescriptors()) {
                if (d.name == "watch-refresh-skill") {
                    refreshed = true
                    @Expect(d.description, "updated description")
                }
            }
            @Expect(refreshed, true)
        } finally {
            clearTestSkill(skillDir)
        }
    }
    */

    @TestCase
    public func watcherRefreshesCachedSkillsWhenSettingsChange(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-settings-refresh")
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: settings-refresh-skill\n" +
                    "description: settings refresh skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"settings-refresh-key\"}}\n" +
                    "---\n# settings-refresh-skill\n").toArray()
            )
            SkillsPrompt.invalidate()
            @Expect(SkillsPrompt.isSkillEnabledByName("settings-refresh-skill"), true)

            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("enabled", false.toJsonValue())
            entries.put("settings-refresh-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))

            @Expect(SkillsPrompt.isSkillEnabledByName("settings-refresh-skill"), false)
        } finally {
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestSkill(skillDir)
        }
    }

    @TestCase
    public func topLevelSkillsLoadExtraDirsParticipatesInDiscovery(): Unit {
        let extraRoot = skillsWorkspaceDir().join("skills-runtime-extra-root")
        let skillDir = extraRoot.join("top-level-extra-skill")
        let cfgPath = MetisConfigManager.configPath()
        let baseline = try {
            String.fromUtf8(File.readFrom(cfgPath))
        } catch (_: Exception) {
            ""
        }
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: top-level-extra-skill\n" +
                    "description: loaded from top level skills.load.extraDirs\n" +
                    "---\n# top-level-extra-skill\n").toArray()
            )

            let root = MetisConfigManager.rawConfig() ?? JsonObject()
            let skillsObj = match (root.get("skills")) {
                case Some(value) =>
                    try { value.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
            let loadObj = JsonObject()
            loadObj.put("extraDirs", JsonArray([JsonString(extraRoot.toString())]))
            skillsObj.put("load", loadObj)
            root.put("skills", skillsObj)
            File.writeTo(cfgPath, root.toJsonString().toArray())
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            SkillsPrompt.invalidate()

            @Expect(SkillsPrompt.hasSkillName("top-level-extra-skill"), true)
        } finally {
            if (!baseline.isEmpty()) {
                File.writeTo(cfgPath, baseline.toArray())
            }
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            clearTestSkill(skillDir)
            if (exists(extraRoot)) {
                remove(extraRoot, recursive: true)
            }
        }
    }

    @TestCase
    public func watcherCanBeDisabledViaTopLevelSkillsLoadWatchFalse(): Unit {
        let skillDir = skillsWorkspaceDir().join("skills-runtime-watch-disabled")
        let cfgPath = MetisConfigManager.configPath()
        let baseline = try {
            String.fromUtf8(File.readFrom(cfgPath))
        } catch (_: Exception) {
            ""
        }
        try {
            clearTestSkill(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: watch-disabled-skill\n" +
                    "description: first disabled-watch description\n" +
                    "---\n# watch-disabled-skill\n").toArray()
            )
            let root = MetisConfigManager.rawConfig() ?? JsonObject()
            let skillsObj = match (root.get("skills")) {
                case Some(value) =>
                    try { value.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
            let loadObj = match (skillsObj.get("load")) {
                case Some(value) =>
                    try { value.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
            loadObj.put("watch", false.toJsonValue())
            skillsObj.put("load", loadObj)
            root.put("skills", skillsObj)
            File.writeTo(cfgPath, root.toJsonString().toArray())
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            SkillsPrompt.invalidate()

            var firstFound = false
            for (d in SkillsPrompt.listSkillDescriptors()) {
                if (d.name == "watch-disabled-skill") {
                    firstFound = true
                    @Expect(d.description, "first disabled-watch description")
                }
            }
            @Expect(firstFound, true)

            sleep(Duration.millisecond * 700)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: watch-disabled-skill\n" +
                    "description: second disabled-watch description\n" +
                    "---\n# watch-disabled-skill\n").toArray()
            )

            var staleFound = false
            for (d in SkillsPrompt.listSkillDescriptors()) {
                if (d.name == "watch-disabled-skill") {
                    staleFound = true
                    @Expect(d.description, "first disabled-watch description")
                }
            }
            @Expect(staleFound, true)
        } finally {
            if (!baseline.isEmpty()) {
                File.writeTo(cfgPath, baseline.toArray())
            }
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            clearTestSkill(skillDir)
        }
    }
}
