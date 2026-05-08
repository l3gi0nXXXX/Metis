package metis.gateway.openclaw_http

import magic.jsonable.*
import metis.gateway.openclaw_channel_http.{OpenClawHttpDispatchResult, OpenClawHttpRouteBridge}

import std.collection.ArrayList
import stdx.encoding.json.{JsonObject, JsonString}
import stdx.net.http.*

private func openClawHttpDiagnosticResult(
    statusCode: Int64,
    status: String,
    kind: String,
    message: String
): OpenClawHttpDispatchResult {
    let diagnostic = JsonObject()
    diagnostic.put("kind", JsonString(kind))
    diagnostic.put("message", JsonString(message))
    let raw = JsonObject()
    raw.put("ok", false.toJsonValue())
    raw.put("status", JsonString(status))
    raw.put("statusCode", statusCode.toJsonValue())
    raw.put("headers", JsonObject())
    raw.put("body", JsonString(""))
    raw.put("diagnostic", diagnostic)
    OpenClawHttpDispatchResult(false, status, statusCode, JsonObject(), "", diagnostic, kind, message, raw)
}

private func openClawHttpReadBody(ctx: HttpContext): String {
    let chunks = ArrayList<Byte>()
    let buffer = Array<Byte>(4096, repeat: 0)
    try {
        while (true) {
            let n = ctx.request.body.read(buffer)
            if (n <= 0) {
                break
            }
            for (i in 0..n) {
                chunks.add(buffer[i])
            }
        }
        String.fromUtf8(chunks.toArray())
    } catch (_e: Exception) {
        ""
    }
}

private func openClawHttpSelectedHeaders(ctx: HttpContext): JsonObject {
    let out = JsonObject()
    for (name in ["host", "content-type", "x-openclaw-signature", "x-wechat-signature", "x-wecom-signature"]) {
        let value = ctx.request.headers.getFirst(name) ?? ctx.request.headers.getFirst(name.toAsciiLower()) ?? ""
        if (!value.trimAscii().isEmpty()) {
            out.put(name, JsonString(value))
        }
    }
    out
}

public class OpenClawHttpDispatcher {
    public static func dispatch(
        method: String,
        path: String,
        query!: JsonObject = JsonObject(),
        headers!: JsonObject = JsonObject(),
        body!: String = ""
    ): OpenClawHttpDispatchResult {
        match (OpenClawHttpRouteRegistry.find(method, path)) {
            case Some(route) =>
                if (route.maxBodyBytes >= 0 && Int64(body.toArray().size) > route.maxBodyBytes) {
                    return openClawHttpDiagnosticResult(413, "body_too_large", "body_too_large", "request body exceeds route limit")
                }
                OpenClawHttpRouteBridge(route.runner).dispatch(
                    route.method,
                    route.path,
                    query: query,
                    headers: headers,
                    body: JsonString(body),
                    timeoutMs: route.timeoutMs
                )
            case None =>
                openClawHttpDiagnosticResult(404, "not_found", "route_not_found", "${method.trimAscii().toAsciiUpper()} ${path.trimAscii()} is not registered")
        }
    }
}

public func gatewayRegisterOpenClawHttpRoutes(server: Server): Int64 {
    var count: Int64 = 0
    for (route in OpenClawHttpRouteRegistry.allRoutes()) {
        let routePath = route.path
        server.distributor.register(routePath, { ctx =>
            let result = OpenClawHttpDispatcher.dispatch(
                ctx.request.method,
                routePath,
                headers: openClawHttpSelectedHeaders(ctx),
                body: openClawHttpReadBody(ctx)
            )
            let rb = ctx.responseBuilder
            if (result.statusCode > 0) {
                rb.status(UInt16(result.statusCode))
            }
            let contentType = match (result.headers.get("content-type")) {
                case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "application/json; charset=utf-8" }
                case None => "application/json; charset=utf-8"
            }
            rb.header("content-type", contentType)
            rb.body(result.body)
        })
        count += 1
    }
    count
}
