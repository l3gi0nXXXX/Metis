package metis.gateway.openclaw_memory

import metis.core.memory.MemoryRuntime

import std.collection.{ArrayList, HashMap}

public class OpenClawMemoryBackendBinding {
    public let contract: String = "metis.memory-context-backend.v1"
    public let providerId: String
    public let backend: String
    public let searchEnabled: Bool
    public let indexPath: String
    public let agentId: String
    public let purpose: String

    public init(
        providerId: String,
        backend: String,
        searchEnabled: Bool,
        indexPath: String,
        agentId!: String = "",
        purpose!: String = "default"
    ) {
        this.providerId = providerId.trimAscii()
        this.backend = backend.trimAscii()
        this.searchEnabled = searchEnabled
        this.indexPath = indexPath.trimAscii()
        this.agentId = agentId.trimAscii()
        this.purpose = purpose.trimAscii()
    }
}

public class OpenClawMemorySearchHit {
    public let backendId: String
    public let scope: String
    public let owner: String
    public let name: String
    public let text: String

    public init(backendId: String, scope: String, owner: String, name: String, text: String) {
        this.backendId = backendId.trimAscii()
        this.scope = scope.trimAscii()
        this.owner = owner.trimAscii()
        this.name = name.trimAscii()
        this.text = text
    }
}

private class OpenClawMemoryFact {
    public let scope: String
    public let owner: String
    public let name: String
    public let value: String

    public init(scope: String, owner: String, name: String, value: String) {
        this.scope = scope.trimAscii()
        this.owner = owner.trimAscii()
        this.name = name.trimAscii()
        this.value = value
    }
}

public class OpenClawMemoryRuntime {
    private let facts = HashMap<String, String>()
    private let factRows = ArrayList<OpenClawMemoryFact>()
    private let backends = HashMap<String, OpenClawMemoryBackendBinding>()

    public init() {}

    private func key(scope: String, owner: String, name: String): String {
        "${scope.trimAscii().toAsciiLower()}/${owner.trimAscii()}/${name.trimAscii().toAsciiLower()}"
    }

    public func write(scope: String, owner: String, name: String, value: String): Unit {
        this.facts[this.key(scope, owner, name)] = value
        this.factRows.add(OpenClawMemoryFact(scope, owner, name, value))
    }

    public func read(scope: String, owner: String, name: String): Option<String> {
        this.facts.get(this.key(scope, owner, name))
    }

    public func registerBackend(
        providerId: String,
        backend: String,
        searchEnabled!: Bool = true,
        indexPath!: String = ""
    ): OpenClawMemoryBackendBinding {
        let binding = OpenClawMemoryBackendBinding(providerId, backend, searchEnabled, indexPath)
        this.backends[providerId.trimAscii()] = binding
        binding
    }

    public func metisBackendSnapshot(agentId!: String = "", purpose!: String = "openclaw-runtime"): OpenClawMemoryBackendBinding {
        let resolved = MemoryRuntime.resolveResolvedBackendConfig(agentId: agentId, purpose: purpose)
        OpenClawMemoryBackendBinding(
            if (resolved.providerId.isEmpty()) { "memory-core" } else { resolved.providerId },
            if (resolved.backend.isEmpty()) { "local" } else { resolved.backend },
            resolved.searchEnabled,
            resolved.indexPath,
            agentId: resolved.agentId,
            purpose: resolved.purpose
        )
    }

    public func search(query: String, limit!: Int64 = 8, backendId!: String = "memory-core"): Array<OpenClawMemorySearchHit> {
        let normalizedQuery = query.trimAscii().toAsciiLower()
        let hits = ArrayList<OpenClawMemorySearchHit>()
        if (normalizedQuery.isEmpty() || limit <= 0) {
            return hits.toArray()
        }
        let effectiveBackend = if (backendId.trimAscii().isEmpty()) { "memory-core" } else { backendId.trimAscii() }
        for (fact in this.factRows) {
            let haystack = "${fact.scope} ${fact.owner} ${fact.name} ${fact.value}".toAsciiLower()
            if (haystack.contains(normalizedQuery)) {
                hits.add(OpenClawMemorySearchHit(effectiveBackend, fact.scope, fact.owner, fact.name, fact.value))
            }
            if (Int64(hits.size) >= limit) {
                break
            }
        }
        hits.toArray()
    }
}
