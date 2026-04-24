package metis.telemetry.otel

import std.collection.*

public class TracerProvider {
    let name: String
    let version: String
    let tracers: HashMap<String, Tracer>
    let spanExporters: ArrayList<SpanExporter>
    let resourceAttributes: HashMap<String, AttributeValue>
    var isShutdown: Bool = false

    public init(name: String, version!: String = "1.0.0", spanExporters!: ArrayList<SpanExporter> = ArrayList<SpanExporter>()) {
        this.name = name
        this.version = version
        this.tracers = HashMap<String, Tracer>()
        this.spanExporters = ArrayList<SpanExporter>()
        this.spanExporters.add(all: spanExporters)
        this.resourceAttributes = HashMap<String, AttributeValue>()
        updateSpanExporterResources()
    }

    public func createTracer(name: String, version: String): Tracer {
        if (isShutdown) {
            return Tracer(name, version: version)
        }

        let key = "${name}-${version}"
        match (tracers.get(key)) {
            case Some(tracer) => return tracer
            case None =>
                let tracer = Tracer(name, version: version)
                tracers[key] = tracer
                return tracer
        }
    }

    public func shutdown(): Unit {
        isShutdown = true
        let allSpans = ArrayList<Span>()
        for (tracer in tracers.values()) {
            allSpans.add(all: tracer.spans)
        }
        for (exporter in spanExporters) {
            exporter.export(allSpans)
            exporter.shutdown()
        }
    }

    public func setResourceAttribute(key: String, value: AttributeValue): Unit {
        resourceAttributes[key] = value
        updateSpanExporterResources()
    }

    public func getResourceAttributes(): HashMap<String, AttributeValue> {
        return resourceAttributes
    }

    public func getSpanExporters(): ArrayList<SpanExporter> {
        let copy = ArrayList<SpanExporter>()
        copy.add(all: spanExporters)
        return copy
    }

    public func registerSpanExporter(exporter: SpanExporter): Unit {
        spanExporters.add(exporter)
        exporter.updateResourceAttributes(resourceAttributes)
    }

    private func updateSpanExporterResources(): Unit {
        for (exporter in spanExporters) {
            exporter.updateResourceAttributes(resourceAttributes)
        }
    }
}
