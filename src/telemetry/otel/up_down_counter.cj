package metis.telemetry.otel

import std.collection.*
import std.time.*

public class UpDownCounter {
    public let name: String
    public let description: String
    public let unit: String
    public let startTimeUnixNano: Int64
    public var value: Float64 = 0.0

    public init(name: String, description!: String = "", unit!: String = "") {
        this.name = name
        this.description = description
        this.unit = unit
        this.startTimeUnixNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
    }

    public func add(value: Float64, attributes: HashMap<String, String>): Unit {
        this.value += value
    }
}
