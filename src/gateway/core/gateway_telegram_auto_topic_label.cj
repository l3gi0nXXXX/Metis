package metis.gateway.core

import metis.core.config.GatewayUserSettings

import std.collection.ArrayList

public func gatewayTelegramAutoTopicLabelStrategy(user: GatewayUserSettings): String {
    let normalized = user.telegram.autoTopicLabel.strategy.trimAscii().toAsciiLower()
    if (normalized == "off" || normalized == "disabled" || normalized == "false") {
        return "off"
    }
    if (normalized == "model") {
        return "model"
    }
    "deterministic"
}

public func gatewayTelegramAutoTopicLabelEnabled(user: GatewayUserSettings): Bool {
    user.telegram.autoTopicLabel.enabled && gatewayTelegramAutoTopicLabelStrategy(user) != "off"
}

public func gatewayTelegramDeterministicAutoTopicLabel(text: String): String {
    let cleaned = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")[0]
        .replace("[media-context]", "")
        .replace("[photo]", "")
        .replace("[document]", "")
        .replace("[voice]", "")
        .replace("[audio]", "")
        .trimAscii()
    if (cleaned.isEmpty()) {
        return "Metis topic"
    }
    let words = ArrayList<String>()
    for (part in cleaned.split(" ")) {
        let one = part.trimAscii()
        if (!one.isEmpty()) {
            words.add(one)
        }
        if (words.size >= 4) {
            break
        }
    }
    var title = if (words.isEmpty()) { cleaned } else { String.join(words.toArray(), delimiter: " ") }
    if (title.size > 32) {
        title = title[..32].trimAscii()
    }
    if (title.isEmpty()) { "Metis topic" } else { title }
}
