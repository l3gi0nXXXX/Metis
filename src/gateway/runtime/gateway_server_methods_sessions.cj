package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{MetisConfigManager, CliConfig, CliSettingManager, GatewayUserSettings}
import metis.core.model.ModelTokenLimits
import metis.gateway.core.{GatewaySessionCatalogRow, GatewaySessionStore, gatewayBuildChatEventMessage, gatewayFindSessionCatalogRowForUser, gatewayFindSessionConversationViewForUser, gatewayListSessionConversationViewsForUser, gatewaySessionStoreForResolvedRequest, gatewaySessionStoreForUserWithAgentId}
import metis.gateway.core.gatewayBuildSessionEventPayload
import metis.gateway.session.{GatewayIngressSource, gatewayResolveSessionContext, gatewaySessionRequestFromRpcParams}

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{File, Path, exists, copy, remove}
import std.time.DateTime

import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewaySessionsRpcStringParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewaySessionsRpcIntParam(request: GatewayRpcRequest, key: String, defaultValue: Int64): Int64 {
    match (request.params.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.toJsonString())
            } catch (_: Exception) {
                defaultValue
            }
        case None => defaultValue
    }
}

private func gatewaySessionsRpcStringArrayParam(request: GatewayRpcRequest, key: String): Array<String> {
    let out = ArrayList<String>()
    match (request.params.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (i in 0..arr.size()) {
                    try {
                        let item = arr[i].asString().getValue().trimAscii()
                        if (!item.isEmpty()) {
                            out.add(item)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    out.toArray()
}

private func gatewaySessionsPreviewRole(raw: String): String {
    let normalized = raw.trimAscii().toAsciiLower()
    if (normalized == "user" || normalized == "assistant" || normalized == "tool" || normalized == "system") {
        return normalized
    }
    if (normalized.isEmpty()) {
        return ""
    }
    "other"
}

private func gatewaySessionsPreviewText(raw: String, maxChars: Int64): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let limit = max(20, maxChars)
    if (text.size <= limit) {
        return text
    }
    if (limit <= 3) {
        return text[0..limit]
    }
    text[0..limit - 3] + "..."
}

private func gatewaySessionsNormalizeInlineText(raw: String): String {
    let out = ArrayList<String>()
    for (part in raw.replace("\n", " ").replace("\r", " ").split(" ")) {
        let normalized = part.trimAscii()
        if (!normalized.isEmpty()) {
            out.add(normalized)
        }
    }
    String.join(out.toArray(), delimiter: " ")
}

private func gatewaySessionsDeriveTitle(raw: String, displayName: String, sessionId: String): String {
    let normalizedDisplayName = displayName.trimAscii()
    if (!normalizedDisplayName.isEmpty()) {
        return normalizedDisplayName
    }
    for (obj in gatewayControlUiParseJsonObjectsFromRaw(raw)) {
        let role = gatewaySessionsPreviewRole(match (obj.get("role")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        })
        if (role != "user") {
            continue
        }
        let text = gatewaySessionsNormalizeInlineText(match (obj.get("text")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        }).trimAscii()
        if (!text.isEmpty()) {
            return gatewaySessionsPreviewText(text, 60)
        }
    }
    let normalizedSessionId = sessionId.trimAscii()
    if (normalizedSessionId.size > 8) {
        return normalizedSessionId[0..8]
    }
    normalizedSessionId
}

private func gatewaySessionsLastMessagePreview(raw: String): String {
    var preview = ""
    for (obj in gatewayControlUiParseJsonObjectsFromRaw(raw)) {
        let role = gatewaySessionsPreviewRole(match (obj.get("role")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        })
        if (role != "user" && role != "assistant") {
            continue
        }
        let text = gatewaySessionsNormalizeInlineText(match (obj.get("text")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        }).trimAscii()
        if (!text.isEmpty()) {
            preview = gatewaySessionsPreviewText(text, 160)
        }
    }
    preview
}

private func gatewaySessionsPreviewItemsFromRaw(raw: String, limit: Int64, maxChars: Int64): JsonArray {
    let allItems = ArrayList<JsonObject>()
    for (obj in gatewayControlUiParseJsonObjectsFromRaw(raw)) {
        let kind = match (obj.get("kind")) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_: Exception) { "" }
            case None => ""
        }
        if (kind == "meta" || kind == "binding") {
            continue
        }
        let role = gatewaySessionsPreviewRole(match (obj.get("role")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        })
        let text = gatewaySessionsPreviewText(match (obj.get("text")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        }, maxChars)
        if (role.isEmpty() || text.isEmpty()) {
            continue
        }
        let row = JsonObject()
        row.put("role", JsonString(role))
        row.put("text", JsonString(text))
        allItems.add(row)
    }
    let items = JsonArray([])
    let maxItems = max(1, limit)
    let start = max(0, allItems.size - maxItems)
    for (i in start..allItems.size) {
        items.add(allItems[i])
    }
    items
}

private func gatewaySessionsMessageTimestamp(obj: JsonObject): Int64 {
    match (obj.get("ts")) {
        case Some(v) =>
            try {
                Int64.parse(v.asString().getValue().trimAscii())
            } catch (_: Exception) {
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            }
        case None => 0
    }
}

private func gatewaySessionsTimestampStringMs(raw: String): Int64 {
    let normalized = raw.trimAscii()
    if (normalized.isEmpty()) {
        return 0
    }
    try {
        DateTime.parse(normalized, "yyyy-MM-dd'T'HH:mm:ss'Z'").toUnixTimeStamp().toMilliseconds()
    } catch (_: Exception) {
        try {
            DateTime.parse(normalized, "yyyy-MM-dd'T'HH:mm:ss").toUnixTimeStamp().toMilliseconds()
        } catch (_inner: Exception) {
            try {
                DateTime.parse(normalized, "yyyy-MM-dd HH:mm:ss").toUnixTimeStamp().toMilliseconds()
            } catch (_last: Exception) {
                0
            }
        }
    }
}

private func gatewaySessionsCompactionTimestamp(obj: JsonObject): Int64 {
    match (obj.get("timestamp")) {
        case Some(v) =>
            try {
                gatewaySessionsTimestampStringMs(v.asString().getValue())
            } catch (_: Exception) {
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            }
        case None => 0
    }
}

private struct GatewaySessionsTranscriptUsageSnapshot {
    let modelProvider: String
    let model: String
    let totalTokens: Int64
    let totalTokensFresh: Bool
    let estimatedCostUsd: Float64

    public init(
        modelProvider!: String = "",
        model!: String = "",
        totalTokens!: Int64 = 0,
        totalTokensFresh!: Bool = false,
        estimatedCostUsd!: Float64 = 0.0
    ) {
        this.modelProvider = modelProvider.trimAscii()
        this.model = model.trimAscii()
        this.totalTokens = totalTokens
        this.totalTokensFresh = totalTokensFresh
        this.estimatedCostUsd = estimatedCostUsd
    }
}

private func gatewaySessionsUsageInt(raw: Option<JsonValue>, key: String): Int64 {
    match (raw) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                match (obj.get(key)) {
                    case Some(inner) =>
                        try {
                            Int64.parse(inner.toJsonString())
                        } catch (_: Exception) {
                            0
                        }
                    case None => 0
                }
            } catch (_: Exception) {
                0
            }
        case None => 0
    }
}

private func gatewaySessionsUsageCost(raw: Option<JsonValue>): Float64 {
    match (raw) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                match (obj.get("cost")) {
                    case Some(costRaw) =>
                        try {
                            let costObj = costRaw.asObject()
                            match (costObj.get("total")) {
                                case Some(totalRaw) =>
                                    try {
                                        Float64.parse(totalRaw.toJsonString())
                                    } catch (_: Exception) {
                                        0.0
                                    }
                                case None => 0.0
                            }
                        } catch (_: Exception) {
                            0.0
                        }
                    case None => 0.0
                }
            } catch (_: Exception) {
                0.0
            }
        case None => 0.0
    }
}

private func gatewaySessionsTranscriptString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asString().getValue().trimAscii()
            } catch (_: Exception) {
                ""
            }
        case None => ""
    }
}

private func gatewaySessionsSpawnMetadataField(raw: String, field: String): String {
    let marker = "sessions_spawn metadata:"
    let markerIdx = raw.indexOf(marker)
    if (markerIdx.isNone()) {
        return ""
    }
    let segment = raw[markerIdx.getOrThrow() + marker.size..]
    let needle = "${field}="
    let fieldIdx = segment.indexOf(needle)
    if (fieldIdx.isNone()) {
        return ""
    }
    let rest = segment[fieldIdx.getOrThrow() + needle.size..]
    var end = rest.size
    match (rest.indexOf(",")) {
        case Some(v) => end = min(end, v)
        case None => ()
    }
    match (rest.indexOf("\"")) {
        case Some(v) => end = min(end, v)
        case None => ()
    }
    match (rest.indexOf("\n")) {
        case Some(v) => end = min(end, v)
        case None => ()
    }
    rest[0..end].trimAscii()
}

private func gatewaySessionsApplySpawnMetadataFallback(row: JsonObject, transcriptRaw: String): Unit {
    let streamTo = gatewaySessionsSpawnMetadataField(transcriptRaw, "streamTo")
    let thread = gatewaySessionsSpawnMetadataField(transcriptRaw, "thread").toAsciiLower()
    if (!streamTo.isEmpty() && row.get("streamTo").isNone()) {
        row.put("streamTo", JsonString(streamTo))
    }
    if (!thread.isEmpty() && row.get("thread").isNone()) {
        row.put("thread", (thread == "true").toJsonValue())
    }
    if (!streamTo.startsWith("telegram:")) {
        return
    }
    let target = streamTo["telegram:".size..].trimAscii()
    if (target.isEmpty()) {
        return
    }
    let delivery = match (row.get("deliveryContext")) {
        case Some(v) =>
            try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    if (delivery.get("channel").isNone()) {
        delivery.put("channel", JsonString("telegram"))
    }
    if (delivery.get("to").isNone()) {
        delivery.put("to", JsonString(target))
    }
    let topicMarker = ":topic:"
    if (let Some(idx) <- target.indexOf(topicMarker)) {
        let threadId = target[idx + topicMarker.size..].trimAscii()
        if (!threadId.isEmpty() && delivery.get("threadId").isNone()) {
            delivery.put("threadId", JsonString(threadId))
        }
        if (row.get("lastThreadId").isNone()) {
            row.put("lastThreadId", JsonString(threadId))
        }
    }
    if (delivery.size() > 0 && row.get("deliveryContext").isNone()) {
        row.put("deliveryContext", delivery)
    }
    if (row.get("lastChannel").isNone()) {
        row.put("lastChannel", JsonString("telegram"))
    }
    if (row.get("lastTo").isNone()) {
        row.put("lastTo", JsonString(target))
    }
    if (row.get("kind").isNone()) {
        row.put("kind", JsonString(if (target.startsWith("group:")) { "group" } else { "direct" }))
    }
}

private func gatewaySessionsTranscriptUsageSnapshot(raw: String): Option<GatewaySessionsTranscriptUsageSnapshot> {
    if (raw.trimAscii().isEmpty()) {
        return None
    }
    var sawSnapshot = false
    var modelProvider = ""
    var model = ""
    var totalTokens = 0
    var totalTokensFresh = false
    var estimatedCostUsd = 0.0
    for (line in raw.split("\n")) {
        let text = line.trimAscii()
        if (text.isEmpty()) {
            continue
        }
        try {
            let parsed = JsonValue.fromStr(text).asObject()
            let message = match (parsed.get("message")) {
                case Some(v) =>
                    try { v.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
            let role = if (!gatewaySessionsTranscriptString(message, "role").isEmpty()) {
                gatewaySessionsTranscriptString(message, "role")
            } else {
                gatewaySessionsTranscriptString(parsed, "role")
            }
            if (!role.isEmpty() && role != "assistant") {
                continue
            }
            let usageRaw = if (message.get("usage").isSome()) { message.get("usage") } else { parsed.get("usage") }
            let nextProvider = if (!gatewaySessionsTranscriptString(message, "provider").isEmpty()) {
                gatewaySessionsTranscriptString(message, "provider")
            } else {
                gatewaySessionsTranscriptString(parsed, "provider")
            }
            let nextModel = if (!gatewaySessionsTranscriptString(message, "model").isEmpty()) {
                gatewaySessionsTranscriptString(message, "model")
            } else {
                gatewaySessionsTranscriptString(parsed, "model")
            }
            let inputTokens = gatewaySessionsUsageInt(usageRaw, "input")
            let outputTokens = gatewaySessionsUsageInt(usageRaw, "output")
            let cacheRead = gatewaySessionsUsageInt(usageRaw, "cacheRead")
            let cacheWrite = gatewaySessionsUsageInt(usageRaw, "cacheWrite")
            let nextTotalTokens = inputTokens + outputTokens + cacheRead + cacheWrite
            let nextCostUsd = gatewaySessionsUsageCost(usageRaw)
            let isDeliveryMirror = nextProvider == "metis" && nextModel == "delivery-mirror"
            let hasMeaningfulUsage = nextTotalTokens > 0 || nextCostUsd > 0.0
            let hasModelIdentity = !nextProvider.isEmpty() || !nextModel.isEmpty()
            if (!hasMeaningfulUsage && !hasModelIdentity) {
                continue
            }
            if (isDeliveryMirror && !hasMeaningfulUsage) {
                continue
            }
            sawSnapshot = true
            if (!isDeliveryMirror) {
                if (!nextProvider.isEmpty()) {
                    modelProvider = nextProvider
                }
                if (!nextModel.isEmpty()) {
                    model = nextModel
                }
            }
            if (nextTotalTokens > 0) {
                totalTokens = nextTotalTokens
                totalTokensFresh = true
            }
            if (nextCostUsd >= 0.0) {
                estimatedCostUsd += nextCostUsd
            }
        } catch (_: Exception) {
            ()
        }
    }
    if (!sawSnapshot) {
        return None
    }
    Some(
        GatewaySessionsTranscriptUsageSnapshot(
            modelProvider: modelProvider,
            model: model,
            totalTokens: totalTokens,
            totalTokensFresh: totalTokensFresh,
            estimatedCostUsd: estimatedCostUsd
        )
    )
}

private func gatewaySessionsApplyTranscriptFallback(row: JsonObject, transcriptRaw: String): Unit {
    gatewaySessionsApplySpawnMetadataFallback(row, transcriptRaw)
    match (gatewaySessionsTranscriptUsageSnapshot(transcriptRaw)) {
        case Some(snapshot) =>
            let currentProvider = gatewaySessionsTranscriptString(row, "modelProvider")
            let currentModel = gatewaySessionsTranscriptString(row, "model")
            if (currentProvider.isEmpty() && !snapshot.modelProvider.isEmpty()) {
                row.put("modelProvider", JsonString(snapshot.modelProvider))
            }
            if (currentModel.isEmpty() && !snapshot.model.isEmpty()) {
                row.put("model", JsonString(snapshot.model))
            }
            let currentTotalTokens = match (row.get("totalTokens")) {
                case Some(v) =>
                    try { Int64.parse(v.toJsonString()) } catch (_: Exception) { 0 }
                case None => 0
            }
            let currentTotalTokensFresh = match (row.get("totalTokensFresh")) {
                case Some(v) =>
                    try { v.asBool().getValue() } catch (_: Exception) { false }
                case None => false
            }
            if (snapshot.totalTokens > 0 && (currentTotalTokens <= 0 || !currentTotalTokensFresh)) {
                row.put("totalTokens", snapshot.totalTokens.toJsonValue())
                row.put("totalTokensFresh", snapshot.totalTokensFresh.toJsonValue())
            }
            let currentCostUsd = match (row.get("estimatedCostUsd")) {
                case Some(v) =>
                    try { Float64.parse(v.toJsonString()) } catch (_: Exception) { 0.0 }
                case None => 0.0
            }
            if (snapshot.estimatedCostUsd >= 0.0 && currentCostUsd <= 0.0) {
                row.put("estimatedCostUsd", snapshot.estimatedCostUsd.toJsonValue())
            }
            let currentContextTokens = match (row.get("contextTokens")) {
                case Some(v) =>
                    try { Int64.parse(v.toJsonString()) } catch (_: Exception) { 0 }
                case None => 0
            }
            let resolvedProvider = if (currentProvider.isEmpty()) { snapshot.modelProvider } else { currentProvider }
            let resolvedModel = if (currentModel.isEmpty()) { snapshot.model } else { currentModel }
            if (currentContextTokens <= 0 && !resolvedProvider.isEmpty() && !resolvedModel.isEmpty()) {
                let modelRef = MetisConfigManager.canonicalModelRef("${resolvedProvider}:${resolvedModel}").trimAscii()
                if (!modelRef.isEmpty()) {
                    row.put("contextTokens", ModelTokenLimits.getInputLimit(modelRef).toJsonValue())
                }
            }
        case None => ()
    }
}

private func gatewaySessionsDefaultModelSummary(): JsonObject {
    let defaults = JsonObject()
    let configuredModel = CliConfig.modelOrEmpty().trimAscii()
    let canonical = MetisConfigManager.canonicalModelRef(configuredModel).trimAscii()
    if (!canonical.isEmpty() && canonical.contains(":")) {
        let parts = canonical.split(":")
        if (parts.size >= 2) {
            defaults.put("modelProvider", JsonString(parts[0].trimAscii()))
            defaults.put("model", JsonString(String.join(parts[1..parts.size], delimiter: ":").trimAscii()))
            defaults.put("contextTokens", ModelTokenLimits.getInputLimit(canonical).toJsonValue())
            return defaults
        }
    }
    defaults.put("modelProvider", JsonString(""))
    defaults.put("model", JsonString(configuredModel))
    if (!configuredModel.isEmpty()) {
        defaults.put("contextTokens", ModelTokenLimits.getInputLimit(configuredModel).toJsonValue())
    } else {
        defaults.put("contextTokens", 0.toJsonValue())
    }
    defaults
}

private func gatewaySessionsDeliveryContextJson(delivery: JsonObject): JsonObject {
    let out = JsonObject()
    match (delivery.get("channel")) {
        case Some(v) =>
            try {
                let channel = v.asString().getValue().trimAscii()
                if (!channel.isEmpty()) {
                    out.put("channel", JsonString(channel))
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    match (delivery.get("replyTo")) {
        case Some(v) =>
            try {
                let to = v.asString().getValue().trimAscii()
                if (!to.isEmpty()) {
                    out.put("to", JsonString(to))
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    match (delivery.get("accountId")) {
        case Some(v) =>
            try {
                let accountId = v.asString().getValue().trimAscii()
                if (!accountId.isEmpty()) {
                    out.put("accountId", JsonString(accountId))
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    match (delivery.get("threadId")) {
        case Some(v) =>
            try {
                let threadId = v.asString().getValue().trimAscii()
                if (!threadId.isEmpty()) {
                    out.put("threadId", JsonString(threadId))
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    out
}

private func gatewaySessionsThreadBindingJson(row: JsonObject): JsonObject {
    let out = JsonObject()
    let streamTo = gatewaySessionsTranscriptString(row, "streamTo")
    let delivery = match (row.get("deliveryContext")) {
        case Some(v) =>
            try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let threadEnabled = match (row.get("thread")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
    let channel = if (!gatewaySessionsTranscriptString(delivery, "channel").isEmpty()) {
        gatewaySessionsTranscriptString(delivery, "channel")
    } else {
        gatewaySessionsTranscriptString(row, "lastChannel")
    }
    let peer = if (!gatewaySessionsTranscriptString(delivery, "to").isEmpty()) {
        gatewaySessionsTranscriptString(delivery, "to")
    } else {
        gatewaySessionsTranscriptString(row, "lastTo")
    }
    let threadId = if (!gatewaySessionsTranscriptString(delivery, "threadId").isEmpty()) {
        gatewaySessionsTranscriptString(delivery, "threadId")
    } else {
        gatewaySessionsTranscriptString(row, "lastThreadId")
    }
    if (!threadEnabled && threadId.isEmpty() && streamTo.isEmpty()) {
        return out
    }
    out.put("enabled", true.toJsonValue())
    if (!channel.isEmpty()) {
        out.put("channel", JsonString(channel))
    }
    if (!peer.isEmpty()) {
        out.put("peer", JsonString(peer))
    }
    if (!threadId.isEmpty()) {
        out.put("threadId", JsonString(threadId))
    }
    if (!streamTo.isEmpty()) {
        out.put("streamTo", JsonString(streamTo))
    }
    out
}

private func gatewaySessionsClassifyKind(key: String, chatType: String): String {
    let normalizedKey = key.trimAscii()
    if (normalizedKey == "global") {
        return "global"
    }
    let normalizedChatType = chatType.trimAscii().toAsciiLower()
    if (normalizedChatType == "group" || normalizedChatType == "channel") {
        return "group"
    }
    if (normalizedKey.contains(":group:") || normalizedKey.contains(":channel:")) {
        return "group"
    }
    if (normalizedKey.isEmpty()) {
        return "unknown"
    }
    "direct"
}

private func gatewaySessionsMessagesFromRaw(raw: String, limit: Int64): JsonArray {
    let allMessages = ArrayList<JsonObject>()
    var messageSeq = 0
    for (obj in gatewayControlUiParseJsonObjectsFromRaw(raw)) {
        let rowType = match (obj.get("type")) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_: Exception) { "" }
            case None => ""
        }
        let kind = match (obj.get("kind")) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_: Exception) { "" }
            case None => ""
        }
        if (kind == "meta" || kind == "binding") {
            continue
        }
        let role = gatewaySessionsPreviewRole(match (obj.get("role")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        })
        let text = match (obj.get("text")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        }
        if (role.isEmpty() || text.trimAscii().isEmpty()) {
            if (rowType != "compaction") {
                continue
            }
            messageSeq += 1
            let message = gatewayBuildChatEventMessage("system", "Compaction", gatewaySessionsCompactionTimestamp(obj))
            let legacyMeta = JsonObject()
            legacyMeta.put("kind", JsonString("compaction"))
            legacyMeta.put("seq", messageSeq.toJsonValue())
            match (obj.get("id")) {
                case Some(v) =>
                    try {
                        let messageId = v.asString().getValue().trimAscii()
                        if (!messageId.isEmpty()) {
                            legacyMeta.put("id", JsonString(messageId))
                        }
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
            message.put("__metis", legacyMeta)
            allMessages.add(message)
            continue
        }
        messageSeq += 1
        let message = gatewayBuildChatEventMessage(role, text, gatewaySessionsMessageTimestamp(obj))
        let legacyMeta = JsonObject()
        legacyMeta.put("seq", messageSeq.toJsonValue())
        match (obj.get("id")) {
            case Some(v) =>
                try {
                    let messageId = v.asString().getValue().trimAscii()
                    if (!messageId.isEmpty()) {
                        legacyMeta.put("id", JsonString(messageId))
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        message.put("__metis", legacyMeta)
        allMessages.add(message)
    }
    let out = JsonArray([])
    let maxItems = max(1, limit)
    let start = max(0, allMessages.size - maxItems)
    for (i in start..allMessages.size) {
        out.add(allMessages[i])
    }
    out
}

private func gatewaySessionsPreviewResolvedContext(user: GatewayUserSettings, requestedKey: String): (String, String) {
    let params = JsonObject()
    params.put("session", JsonString(requestedKey.trimAscii()))
    let request = gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc)
    let context = gatewayResolveSessionContext(request)
    let store = gatewaySessionStoreForResolvedRequest(user, request)
    (context.sessionKey, store.readTranscriptRaw(context.sessionKey).getOrDefault({ => "" }))
}

private func gatewaySessionsResolvedKey(request: GatewayRpcRequest, requestedKey: String): String {
    let params = JsonObject()
    params.put("session", JsonString(requestedKey.trimAscii()))
    let sessionRequest = gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc)
    gatewayResolveSessionContext(sessionRequest).sessionKey
}

private func gatewaySessionsResolvedStore(user: GatewayUserSettings, requestedKey: String): (String, GatewaySessionStore) {
    let params = JsonObject()
    params.put("session", JsonString(requestedKey.trimAscii()))
    let request = gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc)
    let context = gatewayResolveSessionContext(request)
    (context.sessionKey, gatewaySessionStoreForResolvedRequest(user, request))
}

private func gatewaySessionsValueIsNull(value: JsonValue): Bool {
    value.toJsonString().trimAscii() == "null"
}

private func gatewaySessionsPatchStringField(entry: JsonObject, request: GatewayRpcRequest, key: String): Bool {
    match (request.params.get(key)) {
        case Some(v) =>
            if (gatewaySessionsValueIsNull(v)) {
                entry.put(key, JsonString(""))
                return true
            }
            try {
                entry.put(key, JsonString(v.asString().getValue().trimAscii()))
                true
            } catch (_: Exception) {
                false
            }
        case None => false
    }
}

private func gatewaySessionsPatchBoolField(entry: JsonObject, request: GatewayRpcRequest, key: String): Bool {
    match (request.params.get(key)) {
        case Some(v) =>
            if (gatewaySessionsValueIsNull(v)) {
                entry.put(key, false.toJsonValue())
                return true
            }
            try {
                entry.put(key, v.asBool().getValue().toJsonValue())
                true
            } catch (_: Exception) {
                false
            }
        case None => false
    }
}

private func gatewaySessionsPatchIntField(entry: JsonObject, request: GatewayRpcRequest, key: String): Bool {
    match (request.params.get(key)) {
        case Some(v) =>
            if (gatewaySessionsValueIsNull(v)) {
                entry.put(key, 0.toJsonValue())
                return true
            }
            try {
                entry.put(key, Int64.parse(v.toJsonString()).toJsonValue())
                true
            } catch (_: Exception) {
                false
            }
        case None => false
    }
}

private func gatewaySessionsPatchStringArrayField(entry: JsonObject, request: GatewayRpcRequest, key: String): Bool {
    match (request.params.get(key)) {
        case Some(v) =>
            if (gatewaySessionsValueIsNull(v)) {
                entry.put(key, JsonArray([]))
                return true
            }
            try {
                let arr = v.asArray()
                let next = JsonArray([])
                for (i in 0..arr.size()) {
                    try {
                        let text = arr[i].asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            next.add(JsonString(text))
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                entry.put(key, next)
                true
            } catch (_: Exception) {
                false
            }
        case None => false
    }
}

private func gatewaySessionsPatchEntry(entry: JsonObject, request: GatewayRpcRequest): Bool {
    var changed = false
    changed = gatewaySessionsPatchStringField(entry, request, "verboseLevel") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "responseUsage") || changed
    changed = gatewaySessionsPatchBoolField(entry, request, "fastMode") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "sendPolicy") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "spawnedBy") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "spawnedWorkspaceDir") || changed
    changed = gatewaySessionsPatchBoolField(entry, request, "forkedFromParent") || changed
    changed = gatewaySessionsPatchIntField(entry, request, "spawnDepth") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "subagentRole") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "subagentControlScope") || changed
    changed = gatewaySessionsPatchStringField(entry, request, "parentSessionKey") || changed
    changed = gatewaySessionsPatchStringArrayField(entry, request, "childSessions") || changed
    changed
}

private func gatewaySessionsPatchResultFromRow(row: GatewaySessionCatalogRow): JsonObject {
    let entry = JsonObject()
    if (!row.verboseLevel.isEmpty()) {
        entry.put("verboseLevel", JsonString(row.verboseLevel))
    }
    if (!row.responseUsage.isEmpty()) {
        entry.put("responseUsage", JsonString(row.responseUsage))
    }
    entry.put("fastMode", row.fastMode.toJsonValue())
    if (!row.sendPolicy.isEmpty()) {
        entry.put("sendPolicy", JsonString(row.sendPolicy))
    }
    if (!row.spawnedBy.isEmpty()) {
        entry.put("spawnedBy", JsonString(row.spawnedBy))
    }
    if (!row.spawnedWorkspaceDir.isEmpty()) {
        entry.put("spawnedWorkspaceDir", JsonString(row.spawnedWorkspaceDir))
    }
    entry.put("forkedFromParent", row.forkedFromParent.toJsonValue())
    if (row.spawnDepth > 0) {
        entry.put("spawnDepth", row.spawnDepth.toJsonValue())
    }
    if (!row.subagentRole.isEmpty()) {
        entry.put("subagentRole", JsonString(row.subagentRole))
    }
    if (!row.subagentControlScope.isEmpty()) {
        entry.put("subagentControlScope", JsonString(row.subagentControlScope))
    }
    if (!row.parentSessionKey.isEmpty()) {
        entry.put("parentSessionKey", JsonString(row.parentSessionKey))
    }
    if (row.childSessions.size > 0) {
        let children = JsonArray([])
        for (child in row.childSessions) {
            children.add(JsonString(child))
        }
        entry.put("childSessions", children)
    }
    entry
}

private func gatewaySessionsResetMetaLine(sessionKey: String): String {
    let jo = JsonObject()
    jo.put("kind", JsonString("meta"))
    jo.put("v", JsonString("1"))
    jo.put("sessionKey", JsonString(sessionKey.trimAscii()))
    jo.toJsonString() + "\n"
}

private func gatewaySessionsArchivePath(path: Path, reason: String): Path {
    let ts = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let normalized = reason.trimAscii().toAsciiLower()
    if (normalized == "bak") {
        return Path("${path.toString()}.bak.${ts}")
    }
    Path("${path.toString()}.${normalized}.${ts}.bak")
}

private func gatewaySessionsResetIndexEntry(entry: JsonObject): Unit {
    entry.put("updatedAt", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
    entry.put("contextTokens", 0.toJsonValue())
    entry.put("totalTokens", 0.toJsonValue())
    entry.put("totalTokensFresh", false.toJsonValue())
    entry.put("estimatedCostUsd", 0.0.toJsonValue())
    entry.put("modelProvider", JsonString(""))
    entry.put("model", JsonString(""))
}

private func gatewaySessionsResetResultFromRow(row: GatewaySessionCatalogRow): JsonObject {
    let entry = gatewaySessionsPatchResultFromRow(row)
    entry.put("sessionId", JsonString(row.sessionId))
    entry.put("sessionFile", JsonString(row.sessionFile))
    if (!row.lastAccountId.isEmpty()) {
        entry.put("lastAccountId", JsonString(row.lastAccountId))
    }
    if (row.lastThreadId > 0) {
        entry.put("lastThreadId", row.lastThreadId.toJsonValue())
    }
    entry
}

private func gatewaySessionsCompactIndexEntry(entry: JsonObject): Unit {
    entry.put("updatedAt", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
    entry.put("contextTokens", 0.toJsonValue())
    entry.put("totalTokens", 0.toJsonValue())
    entry.put("totalTokensFresh", false.toJsonValue())
    entry.put("estimatedCostUsd", 0.0.toJsonValue())
}

private func gatewaySessionsDeleteResult(key: String, deleted: Bool, archived: Array<String>): JsonObject {
    let result = JsonObject()
    result.put("ok", true.toJsonValue())
    result.put("key", JsonString(key))
    result.put("deleted", deleted.toJsonValue())
    let archivedJson = JsonArray([])
    for (path in archived) {
        archivedJson.add(JsonString(path))
    }
    result.put("archived", archivedJson)
    result
}

public func handleGatewaySessionsFamily(method: String, request!: Option<GatewayRpcRequest> = None<GatewayRpcRequest>): Option<GatewayRpcResponse> {
    if (method == "sessions.list") {
        let user = CliSettingManager.readGatewaySettings()
        let rootsList = gatewaySessionStorageRootsForUser(user)
        let sessions = JsonArray([])
        for (entry in gatewayListSessionConversationViewsForUser(user)) {
            try {
                let transcriptStore = GatewaySessionStore(entry.root)
                let row = JsonObject()
                row.put("key", JsonString(entry.key))
                row.put("agentId", JsonString(entry.agentId))
                row.put("kind", JsonString(gatewaySessionsClassifyKind(entry.key, entry.chatType)))
                row.put("root", JsonString(entry.root.toString()))
                row.put("sessionId", JsonString(entry.sessionId))
                row.put("sessionFile", JsonString(entry.sessionFile))
                row.put("displayName", JsonString(entry.displayName))
                row.put("channel", JsonString(entry.channel))
                row.put("chatType", JsonString(entry.chatType))
                row.put("peer", JsonString(entry.peer))
                row.put("origin", entry.origin)
                row.put("delivery", entry.delivery)
                row.put("binding", entry.binding)
                row.put("updatedAt", JsonString("${entry.updatedAt}"))
                match (gatewayFindSessionCatalogRowForUser(user, entry.key)) {
                    case Some(catalogRow) =>
                        if (!catalogRow.verboseLevel.isEmpty()) {
                            row.put("verboseLevel", JsonString(catalogRow.verboseLevel))
                        }
                        if (!catalogRow.responseUsage.isEmpty()) {
                            row.put("responseUsage", JsonString(catalogRow.responseUsage))
                        }
                        row.put("fastMode", catalogRow.fastMode.toJsonValue())
                        if (!catalogRow.sendPolicy.isEmpty()) {
                            row.put("sendPolicy", JsonString(catalogRow.sendPolicy))
                        }
                        if (!catalogRow.lastChannel.isEmpty()) {
                            row.put("lastChannel", JsonString(catalogRow.lastChannel))
                        }
                        if (!catalogRow.lastTo.isEmpty()) {
                            row.put("lastTo", JsonString(catalogRow.lastTo))
                        }
                        if (!catalogRow.lastAccountId.isEmpty()) {
                            row.put("lastAccountId", JsonString(catalogRow.lastAccountId))
                        }
                        if (catalogRow.lastThreadId > 0) {
                            row.put("lastThreadId", catalogRow.lastThreadId.toJsonValue())
                        }
                        if (!catalogRow.modelProvider.isEmpty()) {
                            row.put("modelProvider", JsonString(catalogRow.modelProvider))
                        }
                        if (!catalogRow.model.isEmpty()) {
                            row.put("model", JsonString(catalogRow.model))
                        }
                        if (catalogRow.contextTokens > 0) {
                            row.put("contextTokens", catalogRow.contextTokens.toJsonValue())
                        }
                        if (catalogRow.totalTokens > 0 || catalogRow.totalTokensFresh) {
                            row.put("totalTokens", catalogRow.totalTokens.toJsonValue())
                            row.put("totalTokensFresh", catalogRow.totalTokensFresh.toJsonValue())
                        }
                        if (catalogRow.estimatedCostUsd > 0.0) {
                            row.put("estimatedCostUsd", catalogRow.estimatedCostUsd.toJsonValue())
                        }
                        if (!catalogRow.spawnedBy.isEmpty()) {
                            row.put("spawnedBy", JsonString(catalogRow.spawnedBy))
                        }
                        if (!catalogRow.spawnedWorkspaceDir.isEmpty()) {
                            row.put("spawnedWorkspaceDir", JsonString(catalogRow.spawnedWorkspaceDir))
                        }
                        row.put("forkedFromParent", catalogRow.forkedFromParent.toJsonValue())
                        if (catalogRow.spawnDepth > 0) {
                            row.put("spawnDepth", catalogRow.spawnDepth.toJsonValue())
                        }
                        if (!catalogRow.subagentRole.isEmpty()) {
                            row.put("subagentRole", JsonString(catalogRow.subagentRole))
                        }
                        if (!catalogRow.subagentControlScope.isEmpty()) {
                            row.put("subagentControlScope", JsonString(catalogRow.subagentControlScope))
                        }
                        if (!catalogRow.parentSessionKey.isEmpty()) {
                            row.put("parentSessionKey", JsonString(catalogRow.parentSessionKey))
                        }
                        if (catalogRow.childSessions.size > 0) {
                            let children = JsonArray([])
                            for (child in catalogRow.childSessions) {
                                children.add(JsonString(child))
                            }
                            row.put("childSessions", children)
                        }
                    case None => ()
                }
                let deliveryContext = gatewaySessionsDeliveryContextJson(entry.delivery)
                if (deliveryContext.size() > 0) {
                    row.put("deliveryContext", deliveryContext)
                    if (row.get("lastChannel").isNone()) {
                        match (deliveryContext.get("channel")) {
                            case Some(v) => row.put("lastChannel", v)
                            case None => ()
                        }
                    }
                    if (row.get("lastTo").isNone()) {
                        match (deliveryContext.get("to")) {
                            case Some(v) => row.put("lastTo", v)
                            case None => ()
                        }
                    }
                    if (row.get("lastAccountId").isNone()) {
                        match (deliveryContext.get("accountId")) {
                            case Some(v) => row.put("lastAccountId", v)
                            case None => ()
                        }
                    }
                    if (row.get("lastThreadId").isNone()) {
                        match (deliveryContext.get("threadId")) {
                            case Some(v) => row.put("lastThreadId", v)
                            case None => ()
                        }
                    }
                }
                let threadBinding = gatewaySessionsThreadBindingJson(row)
                if (threadBinding.size() > 0) {
                    row.put("threadBinding", threadBinding)
                }
                if (let Some(transcriptRaw) <- transcriptStore.readTranscriptRaw(entry.key)) {
                    gatewaySessionsApplyTranscriptFallback(row, transcriptRaw)
                    row.put(
                        "derivedTitle",
                        JsonString(gatewaySessionsDeriveTitle(transcriptRaw, entry.displayName, entry.sessionId))
                    )
                    let lastMessagePreview = gatewaySessionsLastMessagePreview(transcriptRaw)
                    if (!lastMessagePreview.isEmpty()) {
                        row.put("lastMessagePreview", JsonString(lastMessagePreview))
                    }
                }
                sessions.add(row)
            } catch (_: Exception) {
                ()
            }
        }
        let roots = JsonArray([])
        for (root in rootsList) {
            roots.add(JsonString(root))
        }
        let result = JsonObject()
        result.put("path", JsonString(rootsList[0]))
        result.put("roots", roots)
        result.put("defaults", gatewaySessionsDefaultModelSummary())
        result.put("sessions", sessions)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.path") {
        let user = CliSettingManager.readGatewaySettings()
        let rootsList = gatewaySessionStorageRootsForUser(user)
        let roots = JsonArray([])
        for (root in rootsList) {
            roots.add(JsonString(root))
        }
        let result = JsonObject()
        result.put("path", JsonString(rootsList[0]))
        result.put("roots", roots)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.subscribe") {
        let clientId = match (request) {
            case Some(req) => gatewaySessionsRpcStringParam(req, ["clientId", "client", "id"], req.clientId.trimAscii())
            case None => ""
        }
        let kinds = gatewayServerSubscribeSessionEvents(clientId)
        let result = JsonObject()
        result.put("subscribed", (!clientId.isEmpty()).toJsonValue())
        let kindsJson = JsonArray([])
        for (kind in kinds) {
            kindsJson.add(JsonString(kind))
        }
        result.put("kinds", kindsJson)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.unsubscribe") {
        let clientId = match (request) {
            case Some(req) => gatewaySessionsRpcStringParam(req, ["clientId", "client", "id"], req.clientId.trimAscii())
            case None => ""
        }
        gatewayServerUnsubscribeSessionEvents(clientId)
        let result = JsonObject()
        result.put("subscribed", false.toJsonValue())
        let kindsJson = JsonArray([])
        for (kind in gatewayServerSessionEventKinds(clientId)) {
            kindsJson.add(JsonString(kind))
        }
        result.put("kinds", kindsJson)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.messages.subscribe") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(true, method, result: JsonObject()))
        }
        let clientId = req.clientId.trimAscii()
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "session"], "")
        let key = gatewaySessionsResolvedKey(req, requestedKey)
        let result = JsonObject()
        result.put("subscribed", gatewayServerSubscribeSessionMessageEvents(clientId, key).toJsonValue())
        result.put("key", JsonString(key))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.messages.unsubscribe") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(true, method, result: JsonObject()))
        }
        let clientId = req.clientId.trimAscii()
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "session"], "")
        let key = gatewaySessionsResolvedKey(req, requestedKey)
        let result = JsonObject()
        result.put("subscribed", false.toJsonValue())
        let _ = gatewayServerUnsubscribeSessionMessageEvents(clientId, key)
        result.put("key", JsonString(key))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.preview") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(true, method, result: JsonObject()))
        }
        let keys = gatewaySessionsRpcStringArrayParam(req, "keys")
        let limit = max(1, gatewaySessionsRpcIntParam(req, "limit", 12))
        let maxChars = max(20, gatewaySessionsRpcIntParam(req, "maxChars", 240))
        let previews = JsonArray([])
        let user = CliSettingManager.readGatewaySettings()
        for (i in 0..min(keys.size, 64)) {
            let key = keys[i]
            let row = JsonObject()
            row.put("key", JsonString(key))
            try {
                let (resolvedKey, raw) = gatewaySessionsPreviewResolvedContext(user, key)
                if (resolvedKey.isEmpty() || raw.isEmpty()) {
                    row.put("status", JsonString("missing"))
                    row.put("items", JsonArray([]))
                } else {
                    let items = gatewaySessionsPreviewItemsFromRaw(raw, limit, maxChars)
                    row.put("status", JsonString(if (items.size() > 0) { "ok" } else { "empty" }))
                    row.put("items", items)
                }
            } catch (_: Exception) {
                row.put("status", JsonString("error"))
                row.put("items", JsonArray([]))
            }
            previews.add(row)
        }
        let result = JsonObject()
        result.put("ts", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        result.put("previews", previews)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.get") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(true, method, result: JsonObject()))
        }
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "sessionKey", "session"], "")
        let limit = max(1, gatewaySessionsRpcIntParam(req, "limit", 200))
        let result = JsonObject()
        result.put("messages", JsonArray([]))
        if (requestedKey.isEmpty()) {
            return Some(GatewayRpcResponse(true, method, result: result))
        }
        let user = CliSettingManager.readGatewaySettings()
        try {
            let (_, raw) = gatewaySessionsPreviewResolvedContext(user, requestedKey)
            if (!raw.isEmpty()) {
                result.put("messages", gatewaySessionsMessagesFromRaw(raw, limit))
            }
        } catch (_: Exception) {
            ()
        }
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.patch") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(false, method, error: "missing request"))
        }
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "sessionKey", "session"], "")
        if (requestedKey.isEmpty()) {
            return Some(GatewayRpcResponse(false, method, error: "missing session key"))
        }
        let user = CliSettingManager.readGatewaySettings()
        let (resolvedKey, store) = gatewaySessionsResolvedStore(user, requestedKey)
        let _ = store.listSessionKeys()
        let indexRoot = store.readSessionsIndexRoot()
        let existing = match (indexRoot.get(resolvedKey)) {
            case Some(v) =>
                try { v.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        if (existing.get("sessionKey").isNone()) {
            return Some(GatewayRpcResponse(false, method, error: "session not found"))
        }
        let changed = gatewaySessionsPatchEntry(existing, req)
        if (changed) {
            existing.put("updatedAt", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
            indexRoot.put(resolvedKey, existing)
            try {
                File.writeTo(store.sessionsRoot().join("sessions.json"), indexRoot.toJsonString().toArray())
            } catch (_: Exception) {
                return Some(GatewayRpcResponse(false, method, error: "failed to persist session patch"))
            }
        }
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("key", JsonString(resolvedKey))
        match (gatewayFindSessionCatalogRowForUser(user, resolvedKey)) {
            case Some(row) => result.put("entry", gatewaySessionsPatchResultFromRow(row))
            case None => result.put("entry", JsonObject())
        }
        let _ = gatewayServerPublishSessionsChangedEvent(resolvedKey, reason: "patch", detail: "patch")
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.delete") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(false, method, error: "missing request"))
        }
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "sessionKey", "session"], "")
        if (requestedKey.isEmpty()) {
            return Some(GatewayRpcResponse(false, method, error: "missing session key"))
        }
        match (req.params.get("deleteTranscript")) {
            case Some(v) =>
                try {
                    if (!v.asBool().getValue()) {
                        return Some(GatewayRpcResponse(false, method, error: "deleteTranscript=false is not supported"))
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        let user = CliSettingManager.readGatewaySettings()
        let (resolvedKey, store) = gatewaySessionsResolvedStore(user, requestedKey)
        let conversation = gatewayFindSessionConversationViewForUser(user, resolvedKey)
        if (resolvedKey == "agent:main:main") {
            return Some(GatewayRpcResponse(false, method, error: "cannot delete the main session"))
        }
        let transcriptPath = store.transcriptPath(resolvedKey)
        let hadTranscript = exists(transcriptPath)
        let indexRoot = store.readSessionsIndexRoot()
        let hadEntry = indexRoot.get(resolvedKey).isSome()
        if (!hadTranscript && !hadEntry) {
            return Some(GatewayRpcResponse(true, method, result: gatewaySessionsDeleteResult(resolvedKey, false, [])))
        }
        let archived = ArrayList<String>()
        if (hadTranscript) {
            let archivedPath = gatewaySessionsArchivePath(transcriptPath, "deleted")
            try {
                copy(transcriptPath, to: archivedPath, overwrite: false)
                remove(transcriptPath)
                archived.add(archivedPath.toString())
            } catch (_: Exception) {
                return Some(GatewayRpcResponse(false, method, error: "failed to delete session transcript"))
            }
        }
        let _ = store.listSessionKeys()
        let result = gatewaySessionsDeleteResult(resolvedKey, true, archived.toArray())
        let lifecyclePayload = gatewayBuildSessionEventPayload(
            resolvedKey,
            "deleted",
            conversation: conversation,
            detail: "deleted"
        )
        let _ = gatewayServerPublishSessionLifecycleEvent(lifecyclePayload, detail: "deleted")
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.reset") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(false, method, error: "missing request"))
        }
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "sessionKey", "session"], "")
        if (requestedKey.isEmpty()) {
            return Some(GatewayRpcResponse(false, method, error: "missing session key"))
        }
        let reasonRaw = gatewaySessionsRpcStringParam(req, ["reason"], "reset").toAsciiLower()
        let reason = if (reasonRaw == "new") { "new" } else { "reset" }
        let user = CliSettingManager.readGatewaySettings()
        let (resolvedKey, store) = gatewaySessionsResolvedStore(user, requestedKey)
        let conversation = gatewayFindSessionConversationViewForUser(user, resolvedKey)
        let transcriptPath = store.transcriptPath(resolvedKey)
        if (exists(transcriptPath)) {
            try {
                let archived = gatewaySessionsArchivePath(transcriptPath, reason)
                copy(transcriptPath, to: archived, overwrite: false)
                remove(transcriptPath)
            } catch (_: Exception) {
                return Some(GatewayRpcResponse(false, method, error: "failed to archive session transcript"))
            }
        }
        try {
            File.writeTo(transcriptPath, gatewaySessionsResetMetaLine(resolvedKey).toArray())
        } catch (_: Exception) {
            return Some(GatewayRpcResponse(false, method, error: "failed to reset session transcript"))
        }
        let _ = store.listSessionKeys()
        let indexRoot = store.readSessionsIndexRoot()
        let entry = match (indexRoot.get(resolvedKey)) {
            case Some(v) =>
                try { v.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        if (entry.get("sessionKey").isSome()) {
            gatewaySessionsResetIndexEntry(entry)
            indexRoot.put(resolvedKey, entry)
            try {
                File.writeTo(store.sessionsRoot().join("sessions.json"), indexRoot.toJsonString().toArray())
            } catch (_: Exception) {
                return Some(GatewayRpcResponse(false, method, error: "failed to persist session reset"))
            }
        }
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("key", JsonString(resolvedKey))
        match (gatewayFindSessionCatalogRowForUser(user, resolvedKey)) {
            case Some(row) => result.put("entry", gatewaySessionsResetResultFromRow(row))
            case None => result.put("entry", JsonObject())
        }
        let lifecyclePayload = gatewayBuildSessionEventPayload(
            resolvedKey,
            reason,
            conversation: conversation,
            detail: reason
        )
        let _ = gatewayServerPublishSessionLifecycleEvent(lifecyclePayload, detail: reason)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "sessions.compact") {
        let req = match (request) {
            case Some(value) => value
            case None => return Some(GatewayRpcResponse(false, method, error: "missing request"))
        }
        let requestedKey = gatewaySessionsRpcStringParam(req, ["key", "sessionKey", "session"], "")
        if (requestedKey.isEmpty()) {
            return Some(GatewayRpcResponse(false, method, error: "missing session key"))
        }
        let maxLines = max(1, gatewaySessionsRpcIntParam(req, "maxLines", 400))
        let user = CliSettingManager.readGatewaySettings()
        let (resolvedKey, store) = gatewaySessionsResolvedStore(user, requestedKey)
        let transcriptPath = store.transcriptPath(resolvedKey)
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("key", JsonString(resolvedKey))
        if (!exists(transcriptPath)) {
            result.put("compacted", false.toJsonValue())
            result.put("reason", JsonString("no transcript"))
            return Some(GatewayRpcResponse(true, method, result: result))
        }
        let raw = try {
            String.fromUtf8(File.readFrom(transcriptPath))
        } catch (_: Exception) {
            result.put("compacted", false.toJsonValue())
            result.put("reason", JsonString("read failed"))
            return Some(GatewayRpcResponse(true, method, result: result))
        }
        let linesRaw = raw.split("\n")
        let lines = ArrayList<String>()
        for (line in linesRaw) {
            if (!line.trimAscii().isEmpty()) {
                lines.add(line)
            }
        }
        if (lines.size <= maxLines) {
            result.put("compacted", false.toJsonValue())
            result.put("kept", Int64(lines.size).toJsonValue())
            return Some(GatewayRpcResponse(true, method, result: result))
        }
        let archived = gatewaySessionsArchivePath(transcriptPath, "bak")
        try {
            copy(transcriptPath, to: archived, overwrite: false)
            let keptLines = lines.toArray()[lines.size - maxLines..lines.size]
            File.writeTo(transcriptPath, (String.join(keptLines, delimiter: "\n") + "\n").toArray())
            let _ = store.listSessionKeys()
            let indexRoot = store.readSessionsIndexRoot()
            match (indexRoot.get(resolvedKey)) {
                case Some(v) =>
                    try {
                        let entry = v.asObject()
                        gatewaySessionsCompactIndexEntry(entry)
                        indexRoot.put(resolvedKey, entry)
                        File.writeTo(store.sessionsRoot().join("sessions.json"), indexRoot.toJsonString().toArray())
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
            result.put("compacted", true.toJsonValue())
            result.put("archived", JsonString(archived.toString()))
            result.put("kept", maxLines.toJsonValue())
            let _ = gatewayServerPublishSessionsChangedEvent(resolvedKey, reason: "compact", detail: "compact", compacted: true)
            return Some(GatewayRpcResponse(true, method, result: result))
        } catch (_: Exception) {
            result.put("compacted", false.toJsonValue())
            result.put("reason", JsonString("compact failed"))
            return Some(GatewayRpcResponse(true, method, result: result))
        }
    }
    None
}
