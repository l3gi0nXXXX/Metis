package metis.gateway.tools

import metis.core.{GatewayToolRuntimeContext, gatewayWithToolRuntimeContext}

import std.collection.ArrayList
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

private class FeishuMediaToolsetFakeResourceClient <: FeishuOapiResourceClient {
    public let captured = ArrayList<String>()

    public init() {}

    public func fetchMessageResource(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String
    ): FeishuOapiResourceResult {
        this.captured.add(accountId)
        this.captured.add(messageId)
        this.captured.add(fileKey)
        this.captured.add(resourceType)
        if (fileKey == "missing") {
            return FeishuOapiResourceResult(status: "not_found", error: "not found")
        }
        if (fileKey == "forbidden") {
            return FeishuOapiResourceResult(status: "forbidden", error: "forbidden")
        }
        if (fileKey == "rate") {
            return FeishuOapiResourceResult(status: "rate_limited", error: "rate limited")
        }
        if (fileKey == "auth_required") {
            return FeishuOapiResourceResult(status: "auth_required", error: "authorization required")
        }
        if (fileKey == "scope_missing") {
            return FeishuOapiResourceResult(status: "scope_missing", error: "missing im:message.resource:read")
        }
        FeishuOapiResourceResult(
            ok: true,
            status: "ok",
            bytes: "oapi-history".toArray(),
            contentType: "image/png",
            fileName: "../../history.png"
        )
    }
}

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

    @TestCase
    public func feishuHistoricalFetchDefaultsToOapiAuthRequiredWhenNoTestRunnerIsConfigured(): Unit {
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let context = JsonObject()
        context.put("feishuHistoricalResource", JsonObject())
        media.put("context", context)

        let out = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
            { => GatewayFeishuMediaToolset().debugFeishuFetchResourceForTest("om_history", "img_history", Some("image")) }
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(json.get("reason").getOrThrow().asString().getValue().contains("authorization"), true)
    }

    @TestCase
    public func feishuHistoricalFetchCanUseOapiResourceClientAndPreservesSafeTempCache(): Unit {
        let root = "/tmp/metis-feishu-oapi-history-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let policy = JsonObject()
        policy.put("cacheRoot", JsonString(root))
        policy.put("mediaMaxBytes", JsonInt(64))
        policy.put("allowedMimes", JsonArray([JsonString("image/png")]))
        let context = JsonObject()
        context.put("feishuHistoricalResource", policy)
        media.put("context", context)
        let client = FeishuMediaToolsetFakeResourceClient()
        setGatewayFeishuHistoricalResourceClientForTest(Some<FeishuOapiResourceClient>(client))
        try {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => GatewayFeishuMediaToolset().debugFeishuFetchResourceForTest("om_history", "img_history", Some("image")) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("relation").getOrThrow().asString().getValue(), "historical")
            @Expect(json.get("source").getOrThrow().asString().getValue(), "oapi")
            let savedPath = json.get("saved_path").getOrThrow().asString().getValue()
            @Expect(savedPath.startsWith(root), true)
            @Expect(savedPath.contains(".."), false)
            @Expect(exists(Path(savedPath)), true)
            @Expect(String.fromUtf8(File.readFrom(Path(savedPath))), "oapi-history")
            @Expect(client.captured[0], "tenant-a")
            @Expect(client.captured[1], "om_history")
            @Expect(client.captured[2], "img_history")
            @Expect(client.captured[3], "image")
        } finally {
            setGatewayFeishuHistoricalResourceClientForTest(None<FeishuOapiResourceClient>)
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func feishuHistoricalResourceLiveMissingExternalResourcesReturnsSkippedDiagnostic(): Unit {
        let report = GatewayFeishuResourceLiveSmokeChecklist.skippedExternalResourceReport()
        let raw = report.toJsonString()
        @Expect(report.get("status").getOrThrow().asString().getValue(), "skipped")
        @Expect(report.get("reason").getOrThrow().asString().getValue(), "external-resource-required")
        @Expect(report.get("networkAttempted").getOrThrow().asBool().getValue(), false)
        @Expect(report.get("redacted").getOrThrow().asBool().getValue(), true)
        @Expect(raw.contains("test_message_id"), true)
        @Expect(raw.contains("test_file_key"), true)
        @Expect(raw.contains("safe_temp_cache_root"), true)
        @Expect(raw.contains("Authorization"), false)
        @Expect(raw.contains("access_token"), false)
    }

    @TestCase
    public func feishuHistoricalFetchPropagatesOapiNotFoundForbiddenAndRateLimit(): Unit {
        let root = "/tmp/metis-feishu-oapi-errors-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let policy = JsonObject()
        policy.put("cacheRoot", JsonString(root))
        let context = JsonObject()
        context.put("feishuHistoricalResource", policy)
        media.put("context", context)
        let client = FeishuMediaToolsetFakeResourceClient()
        setGatewayFeishuHistoricalResourceClientForTest(Some<FeishuOapiResourceClient>(client))
        try {
            let toolset = GatewayFeishuMediaToolset()
            let missing = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "missing", Some("image")) }
            )
            @Expect(JsonValue.fromStr(missing).asObject().get("status").getOrThrow().asString().getValue(), "not_found")
            let forbidden = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "forbidden", Some("image")) }
            )
            @Expect(JsonValue.fromStr(forbidden).asObject().get("status").getOrThrow().asString().getValue(), "forbidden")
            let rate = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "rate", Some("image")) }
            )
            @Expect(JsonValue.fromStr(rate).asObject().get("status").getOrThrow().asString().getValue(), "rate_limited")
        } finally {
            setGatewayFeishuHistoricalResourceClientForTest(None<FeishuOapiResourceClient>)
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func feishuHistoricalFetchOapiAuthAndScopeDiagnosticsAreStructured(): Unit {
        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let context = JsonObject()
        context.put("feishuHistoricalResource", JsonObject())
        media.put("context", context)
        let client = FeishuMediaToolsetFakeResourceClient()
        setGatewayFeishuHistoricalResourceClientForTest(Some<FeishuOapiResourceClient>(client))
        try {
            let toolset = GatewayFeishuMediaToolset()
            let authRequired = JsonValue.fromStr(gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "auth_required", Some("image")) }
            )).asObject()
            @Expect(authRequired.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(authRequired.get("status").getOrThrow().asString().getValue(), "auth_required")
            @Expect(authRequired.get("relation").getOrThrow().asString().getValue(), "historical")
            @Expect(authRequired.get("source").getOrThrow().asString().getValue(), "oapi")
            @Expect(authRequired.get("auth_required").getOrThrow().asBool().getValue(), true)

            let scopeMissing = JsonValue.fromStr(gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
                { => toolset.debugFeishuFetchResourceForTest("om_history", "scope_missing", Some("image")) }
            )).asObject()
            @Expect(scopeMissing.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(scopeMissing.get("status").getOrThrow().asString().getValue(), "scope_missing")
            @Expect(scopeMissing.get("relation").getOrThrow().asString().getValue(), "historical")
            @Expect(scopeMissing.get("source").getOrThrow().asString().getValue(), "oapi")
            @Expect(scopeMissing.get("scope_missing").getOrThrow().asBool().getValue(), true)
            @Expect(scopeMissing.get("required_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:message.resource:read")
        } finally {
            setGatewayFeishuHistoricalResourceClientForTest(None<FeishuOapiResourceClient>)
        }
    }

    @TestCase
    public func feishuBotImageMapsCurrentTurnAndReportsNotConfiguredForHistoricalBotFetch(): Unit {
        let toolset = GatewayFeishuMediaToolset()
        let current = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: this.mediaContext()),
            { => toolset.debugFeishuBotImageForTest("om_1", "img_1", Some("image")) }
        )
        let currentJson = JsonValue.fromStr(current).asObject()
        @Expect(currentJson.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(currentJson.get("status").getOrThrow().asString().getValue(), "ok")
        @Expect(currentJson.get("identity").getOrThrow().asString().getValue(), "bot")

        let media = JsonObject()
        media.put("channel", JsonString("feishu"))
        media.put("accountId", JsonString("tenant-a"))
        let missing = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("feishu", channelName: "feishu", sessionKey: "feishu:chat:1", mediaContext: media),
            { => toolset.debugFeishuBotImageForTest("om_history", "img_history", Some("image")) }
        )
        let missingJson = JsonValue.fromStr(missing).asObject()
        @Expect(missingJson.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(missingJson.get("status").getOrThrow().asString().getValue(), "not_configured")
        @Expect(missingJson.get("identity").getOrThrow().asString().getValue(), "bot")
    }

    @TestCase
    public func feishuMediaStatusAndCleanupRejectUnsafeRootsAndCleanSafeAccountCache(): Unit {
        let safeRoot = "/tmp/metis-feishu-cleanup-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        let unsafeRoot = "/Users/l3gi0n/Downloads/metis-feishu-media"
        try { remove(Path(safeRoot), recursive: true) } catch (_e: Exception) { () }
        try {
            let unsafePolicy = JsonObject()
            unsafePolicy.put("cacheRoot", JsonString(unsafeRoot))
            let unsafeStatus = JsonValue.fromStr(GatewayFeishuMediaToolset().debugFeishuMediaStatusForTest(unsafePolicy, "tenant-a")).asObject()
            @Expect(unsafeStatus.get("safe_cache_root").getOrThrow().asBool().getValue(), false)

            let safePolicy = JsonObject()
            safePolicy.put("cacheRoot", JsonString(safeRoot))
            let accountDir = Path(safeRoot).join("tenant-a").join("om_1")
            Directory.create(accountDir, recursive: true)
            File.writeTo(accountDir.join("image.png"), "cache".toArray())
            let cleanup = JsonValue.fromStr(GatewayFeishuMediaToolset().debugFeishuMediaCleanupForTest(safePolicy, "tenant-a")).asObject()
            @Expect(cleanup.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(cleanup.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(exists(accountDir), false)
        } finally {
            try { remove(Path(safeRoot), recursive: true) } catch (_e: Exception) { () }
        }
    }
}
