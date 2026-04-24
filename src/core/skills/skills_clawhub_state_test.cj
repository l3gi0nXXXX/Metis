package metis.core.skills

import metis.core.config.CliConfig

import std.fs.{Directory, exists, remove}
import std.unittest.testmacro.*

@Test
public class SkillsClawHubStateTest {
    @TestCase
    public func resolveSkillsInstallTargetDetectsClawHubSlugs(): Unit {
        let direct = resolveSkillsInstallTarget("calendar")
        @Expect(direct.kind, "clawhub")
        @Expect(direct.slug, "calendar")

        let legacy = resolveSkillsInstallTarget("steipete/clawdis@gog")
        @Expect(legacy.kind, "package")
        @Expect(legacy.slug, "gog")

        @Expect(isLikelyClawHubSlug("weather"), true)
        @Expect(isLikelyClawHubSlug("weather-skill"), true)
        @Expect(isLikelyClawHubSlug("owner/repo@weather"), false)
        @Expect(isLikelyClawHubSlug("bad slug"), false)
    }

    @TestCase
    public func resolveSkillsInstallRequestParsesVersionAndForceFlags(): Unit {
        let direct = resolveSkillsInstallRequest("weather --version 1.2.3 --force")
        @Expect(direct.target.kind, "clawhub")
        @Expect(direct.target.slug, "weather")
        @Expect(direct.version, "1.2.3")
        @Expect(direct.force, true)

        let directEq = resolveSkillsInstallRequest("weather --version=2.0.0")
        @Expect(directEq.target.kind, "clawhub")
        @Expect(directEq.target.slug, "weather")
        @Expect(directEq.version, "2.0.0")
        @Expect(directEq.force, false)

        let legacy = resolveSkillsInstallRequest("steipete/clawdis@gog --force")
        @Expect(legacy.target.kind, "package")
        @Expect(legacy.target.slug, "gog")
        @Expect(legacy.version, "")
        @Expect(legacy.force, true)
    }

    @TestCase
    public func resolveSkillsUpdateRequestParsesAllFlag(): Unit {
        let empty = resolveSkillsUpdateRequest("")
        @Expect(empty.all, true)
        @Expect(empty.slug, "")
        @Expect(empty.valid, true)

        let all = resolveSkillsUpdateRequest("--all")
        @Expect(all.all, true)
        @Expect(all.slug, "")
        @Expect(all.valid, true)

        let one = resolveSkillsUpdateRequest("weather")
        @Expect(one.all, false)
        @Expect(one.slug, "weather")
        @Expect(one.valid, true)

        let invalid = resolveSkillsUpdateRequest("weather --all")
        @Expect(invalid.valid, false)
    }

    @TestCase
    public func resolveSkillsSearchRequestParsesLimitAndBrowseAll(): Unit {
        let empty = resolveSkillsSearchRequest("")
        @Expect(empty.query, "")
        @Expect(empty.limit, 0)
        @Expect(empty.json, false)
        @Expect(empty.valid, true)

        let simple = resolveSkillsSearchRequest("weather")
        @Expect(simple.query, "weather")
        @Expect(simple.limit, 0)
        @Expect(simple.json, false)
        @Expect(simple.valid, true)

        let limited = resolveSkillsSearchRequest("--limit 20 react performance")
        @Expect(limited.query, "react performance")
        @Expect(limited.limit, 20)
        @Expect(limited.json, false)
        @Expect(limited.valid, true)

        let limitedEq = resolveSkillsSearchRequest("calendar --limit=5 --json")
        @Expect(limitedEq.query, "calendar")
        @Expect(limitedEq.limit, 5)
        @Expect(limitedEq.json, true)
        @Expect(limitedEq.valid, true)

        let invalid = resolveSkillsSearchRequest("--limit nope")
        @Expect(invalid.valid, false)
    }

    /*
    @TestCase
    public func recordsAndReadsClawHubOriginAndLockfile(): Unit {
        let workspaceDir = CliConfig.cwd.join("target").join("skills_clawhub_state_test")
        try {
            if (exists(workspaceDir)) {
                remove(workspaceDir, recursive: true)
            }
            Directory.create(workspaceDir, recursive: true)

            recordInstalledClawHubSkill(
                workspaceDir,
                "calendar",
                "1.2.3",
                installedAtMs: 12345
            )

            let skillDir = resolveClawHubSkillInstallDir(workspaceDir, "calendar")
            @Expect(exists(clawHubSkillOriginPath(skillDir)), true)
            @Expect(exists(clawHubSkillsLockfilePath(workspaceDir)), true)

            let origin = readClawHubSkillOrigin(skillDir).getOrThrow()
            @Expect(origin.registry, "https://clawhub.ai")
            @Expect(origin.slug, "calendar")
            @Expect(origin.installedVersion, "1.2.3")
            @Expect(origin.installedAt, 12345)

            let lock = readClawHubSkillsLockfile(workspaceDir)
            @Expect(lock.skills.size, 1)
            @Expect(lock.skills["calendar"].version, "1.2.3")
            @Expect(lock.skills["calendar"].installedAt, 12345)
            let tracked = readTrackedClawHubSkillSlugs(workspaceDir)
            @Expect(tracked.size, 1)
            @Expect(tracked[0], "calendar")

            refreshTrackedClawHubSkillVersion(workspaceDir, "calendar", "1.2.4")
            let refreshed = readClawHubSkillOrigin(skillDir).getOrThrow()
            @Expect(refreshed.installedVersion, "1.2.4")
            @Expect(readClawHubSkillsLockfile(workspaceDir).skills["calendar"].version, "1.2.4")
        } finally {
            if (exists(workspaceDir)) {
                remove(workspaceDir, recursive: true)
            }
        }
    }
    */

    /*
    @TestCase
    public func trackedClawHubSkillSlugsStaySorted(): Unit {
        let workspaceDir = CliConfig.cwd.join("target").join("skills_clawhub_state_sorted_test")
        try {
            if (exists(workspaceDir)) {
                remove(workspaceDir, recursive: true)
            }
            Directory.create(workspaceDir, recursive: true)

            recordInstalledClawHubSkill(workspaceDir, "zeta", "1.0.0", installedAtMs: 1)
            recordInstalledClawHubSkill(workspaceDir, "alpha", "1.0.0", installedAtMs: 2)
            recordInstalledClawHubSkill(workspaceDir, "middle", "1.0.0", installedAtMs: 3)

            let tracked = readTrackedClawHubSkillSlugs(workspaceDir)
            @Expect(tracked.size, 3)
            @Expect(tracked[0], "alpha")
            @Expect(tracked[1], "middle")
            @Expect(tracked[2], "zeta")
            @Expect(isTrackedClawHubSkill(workspaceDir, "alpha"), true)
            @Expect(isTrackedClawHubSkill(workspaceDir, "missing"), false)
        } finally {
            if (exists(workspaceDir)) {
                remove(workspaceDir, recursive: true)
            }
        }
    }
    */
}
