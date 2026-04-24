package metis.telemetry.otel

import std.collection.*

// Simple metric data container for export
public class MetricData {
    public let name: String
    public let description: String
    public let unit: String
    public let value: Float64
    public let attributes: HashMap<String, AttributeValue>
    public let timestamp: Int64

    public init(name: String, description: String, unit: String, value: Float64, attributes: HashMap<String, AttributeValue>, timestamp: Int64) {
        this.name = name
        this.description = description
        this.unit = unit
        this.value = value
        this.attributes = attributes
        this.timestamp = timestamp
    }
}

public enum SpanExportResult {
    | Success
    | Failure
}

public interface SpanExporter {
    func export(spans: ArrayList<Span>): Bool
    func shutdown(): Unit
    func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit
}

public interface MetricExporter {
    func export(metrics: ArrayList<MetricData>): Bool
    func shutdown(): Unit
    func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit
}

public enum LogExportResult {
    | Success
    | Failure
}

public interface LogExporter {
    func export(logRecords: ArrayList<LogRecord>): Bool
    func shutdown(): Unit
    func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit
}
