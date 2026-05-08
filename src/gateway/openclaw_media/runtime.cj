package metis.gateway.openclaw_media

import metis.core.{gatewayMediaUnderstandingFirstText, gatewayMediaUnderstandingForRecord}

import std.collection.HashMap
import stdx.encoding.json.{JsonBool, JsonObject, JsonString}

public class OpenClawMediaRef {
    public let contract: String = "metis.media-ref.v1"
    public let ref: String
    public let mimeType: String
    public let fileName: String
    public let payload: String
    public let localPath: String
    public let mediaKind: String

    public init(
        ref: String,
        mimeType: String,
        fileName: String,
        payload: String,
        localPath!: String = "",
        mediaKind!: String = ""
    ) {
        this.ref = ref.trimAscii()
        this.mimeType = mimeType.trimAscii().toAsciiLower()
        this.fileName = fileName.trimAscii()
        this.payload = payload
        this.localPath = localPath.trimAscii()
        this.mediaKind = mediaKind.trimAscii().toAsciiLower()
    }
}

public class OpenClawOutboundMediaRef {
    public let contract: String = "metis.outbound-media-ref.v1"
    public let kind: String
    public let ref: String
    public let channel: String
    public let caption: String

    public init(ref: String, channel!: String = "", caption!: String = "") {
        this.kind = "outbound-media"
        this.ref = ref.trimAscii()
        this.channel = channel.trimAscii().toAsciiLower()
        this.caption = caption
    }
}

public class OpenClawMediaUnderstandingResult {
    public let contract: String = "metis.media-understanding.v1"
    public let ok: Bool
    public let status: String
    public let capability: String
    public let ref: String
    public let text: String
    public let error: String

    public init(ok: Bool, status: String, capability: String, ref: String, text: String, error!: String = "") {
        this.ok = ok
        this.status = status.trimAscii()
        this.capability = capability.trimAscii()
        this.ref = ref.trimAscii()
        this.text = text
        this.error = error.trimAscii()
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

    public func storeMetisRef(
        mimeType: String,
        fileName: String,
        localPath: String,
        mediaKind!: String = "document"
    ): OpenClawMediaRef {
        let ref = "media-${this.nextId}"
        this.nextId += 1
        let stored = OpenClawMediaRef(ref, mimeType, fileName, "", localPath: localPath, mediaKind: mediaKind)
        this.refs[ref] = stored
        stored
    }

    public func resolve(ref: String): Option<OpenClawMediaRef> {
        this.refs.get(ref.trimAscii())
    }

    private func recordFor(ref: OpenClawMediaRef): JsonObject {
        let record = JsonObject()
        record.put("mediaId", JsonString(ref.ref))
        record.put("mediaKind", JsonString(if (ref.mediaKind.isEmpty()) { "document" } else { ref.mediaKind }))
        record.put("mimeType", JsonString(ref.mimeType))
        record.put("fileName", JsonString(ref.fileName))
        record.put("originalFileName", JsonString(ref.fileName))
        record.put("localPath", JsonString(ref.localPath))
        record.put("downloaded", JsonBool(!ref.localPath.isEmpty()))
        record
    }

    private func resultString(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(value) => try { value.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
            case None => ""
        }
    }

    private func resultBool(obj: JsonObject, key: String): Bool {
        match (obj.get(key)) {
            case Some(value) => try { value.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
    }

    public func understand(
        ref: String,
        capability!: String = "auto",
        prompt!: String = "",
        maxBytes!: Int64 = 8192
    ): OpenClawMediaUnderstandingResult {
        match (this.resolve(ref)) {
            case Some(media) =>
                let result = gatewayMediaUnderstandingForRecord(this.recordFor(media), capability: capability, prompt: prompt, maxBytes: maxBytes)
                OpenClawMediaUnderstandingResult(
                    this.resultBool(result, "ok"),
                    this.resultString(result, "status"),
                    this.resultString(result, "capability"),
                    media.ref,
                    gatewayMediaUnderstandingFirstText(result),
                    error: this.resultString(result, "error")
                )
            case None =>
                OpenClawMediaUnderstandingResult(false, "not_found", capability, ref, "", error: "media ref not found")
        }
    }

    public func outbound(ref: String, channel!: String = "", caption!: String = ""): OpenClawOutboundMediaRef {
        OpenClawOutboundMediaRef(ref, channel: channel, caption: caption)
    }
}
