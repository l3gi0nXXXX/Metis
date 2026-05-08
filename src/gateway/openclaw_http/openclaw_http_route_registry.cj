package metis.gateway.openclaw_http

import metis.gateway.openclaw_channel_http.OpenClawBridgeRunner

import std.collection.ArrayList
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonFloat, JsonInt, JsonObject, JsonString}

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

    public init(
        ok: Bool,
        status: String,
        diagnosticKind!: String = "",
        diagnosticMessage!: String = "",
        method!: String = "",
        path!: String = "",
        pluginId!: String = ""
    ) {
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
        if (!method.trimAscii().isEmpty()) {
            d.put("method", JsonString(method.trimAscii().toAsciiUpper()))
        }
        if (!path.trimAscii().isEmpty()) {
            d.put("path", JsonString(path.trimAscii()))
        }
        if (!pluginId.trimAscii().isEmpty()) {
            d.put("pluginId", JsonString(pluginId.trimAscii().toAsciiLower()))
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
            return OpenClawHttpRouteRegistryResult(
                false,
                "invalid",
                diagnosticKind: "invalid_path",
                diagnosticMessage: "route path is empty",
                method: route.method,
                pluginId: route.pluginId
            )
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
                    diagnosticMessage: "${route.method} ${route.path} already registered",
                    method: route.method,
                    path: route.path,
                    pluginId: existing.pluginId
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

private func openClawHttpCaptureObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func openClawHttpCaptureArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func openClawHttpCaptureString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func openClawHttpCaptureString(obj: JsonObject, keys: Array<String>): String {
    for (key in keys) {
        let value = openClawHttpCaptureString(obj, key)
        if (!value.isEmpty()) {
            return value
        }
    }
    ""
}

private func openClawHttpCaptureInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            match (v) {
                case i: JsonInt => i.getValue()
                case f: JsonFloat => Int64(f.getValue())
                case _ => try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_e: Exception) { fallback }
            }
        case None => fallback
    }
}

private func openClawHttpCapturedCapabilityArray(capture: JsonObject, key: String): JsonArray {
    let direct = openClawHttpCaptureArray(capture, key)
    if (direct.size() > 0) {
        return direct
    }
    let capabilities = openClawHttpCaptureArray(openClawHttpCaptureObject(capture, "capabilities"), key)
    if (capabilities.size() > 0) {
        return capabilities
    }
    let gatewayRegistries = openClawHttpCaptureArray(openClawHttpCaptureObject(capture, "gatewayRegistries"), key)
    if (gatewayRegistries.size() > 0) {
        return gatewayRegistries
    }
    openClawHttpCaptureArray(openClawHttpCaptureObject(capture, "registry"), key)
}

private func registerOpenClawCapturedHttpRouteRecord(record: JsonObject, runner: OpenClawBridgeRunner): Bool {
    let spec = openClawHttpCaptureObject(record, "spec")
    let pluginMeta = openClawHttpCaptureObject(spec, "plugin")
    var pluginId = openClawHttpCaptureString(record, "pluginId")
    if (pluginId.isEmpty()) {
        pluginId = openClawHttpCaptureString(pluginMeta, ["id", "name"])
    }
    var path = openClawHttpCaptureString(record, "path")
    if (path.isEmpty()) {
        path = openClawHttpCaptureString(spec, "path")
    }
    if (path.isEmpty()) {
        return false
    }
    if (pluginId.isEmpty()) {
        pluginId = path
    }
    var method = openClawHttpCaptureString(record, "method")
    if (method.isEmpty()) {
        method = openClawHttpCaptureString(spec, "method")
    }
    if (method.isEmpty()) {
        method = "POST"
    }
    let maxBodyBytes = openClawHttpCaptureInt(spec, "maxBodyBytes", openClawHttpCaptureInt(record, "maxBodyBytes", 1048576))
    let timeoutMs = openClawHttpCaptureInt(spec, "timeoutMs", openClawHttpCaptureInt(record, "timeoutMs", 3000))
    OpenClawHttpRouteRegistry.register(
        OpenClawHttpRouteRegistration(
            pluginId,
            method,
            path,
            runner,
            maxBodyBytes: maxBodyBytes,
            timeoutMs: timeoutMs
        )
    ).ok
}

public func registerOpenClawCapturedHttpRoutes(capture: JsonObject, runner: OpenClawBridgeRunner): Int64 {
    var count: Int64 = 0
    for (group in ["httpRoutes", "httpHandlers"]) {
        let routes = openClawHttpCapturedCapabilityArray(capture, group)
        for (i in 0..routes.size()) {
            let record = try { routes[i].asObject() } catch (_e: Exception) { JsonObject() }
            if (registerOpenClawCapturedHttpRouteRecord(record, runner)) {
                count += 1
            }
        }
    }
    count
}
