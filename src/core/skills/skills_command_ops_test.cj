package metis.core.skills

import metis.core.config.{CliConfig, MetisConfigManager}

import std.fs.{Directory, File, OpenMode, Path, exists, remove}
import stdx.encoding.json.{JsonObject, JsonString}
import std.unittest.testmacro.*

@Test
public class SkillsCommandOpsTest {
    private func clearTestState(skillDir: Path): Unit {
        SkillsPrompt.invalidate()
        setSkillsCommandRunnerForTest(None)
        setClawHubHttpGetForTest(None)
        setClawHubArchiveRootForTest(None)
        if (exists(skillDir)) {
            remove(skillDir, recursive: true)
        }
        let lockPath = clawHubSkillsLockfilePath(CliConfig.cwd)
        if (exists(lockPath)) {
            remove(lockPath)
        }
        let dotDir = CliConfig.cwd.join(".clawhub")
        if (exists(dotDir)) {
            remove(dotDir, recursive: true)
        }
    }

    @TestCase
    public func updateRejectsUntrackedClawHubSlug(): Unit {
        let response = tryHandleSkillsCommand("/skills update definitely-not-tracked").getOrThrow()
        @Expect(
            response,
            "Skill \"definitely-not-tracked\" is not tracked as a ClawHub install. Install it first with /skills install definitely-not-tracked"
        )
    }

    @TestCase
    public func updateRejectsSlugAndAllMix(): Unit {
        let response = tryHandleSkillsCommand("/skills update weather --all").getOrThrow()
        @Expect(response, "Usage: /skills update [slug | --all]")
    }

    @TestCase
    public func searchSupportsLimitAndBrowseAll(): Unit {
        let dummyDir = skillsWorkspaceDir().join("skills-command-ops-search-test")
        let capturePath = dummyDir.join("runner-args.txt")
        try {
            clearTestState(dummyDir)
            Directory.create(dummyDir, recursive: true)
            setSkillsCommandRunnerForTest(Some({ args: String =>
                File.writeTo(capturePath, args.toArray())
                "search ok"
            }))

            let limited = tryHandleSkillsCommand("/skills search --limit 20 weather").getOrThrow()
            @Expect(limited, "search ok")
            @Expect(String.fromUtf8(File.readFrom(capturePath)), "find weather --limit 20")

            let browseAll = tryHandleSkillsCommand("/skills search").getOrThrow()
            @Expect(browseAll, "search ok")
            @Expect(String.fromUtf8(File.readFrom(capturePath)), "find")

            let jsonSearch = tryHandleSkillsCommand("/skills search --json --limit 5 calendar").getOrThrow()
            @Expect(jsonSearch, "search ok")
            @Expect(String.fromUtf8(File.readFrom(capturePath)), "find calendar --limit 5 --json")
        } finally {
            clearTestState(dummyDir)
        }
    }

    @TestCase
    public func infoShowsClawHubOriginMetadataForTrackedWorkspaceSkill(): Unit {
        let slug = "skills-command-ops-test-skill"
        let skillDir = skillsWorkspaceDir().join(slug)
        let skillFile = skillDir.join("SKILL.md")
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            let raw = "---\nname: ${slug}\nversion: 9.9.9\ndescription: test skill\n---\n# ${slug}\n"
            File.writeTo(skillFile, raw.toArray())
            recordInstalledClawHubSkill(CliConfig.cwd, slug, "9.9.9", installedAtMs: 42)
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills info ${slug}").getOrThrow()
            @Expect(response.contains("ClawHub Slug: ${slug}"), true)
            @Expect(response.contains("Registry: https://clawhub.ai"), true)
            @Expect(response.contains("Installed Version: 9.9.9"), true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func installReturnsClawHubSummary(): Unit {
        let slug = "skills-command-ops-install-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        let skillFile = skillDir.join("SKILL.md")
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            let raw = "---\nname: ${slug}\nversion: 1.2.3\ndescription: install test skill\n---\n# ${slug}\n"
            File.writeTo(skillFile, raw.toArray())
            setSkillsCommandRunnerForTest(Some({ _args: String => "installer ok" }))

            let response = tryHandleSkillsCommand("/skills install ${slug} --version 1.2.3 --force").getOrThrow()
            @Expect(response.contains("Installed ${slug}@1.2.3"), true)
            @Expect(response.contains("Target Dir: ${skillDir}"), true)
            @Expect(response.contains("Registry: https://clawhub.ai"), true)
            @Expect(response.contains("installer ok"), true)
        } finally {
            clearTestState(skillDir)
        }
    }

    /*
    @TestCase
    public func updateReturnsTrackedSummary(): Unit {
        let slug = "skills-command-ops-update-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        let skillFile = skillDir.join("SKILL.md")
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            let raw = "---\nname: ${slug}\nversion: 2.0.0\ndescription: update test skill\n---\n# ${slug}\n"
            File.writeTo(skillFile, raw.toArray())
            recordInstalledClawHubSkill(CliConfig.cwd, slug, "1.0.0", installedAtMs: 1)
            setSkillsCommandRunnerForTest(Some({ _args: String => "update ok" }))
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills update ${slug}").getOrThrow()
            @Expect(response.contains("Updated ${slug}@2.0.0"), true)
            @Expect(response.contains("update ok"), true)
        } finally {
            clearTestState(skillDir)
        }
    }
    */

    @TestCase
    public func nativeSearchUsesClawHubTransportWhenNoRunnerOverride(): Unit {
        let dummyDir = skillsWorkspaceDir().join("skills-command-native-search-test")
        try {
            clearTestState(dummyDir)
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"results\":[{\"slug\":\"weather\",\"displayName\":\"Weather\",\"summary\":\"forecast\",\"version\":\"1.2.3\"}]}"
            }))
            let response = tryHandleSkillsCommand("/skills search weather").getOrThrow()
            @Expect(response.contains("weather @1.2.3"), true)
            @Expect(response.contains("Name: Weather"), true)
            @Expect(response.contains("Summary: forecast"), true)
        } finally {
            clearTestState(dummyDir)
        }
    }

    /*
    @TestCase
    public func nativeInstallUsesClawHubTransportWhenNoRunnerOverride(): Unit {
        let slug = "skills-command-native-install-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        let archiveRoot = CliConfig.cwd.join("target").join("skills-command-native-install-archive")
        try {
            clearTestState(skillDir)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
            Directory.create(archiveRoot, recursive: true)
            File.writeTo(
                archiveRoot.join("SKILL.md"),
                "---\nname: ${slug}\nversion: 4.5.6\ndescription: native install\n---\n# ${slug}\n".toArray()
            )
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"${slug}\"},\"latestVersion\":{\"version\":\"4.5.6\"}}"
            }))
            setClawHubArchiveRootForTest(Some({ _slug: String, _version: String => archiveRoot }))

            let response = tryHandleSkillsCommand("/skills install ${slug}").getOrThrow()
            @Expect(response.contains("Installed ${slug}@4.5.6"), true)
            @Expect(response.contains("Target Dir: ${skillDir}"), true)
            @Expect(response.contains("Registry: https://clawhub.ai"), true)
        } finally {
            clearTestState(skillDir)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
        }
    }
    */

    @TestCase
    public func nativeUpdateAllWithoutTrackedSkillsDoesNotFallBackToLegacyCli(): Unit {
        let dummyDir = skillsWorkspaceDir().join("skills-command-native-update-empty-test")
        try {
            clearTestState(dummyDir)
            let response = tryHandleSkillsCommand("/skills update --all").getOrThrow()
            @Expect(response, "No tracked ClawHub skills to update.")
        } finally {
            clearTestState(dummyDir)
        }
    }

    @TestCase
    public func checkTreatsConfiguredSkillKeyEnvAndApiKeyAsReady(): Unit {
        let slug = "skills-command-configured-check-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: configured check skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"configured-check-key\",\"primaryEnv\":\"PRIMARY_SECRET\",\"requires\":{\"env\":[\"PRIMARY_SECRET\",\"CUSTOM_ENV\"],\"config\":[\"browser.enabled\"]}}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("apiKey", JsonString("resolved-secret"))
            let envObj = JsonObject()
            envObj.put("CUSTOM_ENV", JsonString("configured"))
            entry.put("env", envObj)
            entries.put("configured-check-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills check").getOrThrow()
            @Expect(response.contains("${slug}"), true)
            @Expect(response.contains("${slug} (env:"), false)
        } finally {
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func infoTreatsConfiguredSkillKeyEnvAndApiKeyAsReady(): Unit {
        let slug = "skills-command-configured-info-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: configured info skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"configured-info-key\",\"primaryEnv\":\"PRIMARY_SECRET\",\"requires\":{\"env\":[\"PRIMARY_SECRET\",\"CUSTOM_ENV\"]}}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("apiKey", JsonString("resolved-secret"))
            let envObj = JsonObject()
            envObj.put("CUSTOM_ENV", JsonString("configured"))
            entry.put("env", envObj)
            entries.put("configured-info-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills info ${slug}").getOrThrow()
            @Expect(response.contains("${slug}"), true)
            @Expect(response.contains("✓ Ready"), true)
            @Expect(response.contains("Env PRIMARY_SECRET:"), true)
            @Expect(response.contains("Env CUSTOM_ENV:"), true)
            @Expect(response.contains("✗ missing"), false)
        } finally {
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func checkSupportsJsonOutput(): Unit {
        let slug = "skills-command-check-json-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                "---\nname: ${slug}\ndescription: json check skill\n---\n# ${slug}\n".toArray()
            )
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills check --json").getOrThrow()
            @Expect(response.contains("\"kind\":\"skills-check\""), true)
            @Expect(response.contains("\"ready\""), true)
            @Expect(response.contains("\"installRisk\""), true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func checkPrintsDoctorActionsForMissingRequirements(): Unit {
        let slug = "skills-command-doctor-actions-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: doctor actions check skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"doctor-actions-check-key\",\"primaryEnv\":\"PRIMARY_SECRET\",\"requires\":{\"env\":[\"PRIMARY_SECRET\"],\"config\":[\"channels.discord.token\"]}}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills check").getOrThrow()
            @Expect(response.contains("${slug} (env:"), true)
            @Expect(response.contains("fix: configure skills.entries.doctor-actions-check-key.env.PRIMARY_SECRET or provide shell env PRIMARY_SECRET"), true)
            @Expect(response.contains("set config path channels.discord.token to a truthy value"), true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func checkPrintsInstallerRiskHintForDirectDownloadSkill(): Unit {
        let slug = "skills-command-download-risk-check-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: download risk check skill\n" +
                    "metadata: {\"metis\":{\"requires\":{\"env\":[\"PRIMARY_SECRET\"]},\"install\":[{\"id\":\"download\",\"kind\":\"download\",\"url\":\"https://example.com/tool.zip\"}]}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills check").getOrThrow()
            @Expect(response.contains("${slug} (env:"), true)
            @Expect(response.contains("Installer risk:"), true)
            @Expect(response.contains("warn="), true)
            @Expect(response.contains("review installer source before running direct download"), true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func checkListsInstallerReviewForReadyNodeInstallerSkill(): Unit {
        let slug = "skills-command-node-risk-ready-test"
        let skillDir = skillsWorkspaceDir().join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: node risk ready skill\n" +
                    "metadata: {\"metis\":{\"install\":[{\"id\":\"node\",\"kind\":\"node\",\"package\":\"@scope/tool\"}]}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = tryHandleSkillsCommand("/skills check").getOrThrow()
            @Expect(response.contains("Installer review:"), true)
            @Expect(response.contains("${slug} (caution: review package installer before running node-based install)"), true)
        } finally {
            clearTestState(skillDir)
        }
    }
}
