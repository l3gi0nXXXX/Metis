package metis.core.model

public class OpenClawProviderRegistration {
    public let id: String
    public let authKind: String
    public let configKeys: Array<String>
    public let models: Array<String>
    public let supportsStreaming: Bool
    public let supportsToolCalls: Bool
    public let supportsModelList: Bool

    public init(
        id: String,
        authKind!: String = "",
        configKeys!: Array<String> = [],
        models!: Array<String> = [],
        supportsStreaming!: Bool = false,
        supportsToolCalls!: Bool = false,
        supportsModelList!: Bool = false
    ) {
        this.id = id.trimAscii()
        this.authKind = authKind.trimAscii().toAsciiLower()
        this.configKeys = configKeys
        this.models = models
        this.supportsStreaming = supportsStreaming
        this.supportsToolCalls = supportsToolCalls
        this.supportsModelList = supportsModelList
    }
}

public class OpenClawProviderProjection {
    public let id: String
    public let authKind: String
    public let configKeys: Array<String>
    public let models: Array<String>
    public let supportsStreaming: Bool
    public let supportsToolCalls: Bool
    public let supportsModelList: Bool

    public init(registration: OpenClawProviderRegistration) {
        this.id = registration.id
        this.authKind = registration.authKind
        this.configKeys = registration.configKeys
        this.models = registration.models
        this.supportsStreaming = registration.supportsStreaming
        this.supportsToolCalls = registration.supportsToolCalls
        this.supportsModelList = registration.supportsModelList
    }

    public func toSafeSummary(): String {
        "provider=${this.id};auth=${this.authKind};models=${String.join(this.models, delimiter: ",")};config=${String.join(this.configKeys, delimiter: ",")}"
    }
}

public class OpenClawProviderStreamChunk {
    public let kind: String
    public let content: String
    public let done: Bool

    public init(kind: String, content: String, done: Bool) {
        this.kind = kind
        this.content = content
        this.done = done
    }
}

public class OpenClawProviderToolCall {
    public let name: String
    public let argumentsJson: String

    public init(name: String, argumentsJson: String) {
        this.name = name.trimAscii()
        this.argumentsJson = argumentsJson
    }
}

public class OpenClawProviderBridge {
    public static func project(registration: OpenClawProviderRegistration): OpenClawProviderProjection {
        OpenClawProviderProjection(registration)
    }

    public static func fakeModelList(projection: OpenClawProviderProjection): Array<String> {
        if (!projection.supportsModelList) {
            return []
        }
        projection.models
    }

    public static func fakeStream(model: String, prompt: String): Array<OpenClawProviderStreamChunk> {
        [
            OpenClawProviderStreamChunk("partial-token", "[${model.trimAscii()}] ${prompt}", false),
            OpenClawProviderStreamChunk("done", "", true)
        ]
    }

    public static func fakeToolCall(name: String, argumentsJson: String): OpenClawProviderToolCall {
        OpenClawProviderToolCall(name, argumentsJson)
    }
}
