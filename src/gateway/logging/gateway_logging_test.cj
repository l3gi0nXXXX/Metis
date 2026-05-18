package metis.gateway.logging

import magic.config.Config

import metis.core.config.{CliConfig, CliSettingManager}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists}
import std.regex.Regex
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func loggingTestRestoreEnv(name: String, oldValue: Option<String>): Unit {
    match (oldValue) {
        case Some(value) => setVariable(name, value)
        case None => setVariable(name, "")
    }
}

private func loggingTestHome(label: String): Path {
    let root = Path("/tmp/metis-logging-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
    Directory.create(root, recursive: true)
    root
}

private func loggingTestReset(home: Path): Unit {
    setVariable("METIS_HOME", home.toString())
    CliConfig.invalidatePathCache()
    CliSettingManager.invalidate()
    gatewayLoggingResetForTest()
}

private func loggingTestOccurrenceCount(text: String, needle: String): Int64 {
    if (needle.isEmpty()) {
        return 0
    }
    text.split(needle).size - 1
}

@Test
public class GatewayLoggingTest {
    @TestCase
    public func resolveSettingsUsesStableCurrentFileAndEnvOverrides(): Unit {
        let oldHome = getVariable("METIS_HOME")
        let oldLevel = getVariable("METIS_LOG_LEVEL")
        let oldFile = getVariable("METIS_LOG_FILE")
        let oldConsoleLevel = getVariable("METIS_CONSOLE_LEVEL")
        let oldConsoleStyle = getVariable("METIS_CONSOLE_STYLE")
        let home = loggingTestHome("settings")
        let file = home.join("logs").join("fixed-gateway.log").toString()
        let configuredFile = home.join("logs").join("configured-gateway.log").toString()
        try {
            loggingTestReset(home)
            File.writeTo(
                home.join("metis.json"),
                ("{\"gateway\":{\"logging\":{\"level\":\"trace\",\"file\":\"${configuredFile}\"," +
                    "\"consoleLevel\":\"error\",\"consoleStyle\":\"pretty\",\"maxFileBytes\":12345}}}").toArray()
            )
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
            let configured = gatewayLoggingResolveSettings()
            @Expect(configured.level, "trace")
            @Expect(configured.file, configuredFile)
            @Expect(configured.consoleLevel, "error")
            @Expect(configured.consoleStyle, "pretty")
            @Expect(configured.maxFileBytes, 12345)

            gatewayLoggingResetForTest()
            setVariable("METIS_LOG_LEVEL", "debug")
            setVariable("METIS_LOG_FILE", file)
            setVariable("METIS_CONSOLE_LEVEL", "warn")
            setVariable("METIS_CONSOLE_STYLE", "json")
            let first = gatewayLoggingResolveSettings()
            let second = gatewayLoggingResolveSettings()
            @Expect(first.level, "debug")
            @Expect(first.file, file)
            @Expect(second.file, file)
            @Expect(first.consoleLevel, "warn")
            @Expect(first.consoleStyle, "json")
            @Expect(gatewayLoggingCurrentLogFile(), file)
            @Expect(Config.logFile, file)
        } finally {
            loggingTestRestoreEnv("METIS_HOME", oldHome)
            loggingTestRestoreEnv("METIS_LOG_LEVEL", oldLevel)
            loggingTestRestoreEnv("METIS_LOG_FILE", oldFile)
            loggingTestRestoreEnv("METIS_CONSOLE_LEVEL", oldConsoleLevel)
            loggingTestRestoreEnv("METIS_CONSOLE_STYLE", oldConsoleStyle)
            CliConfig.invalidatePathCache()
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
        }
    }

    @TestCase
    public func loggerWritesJsonlRedactsTruncatesAndChildSubsystem(): Unit {
        let oldHome = getVariable("METIS_HOME")
        let oldLevel = getVariable("METIS_LOG_LEVEL")
        let oldFile = getVariable("METIS_LOG_FILE")
        let oldConsoleLevel = getVariable("METIS_CONSOLE_LEVEL")
        let home = loggingTestHome("jsonl")
        let file = home.join("logs").join("gateway-jsonl.log").toString()
        try {
            loggingTestReset(home)
            setVariable("METIS_LOG_LEVEL", "debug")
            setVariable("METIS_LOG_FILE", file)
            setVariable("METIS_CONSOLE_LEVEL", "silent")
            var longError = ""
            for (_i in 0..2000) {
                longError += "x"
            }
            let meta = JsonObject()
            meta.put("token", JsonString("123456:telegram_secret"))
            meta.put("authorization", JsonString("Bearer secret"))
            meta.put("error", JsonString(longError))
            let logger = metisCreateSubsystemLogger("gateway").child("channel/telegram")
            logger.info(MetisLogEvent.channelStarted, "started app_secret_xxx", meta: meta)
            @Expect(exists(Path(file)), true)
            let raw = String.fromUtf8(File.readFrom(Path(file)))
            @Expect(raw.contains("\"time\""), true)
            @Expect(raw.contains("telegram_secret"), false)
            @Expect(raw.contains("app_secret_xxx"), false)
            @Expect(raw.contains("Bearer secret"), false)
            @Expect(raw.contains("[truncated]"), true)
            let row = JsonValue.fromStr(raw.trimAscii()).asObject()
            @Expect(row.get("level").getOrThrow().asString().getValue(), "info")
            @Expect(row.get("subsystem").getOrThrow().asString().getValue(), "gateway/channel/telegram")
            @Expect(row.get("event").getOrThrow().asString().getValue(), "channel.started")
            let ts = row.get("time").getOrThrow().asString().getValue()
            @Expect(Regex(#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#).matches(ts), true)
            @Expect(row.get("message").getOrThrow().asString().getValue().contains("[redacted]"), true)
        } finally {
            loggingTestRestoreEnv("METIS_HOME", oldHome)
            loggingTestRestoreEnv("METIS_LOG_LEVEL", oldLevel)
            loggingTestRestoreEnv("METIS_LOG_FILE", oldFile)
            loggingTestRestoreEnv("METIS_CONSOLE_LEVEL", oldConsoleLevel)
            CliConfig.invalidatePathCache()
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
        }
    }

    @TestCase
    public func redactionCoversOpenClawDefaultSecretPatterns(): Unit {
        let oldHome = getVariable("METIS_HOME")
        let home = loggingTestHome("redaction")
        try {
            loggingTestReset(home)
            let bearer = "abcdefghijklmnopqrstuvwxyz012345"
            let openAi = "sk-abcdefghijklmnopqrstuvwxyz012345"
            let telegram = "123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
            let github = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
            let cliKey = "cli-secret-abcdefghijklmnopqrstuvwxyz"
            let pemBody = "PRIVATEKEYBODY"
            let input =
                "Authorization: Bearer ${bearer} " +
                "OPENAI_API_KEY=${openAi} " +
                "{\"accessToken\":\"${github}\"} " +
                "--api-key ${cliKey} " +
                "https://api.telegram.org/bot${telegram}/sendMessage " +
                "-----BEGIN PRIVATE KEY-----\n${pemBody}\n-----END PRIVATE KEY-----"
            let redacted = gatewayLogRedactText(input)
            @Expect(redacted.contains(bearer), false)
            @Expect(redacted.contains(openAi), false)
            @Expect(redacted.contains(telegram), false)
            @Expect(redacted.contains(github), false)
            @Expect(redacted.contains(cliKey), false)
            @Expect(redacted.contains(pemBody), false)
            @Expect(redacted.contains("[redacted]"), true)
            @Expect(redacted.contains("-----BEGIN PRIVATE KEY-----"), true)
            @Expect(redacted.contains("-----END PRIVATE KEY-----"), true)
        } finally {
            loggingTestRestoreEnv("METIS_HOME", oldHome)
            CliConfig.invalidatePathCache()
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
        }
    }

    @TestCase
    public func fileSizeCapUsesSingleWarningAndSuppressesRepeatedWrites(): Unit {
        let oldHome = getVariable("METIS_HOME")
        let oldLevel = getVariable("METIS_LOG_LEVEL")
        let oldFile = getVariable("METIS_LOG_FILE")
        let oldConsoleLevel = getVariable("METIS_CONSOLE_LEVEL")
        let home = loggingTestHome("size-cap")
        let file = home.join("logs").join("gateway-size-cap.log").toString()
        try {
            loggingTestReset(home)
            setVariable("METIS_LOG_LEVEL", "info")
            setVariable("METIS_LOG_FILE", file)
            setVariable("METIS_CONSOLE_LEVEL", "silent")
            File.writeTo(
                home.join("metis.json"),
                "{\"gateway\":{\"logging\":{\"maxFileBytes\":1}}}".toArray()
            )
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
            let logger = metisCreateSubsystemLogger("gateway")
            logger.info(MetisLogEvent.gatewayReady, "first line should trip cap")
            logger.info(MetisLogEvent.gatewayReady, "second line should stay suppressed")
            @Expect(exists(Path(file)), true)
            let raw = String.fromUtf8(File.readFrom(Path(file)))
            @Expect(loggingTestOccurrenceCount(raw, "log file size cap reached"), 1)
            @Expect(raw.contains("first line should trip cap"), false)
            @Expect(raw.contains("second line should stay suppressed"), false)
            let row = JsonValue.fromStr(raw.trimAscii()).asObject()
            @Expect(row.get("event").getOrThrow().asString().getValue(), MetisLogEvent.loggingFileSizeCap)
        } finally {
            loggingTestRestoreEnv("METIS_HOME", oldHome)
            loggingTestRestoreEnv("METIS_LOG_LEVEL", oldLevel)
            loggingTestRestoreEnv("METIS_LOG_FILE", oldFile)
            loggingTestRestoreEnv("METIS_CONSOLE_LEVEL", oldConsoleLevel)
            CliConfig.invalidatePathCache()
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
        }
    }

    @TestCase
    public func consoleLevelFiltersAndEventDictionaryIsStable(): Unit {
        let oldHome = getVariable("METIS_HOME")
        let oldFile = getVariable("METIS_LOG_FILE")
        let oldConsoleLevel = getVariable("METIS_CONSOLE_LEVEL")
        let oldLevel = getVariable("METIS_LOG_LEVEL")
        let home = loggingTestHome("console")
        try {
            loggingTestReset(home)
            setVariable("METIS_LOG_FILE", home.join("logs").join("console.log").toString())
            setVariable("METIS_LOG_LEVEL", "silent")
            setVariable("METIS_CONSOLE_LEVEL", "warn")
            gatewayLoggingCaptureConsoleForTest()
            let logger = metisCreateSubsystemLogger("gateway")
            logger.info(MetisLogEvent.gatewayReady, "ready")
            logger.warn(MetisLogEvent.rpcFailed, "rpc failed")
            let lines = gatewayLoggingCapturedConsoleForTest()
            @Expect(lines.size, 1)
            @Expect(lines[0].contains("rpc.failed"), true)
            for (event in MetisLogEvent.all()) {
                @Expect(gatewayLogEventIsKnown(event), true)
            }
            @Expect(gatewayLogEventIsKnown("not.in.dictionary"), false)
        } finally {
            loggingTestRestoreEnv("METIS_HOME", oldHome)
            loggingTestRestoreEnv("METIS_LOG_FILE", oldFile)
            loggingTestRestoreEnv("METIS_CONSOLE_LEVEL", oldConsoleLevel)
            loggingTestRestoreEnv("METIS_LOG_LEVEL", oldLevel)
            CliConfig.invalidatePathCache()
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
        }
    }
}
