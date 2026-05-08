package metis.gateway.openclaw_http

import metis.gateway.openclaw_channel_http.OpenClawBridgeRunner

import std.collection.ArrayList
import stdx.encoding.json.{JsonObject, JsonString}

public class OpenClawHttpRouteRegistration {
    public let pluginId: String
    public let method: String
    public let path: String
    public let runner: OpenClawBridgeRunner
    public let maxBodyBytes: Int64
    public let timeoutMs: Int64
    public let collisionPolicy: String

    public init(
        pluginId: String,
        method: String,
        path: String,
        runner: OpenClawBridgeRunner,
        maxBodyBytes!: Int64 = 1048576,
        timeoutMs!: Int64 = 3000,
        collisionPolicy!: String = "reject"
    ) {
        this.pluginId = pluginId.trimAscii().toAsciiLower()
        this.method = method.trimAscii().toAsciiUpper()
        this.path = path.trimAscii()
        this.runner = runner
        this.maxBodyBytes = maxBodyBytes
        this.timeoutMs = timeoutMs
        this.collisionPolicy = collisionPolicy.trimAscii().toAsciiLower()
    }
}

public class OpenClawHttpRouteRegistryResult {
    public let ok: Bool
    public let status: String
    public let diagnosticKind: String
    public let diagnosticMessage: String
    public let diagnostic: JsonObject

    public init(ok: Bool, status: String, diagnosticKind!: String = "", diagnosticMessage!: String = "") {
        this.ok = ok
        this.status = status
        this.diagnosticKind = diagnosticKind
        this.diagnosticMessage = diagnosticMessage
        let d = JsonObject()
        if (!diagnosticKind.isEmpty()) {
            d.put("kind", JsonString(diagnosticKind))
        }
        if (!diagnosticMessage.isEmpty()) {
            d.put("message", JsonString(diagnosticMessage))
        }
        this.diagnostic = d
    }
}

public class OpenClawHttpRouteRegistry {
    private static var routes: ArrayList<OpenClawHttpRouteRegistration> = ArrayList<OpenClawHttpRouteRegistration>()

    public static func clearForTest(): Unit {
        routes = ArrayList<OpenClawHttpRouteRegistration>()
    }

    public static func allRoutes(): Array<OpenClawHttpRouteRegistration> {
        routes.toArray()
    }

    public static func register(route: OpenClawHttpRouteRegistration): OpenClawHttpRouteRegistryResult {
        if (route.path.isEmpty()) {
            return OpenClawHttpRouteRegistryResult(false, "invalid", diagnosticKind: "invalid_path", diagnosticMessage: "route path is empty")
        }
        for (existing in routes) {
            if (existing.method == route.method && existing.path == route.path) {
                if (route.collisionPolicy == "replace") {
                    let next = ArrayList<OpenClawHttpRouteRegistration>()
                    for (row in routes) {
                        if (!(row.method == route.method && row.path == route.path)) {
                            next.add(row)
                        }
                    }
                    next.add(route)
                    routes = next
                    return OpenClawHttpRouteRegistryResult(true, "replaced")
                }
                return OpenClawHttpRouteRegistryResult(
                    false,
                    "collision",
                    diagnosticKind: "route_collision",
                    diagnosticMessage: "${route.method} ${route.path} already registered"
                )
            }
        }
        routes.add(route)
        OpenClawHttpRouteRegistryResult(true, "registered")
    }

    public static func find(method: String, path: String): Option<OpenClawHttpRouteRegistration> {
        let m = method.trimAscii().toAsciiUpper()
        let p = path.trimAscii()
        for (route in routes) {
            if (route.method == m && route.path == p) {
                return Some(route)
            }
        }
        None<OpenClawHttpRouteRegistration>
    }
}

public func openClawHttpSidecarPublicListenerEnabled(): Bool {
    false
}
