package metis.core.skills

import metis.core.config.CliConfig

import std.fs.{Directory, File, OpenMode, Path, exists, remove}
import std.unittest.testmacro.*

@Test
public class SkillsClawHubTransportTest {
    private func cleanup(root: Path): Unit {
        setClawHubHttpGetForTest(None)
        setClawHubArchiveRootForTest(None)
        if (exists(root)) {
            remove(root, recursive: true)
        }
        let dotDir = CliConfig.cwd.join(".clawhub")
        if (exists(dotDir)) {
            remove(dotDir, recursive: true)
        }
    }

    @TestCase
    public func searchFormatsBrowseAllAndJson(): Unit {
        let raw = "{\"results\":[{\"slug\":\"weather\",\"displayName\":\"Weather\",\"summary\":\"forecast\",\"version\":\"1.2.3\",\"updatedAt\":42}]}"
        try {
            setClawHubHttpGetForTest(Some({ _url: String => raw }))
            let text = searchClawHubSkillsText(SkillsSearchRequest(query: "weather", limit: 5))
            @Expect(text.contains("weather @1.2.3"), true)
            @Expect(text.contains("Name: Weather"), true)
            @Expect(text.contains("Summary: forecast"), true)

            let json = searchClawHubSkillsText(SkillsSearchRequest(limit: 5, json: true))
            @Expect(json, raw)
        } finally {
            setClawHubHttpGetForTest(None)
        }
    }

    /*
    @TestCase
    public func installWritesTrackedMetadataFromNativeTransport(): Unit {
        let slug = "native-install-skill"
        let workspaceRoot = CliConfig.cwd.join("skills").join(slug)
        let archiveRoot = CliConfig.cwd.join("target").join("test-clawhub-archive")
        let skillFile = archiveRoot.join("SKILL.md")
        try {
            cleanup(workspaceRoot)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
            Directory.create(archiveRoot, recursive: true)
            File.writeTo(
                skillFile,
                "---\nname: ${slug}\nversion: 3.2.1\ndescription: native test\n---\n# ${slug}\n".toArray()
            )
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"${slug}\"},\"latestVersion\":{\"version\":\"3.2.1\"}}"
            }))
            setClawHubArchiveRootForTest(Some({ _slug: String, _version: String => archiveRoot }))

            let result = installClawHubSkill(CliConfig.cwd, slug)
            @Expect(result.ok, true)
            @Expect(exists(resolveClawHubSkillInstallDir(CliConfig.cwd, slug).join("SKILL.md")), true)
            let origin = readClawHubSkillOrigin(resolveClawHubSkillInstallDir(CliConfig.cwd, slug))
            @Expect(origin.isSome(), true)
            @Expect(origin.getOrThrow().installedVersion, "3.2.1")
        } finally {
            cleanup(workspaceRoot)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
        }
    }
    */

    /*
    @TestCase
    public func updateUsesLatestVersionAndPreservesPreviousVersion(): Unit {
        let slug = "native-update-skill"
        let skillDir = resolveClawHubSkillInstallDir(CliConfig.cwd, slug)
        let archiveRoot = CliConfig.cwd.join("target").join("test-clawhub-update-archive")
        try {
            cleanup(skillDir)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                "---\nname: ${slug}\nversion: 1.0.0\n---\n# ${slug}\n".toArray()
            )
            recordInstalledClawHubSkill(CliConfig.cwd, slug, "1.0.0", installedAtMs: 1)

            Directory.create(archiveRoot, recursive: true)
            File.writeTo(
                archiveRoot.join("SKILL.md"),
                "---\nname: ${slug}\nversion: 2.0.0\n---\n# ${slug}\n".toArray()
            )
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"${slug}\"},\"latestVersion\":{\"version\":\"2.0.0\"}}"
            }))
            setClawHubArchiveRootForTest(Some({ _slug: String, _version: String => archiveRoot }))

            let results = updateClawHubSkills(CliConfig.cwd, [slug])
            @Expect(results.size, 1)
            @Expect(results[0].ok, true)
            @Expect(results[0].previousVersion, "1.0.0")
            @Expect(results[0].version, "2.0.0")
        } finally {
            cleanup(skillDir)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
        }
    }
    */
}
