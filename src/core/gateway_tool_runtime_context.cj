package metis.core

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import stdx.encoding.json.JsonObject

public class GatewayToolRuntimeContext {
    public let sourceLabel: String
    public let channelName: String
    public let sessionKey: String
    public let senderId: String
    public let declaredUser: String
    public let operatorScopes: Array<String>
    public let prompt: String
    public let mediaContext: JsonObject
    public let lifecycleHook: Option<(String) -> Unit>

    public init(
        sourceLabel: String,
        channelName!: String = "",
        sessionKey!: String = "",
        senderId!: String = "",
        declaredUser!: String = "",
        operatorScopes!: Array<String> = [],
        prompt!: String = "",
        mediaContext!: JsonObject = JsonObject(),
        lifecycleHook!: Option<(String) -> Unit> = None<(String) -> Unit>
    ) {
        this.sourceLabel = sourceLabel.trimAscii().toAsciiLower()
        this.channelName = channelName.trimAscii().toAsciiLower()
        this.sessionKey = sessionKey.trimAscii()
        this.senderId = senderId.trimAscii()
        this.declaredUser = declaredUser.trimAscii()
        let normalizedScopes = ArrayList<String>()
        for (scope in operatorScopes) {
            let normalized = scope.trimAscii().toAsciiLower()
            if (!normalized.isEmpty() && !normalizedScopes.contains(normalized)) {
                normalizedScopes.add(normalized)
            }
        }
        this.operatorScopes = normalizedScopes.toArray()
        this.prompt = prompt
        this.mediaContext = mediaContext
        this.lifecycleHook = lifecycleHook
    }

    public func notifyLifecycleStatus(status: String): Unit {
        let normalized = status.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return
        }
        match (this.lifecycleHook) {
            case Some(hook) =>
                try {
                    hook(normalized)
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
}

private let gatewayToolRuntimeContextLock = Mutex()
private let gatewayToolRuntimeContextByThread = HashMap<String, ArrayList<GatewayToolRuntimeContext>>()

private func gatewayToolRuntimeThreadKey(): String {
    Thread.currentThread.name.trimAscii()
}

private func gatewayToolRuntimeContextStack(threadKey: String): ArrayList<GatewayToolRuntimeContext> {
    match (gatewayToolRuntimeContextByThread.get(threadKey)) {
        case Some(existing) => existing
        case None =>
            let created = ArrayList<GatewayToolRuntimeContext>()
            gatewayToolRuntimeContextByThread[threadKey] = created
            created
    }
}

public func gatewayPushToolRuntimeContext(context: GatewayToolRuntimeContext): Unit {
    synchronized(gatewayToolRuntimeContextLock) {
        gatewayToolRuntimeContextStack(gatewayToolRuntimeThreadKey()).add(context)
    }
}

public func gatewayPopToolRuntimeContext(): Unit {
    synchronized(gatewayToolRuntimeContextLock) {
        let threadKey = gatewayToolRuntimeThreadKey()
        match (gatewayToolRuntimeContextByThread.get(threadKey)) {
            case Some(stack) =>
                if (stack.size > 0) {
                    stack.remove(at: stack.size - 1)
                }
                if (stack.size == 0) {
                    gatewayToolRuntimeContextByThread.remove(threadKey)
                }
            case None => ()
        }
    }
}

public func gatewayCurrentToolRuntimeContext(): Option<GatewayToolRuntimeContext> {
    synchronized(gatewayToolRuntimeContextLock) {
        match (gatewayToolRuntimeContextByThread.get(gatewayToolRuntimeThreadKey())) {
            case Some(stack) =>
                if (stack.size > 0) {
                    Some(stack[stack.size - 1])
                } else {
                    None<GatewayToolRuntimeContext>
                }
            case None => None<GatewayToolRuntimeContext>
        }
    }
}

public func gatewayNotifyCurrentToolRuntimeStatus(status: String): Unit {
    match (gatewayCurrentToolRuntimeContext()) {
        case Some(context) => context.notifyLifecycleStatus(status)
        case None => ()
    }
}

public func gatewayWithToolRuntimeContext<T>(context: GatewayToolRuntimeContext, block: () -> T): T {
    gatewayPushToolRuntimeContext(context)
    try {
        block()
    } finally {
        gatewayPopToolRuntimeContext()
    }
}
