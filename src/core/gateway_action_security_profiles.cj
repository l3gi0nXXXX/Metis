package metis.core

public func gatewayActionNormalize(action: String): String {
    action.trimAscii().toAsciiLower()
}

public func gatewayConfigPathNormalize(path: String): String {
    path.trimAscii().toAsciiLower()
}

public func gatewayActionClass(action: String): String {
    let normalized = gatewayActionNormalize(action)
    if (
        normalized == "status" ||
        normalized == "health" ||
        normalized == "discover" ||
        normalized == "discover.detail" ||
        normalized == "config.get" ||
        normalized == "config.schema.lookup"
    ) {
        return "read_only"
    }
    if (
        normalized == "start" ||
        normalized == "stop" ||
        normalized == "restart" ||
        normalized == "master_on" ||
        normalized == "master_off"
    ) {
        return "mutating_runtime"
    }
    if (normalized == "config.patch" || normalized == "config.apply") {
        return "mutating_config"
    }
    if (normalized == "update.run") {
        return "control_plane"
    }
    return "unsupported"
}

public func gatewayActionIsReadOnly(action: String): Bool {
    gatewayActionClass(action) == "read_only"
}

public func gatewayActionIsControlPlane(action: String): Bool {
    let klass = gatewayActionClass(action)
    klass == "control_plane" || klass == "mutating_runtime" || klass == "mutating_config"
}

public func gatewayActionIsMutating(action: String): Bool {
    let klass = gatewayActionClass(action)
    klass == "mutating_runtime" || klass == "mutating_config"
}

public func gatewayActionRequiresOwner(action: String): Bool {
    gatewayActionIsControlPlane(action)
}

public func gatewayActionRequiresExplicitUserRequest(action: String): Bool {
    let normalized = gatewayActionNormalize(action)
    normalized == "config.patch" || normalized == "config.apply" || normalized == "update.run"
}

public func gatewayActionIsApprovalSensitive(action: String): Bool {
    gatewayActionIsControlPlane(action)
}

public func gatewayActionIsProtectedPathSensitive(action: String): Bool {
    let normalized = gatewayActionNormalize(action)
    normalized == "config.patch" || normalized == "config.apply"
}

public func gatewayConfigPathIsProtected(path: String): Bool {
    let normalized = gatewayConfigPathNormalize(path)
    normalized == "controlui.allowinsecureauth" ||
        normalized == "gateway.controlui.allowinsecureauth" ||
        normalized == "controlui.dangerouslydisabledeviceauth" ||
        normalized == "gateway.controlui.dangerouslydisabledeviceauth" ||
        normalized == "auth.mode" ||
        normalized == "gateway.auth.mode" ||
        normalized == "auth.allowtailscale" ||
        normalized == "gateway.auth.allowtailscale"
}

public func gatewayActionRequiresDeniedControlAction(action: String): Bool {
    gatewayActionIsControlPlane(action)
}
