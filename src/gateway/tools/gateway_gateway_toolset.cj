package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.{GatewayToolRuntimeContext, gatewayActionIsProtectedPathSensitive, gatewayActionIsReadOnly, gatewayActionNormalize, gatewayConfigPathIsProtected, gatewayActionRequiresExplicitUserRequest, gatewayActionRequiresOwner, gatewayCurrentToolRuntimeContext}
import metis.core.config.MetisPaths
import metis.io.PrintUtils

import std.fs.{Path, exists}
import std.process.executeWithOutput

import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

public func gatewayToolRequiresOwnerApproval(action: String): Bool {
    gatewayActionRequiresOwner(action)
}

public func gatewayToolRequiresExplicitRequestApproval(action: String): Bool {
    gatewayActionRequiresExplicitUserRequest(action)
}

public func gatewayToolAutoOwnerApprovedForSource(sourceLabel: String): Bool {
    let normalized = sourceLabel.trimAscii().toAsciiLower()
    normalized == "cli" || normalized == "control-ui" || normalized == "dashboard" || normalized == "cron"
}

private func gatewayToolScopeAllowsOwner(scopes: Array<String>): Bool {
    for (scope in scopes) {
        let normalized = scope.trimAscii().toAsciiLower()
        if (normalized == "admin" ||
            normalized == "write" ||
            normalized == "approvals" ||
            normalized == "operator" ||
            normalized == "operator.admin" ||
            normalized == "operator.write") {
            return true
        }
    }
    false
}

public func gatewayToolAutoOwnerApprovedForRuntimeContext(context: GatewayToolRuntimeContext): Bool {
    if (gatewayToolScopeAllowsOwner(context.operatorScopes)) {
        return true
    }
    if (!context.declaredUser.trimAscii().isEmpty() && gatewayToolAutoOwnerApprovedForSource(context.sourceLabel)) {
        return true
    }
    gatewayToolAutoOwnerApprovedForSource(context.sourceLabel)
}

private func gatewayToolPromptContainsAny(prompt: String, terms: Array<String>): Bool {
    let normalizedPrompt = prompt.trimAscii().toAsciiLower()
    if (normalizedPrompt.isEmpty()) {
        return false
    }
    for (term in terms) {
        let normalized = term.trimAscii().toAsciiLower()
        if (!normalized.isEmpty() && normalizedPrompt.contains(normalized)) {
            return true
        }
    }
    false
}

public func gatewayToolInfersExplicitRequestFromPrompt(
    action: String,
    prompt: String,
    path!: Option<String> = None<String>
): Bool {
    let normalized = gatewayActionNormalize(action)
    let normalizedPath = match (path) {
        case Some(value) => value.trimAscii().toAsciiLower()
        case None => ""
    }
    if (normalized == "config.patch" || normalized == "config.apply") {
        if (gatewayToolPromptContainsAny(prompt, [normalized, "config.patch", "config.apply", "apply config", "patch config", "update config", "modify config", "change config", "修改配置", "更新配置", "应用配置"])) {
            return true
        }
        return !normalizedPath.isEmpty() &&
            gatewayToolPromptContainsAny(prompt, [normalizedPath, normalizedPath.replace("gateway.", ""), "配置", "config"])
    }
    if (normalized == "update.run") {
        return gatewayToolPromptContainsAny(prompt, [normalized, "self-update", "update metis", "update gateway", "upgrade metis", "upgrade gateway", "更新 metis", "升级 metis", "更新 gateway", "升级 gateway"])
    }
    if (normalized == "restart") {
        return gatewayToolPromptContainsAny(prompt, [normalized, "restart gateway", "重启网关", "重启 gateway"])
    }
    if (normalized == "start") {
        return gatewayToolPromptContainsAny(prompt, [normalized, "start gateway", "启动网关", "启动 gateway"])
    }
    if (normalized == "stop") {
        return gatewayToolPromptContainsAny(prompt, [normalized, "stop gateway", "停止网关", "停止 gateway"])
    }
    if (normalized == "master_on") {
        return gatewayToolPromptContainsAny(prompt, [normalized, "master on", "开启主控", "打开主控"])
    }
    if (normalized == "master_off") {
        return gatewayToolPromptContainsAny(prompt, [normalized, "master off", "关闭主控"])
    }
    false
}

private func gatewayToolResolvedOwnerApproved(ownerApproved: Option<Bool>): Bool {
    match (ownerApproved) {
        case Some(value) => value
        case None =>
            match (gatewayCurrentToolRuntimeContext()) {
                case Some(context) => gatewayToolAutoOwnerApprovedForRuntimeContext(context)
                case None => false
            }
    }
}

private func gatewayToolResolvedExplicitRequest(action: String, path: Option<String>, explicitRequest: Option<Bool>): Bool {
    match (explicitRequest) {
        case Some(value) => value
        case None =>
            match (gatewayCurrentToolRuntimeContext()) {
                case Some(context) => gatewayToolInfersExplicitRequestFromPrompt(action, context.prompt, path: path)
                case None => false
            }
    }
}

public func gatewayToolDeniedActionJson(
    action: String,
    errorMessage!: Option<String> = None<String>,
    reasonCode!: Option<String> = None<String>,
    ownerApproved!: Bool = false,
    explicitRequest!: Bool = false,
    path!: Option<String> = None<String>,
    raw!: Option<String> = None<String>,
    note!: Option<String> = None<String>
): JsonObject {
    let normalized = gatewayActionNormalize(action)
    let out = JsonObject()
    out.put("ok", JsonBool(false))
    out.put("status", JsonString("denied"))
    out.put("action", JsonString(normalized))
    out.put(
        "error",
        JsonString(
            match (errorMessage) {
                case Some(v) =>
                    let trimmed = v.trimAscii()
                    if (trimmed.isEmpty()) {
                        "Gateway action `${normalized}` is registered on the unified Gateway main runtime, but the current authorization guard denied it."
                    } else {
                        trimmed
                    }
                case None => "Gateway action `${normalized}` is registered on the unified Gateway main runtime, but the current authorization guard denied it."
            }
        )
    )
    out.put("rejectionContract", JsonString("deny-with-reason"))
    out.put("authorizationMode", JsonString("owner-explicit-request-gated"))
    out.put("ownerRequired", gatewayToolRequiresOwnerApproval(normalized).toJsonValue())
    out.put("explicitRequestRequired", gatewayToolRequiresExplicitRequestApproval(normalized).toJsonValue())
    out.put("ownerApproved", ownerApproved.toJsonValue())
    out.put("explicitRequest", explicitRequest.toJsonValue())
    match (reasonCode) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (!trimmed.isEmpty()) {
                out.put("reasonCode", JsonString(trimmed))
            }
        case None => ()
    }
    match (path) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (!trimmed.isEmpty()) {
                out.put("path", JsonString(trimmed))
            }
        case None => ()
    }
    match (raw) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (!trimmed.isEmpty()) {
                out.put("raw", JsonString(trimmed))
            }
        case None => ()
    }
    match (note) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (!trimmed.isEmpty()) {
                out.put("note", JsonString(trimmed))
            }
        case None => ()
    }
    out
}

public func gatewayToolAuthorizationFailureJson(
    action: String,
    ownerApproved!: Bool = false,
    explicitRequest!: Bool = false,
    path!: Option<String> = None<String>,
    raw!: Option<String> = None<String>,
    note!: Option<String> = None<String>
): Option<JsonObject> {
    let normalized = gatewayActionNormalize(action)
    if (gatewayToolRequiresOwnerApproval(normalized) && !ownerApproved) {
        return Some(
            gatewayToolDeniedActionJson(
                normalized,
                errorMessage: Some("Gateway action `${normalized}` is visible on the unified Gateway main runtime, but it requires owner approval before execution."),
                reasonCode: Some("owner_required"),
                ownerApproved: ownerApproved,
                explicitRequest: explicitRequest,
                path: path,
                raw: raw,
                note: note
            )
        )
    }
    if (gatewayToolRequiresExplicitRequestApproval(normalized) && !explicitRequest) {
        return Some(
            gatewayToolDeniedActionJson(
                normalized,
                errorMessage: Some("Gateway action `${normalized}` is visible on the unified Gateway main runtime, but it requires an explicit user request before execution."),
                reasonCode: Some("explicit_request_required"),
                ownerApproved: ownerApproved,
                explicitRequest: explicitRequest,
                path: path,
                raw: raw,
                note: note
            )
        )
    }
    None<JsonObject>
}

@toolset
public class GatewayGatewayToolset {
    private func gatewayBinaryCommand(): (String, Option<Path>) {
        match (MetisPaths.projectRoot()) {
            case Some(root) =>
                let devBinary = root.join("target").join("release").join("bin").join("metis")
                if (exists(devBinary)) {
                    return (devBinary.toString(), Some(root))
                }
                return ("metis", Some(root))
            case None => ("metis", None<Path>)
        }
    }

    private func invokeGatewayCall(method: String, params!: Option<JsonObject> = None<JsonObject>): JsonObject {
        let (command, workDir) = this.gatewayBinaryCommand()
        let args = match (params) {
            case Some(obj) => ["gateway", "call", method, obj.toJsonString()]
            case None => ["gateway", "call", method]
        }
        let (exitCode, stdoutBytes, stderrBytes) = executeWithOutput(command, args, workingDirectory: workDir)
        let stdout = try { String.fromUtf8(stdoutBytes).trimAscii() } catch (_: Exception) { "" }
        let stderr = try { String.fromUtf8(stderrBytes).trimAscii() } catch (_: Exception) { "" }
        if (!stdout.isEmpty()) {
            try {
                let obj = JsonValue.fromStr(stdout).asObject()
                obj.put("exitCode", exitCode.toJsonValue())
                if (!stderr.isEmpty()) {
                    obj.put("stderr", JsonString(stderr))
                }
                return obj
            } catch (_: Exception) {
                ()
            }
        }
        let out = JsonObject()
        out.put("ok", JsonBool(exitCode == 0))
        out.put("exitCode", exitCode.toJsonValue())
        out.put("stdout", JsonString(stdout))
        out.put("stderr", JsonString(stderr))
        out
    }

    @tool[
        description: "Operate the unified Gateway runtime through the Gateway RPC surface. Safe read actions are executed directly. High-risk control or mutation actions stay visible, but require owner approval and sometimes an explicit user request before execution.",
        parameters: {
            action: "Gateway action. Supported read actions: status, health, discover, discover.detail, config.get, config.schema.lookup. High-risk actions such as start, stop, restart, master_on, master_off, config.patch, config.apply, and update.run require owner approval; config.patch, config.apply, and update.run also require an explicit user request.",
            path: "Optional config path for config.get or config.schema.lookup, such as gateway, gateway.feishu, or gateway.session.dmScope.",
            raw: "Optional raw value for config.patch or config.apply. Ignored by read-only actions.",
            note: "Optional note echoed back in denied or unsupported responses.",
            ownerApproved: "Optional. Set true only when this action is authorized for the owner/operator on the current surface.",
            explicitRequest: "Optional. Set true only when the user explicitly requested this mutation or control action."
        }
    ]
    public func gateway(
        action: String,
        path: Option<String>,
        raw: Option<String>,
        note: Option<String>,
        ownerApproved: Option<Bool>,
        explicitRequest: Option<Bool>
    ): String {
        let act = gatewayActionNormalize(action)
        PrintUtils.printTool("gateway", shortMessage: act)
        let ownerApprovedValue = gatewayToolResolvedOwnerApproved(ownerApproved)
        let explicitRequestValue = gatewayToolResolvedExplicitRequest(act, path, explicitRequest)

        if (gatewayActionIsReadOnly(act) && !(act == "config.get" || act == "config.schema.lookup")) {
            let out = this.invokeGatewayCall(act).toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "config.get" || act == "config.schema.lookup") {
            let lookupPath = match (path) {
                case Some(v) => v.trimAscii()
                case None => "gateway"
            }
            let params = JsonObject()
            params.put("path", JsonString(if (lookupPath.isEmpty()) { "gateway" } else { lookupPath }))
            let out = this.invokeGatewayCall(act, params: Some(params)).toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        match (
            gatewayToolAuthorizationFailureJson(
                act,
                ownerApproved: ownerApprovedValue,
                explicitRequest: explicitRequestValue,
                path: path,
                raw: raw,
                note: note
            )
        ) {
            case Some(denied) =>
                let out = denied.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            case None => ()
        }

        if (
            act == "start" ||
            act == "stop" ||
            act == "restart" ||
            act == "master_on" ||
            act == "master_off" ||
            act == "update.run"
        ) {
            let out = this.invokeGatewayCall(act).toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "config.patch" || act == "config.apply") {
            let params = JsonObject()
            let patchPath = match (path) {
                case Some(v) =>
                    let trimmed = v.trimAscii()
                    if (trimmed.isEmpty()) { "gateway" } else { trimmed }
                case None => "gateway"
            }
            let patchRaw = match (raw) {
                case Some(v) => v
                case None => ""
            }
            if (gatewayActionIsProtectedPathSensitive(act) && gatewayConfigPathIsProtected(patchPath)) {
                let denied = gatewayToolDeniedActionJson(
                    act,
                    errorMessage: Some("Gateway action `${act}` cannot modify protected config path `${patchPath}` on the unified Gateway main runtime."),
                    reasonCode: Some("protected_path"),
                    ownerApproved: ownerApprovedValue,
                    explicitRequest: explicitRequestValue,
                    path: Some(patchPath),
                    raw: Some(patchRaw),
                    note: note
                )
                let out = denied.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            params.put("path", JsonString(patchPath))
            params.put("raw", JsonString(patchRaw))
            let out = this.invokeGatewayCall(act, params: Some(params)).toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", JsonBool(false))
        unsupported.put("status", JsonString("unsupported"))
        unsupported.put("action", JsonString(act))
        unsupported.put("error", JsonString("Unsupported gateway action on the unified Gateway main runtime: ${act}"))
        match (note) {
            case Some(v) =>
                let trimmed = v.trimAscii()
                if (!trimmed.isEmpty()) {
                    unsupported.put("note", JsonString(trimmed))
                }
            case None => ()
        }
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }
}
