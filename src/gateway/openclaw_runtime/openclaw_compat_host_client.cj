package metis.gateway.openclaw_runtime

import magic.jsonable.*
import stdx.encoding.json.{JsonObject, JsonString}

public enum OpenClawCompatHostTransportResult {
    | Response(JsonObject)
    | Timeout
    | Failure(String)
}

public interface OpenClawCompatHostTransport {
    func send(frame: JsonObject, timeoutMs!: Int64): OpenClawCompatHostTransportResult
    func close(): Unit
    func isAlive(): Bool
}

public class OpenClawCompatHostClientResult {
    public let ok: Bool
    public let status: String
    public let requestId: Int64
    public let result: JsonObject
    public let errorCode: String
    public let errorMessage: String
    public let diagnostic: JsonObject
    public let raw: JsonObject

    public init(
        ok: Bool,
        status: String,
        requestId!: Int64 = 0,
        result!: JsonObject = JsonObject(),
        errorCode!: String = "",
        errorMessage!: String = "",
        diagnostic!: JsonObject = JsonObject(),
        raw!: JsonObject = JsonObject()
    ) {
        this.ok = ok
        this.status = status
        this.requestId = requestId
        this.result = result
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.diagnostic = diagnostic
        this.raw = raw
    }
}

private func ocClientString(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func ocClientBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func ocClientObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func ocClientDiagnostic(kind: String, message!: String = "", timeoutMs!: Int64 = 0): JsonObject {
    let out = JsonObject()
    out.put("kind", JsonString(kind))
    if (!message.trimAscii().isEmpty()) {
        out.put("message", JsonString(message.trimAscii()))
    }
    if (timeoutMs > 0) {
        out.put("timeoutMs", timeoutMs.toJsonValue())
    }
    out
}

private func ocClientParseResponse(requestId: Int64, raw: JsonObject): OpenClawCompatHostClientResult {
    match (raw.get("error")) {
        case Some(v) =>
            let err = try { v.asObject() } catch (_: Exception) { JsonObject() }
            let code = ocClientString(err, "code", "OPENCLAW_HOST_RPC_ERROR")
            let message = ocClientString(err, "message", "OpenClaw host RPC error")
            return OpenClawCompatHostClientResult(
                false,
                "error",
                requestId: requestId,
                errorCode: code,
                errorMessage: message,
                diagnostic: ocClientDiagnostic("rpc_error", message: message),
                raw: raw
            )
        case None => ()
    }
    let result = ocClientObject(raw, "result")
    let ok = ocClientBool(result, "ok", true)
    let status = ocClientString(result, "status", if (ok) { "ok" } else { "error" })
    OpenClawCompatHostClientResult(ok, status, requestId: requestId, result: result, raw: raw)
}

public class OpenClawCompatHostClient {
    private let transport: OpenClawCompatHostTransport
    private let defaultTimeoutMs: Int64
    private var nextRequestId: Int64 = 1

    public init(transport: OpenClawCompatHostTransport, defaultTimeoutMs!: Int64 = 10000) {
        this.transport = transport
        this.defaultTimeoutMs = if (defaultTimeoutMs > 0) { defaultTimeoutMs } else { 10000 }
    }

    public func request(
        method: String,
        params!: JsonObject = JsonObject(),
        timeoutMs!: Int64 = 0
    ): OpenClawCompatHostClientResult {
        let requestId = this.nextRequestId
        this.nextRequestId += 1
        let frame = JsonObject()
        frame.put("jsonrpc", JsonString("2.0"))
        frame.put("id", requestId.toJsonValue())
        frame.put("method", JsonString(method.trimAscii()))
        frame.put("params", params)
        let effectiveTimeoutMs = if (timeoutMs > 0) { timeoutMs } else { this.defaultTimeoutMs }
        match (this.transport.send(frame, timeoutMs: effectiveTimeoutMs)) {
            case Response(raw) =>
                ocClientParseResponse(requestId, raw)
            case Timeout =>
                OpenClawCompatHostClientResult(
                    false,
                    "timeout",
                    requestId: requestId,
                    errorCode: "OPENCLAW_HOST_TIMEOUT",
                    errorMessage: "OpenClaw compatibility host request timed out",
                    diagnostic: ocClientDiagnostic("timeout", timeoutMs: effectiveTimeoutMs)
                )
            case Failure(reason) =>
                OpenClawCompatHostClientResult(
                    false,
                    "error",
                    requestId: requestId,
                    errorCode: "OPENCLAW_HOST_TRANSPORT_ERROR",
                    errorMessage: reason.trimAscii(),
                    diagnostic: ocClientDiagnostic("transport_error", message: reason)
                )
        }
    }

    public func health(timeoutMs!: Int64 = 0): OpenClawCompatHostClientResult {
        this.request("runtime.health", timeoutMs: timeoutMs)
    }

    public func stop(timeoutMs!: Int64 = 0): OpenClawCompatHostClientResult {
        try {
            return this.request("runtime.stop", timeoutMs: timeoutMs)
        } finally {
            this.transport.close()
        }
    }

    public func isAlive(): Bool {
        this.transport.isAlive()
    }
}
