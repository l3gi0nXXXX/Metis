package metis.telemetry.otel.exporters

import metis.telemetry.otel.*
import std.collection.*

public class ConsoleSpanExporter <: SpanExporter {
    public init() {}

    public func export(spans: ArrayList<Span>): Bool {
        println("=== Exporting Spans ===")
        for (span in spans) {
            println("Span: ${span.getName()}")
            println("  Trace ID: ${span.getContext().getTraceId()}")
            println("  Span ID: ${span.getContext().getSpanId()}")
            println("  Start Time: ${span.getStartTime()}")
            println("  End Time: ${span.getEndTime()}")
            println("  Status: ${span.getStatus()}")

            let attributes = span.getAttributes()
            if (attributes.size > 0) {
                println("  Attributes:")
                for ((key, value) in attributes) {
                    println("    ${key}: ${attributeValueToString(value)}")
                }
            }

            let events = span.getEvents()
            if (events.size > 0) {
                println("  Events:")
                for (event in events) {
                    println("    ${event.getName()} at ${event.getTimestamp()}")
                    let eventAttrs = event.getAttributes()
                    if (eventAttrs.size > 0) {
                        println("      Attributes:")
                        for ((ek, ev) in eventAttrs) {
                            println("        ${ek}: ${attributeValueToString(ev)}")
                        }
                    }
                }
            }
            println("")
        }
        return true
    }

    public func shutdown(): Unit {
        println("ConsoleSpanExporter shutdown")
    }

    public func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit {
        // console exporter ignores resource attributes but must satisfy the interface
    }

    private func attributeValueToString(value: AttributeValue): String {
        match (value) {
            case AttributeValue.StringValue(v) => return v
            case AttributeValue.IntValue(v) => return v.toString()
            case AttributeValue.DoubleValue(v) => return v.toString()
            case AttributeValue.BoolValue(v) => return v.toString()
            case AttributeValue.BytesValue(bytes) =>
                var sb = StringBuilder()
                sb.append("[")
                var first = true
                for (b in bytes) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(b.toString())
                    first = false
                }
                sb.append("]")
                return sb.toString()
            case AttributeValue.ArrayValue(values) =>
                var sb = StringBuilder()
                sb.append("[")
                var first = true
                for (v in values) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(attributeValueToString(v))
                    first = false
                }
                sb.append("]")
                return sb.toString()
            case AttributeValue.KvList(map) =>
                var sb = StringBuilder()
                sb.append("{")
                var first = true
                for ((k, v) in map) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(k)
                    sb.append(": ")
                    sb.append(attributeValueToString(v))
                    first = false
                }
                sb.append("}")
                return sb.toString()
        }
    }
}

public class ConsoleLogExporter <: LogExporter {
    public init() {}

    public func export(logRecords: ArrayList<LogRecord>): Bool {
        println("=== Exporting Logs ===")
        if (logRecords.size == 0) {
            println("No logs to export")
            return true
        }

        for (record in logRecords) {
            println("LogRecord@${record.timestamp}: ${record.severity}")
            println("  Body: ${attributeValueToString(record.body)}")
            if (record.attributes.size > 0) {
                println("  Attributes:")
                for ((key, value) in record.attributes) {
                    println("    ${key}: ${attributeValueToString(value)}")
                }
            }
            if (record.traceId.size > 0) {
                println("  TraceId: ${record.traceId} SpanId: ${record.spanId}")
            }
        }

        return true
    }

    public func shutdown(): Unit {
        println("ConsoleLogExporter shutdown")
    }

    public func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit {
        // console exporter does not need extra resource state
    }

    private func attributeValueToString(value: AttributeValue): String {
        match (value) {
            case AttributeValue.StringValue(v) => return v
            case AttributeValue.IntValue(v) => return v.toString()
            case AttributeValue.DoubleValue(v) => return v.toString()
            case AttributeValue.BoolValue(v) => return v.toString()
            case AttributeValue.BytesValue(bytes) =>
                var sb = StringBuilder()
                sb.append("[")
                var first = true
                for (b in bytes) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(b.toString())
                    first = false
                }
                sb.append("]")
                return sb.toString()
            case AttributeValue.ArrayValue(values) =>
                var sb = StringBuilder()
                sb.append("[")
                var first = true
                for (v in values) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(attributeValueToString(v))
                    first = false
                }
                sb.append("]")
                return sb.toString()
            case AttributeValue.KvList(map) =>
                var sb = StringBuilder()
                sb.append("{")
                var first = true
                for ((k, v) in map) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(k)
                    sb.append(": ")
                    sb.append(attributeValueToString(v))
                    first = false
                }
                sb.append("}")
                return sb.toString()
        }
    }

    private func prettyPrintAnyValue(value: OtlpAnyValue): String {
        if (let Some(v) <- value.stringValue) {
            return v
        } else if (let Some(v) <- value.boolValue) {
            return v.toString()
        } else if (let Some(v) <- value.intValue) {
            return v
        } else if (let Some(v) <- value.doubleValue) {
            return v.toString()
        } else if (let Some(v) <- value.bytesValue) {
            return v
        } else if (let Some(arrayValue) <- value.arrayValue) {
            var sb = StringBuilder()
            sb.append("[")
            var first = true
            for (item in arrayValue.values) {
                if (!first) {
                    sb.append(", ")
                }
                sb.append(prettyPrintAnyValue(item))
                first = false
            }
            sb.append("]")
            return sb.toString()
        } else if (let Some(kvList) <- value.kvlistValue) {
            var sb = StringBuilder()
            sb.append("{")
            var first = true
            for (kv in kvList.values) {
                if (!first) {
                    sb.append(", ")
                }
                sb.append(kv.key)
                sb.append(": ")
                sb.append(prettyPrintAnyValue(kv.value))
                first = false
            }
            sb.append("}")
            return sb.toString()
        } else {
            return ""
        }
    }
}

public class ConsoleMetricExporter <: MetricExporter {
    public init() {}

    public func export(metrics: ArrayList<MetricData>): Bool {
        println("=== Exporting Metrics ===")
        if (metrics.size == 0) {
            println("No metrics to export")
            return true
        }

        for (metric in metrics) {
            println("Metric: ${metric.name} (${metric.unit}) - ${metric.description}")
            println("  Value: ${metric.value}")
            println("  Timestamp: ${metric.timestamp}")
            if (metric.attributes.size > 0) {
                println("  Attributes:")
                for ((key, value) in metric.attributes) {
                    println("    ${key}: ${attributeValueToString(value)}")
                }
            }
        }
        return true
    }

    public func shutdown(): Unit {
        println("ConsoleMetricExporter shutdown")
    }

    public func updateResourceAttributes(attributes: HashMap<String, AttributeValue>): Unit {
        // console exporter uses the payload directly and does not need extra state
    }

    private func attributeValueToString(value: AttributeValue): String {
        match (value) {
            case AttributeValue.StringValue(v) => return v
            case AttributeValue.IntValue(v) => return v.toString()
            case AttributeValue.DoubleValue(v) => return v.toString()
            case AttributeValue.BoolValue(v) => return v.toString()
            case AttributeValue.BytesValue(bytes) =>
                var sb = StringBuilder()
                sb.append("[")
                var first = true
                for (b in bytes) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(b.toString())
                    first = false
                }
                sb.append("]")
                return sb.toString()
            case AttributeValue.ArrayValue(values) =>
                var sb = StringBuilder()
                sb.append("[")
                var first = true
                for (v in values) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(attributeValueToString(v))
                    first = false
                }
                sb.append("]")
                return sb.toString()
            case AttributeValue.KvList(map) =>
                var sb = StringBuilder()
                sb.append("{")
                var first = true
                for ((k, v) in map) {
                    if (!first) {
                        sb.append(", ")
                    }
                    sb.append(k)
                    sb.append(": ")
                    sb.append(attributeValueToString(v))
                    first = false
                }
                sb.append("}")
                return sb.toString()
        }
    }

    private func printNumberDataPoints(points: ArrayList<OtlpNumberDataPoint>): Unit {
        for (point in points) {
            let value = point.asDouble.map({ v => v.toString() }).getOrDefault({ => point.asInt.getOrDefault({ => "0" }) })
            println("      Value: ${value}")
            if (point.attributes.size > 0) {
                println("        Attributes:")
                for (attr in point.attributes) {
                    println("          ${attr.key}: ${prettyPrintAnyValue(attr.value)}")
                }
            }
        }
    }

    private func prettyPrintAnyValue(value: OtlpAnyValue): String {
        if (let Some(v) <- value.stringValue) {
            return v
        } else if (let Some(v) <- value.boolValue) {
            return v.toString()
        } else if (let Some(v) <- value.intValue) {
            return v
        } else if (let Some(v) <- value.doubleValue) {
            return v.toString()
        } else if (let Some(v) <- value.bytesValue) {
            return v
        } else if (let Some(arrayValue) <- value.arrayValue) {
            var sb = StringBuilder()
            sb.append("[")
            var first = true
            for (item in arrayValue.values) {
                if (!first) {
                    sb.append(", ")
                }
                sb.append(prettyPrintAnyValue(item))
                first = false
            }
            sb.append("]")
            return sb.toString()
        } else if (let Some(kvList) <- value.kvlistValue) {
            var sb = StringBuilder()
            sb.append("{")
            var first = true
            for (kv in kvList.values) {
                if (!first) {
                    sb.append(", ")
                }
                sb.append(kv.key)
                sb.append(": ")
                sb.append(prettyPrintAnyValue(kv.value))
                first = false
            }
            sb.append("}")
            return sb.toString()
        } else {
            return ""
        }
    }
}
