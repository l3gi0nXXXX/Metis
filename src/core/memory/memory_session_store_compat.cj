package metis.core.memory

import magic.log.LogUtils

import metis.core.config.{CliConfig, GatewayUserSettings}

import std.collection.ArrayList
import std.fs.{Path, File, Directory, FileInfo, exists, remove, OpenMode, copy, FSException}
import std.time.DateTime

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

public func memorySanitizeGatewayAgentId(raw: String): String {
    var s = raw.trimAscii().replace("/", "_").replace("\\", "_").replace("..", "_").replace(":", "_")
    if (s.isEmpty()) {
        return "main"
    }
    s
}

public func memoryGatewaySessionsRootForUser(user: GatewayUserSettings): Path {
    let id = memorySanitizeGatewayAgentId(user.session.agentId)
    CliConfig.dotDir.join("agents").join(id).join("sessions")
}

public func memoryMigrateLegacyGatewaySessionsIfNeeded(newRoot: Path): Unit {
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
        LogUtils.info("memoryMigrateLegacyGatewaySessionsIfNeeded: ${e.message}")
    }
}

public class MemorySessionTranscriptStore {
    private let root: Path
    private let enabled: Bool

    public init(rootDir: Path, enabled!: Bool = true) {
        this.root = rootDir
        this.enabled = enabled
    }

    public func sessionsRoot(): Path {
        this.root
    }

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
        this.root.join("${MemorySessionTranscriptStore.fileStemForSessionKey(sessionKey)}.jsonl")
    }

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
            key
        } catch (e: Exception) {
            "error:${e.message}"
        }
    }

    public func appendTranscriptEntry(sessionKey: String, role: String, text: String): Unit {
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
            LogUtils.error("MemorySessionTranscriptStore.appendTranscriptEntry failed (sessionKey=${sessionKey}, role=${role}): ${e.message}")
        }
    }

    public func listSessionKeys(): Array<String> {
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
        } catch (_: Exception) {
            ()
        }
        out.toArray()
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
        } catch (_: Exception) {
            None
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
            true
        } catch (_: FSException) {
            false
        }
    }

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

    private static func parseJsonlTextToObjects(text: String): ArrayList<JsonObject> {
        let objs = ArrayList<JsonObject>()
        let lines = text.split("\n")
        var buffer = ""
        for (line in lines) {
            if (buffer.isEmpty() && line.trimAscii().isEmpty()) {
                continue
            }
            buffer = if (buffer.isEmpty()) { line } else { buffer + "\n" + line }
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
        } catch (_: Exception) {
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

public func memorySessionStoreForGatewayUser(user: GatewayUserSettings): MemorySessionTranscriptStore {
    let root = memoryGatewaySessionsRootForUser(user)
    memoryMigrateLegacyGatewaySessionsIfNeeded(root)
    MemorySessionTranscriptStore(root, enabled: user.session.persistenceEnabled)
}
