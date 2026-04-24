package metis.core

import std.collection.ArrayList

public func renderGatewayPollText(raw: String): String {
    let parts = ArrayList<String>()
    for (seg in raw.trimAscii().split("|")) {
        let one = seg.trimAscii()
        if (!one.isEmpty()) {
            parts.add(one)
        }
    }
    if (parts.isEmpty()) {
        return raw.trimAscii()
    }
    let title = parts[0]
    if (parts.size == 1) {
        return "[poll]\n${title}"
    }
    let lines = ArrayList<String>()
    lines.add("[poll]")
    lines.add(title)
    var i: Int64 = 1
    while (i < parts.size) {
        lines.add("${i}. ${parts[i]}")
        i += 1
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayPollParts(raw: String): (String, Array<String>) {
    let parts = ArrayList<String>()
    for (seg in raw.trimAscii().split("|")) {
        let one = seg.trimAscii()
        if (!one.isEmpty()) {
            parts.add(one)
        }
    }
    if (parts.isEmpty()) {
        return ("", [])
    }
    let title = parts[0]
    if (parts.size == 1) {
        return (title, [])
    }
    let options = ArrayList<String>()
    var i: Int64 = 1
    while (i < parts.size) {
        options.add(parts[i])
        i += 1
    }
    return (title, options.toArray())
}

public func renderGatewayReactionText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    return "[reaction]\ntoken=${text}\nrender=${text}"
}

public func parseGatewayReactionToken(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[reaction]")) {
        return ""
    }
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("token=")) {
            return line["token=".size..].trimAscii()
        }
    }
    ""
}

public func renderGatewayStickerText(fileId: String): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    return "[sticker]\nfileId=${text}"
}

public func renderGatewayPhotoText(fileId: String, caption!: String = ""): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[photo]")
    lines.add("fileId=${text}")
    let normalizedCaption = caption.trimAscii()
    if (!normalizedCaption.isEmpty()) {
        lines.add("caption=${normalizedCaption}")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayPhotoParts(raw: String): (String, String) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[photo]")) {
        return ("", "")
    }
    var fileId = ""
    var caption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            fileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            caption = line["caption=".size..].trimAscii()
        }
    }
    (fileId, caption)
}

public func renderGatewayDocumentText(fileId: String, caption!: String = ""): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[document]")
    lines.add("fileId=${text}")
    let normalizedCaption = caption.trimAscii()
    if (!normalizedCaption.isEmpty()) {
        lines.add("caption=${normalizedCaption}")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayDocumentParts(raw: String): (String, String) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[document]")) {
        return ("", "")
    }
    var fileId = ""
    var caption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            fileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            caption = line["caption=".size..].trimAscii()
        }
    }
    (fileId, caption)
}

public func renderGatewayAudioText(fileId: String, caption!: String = ""): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[audio]")
    lines.add("fileId=${text}")
    let normalizedCaption = caption.trimAscii()
    if (!normalizedCaption.isEmpty()) {
        lines.add("caption=${normalizedCaption}")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayAudioParts(raw: String): (String, String) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[audio]")) {
        return ("", "")
    }
    var fileId = ""
    var caption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            fileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            caption = line["caption=".size..].trimAscii()
        }
    }
    (fileId, caption)
}

public func renderGatewayVoiceText(fileId: String, caption!: String = ""): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[voice]")
    lines.add("fileId=${text}")
    let normalizedCaption = caption.trimAscii()
    if (!normalizedCaption.isEmpty()) {
        lines.add("caption=${normalizedCaption}")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayVoiceParts(raw: String): (String, String) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[voice]")) {
        return ("", "")
    }
    var fileId = ""
    var caption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            fileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            caption = line["caption=".size..].trimAscii()
        }
    }
    (fileId, caption)
}

public func renderGatewayVideoText(fileId: String, caption!: String = ""): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[video]")
    lines.add("fileId=${text}")
    let normalizedCaption = caption.trimAscii()
    if (!normalizedCaption.isEmpty()) {
        lines.add("caption=${normalizedCaption}")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayVideoParts(raw: String): (String, String) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[video]")) {
        return ("", "")
    }
    var fileId = ""
    var caption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            fileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            caption = line["caption=".size..].trimAscii()
        }
    }
    (fileId, caption)
}

public func renderGatewayVideoNoteText(fileId: String): String {
    let text = fileId.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    return "[video-note]\nfileId=${text}"
}

public func parseGatewayVideoNoteFileId(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[video-note]")) {
        return ""
    }
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            return line["fileId=".size..].trimAscii()
        }
    }
    ""
}

public func parseGatewayStickerFileId(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[sticker]")) {
        return ""
    }
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("fileId=")) {
            return line["fileId=".size..].trimAscii()
        }
    }
    ""
}

public func renderGatewayDeleteText(): String {
    return "[delete]"
}

public func renderGatewayEditText(content: String): String {
    let text = content.trimAscii()
    if (text.isEmpty()) {
        return "[edit]"
    }
    return "[edit]\n${text}"
}

public func parseGatewayEditText(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[edit]")) {
        return ""
    }
    let lines = normalized.split("\n")
    if (lines.size <= 1) {
        return ""
    }
    String.join(lines[1..], delimiter: "\n").trimAscii()
}

public func renderGatewayTopicCreateText(title: String): String {
    let text = title.trimAscii()
    if (text.isEmpty()) {
        return "[topic-create]"
    }
    return "[topic-create]\n${text}"
}

public func parseGatewayTopicCreateText(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[topic-create]")) {
        return ""
    }
    let lines = normalized.split("\n")
    if (lines.size <= 1) {
        return ""
    }
    String.join(lines[1..], delimiter: "\n").trimAscii()
}

public func renderGatewayTopicEditText(title: String): String {
    let text = title.trimAscii()
    if (text.isEmpty()) {
        return "[topic-edit]"
    }
    return "[topic-edit]\n${text}"
}

public func parseGatewayTopicEditText(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[topic-edit]")) {
        return ""
    }
    let lines = normalized.split("\n")
    if (lines.size <= 1) {
        return ""
    }
    String.join(lines[1..], delimiter: "\n").trimAscii()
}

public func gatewayMessagePayloadPreview(text: String): String {
    let trimmed = text.trimAscii()
    if (trimmed.size <= 160) {
        return trimmed
    }
    return trimmed[0..160] + "..."
}
