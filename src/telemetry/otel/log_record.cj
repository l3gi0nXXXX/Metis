package metis.telemetry.otel

import std.collection.*
import std.time.*

/**
 * Immutable log entry representation that can be converted into OTLP wire format.
 */
public class LogRecord {
    public let timestamp: Int64
    public let observedTimestamp: Int64
    public let severity: LogSeverity
    public let body: AttributeValue
    public let attributes: HashMap<String, AttributeValue>
    public let droppedAttributesCount: Int64
    public let flags: Int64
    public let traceId: String
    public let spanId: String
    public let traceState: String

    public init(body: AttributeValue,
                severity!: LogSeverity = LogSeverity.Info,
                timestamp!: Option<Int64> = None,
                attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(),
                traceId!: String = "",
                spanId!: String = "",
                traceState!: String = "",
                flags!: Int64 = 0,
                droppedAttributesCount!: Int64 = 0) {
        let now = DateTime.now().toUnixTimeStamp().toNanoseconds()
        match (timestamp) {
            case Some(explicit) => this.timestamp = explicit
            case None => this.timestamp = now
        }
        this.observedTimestamp = now
        this.severity = severity
        this.body = body
        this.attributes = HashMap<String, AttributeValue>()
        for ((key, value) in attributes) {
            this.attributes[key] = value
        }
        this.traceId = traceId
        this.spanId = spanId
        this.traceState = traceState
        this.flags = flags
        this.droppedAttributesCount = droppedAttributesCount
    }

    public func toOtlp(): OtlpLogRecord {
        var record = OtlpLogRecord()
        record.timeUnixNano = timestamp.toString()
        record.observedTimeUnixNano = observedTimestamp.toString()
        record.severityNumber = severityNumberFor(severity)
        record.severityText = severityTextFor(severity)
        record.body = OtlpJsonUtils.toAnyValue(body)
        record.attributes = OtlpJsonUtils.mapAttributes(attributes)
        record.droppedAttributesCount = droppedAttributesCount
        record.flags = flags.toString()
        record.traceId = OtlpJsonUtils.normalizeTraceId(traceId)
        record.spanId = OtlpJsonUtils.normalizeSpanId(spanId)
        record.traceState = traceState
        return record
    }

    private func severityNumberFor(severity: LogSeverity): String {
        match (severity) {
            case LogSeverity.Trace => return "SEVERITY_NUMBER_TRACE"
            case LogSeverity.Debug => return "SEVERITY_NUMBER_DEBUG"
            case LogSeverity.Info => return "SEVERITY_NUMBER_INFO"
            case LogSeverity.Warn => return "SEVERITY_NUMBER_WARN"
            case LogSeverity.Error => return "SEVERITY_NUMBER_ERROR"
            case LogSeverity.Fatal => return "SEVERITY_NUMBER_FATAL"
        }
    }

    private func severityTextFor(severity: LogSeverity): String {
        match (severity) {
            case LogSeverity.Trace => return "TRACE"
            case LogSeverity.Debug => return "DEBUG"
            case LogSeverity.Info => return "INFO"
            case LogSeverity.Warn => return "WARN"
            case LogSeverity.Error => return "ERROR"
            case LogSeverity.Fatal => return "FATAL"
        }
    }
}
