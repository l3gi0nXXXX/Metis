package metis.gateway.core

import magic.jsonable.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public class GatewayTelegramNativeCommandContext {
    public let spec: GatewayTelegramNativeCommandSpec
    public let command: String
    public let rawText: String
    public let commandText: String
    public let argsText: String
    public let senderId: String
    public let accountId: String
    public let sessionKey: String
    public let isCallback: Bool

    public init(
        spec: GatewayTelegramNativeCommandSpec,
        command: String,
        rawText: String,
        commandText: String,
        argsText: String,
        senderId: String,
        accountId: String,
        sessionKey: String,
        isCallback!: Bool = false
    ) {
        this.spec = spec
        this.command = command
        this.rawText = rawText
        this.commandText = commandText
        this.argsText = argsText
        this.senderId = senderId
        this.accountId = accountId
        this.sessionKey = sessionKey
        this.isCallback = isCallback
    }
}

public class GatewayTelegramNativeCommandDecision {
    public let handled: Bool
    public let context: Option<GatewayTelegramNativeCommandContext>
    public let preflightReply: String

    public init(
        handled: Bool,
        context!: Option<GatewayTelegramNativeCommandContext> = None,
        preflightReply!: String = ""
    ) {
        this.handled = handled
        this.context = context
        this.preflightReply = preflightReply
    }
}

public func gatewayTelegramNativeCommandNameFromText(text: String): String {
    let normalized = text.trimAscii()
    if (!normalized.startsWith("/")) {
        return ""
    }
    let token = normalized.split(" ", 2)[0].trimAscii()
    if (token.size <= 1) {
        return ""
    }
    let withoutSlash = token[1..]
    match (withoutSlash.indexOf("@")) {
        case Some(idx) => withoutSlash[..idx].trimAscii().toAsciiLower()
        case None => withoutSlash.trimAscii().toAsciiLower()
    }
}

public func gatewayTelegramNativeCommandArgsFromText(text: String): String {
    let normalized = text.trimAscii()
    if (!normalized.startsWith("/")) {
        return ""
    }
    let parts = normalized.split(" ", 2)
    if (parts.size > 1) {
        return parts[1].trimAscii()
    }
    ""
}

public func gatewayTelegramNativeCommandHandlerStatus(command: String): String {
    match (command.trimAscii().toAsciiLower()) {
        case "help" | "commands" | "tools" | "skill" | "status" | "tasks" | "approve" |
            "context" | "btw" | "export-session" | "tts" | "whoami" | "session" |
            "sessions" | "subagents" | "approvals" | "focus" | "unfocus" | "agents" |
            "kill" | "steer" | "config" | "mcp" | "plugins" | "debug" | "usage" |
            "stop" | "restart" | "activation" | "pair" | "send" | "reset" | "new" |
            "compact" | "think" | "verbose" | "fast" | "reasoning" | "elevated" |
            "exec" | "model" | "models" | "queue" | "bash" => "implemented"
        case "allowlist" => "approval_required"
        case "acp" => "not_applicable"
        case _ => "missing"
    }
}

public func gatewayTelegramNativeCommandStatusIsAllowed(status: String): Bool {
    let normalized = status.trimAscii().toAsciiLower()
    normalized == "implemented" || normalized == "approval_required" || normalized == "not_applicable"
}

public func gatewayTelegramNativeCommandCatalogValidation(): JsonObject {
    let invalidStatuses = JsonArray([])
    let missingHandlers = JsonArray([])
    let rows = JsonArray([])
    for (entry in gatewayTelegramNativeCommandCatalog()) {
        let handlerStatus = gatewayTelegramNativeCommandHandlerStatus(entry.command)
        let row = JsonObject()
        row.put("command", JsonString(entry.command))
        row.put("catalogStatus", JsonString(entry.status))
        row.put("handlerStatus", JsonString(handlerStatus))
        rows.add(row)
        if (!gatewayTelegramNativeCommandStatusIsAllowed(entry.status)) {
            invalidStatuses.add(JsonString(entry.command))
        }
        if (entry.status == "implemented" && handlerStatus != "implemented") {
            missingHandlers.add(JsonString(entry.command))
        }
    }
    let out = JsonObject()
    out.put("ok", (invalidStatuses.size() == 0 && missingHandlers.size() == 0).toJsonValue())
    out.put("invalidStatuses", invalidStatuses)
    out.put("missingHandlers", missingHandlers)
    out.put("commands", rows)
    out
}

public class GatewayTelegramNativeCommandRuntime {
    public init() {}

    public func resolveText(
        text: String,
        senderId: String,
        accountId: String,
        sessionKey: String,
        authorizedForOperator: Bool
    ): GatewayTelegramNativeCommandDecision {
        let command = gatewayTelegramNativeCommandNameFromText(text)
        if (command.isEmpty()) {
            return GatewayTelegramNativeCommandDecision(false)
        }
        match (gatewayFindTelegramNativeCommandSpec(command)) {
            case Some(spec) =>
                let args = gatewayTelegramNativeCommandArgsFromText(text)
                let commandText = if (args.isEmpty()) { "/${spec.command}" } else { "/${spec.command} ${args}" }
                this.resolveSpec(spec, text, commandText, args, senderId, accountId, sessionKey, authorizedForOperator)
            case None => GatewayTelegramNativeCommandDecision(false)
        }
    }

    public func resolveCallbackData(
        data: String,
        senderId: String,
        accountId: String,
        sessionKey: String,
        authorizedForOperator: Bool
    ): GatewayTelegramNativeCommandDecision {
        let parts = data.trimAscii().split(":", 3)
        if (parts.size < 3 || parts[0] != "cmd") {
            return GatewayTelegramNativeCommandDecision(false)
        }
        let command = parts[1].trimAscii()
        let value = parts[2].trimAscii()
        match (gatewayFindTelegramNativeCommandSpec(command)) {
            case Some(spec) =>
                let commandText = if (value.isEmpty()) { "/${spec.command}" } else { "/${spec.command} ${value}" }
                this.resolveSpec(spec, data, commandText, value, senderId, accountId, sessionKey, authorizedForOperator, isCallback: true)
            case None =>
                GatewayTelegramNativeCommandDecision(true, preflightReply: this.commandJson("telegram_callback", "not_found", ok: false, message: "native command callback target not found").toJsonString())
        }
    }

    private func resolveSpec(
        spec: GatewayTelegramNativeCommandSpec,
        rawText: String,
        commandText: String,
        argsText: String,
        senderId: String,
        accountId: String,
        sessionKey: String,
        authorizedForOperator: Bool,
        isCallback!: Bool = false
    ): GatewayTelegramNativeCommandDecision {
        let context = GatewayTelegramNativeCommandContext(
            spec,
            spec.command,
            rawText,
            commandText,
            argsText,
            senderId,
            accountId,
            sessionKey,
            isCallback: isCallback
        )
        let reply = this.preflightReply(context, authorizedForOperator)
        GatewayTelegramNativeCommandDecision(true, context: Some(context), preflightReply: reply)
    }

    private func preflightReply(context: GatewayTelegramNativeCommandContext, authorizedForOperator: Bool): String {
        let spec = context.spec
        if (!gatewayTelegramNativeCommandStatusIsAllowed(spec.status)) {
            return this.commandJson(spec.command, "invalid_catalog_status", ok: false, message: "Telegram native command catalog status is not supported.").toJsonString()
        }
        if ((spec.auth == "operator" || spec.auth == "approval") && !authorizedForOperator) {
            let denied = this.commandJson(spec.command, "rejected", ok: false, message: "sender is not authorized for /${spec.command}")
            denied.put("auth", JsonString(spec.auth))
            denied.put("senderId", JsonString(context.senderId))
            return denied.toJsonString()
        }
        if (spec.status == "not_applicable") {
            let out = this.commandJson(spec.command, "not_applicable", ok: false, message: spec.notApplicableReason)
            out.put("category", JsonString(spec.category))
            return out.toJsonString()
        }
        if (spec.status == "approval_required") {
            let message = if (spec.notApplicableReason.trimAscii().isEmpty()) {
                "This Telegram native command requires the Gateway approval/control surface."
            } else {
                spec.notApplicableReason
            }
            let out = this.commandJson(spec.command, "approval_required", ok: false, message: message)
            out.put("category", JsonString(spec.category))
            return out.toJsonString()
        }
        ""
    }

    private func commandJson(action: String, status: String, ok!: Bool = true, message!: String = ""): JsonObject {
        let out = JsonObject()
        out.put("ok", ok.toJsonValue())
        out.put("status", JsonString(status))
        out.put("action", JsonString(action))
        if (!message.trimAscii().isEmpty()) {
            out.put("message", JsonString(message.trimAscii()))
        }
        out
    }
}
