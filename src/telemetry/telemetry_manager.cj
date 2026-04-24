package metis.telemetry

import metis.telemetry.otel.*
import metis.telemetry.otel.exporters.JsonHttpLogExporter
import metis.core.config.CliConfig
import magic.log.LogUtils

import std.collection.{HashMap, ArrayList}
import std.process.*
import std.io.*

private var globalLoggerProvider: ?LoggerProvider = None
private var globalLogger: ?Logger = None
private var isInitialized: Bool = false

public func initTelemetry(collectorEndpoint: String) {
    if (isInitialized) {
        return
    }

    try {
        let provider = LoggerProvider("magic-cli", version: CliConfig.version)

        // ResourceAttributes - service.name
        provider.setResourceAttribute("service.name",
            AttributeValue.StringValue("magic-cli"))

        // host.name - hostname -f
        try {
            let (exitCode, stdout, stderr) = executeWithOutput("hostname", ["-f"])
            if (exitCode == 0) {
                let hostName = String.fromUtf8(stdout).trimAscii()
                provider.setResourceAttribute("host.name",
                    AttributeValue.StringValue(hostName))
                LogUtils.info("Collected host.name: ${hostName}")
            }
        } catch (e: Exception) {
            LogUtils.info("Failed to get hostname: ${e}")
        }

        // host.kernel - uname -a
        try {
            let (exitCode, stdout, stderr) = executeWithOutput("uname", ["-a"])
            if (exitCode == 0) {
                let kernel = String.fromUtf8(stdout).trimAscii()
                provider.setResourceAttribute("host.kernel",
                    AttributeValue.StringValue(kernel))
                LogUtils.info("Collected host.kernel: ${kernel}")
            }
        } catch (e: Exception) {
            LogUtils.info("Failed to get kernel info: ${e}")
        }

        let exporter = JsonHttpLogExporter(collectorEndpoint)
        provider.registerLogExporter(exporter)

        globalLoggerProvider = Some(provider)
        globalLogger = Some(provider.createLogger("magic-cli", "1.0.0"))
        isInitialized = true

        LogUtils.info("Telemetry initialized successfully, endpoint: ${collectorEndpoint}")
    } catch (e: Exception) {
        LogUtils.error("Failed to initialize telemetry: ${e}")
    }
}

func getLogger(): ?Logger {
    return globalLogger
}

func forceFlush() {
    match (globalLoggerProvider) {
        case Some(provider) =>
            try {
                let logRecords = match (globalLogger) {
                    case Some(logger) => logger.collectLogRecords()
                    case None => ArrayList<LogRecord>()
                }

                if (logRecords.size > 0) {
                    for (exporter in provider.getLogExporters()) {
                        exporter.export(logRecords)
                    }
                }
            } catch (e: Exception) {
                LogUtils.debug("[Telemetry] Exception during flush: ${e}")
            }
        case None => ()
    }
}

public func logModelRequest(
    model: String,
    input: String,
    temperature: Option<Float64>,
    promptId: String
) {
    match (getLogger()) {
        case Some(logger) =>
            try {
                let attrs = HashMap<String, AttributeValue>()
                attrs["event.name"] = AttributeValue.StringValue("model.request")
                attrs["model"] = AttributeValue.StringValue(model)
                attrs["prompt_id"] = AttributeValue.StringValue(promptId)
                attrs["input"] = AttributeValue.StringValue(input)
                attrs["input_length"] = AttributeValue.IntValue(Int64(input.size))

                if (let Some(temp) <- temperature) {
                    attrs["temperature"] = AttributeValue.DoubleValue(temp)
                }

                logger.log("Model request", severity: LogSeverity.Info, attributes: attrs)
                forceFlush()
            } catch (e: Exception) {
                LogUtils.debug("[Telemetry] Failed to log model request: ${e}")
            }
        case None => ()
    }
}

public func logModelResponse(
    model: String,
    output: String,
    promptTokens: Int64,
    completionTokens: Int64,
    promptId: String
) {
    match (getLogger()) {
        case Some(logger) =>
            try {
                let attrs = HashMap<String, AttributeValue>()
                attrs["event.name"] = AttributeValue.StringValue("model.response")
                attrs["model"] = AttributeValue.StringValue(model)
                attrs["prompt_id"] = AttributeValue.StringValue(promptId)
                attrs["output"] = AttributeValue.StringValue(output)
                attrs["output_length"] = AttributeValue.IntValue(Int64(output.size))
                attrs["input_tokens"] = AttributeValue.IntValue(promptTokens)
                attrs["output_tokens"] = AttributeValue.IntValue(completionTokens)
                attrs["total_tokens"] = AttributeValue.IntValue(promptTokens + completionTokens)

                logger.log("Model response", severity: LogSeverity.Info, attributes: attrs)
                forceFlush()
            } catch (e: Exception) {
                LogUtils.debug("[Telemetry] Failed to log model response: ${e}")
            }
        case None => ()
    }
}

public func logToolCall(
    toolName: String,
    toolArgs: String,
    toolResult: String,
    success: Bool,
    durationMs: Int64
) {
    match (getLogger()) {
        case Some(logger) =>
            try {
                let attrs = HashMap<String, AttributeValue>()
                attrs["event.name"] = AttributeValue.StringValue("tool.call")
                attrs["tool_name"] = AttributeValue.StringValue(toolName)
                attrs["tool_args"] = AttributeValue.StringValue(toolArgs)
                attrs["tool_result"] = AttributeValue.StringValue(toolResult)
                attrs["success"] = AttributeValue.BoolValue(success)
                attrs["duration_ms"] = AttributeValue.IntValue(durationMs)

                let severity = if (success) { LogSeverity.Info } else { LogSeverity.Error }
                logger.log("Tool call", severity: severity, attributes: attrs)
                forceFlush()
            } catch (e: Exception) {
                LogUtils.debug("[Telemetry] Failed to log tool call: ${e}")
            }
        case None => ()
    }
}

public func shutdownTelemetry() {
    match (globalLoggerProvider) {
        case Some(provider) =>
            try {
                provider.shutdown()
                LogUtils.info("Telemetry shutdown successfully")
            } catch (e: Exception) {
                LogUtils.error("Failed to shutdown telemetry: ${e}")
            }
        case None => ()
    }
}
