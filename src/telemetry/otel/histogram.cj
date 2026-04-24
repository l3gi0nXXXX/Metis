package metis.telemetry.otel

import std.collection.*
import std.time.*

public class Histogram {
    public let name: String
    public let description: String
    public let unit: String
    public let startTimeUnixNano: Int64
    public let bucketBoundaries: Array<Float64>
    public var buckets: HashMap<String, Int64>
    public var sum: Float64 = 0.0
    public var count: Int64 = 0
    public var minValue: Option<Float64> = None
    public var maxValue: Option<Float64> = None

    public init(name: String, description!: String = "", unit!: String = "") {
        this.name = name
        this.description = description
        this.unit = unit
        this.startTimeUnixNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
        this.bucketBoundaries = [0.0, 5.0, 10.0, 25.0, 50.0, 75.0, 100.0, 250.0, 500.0, 750.0, 1000.0, 2500.0, 5000.0, 7500.0, 10000.0]
        this.buckets = HashMap<String, Int64>()
        for (bound in bucketBoundaries) {
            buckets[bound.toString()] = 0
        }
        buckets["+Inf"] = 0
    }

    public func record(value: Float64, attributes: HashMap<String, String>): Unit {
        sum += value
        count++
        match (minValue) {
            case Some(existing) =>
                if (value < existing) {
                    minValue = Some(value)
                }
            case None => minValue = Some(value)
        }
        match (maxValue) {
            case Some(existing) =>
                if (value > existing) {
                    maxValue = Some(value)
                }
            case None => maxValue = Some(value)
        }

        var recorded = false
        for (bound in bucketBoundaries) {
            if (value <= bound) {
                match (buckets.get(bound.toString())) {
                    case Some(existing) => buckets[bound.toString()] = existing + 1
                    case None => buckets[bound.toString()] = 1
                }
                recorded = true
                break
            }
        }
        if (!recorded) {
            match (buckets.get("+Inf")) {
                case Some(existing) => buckets["+Inf"] = existing + 1
                case None => buckets["+Inf"] = 1
            }
        }
    }
}
