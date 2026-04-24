package metis.lsp

import magic.dsl.jsonable
import magic.log.LogUtils

import std.fs.{File, Path}
import std.io.*
import std.process.*
import std.convert.*
import std.collection.*
import std.collection.concurrent.ConcurrentHashMap
import std.unicode.*
import stdx.encoding.json.*

private enum RPCMessageType {
    | Request(LSPRequest)
    | Response(LSPResponse)
    | Notification(LSPNotification)
}

/**
 * JSON-RPC 2.0 Client for LSP communication
 */
public class JSONRPCClient {
    private var process: SubProcess
    private var reader: StringReader<InputStream>
    private var writer: StringWriter<OutputStream>
    private var nextId: Int64 = 1
    private let pendingRequests = ConcurrentHashMap<Int64, Promise<JsonValue>>()
    private var workerFuture: Option<Future<Unit>> = None

    public init(serverPath: String, serverArgs!: Array<String> = Array<String>()) {
        try {
            this.process = launch(
                serverPath, serverArgs,
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            this.reader = StringReader<InputStream>(this.process.stdOutPipe)
            this.writer = StringWriter(this.process.stdInPipe)
            LogUtils.info("JSON-RPC client started for server: ${serverPath}")
        } catch (ex: Exception) {
            LogUtils.error("Failed to start JSON-RPC server ${serverPath}: ${ex}")
            throw Exception("Failed to start LSP server: ${ex.message}")
        }
        this.workerFuture = spawn {
            this.doReceiving()
        }
    }

    public func sendRequest(method: String, params!: Option<JsonObject> = None): JsonValue {
        let requestId = this.nextId
        this.nextId = this.nextId + 1
        let request = LSPRequest(
            id: requestId,
            method: method,
            params: params
        )

        let requestJson = request.toJsonValue()
        let requestStr = requestJson.toString()
        LogUtils.debug("Sending request: ${requestStr}")

        // Send with LSP protocol headers
        let contentBytes = requestStr.toArray()
        let header = "Content-Length: ${contentBytes.size}\r\n\r\n"

        // Write headers and content
        try {
            this.writer.write(header)
            this.writer.write(requestStr)
            this.writer.flush()
        } catch (ex: Exception) {
            LogUtils.error("Failed to send JSON-RPC request: ${ex}")
            throw Exception("Failed to send request: ${ex.message}")
        }

        // Read response:
        // 1. Register the pending request
        let promise = Promise<JsonValue>()
        this.pendingRequests.add(requestId, promise)
        // 2. Wait for the response
        let resp = promise.get()
        LogUtils.debug("Received response: ${resp.toJsonString()}")
        return resp
    }

    public func sendNotification(method: String, params!: Option<JsonObject> = None): Unit {
        let notification = LSPNotification(
            method: method,
            params: params
        )

        let notificationJson = notification.toJsonValue()
        let notificationStr = notificationJson.toString()
        LogUtils.debug("Sending notification: ${notificationStr}")

        // Send with LSP protocol headers
        let contentBytes = notificationStr.toArray()
        let header = "Content-Length: ${contentBytes.size}\r\n\r\n"

        try {
            this.writer.write(header)
            this.writer.write(notificationStr)
            this.writer.flush()
        } catch (ex: Exception) {
            LogUtils.error("Failed to send JSON-RPC notification: ${ex}")
            throw Exception("Failed to send notification: ${ex.message}")
        }
    }

    private func doReceiving(): Unit {
        while (true) {
            if (Thread.currentThread.hasPendingCancellation) {
                break
            }
            let message = this.readMessage()
            let rpcMessage = this.parseMessage(message)
            this.handleMessage(rpcMessage)
        }
    }

    private func readMessage(): JsonValue {
        try {
            // Read headers first
            var contentLength: Option<Int64> = None

            while (true) {
                let line = this.readLine()
                if (line.isEmpty()) {
                    break
                }

                if (line.startsWith("Content-Length:")) {
                    let lengthStr = line["Content-Length:".size..].trimAsciiStart()
                    contentLength = Int64.parse(lengthStr)
                }
            }

            match (contentLength) {
                case Some(length) =>
                    // Read the JSON content
                    let content = this.readContent(length)
                    LogUtils.trace("Received content: ${content}")
                    return JsonValue.fromStr(content)
                case _ =>
                    throw Exception("Missing Content-Length header in LSP response")
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to read JSON-RPC response: ${ex}")
            throw Exception("Failed to read response: ${ex.message}")
        }
    }

    private func parseMessage(jsonValue: JsonValue): RPCMessageType {
        // Validate JSON-RPC version
        let jo = jsonValue.asObject()

        if (((jo.get("jsonrpc")?.asString())?.getValue() ?? "") != "2.0") {
            throw Exception("Unsupported JSON-RPC version")
        }

        // Determine message type
        if (jo.containsKey("method")) {
            if (jo.containsKey("id")) {
                return RPCMessageType.Request(LSPRequest.fromJsonValue(jsonValue))
            } else {
                return RPCMessageType.Notification(LSPNotification.fromJsonValue(jsonValue))
            }
        } else if (jo.containsKey("id")) {
            return RPCMessageType.Response(LSPResponse.fromJsonValue(jsonValue))
        } else {
            throw Exception("Unknown message type: {data}")
        }
    }

    // Handle an incoming message
    private func handleMessage(message: RPCMessageType): Unit {
        match (message) {
            case RPCMessageType.Request(request) =>
                this.handleServerRequest(request)
            case RPCMessageType.Response(response) =>
                this.handleServerResponse(response)
            case RPCMessageType.Notification(notification) =>
                this.handleServerNotification(notification)
        }
    }

    // Handle a response message
    private func handleServerResponse(response: LSPResponse): Unit {
        let requestId = response.id

        if (this.pendingRequests.contains(requestId)) {
            let promise = this.pendingRequests[requestId]
            this.pendingRequests.remove(requestId)
            if (let Some(error) <- response.error) {
                LogUtils.error("LSP Error ${error.code}: ${error.message}")
                promise.reject(error.toJsonValue().toJsonString())
            } else {
                // Send the result to the pending request
                let result = match (response.result) {
                    case Some(result) => result.toJsonValue()
                    case _ => JsonValue.fromStr("{}")
                }
                promise.resolve(result)
            }
        } else {
            LogUtils.error("Received response for unknown request ID: ${requestId}")
            throw UnsupportedException("Unreachable")
        }
    }

    // Handle a notification message
    private func handleServerNotification(notification: LSPNotification): Unit {
        // For now, we'll just log unknown server notification
        LogUtils.info("Received server notification: ${notification.method}")
    }

    // Handle a request from the server
    private func handleServerRequest(request: LSPRequest): Unit {
        // For now, we'll just log unknown server requests
        LogUtils.info("Received server request: ${request.method}")
    }

    private func readLine(): String {
        return try {
            this.reader.readln() ?? String.empty
        } catch (ex: Exception) {
            String.empty
        }
    }

    private func readContent(length: Int64): String {
        let contentBuilder = StringBuilder()
        var bytesRead: Int64 = 0

        while (bytesRead < length) {
            let charOption = try {
                this.reader.read()
            } catch (ex: Exception) {
                break
            }
            match (charOption) {
                case Some(char) =>
                    contentBuilder.append(char)
                    bytesRead++
                case _ => break
            }
        }

        return contentBuilder.toString()
    }

    public func close(): Unit {
        try {
            // Stop the worker thread
            this.workerFuture?.cancel()
            // Send shutdown request
            this.sendRequest("shutdown", params: None)
            // Send exit notification
            this.sendNotification("exit")

            // Wait for process to finish
            let _ = this.process.wait()
            LogUtils.info("JSON-RPC client closed")
        } catch (ex: Exception) {
            LogUtils.error("Error during JSON-RPC client shutdown: ${ex}")
        }
    }
}