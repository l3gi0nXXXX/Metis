package metis.telemetry.otel

import std.time.*

public class ObservableCounter {
    public let name: String
    public let description: String
    public let unit: String
    public let startTimeUnixNano: Int64
    private var callback: () -> Float64

    public init(name: String, description!: String = "", unit!: String = "") {
        this.name = name
        this.description = description
        this.unit = unit
        this.startTimeUnixNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
        this.callback = { => 0.0 }
    }

    public func observe(callback: () -> Float64): Unit {
        this.callback = callback
    }

    public func read(): Float64 {
        return callback()
    }
}
