package metis.core.support_surface_tests

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}
import metis.gateway.logging.{gatewayLoggingCurrentLogFile, gatewayLoggingResetForTest}
import metis.program.executeCliLogsCommand
import metis.program_support.*

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.unittest.testmacro.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonInt, JsonObject, JsonString, JsonValue}

private func withLogsCliTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-logs-cli-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_e: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    let oldMetisLogFile = getVariable("METIS_LOG_FILE")
    setVariable("METIS_HOME", testHome)
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    gatewayLoggingResetForTest()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        match (oldMetisLogFile) {
            case Some(value) => setVariable("METIS_LOG_FILE", value)
            case None => setVariable("METIS_LOG_FILE", "")
        }
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        gatewayLoggingResetForTest()
    }
}

@Test
public class CliLocalFlowsTest {
    @BeforeAll
    public func isolateMetisHome(): Unit {
        setVariable("METIS_HOME", "/tmp/metis-program-cli-local-flows-test-home")
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func localCommandSummaryRendersHumanTextWithoutRawJson(): Unit {
        let steps = ArrayList<JsonValue>()
        steps.add(JsonString("metis models current"))
        steps.add(JsonString("metis models providers"))

        let obj = JsonObject()
        obj.put("kind", JsonString("models"))
        obj.put("subcommand", JsonString("status"))
        obj.put("currentModel", JsonString("ark:kimi-k2-250905"))
        obj.put("provider", JsonString("ark"))
        obj.put("nextSteps", JsonArray(steps))

        let rendered = programSupportRenderLocalCommandSummary(obj)

        @Expect(rendered.contains("Metis models status"), true)
        @Expect(rendered.contains("Current model: ark:kimi-k2-250905"), true)
        @Expect(rendered.contains("Next steps:"), true)
        @Expect(rendered.contains("{"), false)
        @Expect(rendered.contains("\"kind\""), false)
        @Expect(rendered.contains("Machine output: rerun with --json."), true)
    }

    @TestCase
    public func localCommandSummaryHidesNestedCatalogDetails(): Unit {
        let providers = ArrayList<JsonValue>()
        providers.add(JsonString("ark"))

        let obj = JsonObject()
        obj.put("kind", JsonString("models"))
        obj.put("subcommand", JsonString("providers"))
        obj.put("providers", JsonArray(providers))

        let rendered = programSupportRenderLocalCommandSummary(obj)

        @Expect(rendered.contains("Metis models providers"), true)
        @Expect(rendered.contains("Catalog details: available with --json"), true)
    }

    @TestCase
    public func modelsStatusMentionsIndependentImageModel(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("deepseek/deepseek-v4-pro"))
        defaults.put("model", model)
        let imageModel = JsonObject()
        imageModel.put("primary", JsonString("qwen/qwen-vl-max"))
        imageModel.put("fallbacks", JsonArray([JsonString("openai/gpt-4o")]))
        defaults.put("imageModel", imageModel)
        agents.put("defaults", defaults)
        root.put("agents", agents)
        root.put("gateway", JsonObject())
        MetisConfigManager.writeRoot(root)
        CliSettingManager.applyPersistedFieldsToCliConfig()

        let rendered = programSupportRenderModelsStatus()

        @Expect(rendered.contains("Image primary: qwen:qwen-vl-max"), true)
        @Expect(rendered.contains("Image fallbacks: openai:gpt-4o"), true)
        @Expect(rendered.contains("independent from the main chat model"), true)
    }

    @TestCase
    public func pdfStatusRendersHumanTextWithoutRawJson(): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let pdfModel = JsonObject()
        pdfModel.put("primary", JsonString("anthropic/claude-sonnet-4-5"))
        defaults.put("pdfModel", pdfModel)
        defaults.put("pdfMaxPages", JsonInt(12))
        agents.put("defaults", defaults)
        root.put("agents", agents)
        MetisConfigManager.writeRoot(root)
        CliSettingManager.applyPersistedFieldsToCliConfig()

        let rendered = programSupportRenderPdfStatus()

        @Expect(rendered.contains("PDF tool status"), true)
        @Expect(rendered.contains("Model candidates: 1 (configured)"), true)
        @Expect(rendered.contains("anthropic:claude-sonnet-4-5"), true)
        @Expect(rendered.contains("native PDF: yes"), true)
        @Expect(rendered.contains("maxPages=12"), true)
        @Expect(rendered.contains("pdfjs-dist"), true)
        @Expect(rendered.contains("{"), false)
        @Expect(rendered.contains("\"ok\""), false)
        @Expect(rendered.contains("\"result\""), false)
        @Expect(rendered.contains("\"sessions\""), false)
    }

    @TestCase
    public func logFileGetterIsStableWithinProcess(): Unit {
        withLogsCliTestHome({ =>
            let first = CliConfig.logFile.toString()
            let second = CliConfig.logFile.toString()
            @Expect(first, second)
        })
    }

    @TestCase
    public func logsCliRendersRecentCurrentTailAndJsonlWithoutRawJsonByDefault(): Unit {
        withLogsCliTestHome({ =>
            let first = "{\"ts\":\"2026-05-18T10:00:00.000Z\",\"level\":\"info\",\"subsystem\":\"gateway\",\"event\":\"ready\",\"message\":\"gateway ready\"}\n"
            let second = "{\"ts\":\"2026-05-18T10:00:01.000Z\",\"level\":\"warn\",\"subsystem\":\"gateway/channel/telegram\",\"event\":\"poll.retry\",\"message\":\"retrying poll\"}\n"
            let third = "plain fallback line\n"
            let logPath = CliConfig.logsDir.join("2026_05_18-10_00_00_000.log")
            File.writeTo(logPath, "${first}${second}${third}".toArray())
            setVariable("METIS_LOG_FILE", logPath.toString())
            gatewayLoggingResetForTest()

            let (recent, recentCode) = executeCliLogsCommand(["recent", "--limit", "1"])
            @Expect(recentCode, 0)
            @Expect(recent.contains("Recent log files:"), true)
            @Expect(recent.contains("2026_05_18-10_00_00_000.log"), true)
            @Expect(recent.contains("\"level\""), false)

            let (current, currentCode) = executeCliLogsCommand(["current"])
            @Expect(currentCode, 0)
            @Expect(current.contains("Current log file:"), true)
            @Expect(current.contains(logPath.toString()), true)
            @Expect(current.contains(gatewayLoggingCurrentLogFile()), true)

            let (tail, tailCode) = executeCliLogsCommand(["tail", "--limit", "2"])
            @Expect(tailCode, 0)
            @Expect(tail.contains("poll.retry retrying poll"), true)
            @Expect(tail.contains("plain fallback line"), true)
            @Expect(tail.contains("\"message\""), false)

            let (jsonl, jsonCode) = executeCliLogsCommand(["tail", "--limit", "1", "--json"])
            @Expect(jsonCode, 0)
            let rows = jsonl.split("\n")
            @Expect(JsonValue.fromStr(rows[0]).asObject().get("type").getOrThrow().asString().getValue(), "meta")
            @Expect(JsonValue.fromStr(rows[1]).asObject().get("type").getOrThrow().asString().getValue(), "raw")
        })
    }

    @TestCase
    public func logsCliTailHonorsCursorLimitAndMaxBytes(): Unit {
        withLogsCliTestHome({ =>
            let first = "{\"ts\":\"2026-05-18T10:00:00.000Z\",\"level\":\"info\",\"subsystem\":\"gateway\",\"event\":\"one\",\"message\":\"one\"}\n"
            let second = "{\"ts\":\"2026-05-18T10:00:01.000Z\",\"level\":\"info\",\"subsystem\":\"gateway\",\"event\":\"two\",\"message\":\"two\"}\n"
            let third = "{\"ts\":\"2026-05-18T10:00:02.000Z\",\"level\":\"info\",\"subsystem\":\"gateway\",\"event\":\"three\",\"message\":\"three\"}\n"
            let logPath = CliConfig.logsDir.join("2026_05_18-10_00_01_000.log")
            File.writeTo(logPath, "${first}${second}${third}".toArray())
            setVariable("METIS_LOG_FILE", logPath.toString())
            gatewayLoggingResetForTest()

            let cursor = Int64(first.toArray().size)
            let (cursorTail, cursorCode) = executeCliLogsCommand(["tail", "--cursor", "${cursor}", "--limit", "10", "--json"])
            @Expect(cursorCode, 0)
            @Expect(cursorTail.contains("\"event\":\"one\""), false)
            @Expect(cursorTail.contains("\"event\":\"two\""), true)
            @Expect(cursorTail.contains("\"event\":\"three\""), true)

            let (limited, limitedCode) = executeCliLogsCommand(["tail", "--limit", "1", "--json"])
            @Expect(limitedCode, 0)
            @Expect(limited.contains("\"event\":\"two\""), false)
            @Expect(limited.contains("\"event\":\"three\""), true)

            let (truncated, truncatedCode) = executeCliLogsCommand(["tail", "--cursor", "0", "--max-bytes", "80", "--json"])
            @Expect(truncatedCode, 0)
            @Expect(truncated.contains("\"type\":\"notice\""), true)
            @Expect(truncated.contains("truncated"), true)
        })
    }
}
