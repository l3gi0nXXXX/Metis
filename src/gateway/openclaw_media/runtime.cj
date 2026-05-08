package metis.gateway.openclaw_media

import std.collection.HashMap

public class OpenClawMediaRef {
    public let ref: String
    public let mimeType: String
    public let fileName: String
    public let payload: String

    public init(ref: String, mimeType: String, fileName: String, payload: String) {
        this.ref = ref.trimAscii()
        this.mimeType = mimeType.trimAscii().toAsciiLower()
        this.fileName = fileName.trimAscii()
        this.payload = payload
    }
}

public class OpenClawOutboundMediaRef {
    public let kind: String
    public let ref: String

    public init(ref: String) {
        this.kind = "outbound-media"
        this.ref = ref.trimAscii()
    }
}

public class OpenClawMediaRuntime {
    private var nextId: Int64 = 1
    private let refs = HashMap<String, OpenClawMediaRef>()

    public init() {}

    public func store(mimeType: String, fileName: String, payload: String): OpenClawMediaRef {
        let ref = "media-${this.nextId}"
        this.nextId += 1
        let stored = OpenClawMediaRef(ref, mimeType, fileName, payload)
        this.refs[ref] = stored
        stored
    }

    public func resolve(ref: String): Option<OpenClawMediaRef> {
        this.refs.get(ref.trimAscii())
    }

    public func outbound(ref: String): OpenClawOutboundMediaRef {
        OpenClawOutboundMediaRef(ref)
    }
}
