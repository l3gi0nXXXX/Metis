package metis.gateway.channels.telegram

import magic.jsonable.*

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{File, Path}
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
    public let bodyBytes: Array<Byte>
    public let contentType: String
    public let proxy: String
    public let timeoutSeconds: Int64
    public let autoSelectFamily: Bool
    public let dnsResultOrder: String

    public init(
        method: String,
        url: String,
        context!: String = "",
        accept!: String = "application/json",
        body!: String = "",
        bodyBytes!: Array<Byte> = [],
        contentType!: String = "",
        proxy!: String = "",
        timeoutSeconds!: Int64 = 30,
        autoSelectFamily!: Bool = true,
        dnsResultOrder!: String = "ipv4first"
    ) {
        this.method = method
        this.url = url
        this.context = context
        this.accept = accept
        this.body = body
        this.bodyBytes = bodyBytes
        this.contentType = contentType
        this.proxy = proxy
        this.timeoutSeconds = timeoutSeconds
        this.autoSelectFamily = autoSelectFamily
        this.dnsResultOrder = dnsResultOrder
    }
}

public class TelegramTransportResponse {
    public let ok: Bool
    public let body: String
    public let bodyBytes: Array<Byte>
    public let error: String
    public let outcome: String
    public let statusCode: Int64

    public init(
        ok: Bool,
        body!: String = "",
        bodyBytes!: Array<Byte> = [],
        error!: String = "",
        outcome!: String = "",
        statusCode!: Int64 = 0
    ) {
        this.ok = ok
        this.body = body
        this.bodyBytes = bodyBytes
        this.error = error
        this.outcome = outcome
        this.statusCode = statusCode
    }
}

public class TelegramMultipartFile {
    public let fieldName: String
    public let fileName: String
    public let filePath: String
    public let bytes: Array<Byte>

    public init(fieldName: String, fileName!: String = "", filePath!: String = "", bytes!: Array<Byte> = []) {
        this.fieldName = fieldName.trimAscii()
        this.fileName = fileName.trimAscii()
        this.filePath = filePath.trimAscii()
        this.bytes = bytes
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
    private let insecureSkipTlsVerify: Bool
    private let dangerouslyAllowPrivateNetwork: Bool
    private let autoSelectFamily: Bool
    private let dnsResultOrder: String

    public init(
        proxy!: String = "",
        timeoutSeconds!: Int64 = 30,
        insecureSkipTlsVerify!: Bool = false,
        dangerouslyAllowPrivateNetwork!: Bool = false,
        autoSelectFamily!: Bool = true,
        dnsResultOrder!: String = "ipv4first"
    ) {
        this.proxy = proxy.trimAscii()
        this.timeoutSeconds = if (timeoutSeconds > 0) { timeoutSeconds } else { 30 }
        this.insecureSkipTlsVerify = insecureSkipTlsVerify
        this.dangerouslyAllowPrivateNetwork = dangerouslyAllowPrivateNetwork
        this.autoSelectFamily = autoSelectFamily
        this.dnsResultOrder = if (dnsResultOrder.trimAscii().isEmpty()) { "ipv4first" } else { dnsResultOrder.trimAscii().toAsciiLower() }
    }

    public func get(url: String, accept!: String = "application/json", context!: String = "get"): TelegramTransportResponse {
        let request = TelegramTransportRequest(
            "GET",
            url,
            context: context,
            accept: accept,
            proxy: this.proxy,
            timeoutSeconds: this.timeoutSeconds,
            autoSelectFamily: this.autoSelectFamily,
            dnsResultOrder: this.dnsResultOrder
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
            contentType: "application/json; charset=utf-8",
            proxy: this.proxy,
            timeoutSeconds: this.timeoutSeconds,
            autoSelectFamily: this.autoSelectFamily,
            dnsResultOrder: this.dnsResultOrder
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

    public func postMultipartFile(
        url: String,
        fields: HashMap<String, String>,
        fileField: String,
        filePath: String,
        context!: String = "postMultipartFile"
    ): TelegramTransportResponse {
        let file = TelegramMultipartFile(fileField, filePath: filePath)
        this.postMultipartFiles(url, fields, [file], context: context)
    }

    public func postMultipartFiles(
        url: String,
        fields: HashMap<String, String>,
        files: Array<TelegramMultipartFile>,
        context!: String = "postMultipartFiles"
    ): TelegramTransportResponse {
        let boundary = "metis-telegram-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        let bodyBytes = this.buildMultipartFilesBody(boundary, fields, files)
        let request = TelegramTransportRequest(
            "POST",
            url,
            context: context,
            accept: "application/json",
            bodyBytes: bodyBytes,
            contentType: "multipart/form-data; boundary=${boundary}",
            proxy: this.proxy,
            timeoutSeconds: this.timeoutSeconds,
            autoSelectFamily: this.autoSelectFamily,
            dnsResultOrder: this.dnsResultOrder
        )
        match (telegramTransportRunnerOverride) {
            case Some(runner) => return runner(request)
            case None => ()
        }
        let headers = HashMap<String, String>()
        headers["Accept"] = "application/json"
        headers["Content-Type"] = request.contentType
        this.sendNative(request, headers)
    }

    private func sendNative(
        request: TelegramTransportRequest,
        headers: HashMap<String, String>
    ): TelegramTransportResponse {
        try {
            let urlPolicyError = this.validateTelegramRequestUrl(request.url)
            if (!urlPolicyError.isEmpty()) {
                return TelegramTransportResponse(false, error: urlPolicyError, outcome: "blocked-url", statusCode: 0)
            }
            let client = this.buildNativeHttpClient(request.url)
            try {
                let response = client.send(this.buildNativeHttpRequest(request, headers))
                let status = Int64(response.status)
                let responseBytes = ArrayList<Byte>()
                let responseBuffer = Array<Byte>(8192, repeat: 0)
                while (true) {
                    let n = response.body.read(responseBuffer)
                    if (n <= 0) {
                        break
                    }
                    responseBytes.add(all: responseBuffer[..n])
                }
                let isBinaryResponse = request.context == "downloadFile" || request.accept == "*/*"
                var responseBody = ""
                var decodeError = ""
                if (!isBinaryResponse) {
                    try {
                        responseBody = String.fromUtf8(responseBytes.toArray())
                    } catch (e: Exception) {
                        decodeError = e.message.trimAscii()
                    }
                }
                if (!decodeError.isEmpty()) {
                    return TelegramTransportResponse(
                        false,
                        error: "invalid utf8 response body: ${decodeError}",
                        outcome: "invalid-response-body",
                        statusCode: status
                    )
                }
                if (status >= 200 && status < 300) {
                    return TelegramTransportResponse(true, body: responseBody, bodyBytes: responseBytes.toArray(), outcome: "ok", statusCode: status)
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

    private func validateTelegramRequestUrl(url: String): String {
        let trimmed = url.trimAscii()
        let lower = trimmed.toAsciiLower()
        if (!(lower.startsWith("https://") || lower.startsWith("http://"))) {
            return "telegram transport blocked non-http url"
        }
        let parsed = try {
            URL.parse(trimmed)
        } catch (_e: Exception) {
            return "telegram transport blocked invalid url"
        }
        let host = parsed.hostName.trimAscii().toAsciiLower()
        if (host.isEmpty()) {
            return "telegram transport blocked url without host"
        }
        if (!this.dangerouslyAllowPrivateNetwork && this.telegramHostLooksPrivate(host)) {
            return "telegram transport blocked private-network host: ${host}"
        }
        ""
    }

    private func telegramHostLooksPrivate(host: String): Bool {
        let h = host.trimAscii().toAsciiLower()
        if (h == "localhost" || h == "0.0.0.0" || h == "127.0.0.1" || h == "::1" || h == "[::1]") {
            return true
        }
        if (h.startsWith("127.") || h.startsWith("10.") || h.startsWith("192.168.") || h.startsWith("169.254.")) {
            return true
        }
        if (h.startsWith("172.")) {
            let parts = h.split(".")
            if (parts.size >= 2) {
                try {
                    let second = Int64.parse(parts[1])
                    if (second >= 16 && second <= 31) {
                        return true
                    }
                } catch (_e: Exception) {
                    ()
                }
            }
        }
        h.startsWith("fc") || h.startsWith("fd") || h.startsWith("fe80:")
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
            if (this.insecureSkipTlsVerify) {
                tlsConfig.verifyMode = TrustAll
            }
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
            if (!request.bodyBytes.isEmpty()) {
                builder.body(request.bodyBytes)
            } else {
                builder.body(request.body)
            }
        } else {
            builder.get()
        }
        for ((key, value) in headers) {
            builder.header(key, value)
        }
        builder.build()
    }

    private func buildMultipartBody(
        boundary: String,
        fields: HashMap<String, String>,
        fileField: String,
        filePath: String
    ): Array<Byte> {
        this.buildMultipartFilesBody(boundary, fields, [TelegramMultipartFile(fileField, filePath: filePath)])
    }

    private func buildMultipartFilesBody(
        boundary: String,
        fields: HashMap<String, String>,
        files: Array<TelegramMultipartFile>
    ): Array<Byte> {
        let out = ArrayList<Byte>()
        for ((key, value) in fields) {
            out.add(all: "--${boundary}\r\n".toArray())
            out.add(all: "Content-Disposition: form-data; name=\"${this.escapeMultipartName(key)}\"\r\n\r\n".toArray())
            out.add(all: value.toArray())
            out.add(all: "\r\n".toArray())
        }
        for (file in files) {
            if (file.fieldName.isEmpty()) {
                continue
            }
            let normalizedPath = this.normalizeLocalFilePath(file.filePath)
            let filename = if (!file.fileName.isEmpty()) {
                file.fileName
            } else if (!normalizedPath.isEmpty()) {
                this.fileNameForMultipart(normalizedPath)
            } else {
                "upload.bin"
            }
            out.add(all: "--${boundary}\r\n".toArray())
            out.add(all: "Content-Disposition: form-data; name=\"${this.escapeMultipartName(file.fieldName)}\"; filename=\"${this.escapeMultipartName(filename)}\"\r\n".toArray())
            out.add(all: "Content-Type: application/octet-stream\r\n\r\n".toArray())
            if (!file.bytes.isEmpty()) {
                out.add(all: file.bytes)
            } else if (!normalizedPath.isEmpty()) {
                out.add(all: File.readFrom(Path(normalizedPath)))
            }
            out.add(all: "\r\n".toArray())
        }
        out.add(all: "--${boundary}--\r\n".toArray())
        out.toArray()
    }

    private func normalizeLocalFilePath(pathText: String): String {
        let trimmed = pathText.trimAscii()
        if (trimmed.toAsciiLower().startsWith("file://")) {
            return trimmed[7..]
        }
        trimmed
    }

    private func fileNameForMultipart(pathText: String): String {
        let normalized = pathText.trimAscii()
        match (normalized.lastIndexOf("/")) {
            case Some(idx) =>
                let name = normalized[idx + 1..].trimAscii()
                if (name.isEmpty()) { "upload.bin" } else { name }
            case None =>
                if (normalized.isEmpty()) { "upload.bin" } else { normalized }
        }
    }

    private func escapeMultipartName(raw: String): String {
        raw.replace("\\", "\\\\").replace("\"", "\\\"").replace("\r", "").replace("\n", "")
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

    public func debugValidateRequestUrlForTest(url: String): String {
        this.validateTelegramRequestUrl(url)
    }

    public func debugClassifyStatusForTest(status: Int64): String {
        this.classifyStatus(status)
    }

    public func debugClassifyExceptionForTest(message: String): String {
        this.classifyException(message)
    }

    public func debugBuildMultipartFilesBodyForTest(fields: HashMap<String, String>, files: Array<TelegramMultipartFile>): String {
        String.fromUtf8(this.buildMultipartFilesBody("metis-test-boundary", fields, files))
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
