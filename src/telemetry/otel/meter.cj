package metis.telemetry.otel

import std.collection.*
import std.time.*

public class Meter {
    let name: String
    let version: String
    let counters: HashMap<String, Counter>
    let histograms: HashMap<String, Histogram>
    let upDownCounters: HashMap<String, UpDownCounter>
    let observableCounters: HashMap<String, ObservableCounter>
    let observableGauges: HashMap<String, ObservableGauge>

    public init(name: String, version!: String = "1.0.0") {
        this.name = name
        this.version = version
        this.counters = HashMap<String, Counter>()
        this.histograms = HashMap<String, Histogram>()
        this.upDownCounters = HashMap<String, UpDownCounter>()
        this.observableCounters = HashMap<String, ObservableCounter>()
        this.observableGauges = HashMap<String, ObservableGauge>()
    }

    public func createCounter(name: String, description: String, unit: String): Counter {
        match (counters.get(name)) {
            case Some(counter) => return counter
            case None =>
                let counter = Counter(name, description: description, unit: unit)
                counters[name] = counter
                return counter
        }
    }

    public func createHistogram(name: String, description: String, unit: String): Histogram {
        match (histograms.get(name)) {
            case Some(histogram) => return histogram
            case None =>
                let histogram = Histogram(name, description: description, unit: unit)
                histograms[name] = histogram
                return histogram
        }
    }

    public func createUpDownCounter(name: String, description: String, unit: String): UpDownCounter {
        match (upDownCounters.get(name)) {
            case Some(counter) => return counter
            case None =>
                let counter = UpDownCounter(name, description: description, unit: unit)
                upDownCounters[name] = counter
                return counter
        }
    }

    public func createObservableCounter(name: String, description: String, unit: String): ObservableCounter {
        match (observableCounters.get(name)) {
            case Some(counter) => return counter
            case None =>
                let counter = ObservableCounter(name, description: description, unit: unit)
                observableCounters[name] = counter
                return counter
        }
    }

    public func createObservableGauge(name: String, description: String, unit: String): ObservableGauge {
        match (observableGauges.get(name)) {
            case Some(gauge) => return gauge
            case None =>
                let gauge = ObservableGauge(name, description: description, unit: unit)
                observableGauges[name] = gauge
                return gauge
        }
    }

    public func collectMetrics(): ArrayList<MetricData> {
        // Capture a point-in-time snapshot of all instruments for this meter.
        let metrics = ArrayList<MetricData>()
        let collectionTime = DateTime.now().toUnixTimeStamp().toNanoseconds()

        for ((_, counter) in counters) {
            let counterMetrics = buildCounterMetrics(counter, collectionTime)
            metrics.add(all: counterMetrics)
        }

        for ((_, counter) in upDownCounters) {
            let counterMetrics = buildUpDownCounterMetrics(counter, collectionTime)
            metrics.add(all: counterMetrics)
        }

        for ((_, histogram) in histograms) {
            let histogramMetrics = buildHistogramMetrics(histogram, collectionTime)
            metrics.add(all: histogramMetrics)
        }

        for ((_, observableCounter) in observableCounters) {
            let counterMetrics = buildObservableCounterMetrics(observableCounter, collectionTime)
            metrics.add(all: counterMetrics)
        }

        for ((_, observableGauge) in observableGauges) {
            let gaugeMetrics = buildObservableGaugeMetrics(observableGauge, collectionTime)
            metrics.add(all: gaugeMetrics)
        }

        return metrics
    }

    public func collectScopeMetrics(): Option<OtlpScopeMetrics> {
        // Capture a point-in-time snapshot of all instruments for this meter.
        let metrics = ArrayList<OtlpMetric>()
        let collectionTime = DateTime.now().toUnixTimeStamp().toNanoseconds()

        for ((_, counter) in counters) {
            match (buildCounterMetric(counter, collectionTime)) {
                case Some(metric) => metrics.add(metric)
                case None => ()
            }
        }

        for ((_, counter) in upDownCounters) {
            match (buildUpDownCounterMetric(counter, collectionTime)) {
                case Some(metric) => metrics.add(metric)
                case None => ()
            }
        }

        for ((_, histogram) in histograms) {
            match (buildHistogramMetric(histogram, collectionTime)) {
                case Some(metric) => metrics.add(metric)
                case None => ()
            }
        }

        for ((_, observableCounter) in observableCounters) {
            match (buildObservableCounterMetric(observableCounter, collectionTime)) {
                case Some(metric) => metrics.add(metric)
                case None => ()
            }
        }

        for ((_, observableGauge) in observableGauges) {
            match (buildObservableGaugeMetric(observableGauge, collectionTime)) {
                case Some(metric) => metrics.add(metric)
                case None => ()
            }
        }

        if (metrics.size == 0) {
            return None
        }

        var scope = OtlpInstrumentationScope()
        scope.name = name
        scope.version = version

        var scopeMetrics = OtlpScopeMetrics(scope: scope)
        scopeMetrics.metrics = metrics
        return Some(scopeMetrics)
    }

    private func buildCounterMetric(counter: Counter, collectionTime: Int64): Option<OtlpMetric> {
        let totals = counter.attributeTotals
        if (totals.size == 0) {
            return None
        }

        // Convert each attribute combination into an OTLP number data point.
        let dataPoints = ArrayList<OtlpNumberDataPoint>()
        for ((key, total) in totals) {
            let attributes = OtlpJsonUtils.decodeAttributeKey(key)
            let otlpAttributes = OtlpJsonUtils.mapStringAttributes(attributes)
            dataPoints.add(createNumberDataPoint(counter.startTimeUnixNano, collectionTime, total, otlpAttributes))
        }

        var sum = OtlpSum()
        sum.dataPoints = dataPoints
        sum.aggregationTemporality = "AGGREGATION_TEMPORALITY_CUMULATIVE"
        sum.isMonotonic = true

        var metric = OtlpMetric(name: counter.name)
        metric.description = counter.description
        metric.unit = counter.unit
        metric.sum = Some(sum)
        return Some(metric)
    }

    private func buildUpDownCounterMetric(counter: UpDownCounter, collectionTime: Int64): Option<OtlpMetric> {
        let dataPoints = ArrayList<OtlpNumberDataPoint>()
        dataPoints.add(createNumberDataPoint(counter.startTimeUnixNano, collectionTime, counter.value, ArrayList<OtlpKeyValue>()))

        var sum = OtlpSum()
        sum.dataPoints = dataPoints
        sum.aggregationTemporality = "AGGREGATION_TEMPORALITY_CUMULATIVE"
        sum.isMonotonic = false

        var metric = OtlpMetric(name: counter.name)
        metric.description = counter.description
        metric.unit = counter.unit
        metric.sum = Some(sum)
        return Some(metric)
    }

    private func buildObservableCounterMetric(counter: ObservableCounter, collectionTime: Int64): Option<OtlpMetric> {
        let value = safeObserve(counter.read)
        let dataPoints = ArrayList<OtlpNumberDataPoint>()
        dataPoints.add(createNumberDataPoint(counter.startTimeUnixNano, collectionTime, value, ArrayList<OtlpKeyValue>()))

        var sum = OtlpSum()
        sum.dataPoints = dataPoints
        sum.aggregationTemporality = "AGGREGATION_TEMPORALITY_CUMULATIVE"
        sum.isMonotonic = true

        var metric = OtlpMetric(name: counter.name)
        metric.description = counter.description
        metric.unit = counter.unit
        metric.sum = Some(sum)
        return Some(metric)
    }

    private func buildObservableGaugeMetric(gauge: ObservableGauge, collectionTime: Int64): Option<OtlpMetric> {
        let value = safeObserve(gauge.read)
        let dataPoints = ArrayList<OtlpNumberDataPoint>()
        dataPoints.add(createNumberDataPoint(gauge.startTimeUnixNano, collectionTime, value, ArrayList<OtlpKeyValue>()))

        var otlpGauge = OtlpGauge()
        otlpGauge.dataPoints = dataPoints

        var metric = OtlpMetric(name: gauge.name)
        metric.description = gauge.description
        metric.unit = gauge.unit
        metric.gauge = Some(otlpGauge)
        return Some(metric)
    }

    private func buildHistogramMetric(histogram: Histogram, collectionTime: Int64): Option<OtlpMetric> {
        if (histogram.count == 0) {
            return None
        }

        // Translate internal bucket map into ordered bucket counts for OTLP.
        let bucketCountsMap = histogram.buckets
        let bucketCounts = ArrayList<String>()
        let explicitBounds = ArrayList<Float64>()
        for (bound in histogram.bucketBoundaries) {
            explicitBounds.add(bound)
            match (bucketCountsMap.get(bound.toString())) {
                case Some(count) => bucketCounts.add(count.toString())
                case None => bucketCounts.add("0")
            }
        }
        match (bucketCountsMap.get("+Inf")) {
            case Some(count) => bucketCounts.add(count.toString())
            case None => bucketCounts.add("0")
        }

        var dataPoint = OtlpHistogramDataPoint()
        dataPoint.startTimeUnixNano = histogram.startTimeUnixNano.toString()
        dataPoint.timeUnixNano = collectionTime.toString()
        dataPoint.count = histogram.count.toString()
        dataPoint.sum = histogram.sum
        dataPoint.bucketCounts = bucketCounts
        dataPoint.explicitBounds = explicitBounds
        dataPoint.flags = "0"
        dataPoint.attributes = ArrayList<OtlpKeyValue>()
        dataPoint.min = histogram.minValue
        dataPoint.max = histogram.maxValue

        let dataPoints = ArrayList<OtlpHistogramDataPoint>()
        dataPoints.add(dataPoint)

        var otlpHistogram = OtlpHistogram()
        otlpHistogram.dataPoints = dataPoints
        otlpHistogram.aggregationTemporality = "AGGREGATION_TEMPORALITY_CUMULATIVE"

        var metric = OtlpMetric(name: histogram.name)
        metric.description = histogram.description
        metric.unit = histogram.unit
        metric.histogram = Some(otlpHistogram)
        return Some(metric)
    }

    private func createNumberDataPoint(startTime: Int64, collectionTime: Int64, value: Float64, attributes: ArrayList<OtlpKeyValue>): OtlpNumberDataPoint {
        var point = OtlpNumberDataPoint()
        point.startTimeUnixNano = startTime.toString()
        point.timeUnixNano = collectionTime.toString()
        point.attributes = attributes
        point.flags = "0"
        point.asDouble = Some(value)
        return point
    }

    private func safeObserve(callback: () -> Float64): Float64 {
        try {
            return callback()
        } catch (ex: Exception) {
            return 0.0
        }
    }

    // Helper methods to build MetricData objects
    private func buildCounterMetrics(counter: Counter, collectionTime: Int64): ArrayList<MetricData> {
        let metrics = ArrayList<MetricData>()
        let totals = counter.attributeTotals

        for ((key, total) in totals) {
            let attributes = OtlpJsonUtils.decodeAttributeKey(key)
            let metricAttributes = HashMap<String, AttributeValue>()
            for ((attrKey, attrValue) in attributes) {
                metricAttributes[attrKey] = AttributeValue.StringValue(attrValue)
            }

            let metricData = MetricData(counter.name, counter.description, counter.unit, total, metricAttributes, collectionTime)
            metrics.add(metricData)
        }

        return metrics
    }

    private func buildUpDownCounterMetrics(counter: UpDownCounter, collectionTime: Int64): ArrayList<MetricData> {
        let metrics = ArrayList<MetricData>()
        let attributes = HashMap<String, AttributeValue>()

        let metricData = MetricData(counter.name, counter.description, counter.unit, counter.value, attributes, collectionTime)
        metrics.add(metricData)

        return metrics
    }

    private func buildObservableCounterMetrics(counter: ObservableCounter, collectionTime: Int64): ArrayList<MetricData> {
        let metrics = ArrayList<MetricData>()
        let value = safeObserve(counter.read)
        let attributes = HashMap<String, AttributeValue>()

        let metricData = MetricData(counter.name, counter.description, counter.unit, value, attributes, collectionTime)
        metrics.add(metricData)

        return metrics
    }

    private func buildObservableGaugeMetrics(gauge: ObservableGauge, collectionTime: Int64): ArrayList<MetricData> {
        let metrics = ArrayList<MetricData>()
        let value = safeObserve(gauge.read)
        let attributes = HashMap<String, AttributeValue>()

        let metricData = MetricData(gauge.name, gauge.description, gauge.unit, value, attributes, collectionTime)
        metrics.add(metricData)

        return metrics
    }

    private func buildHistogramMetrics(histogram: Histogram, collectionTime: Int64): ArrayList<MetricData> {
        let metrics = ArrayList<MetricData>()

        if (histogram.count > 0) {
            let attributes = HashMap<String, AttributeValue>()
            // For histogram, we export the count as the main value
            let metricData = MetricData("${histogram.name}_count", "${histogram.description} (count)", histogram.unit, Float64(histogram.count), attributes, collectionTime)
            metrics.add(metricData)

            // Also export the sum as a separate metric
            let sumMetricData = MetricData("${histogram.name}_sum", "${histogram.description} (sum)", histogram.unit, histogram.sum, attributes, collectionTime)
            metrics.add(sumMetricData)
        }

        return metrics
    }
}
