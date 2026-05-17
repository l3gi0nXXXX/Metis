package metis.gateway.runtime

import std.collection.{ArrayList, HashSet}

public class GatewayReloadPlan {
    public let changedPaths: Array<String>
    public var restartGateway: Bool = false
    public let restartReasons = ArrayList<String>()
    public let hotReasons = ArrayList<String>()
    public let noopPaths = ArrayList<String>()
    public let restartChannels = ArrayList<String>()

    public init(changedPaths: Array<String>) {
        this.changedPaths = changedPaths
    }
}

private func gatewayReloadPathMatches(path: String, prefix: String): Bool {
    let p = path.trimAscii()
    let rule = prefix.trimAscii()
    p == rule || p.startsWith("${rule}.")
}

private func gatewayReloadAddChannel(plan: GatewayReloadPlan, seen: HashSet<String>, channelId: String): Unit {
    let normalized = channelId.trimAscii().toAsciiLower()
    if (normalized.isEmpty() || seen.contains(normalized)) {
        return
    }
    seen.add(normalized)
    plan.restartChannels.add(normalized)
}

public func buildGatewayReloadPlan(changedPaths: Array<String>): GatewayReloadPlan {
    let plan = GatewayReloadPlan(changedPaths)
    let seenChannels = HashSet<String>()
    for (path in changedPaths) {
        let p = path.trimAscii()
        if (p.isEmpty()) {
            continue
        }
        if (gatewayReloadPathMatches(p, "gateway.reload") || gatewayReloadPathMatches(p, "gateway.remote")) {
            plan.noopPaths.add(p)
            continue
        }
        if (gatewayReloadPathMatches(p, "gateway.telegram")) {
            plan.hotReasons.add(p)
            gatewayReloadAddChannel(plan, seenChannels, "telegram")
            continue
        }
        if (gatewayReloadPathMatches(p, "gateway.feishu")) {
            plan.hotReasons.add(p)
            gatewayReloadAddChannel(plan, seenChannels, "feishu")
            continue
        }
        if (gatewayReloadPathMatches(p, "gateway.qq")) {
            plan.hotReasons.add(p)
            gatewayReloadAddChannel(plan, seenChannels, "qq")
            continue
        }
        if (
            gatewayReloadPathMatches(p, "agents") ||
            gatewayReloadPathMatches(p, "bindings") ||
            gatewayReloadPathMatches(p, "models") ||
            gatewayReloadPathMatches(p, "tools") ||
            gatewayReloadPathMatches(p, "session") ||
            gatewayReloadPathMatches(p, "meta")
        ) {
            plan.noopPaths.add(p)
            continue
        }
        plan.restartGateway = true
        plan.restartReasons.add(p)
    }
    plan
}
