package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings}
import metis.core.skills.skillsResolvedRoots
import metis.gateway.core.{GatewaySessionCatalogView, GatewaySessionConversationView, GatewaySessionStore, gatewayFindSessionCatalogViewForUser, gatewayFindSessionConversationViewForUser, gatewayFindSessionLocationForUser, gatewaySessionStoreForSessionKey, gatewaySessionStoreForUserWithAgentId}

import std.collection.{ArrayList, HashSet}
import std.fs.{Directory, File, exists, Path}
import stdx.encoding.json.{JsonObject, JsonValue}

public func gatewayControlUiServeRunningNow(): Bool {
    exists(CliConfig.dotDir.join("gateway-serve.lock"))
}

private func gatewayControlUiSummarizeRawTranscript(raw: String): (Int64, Int64, String, String) {
    let objs = gatewayControlUiParseJsonObjectsFromRaw(raw)
    var msgCount: Int64 = 0
    var tokenApprox: Int64 = 0
    var updatedTs = ""
    var lastRole = ""
    for (o in objs) {
        let kind = match (o.get("kind")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        if (kind == "meta") {
            continue
        }
        let role = match (o.get("role")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        let text = match (o.get("text")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        let ts = match (o.get("ts")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        if (!role.isEmpty() || !text.isEmpty()) {
            msgCount += 1
        }
        if (!text.isEmpty()) {
            tokenApprox += max(1, text.size / 4)
        }
        if (!ts.isEmpty()) {
            updatedTs = ts
        }
        if (!role.isEmpty()) {
            lastRole = role
        }
    }
    (msgCount, tokenApprox, updatedTs, lastRole)
}

public func gatewayControlUiSummarizeConversation(view: GatewaySessionConversationView): (Int64, Int64, String, String) {
    let store = GatewaySessionStore(view.root)
    if (let Some(raw) <- store.readTranscriptRaw(view.key)) {
        return gatewayControlUiSummarizeRawTranscript(raw)
    }
    (0, 0, "", "")
}

public func gatewayControlUiSummarizeSession(sessionKey: String): (Int64, Int64, String, String) {
    let user = CliSettingManager.readGatewaySettings()
    match (gatewayFindSessionConversationViewForUser(user, sessionKey)) {
        case Some(view) => return gatewayControlUiSummarizeConversation(view)
        case None => ()
    }
    let store = gatewaySessionStoreForSessionKey(user, sessionKey)
    if (let Some(raw) <- store.readTranscriptRaw(sessionKey)) {
        return gatewayControlUiSummarizeRawTranscript(raw)
    }
    (0, 0, "", "")
}

public func gatewayControlUiParseJsonObjectsFromRaw(raw: String): ArrayList<JsonObject> {
    let out = ArrayList<JsonObject>()
    let lines = raw.split("\n")
    var buffer = ""
    for (line in lines) {
        if (buffer.isEmpty() && line.trimAscii().isEmpty()) {
            continue
        }
        buffer = if (buffer.isEmpty()) { line } else { buffer + "\n" + line }
        let cand = buffer.trimAscii()
        try {
            out.add(JsonValue.fromStr(cand).asObject())
            buffer = ""
        } catch (_e: Exception) {
            ()
        }
    }
    out
}

public func gatewayControlUiDiscoverSkills(): ArrayList<Array<String>> {
    let out = ArrayList<Array<String>>()
    let seen = HashSet<String>()
    let st = CliSettingManager.setting.skills
    for ((_, root) in skillsResolvedRoots(st)) {
        if (!exists(root)) {
            continue
        }
        try {
            for (info in Directory.readFrom(root)) {
                if (!info.isDirectory()) { continue }
                let md = info.path.join("SKILL.md")
                if (!exists(md)) { continue }
                let (name, desc) = gatewayControlUiParseSkillMeta(md, info.name)
                let nm = name.trimAscii()
                if (nm.isEmpty() || seen.contains(nm)) { continue }
                seen.add(nm)
                out.add([nm, desc.trimAscii()])
            }
        } catch (_e: Exception) {
            ()
        }
    }
    out
}

public func gatewayControlUiParseSkillMeta(path: Path, fallbackName: String): (String, String) {
    try {
        let content = String.fromUtf8(File.readFrom(path))
        let lines = content.split("\n")
        if (lines.size == 0 || lines[0].trimAscii() != "---") {
            return (fallbackName, "")
        }
        var endIdx: Int64 = -1
        var i: Int64 = 1
        while (i < lines.size) {
            if (lines[i].trimAscii() == "---") {
                endIdx = i
                break
            }
            i += 1
        }
        if (endIdx < 0) {
            return (fallbackName, "")
        }
        var name = fallbackName
        var desc = ""
        var j: Int64 = 1
        while (j < endIdx) {
            let line = lines[j]
            match (line.indexOf(":")) {
                case Some(colon) =>
                    let k = line[0..colon].trimAscii().toAsciiLower()
                    let v = line[colon + 1..line.size].trimAscii().replace("\"", "").replace("'", "")
                    if (k == "name" && !v.isEmpty()) {
                        name = v
                    } else if (k == "description" && !v.isEmpty()) {
                        desc = v
                    }
                case None => ()
            }
            j += 1
        }
        (name, desc)
    } catch (_e: Exception) {
        (fallbackName, "")
    }
}

public func gatewayControlUiPickLast(items: Array<String>, n: Int64): Array<String> {
    if (n <= 0 || items.isEmpty()) {
        return []
    }
    if (items.size <= n) {
        return items
    }
    let start = items.size - n
    items[start..items.size]
}

public func gatewayControlUiPickLastSessionViews(items: Array<GatewaySessionCatalogView>, n: Int64): Array<GatewaySessionCatalogView> {
    if (n <= 0 || items.isEmpty()) {
        return []
    }
    if (items.size <= n) {
        return items
    }
    let start = items.size - n
    items[start..items.size]
}

public func gatewayControlUiPickLastConversationViews(items: Array<GatewaySessionConversationView>, n: Int64): Array<GatewaySessionConversationView> {
    if (n <= 0 || items.isEmpty()) {
        return []
    }
    if (items.size <= n) {
        return items
    }
    let start = items.size - n
    items[start..items.size]
}

public func gatewayControlUiBuildRecentMessagesResolved(user: GatewayUserSettings, sessions: Array<String>, maxLines: Int64): Array<String> {
    let views = ArrayList<GatewaySessionConversationView>()
    let unresolved = ArrayList<String>()
    for (k in sessions) {
        match (gatewayFindSessionConversationViewForUser(user, k)) {
            case Some(view) => views.add(view)
            case None => unresolved.add(k)
        }
    }
    if (unresolved.isEmpty()) {
        return gatewayControlUiBuildRecentMessagesForConversations(user, views.toArray(), maxLines)
    }
    let out = ArrayList<String>()
    if (views.size > 0) {
        for (line in gatewayControlUiBuildRecentMessagesForConversations(user, views.toArray(), maxLines)) {
            out.add(line)
        }
    }
    for (k in unresolved) {
        let store = match (gatewayFindSessionLocationForUser(user, k)) {
            case Some(location) => GatewaySessionStore(location.root)
            case None => gatewaySessionStoreForSessionKey(user, k)
        }
        let label = match (gatewayFindSessionCatalogViewForUser(user, k)) {
            case Some(view) => view.displayName
            case None => k
        }
        if (let Some(raw) <- store.readTranscriptRaw(k)) {
            let lines = raw.split("\n")
            for (line in lines) {
                let t = line.trimAscii()
                if (t.isEmpty()) {
                    continue
                }
                try {
                    let o = JsonValue.fromStr(t).asObject()
                    if (let Some(kind) <- o.get("kind")) {
                        if (kind.asString().getValue() == "meta") {
                            continue
                        }
                    }
                    let role = match (o.get("role")) {
                        case Some(v) => v.asString().getValue()
                        case None => ""
                    }
                    let text = match (o.get("text")) {
                        case Some(v) => v.asString().getValue()
                        case None => ""
                    }
                    if (!role.isEmpty() && !text.isEmpty()) {
                        out.add("${label} [${role}] ${text}")
                    }
                } catch (_e: Exception) {
                    ()
                }
            }
        }
    }
    gatewayControlUiPickLast(out.toArray(), maxLines)
}

public func gatewayControlUiBuildRecentMessagesForConversations(
    user: GatewayUserSettings,
    sessions: Array<GatewaySessionConversationView>,
    maxLines: Int64
): Array<String> {
    let out = ArrayList<String>()
    for (entry in sessions) {
        let store = GatewaySessionStore(entry.root)
        let label = if (!entry.displayName.isEmpty()) { entry.displayName } else { entry.key }
        if (let Some(raw) <- store.readTranscriptRaw(entry.key)) {
            let lines = raw.split("\n")
            for (line in lines) {
                let t = line.trimAscii()
                if (t.isEmpty()) {
                    continue
                }
                try {
                    let o = JsonValue.fromStr(t).asObject()
                    if (let Some(kind) <- o.get("kind")) {
                        if (kind.asString().getValue() == "meta") {
                            continue
                        }
                    }
                    let role = match (o.get("role")) {
                        case Some(v) => v.asString().getValue()
                        case None => ""
                    }
                    let text = match (o.get("text")) {
                        case Some(v) => v.asString().getValue()
                        case None => ""
                    }
                    if (!role.isEmpty() && !text.isEmpty()) {
                        out.add("${label} [${role}] ${text}")
                    }
                } catch (_e: Exception) {
                    ()
                }
            }
        }
    }
    gatewayControlUiPickLast(out.toArray(), maxLines)
}

public func gatewayControlUiReadLatestLogTail(maxLines: Int64): (String, Array<String>) {
    let dir = CliConfig.logsDir
    if (!exists(dir)) {
        return ("", [])
    }
    var latestName = ""
    try {
        for (entry in Directory.readFrom(dir)) {
            if (!entry.isRegular()) {
                continue
            }
            let n = entry.name
            if (!n.endsWith(".log")) {
                continue
            }
            if (latestName.isEmpty() || n > latestName) {
                latestName = n
            }
        }
    } catch (_e: Exception) {
        return ("", [])
    }
    if (latestName.isEmpty()) {
        return ("", [])
    }
    let p = dir.join(latestName)
    try {
        let text = String.fromUtf8(File.readFrom(p))
        let lines = text.split("\n")
        return (latestName, gatewayControlUiPickLast(lines, maxLines))
    } catch (_e: Exception) {
        return (latestName, [])
    }
}

public func gatewayControlUiJsonEscape(raw: String): String {
    raw
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}

public func gatewayControlUiMaskSecret(s: String): String {
    let t = s.trimAscii()
    if (t.isEmpty()) {
        return "—"
    }
    "••••••••"
}

public func gatewayControlUiAppendGatewayChannelsJson(sb: StringBuilder, gw: GatewayUserSettings): Unit {
    sb.append("\"channels\":[")
    var first = true
    var fsModel = ""
    var qqModel = ""
    for ((ck, cv) in gw.channelModels) {
        let kk = ck.trimAscii()
        if (kk == "feishu") {
            fsModel = cv
        }
        if (kk == "qq") {
            qqModel = cv
        }
    }
    if (!first) {
        sb.append(",")
    }
    first = false
    sb.append("{")
    sb.append("\"id\":\"feishu\",")
    sb.append("\"title\":\"Feishu\",")
    sb.append("\"subtitle\":\"飞书\",")
    sb.append("\"description\":\"飞书开放平台：长连接 / Webhook 事件、机器人消息。\",")
    sb.append("\"enabled\":${gw.feishu.enabled},")
    sb.append("\"boundModel\":\"${gatewayControlUiJsonEscape(fsModel)}\",")
    sb.append("\"tags\":[\"network\",\"channels\"],")
    sb.append("\"rows\":[")
    sb.append("{\"label\":\"App ID\",\"value\":\"${gatewayControlUiJsonEscape(gw.feishu.appId)}\"},")
    sb.append("{\"label\":\"App Secret\",\"value\":\"${gatewayControlUiJsonEscape(gatewayControlUiMaskSecret(gw.feishu.appSecret))}\"},")
    sb.append("{\"label\":\"Receive mode\",\"value\":\"${gatewayControlUiJsonEscape(gw.feishu.receiveMode)}\"},")
    sb.append("{\"label\":\"Domain\",\"value\":\"${gatewayControlUiJsonEscape(gw.feishu.domain)}\"},")
    sb.append("{\"label\":\"Bot Open ID\",\"value\":\"${gatewayControlUiJsonEscape(gw.feishu.botOpenId)}\"},")
    let feishuWh = "${gw.feishu.webhookHost}:${gw.feishu.webhookPort}${gw.feishu.webhookPath}"
    sb.append("{\"label\":\"Webhook\",\"value\":\"${gatewayControlUiJsonEscape(feishuWh)}\"},")
    sb.append("{\"label\":\"Verification token\",\"value\":\"${gatewayControlUiJsonEscape(gatewayControlUiMaskSecret(gw.feishu.verificationToken))}\"},")
    sb.append("{\"label\":\"Encrypt key\",\"value\":\"${gatewayControlUiJsonEscape(gatewayControlUiMaskSecret(gw.feishu.encryptKey))}\"},")
    sb.append("{\"label\":\"Group session scope\",\"value\":\"${gatewayControlUiJsonEscape(gw.feishu.groupSessionScope)}\"},")
    sb.append("{\"label\":\"Reply in thread\",\"value\":\"${gatewayControlUiJsonEscape(gw.feishu.replyInThread)}\"},")
    let feishuReqSig = "${gw.feishu.requireSignatureHeaders}"
    let feishuSkew = "${gw.feishu.requestMaxSkewSeconds}"
    sb.append("{\"label\":\"Require signature headers\",\"value\":\"${gatewayControlUiJsonEscape(feishuReqSig)}\"},")
    sb.append("{\"label\":\"Request max skew (s)\",\"value\":\"${gatewayControlUiJsonEscape(feishuSkew)}\"}")
    sb.append("]")
    sb.append("}")
    sb.append(",")
    sb.append("{")
    sb.append("\"id\":\"qq\",")
    sb.append("\"title\":\"QQ\",")
    sb.append("\"subtitle\":\"QQ\",")
    sb.append("\"description\":\"QQ official bot over WebSocket gateway.\",")
    sb.append("\"enabled\":${gw.qq.enabled},")
    sb.append("\"boundModel\":\"${gatewayControlUiJsonEscape(qqModel)}\",")
    sb.append("\"tags\":[\"network\",\"channels\"],")
    sb.append("\"rows\":[")
    sb.append("{\"label\":\"Mode\",\"value\":\"${gatewayControlUiJsonEscape(gw.qq.mode)}\"},")
    sb.append("{\"label\":\"Bot QQ\",\"value\":\"${gatewayControlUiJsonEscape(gw.qq.botQQ)}\"},")
    sb.append("{\"label\":\"App ID\",\"value\":\"${gatewayControlUiJsonEscape(gw.qq.appId)}\"},")
    sb.append("{\"label\":\"App Secret\",\"value\":\"${gatewayControlUiJsonEscape(gatewayControlUiMaskSecret(gw.qq.appSecret))}\"},")
    let qqIntents = "${gw.qq.officialIntents}"
    let qqDedup = "${gw.qq.dedupWindowSize}"
    sb.append("{\"label\":\"Official intents\",\"value\":\"${gatewayControlUiJsonEscape(qqIntents)}\"},")
    sb.append("{\"label\":\"Dedup cache size\",\"value\":\"${gatewayControlUiJsonEscape(qqDedup)}\"}")
    sb.append("]")
    sb.append("}")
    for (p in gw.gatewayPlugins) {
        let pid = p.id.trimAscii()
        if (pid.isEmpty()) {
            continue
        }
        sb.append(",")
        sb.append("{")
        sb.append("\"id\":\"${gatewayControlUiJsonEscape(pid)}\",")
        sb.append("\"title\":\"${gatewayControlUiJsonEscape(pid)}\",")
        sb.append("\"subtitle\":\"Plugin\",")
        sb.append("\"description\":\"网关扩展渠道插件（gatewayPlugins）。\",")
        sb.append("\"enabled\":${p.enabled},")
        sb.append("\"boundModel\":\"\",")
        sb.append("\"tags\":[\"plugin\",\"channels\"],")
        sb.append("\"rows\":[")
        sb.append("{\"label\":\"Plugin ID\",\"value\":\"${gatewayControlUiJsonEscape(pid)}\"},")
        let pluginEn = "${p.enabled}"
        sb.append("{\"label\":\"Enabled\",\"value\":\"${gatewayControlUiJsonEscape(pluginEn)}\"}")
        sb.append("]")
        sb.append("}")
    }
    sb.append("],")
}
