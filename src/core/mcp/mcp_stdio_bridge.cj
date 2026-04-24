package metis.core.mcp

import magic.jsonable.*
import magic.log.LogUtils
import magic.utils.readFile
import magic.utils.http.HttpUtils

import metis.core.config.{CliSettingManager, GatewayUserSettings}
import metis.gateway.{gatewayRuntimeEffectiveAuthPassword, gatewayRuntimeEffectiveAuthToken}
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.runtime.GatewayHttpSurface

import std.collection.HashMap
import std.convert.*
import std.env.getVariable
import std.fs.{File, OpenMode, Path}
import std.io.*
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func mcpServeReadSecretFile(path: String): String {
    let trimmed = path.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    try {
        readFile(Path(trimmed)).trimAscii()
    } catch (e: Exception) {
        throw Exception("Failed to read secret file `${trimmed}`: ${e.message}")
    }
}

public func mcpResolveSecretOption(
    direct!: String = "",
    file!: String = "",
    directFlag!: String = "",
    fileFlag!: String = "",
    label!: String = ""
): String {
    let directValue = direct.trimAscii()
    let fileValue = file.trimAscii()
    if (!directValue.isEmpty() && !fileValue.isEmpty()) {
        throw Exception("Use either ${directFlag} or ${fileFlag} for ${label}.")
    }
    if (!fileValue.isEmpty()) {
        return mcpServeReadSecretFile(fileValue)
    }
    directValue
}

private func mcpBridgeBaseUrlFromUser(user: GatewayUserSettings): String {
    if (user.remote.enabled && !user.remote.url.trimAscii().isEmpty()) {
        return user.remote.url.trimAscii()
    }
    GatewayHttpSurface.baseUrl(buildGatewayConfigFromUserSettings(user))
}

private func mcpServeNormalizeGatewayUrl(raw: String, user: GatewayUserSettings): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return mcpBridgeBaseUrlFromUser(user)
    }
    var normalized = trimmed
    if (normalized.startsWith("ws://")) {
        normalized = "http://" + normalized[5..]
    } else if (normalized.startsWith("wss://")) {
        normalized = "https://" + normalized[6..]
    }
    if (normalized.endsWith("/ws")) {
        return normalized[..normalized.size - 3]
    }
    if (normalized.endsWith("/rpc") || normalized.endsWith("/mcp")) {
        let slash = match (normalized.lastIndexOf("/")) {
            case Some(idx) => idx
            case None => normalized.size
        }
        return normalized[..slash]
    }
    normalized
}

private func mcpServeEndpoint(rawGatewayUrl: String, user: GatewayUserSettings): String {
    let base = mcpServeNormalizeGatewayUrl(rawGatewayUrl, user)
    if (base.endsWith("/mcp")) {
        return base
    }
    if (base.endsWith("/")) {
        return base + "mcp"
    }
    base + "/mcp"
}

private func mcpServeWriteLog(stderr: File, verbose: Bool, message: String): Unit {
    if (!verbose) {
        return
    }
    try {
        stderr.write(("metis mcp serve: ${message}\n").toArray())
        stderr.flush()
    } catch (_e: Exception) {
        ()
    }
}

private func mcpServeReadLine(reader: StringReader<File>): Option<String> {
    try {
        reader.readln()
    } catch (_e: Exception) {
        None
    }
}

private func mcpServeReadContent(reader: StringReader<File>, length: Int64): String {
    let sb = StringBuilder()
    var consumed: Int64 = 0
    while (consumed < length) {
        let next = try {
            reader.read()
        } catch (_e: Exception) {
            None<Rune>
        }
        match (next) {
            case Some(ch) =>
                sb.append(ch)
                consumed += 1
            case None => break
        }
    }
    sb.toString()
}

private func mcpServeReadFrame(reader: StringReader<File>): Option<String> {
    var contentLength: Int64 = -1
    var sawHeader = false
    while (true) {
        match (mcpServeReadLine(reader)) {
            case Some(rawLine) =>
                let line = rawLine.replace("\r", "")
                sawHeader = true
                if (line.isEmpty()) {
                    break
                }
                if (line.toAsciiLower().startsWith("content-length:")) {
                    let lenText = line["Content-Length:".size..].trimAscii()
                    try {
                        contentLength = Int64.parse(lenText)
                    } catch (_e: Exception) {
                        throw Exception("Invalid Content-Length header: ${lenText}")
                    }
                }
            case None =>
                if (!sawHeader) {
                    return None<String>
                }
                break
        }
    }
    if (!sawHeader) {
        return None<String>
    }
    if (contentLength < 0) {
        throw Exception("Missing Content-Length header.")
    }
    Some<String>(mcpServeReadContent(reader, contentLength))
}

private func mcpServeWriteFrame(stdout: File, body: String): Unit {
    let payload = body.toArray()
    let header = "Content-Length: ${payload.size}\r\n\r\n"
    stdout.write(header.toArray())
    stdout.write(payload)
    stdout.flush()
}

private func mcpServeJsonRpcIdValue(root: JsonObject): JsonValue {
    match (root.get("id")) {
        case Some(id) => id
        case None => JsonString("mcp-bridge")
    }
}

private func mcpServeErrorResponse(root: JsonObject, code: Int64, message: String): String {
    let out = JsonObject()
    out.put("jsonrpc", JsonString("2.0"))
    out.put("id", mcpServeJsonRpcIdValue(root))
    let err = JsonObject()
    err.put("code", code.toJsonValue())
    err.put("message", JsonString(message))
    out.put("error", err)
    out.toJsonString()
}

private func mcpServePost(endpoint: String, headers: HashMap<String, String>, request: JsonObject): String {
    let rawOpt = try {
        HttpUtils.post(endpoint, headers, request, verify: false)
    } catch (e: Exception) {
        throw Exception("Gateway MCP request failed: ${e.message}")
    }
    match (rawOpt) {
        case Some(raw) => raw
        case None => throw Exception("Gateway MCP returned no response.")
    }
}

public func serveMetisMcpStdio(
    gatewayUrl!: String = "",
    gatewayToken!: String = "",
    gatewayPassword!: String = "",
    claudeChannelMode!: String = "auto",
    verbose!: Bool = false
): Int64 {
    let user = CliSettingManager.readGatewaySettings()
    let endpoint = mcpServeEndpoint(gatewayUrl, user)
    let token = if (!gatewayToken.trimAscii().isEmpty()) {
        gatewayToken.trimAscii()
    } else {
        gatewayRuntimeEffectiveAuthToken(user)
    }
    let password = if (!gatewayPassword.trimAscii().isEmpty()) {
        gatewayPassword.trimAscii()
    } else {
        gatewayRuntimeEffectiveAuthPassword(user)
    }
    let headers = HashMap<String, String>()
    headers["Content-Type"] = "application/json"
    if (!token.isEmpty()) {
        headers["X-Metis-Gateway-Token"] = token
    }
    if (!password.isEmpty()) {
        headers["X-Metis-Gateway-Password"] = password
    }
    let stdinPath = getVariable("CANGJIECLAW_MCP_STDIN_PATH") ?? "/dev/stdin"
    let stdoutPath = getVariable("CANGJIECLAW_MCP_STDOUT_PATH") ?? "/dev/stdout"
    let stderrPath = getVariable("CANGJIECLAW_MCP_STDERR_PATH") ?? "/dev/stderr"
    try (stdinFile = File(stdinPath, OpenMode.Read)) {
        try (stdoutFile = File(stdoutPath, OpenMode.Write)) {
            try (stderrFile = File(stderrPath, OpenMode.Write)) {
                let reader = StringReader(stdinFile)
                mcpServeWriteLog(stderrFile, verbose, "bridge ready endpoint=${endpoint} claudeChannelMode=${claudeChannelMode.trimAscii().toAsciiLower()}")
                while (true) {
                    let frame = try {
                        mcpServeReadFrame(reader)
                    } catch (e: Exception) {
                        mcpServeWriteLog(stderrFile, verbose, "frame read failed: ${e.message}")
                        break
                    }
                    match (frame) {
                        case Some(body) =>
                            mcpServeWriteLog(stderrFile, verbose, "request bytes=${body.size}")
                            let requestRoot = try {
                                JsonValue.fromStr(body).asObject()
                            } catch (e: Exception) {
                                let fallback = JsonObject()
                                let errorBody = mcpServeErrorResponse(fallback, -32700, "Parse error: ${e.message}")
                                mcpServeWriteFrame(stdoutFile, errorBody)
                                continue
                            }
                            let method = match (requestRoot.get("method")) {
                                case Some(v) =>
                                    try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
                                case None => ""
                            }
                            if (method.isEmpty()) {
                                let errorBody = mcpServeErrorResponse(requestRoot, -32600, "Invalid Request: missing method.")
                                mcpServeWriteFrame(stdoutFile, errorBody)
                                continue
                            }
                            let hasId = requestRoot.containsKey("id")
                            if (!hasId) {
                                mcpServeWriteLog(stderrFile, verbose, "notification method=${method}")
                                continue
                            }
                            let responseBody = try {
                                mcpServePost(endpoint, headers, requestRoot)
                            } catch (e: Exception) {
                                mcpServeErrorResponse(requestRoot, -32000, e.message)
                            }
                            mcpServeWriteFrame(stdoutFile, responseBody)
                        case None =>
                            mcpServeWriteLog(stderrFile, verbose, "stdin closed")
                            break
                    }
                }
            }
        }
    } catch (e: Exception) {
        LogUtils.error("MCP stdio bridge failed: ${e.message}")
        return 1
    }
    0
}
