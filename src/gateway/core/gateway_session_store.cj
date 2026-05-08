package metis.gateway.core

import magic.jsonable.*
import magic.log.LogUtils

import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.gateway.session.{GatewayDeliveryTarget, GatewayIngressSource, GatewaySessionRequest, gatewayResolveSessionContext, gatewaySessionRequestFromRpcParams}

import std.collection.ArrayList
import std.convert.*
import std.fs.{Path, File, Directory, FileInfo, exists, remove, OpenMode, FSException, copy}
import std.sort.sort
import std.time.DateTime

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewayEmptySessionStringArray(): Array<String> {
    let out = ArrayList<String>()
    out.toArray()
}

/**
 * 网关会话持久化。
 *
 * - 目录：`~/.metis/agents/<agentId>/sessions/`（由 `gateway.session.agentId` 配置，默认 `main`）。
 * - 转录：`<fileStem>.jsonl`，首行 meta（`kind`/`sessionKey`），后续为 user/assistant 等消息行。
 * - 索引：`sessions.json`，顶层为 `sessionKey -> { updatedAt, sessionFile, sessionId }`；转录行格式仍为仓颉网关实现。
 *
 * 首次使用新目录时，若为空则从旧版 gateway-sessions 目录复制全部 .jsonl 转录（不删除旧目录）。
 */
public class GatewaySessionStore {
    private let root: Path
    private let enabled: Bool
    private let indexAgentId: String

    public init(rootDir: Path, enabled!: Bool = true, agentId!: String = "main") {
        this.root = rootDir
        this.enabled = enabled
        this.indexAgentId = gatewaySanitizeAgentId(agentId)
    }

    public func isEnabled(): Bool {
        this.enabled
    }

    public func sessionsRoot(): Path {
        this.root
    }

    public func indexAgentLabel(): String {
        this.indexAgentId
    }

    /** 与会话键一一对应的文件名主干（可安全用作文件名）。 */
    public static func fileStemForSessionKey(sessionKey: String): String {
        var s = sessionKey
        let bad = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", "\r", "\n", "\t"]
        for (b in bad) {
            s = s.replace(b, "_")
        }
        if (s.size > 180) {
            return "long_${djb2Hash(sessionKey)}_${sessionKey.size}"
        }
        if (s.isEmpty()) {
            return "empty_session"
        }
        s
    }

    public func transcriptPath(sessionKey: String): Path {
        this.root.join("${fileStemForSessionKey(sessionKey)}.jsonl")
    }

    /**
     * 加载为 AgentBridge 使用的 `user:` / `assistant:` 行列表（不含 meta 行）。
     */
    public func loadHistoryLines(sessionKey: String): ArrayList<String> {
        let out = ArrayList<String>()
        if (!this.enabled) {
            return out
        }
        let p = this.transcriptPath(sessionKey)
        if (!exists(p)) {
            return out
        }
        try {
            let text = String.fromUtf8(File.readFrom(p))
            for (o in parseJsonlTextToObjects(text)) {
                match (parseHistoryFromObject(o)) {
                    case Some(pair) => out.add("${pair[0]}: ${pair[1]}")
                    case None => ()
                }
            }
        } catch (_e: Exception) {
            ()
        }
        out
    }

    /**
     * 追加一轮 user + assistant（先写 user，模型返回后再写 assistant）。
     */
    public func appendUser(sessionKey: String, text: String): Unit {
        this.appendRole(sessionKey, "user", text)
    }

    public func appendAssistant(sessionKey: String, text: String): Unit {
        this.appendRole(sessionKey, "assistant", text)
    }

    /**
     * 追加任意 role 的转录行（如 system、或由 Agent 工具注入的 assistant），供 sessions_send 等使用。
     */
    public func appendTranscriptEntry(sessionKey: String, role: String, text: String): Unit {
        this.appendRole(sessionKey, role, text)
    }

    /**
     * 记录最近一次真实的会话 binding / delivery 快照。
     * 该快照会在 catalog / conversation view 中回放，避免仅靠 sessionKey 猜测 thread / reply target。
     */
    public func appendBindingSnapshot(
        sessionKey: String,
        target: GatewayDeliveryTarget,
        mode!: String = "delivery-target"
    ): Unit {
        if (!this.enabled) {
            return
        }
        try {
            ensureDir()
            let p = this.transcriptPath(sessionKey)
            let needMeta = !exists(p)
            if (needMeta) {
                writeEntireFile(p, metaLine(sessionKey) + "\n")
            }
            let ts = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
            let jo = JsonObject()
            jo.put("kind", JsonString("binding"))
            jo.put("channel", JsonString(target.channelName))
            jo.put("peer", JsonString(target.peerId))
            jo.put("accountId", JsonString(target.accountId))
            jo.put("conversationId", JsonString(target.conversationId))
            jo.put("threadId", JsonString(target.threadId))
            jo.put("sourceMessageId", JsonString(target.sourceMessageId))
            jo.put("replyToMessageId", JsonString(target.replyToMessageId))
            jo.put("replyTargetMessageId", JsonString(target.replyToMessageId))
            jo.put("replyInThread", target.replyInThread.toJsonValue())
            jo.put("deliverable", (!target.channelName.trimAscii().isEmpty()).toJsonValue())
            jo.put("mode", JsonString(mode.trimAscii()))
            jo.put("ts", JsonString("${ts}"))
            appendUtf8Line(p, jo.toJsonString() + "\n")
        } catch (e: Exception) {
            LogUtils.error("GatewaySessionStore.appendBindingSnapshot failed (sessionKey=${sessionKey}): ${e.message}")
        }
    }

    /**
     * 将某会话转录格式化为易读文本（含 user/assistant/system；不含 meta）。
     * `maxEntries` 为最多包含的消息条数（从文件尾部向前截断）。
     */
    public func formatHistoryAsText(sessionKey: String, maxEntries: Int64): String {
        if (maxEntries <= 0) {
            return "maxEntries must be positive"
        }
        let p = this.transcriptPath(sessionKey)
        if (!exists(p)) {
            return "No transcript file for sessionKey: ${sessionKey}"
        }
        try {
            let raw = String.fromUtf8(File.readFrom(p))
            let objs = parseJsonlTextToObjects(raw)
            let msgs = ArrayList<(String, String)>()
            for (o in objs) {
                match (parseHistoryFromObject(o)) {
                    case Some(pair) => msgs.add(pair)
                    case None => ()
                }
            }
            if (msgs.size == 0) {
                return "(transcript has no user/assistant/system messages yet)"
            }
            let start = max(0, msgs.size - maxEntries)
            let sb = StringBuilder()
            var j = start
            while (j < msgs.size) {
                let pr = msgs[j]
                sb.append("[${pr[0]}] ${pr[1]}\n\n")
                j += 1
            }
            sb.toString()
        } catch (e: Exception) {
            "Failed to read history: ${e.message}"
        }
    }

    /**
     * 新建仅含 meta 的空会话文件，返回新的 sessionKey（用于 sessions_spawn）。
     */
    public func spawnSession(shortLabel: String): String {
        let ts = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
        var lab = shortLabel.trimAscii().replace(":", "_").replace("/", "_").replace("\\", "_")
        if (lab.size > 48) {
            lab = lab[0..48]
        }
        let baseKey = if (lab.isEmpty()) {
            "gateway:spawn:${ts}"
        } else {
            "gateway:spawn:${lab}:${ts}"
        }
        try {
            ensureDir()
            var key = baseKey
            var n: Int64 = 0
            while (exists(this.transcriptPath(key))) {
                n += 1
                key = "${baseKey}#${n}"
            }
            let p = this.transcriptPath(key)
            writeEntireFile(p, metaLine(key) + "\n")
            writeGatewaySessionsIndexJson(collectSessionKeysFromDiskUnsorted())
            key
        } catch (e: Exception) {
            "error:${e.message}"
        }
    }

    private func appendRole(sessionKey: String, role: String, text: String): Unit {
        if (!this.enabled) {
            return
        }
        try {
            ensureDir()
            let p = this.transcriptPath(sessionKey)
            let needMeta = !exists(p)
            if (needMeta) {
                writeEntireFile(p, metaLine(sessionKey) + "\n")
            }
            let ts = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
            let jo = JsonObject()
            jo.put("role", JsonString(role))
            jo.put("text", JsonString(text))
            jo.put("ts", JsonString("${ts}"))
            appendUtf8Line(p, jo.toJsonString() + "\n")
        } catch (e: Exception) {
            LogUtils.error("GatewaySessionStore.appendRole failed (sessionKey=${sessionKey}, role=${role}): ${e.message}")
        }
    }

    private func collectSessionKeysFromDiskUnsorted(): Array<String> {
        let out = ArrayList<String>()
        if (!exists(this.root)) {
            return out.toArray()
        }
        try {
            for (entry in Directory.readFrom(this.root)) {
                if (!entry.isRegular()) {
                    continue
                }
                let name = entry.name
                if (name == "sessions.json" || !name.endsWith(".jsonl")) {
                    continue
                }
                let p = this.root.join(name)
                match (readMetaSessionKey(p)) {
                    case Some(k) => out.add(k)
                    case None => ()
                }
            }
        } catch (_e: Exception) {
            ()
        }
        out.toArray()
    }

    /**
     * 列出已存在的会话（从各 jsonl 首行 meta 读取 sessionKey），并刷新 `sessions.json` 索引。
     */
    public func listSessionKeys(): Array<String> {
        let keys = collectSessionKeysFromDiskUnsorted()
        writeGatewaySessionsIndexJson(keys)
        keys
    }

    public func readTranscriptRaw(sessionKeyOrStem: String): Option<String> {
        var p = this.transcriptPath(sessionKeyOrStem)
        if (!exists(p) && !sessionKeyOrStem.contains(":")) {
            p = this.root.join("${sessionKeyOrStem}.jsonl")
        }
        if (!exists(p)) {
            return None
        }
        try {
            Some(String.fromUtf8(File.readFrom(p)))
        } catch (_e: Exception) {
            None
        }
    }

    public func readLatestBindingSnapshot(sessionKeyOrStem: String): JsonObject {
        match (this.readTranscriptRaw(sessionKeyOrStem)) {
            case Some(raw) =>
                let objs = parseJsonlTextToObjects(raw)
                var i = objs.size - 1
                while (i >= 0) {
                    match (GatewaySessionStore.parseBindingSnapshotFromObject(objs[i])) {
                        case Some(binding) => return binding
                        case None => ()
                    }
                    i -= 1
                }
                JsonObject()
            case None => JsonObject()
        }
    }

    public func deleteSession(sessionKeyOrStem: String): Bool {
        var p = this.transcriptPath(sessionKeyOrStem)
        if (!exists(p) && !sessionKeyOrStem.contains(":")) {
            p = this.root.join("${sessionKeyOrStem}.jsonl")
        }
        if (!exists(p)) {
            return false
        }
        try {
            remove(p)
            writeGatewaySessionsIndexJson(collectSessionKeysFromDiskUnsorted())
            true
        } catch (_e: FSException) {
            false
        }
    }

    public func readSessionsIndexRoot(): JsonObject {
        let path = this.root.join("sessions.json")
        if (!exists(path)) {
            return JsonObject()
        }
        try {
            JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
    }

    public static func sessionIndexString(entry: JsonObject, key: String): String {
        match (entry.get(key)) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
            case None => ""
        }
    }

    public static func sessionIndexBool(entry: JsonObject, key: String, defaultValue!: Bool = false): Bool {
        match (entry.get(key)) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_: Exception) {
                    try {
                        let raw = v.asString().getValue().trimAscii().toAsciiLower()
                        raw == "true" || raw == "1" || raw == "yes" || raw == "on"
                    } catch (_inner: Exception) {
                        defaultValue
                    }
                }
            case None => defaultValue
        }
    }

    public static func sessionIndexInt(entry: JsonObject, key: String, defaultValue!: Int64 = 0): Int64 {
        match (entry.get(key)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_: Exception) {
                    try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { defaultValue }
                }
            case None => defaultValue
        }
    }

    public static func sessionIndexFloat(entry: JsonObject, key: String, defaultValue!: Float64 = 0.0): Float64 {
        match (entry.get(key)) {
            case Some(v) =>
                try { Float64.parse(v.toJsonString()) } catch (_: Exception) {
                    try { Float64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { defaultValue }
                }
            case None => defaultValue
        }
    }

    public static func sessionIndexStringArray(entry: JsonObject, key: String): Array<String> {
        let out = ArrayList<String>()
        match (entry.get(key)) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    for (i in 0..arr.size()) {
                        try {
                            let text = arr[i].asString().getValue().trimAscii()
                            if (!text.isEmpty()) {
                                out.add(text)
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

    public static func copySessionIndexMetadata(from: JsonObject, into!: JsonObject): Unit {
        let stringKeys = [
            "verboseLevel",
            "responseUsage",
            "sendPolicy",
            "thinkingLevel",
            "reasoningVisibility",
            "queueMode",
            "elevatedMode",
            "execDefault",
            "lastChannel",
            "lastTo",
            "lastAccountId",
            "modelProvider",
            "model",
            "spawnedBy",
            "spawnedWorkspaceDir",
            "subagentRole",
            "subagentControlScope",
            "parentSessionKey"
        ]
        for (key in stringKeys) {
            match (from.get(key)) {
                case Some(v) => into.put(key, v)
                case None => ()
            }
        }
        let valueKeys = [
            "fastMode",
            "lastThreadId",
            "contextTokens",
            "totalTokens",
            "totalTokensFresh",
            "estimatedCostUsd",
            "forkedFromParent",
            "spawnDepth",
            "childSessions"
        ]
        for (key in valueKeys) {
            match (from.get(key)) {
                case Some(v) => into.put(key, v)
                case None => ()
            }
        }
    }

    /**
     * 顶层 `sessionKey` -> 条目；含 `updatedAt`(ms)、`sessionFile`、`sessionId`（与文件名 stem 对齐）。
     */
    private func writeGatewaySessionsIndexJson(keys: Array<String>): Unit {
        if (!this.enabled) {
            return
        }
        try {
            ensureDir()
            let previous = this.readSessionsIndexRoot()
            let rootObj = JsonObject()
            for (k in keys) {
                let p = transcriptPath(k)
                var updated: Int64 = 0
                if (exists(p)) {
                    try {
                        updated = FileInfo(p).lastModificationTime.toUnixTimeStamp().toMilliseconds()
                    } catch (_: Exception) {
                        ()
                    }
                }
                let fname = p.fileName
                var stem = fname
                if (fname.size > 6 && fname.endsWith(".jsonl")) {
                    stem = fname[0..fname.size - 6]
                }
                let e = JsonObject()
                e.put("sessionKey", JsonString(k))
                e.put("updatedAt", updated.toJsonValue())
                e.put("sessionFile", JsonString(fname))
                e.put("sessionId", JsonString(stem))
                match (previous.get(k)) {
                    case Some(old) =>
                        try {
                            GatewaySessionStore.copySessionIndexMetadata(old.asObject(), into: e)
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
                rootObj.put(k, e)
            }
            File.writeTo(this.root.join("sessions.json"), rootObj.toJsonString().toArray())
        } catch (_e: Exception) {
            ()
        }
    }

    private func ensureDir(): Unit {
        if (!exists(this.root)) {
            Directory.create(this.root, recursive: true)
        }
    }

    private static func metaLine(sessionKey: String): String {
        let jo = JsonObject()
        jo.put("kind", JsonString("meta"))
        jo.put("v", JsonString("1"))
        jo.put("sessionKey", JsonString(sessionKey))
        jo.toJsonString()
    }

    /**
     * 将 jsonl 文本拆成多个顶层 JSON 对象（支持每行一条，也支持被格式化器展开成多行的对象）。
     */
    private static func parseJsonlTextToObjects(text: String): ArrayList<JsonObject> {
        let objs = ArrayList<JsonObject>()
        let lines = text.split("\n")
        var buffer = ""
        for (line in lines) {
            if (buffer.isEmpty() && line.trimAscii().isEmpty()) {
                continue
            }
            buffer = if (buffer.isEmpty()) {
                line
            } else {
                buffer + "\n" + line
            }
            let candidate = buffer.trimAscii()
            try {
                objs.add(JsonValue.fromStr(candidate).asObject())
                buffer = ""
            } catch (_: Exception) {
                ()
            }
        }
        objs
    }

    private static func parseHistoryFromObject(o: JsonObject): Option<(String, String)> {
        match (o.get("kind")) {
            case Some(kv) =>
                if (kv.asString().getValue() == "meta") {
                    return None
                }
            case None => ()
        }
        let role = match (o.get("role")) {
            case Some(rv) => rv.asString().getValue()
            case None => return None
        }
        let txt = match (o.get("text")) {
            case Some(tv) => tv.asString().getValue()
            case None => return None
        }
        Some((role, txt))
    }

    private static func parseBindingSnapshotFromObject(o: JsonObject): Option<JsonObject> {
        match (o.get("kind")) {
            case Some(kindVal) =>
                if (kindVal.asString().getValue() != "binding") {
                    return None
                }
            case None => return None
        }
        let normalized = JsonObject()
        normalized.put("channel", o.get("channel") ?? JsonString(""))
        normalized.put("peer", o.get("peer") ?? JsonString(""))
        normalized.put("accountId", o.get("accountId") ?? JsonString(""))
        normalized.put("conversationId", o.get("conversationId") ?? JsonString(""))
        normalized.put("threadId", o.get("threadId") ?? JsonString(""))
        normalized.put("sourceMessageId", o.get("sourceMessageId") ?? JsonString(""))
        normalized.put("replyToMessageId", o.get("replyToMessageId") ?? JsonString(""))
        normalized.put("replyTargetMessageId", o.get("replyTargetMessageId") ?? o.get("replyToMessageId") ?? JsonString(""))
        normalized.put("replyInThread", o.get("replyInThread") ?? false.toJsonValue())
        normalized.put("deliverable", o.get("deliverable") ?? false.toJsonValue())
        normalized.put("mode", o.get("mode") ?? JsonString("binding-snapshot"))
        Some(normalized)
    }

    private static func readMetaSessionKey(path: Path): Option<String> {
        try {
            let text = String.fromUtf8(File.readFrom(path))
            let objs = parseJsonlTextToObjects(text)
            if (objs.size == 0) {
                return None
            }
            let o = objs[0]
            match (o.get("kind")) {
                case Some(kv) =>
                    if (kv.asString().getValue() != "meta") {
                        return None
                    }
                case None => return None
            }
            match (o.get("sessionKey")) {
                case Some(sv) => Some(sv.asString().getValue())
                case None => None
            }
        } catch (_e: Exception) {
            None
        }
    }

    private static func writeEntireFile(path: Path, content: String): Unit {
        File.writeTo(path, content.toArray())
    }

    private static func appendUtf8Line(path: Path, line: String): Unit {
        try (file = File(path, OpenMode.Append)) {
            file.write(line.toArray())
        }
    }

    private static func djb2Hash(s: String): UInt64 {
        var h: UInt64 = 5381
        let bytes = s.toArray()
        var i: Int64 = 0
        let n = Int64(bytes.size)
        while (i < n) {
            h = ((h << 5) + h) + UInt64(UInt8(bytes[i]))
            i += 1
        }
        h
    }
}

public class GatewaySessionLocation {
    public let agentId: String
    public let sessionKey: String
    public let root: Path

    public init(agentId: String, sessionKey: String, root: Path) {
        this.agentId = gatewaySanitizeAgentId(agentId)
        this.sessionKey = sessionKey.trimAscii()
        this.root = root
    }
}

public class GatewaySessionCatalogRow {
    public let agentId: String
    public let sessionKey: String
    public let root: Path
    public let sessionId: String
    public let sessionFile: String
    public let updatedAt: Int64
    public let deliverySnapshot: JsonObject
    public let bindingSnapshot: JsonObject
    public let verboseLevel: String
    public let responseUsage: String
    public let fastMode: Bool
    public let sendPolicy: String
    public let lastChannel: String
    public let lastTo: String
    public let lastAccountId: String
    public let lastThreadId: Int64
    public let modelProvider: String
    public let model: String
    public let contextTokens: Int64
    public let totalTokens: Int64
    public let totalTokensFresh: Bool
    public let estimatedCostUsd: Float64
    public let spawnedBy: String
    public let spawnedWorkspaceDir: String
    public let forkedFromParent: Bool
    public let spawnDepth: Int64
    public let subagentRole: String
    public let subagentControlScope: String
    public let parentSessionKey: String
    public let childSessions: Array<String>

    public init(
        agentId: String,
        sessionKey: String,
        root: Path,
        sessionId: String,
        sessionFile: String,
        updatedAt: Int64,
        deliverySnapshot!: JsonObject = JsonObject(),
        bindingSnapshot!: JsonObject = JsonObject(),
        verboseLevel!: String = "",
        responseUsage!: String = "",
        fastMode!: Bool = false,
        sendPolicy!: String = "",
        lastChannel!: String = "",
        lastTo!: String = "",
        lastAccountId!: String = "",
        lastThreadId!: Int64 = 0,
        modelProvider!: String = "",
        model!: String = "",
        contextTokens!: Int64 = 0,
        totalTokens!: Int64 = 0,
        totalTokensFresh!: Bool = false,
        estimatedCostUsd!: Float64 = 0.0,
        spawnedBy!: String = "",
        spawnedWorkspaceDir!: String = "",
        forkedFromParent!: Bool = false,
        spawnDepth!: Int64 = 0,
        subagentRole!: String = "",
        subagentControlScope!: String = "",
        parentSessionKey!: String = "",
        childSessions!: Array<String> = gatewayEmptySessionStringArray()
    ) {
        this.agentId = agentId.trimAscii()
        this.sessionKey = sessionKey.trimAscii()
        this.root = root
        this.sessionId = sessionId.trimAscii()
        this.sessionFile = sessionFile.trimAscii()
        this.updatedAt = updatedAt
        this.deliverySnapshot = deliverySnapshot
        this.bindingSnapshot = bindingSnapshot
        this.verboseLevel = verboseLevel.trimAscii()
        this.responseUsage = responseUsage.trimAscii()
        this.fastMode = fastMode
        this.sendPolicy = sendPolicy.trimAscii()
        this.lastChannel = lastChannel.trimAscii()
        this.lastTo = lastTo.trimAscii()
        this.lastAccountId = lastAccountId.trimAscii()
        this.lastThreadId = lastThreadId
        this.modelProvider = modelProvider.trimAscii()
        this.model = model.trimAscii()
        this.contextTokens = contextTokens
        this.totalTokens = totalTokens
        this.totalTokensFresh = totalTokensFresh
        this.estimatedCostUsd = estimatedCostUsd
        this.spawnedBy = spawnedBy.trimAscii()
        this.spawnedWorkspaceDir = spawnedWorkspaceDir.trimAscii()
        this.forkedFromParent = forkedFromParent
        this.spawnDepth = spawnDepth
        this.subagentRole = subagentRole.trimAscii()
        this.subagentControlScope = subagentControlScope.trimAscii()
        this.parentSessionKey = parentSessionKey.trimAscii()
        this.childSessions = childSessions
    }
}

public class GatewaySessionCatalogView {
    public let row: GatewaySessionCatalogRow
    public let channel: String
    public let chatType: String
    public let peer: String
    public let displayName: String

    public init(
        row: GatewaySessionCatalogRow,
        channel: String,
        chatType: String,
        peer: String,
        displayName: String
    ) {
        this.row = row
        this.channel = channel.trimAscii()
        this.chatType = chatType.trimAscii()
        this.peer = peer.trimAscii()
        this.displayName = displayName.trimAscii()
    }
}

public class GatewaySessionConversationView {
    public let key: String
    public let displayName: String
    public let channel: String
    public let chatType: String
    public let peer: String
    public let agentId: String
    public let sessionId: String
    public let sessionFile: String
    public let root: Path
    public let updatedAt: Int64
    public let origin: JsonObject
    public let delivery: JsonObject
    public let binding: JsonObject

    public init(
        key: String,
        displayName: String,
        channel: String,
        chatType: String,
        peer: String,
        agentId: String,
        sessionId: String,
        sessionFile: String,
        root: Path,
        updatedAt: Int64,
        origin: JsonObject,
        delivery!: JsonObject = JsonObject(),
        binding!: JsonObject = JsonObject()
    ) {
        this.key = key.trimAscii()
        this.displayName = displayName.trimAscii()
        this.channel = channel.trimAscii()
        this.chatType = chatType.trimAscii()
        this.peer = peer.trimAscii()
        this.agentId = agentId.trimAscii()
        this.sessionId = sessionId.trimAscii()
        this.sessionFile = sessionFile.trimAscii()
        this.root = root
        this.updatedAt = updatedAt
        this.origin = origin
        this.delivery = delivery
        this.binding = binding
    }
}

public func gatewayBuildSessionCatalogOrigin(view: GatewaySessionCatalogView): JsonObject {
    let origin = JsonObject()
    let snapshot = view.row.bindingSnapshot
    let snapshotChannel = match (snapshot.get("channel")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let snapshotPeer = match (snapshot.get("peer")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let snapshotAccountId = match (snapshot.get("accountId")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let snapshotConversationId = match (snapshot.get("conversationId")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let normalizedChannel = if (!snapshotChannel.isEmpty()) { snapshotChannel } else { view.channel.trimAscii() }
    let effectivePeer = if (!snapshotConversationId.isEmpty()) {
        snapshotConversationId
    } else if (!snapshotPeer.isEmpty()) {
        snapshotPeer
    } else {
        view.peer
    }
    origin.put("label", JsonString(if (normalizedChannel.isEmpty()) { "local" } else { normalizedChannel }))
    origin.put("provider", JsonString(if (normalizedChannel.isEmpty()) { "local" } else { normalizedChannel }))
    origin.put("surface", JsonString(if (normalizedChannel.isEmpty()) { "cli" } else { normalizedChannel }))
    origin.put("chatType", JsonString(view.chatType))
    if (!snapshotAccountId.isEmpty()) {
        origin.put("accountId", JsonString(snapshotAccountId))
    }
    if (normalizedChannel == "cli") {
        origin.put("from", JsonString("local-user"))
        origin.put("to", JsonString("main"))
    } else if (!normalizedChannel.isEmpty()) {
        origin.put("from", JsonString(normalizedChannel))
        origin.put("to", JsonString(if (effectivePeer.isEmpty()) { normalizedChannel } else { effectivePeer }))
    }
    origin
}

public func gatewayBuildSessionCatalogDelivery(view: GatewaySessionCatalogView): JsonObject {
    let delivery = JsonObject()
    let normalizedChannel = view.channel.trimAscii()
    let normalizedPeer = view.peer.trimAscii()
    delivery.put("channel", JsonString(normalizedChannel))
    delivery.put("peer", JsonString(normalizedPeer))
    delivery.put("replyChannel", JsonString(normalizedChannel))
    delivery.put("replyTo", JsonString(normalizedPeer))
    delivery.put("conversationId", JsonString(if (normalizedPeer.isEmpty()) { "" } else { normalizedPeer }))
    delivery.put("threadId", JsonString(""))
    delivery.put("sourceMessageId", JsonString(""))
    delivery.put("replyToMessageId", JsonString(""))
    delivery.put("replyInThread", false.toJsonValue())
    delivery.put("accountId", JsonString(""))
    delivery.put("deliverable", (!normalizedChannel.isEmpty()).toJsonValue())
    delivery.put("mode", JsonString(if (normalizedPeer.isEmpty()) { "session-default" } else { "peer-target" }))
    let snapshot = view.row.deliverySnapshot
    if (snapshot.size() > 0) {
        delivery.put("channel", snapshot.get("channel") ?? delivery.get("channel").getOrThrow())
        delivery.put("peer", snapshot.get("peer") ?? delivery.get("peer").getOrThrow())
        delivery.put("replyChannel", snapshot.get("channel") ?? delivery.get("replyChannel").getOrThrow())
        delivery.put("replyTo", snapshot.get("peer") ?? delivery.get("replyTo").getOrThrow())
        delivery.put("conversationId", snapshot.get("conversationId") ?? delivery.get("conversationId").getOrThrow())
        delivery.put("threadId", snapshot.get("threadId") ?? delivery.get("threadId").getOrThrow())
        delivery.put("sourceMessageId", snapshot.get("sourceMessageId") ?? delivery.get("sourceMessageId").getOrThrow())
        delivery.put("replyToMessageId", snapshot.get("replyToMessageId") ?? delivery.get("replyToMessageId").getOrThrow())
        delivery.put("replyInThread", snapshot.get("replyInThread") ?? delivery.get("replyInThread").getOrThrow())
        delivery.put("accountId", snapshot.get("accountId") ?? delivery.get("accountId").getOrThrow())
        delivery.put("deliverable", snapshot.get("deliverable") ?? delivery.get("deliverable").getOrThrow())
        delivery.put("mode", snapshot.get("mode") ?? JsonString("binding-snapshot"))
    }
    delivery
}

public func gatewayBuildSessionCatalogBinding(view: GatewaySessionCatalogView): JsonObject {
    let binding = JsonObject()
    let delivery = gatewayBuildSessionCatalogDelivery(view)
    binding.put("channel", JsonString(view.channel))
    binding.put("peer", JsonString(view.peer))
    binding.put("accountId", delivery.get("accountId") ?? JsonString(""))
    binding.put("conversationId", delivery.get("conversationId") ?? JsonString(""))
    binding.put("threadId", delivery.get("threadId") ?? JsonString(""))
    binding.put("sourceMessageId", delivery.get("sourceMessageId") ?? JsonString(""))
    binding.put("replyTargetMessageId", delivery.get("replyToMessageId") ?? JsonString(""))
    binding.put("replyInThread", delivery.get("replyInThread") ?? false.toJsonValue())
    binding.put("mode", JsonString("session-projection"))
    let snapshot = view.row.bindingSnapshot
    if (snapshot.size() > 0) {
        binding.put("channel", snapshot.get("channel") ?? binding.get("channel").getOrThrow())
        binding.put("peer", snapshot.get("peer") ?? binding.get("peer").getOrThrow())
        binding.put("accountId", snapshot.get("accountId") ?? binding.get("accountId").getOrThrow())
        binding.put("conversationId", snapshot.get("conversationId") ?? binding.get("conversationId").getOrThrow())
        binding.put("threadId", snapshot.get("threadId") ?? binding.get("threadId").getOrThrow())
        binding.put("sourceMessageId", snapshot.get("sourceMessageId") ?? binding.get("sourceMessageId").getOrThrow())
        binding.put("replyTargetMessageId", snapshot.get("replyTargetMessageId") ?? binding.get("replyTargetMessageId").getOrThrow())
        binding.put("replyInThread", snapshot.get("replyInThread") ?? binding.get("replyInThread").getOrThrow())
        binding.put("mode", snapshot.get("mode") ?? JsonString("binding-snapshot"))
    }
    binding
}

public func gatewayBuildSessionConversationView(view: GatewaySessionCatalogView): GatewaySessionConversationView {
    let delivery = gatewayBuildSessionCatalogDelivery(view)
    GatewaySessionConversationView(
        view.row.sessionKey,
        view.displayName,
        view.channel,
        view.chatType,
        view.peer,
        view.row.agentId,
        view.row.sessionId,
        view.row.sessionFile,
        view.row.root,
        view.row.updatedAt,
        gatewayBuildSessionCatalogOrigin(view),
        delivery: delivery,
        binding: gatewayBuildSessionCatalogBinding(view)
    )
}

/** 规范化 agentId，用作路径分量（与 `agents/<id>` 布局一致）。 */
public func gatewaySanitizeAgentId(raw: String): String {
    var s = raw.trimAscii().replace("/", "_").replace("\\", "_").replace("..", "_").replace(":", "_")
    if (s.isEmpty()) {
        return "main"
    }
    s
}

/** `~/.metis/agents/<agentId>/sessions` */
public func gatewayPersistedSessionsRootForUser(user: GatewayUserSettings): Path {
    let id = gatewaySanitizeAgentId(user.session.agentId)
    CliConfig.dotDir.join("agents").join(id).join("sessions")
}

private func gatewayListPersistedAgentIdsInternal(defaultAgentId: String): Array<String> {
    let out = ArrayList<String>()
    let seen = ArrayList<String>()
    let normalizedDefault = gatewaySanitizeAgentId(defaultAgentId)
    out.add(normalizedDefault)
    seen.add(normalizedDefault)
    let agentsRoot = CliConfig.dotDir.join("agents")
    if (!exists(agentsRoot)) {
        return out.toArray()
    }
    try {
        for (entry in Directory.readFrom(agentsRoot)) {
            if (!entry.isDirectory()) {
                continue
            }
            let agentId = gatewaySanitizeAgentId(entry.name)
            var present = false
            for (existing in seen) {
                if (existing == agentId) {
                    present = true
                    break
                }
            }
            if (present) {
                continue
            }
            out.add(agentId)
            seen.add(agentId)
        }
    } catch (_: Exception) {
        ()
    }
    out.toArray()
}

public func gatewayListPersistedAgentIdsForUser(user: GatewayUserSettings): Array<String> {
    gatewayListPersistedAgentIdsInternal(user.session.agentId)
}

public func gatewayListSessionLocationsForUser(user: GatewayUserSettings): Array<GatewaySessionLocation> {
    let out = ArrayList<GatewaySessionLocation>()
    for (agentId in gatewayListPersistedAgentIdsForUser(user)) {
        let store = gatewaySessionStoreForUserWithAgentId(user, agentId)
        for (sessionKey in store.listSessionKeys()) {
            out.add(GatewaySessionLocation(agentId, sessionKey, store.sessionsRoot()))
        }
    }
    out.toArray()
}

public func gatewayFindSessionLocationForUser(user: GatewayUserSettings, sessionKey: String): Option<GatewaySessionLocation> {
    let normalized = sessionKey.trimAscii()
    if (normalized.isEmpty()) {
        return None
    }
    for (entry in gatewayListSessionLocationsForUser(user)) {
        if (entry.sessionKey == normalized) {
            return Some(entry)
        }
    }
    None
}

private func gatewaySessionTranscriptMtimeMillis(store: GatewaySessionStore, sessionKey: String): Int64 {
    let p = store.transcriptPath(sessionKey)
    if (!exists(p)) {
        return 0
    }
    try {
        FileInfo(p).lastModificationTime.toUnixTimeStamp().toMilliseconds()
    } catch (_: Exception) {
        0
    }
}

private func gatewaySessionIdFromTranscriptFileName(fileName: String): String {
    let normalized = fileName.trimAscii()
    if (normalized.size > 6 && normalized.endsWith(".jsonl")) {
        return normalized[0..normalized.size - 6]
    }
    normalized
}

private func gatewaySessionCatalogChannel(sessionKey: String): String {
    let normalized = sessionKey.trimAscii()
    if (normalized.startsWith("agent:")) {
        return "agent"
    }
    if (normalized.startsWith("qq:")) {
        return "qq"
    }
    if (normalized.startsWith("feishu:")) {
        return "feishu"
    }
    if (normalized.startsWith("cli:")) {
        return "cli"
    }
    ""
}

private func gatewaySessionCatalogChatType(sessionKey: String): String {
    let normalized = sessionKey.trimAscii()
    if (normalized.startsWith("agent:")) {
        return "direct"
    }
    if (normalized.contains(":group:")) {
        return "group"
    }
    if (normalized.contains(":direct:") || normalized.startsWith("cli:")) {
        return "direct"
    }
    ""
}

private func gatewaySessionCatalogPeer(sessionKey: String): String {
    let normalized = sessionKey.trimAscii()
    if (normalized.startsWith("agent:")) {
        let parts = normalized.split(":")
        if (parts.size >= 3) {
            return parts[parts.size - 1].trimAscii()
        }
    }
    let groupMarker = ":group:"
    let directMarker = ":direct:"
    match (normalized.indexOf(groupMarker)) {
        case Some(groupIdx) => return normalized[(groupIdx + groupMarker.size)..normalized.size]
        case None => ()
    }
    match (normalized.indexOf(directMarker)) {
        case Some(directIdx) => return normalized[(directIdx + directMarker.size)..normalized.size]
        case None => ()
    }
    if (normalized.startsWith("cli:")) {
        return "main"
    }
    ""
}

public func gatewayProjectSessionCatalogRow(row: GatewaySessionCatalogRow): GatewaySessionCatalogView {
    let snapshot = row.bindingSnapshot
    let snapshotChannel = match (snapshot.get("channel")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let snapshotPeer = match (snapshot.get("peer")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let snapshotConversationId = match (snapshot.get("conversationId")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let channel = if (!snapshotChannel.isEmpty()) { snapshotChannel } else { gatewaySessionCatalogChannel(row.sessionKey) }
    let chatType = gatewaySessionCatalogChatType(row.sessionKey)
    let peer = if (!snapshotPeer.isEmpty()) {
        snapshotPeer
    } else if (!snapshotConversationId.isEmpty()) {
        snapshotConversationId
    } else {
        gatewaySessionCatalogPeer(row.sessionKey)
    }
    let displayName = if (!peer.isEmpty() && channel != "cli") {
        peer
    } else if (channel == "cli") {
        "CLI"
    } else {
        row.sessionKey
    }
    GatewaySessionCatalogView(row, channel, chatType, peer, displayName)
}

public func gatewayListSessionCatalogRowsForUser(user: GatewayUserSettings): Array<GatewaySessionCatalogRow> {
    let out = ArrayList<GatewaySessionCatalogRow>()
    for (entry in gatewayListSessionLocationsForUser(user)) {
        let store = gatewaySessionStoreForUserWithAgentId(user, entry.agentId)
        let indexRoot = store.readSessionsIndexRoot()
        let transcriptPath = store.transcriptPath(entry.sessionKey)
        let sessionFile = transcriptPath.fileName
        let bindingSnapshot = store.readLatestBindingSnapshot(entry.sessionKey)
        let indexEntry = match (indexRoot.get(entry.sessionKey)) {
            case Some(v) =>
                try { v.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        out.add(
            GatewaySessionCatalogRow(
                entry.agentId,
                entry.sessionKey,
                entry.root,
                gatewaySessionIdFromTranscriptFileName(sessionFile),
                sessionFile,
                gatewaySessionTranscriptMtimeMillis(store, entry.sessionKey),
                deliverySnapshot: bindingSnapshot,
                bindingSnapshot: bindingSnapshot,
                verboseLevel: GatewaySessionStore.sessionIndexString(indexEntry, "verboseLevel"),
                responseUsage: GatewaySessionStore.sessionIndexString(indexEntry, "responseUsage"),
                fastMode: GatewaySessionStore.sessionIndexBool(indexEntry, "fastMode"),
                sendPolicy: GatewaySessionStore.sessionIndexString(indexEntry, "sendPolicy"),
                lastChannel: GatewaySessionStore.sessionIndexString(indexEntry, "lastChannel"),
                lastTo: GatewaySessionStore.sessionIndexString(indexEntry, "lastTo"),
                lastAccountId: GatewaySessionStore.sessionIndexString(indexEntry, "lastAccountId"),
                lastThreadId: GatewaySessionStore.sessionIndexInt(indexEntry, "lastThreadId"),
                modelProvider: GatewaySessionStore.sessionIndexString(indexEntry, "modelProvider"),
                model: GatewaySessionStore.sessionIndexString(indexEntry, "model"),
                contextTokens: GatewaySessionStore.sessionIndexInt(indexEntry, "contextTokens"),
                totalTokens: GatewaySessionStore.sessionIndexInt(indexEntry, "totalTokens"),
                totalTokensFresh: GatewaySessionStore.sessionIndexBool(indexEntry, "totalTokensFresh"),
                estimatedCostUsd: GatewaySessionStore.sessionIndexFloat(indexEntry, "estimatedCostUsd"),
                spawnedBy: GatewaySessionStore.sessionIndexString(indexEntry, "spawnedBy"),
                spawnedWorkspaceDir: GatewaySessionStore.sessionIndexString(indexEntry, "spawnedWorkspaceDir"),
                forkedFromParent: GatewaySessionStore.sessionIndexBool(indexEntry, "forkedFromParent"),
                spawnDepth: GatewaySessionStore.sessionIndexInt(indexEntry, "spawnDepth"),
                subagentRole: GatewaySessionStore.sessionIndexString(indexEntry, "subagentRole"),
                subagentControlScope: GatewaySessionStore.sessionIndexString(indexEntry, "subagentControlScope"),
                parentSessionKey: GatewaySessionStore.sessionIndexString(indexEntry, "parentSessionKey"),
                childSessions: GatewaySessionStore.sessionIndexStringArray(indexEntry, "childSessions")
            )
        )
    }
    let rows = out.toArray()
    sort(rows, by: { a, b => b.updatedAt.compare(a.updatedAt) }, stable: true)
    rows
}

public func gatewayListSessionCatalogViewsForUser(user: GatewayUserSettings): Array<GatewaySessionCatalogView> {
    let out = ArrayList<GatewaySessionCatalogView>()
    for (row in gatewayListSessionCatalogRowsForUser(user)) {
        out.add(gatewayProjectSessionCatalogRow(row))
    }
    out.toArray()
}

public func gatewayListSessionConversationViewsForUser(user: GatewayUserSettings): Array<GatewaySessionConversationView> {
    let out = ArrayList<GatewaySessionConversationView>()
    for (view in gatewayListSessionCatalogViewsForUser(user)) {
        out.add(gatewayBuildSessionConversationView(view))
    }
    out.toArray()
}

public func gatewayFindSessionCatalogViewForUser(
    user: GatewayUserSettings,
    sessionKey: String
): Option<GatewaySessionCatalogView> {
    let normalized = sessionKey.trimAscii()
    if (normalized.isEmpty()) {
        return None
    }
    for (view in gatewayListSessionCatalogViewsForUser(user)) {
        if (view.row.sessionKey == normalized) {
            return Some(view)
        }
    }
    None
}

public func gatewayFindSessionConversationViewForUser(
    user: GatewayUserSettings,
    sessionKey: String
): Option<GatewaySessionConversationView> {
    let normalized = sessionKey.trimAscii()
    if (normalized.isEmpty()) {
        return None
    }
    for (view in gatewayListSessionConversationViewsForUser(user)) {
        if (view.key == normalized) {
            return Some(view)
        }
    }
    None
}

public func gatewayFindSessionCatalogRowForUser(
    user: GatewayUserSettings,
    sessionKey: String
): Option<GatewaySessionCatalogRow> {
    let normalized = sessionKey.trimAscii()
    if (normalized.isEmpty()) {
        return None
    }
    for (row in gatewayListSessionCatalogRowsForUser(user)) {
        if (row.sessionKey == normalized) {
            return Some(row)
        }
    }
    None
}

/**
 * 若新目录尚无 `.jsonl` 转录，则从旧版 `gateway-sessions` 目录复制（不删除旧数据）。
 */
public func gatewayMigrateLegacyGatewaySessionsIfNeeded(newRoot: Path): Unit {
    var newHasJsonl = false
    if (exists(newRoot)) {
        try {
            for (entry in Directory.readFrom(newRoot)) {
                if (entry.isRegular() && entry.name.endsWith(".jsonl")) {
                    newHasJsonl = true
                    break
                }
            }
        } catch (_: Exception) {
            ()
        }
    }
    if (newHasJsonl) {
        return
    }
    let legacy = CliConfig.dotDir.join("gateway-sessions")
    if (!exists(legacy)) {
        if (!exists(newRoot)) {
            try {
                Directory.create(newRoot, recursive: true)
            } catch (_: Exception) {
                ()
            }
        }
        return
    }
    try {
        Directory.create(newRoot, recursive: true)
        for (entry in Directory.readFrom(legacy)) {
            if (!entry.isRegular() || !entry.name.endsWith(".jsonl")) {
                continue
            }
            let from = legacy.join(entry.name)
            let to = newRoot.join(entry.name)
            if (exists(to)) {
                continue
            }
            copy(from, to: to, overwrite: false)
        }
    } catch (e: Exception) {
        LogUtils.info("gatewayMigrateLegacyGatewaySessionsIfNeeded: ${e.message}")
    }
}

/**
 * 按当前网关用户配置构造会话存储（含迁移、`sessions.json` 维护）。
 */
public func gatewaySessionStoreForUser(user: GatewayUserSettings): GatewaySessionStore {
    let root = gatewayPersistedSessionsRootForUser(user)
    gatewayMigrateLegacyGatewaySessionsIfNeeded(root)
    let id = gatewaySanitizeAgentId(user.session.agentId)
    GatewaySessionStore(root, enabled: user.session.persistenceEnabled, agentId: id)
}

/**
 * 与 `gatewaySessionStoreForUser` 相同，但允许按调用时的 agentId 覆盖会话根目录。
 * 这对应 `agents/<agentId>/sessions` 语义：CLI `agent --agent <id>`
 * 不再把所有转录都写到固定的 `gateway.session.agentId` 目录里。
 */
public func gatewaySessionStoreForUserWithAgentId(user: GatewayUserSettings, agentIdOverride: String): GatewaySessionStore {
    let resolvedAgentId = if (agentIdOverride.trimAscii().isEmpty()) {
        user.session.agentId
    } else {
        agentIdOverride.trimAscii()
    }
    let id = gatewaySanitizeAgentId(resolvedAgentId)
    let root = CliConfig.dotDir.join("agents").join(id).join("sessions")
    gatewayMigrateLegacyGatewaySessionsIfNeeded(root)
    GatewaySessionStore(root, enabled: user.session.persistenceEnabled, agentId: id)
}

public func gatewaySessionStoreForResolvedRequest(user: GatewayUserSettings, request: GatewaySessionRequest): GatewaySessionStore {
    let context = gatewayResolveSessionContext(request)
    match (gatewayFindSessionLocationForUser(user, context.sessionKey)) {
        case Some(location) => gatewaySessionStoreForUserWithAgentId(user, location.agentId)
        case None => gatewaySessionStoreForUserWithAgentId(user, context.agentId)
    }
}

public func gatewaySessionStoreForSessionKey(
    user: GatewayUserSettings,
    sessionKey: String,
    agentId!: String = ""
): GatewaySessionStore {
    let params = JsonObject()
    params.put("session", JsonString(sessionKey.trimAscii()))
    params.put("agentId", JsonString(agentId.trimAscii()))
    gatewaySessionStoreForResolvedRequest(
        user,
        gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc)
    )
}
