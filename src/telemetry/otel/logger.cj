package metis.telemetry.otel

import std.collection.*

/**
 * Simple in-memory logger that batches records until the provider drains them.
 */
public class Logger {
    public let name: String
    public let version: String
    let records: ArrayList<LogRecord>

    public init(name: String, version!: String = "1.0.0") {
        this.name = name
        this.version = version
        this.records = ArrayList<LogRecord>()
    }

    public func log(message: String,
                    severity!: LogSeverity = LogSeverity.Info,
                    attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(),
                    timestamp!: Option<Int64> = None,
                    traceId!: String = "",
                    spanId!: String = "",
                    traceState!: String = "",
                    flags!: Int64 = 0): Unit {
        logValue(AttributeValue.StringValue(message),
                 severity: severity,
                 attributes: attributes,
                 timestamp: timestamp,
                 traceId: traceId,
                 spanId: spanId,
                 traceState: traceState,
                 flags: flags)
    }

    public func logValue(body: AttributeValue,
                         severity!: LogSeverity = LogSeverity.Info,
                         attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(),
                         timestamp!: Option<Int64> = None,
                         traceId!: String = "",
                         spanId!: String = "",
                         traceState!: String = "",
                         flags!: Int64 = 0): Unit {
        let record = LogRecord(body,
                               severity: severity,
                               timestamp: timestamp,
                               attributes: attributes,
                               traceId: traceId,
                               spanId: spanId,
                               traceState: traceState,
                               flags: flags)
        records.add(record)
    }

    public func collectLogRecords(): ArrayList<LogRecord> {
        let copy = ArrayList<LogRecord>()
        copy.add(all: records)
        // Clear buffered records so a subsequent collection exports only new items.
        records.clear()
        return copy
    }

    public func collect(): ArrayList<OtlpLogRecord> {
        let otlpRecords = ArrayList<OtlpLogRecord>()
        for (record in records) {
            otlpRecords.add(record.toOtlp())
        }
        // Clear buffered records so a subsequent collection exports only new items.
        records.clear()
        return otlpRecords
    }
}
