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

public func renderGatewayPollTextAdvanced(
    raw: String,
    durationSeconds!: Option<Int64> = None<Int64>,
    allowMultiselect!: Option<Bool> = None<Bool>,
    isAnonymous!: Option<Bool> = None<Bool>
): String {
    let base = renderGatewayPollText(raw)
    if (!base.startsWith("[poll]")) {
        return base
    }
    let lines = ArrayList<String>()
    for (line in base.split("\n")) {
        lines.add(line)
    }
    match (durationSeconds) {
        case Some(v) => lines.add("durationSeconds=${v}")
        case None => ()
    }
    match (allowMultiselect) {
        case Some(v) => lines.add("allowMultiselect=${v}")
        case None => ()
    }
    match (isAnonymous) {
        case Some(v) => lines.add("isAnonymous=${v}")
        case None => ()
    }
    String.join(lines.toArray(), delimiter: "\n")
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
    if (text.toAsciiLower() == "remove" || text.toAsciiLower() == "none" || text.toAsciiLower() == "empty") {
        return "[reaction]\nremove=true\nrender=${text}"
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

public func parseGatewayReactionRemove(raw: String): Bool {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[reaction]")) {
        return false
    }
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii().toAsciiLower()
        if (line == "remove=true" || line == "remove=1" || line == "empty=true") {
            return true
        }
    }
    false
}

public func renderGatewayChatActionText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    return "[chat-action]\naction=${text}"
}

public func parseGatewayChatAction(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[chat-action]")) {
        return ""
    }
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("action=")) {
            return line["action=".size..].trimAscii()
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

public class GatewayMediaGroupItem {
    public let kind: String
    public let fileId: String
    public let caption: String

    public init(kind: String, fileId: String, caption!: String = "") {
        this.kind = kind.trimAscii().toAsciiLower()
        this.fileId = fileId.trimAscii()
        this.caption = caption.trimAscii()
    }
}

public func parseGatewayMediaGroupItems(raw: String): Array<GatewayMediaGroupItem> {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[media-group]")) {
        return []
    }
    let out = ArrayList<GatewayMediaGroupItem>()
    var currentKind = ""
    var currentFileId = ""
    var currentCaption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.isEmpty() || line == "[media-group]") {
            continue
        }
        if (line.startsWith("item=")) {
            if (!currentFileId.isEmpty()) {
                out.add(GatewayMediaGroupItem(currentKind, currentFileId, caption: currentCaption))
                currentKind = ""
                currentFileId = ""
                currentCaption = ""
            }
            let spec = line["item=".size..].trimAscii()
            let parts = spec.split("|")
            if (parts.size >= 2) {
                currentKind = parts[0].trimAscii().toAsciiLower()
                currentFileId = parts[1].trimAscii()
                if (parts.size >= 3) {
                    currentCaption = parts[2].trimAscii()
                }
            }
        } else if (line.startsWith("type=")) {
            currentKind = line["type=".size..].trimAscii().toAsciiLower()
        } else if (line.startsWith("fileId=")) {
            currentFileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            currentCaption = line["caption=".size..].trimAscii()
        } else if (line == "---" || line == "item") {
            if (!currentFileId.isEmpty()) {
                out.add(GatewayMediaGroupItem(currentKind, currentFileId, caption: currentCaption))
            }
            currentKind = ""
            currentFileId = ""
            currentCaption = ""
        }
    }
    if (!currentFileId.isEmpty()) {
        out.add(GatewayMediaGroupItem(currentKind, currentFileId, caption: currentCaption))
    }
    out.toArray()
}

public func parseGatewayEditMediaParts(raw: String): (String, String, String) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[edit-media]")) {
        return ("", "", "")
    }
    var kind = ""
    var fileId = ""
    var caption = ""
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("type=")) {
            kind = line["type=".size..].trimAscii().toAsciiLower()
        } else if (line.startsWith("fileId=")) {
            fileId = line["fileId=".size..].trimAscii()
        } else if (line.startsWith("caption=")) {
            caption = line["caption=".size..].trimAscii()
        }
    }
    (kind, fileId, caption)
}

public func renderGatewayInlineKeyboardText(text: String, buttons: Array<String>): String {
    let normalizedText = text.trimAscii()
    if (normalizedText.isEmpty() || buttons.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[inline-keyboard]")
    lines.add("text=${normalizedText}")
    for (button in buttons) {
        let one = button.trimAscii()
        if (one.isEmpty()) {
            continue
        }
        if (one == "---" || one.toAsciiLower() == "row") {
            lines.add("row")
        } else {
            lines.add("button=${one}")
        }
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayInlineKeyboardParts(raw: String): (String, Array<String>) {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[inline-keyboard]")) {
        return ("", [])
    }
    var text = ""
    let buttons = ArrayList<String>()
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("text=")) {
            text = line["text=".size..].trimAscii()
        } else if (line.startsWith("button=")) {
            let spec = line["button=".size..].trimAscii()
            if (!spec.isEmpty()) {
                buttons.add(spec)
            }
        } else if (line == "row" || line == "---") {
            buttons.add("row")
        }
    }
    (text, buttons.toArray())
}

public func renderGatewayEditButtonsText(buttons: Array<String>): String {
    if (buttons.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    lines.add("[edit-buttons]")
    for (button in buttons) {
        let one = button.trimAscii()
        if (one.isEmpty()) {
            continue
        }
        if (one == "---" || one.toAsciiLower() == "row") {
            lines.add("row")
        } else {
            lines.add("button=${one}")
        }
    }
    if (lines.size == 1) {
        return ""
    }
    String.join(lines.toArray(), delimiter: "\n")
}

public func parseGatewayEditButtonsParts(raw: String): Array<String> {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    if (!normalized.startsWith("[edit-buttons]")) {
        return []
    }
    let buttons = ArrayList<String>()
    for (line0 in normalized.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("button=")) {
            let spec = line["button=".size..].trimAscii()
            if (!spec.isEmpty()) {
                buttons.add(spec)
            }
        } else if (line == "row" || line == "---") {
            buttons.add("row")
        }
    }
    buttons.toArray()
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

public func renderGatewayPinText(): String {
    return "[pin]"
}

public func renderGatewayUnpinText(): String {
    return "[unpin]"
}

public func parseGatewayPinAction(raw: String): String {
    let normalized = raw.replace("\r\n", "\n").replace("\r", "\n").trimAscii().toAsciiLower()
    if (normalized == "[pin]") {
        return "pin"
    }
    if (normalized == "[unpin]") {
        return "unpin"
    }
    ""
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
