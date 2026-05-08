package metis.gateway.openclaw_memory

import std.collection.HashMap

public class OpenClawMemoryRuntime {
    private let facts = HashMap<String, String>()

    public init() {}

    private func key(scope: String, owner: String, name: String): String {
        "${scope.trimAscii().toAsciiLower()}/${owner.trimAscii()}/${name.trimAscii().toAsciiLower()}"
    }

    public func write(scope: String, owner: String, name: String, value: String): Unit {
        this.facts[this.key(scope, owner, name)] = value
    }

    public func read(scope: String, owner: String, name: String): Option<String> {
        this.facts.get(this.key(scope, owner, name))
    }
}
