package metis.telemetry.otel

import std.collection.*

public class MeterProvider {
    let name: String
    let version: String
    let meters: HashMap<String, Meter>
    let metricExporters: ArrayList<MetricExporter>
    let resourceAttributes: HashMap<String, AttributeValue>
    var isShutdown: Bool = false

    public init(name: String, version!: String = "1.0.0", metricExporters!: ArrayList<MetricExporter> = ArrayList<MetricExporter>()) {
        this.name = name
        this.version = version
        this.meters = HashMap<String, Meter>()
        this.metricExporters = ArrayList<MetricExporter>()
        this.metricExporters.add(all: metricExporters)
        this.resourceAttributes = HashMap<String, AttributeValue>()
        updateMetricExporterResources()
    }

    public func createMeter(name: String, version: String): Meter {
        if (isShutdown) {
            return Meter(name, version: version)
        }

        let key = "${name}-${version}"
        match (meters.get(key)) {
            case Some(meter) => return meter
            case None =>
                let meter = Meter(name, version: version)
                meters[key] = meter
                return meter
        }
    }

    public func shutdown(): Unit {
        isShutdown = true
        let metrics = collectMetrics()
        for (exporter in metricExporters) {
            exporter.export(metrics)
            exporter.shutdown()
        }
    }

    public func setResourceAttribute(key: String, value: AttributeValue): Unit {
        resourceAttributes[key] = value
        updateMetricExporterResources()
    }

    public func getResourceAttributes(): HashMap<String, AttributeValue> {
        return resourceAttributes
    }

    public func getMetricExporters(): ArrayList<MetricExporter> {
        let copy = ArrayList<MetricExporter>()
        copy.add(all: metricExporters)
        return copy
    }

    public func registerMetricExporter(exporter: MetricExporter): Unit {
        metricExporters.add(exporter)
        exporter.updateResourceAttributes(resourceAttributes)
    }

    private func collectMetrics(): ArrayList<MetricData> {
        let metrics = ArrayList<MetricData>()
        for ((_, meter) in meters) {
            let meterMetrics = meter.collectMetrics()
            metrics.add(all: meterMetrics)
        }
        return metrics
    }

    private func updateMetricExporterResources(): Unit {
        for (exporter in metricExporters) {
            exporter.updateResourceAttributes(resourceAttributes)
        }
    }
}
