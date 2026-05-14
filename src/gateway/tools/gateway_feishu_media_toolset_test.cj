package metis.gateway.tools

import metis.core.{GatewayToolRuntimeContext, gatewayWithToolRuntimeContext}

import std.fs.{File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

@Test
public class GatewayFeishuMediaToolsetTest {
    private func mediaContext(downloaded!: Bool = true, skippedReason!: String = ""): JsonObject {
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("default"))
        let records = JsonArray([])
        let record = JsonObject()
        record.put("mediaId", JsonString("default:oc_1:om_1:image:img_1"))
        record.put("channel", JsonString("feishu"))
        record.put("accountId", JsonString("default"))
        record.put("peerId", JsonString("oc_1"))
        record.put("messageId", JsonString("om_1"))
        record.put("mediaKind", JsonString("image"))
        record.put("resourceType", JsonString("image"))
        record.put("fileKey", JsonString("img_1"))
        record.put("fileId", JsonString("img_1"))
        record.put("fileName", JsonString("diagram.png"))
        record.put("mimeType", JsonString("image/png"))
        record.put("fileSize", JsonInt(10))
        record.put("downloaded", JsonBool(downloaded))
        record.put("skippedReason", JsonString(skippedReason))
        record.put("localPath", JsonString(if (downloaded) { "/tmp/metis-feishu-media/default/oc_1/om_1/diagram.png" } else { "" }))
        records.add(record)
        media.put("records", records)
        media
    }

    @TestCase
    public func feishuMediaListReadsCurrentRuntimeContext(): Unit {
        let out = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: this.mediaContext()),
            { => GatewayFeishuMediaToolset().debugFeishuMediaListForTest() }
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
        let record = json.get("records").getOrThrow().asArray()[0].asObject()
        @Expect(record.get("fileKey").getOrThrow().asString().getValue(), "img_1")
    }

    @TestCase
    public func feishuFetchResourceReturnsDownloadedLocalPath(): Unit {
        let out = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: this.mediaContext()),
            { => GatewayFeishuMediaToolset().debugFeishuFetchResourceForTest("om_1", "img_1", Some("image")) }
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
        @Expect(json.get("saved_path").getOrThrow().asString().getValue().contains("diagram.png"), true)
        @Expect(json.get("content_type").getOrThrow().asString().getValue(), "image/png")
    }

    @TestCase
    public func feishuFetchResourceReportsSkippedReason(): Unit {
        let out = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: this.mediaContext(downloaded: false, skippedReason: "forbidden")),
            { => GatewayFeishuMediaToolset().debugFeishuFetchResourceForTest("om_1", "img_1", Some("image")) }
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "forbidden")
        @Expect(json.get("reason").getOrThrow().asString().getValue(), "forbidden")
    }

    @TestCase
    public func feishuFetchResourceUsesHistoricalRunnerAndTempCacheWhenCurrentTurnMisses(): Unit {
        let root = "/tmp/metis-feishu-historical-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let policy = JsonObject()
        policy.put("cacheRoot", JsonString(root))
        policy.put("mediaMaxBytes", JsonInt(64))
        policy.put("allowedMimes", JsonArray([JsonString("image/*")]))
        let context = JsonObject()
        context.put("feishuHistoricalResource", policy)
        media.put("context", context)
        setGatewayFeishuHistoricalResourceRunnerForTest(Some({ request: JsonObject =>
            @Expect(request.get("accountId").getOrThrow().asString().getValue(), "tenant-a")
            @Expect(request.get("messageId").getOrThrow().asString().getValue(), "om_history")
            @Expect(request.get("fileKey").getOrThrow().asString().getValue(), "img_history")
            GatewayFeishuHistoricalResourceResult(
                ok: true,
                status: "ok",
                bytes: "historical-image".toArray(),
                contentType: "image/png",
                fileName: "../diagram.png"
            )
        }))
        try {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => GatewayFeishuMediaToolset().debugFeishuFetchResourceForTest("om_history", "img_history", Some("image")) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("relation").getOrThrow().asString().getValue(), "historical")
            let savedPath = json.get("saved_path").getOrThrow().asString().getValue()
            @Expect(savedPath.startsWith(root), true)
            @Expect(savedPath.contains(".."), false)
            @Expect(exists(Path(savedPath)), true)
            @Expect(String.fromUtf8(File.readFrom(Path(savedPath))), "historical-image")
        } finally {
            setGatewayFeishuHistoricalResourceRunnerForTest(None<(JsonObject) -> GatewayFeishuHistoricalResourceResult>)
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func feishuHistoricalFetchAppliesMimeSizeAndPermissionDiagnostics(): Unit {
        let root = "/tmp/metis-feishu-historical-guards-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let policy = JsonObject()
        policy.put("cacheRoot", JsonString(root))
        policy.put("mediaMaxBytes", JsonInt(4))
        policy.put("allowedMimes", JsonArray([JsonString("image/png")]))
        let context = JsonObject()
        context.put("feishuHistoricalResource", policy)
        media.put("context", context)
        setGatewayFeishuHistoricalResourceRunnerForTest(Some({ request: JsonObject =>
            let key = request.get("fileKey").getOrThrow().asString().getValue()
            if (key == "missing_scope") {
                return GatewayFeishuHistoricalResourceResult(status: "user_scope_missing", error: "missing im:message.resource:read")
            }
            if (key == "bad_mime") {
                return GatewayFeishuHistoricalResourceResult(ok: true, status: "ok", bytes: "abc".toArray(), contentType: "application/pdf", fileName: "doc.pdf")
            }
            GatewayFeishuHistoricalResourceResult(ok: true, status: "ok", bytes: "12345".toArray(), contentType: "image/png", fileName: "big.png")
        }))
        try {
            let toolset = GatewayFeishuMediaToolset()
            let missingScope = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "missing_scope", Some("image")) }
            )
            @Expect(JsonValue.fromStr(missingScope).asObject().get("status").getOrThrow().asString().getValue(), "user_scope_missing")
            let badMime = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "bad_mime", Some("file")) }
            )
            @Expect(JsonValue.fromStr(badMime).asObject().get("status").getOrThrow().asString().getValue(), "mime_not_allowed")
            let tooLarge = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "big_image", Some("image")) }
            )
            @Expect(JsonValue.fromStr(tooLarge).asObject().get("status").getOrThrow().asString().getValue(), "download_size_limit_exceeded")
        } finally {
            setGatewayFeishuHistoricalResourceRunnerForTest(None<(JsonObject) -> GatewayFeishuHistoricalResourceResult>)
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }
}
