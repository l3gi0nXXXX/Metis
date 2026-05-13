package metis.core.support_surface_tests

import metis.cron.*

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.JsonValue

private func withCronCommandTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-cron-command-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}

private func addCronCommandFixtureJob(id: String): Unit {
    let _ = executeGatewayCronCommand([
        "cron", "add", "--name", id, "--every", "1h", "--session", "main", "--message", "hello cron"
    ])
}

@Test
public class CronCommandTest {
    @TestCase
    public func cronStatusDefaultsToHumanTextAndJsonIsExplicit(): Unit {
        withCronCommandTestHome({ =>
            addCronCommandFixtureJob("status-human")

            let (text, textCode) = executeGatewayCronCommand(["cron", "status"])
            @Expect(textCode, 0)
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("Cron status"), true)
            @Expect(text.contains("Jobs:"), true)

            let (json, jsonCode) = executeGatewayCronCommand(["cron", "status", "--json"])
            @Expect(jsonCode, 0)
            let obj = JsonValue.fromStr(json).asObject()
            @Expect(obj.get("jobs").getOrThrow().asInt().getValue(), 1)
        })
    }

    @TestCase
    public func cronListDefaultsToHumanTextAndJsonIsExplicit(): Unit {
        withCronCommandTestHome({ =>
            addCronCommandFixtureJob("list-human")

            let (text, textCode) = executeGatewayCronCommand(["cron", "list"])
            @Expect(textCode, 0)
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("ID"), true)
            @Expect(text.contains("list-human"), true)

            let (slashText, slashCode) = executeGatewayCronCommand(parseSlashCronLine("/cron list"))
            @Expect(slashCode, 0)
            @Expect(slashText.startsWith("{"), false)
            @Expect(slashText.contains("list-human"), true)

            let (json, jsonCode) = executeGatewayCronCommand(["cron", "list", "--json"])
            @Expect(jsonCode, 0)
            let obj = JsonValue.fromStr(json).asObject()
            @Expect(obj.get("jobs").getOrThrow().asArray().size(), 1)
        })
    }

    @TestCase
    public func cronRunsDefaultsToHumanTextAndJsonIsExplicit(): Unit {
        withCronCommandTestHome({ =>
            addCronCommandFixtureJob("runs-human")
            let storePath = cronStorePath(CliConfig.dotDir)
            appendCronRunLog(
                storePath,
                "runs-human",
                "success",
                1000,
                1250,
                summary: "completed",
                sessionTarget: "main"
            )

            let (text, textCode) = executeGatewayCronCommand(["cron", "runs"])
            @Expect(textCode, 0)
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("Cron runs"), true)
            @Expect(text.contains("runs-human"), true)

            let (json, jsonCode) = executeGatewayCronCommand(["cron", "runs", "--json"])
            @Expect(jsonCode, 0)
            let obj = JsonValue.fromStr(json).asObject()
            @Expect(obj.get("entries").getOrThrow().asArray().size(), 1)
        })
    }
}
