package metis.core.tools

import metis.gateway.openclaw_sandbox.OpenClawSandboxGrantSet

public class OpenClawToolResultShape {
    public let okKey: String
    public let contentKey: String
    public let errorKey: String

    public init(okKey: String, contentKey: String, errorKey: String) {
        this.okKey = okKey.trimAscii()
        this.contentKey = contentKey.trimAscii()
        this.errorKey = errorKey.trimAscii()
    }
}

public class OpenClawToolRegistration {
    public let name: String
    public let inputSchema: String
    public let requiredPermissions: Array<String>
    public let timeoutMs: Int64
    public let contextScopes: Array<String>
    public let resultShape: OpenClawToolResultShape

    public init(
        name: String,
        inputSchema: String,
        requiredPermissions!: Array<String> = [],
        timeoutMs!: Int64 = 0,
        contextScopes!: Array<String> = [],
        resultOkKey!: String = "ok",
        resultContentKey!: String = "content",
        resultErrorKey!: String = "error"
    ) {
        this.name = name.trimAscii()
        this.inputSchema = inputSchema
        this.requiredPermissions = requiredPermissions
        this.timeoutMs = timeoutMs
        this.contextScopes = contextScopes
        this.resultShape = OpenClawToolResultShape(resultOkKey, resultContentKey, resultErrorKey)
    }
}

public class OpenClawToolProjection {
    public let name: String
    public let inputSchema: String
    public let requiredPermissions: Array<String>
    public let timeoutMs: Int64
    public let contextScopes: Array<String>
    public let resultShape: OpenClawToolResultShape
    public let allowed: Bool
    public let missingPermissions: Array<String>

    public init(registration: OpenClawToolRegistration, grants: OpenClawSandboxGrantSet) {
        this.name = registration.name
        this.inputSchema = registration.inputSchema
        this.requiredPermissions = registration.requiredPermissions
        this.timeoutMs = registration.timeoutMs
        this.contextScopes = registration.contextScopes
        this.resultShape = registration.resultShape
        this.missingPermissions = grants.missing(registration.requiredPermissions)
        this.allowed = this.missingPermissions.isEmpty()
    }
}

public class OpenClawToolBridge {
    public static func project(registration: OpenClawToolRegistration, grants: OpenClawSandboxGrantSet): OpenClawToolProjection {
        OpenClawToolProjection(registration, grants)
    }
}
