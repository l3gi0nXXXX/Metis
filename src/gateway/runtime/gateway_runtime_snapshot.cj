package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.CliConfig

import std.convert.Parsable
import std.fs.{File, exists, Path}
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private var gatewayRuntimeStartedAtMs: Int64 = 0
private var gatewayRuntimeUpdatedAtMs: Int64 = 0
private var gatewayRuntimeRunning: Bool = false
private var gatewayRuntimeStatus: String = "stopped"
private var gatewayRuntimeReason: String = ""

private func gatewayRuntimeNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func gatewayRuntimePersist(): Unit {
    let root = JsonObject()
    root.put("running", gatewayRuntimeRunning.toJsonValue())
    root.put("status", JsonString(gatewayRuntimeStatus))
    root.put("reason", JsonString(gatewayRuntimeReason))
    root.put("startedAtMs", gatewayRuntimeStartedAtMs.toJsonValue())
    root.put("updatedAtMs", gatewayRuntimeUpdatedAtMs.toJsonValue())
    root.put("serveLockPresent", gatewayAnotherServeInstanceSeemsRunning().toJsonValue())
    File.writeTo(gatewayRuntimeStatePath(), root.toJsonString().toArray())
}

private func gatewayRuntimeSnapshotInt64(root: JsonObject, key: String): Int64 {
    match (root.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) { 0 }
        case None => 0
    }
}

public func gatewayRuntimeStatePath(): Path {
    CliConfig.dotDir.join("gateway-runtime-state.json")
}

public func gatewayRuntimeMarkStarting(): Unit {
    gatewayRuntimeStartedAtMs = gatewayRuntimeNowMs()
    gatewayRuntimeUpdatedAtMs = gatewayRuntimeStartedAtMs
    gatewayRuntimeRunning = false
    gatewayRuntimeStatus = "starting"
    gatewayRuntimeReason = ""
    gatewayRuntimePersist()
}

public func gatewayRuntimeMarkRunning(): Unit {
    let now = gatewayRuntimeNowMs()
    if (gatewayRuntimeStartedAtMs <= 0) {
        gatewayRuntimeStartedAtMs = now
    }
    gatewayRuntimeUpdatedAtMs = now
    gatewayRuntimeRunning = true
    gatewayRuntimeStatus = "running"
    gatewayRuntimeReason = ""
    gatewayRuntimePersist()
}

public func gatewayRuntimeHeartbeat(): Unit {
    gatewayRuntimeUpdatedAtMs = gatewayRuntimeNowMs()
    if (gatewayRuntimeStatus.trimAscii().isEmpty()) {
        gatewayRuntimeStatus = if (gatewayRuntimeRunning) { "running" } else { "stopped" }
    }
    gatewayRuntimePersist()
}

public func gatewayRuntimeMarkStopped(reason!: String = "stopped"): Unit {
    gatewayRuntimeUpdatedAtMs = gatewayRuntimeNowMs()
    gatewayRuntimeRunning = false
    gatewayRuntimeStatus = "stopped"
    gatewayRuntimeReason = reason.trimAscii()
    gatewayRuntimePersist()
}

public func gatewayRuntimeMarkStoppedFromCli(reason!: String = "stopped"): Unit {
    let path = gatewayRuntimeStatePath()
    var startedAtMs: Int64 = gatewayRuntimeStartedAtMs
    if (exists(path)) {
        try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            let persistedStartedAtMs = gatewayRuntimeSnapshotInt64(root, "startedAtMs")
            if (persistedStartedAtMs > 0) {
                startedAtMs = persistedStartedAtMs
            }
        } catch (_: Exception) {
            ()
        }
    }
    gatewayRuntimeStartedAtMs = startedAtMs
    gatewayRuntimeUpdatedAtMs = gatewayRuntimeNowMs()
    gatewayRuntimeRunning = false
    gatewayRuntimeStatus = "stopped"
    gatewayRuntimeReason = reason.trimAscii()
    gatewayRuntimePersist()
}

public func gatewayRuntimeSnapshot(): JsonObject {
    let path = gatewayRuntimeStatePath()
    if (exists(path)) {
        try {
            return JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
        } catch (_e: Exception) {
            ()
        }
    }
    let root = JsonObject()
    root.put("running", gatewayRuntimeRunning.toJsonValue())
    root.put("status", JsonString(gatewayRuntimeStatus))
    root.put("reason", JsonString(gatewayRuntimeReason))
    root.put("startedAtMs", gatewayRuntimeStartedAtMs.toJsonValue())
    root.put("updatedAtMs", gatewayRuntimeUpdatedAtMs.toJsonValue())
    root.put("serveLockPresent", gatewayAnotherServeInstanceSeemsRunning().toJsonValue())
    root
}
