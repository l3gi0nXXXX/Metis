package metis.telemetry.otel

import std.collection.*
import std.time.*
import std.deriving.Derive
import std.random.Random

public enum AttributeValue {
    | StringValue(String)
    | IntValue(Int64)
    | DoubleValue(Float64)
    | BoolValue(Bool)
    | BytesValue(Array<UInt8>)
    | ArrayValue(Array<AttributeValue>)
    | KvList(HashMap<String, AttributeValue>)
}

public class Tracer {
    let name: String
    let version: String
    let spans: ArrayList<Span> = ArrayList<Span>()

    public init(name: String, version!: String = "1.0.0") {
        this.name = name
        this.version = version
    }

    public func startSpan(name: String, parentContext: ?SpanContext, kind: SpanKind): Span {
        let spanId = generateSpanId()
        let traceId = match (parentContext) {
            case Some(ctx) => ctx.getTraceId()
            case None => generateTraceId()
        }

        let context = SpanContext(traceId, spanId)
        let span = Span(
            name,
            context,
            parentContext: parentContext,
            kind: kind,
            instrumentationScopeName: this.name,
            instrumentationScopeVersion: this.version
        )
        spans.add(span)
        return span
    }

    public func startSpanWithTimestamp(name: String, timestamp: Int64, parentContext: ?SpanContext, kind: SpanKind): Span {
        let spanId = generateSpanId()
        let traceId = match (parentContext) {
            case Some(ctx) => ctx.getTraceId()
            case None => generateTraceId()
        }

        let context = SpanContext(traceId, spanId)
        return Span(name, context, parentContext: parentContext, kind: kind, startTime: timestamp, instrumentationScopeName: this.name, instrumentationScopeVersion: this.version)
    }

    private func generateTraceId(): String {
        // 生成16字节的trace ID (32个十六进制字符)
        let rand = Random()
        let randomBytes = Array<UInt8>(16) { i =>
            rand.nextUInt8(UInt8.Max)
        }
        return bytesToHex(randomBytes)
    }

    private func generateSpanId(): String {
        // 生成8字节的span ID (16个十六进制字符)
        let rand = Random()
        let randomBytes = Array<UInt8>(8) { i =>
            rand.nextUInt8(UInt8.Max)
        }
        return bytesToHex(randomBytes)
    }

    private func bytesToHex(bytes: Array<UInt8>): String {
        var hex = StringBuilder()
        let hexChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
        for (byte in bytes) {
            let high = byte >> 4
            let low = byte & 0x0F
            hex.append(hexChars[Int64(high)])
            hex.append(hexChars[Int64(low)])
        }
        return hex.toString()
    }

    public func getName(): String {
        return name
    }

    public func getVersion(): String {
        return version
    }
}
