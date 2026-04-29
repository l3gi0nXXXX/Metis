package metis.gateway.channels.telegram

import magic.jsonable.*

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.io.StringReader
import std.net.{SocketAddress, TcpSocket}
import std.time.*
import stdx.encoding.base64.toBase64String
import stdx.encoding.json.*
import stdx.encoding.url.URL
import stdx.net.http.*
import stdx.net.tls.*

public class TelegramTransportRequest {
    public let method: String
    public let url: String
    public let context: String
    public let accept: String
    public let body: String
    public let proxy: String
    public let timeoutSeconds: Int64

    public init(
        method: String,
        url: String,
        context!: String = "",
        accept!: String = "application/json",
        body!: String = "",
        proxy!: String = "",
        timeoutSeconds!: Int64 = 30
    ) {
        this.method = method
        this.url = url
        this.context = context
        this.accept = accept
        this.body = body
        this.proxy = proxy
        this.timeoutSeconds = timeoutSeconds
    }
}

public class TelegramTransportResponse {
    public let ok: Bool
    public let body: String
    public let error: String
    public let outcome: String
    public let statusCode: Int64

    public init(
        ok: Bool,
        body!: String = "",
        error!: String = "",
        outcome!: String = "",
        statusCode!: Int64 = 0
    ) {
        this.ok = ok
        this.body = body
        this.error = error
        this.outcome = outcome
        this.statusCode = statusCode
    }
}

private class TelegramProxyEndpoint {
    public let host: String
    public let port: UInt16
    public let auth: String

    public init(host: String, port: UInt16, auth!: String = "") {
        this.host = host
        this.port = port
        this.auth = auth
    }
}

private var telegramTransportRunnerOverride: Option<(TelegramTransportRequest) -> TelegramTransportResponse> = None<(TelegramTransportRequest) -> TelegramTransportResponse>

public func setTelegramTransportRunnerForTest(runner: Option<(TelegramTransportRequest) -> TelegramTransportResponse>): Unit {
    telegramTransportRunnerOverride = runner
}

public class TelegramTransport {
    private let proxy: String
    private let timeoutSeconds: Int64

    public init(proxy!: String = "", timeoutSeconds!: Int64 = 30) {
        this.proxy = proxy.trimAscii()
        this.timeoutSeconds = if (timeoutSeconds > 0) { timeoutSeconds } else { 30 }
    }

    public func get(url: String, accept!: String = "application/json", context!: String = "get"): TelegramTransportResponse {
        let request = TelegramTransportRequest(
            "GET",
            url,
            context: context,
            accept: accept,
            proxy: this.proxy,
            timeoutSeconds: this.timeoutSeconds
        )
        match (telegramTransportRunnerOverride) {
            case Some(runner) => return runner(request)
            case None => ()
        }
        let headers = HashMap<String, String>()
        headers["Accept"] = accept
        this.sendNative(request, headers)
    }

    public func postJson(url: String, body: JsonObject, context!: String = "postJson"): TelegramTransportResponse {
        let request = TelegramTransportRequest(
            "POST",
            url,
            context: context,
            accept: "application/json",
            body: body.toJsonString(),
            proxy: this.proxy,
            timeoutSeconds: this.timeoutSeconds
        )
        match (telegramTransportRunnerOverride) {
            case Some(runner) => return runner(request)
            case None => ()
        }
        let headers = HashMap<String, String>()
        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/json; charset=utf-8"
        this.sendNative(request, headers)
    }

    private func sendNative(
        request: TelegramTransportRequest,
        headers: HashMap<String, String>
    ): TelegramTransportResponse {
        try {
            let client = this.buildNativeHttpClient(request.url)
            try {
                let response = client.send(this.buildNativeHttpRequest(request, headers))
                let status = Int64(response.status)
                let responseBody = StringReader(response.body).readToEnd()
                if (status >= 200 && status < 300) {
                    return TelegramTransportResponse(true, body: responseBody, outcome: "ok", statusCode: status)
                }
                let detail = if (responseBody.trimAscii().isEmpty()) {
                    "Http status: ${status}"
                } else {
                    "Http status: ${status}\nHttp response: ${responseBody}"
                }
                TelegramTransportResponse(false, error: detail, outcome: this.classifyStatus(status), statusCode: status)
            } finally {
                client.close()
            }
        } catch (e: Exception) {
            TelegramTransportResponse(false, error: e.message, outcome: this.classifyException(e.message), statusCode: 0)
        }
    }

    private func buildNativeHttpClient(url: String): Client {
        let builder = ClientBuilder()
        builder.readTimeout(Duration.second * (this.timeoutSeconds + 5))
        let useConnectTunnel = !this.proxy.isEmpty() && url.startsWith("https")
        if (!this.proxy.isEmpty() && !useConnectTunnel) {
            builder.httpProxy(this.proxy)
        }
        if (url.startsWith("https")) {
            var tlsConfig = TlsClientConfig()
            tlsConfig.verifyMode = TrustAll
            tlsConfig.domain = URL.parse(url).hostName
            tlsConfig.alpnProtocolsList = ["http/1.1"]
            builder.tlsConfig(tlsConfig)
        }
        if (useConnectTunnel) {
            let proxyEndpoint = this.parseHttpProxyEndpoint(this.proxy)
            let targetHost = URL.parse(url).hostName
            let connectTimeoutSeconds = if (this.timeoutSeconds > 0) { this.timeoutSeconds } else { 30 }
            let socketConnector = { _sa: SocketAddress =>
                let socket = TcpSocket(proxyEndpoint.host, proxyEndpoint.port)
                socket.readTimeout = Duration.second * (this.timeoutSeconds + 5)
                socket.writeTimeout = Duration.second * (this.timeoutSeconds + 5)
                socket.connect(timeout: Duration.second * connectTimeoutSeconds)
                this.openHttpConnectTunnel(socket, targetHost, 443u16, proxyEndpoint)
                return socket
            }
            builder.connector(socketConnector)
        } else if (this.proxy.isEmpty()) {
            let connectTimeoutSeconds = if (this.timeoutSeconds > 0) { this.timeoutSeconds } else { 30 }
            let socketConnector = { sa: SocketAddress =>
                let socket = TcpSocket(sa)
                socket.readTimeout = Duration.second * (this.timeoutSeconds + 5)
                socket.writeTimeout = Duration.second * (this.timeoutSeconds + 5)
                socket.connect(timeout: Duration.second * connectTimeoutSeconds)
                return socket
            }
            builder.connector(socketConnector)
        }
        builder.build()
    }

    private func parseHttpProxyEndpoint(proxy: String): TelegramProxyEndpoint {
        let trimmed = proxy.trimAscii()
        let withoutScheme = if (trimmed.startsWith("http://")) {
            trimmed[7..]
        } else if (trimmed.startsWith("https://")) {
            trimmed[8..]
        } else {
            trimmed
        }
        let authority = match (withoutScheme.indexOf("/")) {
            case Some(idx) => withoutScheme[..idx]
            case None => withoutScheme
        }
        var hostPort = authority
        var auth = ""
        match (authority.lastIndexOf("@")) {
            case Some(idx) =>
                auth = authority[..idx]
                hostPort = authority[idx + 1..]
            case None => ()
        }
        var host = hostPort
        var port: UInt16 = 80u16
        match (hostPort.lastIndexOf(":")) {
            case Some(idx) =>
                host = hostPort[..idx]
                let parsed = Int64.parse(hostPort[idx + 1..])
                if (parsed > 0 && parsed <= 65535) {
                    port = UInt16(parsed)
                }
            case None => ()
        }
        if (host.trimAscii().isEmpty()) {
            throw Exception("invalid telegram proxy host")
        }
        TelegramProxyEndpoint(host.trimAscii(), port, auth: auth)
    }

    private func openHttpConnectTunnel(
        socket: TcpSocket,
        targetHost: String,
        targetPort: UInt16,
        proxyEndpoint: TelegramProxyEndpoint
    ): Unit {
        var request =
            "CONNECT ${targetHost}:${targetPort} HTTP/1.1\r\n" +
                "Host: ${targetHost}:${targetPort}\r\n" +
                "Proxy-Connection: Keep-Alive\r\n"
        if (!proxyEndpoint.auth.isEmpty()) {
            request += "Proxy-Authorization: Basic ${toBase64String(proxyEndpoint.auth.toArray())}\r\n"
        }
        request += "\r\n"
        socket.write(request.toArray())
        let response = this.readHttpConnectResponse(socket)
        let firstLine = match (response.indexOf("\r\n")) {
            case Some(idx) => response[..idx]
            case None => response
        }
        if (!firstLine.contains(" 200 ")) {
            throw Exception("Telegram proxy CONNECT failed: ${firstLine}")
        }
    }

    private func readHttpConnectResponse(socket: TcpSocket): String {
        let output = ArrayList<Byte>()
        let buffer = Array<Byte>(1024, repeat: 0)
        var total: Int64 = 0
        while (total < 8192) {
            let n = socket.read(buffer)
            if (n <= 0) {
                break
            }
            output.add(all: buffer[..n])
            total += n
            let text = String.fromUtf8(output.toArray())
            if (text.contains("\r\n\r\n")) {
                return text
            }
        }
        String.fromUtf8(output.toArray())
    }

    private func buildNativeHttpRequest(request: TelegramTransportRequest, headers: HashMap<String, String>): HttpRequest {
        let builder = HttpRequestBuilder().url(request.url)
        if (request.method == "POST") {
            builder.post()
            builder.body(request.body)
        } else {
            builder.get()
        }
        for ((key, value) in headers) {
            builder.header(key, value)
        }
        builder.build()
    }

    private func classifyStatus(status: Int64): String {
        if (status == 401) {
            return "unauthorized"
        }
        if (status == 409) {
            return "conflict"
        }
        if (status == 429) {
            return "rate-limit"
        }
        if (status == 408 || status == 500 || status == 502 || status == 503 || status == 504) {
            return "retryable-status"
        }
        "http-status"
    }

    public func debugBuildRequestForTest(method: String, url: String, body!: String = ""): TelegramTransportRequest {
        TelegramTransportRequest(
            method,
            url,
            context: "debug",
            body: body,
            proxy: this.proxy,
            timeoutSeconds: this.timeoutSeconds
        )
    }

    public func debugEffectiveProxyForTest(): String {
        this.proxy
    }

    public func debugEffectiveTimeoutSecondsForTest(): Int64 {
        this.timeoutSeconds
    }

    public func debugProxyRouteForTest(url: String): String {
        if (this.proxy.isEmpty()) {
            return "none"
        }
        if (url.startsWith("https")) {
            return "httpConnectTunnel"
        }
        "httpProxy"
    }

    public func debugUsesCustomConnectorForTest(): Bool {
        this.proxy.isEmpty()
    }

    public func debugClassifyStatusForTest(status: Int64): String {
        this.classifyStatus(status)
    }

    public func debugClassifyExceptionForTest(message: String): String {
        this.classifyException(message)
    }

    public func debugUsesNativeHttpTransportForTest(): Bool {
        true
    }

    public func redactUrl(url: String): String {
        let marker = "/bot"
        match (url.indexOf(marker)) {
            case Some(idx) =>
                let tokenStart = idx + marker.size
                let rest = url[tokenStart..]
                match (rest.indexOf("/")) {
                    case Some(endIdx) =>
                        url[..tokenStart] + "<redacted>" + rest[endIdx..]
                    case None => url[..tokenStart] + "<redacted>"
                }
            case None => url
        }
    }

    private func classifyException(message: String): String {
        let lower = message.toAsciiLower()
        if (lower.contains("timeout") || lower.contains("timed out")) {
            return "timeout"
        }
        if (lower.contains("unauthorized") || lower.contains("401")) {
            return "unauthorized"
        }
        if (lower.contains("too many requests") || lower.contains("429")) {
            return "rate-limit"
        }
        if (lower.contains("conflict") || lower.contains("409")) {
            return "conflict"
        }
        "exception"
    }
}
