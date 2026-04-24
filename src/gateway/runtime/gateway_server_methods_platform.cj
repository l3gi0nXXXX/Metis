package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliSettingManager, GatewayUserSettings}
import metis.gateway.config.{buildGatewayConfigFromUserSettings, builtinGatewayChannelIds, registeredGatewayPluginIds}
import metis.gateway.model.GatewayConfig

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayControlUiSharedRuntimeContext(cfg: GatewayConfig): JsonObject {
    gatewayControlUiRuntimeStatusJson(cfg)
}

public func handleGatewayPlatformFamily(method: String, user: GatewayUserSettings): Option<GatewayRpcResponse> {
    if (method == "http.status") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let result = JsonObject()
        result.put("http", GatewayHttpSurface.snapshot(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "http.start") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        GatewayHttpSurface.startIfNeeded(cfg)
        let result = JsonObject()
        result.put("http", GatewayHttpSurface.snapshot(cfg))
        result.put("started", true.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.status" || method == "control-ui.status") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        return Some(GatewayRpcResponse(true, method, result: gatewayControlUiRuntimeStatusJson(cfg)))
    }
    if (method == "control_ui.contract" || method == "control-ui.contract") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let result = JsonObject()
        result.put("contract", gatewayControlUiContractJson(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.routes" || method == "control-ui.routes") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let contract = gatewayControlUiContractJson(cfg)
        let result = JsonObject()
        result.put("routes", contract.get("routes") ?? JsonArray([]))
        result.put("apiPrefix", contract.get("apiPrefix") ?? JsonString(""))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.assets" || method == "control-ui.assets") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let runtime = gatewayControlUiSharedRuntimeContext(cfg)
        let contract = match (runtime.get("contract")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let binding = match (runtime.get("binding")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let result = JsonObject()
        result.put("assetsPath", contract.get("assetsPath") ?? JsonString(""))
        result.put("rootPath", contract.get("rootPath") ?? JsonString(""))
        result.put("basePath", contract.get("basePath") ?? JsonString(""))
        result.put("httpUrl", binding.get("httpUrl") ?? JsonString(""))
        result.put("assetMode", gatewayControlUiSnapshotJson(cfg).get("assetMode") ?? JsonString("inline-fallback"))
        result.put("rootState", gatewayControlUiRootStateJson(cfg))
        result.put("summary", runtime.get("summary") ?? JsonObject())
        result.put("binding", binding)
        result.put("contract", contract)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.binding" || method == "control-ui.binding") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let runtime = gatewayControlUiSharedRuntimeContext(cfg)
        let result = JsonObject()
        result.put("binding", gatewayControlUiBindingJson(cfg))
        result.put("summary", runtime.get("summary") ?? JsonObject())
        result.put("contract", runtime.get("contract") ?? JsonObject())
        result.put("state", runtime.get("state") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.runtime" || method == "control-ui.runtime") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let result = JsonObject()
        result.put("runtime", gatewayControlUiRuntimeJson(cfg))
        result.put("summary", gatewayControlUiSharedRuntimeContext(cfg).get("summary") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.auth" || method == "control-ui.auth") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let runtime = gatewayControlUiSharedRuntimeContext(cfg)
        let result = JsonObject()
        result.put("auth", runtime.get("auth") ?? JsonObject())
        result.put("summary", runtime.get("summary") ?? JsonObject())
        result.put("binding", runtime.get("binding") ?? JsonObject())
        result.put("contract", runtime.get("contract") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.state" || method == "control-ui.state") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let runtime = gatewayControlUiSharedRuntimeContext(cfg)
        let result = JsonObject()
        result.put("state", runtime.get("state") ?? JsonObject())
        result.put("statePath", JsonString(gatewayControlUiRuntimeStatePath().toString()))
        result.put("summary", runtime.get("summary") ?? JsonObject())
        result.put("binding", runtime.get("binding") ?? JsonObject())
        result.put("contract", runtime.get("contract") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.origin_policy" || method == "control-ui.origin_policy") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let runtime = gatewayControlUiSharedRuntimeContext(cfg)
        let result = JsonObject()
        result.put("originPolicy", gatewayControlUiOriginPolicyJson(cfg))
        result.put("summary", runtime.get("summary") ?? JsonObject())
        result.put("binding", runtime.get("binding") ?? JsonObject())
        result.put("contract", runtime.get("contract") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.health" || method == "control-ui.health") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let status = gatewayControlUiSharedRuntimeContext(cfg)
        let controlUi = match (status.get("controlUi")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let started = match (controlUi.get("started")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_inner: Exception) { false }
            case None => false
        }
        let enabled = match (controlUi.get("enabled")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_inner: Exception) { false }
            case None => false
        }
        let result = JsonObject()
        result.put("controlUi", controlUi)
        result.put("auth", status.get("auth") ?? JsonObject())
        result.put("healthy", gatewayControlUiRuntimeHealthy(cfg).toJsonValue())
        result.put("summary", status.get("summary") ?? JsonObject())
        result.put("binding", status.get("binding") ?? JsonObject())
        result.put("contract", status.get("contract") ?? JsonObject())
        result.put("state", status.get("state") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.summary" || method == "control-ui.summary") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let status = gatewayControlUiRuntimeStatusJson(cfg)
        let result = JsonObject()
        result.put("summary", status.get("summary") ?? JsonObject())
        result.put("state", status.get("state") ?? JsonObject())
        result.put("controlUi", status.get("controlUi") ?? JsonObject())
        result.put("auth", status.get("auth") ?? JsonObject())
        result.put("statePath", JsonString(gatewayControlUiRuntimeStatePath().toString()))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.start" || method == "control-ui.start") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let started = GatewayControlUiRuntime.startIfEnabled(cfg)
        let result = JsonObject()
        result.put("controlUi", buildGatewayExternalSurfaceJson(user).get("controlUi") ?? JsonObject())
        result.put("started", started.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "control_ui.stop" || method == "control-ui.stop") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let stopped = GatewayControlUiRuntime.stopIfRunning(cfg)
        let result = JsonObject()
        result.put("controlUi", gatewayControlUiRuntimeStatusJson(cfg).get("controlUi") ?? JsonObject())
        result.put("stopped", stopped.toJsonValue())
        result.put("state", gatewayControlUiRuntimeStatusJson(cfg).get("state") ?? JsonObject())
        result.put("mode", JsonString("embedded-http-surface"))
        return Some(GatewayRpcResponse(false, method, result: result, error: "Control UI is embedded in the shared gateway HTTP surface; disable controlUi and restart the gateway to remove it."))
    }
    if (method == "control_ui.reload" || method == "control-ui.reload") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let reloaded = GatewayControlUiRuntime.reloadIfEnabled(cfg)
        let result = JsonObject()
        result.put("controlUi", gatewayControlUiRuntimeStatusJson(cfg).get("controlUi") ?? JsonObject())
        result.put("reloaded", reloaded.toJsonValue())
        result.put("state", gatewayControlUiRuntimeStatusJson(cfg).get("state") ?? JsonObject())
        result.put("mode", JsonString("embedded-http-surface"))
        return Some(GatewayRpcResponse(reloaded, method, result: result, error: if (reloaded) { "" } else { "Control UI is embedded in the shared gateway HTTP surface and is not reloadable independently." }))
    }
    if (method == "webchat.status") {
        let result = JsonObject()
        result.put("webchat", buildGatewayExternalSurfaceJson(user).get("webchat") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "webchat.start") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let started = GatewayControlUiRuntime.startWebchatIfEnabled(cfg)
        let result = JsonObject()
        result.put("webchat", buildGatewayExternalSurfaceJson(user).get("webchat") ?? JsonObject())
        result.put("started", started.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "webchat.reload") {
        let cfg = buildGatewayConfigFromUserSettings(user)
        let reloaded = GatewayControlUiRuntime.reloadIfEnabled(cfg)
        let result = JsonObject()
        result.put("webchat", gatewayWebchatSnapshotJson(cfg))
        result.put("reloaded", reloaded.toJsonValue())
        result.put("mode", JsonString("embedded-http-surface"))
        return Some(GatewayRpcResponse(reloaded, method, result: result, error: if (reloaded) { "" } else { "Webchat is embedded in the shared gateway HTTP surface and is not reloadable independently." }))
    }
    None
}

public func handleGatewayRuntimeMutationFamily(method: String, request: GatewayRpcRequest, user: GatewayUserSettings): Option<GatewayRpcResponse> {
    if (method == "start") {
        let started = gatewayLaunchDedicatedConsole()
        let result = JsonObject()
        result.put("status", JsonString(if (started) { "accepted" } else { "error" }))
        result.put("gateway", buildGatewayRpcStatusJson(CliSettingManager.readGatewaySettings()))
        return Some(GatewayRpcResponse(started, method, result: result, error: if (started) { "" } else { "Failed to launch gateway console." }))
    }
    if (method == "stop") {
        let code = gatewayExecuteStopServe()
        let result = JsonObject()
        result.put("status", JsonString(if (code == 0) { "ok" } else { "error" }))
        result.put("exitCode", code.toJsonValue())
        return Some(GatewayRpcResponse(code == 0, method, result: result, error: if (code == 0) { "" } else { "Failed to stop gateway serve." }))
    }
    if (method == "restart") {
        let code = gatewayExecuteRestartServe()
        let result = JsonObject()
        result.put("status", JsonString(if (code == 0) { "ok" } else { "error" }))
        result.put("exitCode", code.toJsonValue())
        return Some(GatewayRpcResponse(code == 0, method, result: result, error: if (code == 0) { "" } else { "Failed to restart gateway serve." }))
    }
    if (method == "master_on" || method == "master_off") {
        var g = CliSettingManager.readGatewaySettings()
        g.enabled = method == "master_on"
        CliSettingManager.writeGatewaySettings(g)
        let result = JsonObject()
        result.put("status", JsonString("ok"))
        result.put("gateway", buildGatewayRpcStatusJson(CliSettingManager.readGatewaySettings()))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "update.run") {
        let alreadyRunning = gatewayAnotherServeInstanceSeemsRunning()
        let code = if (alreadyRunning) { gatewayExecuteRestartServe() } else { if (gatewayLaunchDedicatedConsole()) { 0 } else { 1 } }
        let result = JsonObject()
        result.put("status", JsonString(if (code == 0) { "accepted" } else { "error" }))
        result.put("exitCode", code.toJsonValue())
        result.put("gatewayWasRunning", alreadyRunning.toJsonValue())
        result.put("compatNote", JsonString("update.run refreshes the gateway runtime by restart-or-start only. It does not fetch repository updates or perform self-update from remote sources."))
        return Some(GatewayRpcResponse(code == 0, method, result: result, error: if (code == 0) { "" } else { "Failed to refresh gateway runtime." }))
    }
    None
}
