package metis.telemetry.otel

import std.collection.*
import std.sort.sort
import std.time.*

public class Counter {
    public let name: String
    public let description: String
    public let unit: String
    public let startTimeUnixNano: Int64
    public var value: Float64 = 0.0
    public let attributeTotals: HashMap<String, Float64>

    public init(name: String, description!: String = "", unit!: String = "") {
        this.name = name
        this.description = description
        this.unit = unit
        this.startTimeUnixNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
        this.attributeTotals = HashMap<String, Float64>()
    }

    public func add(value: Float64, attributes: HashMap<String, String>): Unit {
        this.value += value
        let key = attributesToKey(attributes)
        match (attributeTotals.get(key)) {
            case Some(existing) => attributeTotals[key] = existing + value
            case None => attributeTotals[key] = value
        }
    }

    private func attributesToKey(attributes: HashMap<String, String>): String {
        if (attributes.size == 0) {
            return ""
        }
        var pieces = ArrayList<String>()
        for ((key, value) in attributes) {
            pieces.add("${key}=${value}")
        }
        sort(pieces)
        return String.join(pieces.toArray(), delimiter: ",")
    }
}
