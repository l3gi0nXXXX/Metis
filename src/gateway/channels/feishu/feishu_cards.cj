package metis.gateway.channels.feishu

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public class FeishuInteractiveCard {
    public let title: String
    public let text: String
    public let toolUseText: String
    public let actionId: String

    public init(title!: String = "", text!: String = "", toolUseText!: String = "", actionId!: String = "") {
        this.title = title.trimAscii()
        this.text = text.trimAscii()
        this.toolUseText = toolUseText.trimAscii()
        this.actionId = actionId.trimAscii()
    }

    public func fallbackText(): String {
        let body = if (this.toolUseText.isEmpty()) {
            this.text
        } else if (this.text.isEmpty()) {
            this.toolUseText
        } else {
            "${this.text}\n\n${this.toolUseText}"
        }
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
