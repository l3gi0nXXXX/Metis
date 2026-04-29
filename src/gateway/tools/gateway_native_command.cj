package metis.gateway.tools

import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private let GATEWAY_NATIVE_COMMAND_USAGE = "/help | /status | /activation | /pair | /subagents help | /skills list"

private func gatewayNativeCommandJson(action: String, message: String): String {
    let out = JsonObject()
    out.put("ok", JsonBool(true))
    out.put("status", JsonString("ok"))
    out.put("action", JsonString(action))
    out.put("message", JsonString(message))
    out.put("usage", JsonString(GATEWAY_NATIVE_COMMAND_USAGE))
    let commands = JsonArray()
    for ((command, description) in [
        ("/help", "查看 Gateway 可用命令"),
        ("/status", "查看当前 Gateway 会话可用能力"),
        ("/activation", "查看 Telegram 激活方式说明"),
        ("/pair", "查看 Telegram 私聊配对说明"),
        ("/subagents help", "查看后台 subagent 管理命令"),
        ("/skills list", "查看可用技能")
    ]) {
        let item = JsonObject()
        item.put("command", JsonString(command))
        item.put("description", JsonString(description))
        commands.add(item)
    }
    out.put("commands", commands)
    out.toJsonString()
}

public func gatewayHandleNativeCommandLine(raw: String): Option<String> {
    let trimmed = raw.trimAscii()
    let lowered = trimmed.toAsciiLower()
    if (lowered == "/help") {
        return Some(gatewayNativeCommandJson("help", "Gateway 原生命令已接入当前会话，可使用 /status、/activation、/pair、/subagents help 和 /skills list。"))
    }
    if (lowered == "/status" || lowered.startsWith("/status ")) {
        return Some(gatewayNativeCommandJson("status", "Gateway 当前会话可用。详细运行时状态请使用控制端或 Gateway runtime status 能力查看。"))
    }
    if (lowered == "/activation" || lowered.startsWith("/activation ")) {
        return Some(gatewayNativeCommandJson("activation", "Telegram 激活由通道配置控制：私聊按 dmPolicy，群聊按 groupPolicy、mention 和 allowlist 生效。"))
    }
    if (lowered == "/pair" || lowered.startsWith("/pair ")) {
        return Some(gatewayNativeCommandJson("pair", "Telegram 私聊配对由 Gateway 生成验证码后完成审批；如当前会话需要配对，请先向 bot 私聊发送消息并按返回提示操作。"))
    }
    None<String>
}
