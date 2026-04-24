package metis.telemetry.otel.exporters

import metis.telemetry.otel.*
import magic.log.LogUtils
import magic.utils.http.HttpUtils

import std.collection.*
import std.fs.*
import std.time.*

import stdx.encoding.json.*

/**
 * Shared HTTP client helper that performs JSON POST requests with timeouts and headers.
 */
protected class JsonHttpTransport {
    let endpoint: String
    let timeoutMs: Int64
    let headers: HashMap<String, String>

    public init(endpoint: String,
                timeoutMs!: Int64 = 5000,
                headers!: HashMap<String, String> = HashMap<String, String>()) {
        this.endpoint = endpoint
        this.timeoutMs = timeoutMs
        this.headers = HashMap<String, String>()
        this.headers["Content-Type"] = "application/json"
        for ((key, value) in headers) {
            this.headers[key] = value
        }
    }

    public func send(payload: String): Bool {
        try {
            let jsonValue = JsonValue.fromStr(payload)
            let jsonObject = jsonValue.asObject()

            let httpHeaders = HashMap<String, String>()
            for ((key, value) in headers) {
                httpHeaders[key] = value
            }

            let result = HttpUtils.post(endpoint, httpHeaders, jsonObject, verify: false)

            match (result) {
                case Some(response) =>
                    return true
                case None =>
                    return false
            }
        } catch (ex: Exception) {
            LogUtils.debug("Telemetry export failed: ${ex.message}")
            return false
        }
    }

}

public class JsonHttpSpanExporter <: SpanExporter {
    let transport: JsonHttpTransport
    var resourceAttributes: HashMap<String, AttributeValue>

    public init(endpoint: String,
                timeoutMs!: Int64 = 5000,
                headers!: HashMap<String, String> = HashMap<String, String>()) {
        this.transport = JsonHttpTransport(endpoint, timeoutMs: timeoutMs, headers: headers)
        this.resourceAttributes = HashMap<String, AttributeValue>()
    }

    public func shutdown(): Unit {}

    public func export(spans: ArrayList<Span>): Bool {
        if (spans.size == 0) {
            return true
        }

        let payload = buildPayload(spans)
        // println(payload)
        // return true
        match (transport.send(payload)) {
            case true => return true
            case false => return false
        }
    }

    public func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit {
        let updated = HashMap<String, AttributeValue>()
        for ((key, value) in attributes) {
            updated[key] = value
        }
        resourceAttributes = updated
    }

    private func buildPayload(spans: ArrayList<Span>): String {
        var request = OtlpExportRequest()
        var resource = OtlpResource()
        resource.attributes = OtlpJsonUtils.mapAttributes(resourceAttributes).toArray()

        let scopeSpans = buildScopeSpans(spans)
        var resourceSpans = OtlpResourceSpans(resource: resource)
        resourceSpans.scopeSpans = scopeSpans
        request.resourceSpans.add(resourceSpans)

        return request.toJsonValue().toJsonString()
    }

    private func buildScopeSpans(spans: ArrayList<Span>): ArrayList<OtlpScopeSpans> {
        let grouped = HashMap<String, ArrayList<Span>>()
        for (span in spans) {
            let scopeName = span.getInstrumentationScopeName()
            let scopeVersion = span.getInstrumentationScopeVersion()
            let key = "${scopeName}|${scopeVersion}"
            match (grouped.get(key)) {
                case Some(existing) => existing.add(span)
                case None =>
                    let list = ArrayList<Span>()
                    list.add(span)
                    grouped[key] = list
            }
        }

        let scopeSpansList = ArrayList<OtlpScopeSpans>()
        for ((key, scopedSpans) in grouped) {
            let parts = key.split("|")
            let scopeName = if (parts.size > 0) { parts[0] } else { "" }
            let scopeVersion = if (parts.size > 1) { parts[1] } else { "" }

            var scope = OtlpInstrumentationScope()
            scope.name = scopeName
            scope.version = scopeVersion

            let otlpSpans = ArrayList<OtlpSpan>()
            for (span in scopedSpans) {
                otlpSpans.add(convertSpan(span))
            }

            var scopeSpan = OtlpScopeSpans(scope: scope)
            scopeSpan.spans = otlpSpans
            scopeSpansList.add(scopeSpan)
        }

        return scopeSpansList
    }

    private func convertSpan(span: Span): OtlpSpan {
        let context = span.getContext()
        let parent = span.getParentContext()

        let startTime = span.getStartTime()
        var endTime = span.getEndTime()
        if (endTime == 0) {
            endTime = DateTime.now().toUnixTimeStamp().toNanoseconds()
        }

        var otlpSpan = OtlpSpan(
            traceId: OtlpJsonUtils.normalizeTraceId(context.getTraceId()),
            spanId: OtlpJsonUtils.normalizeSpanId(context.getSpanId()),
            name: span.getName(),
            kind: spanKindToOtlp(span.getKind()),
            startTimeUnixNano: startTime.toString(),
            endTimeUnixNano: endTime.toString()
        )

        match (parent) {
            case Some(p) => otlpSpan.parentSpanId = OtlpJsonUtils.normalizeSpanId(p.getSpanId())
            case None => otlpSpan.parentSpanId = ""
        }

        otlpSpan.traceState = context.getTraceState()
        otlpSpan.attributes = OtlpJsonUtils.mapAttributes(span.getAttributes())
        otlpSpan.droppedAttributesCount = span.getDroppedAttributesCount()
        otlpSpan.events = convertEvents(span.getEvents())
        otlpSpan.droppedEventsCount = span.getDroppedEventsCount()
        otlpSpan.links = convertLinks(span.getLinks())
        otlpSpan.droppedLinksCount = span.getDroppedLinksCount()
        otlpSpan.status = convertStatus(span.getStatus())

        return otlpSpan
    }

    private func convertEvents(events: ArrayList<SpanEvent>): ArrayList<OtlpEvent> {
        let converted = ArrayList<OtlpEvent>()
        for (event in events) {
            var otlpEvent = OtlpEvent(
                name: event.getName(),
                timeUnixNano: event.getTimestamp().toString()
            )
            otlpEvent.attributes = OtlpJsonUtils.mapAttributes(event.getAttributes())
            otlpEvent.droppedAttributesCount = event.getDroppedAttributesCount()
            converted.add(otlpEvent)
        }
        return converted
    }

    private func convertLinks(links: ArrayList<SpanLink>): ArrayList<OtlpLink> {
        let converted = ArrayList<OtlpLink>()
        for (link in links) {
            let ctx = link.getContext()
            var otlpLink = OtlpLink(
                traceId: OtlpJsonUtils.normalizeTraceId(ctx.getTraceId()),
                spanId: OtlpJsonUtils.normalizeSpanId(ctx.getSpanId())
            )
            otlpLink.traceState = ctx.getTraceState()
            otlpLink.attributes = OtlpJsonUtils.mapAttributes(link.getAttributes())
            otlpLink.droppedAttributesCount = link.getDroppedAttributesCount()
            converted.add(otlpLink)
        }
        return converted
    }

    private func convertStatus(status: SpanStatus): OtlpStatus {
        match (status) {
            case SpanStatus.Unset => return OtlpStatus(code: "STATUS_CODE_UNSET")
            case SpanStatus.Ok => return OtlpStatus(code: "STATUS_CODE_OK")
            case SpanStatus.Error(message) => return OtlpStatus(code: "STATUS_CODE_ERROR", message: message)
        }
    }

    private func spanKindToOtlp(kind: SpanKind): String {
        match (kind) {
            case SpanKind.Internal => return "SPAN_KIND_INTERNAL"
            case SpanKind.Server => return "SPAN_KIND_SERVER"
            case SpanKind.Client => return "SPAN_KIND_CLIENT"
            case SpanKind.Producer => return "SPAN_KIND_PRODUCER"
            case SpanKind.Consumer => return "SPAN_KIND_CONSUMER"
        }
    }
}

public class JsonHttpMetricExporter <: MetricExporter {
    let transport: JsonHttpTransport
    var resourceAttributes: HashMap<String, AttributeValue>

    public init(endpoint: String,
                timeoutMs!: Int64 = 5000,
                headers!: HashMap<String, String> = HashMap<String, String>()) {
        this.transport = JsonHttpTransport(endpoint, timeoutMs: timeoutMs, headers: headers)
        this.resourceAttributes = HashMap<String, AttributeValue>()
    }

    public func export(metrics: ArrayList<MetricData>): Bool {
        if (metrics.size == 0) {
            return true
        }
        let payload = buildPayload(metrics)
        return transport.send(payload)
    }

    public func shutdown(): Unit {}

    public func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit {
        let updated = HashMap<String, AttributeValue>()
        for ((key, value) in attributes) {
            updated[key] = value
        }
        resourceAttributes = updated
    }

    private func buildPayload(metrics: ArrayList<MetricData>): String {
        // Convert MetricData objects to OTLP format and wrap in request envelope.
        var request = OtlpMetricExportRequest()

        if (metrics.size > 0) {
            var resource = OtlpResource()
            resource.attributes = OtlpJsonUtils.mapAttributes(resourceAttributes).toArray()

            var scopeMetrics = ArrayList<OtlpScopeMetrics>()
            var scope = OtlpInstrumentationScope()
            scope.name = "default"
            scope.version = "1.0.0"

            var otlpMetrics = ArrayList<OtlpMetric>()
            for (metricData in metrics) {
                otlpMetrics.add(convertMetricData(metricData))
            }

            var scopeMetric = OtlpScopeMetrics(scope: scope)
            scopeMetric.metrics = otlpMetrics
            scopeMetrics.add(scopeMetric)

            var resourceMetric = OtlpResourceMetrics(resource: resource)
            resourceMetric.scopeMetrics = scopeMetrics
            request.resourceMetrics.add(resourceMetric)
        }

        return request.toJsonValue().toJsonString()
    }

    private func convertMetricData(metricData: MetricData): OtlpMetric {
        var metric = OtlpMetric(
            name: metricData.name,
            description: metricData.description,
            unit: metricData.unit
        )

        // Convert MetricData to a gauge OTLP metric
        var gauge = OtlpGauge()
        var dataPoint = OtlpNumberDataPoint()
        dataPoint.timeUnixNano = metricData.timestamp.toString()
        dataPoint.attributes = OtlpJsonUtils.mapAttributes(metricData.attributes)
        dataPoint.asDouble = Some(metricData.value)
        gauge.dataPoints.add(dataPoint)
        metric.gauge = Some(gauge)

        return metric
    }
}

public class JsonHttpLogExporter <: LogExporter {
    let transport: JsonHttpTransport
    var resourceAttributes: HashMap<String, AttributeValue>

    public init(endpoint: String,
                timeoutMs!: Int64 = 5000,
                headers!: HashMap<String, String> = HashMap<String, String>()) {
        this.transport = JsonHttpTransport(endpoint, timeoutMs: timeoutMs, headers: headers)
        this.resourceAttributes = HashMap<String, AttributeValue>()
    }

    public func export(logRecords: ArrayList<LogRecord>): Bool {
        if (logRecords.size == 0) {
            return true
        }
        let payload = buildPayload(logRecords)
        return transport.send(payload)
    }

    public func shutdown(): Unit {}

    public func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit {
        let updated = HashMap<String, AttributeValue>()
        for ((key, value) in attributes) {
            updated[key] = value
        }
        resourceAttributes = updated
    }

    private func buildPayload(logRecords: ArrayList<LogRecord>): String {
        // Convert LogRecord objects to OTLP format and wrap in request envelope.
        var request = OtlpLogExportRequest()

        if (logRecords.size > 0) {
            var resource = OtlpResource()
            resource.attributes = OtlpJsonUtils.mapAttributes(resourceAttributes).toArray()

            var scopeLogs = ArrayList<OtlpScopeLogs>()
            var scope = OtlpInstrumentationScope()
            scope.name = "default"
            scope.version = "1.0.0"

            var otlpLogRecords = ArrayList<OtlpLogRecord>()
            for (logRecord in logRecords) {
                otlpLogRecords.add(logRecord.toOtlp())
            }

            var scopeLog = OtlpScopeLogs(scope: scope)
            scopeLog.logRecords = otlpLogRecords
            scopeLogs.add(scopeLog)

            var resourceLog = OtlpResourceLogs(resource: resource)
            resourceLog.scopeLogs = scopeLogs
            request.resourceLogs.add(resourceLog)
        }

        return request.toJsonValue().toJsonString()
    }
}
