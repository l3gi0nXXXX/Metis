package metis.gateway.channels.feishu

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public class FeishuInteractiveCard {
    public let title: String
    public let text: String
    public let actionId: String

    public init(title!: String = "", text!: String = "", actionId!: String = "") {
        this.title = title.trimAscii()
        this.text = text.trimAscii()
        this.actionId = actionId.trimAscii()
    }

    public func fallbackText(): String {
        if (this.title.isEmpty()) {
            return this.text
        }
        if (this.text.isEmpty()) {
            return this.title
        }
        "${this.title}\n${this.text}"
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
