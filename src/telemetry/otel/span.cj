package metis.telemetry.otel

import std.collection.{ArrayList, HashMap}
import std.time.DateTime
import std.deriving.Derive

@Derive[ToString]
public enum SpanKind {
    | Internal
    | Server
    | Client
    | Producer
    | Consumer
}

@Derive[ToString]
public enum SpanStatus {
    | Unset
    | Ok
    | Error(String)
}

public class SpanContext {
    let traceId: String
    let spanId: String
    let traceFlags: UInt8
    let traceState: String
    let isRemote: Bool

    public init(traceId: String, spanId: String, traceFlags!: UInt8 = 0, traceState!: String = "", isRemote!: Bool = false) {
        this.traceId = traceId
        this.spanId = spanId
        this.traceFlags = traceFlags
        this.traceState = traceState
        this.isRemote = isRemote
    }

    public func getTraceId(): String {
        return traceId
    }

    public func getSpanId(): String {
        return spanId
    }

    public func getTraceFlags(): UInt8 {
        return traceFlags
    }

    public func getTraceState(): String {
        return traceState
    }

    public func isValid(): Bool {
        return traceId != "" && spanId != ""
    }
}

public class SpanEvent {
    let name: String
    let timestamp: Int64
    let attributes: HashMap<String, AttributeValue>
    let droppedAttributesCount: Int64

    public init(name: String, timestamp: Int64, attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(), droppedAttributesCount!: Int64 = 0) {
        this.name = name
        this.timestamp = timestamp
        this.attributes = attributes
        this.droppedAttributesCount = droppedAttributesCount
    }

    public func getName(): String {
        return name
    }

    public func getTimestamp(): Int64 {
        return timestamp
    }

    public func getAttributes(): HashMap<String, AttributeValue> {
        return attributes
    }

    public func getDroppedAttributesCount(): Int64 {
        return droppedAttributesCount
    }
}

public class SpanLink {
    let context: SpanContext
    let attributes: HashMap<String, AttributeValue>
    let droppedAttributesCount: Int64

    public init(context: SpanContext, attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(), droppedAttributesCount!: Int64 = 0) {
        this.context = context
        this.attributes = attributes
        this.droppedAttributesCount = droppedAttributesCount
    }

    public func getContext(): SpanContext {
        return context
    }

    public func getAttributes(): HashMap<String, AttributeValue> {
        return attributes
    }

    public func getDroppedAttributesCount(): Int64 {
        return droppedAttributesCount
    }
}

public class Span {
    var name: String
    let context: SpanContext
    let parentContext: ?SpanContext
    let kind: SpanKind
    let startTime: Int64
    var endTime: Int64 = 0
    var attributes: HashMap<String, AttributeValue>
    var events: ArrayList<SpanEvent>
    var links: ArrayList<SpanLink>
    var status: SpanStatus
    var _isRecording: Bool = true
    var droppedAttributesCount: Int64 = 0
    var droppedEventsCount: Int64 = 0
    var droppedLinksCount: Int64 = 0
    let instrumentationScopeName: String
    let instrumentationScopeVersion: String

    public init(name: String, context: SpanContext, parentContext!: ?SpanContext = None, kind!: SpanKind = SpanKind.Internal, startTime!: Int64 = 0, instrumentationScopeName!: String = "", instrumentationScopeVersion!: String = "") {
        this.name = name
        this.context = context
        this.parentContext = parentContext
        this.kind = kind
        this.startTime = if (startTime == 0) {
            DateTime.now().toUnixTimeStamp().toNanoseconds()
        } else {
            startTime
        }
        this.attributes = HashMap<String, AttributeValue>()
        this.events = ArrayList<SpanEvent>()
        this.links = ArrayList<SpanLink>()
        this.status = SpanStatus.Unset
        this.instrumentationScopeName = instrumentationScopeName
        this.instrumentationScopeVersion = instrumentationScopeVersion
    }

    public func setAttribute(key: String, value: String): Unit {
        setAttributeValue(key, AttributeValue.StringValue(value))
    }

    public func setAttribute(key: String, value: Int64): Unit {
        setAttributeValue(key, AttributeValue.IntValue(value))
    }

    public func setAttribute(key: String, value: Float64): Unit {
        setAttributeValue(key, AttributeValue.DoubleValue(value))
    }

    public func setAttribute(key: String, value: Bool): Unit {
        setAttributeValue(key, AttributeValue.BoolValue(value))
    }

    public func setAttribute(key: String, value: AttributeValue): Unit {
        setAttributeValue(key, value)
    }

    private func setAttributeValue(key: String, value: AttributeValue): Unit {
        if (!_isRecording) {
            return
        }
        attributes[key] = value
    }

    public func addEvent(name: String, attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(), timestamp!: Int64 = 0, droppedAttributesCount!: Int64 = 0): Unit {
        if (!_isRecording) {
            return
        }
        let eventTimestamp = if (timestamp == 0) {
            DateTime.now().toUnixTimeStamp().toNanoseconds()
        } else {
            timestamp
        }
        let event = SpanEvent(name, eventTimestamp, attributes: attributes, droppedAttributesCount: droppedAttributesCount)
        events.add(event)
    }

    public func addLink(context: SpanContext, attributes!: HashMap<String, AttributeValue> = HashMap<String, AttributeValue>(), droppedAttributesCount!: Int64 = 0): Unit {
        if (!_isRecording) {
            return
        }
        let link = SpanLink(context, attributes: attributes, droppedAttributesCount: droppedAttributesCount)
        links.add(link)
    }

    public func setStatus(status: SpanStatus): Unit {
        if (!_isRecording) {
            return
        }
        match (this.status) {
            case Error(_) => return
            case _ => this.status = status
        }
    }

    public func updateName(name: String): Unit {
        if (!_isRecording) {
            return
        }
        this.name = name
    }

    public func end(timestamp!: Option<DateTime> = None): Unit {
        if (!_isRecording) {
            return
        }
        if (let Some(tsc) <- timestamp) {
            this.endTime = tsc.toUnixTimeStamp().toNanoseconds()
        } else {
            this.endTime = DateTime.now().toUnixTimeStamp().toNanoseconds()
        }
        _isRecording = false
    }

    public func getContext(): SpanContext {
        return context
    }

    public func isRecording(): Bool {
        return _isRecording
    }

    public func getName(): String {
        return name
    }

    public func getStartTime(): Int64 {
        return startTime
    }

    public func getEndTime(): Int64 {
        return endTime
    }

    public func getAttributes(): HashMap<String, AttributeValue> {
        return attributes
    }

    public func getEvents(): ArrayList<SpanEvent> {
        return events
    }

    public func getLinks(): ArrayList<SpanLink> {
        return links
    }

    public func getStatus(): SpanStatus {
        return status
    }

    public func getKind(): SpanKind {
        return kind
    }

    public func getParentContext(): ?SpanContext {
        return parentContext
    }

    public func getInstrumentationScopeName(): String {
        return instrumentationScopeName
    }

    public func getInstrumentationScopeVersion(): String {
        return instrumentationScopeVersion
    }

    public func getDroppedAttributesCount(): Int64 {
        return droppedAttributesCount
    }

    public func setDroppedAttributesCount(count: Int64): Unit {
        droppedAttributesCount = count
    }

    public func getDroppedEventsCount(): Int64 {
        return droppedEventsCount
    }

    public func setDroppedEventsCount(count: Int64): Unit {
        droppedEventsCount = count
    }

    public func getDroppedLinksCount(): Int64 {
        return droppedLinksCount
    }

    public func setDroppedLinksCount(count: Int64): Unit {
        droppedLinksCount = count
    }
}
