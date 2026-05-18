package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.logging.gatewayLoggingResetForTest

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

private func logsOpsTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func withLogsOpsTestHome<T>(block: () -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp/metis-gateway-logs-ops-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        let oldLogFile = getVariable("METIS_LOG_FILE")
        setVariable("METIS_HOME", home.toString())
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
            match (oldLogFile) {
                case Some(value) => setVariable("METIS_LOG_FILE", value)
                case None => setVariable("METIS_LOG_FILE", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            gatewayLoggingResetForTest()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
}

@Test
public class GatewayServerMethodsOpsLogsTest {
    @TestCase
    public func logsStatusAndTailUseResolvedCurrentLogFile(): Unit {
        withLogsOpsTestHome {
            let logPath = CliConfig.logsDir.join("current-gateway.log")
            let first = "{\"time\":\"2026-05-18T10:00:00.000+08:00\",\"level\":\"info\",\"subsystem\":\"gateway\",\"event\":\"one\",\"message\":\"one\"}\n"
            let second = "{\"time\":\"2026-05-18T10:00:01.000+08:00\",\"level\":\"info\",\"subsystem\":\"gateway\",\"event\":\"two\",\"message\":\"two\"}\n"
            File.writeTo(logPath, "${first}${second}".toArray())
            setVariable("METIS_LOG_FILE", logPath.toString())
            gatewayLoggingResetForTest()

            let status = gatewayDispatchLocalMethod(GatewayRpcRequest("logs.status"))
            @Expect(status.ok, true)
            let statusRoot = status.result.asObject()
            @Expect(logsOpsTestString(statusRoot, "currentLogFile"), logPath.toString())
            @Expect(statusRoot.get("currentLogFileExists").getOrThrow().asBool().getValue(), true)

            let params = JsonObject()
            params.put("limit", 1.toJsonValue())
            let tail = gatewayDispatchLocalMethod(GatewayRpcRequest("logs.tail", params: params))
            @Expect(tail.ok, true)
            let tailRoot = tail.result.asObject()
            @Expect(logsOpsTestString(tailRoot, "file"), logPath.toString())
            @Expect(tailRoot.get("cursor").isSome(), true)
            @Expect(tailRoot.get("size").isSome(), true)
            @Expect(tailRoot.get("truncated").isSome(), true)
            @Expect(tailRoot.get("reset").isSome(), true)
            let lines = tailRoot.get("lines").getOrThrow().asArray()
            @Expect(lines.size(), 1)
            @Expect(lines[0].asString().getValue().contains("\"event\":\"two\""), true)
        }
    }
}
