package metis.gateway.channels.feishu

import std.collection.{ArrayList, HashMap}
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func feishuCardRedactSensitiveText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lower = text.toAsciiLower()
    if (lower.contains("authorization:") ||
        lower.contains("bearer ") ||
        lower.contains("access_token") ||
        lower.contains("refresh_token") ||
        lower.contains("tenant_secret") ||
        lower.contains("tenant secret") ||
        lower.contains("appsecret") ||
        lower.contains("app_secret") ||
        lower.contains("client_secret") ||
        lower.contains("secret") ||
        lower.contains("token=") ||
        lower.contains("password")) {
        return "[redacted]"
    }
    text
}

private func feishuCardJsonStringArray(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value.trimAscii()))
    }
    arr
}

private func feishuCardCompactJson(raw: String): String {
    let out = StringBuilder()
    var inString = false
    var escaped = false
    for (i in 0..raw.size) {
        let b = raw[i]
        if (inString) {
            out.append(raw[i..i + 1])
            if (escaped) {
                escaped = false
            } else if (b == UInt8(92)) {
                escaped = true
            } else if (b == UInt8(34)) {
                inString = false
            }
        } else if (b == UInt8(34)) {
            inString = true
            out.append(raw[i..i + 1])
        } else if (!(b == UInt8(32) || b == UInt8(10) || b == UInt8(13) || b == UInt8(9))) {
            out.append(raw[i..i + 1])
        }
    }
    out.toString()
}

private func feishuCardJsonString(obj: JsonObject): String {
    feishuCardCompactJson(obj.toJsonString())
}

private func feishuCardKitCardJsonEnvelope(card: FeishuInteractiveCard): JsonObject {
    let envelope = JsonObject()
    envelope.put("type", JsonString("card_json"))
    envelope.put("data", JsonString(feishuCardJsonString(card.toJson())))
    envelope
}

public class FeishuInteractiveCard {
    public let title: String
    public let text: String
    public let toolUseText: String
    public let footerText: String
    public let actionId: String

    public init(title!: String = "", text!: String = "", toolUseText!: String = "", footerText!: String = "", actionId!: String = "") {
        this.title = title.trimAscii()
        this.text = text.trimAscii()
        this.toolUseText = toolUseText.trimAscii()
        this.footerText = footerText.trimAscii()
        this.actionId = actionId.trimAscii()
    }

    public func fallbackText(): String {
        let parts = ArrayList<String>()
        if (!this.text.isEmpty()) {
            parts.add(this.text)
        }
        if (!this.toolUseText.isEmpty()) {
            parts.add(this.toolUseText)
        }
        if (!this.footerText.isEmpty()) {
            parts.add(this.footerText)
        }
        let body = String.join(parts.toArray(), delimiter: "\n\n")
        if (this.title.isEmpty()) {
            return body
        }
        if (body.isEmpty()) {
            return this.title
        }
        "${this.title}\n${body}"
    }

    public func toJson(): JsonObject {
        let root = JsonObject()
        let header = JsonObject()
        let titleObj = JsonObject()
        titleObj.put("tag", JsonString("plain_text"))
        titleObj.put("content", JsonString(this.title))
        header.put("title", titleObj)
        root.put("header", header)
        let elements = JsonArray([])
        let textNode = JsonObject()
        textNode.put("tag", JsonString("div"))
        let textObj = JsonObject()
        textObj.put("tag", JsonString("lark_md"))
        textObj.put("content", JsonString(this.text))
        textNode.put("text", textObj)
        elements.add(textNode)
        if (!this.toolUseText.isEmpty()) {
            let toolNode = JsonObject()
            toolNode.put("tag", JsonString("div"))
            let toolText = JsonObject()
            toolText.put("tag", JsonString("lark_md"))
            toolText.put("content", JsonString(this.toolUseText))
            toolNode.put("text", toolText)
            elements.add(toolNode)
        }
        if (!this.footerText.isEmpty()) {
            let footerNode = JsonObject()
            footerNode.put("tag", JsonString("div"))
            let footer = JsonObject()
            footer.put("tag", JsonString("lark_md"))
            footer.put("content", JsonString(this.footerText))
            footerNode.put("text", footer)
            elements.add(footerNode)
        }
        if (!this.actionId.isEmpty()) {
            let actionNode = JsonObject()
            actionNode.put("tag", JsonString("action"))
            let actions = JsonArray([])
            let button = JsonObject()
            button.put("tag", JsonString("button"))
            let buttonText = JsonObject()
            buttonText.put("tag", JsonString("plain_text"))
            buttonText.put("content", JsonString("Open"))
            button.put("text", buttonText)
            let value = JsonObject()
            value.put("action", JsonString(this.actionId))
            button.put("value", value)
            actions.add(button)
            actionNode.put("actions", actions)
            elements.add(actionNode)
        }
        root.put("elements", elements)
        root
    }
}

public class FeishuCardFallbackDecision {
    public let shouldFallback: Bool
    public let category: String
    public let status: String
    public let detail: String

    public init(shouldFallback!: Bool = false, category!: String = "unrecoverable", status!: String = "", detail!: String = "") {
        this.shouldFallback = shouldFallback
        this.category = if (category.trimAscii().isEmpty()) { "unrecoverable" } else { category.trimAscii() }
        this.status = status.trimAscii()
        this.detail = feishuCardRedactSensitiveText(detail)
    }
}

public func classifyFeishuCardFallback(status: String, error!: String = ""): FeishuCardFallbackDecision {
    let normalizedStatus = status.trimAscii().toAsciiLower()
    let detail = error.trimAscii()
    let probe = "${normalizedStatus} ${detail.toAsciiLower()}"
    if (normalizedStatus.isEmpty() && detail.isEmpty()) {
        return FeishuCardFallbackDecision(category: "unrecoverable")
    }
    if (normalizedStatus == "not_configured") {
        return FeishuCardFallbackDecision(category: "not_configured", status: normalizedStatus, detail: detail)
    }
    if (probe.contains("rate_limited") ||
        probe.contains("too_many_requests") ||
        probe.contains("rate limit") ||
        probe.contains("429")) {
        return FeishuCardFallbackDecision(shouldFallback: true, category: "rate_limit", status: normalizedStatus, detail: detail)
    }
    if (probe.contains("table_size_limit") ||
        probe.contains("table_limit") ||
        probe.contains("table limit") ||
        probe.contains("content_too_large") ||
        probe.contains("message_too_large") ||
        probe.contains("card too large") ||
        probe.contains("too many elements")) {
        return FeishuCardFallbackDecision(shouldFallback: true, category: "table_limit", status: normalizedStatus, detail: detail)
    }
    if (probe.contains("message_unavailable") ||
        probe.contains("not_found") ||
        probe.contains("not found") ||
        probe.contains("deleted") ||
        probe.contains("recalled") ||
        probe.contains("withdrawn")) {
        return FeishuCardFallbackDecision(shouldFallback: true, category: "message_unavailable", status: normalizedStatus, detail: detail)
    }
    FeishuCardFallbackDecision(category: "unrecoverable", status: normalizedStatus, detail: detail)
}

public class FeishuCardLiveSmokeChecklist {
    public static func optInEnvName(): String {
        "METIS_FEISHU_LIVE_CARD_SMOKE"
    }

    public static func isOptInValueEnabled(value: String): Bool {
        let normalized = value.trimAscii().toAsciiLower()
        normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
    }

    public static func toJson(): JsonObject {
        let root = JsonObject()
        root.put("optInRequired", JsonBool(true))
        root.put("optInEnv", JsonString(FeishuCardLiveSmokeChecklist.optInEnvName()))
        root.put("defaultNetwork", JsonString("disabled"))
        root.put("redaction", JsonString("capture fixtures only after removing tokens, authorization headers, user content, and tenant secrets"))
        root.put("phases", JsonArray([
            JsonString("create"),
            JsonString("stream_patch"),
            JsonString("final_update"),
            JsonString("abort"),
            JsonString("message_unavailable"),
            JsonString("image_resolver"),
            JsonString("fallback")
        ]))
        root
    }

    public static func skippedExternalResourceReport(): JsonObject {
        let root = FeishuCardLiveSmokeChecklist.toJson()
        root.put("status", JsonString("skipped"))
        root.put("reason", JsonString("external-resource-required"))
        root.put("networkAttempted", JsonBool(false))
        root.put("redacted", JsonBool(true))
        root.put("requestPlan", FeishuCardKitStreamingPlan.build(
            accountId: "test-account",
            receiveId: "test-chat-id",
            receiveIdType: "chat_id",
            card: FeishuInteractiveCard(title: "Metis", text: "live smoke create placeholder"),
            cardId: "card_id_from_live_create",
            messageId: "message_id_from_live_send",
            elementId: "metis_stream_body",
            patchContent: "live smoke stream patch placeholder",
            finalCard: FeishuInteractiveCard(title: "Metis", text: "live smoke final update placeholder"),
            abortReason: "live smoke abort placeholder"
        ).toJson())
        root.put("requiredExternalResources", JsonArray([
            JsonString("test_feishu_group"),
            JsonString("card_create_patch_finalize_abort"),
            JsonString("cardkit_permissions"),
            JsonString("test_thread"),
            JsonString("image_key_or_upload_fixture")
        ]))
        root
    }
}

public class FeishuCardKitRequestPlan {
    private let stage: String
    private let api: String
    private let method: String
    private let path: String
    private let tokenMode: String
    private let sequence: Int64
    private let params: JsonObject
    private let body: JsonObject
    private let requiredScopes: Array<String>
    private let networkAttempted: Bool

    public init(
        stage: String,
        api: String,
        method: String,
        path: String,
        tokenMode!: String = "sdk_default",
        sequence!: Int64 = 0,
        params!: JsonObject = JsonObject(),
        body!: JsonObject = JsonObject(),
        requiredScopes!: Array<String> = [],
        networkAttempted!: Bool = false
    ) {
        this.stage = stage.trimAscii()
        this.api = api.trimAscii()
        this.method = method.trimAscii().toAsciiUpper()
        this.path = path.trimAscii()
        this.tokenMode = tokenMode.trimAscii()
        this.sequence = sequence
        this.params = params
        this.body = body
        this.requiredScopes = requiredScopes
        this.networkAttempted = networkAttempted
    }

    public func toJson(): JsonObject {
        let out = JsonObject()
        out.put("stage", JsonString(this.stage))
        out.put("api", JsonString(this.api))
        out.put("method", JsonString(this.method))
        out.put("path", JsonString(this.path))
        out.put("tokenMode", JsonString(this.tokenMode))
        out.put("sequence", JsonInt(this.sequence))
        out.put("params", this.params)
        out.put("body", this.body)
        out.put("requiredScopes", feishuCardJsonStringArray(this.requiredScopes))
        out.put("networkAttempted", JsonBool(this.networkAttempted))
        out.put("redacted", JsonBool(true))
        out
    }
}

public class FeishuCardKitStreamingPlan {
    private let accountId: String
    private let receiveId: String
    private let receiveIdType: String
    private let cardId: String
    private let messageId: String
    private let elementId: String
    private let requests: Array<FeishuCardKitRequestPlan>

    public init(
        accountId: String,
        receiveId: String,
        receiveIdType: String,
        cardId: String,
        messageId: String,
        elementId: String,
        requests: Array<FeishuCardKitRequestPlan>
    ) {
        this.accountId = if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() }
        this.receiveId = receiveId.trimAscii()
        this.receiveIdType = receiveIdType.trimAscii()
        this.cardId = cardId.trimAscii()
        this.messageId = messageId.trimAscii()
        this.elementId = elementId.trimAscii()
        this.requests = requests
    }

    public static func build(
        accountId!: String,
        receiveId!: String,
        receiveIdType!: String,
        card!: FeishuInteractiveCard,
        cardId!: String,
        messageId!: String,
        elementId!: String,
        patchContent!: String,
        finalCard!: FeishuInteractiveCard,
        abortReason!: String
    ): FeishuCardKitStreamingPlan {
        let requests = ArrayList<FeishuCardKitRequestPlan>()
        let cleanCardId = cardId.trimAscii()
        let cleanMessageId = messageId.trimAscii()
        let cleanElementId = if (elementId.trimAscii().isEmpty()) { "metis_stream_body" } else { elementId.trimAscii() }

        let createBody = JsonObject()
        createBody.put("type", JsonString("card_json"))
        createBody.put("data", JsonString(feishuCardJsonString(card.toJson())))
        requests.add(FeishuCardKitRequestPlan(
            "create_entity",
            "cardkit.v1.card.create",
            "POST",
            "sdk://cardkit.v1.card.create",
            body: createBody,
            requiredScopes: ["cardkit:card:create"]
        ))

        let sendParams = JsonObject()
        sendParams.put("receive_id_type", JsonString(receiveIdType.trimAscii()))
        let sendBody = JsonObject()
        sendBody.put("receive_id", JsonString(receiveId.trimAscii()))
        sendBody.put("msg_type", JsonString("interactive"))
        let content = JsonObject()
        content.put("type", JsonString("card"))
        let data = JsonObject()
        data.put("card_id", JsonString(cleanCardId))
        content.put("data", data)
        sendBody.put("content", JsonString(feishuCardJsonString(content)))
        requests.add(FeishuCardKitRequestPlan(
            "send_card_message",
            "im.message.create(interactive.cardkit)",
            "POST",
            "/open-apis/im/v1/messages",
            params: sendParams,
            body: sendBody,
            requiredScopes: ["im:message:send_as_bot"]
        ))

        let patchBody = JsonObject()
        patchBody.put("content", JsonString(patchContent.trimAscii()))
        patchBody.put("sequence", JsonInt(2))
        requests.add(FeishuCardKitRequestPlan(
            "stream_patch",
            "cardkit.v1.cardElement.content",
            "PATCH",
            "sdk://cardkit.v1.cardElement.content/${cleanCardId}/${cleanElementId}",
            sequence: 2,
            body: patchBody,
            requiredScopes: ["cardkit:card:update"]
        ))

        let settings = JsonObject()
        settings.put("streaming_mode", JsonBool(false))
        let settingsBody = JsonObject()
        settingsBody.put("settings", JsonString(feishuCardJsonString(settings)))
        settingsBody.put("sequence", JsonInt(3))
        requests.add(FeishuCardKitRequestPlan(
            "settings_close",
            "cardkit.v1.card.settings",
            "PATCH",
            "sdk://cardkit.v1.card.settings/${cleanCardId}",
            sequence: 3,
            body: settingsBody,
            requiredScopes: ["cardkit:card:update"]
        ))

        let finalBody = JsonObject()
        finalBody.put("card", feishuCardKitCardJsonEnvelope(finalCard))
        finalBody.put("sequence", JsonInt(4))
        requests.add(FeishuCardKitRequestPlan(
            "final_update",
            "cardkit.v1.card.update",
            "PATCH",
            "sdk://cardkit.v1.card.update/${cleanCardId}",
            sequence: 4,
            body: finalBody,
            requiredScopes: ["cardkit:card:update"]
        ))

        let abortBody = JsonObject()
        abortBody.put("card", feishuCardKitCardJsonEnvelope(FeishuInteractiveCard(
            title: "Metis",
            text: "Aborted: ${if (abortReason.trimAscii().isEmpty()) { "aborted" } else { abortReason.trimAscii() }}"
        )))
        abortBody.put("sequence", JsonInt(4))
        requests.add(FeishuCardKitRequestPlan(
            "abort_update",
            "cardkit.v1.card.update",
            "PATCH",
            "sdk://cardkit.v1.card.update/${cleanCardId}",
            sequence: 4,
            body: abortBody,
            requiredScopes: ["cardkit:card:update"]
        ))

        let fallbackBody = JsonObject()
        fallbackBody.put("message_id", JsonString(cleanMessageId))
        fallbackBody.put("fallback_text", JsonString(finalCard.fallbackText()))
        fallbackBody.put("reason", JsonString("cardkit_unavailable_or_live_gate_missing"))
        requests.add(FeishuCardKitRequestPlan(
            "fallback_text",
            "im.message.create(text.fallback)",
            "POST",
            "/open-apis/im/v1/messages",
            body: fallbackBody,
            requiredScopes: ["im:message:send_as_bot"]
        ))

        FeishuCardKitStreamingPlan(
            accountId,
            receiveId.trimAscii(),
            receiveIdType.trimAscii(),
            cleanCardId,
            cleanMessageId,
            cleanElementId,
            requests.toArray()
        )
    }

    public func toJson(): JsonObject {
        let root = JsonObject()
        root.put("status", JsonString("planned"))
        root.put("networkAttempted", JsonBool(false))
        root.put("defaultNetwork", JsonString("disabled"))
        root.put("accountId", JsonString(this.accountId))
        root.put("receiveId", JsonString(this.receiveId))
        root.put("receiveIdType", JsonString(this.receiveIdType))
        root.put("cardId", JsonString(this.cardId))
        root.put("messageId", JsonString(this.messageId))
        root.put("elementId", JsonString(this.elementId))
        root.put("transport", JsonString("metis-native-cardkit-request-plan"))
        root.put("redacted", JsonBool(true))
        let rows = JsonArray([])
        for (request in this.requests) {
            rows.add(request.toJson())
        }
        root.put("requests", rows)
        root.put("liveGate", JsonString("external-resource-required"))
        root.put("requiredExternalResources", JsonArray([
            JsonString("test_feishu_group"),
            JsonString("cardkit_permissions"),
            JsonString("live_card_id"),
            JsonString("live_message_id"),
            JsonString("redacted_cardkit_response_fixture")
        ]))
        root
    }
}

public class FeishuReplyFooterMetrics {
    public let status: String
    public let elapsedMs: Int64
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheRead: Int64
    public let cacheWrite: Int64
    public let contextTokens: Int64
    public let model: String

    public init(
        status!: String = "",
        elapsedMs!: Int64 = 0,
        inputTokens!: Int64 = 0,
        outputTokens!: Int64 = 0,
        cacheRead!: Int64 = 0,
        cacheWrite!: Int64 = 0,
        contextTokens!: Int64 = 0,
        model!: String = ""
    ) {
        this.status = status.trimAscii()
        this.elapsedMs = elapsedMs
        this.inputTokens = inputTokens
        this.outputTokens = outputTokens
        this.cacheRead = cacheRead
        this.cacheWrite = cacheWrite
        this.contextTokens = contextTokens
        this.model = model.trimAscii()
    }

    public func toFooterText(config!: FeishuReplyFooterConfig = FeishuReplyFooterConfig()): String {
        let parts = ArrayList<String>()
        if (config.status && !this.status.isEmpty()) {
            parts.add("Status: ${this.status}")
        }
        if (config.elapsed && this.elapsedMs > 0) {
            parts.add("Elapsed: ${this.formatElapsed(this.elapsedMs)}")
        }
        if (config.tokens && this.inputTokens > 0) {
            parts.add("Tokens in: ${this.inputTokens}")
        }
        if (config.tokens && this.outputTokens > 0) {
            parts.add("Tokens out: ${this.outputTokens}")
        }
        if (config.cache && this.cacheRead > 0) {
            parts.add("Cache read: ${this.cacheRead}")
        }
        if (config.cache && this.cacheWrite > 0) {
            parts.add("Cache write: ${this.cacheWrite}")
        }
        if (config.context && this.contextTokens > 0) {
            parts.add("Context: ${this.contextTokens}")
        }
        if (config.model && !this.model.isEmpty()) {
            parts.add("Model: ${this.model}")
        }
        if (parts.isEmpty()) {
            return ""
        }
        "Metrics\n${String.join(parts.toArray(), delimiter: " | ")}"
    }

    public func toJson(): JsonObject {
        let root = JsonObject()
        root.put("status", JsonString(this.status))
        root.put("elapsedMs", JsonInt(this.elapsedMs))
        root.put("inputTokens", JsonInt(this.inputTokens))
        root.put("outputTokens", JsonInt(this.outputTokens))
        root.put("cacheRead", JsonInt(this.cacheRead))
        root.put("cacheWrite", JsonInt(this.cacheWrite))
        root.put("contextTokens", JsonInt(this.contextTokens))
        root.put("model", JsonString(this.model))
        root
    }

    private func formatElapsed(ms: Int64): String {
        let tenths = ms / 100
        let seconds = tenths / 10
        let frac = tenths % 10
        "${seconds}.${frac}s"
    }
}

public class FeishuReplyFooterConfig {
    public let status: Bool
    public let elapsed: Bool
    public let tokens: Bool
    public let cache: Bool
    public let context: Bool
    public let model: Bool

    public init(
        status!: Bool = true,
        elapsed!: Bool = true,
        tokens!: Bool = true,
        cache!: Bool = true,
        context!: Bool = true,
        model!: Bool = true
    ) {
        this.status = status
        this.elapsed = elapsed
        this.tokens = tokens
        this.cache = cache
        this.context = context
        this.model = model
    }
}

public class FeishuReplyCardDraft {
    private let title: String
    private let showToolUse: Bool
    private let textParts = ArrayList<String>()
    private let toolUseParts = ArrayList<String>()

    public init(title!: String = "Metis", showToolUse!: Bool = false) {
        this.title = title.trimAscii()
        this.showToolUse = showToolUse
    }

    public func appendText(text: String): Unit {
        let normalized = text.trimAscii()
        if (!normalized.isEmpty()) {
            this.textParts.add(normalized)
        }
    }

    public func appendToolUse(name: String, payload: String): Unit {
        if (!this.showToolUse) {
            return
        }
        let toolName = name.trimAscii()
        if (toolName.isEmpty()) {
            return
        }
        let preview = payload.trimAscii()
        if (preview.isEmpty()) {
            this.toolUseParts.add("- ${toolName}")
        } else {
            this.toolUseParts.add("- ${toolName}: ${preview}")
        }
    }

    public func toCard(): FeishuInteractiveCard {
        let text = String.join(this.textParts.toArray(), delimiter: "\n")
        let toolText = if (this.toolUseParts.isEmpty()) {
            ""
        } else {
            "Tool use\n${String.join(this.toolUseParts.toArray(), delimiter: "\n")}"
        }
        FeishuInteractiveCard(title: this.title, text: text, toolUseText: toolText)
    }
}

public class FeishuCardImageResolver {
    private let resolved = HashMap<String, String>()
    private let pending = HashMap<String, Bool>()
    private let skipped = HashMap<String, Bool>()
    private var lastStatusValue: String = "idle"

    public init() {}

    public func registerResolved(url: String, imageKey: String): Unit {
        let normalizedUrl = url.trimAscii()
        let normalizedKey = imageKey.trimAscii()
        if (normalizedUrl.isEmpty() || !normalizedKey.startsWith("img_")) {
            return
        }
        this.resolved[normalizedUrl] = normalizedKey
        this.pending.remove(normalizedUrl)
        this.lastStatusValue = "resolved"
    }

    public func markFailed(url: String): Unit {
        let normalizedUrl = url.trimAscii()
        if (normalizedUrl.isEmpty()) {
            return
        }
        this.pending.remove(normalizedUrl)
        this.skipped[normalizedUrl] = true
        this.lastStatusValue = "failed"
    }

    public func resolveImages(text: String): String {
        if (!text.contains("![")) {
            return text
        }
        let out = StringBuilder()
        var cursor: Int64 = 0
        while (cursor < text.size) {
            let start = this.findImageStart(text, cursor)
            if (start < 0) {
                out.append(text[cursor..])
                break
            }
            out.append(text[cursor..start])
            let altEnd = this.findByte(text, UInt8(93), start + 2)
            if (altEnd < 0 || altEnd + 1 >= text.size || text[altEnd + 1] != UInt8(40)) {
                out.append(text[start..start + 2])
                cursor = start + 2
                continue
            }
            let valueStart = altEnd + 2
            let valueEnd = this.findByte(text, UInt8(41), valueStart)
            if (valueEnd < 0) {
                out.append(text[start..])
                break
            }
            let alt = text[start + 2..altEnd]
            let value = text[valueStart..valueEnd].trimAscii()
            let replacement = this.resolveImageReference(alt, value)
            if (!replacement.isEmpty()) {
                out.append(replacement)
            }
            cursor = valueEnd + 1
        }
        out.toString()
    }

    public func toJson(): JsonObject {
        let root = JsonObject()
        root.put("networkEnabled", JsonBool(false))
        root.put("resolvedCount", JsonInt(this.resolved.size))
        root.put("pendingCount", JsonInt(this.pending.size))
        root.put("skippedCount", JsonInt(this.skipped.size))
        root.put("lastStatus", JsonString(this.lastStatusValue))
        root
    }

    private func resolveImageReference(alt: String, value: String): String {
        if (value.startsWith("img_")) {
            return "![${alt}](${value})"
        }
        if (!(value.startsWith("http://") || value.startsWith("https://"))) {
            if (!value.isEmpty()) {
                this.skipped[value] = true
                this.lastStatusValue = "skipped"
            }
            return ""
        }
        match (this.resolved.get(value)) {
            case Some(imageKey) =>
                this.lastStatusValue = "resolved"
                return "![${alt}](${imageKey})"
            case None => ()
        }
        if (!(this.skipped.get(value) ?? false)) {
            this.pending[value] = true
            this.lastStatusValue = "pending"
        }
        ""
    }

    private func findImageStart(text: String, from: Int64): Int64 {
        var i = from
        while (i + 1 < text.size) {
            if (text[i] == UInt8(33) && text[i + 1] == UInt8(91)) {
                return i
            }
            i += 1
        }
        -1
    }

    private func findByte(text: String, byte: UInt8, from: Int64): Int64 {
        var i = from
        while (i < text.size) {
            if (text[i] == byte) {
                return i
            }
            i += 1
        }
        -1
    }
}

public class FeishuStreamingCardController {
    private let client: FeishuApiClient
    private let accountId: String
    private let rawPeerId: String
    private let receiveId: String
    private let receiveIdType: String
    private let replyToMessageId: Option<String>
    private let replyInThread: Bool
    private let showToolUse: Bool
    private var cardMessageId: String = ""
    private var currentText: String = ""
    private var toolUseText: String = ""
    private var aborted: Bool = false
    private var phase: String = "idle"
    private var lastFallbackCategoryValue: String = ""
    private var lastFallbackStatusValue: String = ""
    private var lastFallbackDetailValue: String = ""
    private var pendingFlush: Bool = false
    private var pendingFlushText: String = ""
    private var lastFlushAtMs: Int64 = 0
    private var lastThrottleMs: Int64 = 0
    private var cardKitSequence: Int64 = 0
    private var lastFlushedText: String = ""
    private var unavailableTerminated: Bool = false
    private var unavailableSource: String = ""
    private var unavailableStatus: String = ""
    private var unavailableDetail: String = ""
    private var lastFooterMetrics: Option<FeishuReplyFooterMetrics> = None<FeishuReplyFooterMetrics>
    private let imageResolver = FeishuCardImageResolver()

    public init(
        client: FeishuApiClient,
        accountId!: String,
        rawPeerId!: String,
        receiveId!: String,
        receiveIdType!: String,
        replyToMessageId!: Option<String> = None<String>,
        replyInThread!: Bool = false,
        showToolUse!: Bool = false
    ) {
        this.client = client
        this.accountId = accountId.trimAscii()
        this.rawPeerId = rawPeerId.trimAscii()
        this.receiveId = receiveId.trimAscii()
        this.receiveIdType = receiveIdType.trimAscii()
        this.replyToMessageId = replyToMessageId
        this.replyInThread = replyInThread
        this.showToolUse = showToolUse
    }

    public func create(text: String): String {
        if (this.aborted) {
            return ""
        }
        this.phase = "creating"
        this.currentText = text.trimAscii()
        let result = this.client.sendInteractiveCard(
            this.accountId,
            this.rawPeerId,
            this.receiveId,
            this.receiveIdType,
            this.buildCard(None<FeishuReplyFooterMetrics>),
            this.replyToMessageId,
            this.replyInThread
        )
        if (result.ok && !result.messageId.isEmpty()) {
            this.cardMessageId = result.messageId
            this.phase = "streaming"
            this.cardKitSequence = 1
            this.lastFlushedText = this.currentText
            this.clearFallbackDecision()
            return result.messageId
        }
        this.recordFallbackDecision(classifyFeishuCardFallback(result.status, error: result.error))
        let fallback = this.client.sendTextMessage(
            this.accountId,
            this.rawPeerId,
            this.receiveId,
            this.receiveIdType,
            this.buildCard(None<FeishuReplyFooterMetrics>).fallbackText(),
            this.replyToMessageId,
            this.replyInThread
        )
        if (fallback.ok) {
            this.phase = "terminated"
            return fallback.messageId
        }
        this.phase = "terminated"
        ""
    }

    public func patchChunk(text: String): Bool {
        if (this.aborted || this.cardMessageId.isEmpty() || this.isTerminalPhase()) {
            return false
        }
        let normalized = text.trimAscii()
        if (normalized == this.currentText) {
            return true
        }
        this.currentText = normalized
        this.patchCurrent(None<FeishuReplyFooterMetrics>, source: "patch")
    }

    public func recoverCardMessageId(messageId: String): Bool {
        let normalized = messageId.trimAscii()
        if (normalized.isEmpty() || this.isTerminalPhase()) {
            return false
        }
        this.cardMessageId = normalized
        this.aborted = false
        if (this.phase == "idle" || this.phase == "creating") {
            this.phase = "streaming"
        }
        true
    }

    public func patchChunkThrottled(text: String, nowMs!: Int64, throttleMs!: Int64): Bool {
        if (this.aborted || this.cardMessageId.isEmpty() || this.isTerminalPhase()) {
            return false
        }
        let normalized = text.trimAscii()
        if (normalized == this.currentText && !this.pendingFlush) {
            return true
        }
        let effectiveThrottleMs = if (throttleMs < 0) { 0 } else { throttleMs }
        if (this.lastFlushAtMs <= 0 || nowMs - this.lastFlushAtMs >= effectiveThrottleMs) {
            this.currentText = normalized
            this.pendingFlush = false
            this.pendingFlushText = ""
            this.lastThrottleMs = effectiveThrottleMs
            let ok = this.patchCurrent(None<FeishuReplyFooterMetrics>, source: "patch")
            if (ok) {
                this.lastFlushAtMs = nowMs
            }
            return ok
        }
        this.currentText = normalized
        this.pendingFlush = true
        this.pendingFlushText = normalized
        this.lastThrottleMs = effectiveThrottleMs
        true
    }

    public func flushPending(nowMs!: Int64): Bool {
        if (!this.pendingFlush) {
            return true
        }
        if (this.aborted || this.cardMessageId.isEmpty() || this.isTerminalPhase()) {
            return false
        }
        this.currentText = this.pendingFlushText
        this.pendingFlush = false
        this.pendingFlushText = ""
        let ok = this.patchCurrent(None<FeishuReplyFooterMetrics>, source: "flush")
        if (ok) {
            this.lastFlushAtMs = nowMs
        }
        ok
    }

    public func updateToolPayload(name: String, payload: String): Bool {
        if (this.aborted || this.cardMessageId.isEmpty() || this.isTerminalPhase() || !this.showToolUse) {
            return false
        }
        let toolName = name.trimAscii()
        if (toolName.isEmpty()) {
            return false
        }
        let preview = payload.trimAscii()
        this.toolUseText = if (preview.isEmpty()) {
            "Tool use\n- ${toolName}"
        } else {
            "Tool use\n- ${toolName}: ${preview}"
        }
        this.patchCurrent(None<FeishuReplyFooterMetrics>, source: "tool")
    }

    public func finalize(text: String, footerMetrics!: Option<FeishuReplyFooterMetrics> = None<FeishuReplyFooterMetrics>): Bool {
        if (this.aborted || this.cardMessageId.isEmpty() || this.isTerminalPhase()) {
            return false
        }
        this.currentText = text.trimAscii()
        let ok = this.patchCurrent(footerMetrics, source: "finalize")
        if (ok && this.phase != "terminated") {
            this.phase = "completed"
        }
        ok
    }

    public func abort(reason: String): Bool {
        if (this.cardMessageId.isEmpty()) {
            this.aborted = true
            this.phase = "aborted"
            this.pendingFlush = false
            this.pendingFlushText = ""
            return false
        }
        this.aborted = true
        let message = if (reason.trimAscii().isEmpty()) { "aborted" } else { reason.trimAscii() }
        let result = this.client.patchInteractiveCard(
            this.accountId,
            this.cardMessageId,
            FeishuInteractiveCard(title: "Metis", text: "Aborted: ${message}")
        )
        this.phase = "aborted"
        this.pendingFlush = false
        this.pendingFlushText = ""
        result.ok
    }

    public func currentPhase(): String {
        this.phase
    }

    public func lastFallbackCategory(): String {
        this.lastFallbackCategoryValue
    }

    public func lastFallbackStatus(): String {
        this.lastFallbackStatusValue
    }

    public func lastFallbackDetail(): String {
        this.lastFallbackDetailValue
    }

    public func registerResolvedImage(url: String, imageKey: String): Unit {
        this.imageResolver.registerResolved(url, imageKey)
    }

    public func observableState(): JsonObject {
        let root = JsonObject()
        root.put("phase", JsonString(this.phase))
        root.put("aborted", JsonBool(this.aborted))

        let cardKit = JsonObject()
        cardKit.put("status", JsonString(if (this.cardMessageId.isEmpty()) { "not_created" } else { "ready" }))
        cardKit.put("cardMessageId", JsonString(this.cardMessageId))
        cardKit.put("sequence", JsonInt(this.cardKitSequence))
        root.put("cardKit", cardKit)

        let text = JsonObject()
        text.put("currentText", JsonString(this.currentText))
        text.put("toolUseText", JsonString(this.toolUseText))
        text.put("lastFlushedText", JsonString(this.lastFlushedText))
        root.put("text", text)

        let flush = JsonObject()
        flush.put("pending", JsonBool(this.pendingFlush))
        flush.put("pendingText", JsonString(this.pendingFlushText))
        flush.put("lastFlushAtMs", JsonInt(this.lastFlushAtMs))
        flush.put("throttleMs", JsonInt(this.lastThrottleMs))
        root.put("flush", flush)

        let fallback = JsonObject()
        fallback.put("category", JsonString(this.lastFallbackCategoryValue))
        fallback.put("status", JsonString(this.lastFallbackStatusValue))
        fallback.put("detail", JsonString(this.lastFallbackDetailValue))
        root.put("fallback", fallback)

        let unavailable = JsonObject()
        unavailable.put("terminated", JsonBool(this.unavailableTerminated))
        unavailable.put("source", JsonString(this.unavailableSource))
        unavailable.put("status", JsonString(this.unavailableStatus))
        unavailable.put("detail", JsonString(this.unavailableDetail))
        root.put("unavailable", unavailable)

        root.put("footerMetrics", match (this.lastFooterMetrics) {
            case Some(metrics) => metrics.toJson()
            case None => JsonObject()
        })
        root.put("imageResolver", this.imageResolver.toJson())
        root
    }

    private func isTerminalPhase(): Bool {
        this.phase == "completed" || this.phase == "aborted" || this.phase == "terminated"
    }

    private func patchCurrent(footerMetrics: Option<FeishuReplyFooterMetrics>, source!: String = "patch"): Bool {
        let card = this.buildCard(footerMetrics)
        let result = this.client.patchInteractiveCard(this.accountId, this.cardMessageId, card)
        if (result.ok) {
            this.cardKitSequence += 1
            this.lastFlushedText = this.currentText
            this.lastFooterMetrics = footerMetrics
            this.clearUnavailableState()
            return true
        }
        let decision = classifyFeishuCardFallback(result.status, error: result.error)
        this.recordFallbackDecision(decision)
        if (decision.category == "message_unavailable") {
            this.recordUnavailableState(source, decision)
        }
        if (decision.shouldFallback) {
            let fallback = this.client.sendTextMessage(
                this.accountId,
                this.rawPeerId,
                this.receiveId,
                this.receiveIdType,
                card.fallbackText(),
                this.replyToMessageId,
                this.replyInThread
            )
            if (fallback.ok) {
                this.phase = "terminated"
                return true
            }
        }
        false
    }

    private func recordFallbackDecision(decision: FeishuCardFallbackDecision): Unit {
        this.lastFallbackCategoryValue = decision.category
        this.lastFallbackStatusValue = decision.status
        this.lastFallbackDetailValue = decision.detail
    }

    private func clearFallbackDecision(): Unit {
        this.lastFallbackCategoryValue = ""
        this.lastFallbackStatusValue = ""
        this.lastFallbackDetailValue = ""
    }

    private func recordUnavailableState(source: String, decision: FeishuCardFallbackDecision): Unit {
        this.unavailableTerminated = true
        this.unavailableSource = if (source.trimAscii().isEmpty()) { "patch" } else { source.trimAscii() }
        this.unavailableStatus = decision.status
        this.unavailableDetail = decision.detail
    }

    private func clearUnavailableState(): Unit {
        this.unavailableTerminated = false
        this.unavailableSource = ""
        this.unavailableStatus = ""
        this.unavailableDetail = ""
    }

    private func buildCard(footerMetrics: Option<FeishuReplyFooterMetrics>): FeishuInteractiveCard {
        let footer = match (footerMetrics) {
            case Some(metrics) => metrics.toFooterText()
            case None => ""
        }
        FeishuInteractiveCard(title: "Metis", text: this.imageResolver.resolveImages(this.currentText), toolUseText: this.toolUseText, footerText: footer)
    }
}

public class FeishuApiSendResult {
    public let ok: Bool
    public let status: String
    public let messageId: String
    public let error: String

    public init(ok!: Bool = false, status!: String = "not_configured", messageId!: String = "", error!: String = "") {
        this.ok = ok
        this.status = if (status.trimAscii().isEmpty()) { if (ok) { "ok" } else { "error" } } else { status.trimAscii() }
        this.messageId = messageId.trimAscii()
        this.error = error.trimAscii()
    }
}
