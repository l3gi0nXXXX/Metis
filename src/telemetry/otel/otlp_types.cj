package metis.telemetry.otel

import magic.dsl.jsonable
import magic.jsonable.*

import std.collection.*
import stdx.encoding.json.*

@jsonable
public struct OtlpAnyValue {
    public var stringValue: Option<String> = None
    public var boolValue: Option<Bool> = None
    public var intValue: Option<String> = None
    public var doubleValue: Option<Float64> = None
    public var arrayValue: Option<OtlpArrayValue> = None
    public var kvlistValue: Option<OtlpKeyValueList> = None
    public var bytesValue: Option<String> = None
}

@jsonable
public struct OtlpArrayValue {
    public var values: ArrayList<OtlpAnyValue> = ArrayList<OtlpAnyValue>()
}

@jsonable
public struct OtlpKeyValue {
    public var key: String
    public var value: OtlpAnyValue
}

@jsonable
public struct OtlpKeyValueList {
    public var values: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
}

@jsonable
public struct OtlpStatus {
    public var code: String = "STATUS_CODE_UNSET"
    public var message: String = ""
}

@jsonable
public struct OtlpEvent {
    public var name: String
    public var timeUnixNano: String
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var droppedAttributesCount: Int64 = 0
}

@jsonable
public struct OtlpLink {
    public var traceId: String
    public var spanId: String
    public var traceState: String = ""
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var droppedAttributesCount: Int64 = 0
}

@jsonable
public struct OtlpSpan {
    public var traceId: String
    public var spanId: String
    public var parentSpanId: String = ""
    public var name: String
    public var kind: String
    public var startTimeUnixNano: String
    public var endTimeUnixNano: String
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var droppedAttributesCount: Int64 = 0
    public var events: ArrayList<OtlpEvent> = ArrayList<OtlpEvent>()
    public var droppedEventsCount: Int64 = 0
    public var status: OtlpStatus = OtlpStatus()
    public var links: ArrayList<OtlpLink> = ArrayList<OtlpLink>()
    public var droppedLinksCount: Int64 = 0
    public var traceState: String = ""
}

@jsonable
public struct OtlpInstrumentationScope {
    public var name: String = ""
    public var version: String = ""
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var droppedAttributesCount: Int64 = 0
}

@jsonable
public struct OtlpScopeSpans {
    public var scope: OtlpInstrumentationScope
    public var spans: ArrayList<OtlpSpan> = ArrayList<OtlpSpan>()
    public var schemaUrl: String = ""
}

@jsonable
public struct OtlpResource {
    public var attributes: Array<OtlpKeyValue> = []
    public var droppedAttributesCount: Int64 = 0
}

@jsonable
public struct OtlpResourceSpans {
    public var resource: OtlpResource
    public var scopeSpans: ArrayList<OtlpScopeSpans> = ArrayList<OtlpScopeSpans>()
    public var schemaUrl: String = ""
}

@jsonable
public struct OtlpExportRequest {
    public var resourceSpans: ArrayList<OtlpResourceSpans> = ArrayList<OtlpResourceSpans>()
}

// Metric signal payloads ------------------------------------------------------------------------

@jsonable
public struct OtlpMetricExportRequest {
    public var resourceMetrics: ArrayList<OtlpResourceMetrics> = ArrayList<OtlpResourceMetrics>()
}

@jsonable
public struct OtlpResourceMetrics {
    public var resource: OtlpResource
    public var scopeMetrics: ArrayList<OtlpScopeMetrics> = ArrayList<OtlpScopeMetrics>()
    public var schemaUrl: String = ""
}

@jsonable
public struct OtlpScopeMetrics {
    public var scope: OtlpInstrumentationScope
    public var metrics: ArrayList<OtlpMetric> = ArrayList<OtlpMetric>()
    public var schemaUrl: String = ""
}

@jsonable
public struct OtlpMetric {
    public var name: String
    public var description: String = ""
    public var unit: String = ""
    public var gauge: Option<OtlpGauge> = None
    public var sum: Option<OtlpSum> = None
    public var histogram: Option<OtlpHistogram> = None
}

@jsonable
public struct OtlpGauge {
    public var dataPoints: ArrayList<OtlpNumberDataPoint> = ArrayList<OtlpNumberDataPoint>()
}

@jsonable
public struct OtlpSum {
    public var dataPoints: ArrayList<OtlpNumberDataPoint> = ArrayList<OtlpNumberDataPoint>()
    public var aggregationTemporality: String = "AGGREGATION_TEMPORALITY_UNSPECIFIED"
    public var isMonotonic: Bool = false
}

@jsonable
public struct OtlpHistogram {
    public var dataPoints: ArrayList<OtlpHistogramDataPoint> = ArrayList<OtlpHistogramDataPoint>()
    public var aggregationTemporality: String = "AGGREGATION_TEMPORALITY_UNSPECIFIED"
}

@jsonable
public struct OtlpNumberDataPoint {
    public var startTimeUnixNano: String = "0"
    public var timeUnixNano: String = "0"
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var flags: String = "0"
    public var asDouble: Option<Float64> = None
    public var asInt: Option<String> = None
    public var exemplars: ArrayList<OtlpExemplar> = ArrayList<OtlpExemplar>()
}

@jsonable
public struct OtlpHistogramDataPoint {
    public var startTimeUnixNano: String = "0"
    public var timeUnixNano: String = "0"
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var flags: String = "0"
    public var count: String = "0"
    public var sum: Float64 = 0.0
    public var bucketCounts: ArrayList<String> = ArrayList<String>()
    public var explicitBounds: ArrayList<Float64> = ArrayList<Float64>()
    public var min: Option<Float64> = None
    public var max: Option<Float64> = None
    public var exemplars: ArrayList<OtlpExemplar> = ArrayList<OtlpExemplar>()
}

@jsonable
public struct OtlpExemplar {
    public var filteredAttributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var timeUnixNano: String = "0"
    public var spanId: String = ""
    public var traceId: String = ""
    public var asDouble: Option<Float64> = None
    public var asInt: Option<String> = None
}

// Log signal payloads ---------------------------------------------------------------------------

@jsonable
public struct OtlpLogExportRequest {
    public var resourceLogs: ArrayList<OtlpResourceLogs> = ArrayList<OtlpResourceLogs>()
}

@jsonable
public struct OtlpResourceLogs {
    public var resource: OtlpResource
    public var scopeLogs: ArrayList<OtlpScopeLogs> = ArrayList<OtlpScopeLogs>()
    public var schemaUrl: String = ""
}

@jsonable
public struct OtlpScopeLogs {
    public var scope: OtlpInstrumentationScope
    public var logRecords: ArrayList<OtlpLogRecord> = ArrayList<OtlpLogRecord>()
    public var schemaUrl: String = ""
}

@jsonable
public struct OtlpLogRecord {
    public var timeUnixNano: String = "0"
    public var observedTimeUnixNano: String = "0"
    public var severityNumber: String = "SEVERITY_NUMBER_UNSPECIFIED"
    public var severityText: String = ""
    public var body: OtlpAnyValue = OtlpAnyValue(stringValue: Some(""))
    public var attributes: ArrayList<OtlpKeyValue> = ArrayList<OtlpKeyValue>()
    public var droppedAttributesCount: Int64 = 0
    public var flags: String = "0"
    public var traceId: String = ""
    public var spanId: String = ""
    public var traceState: String = ""
}
