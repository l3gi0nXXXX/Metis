package metis.gateway.tools

import metis.core.{GatewayMediaVideoHttpResult, GatewayToolRuntimeContext, gatewayWithToolRuntimeContext, setGatewayMediaVideoHttpRunnerForTest}
import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager}
import magic.core.message.Message
import magic.core.model.{AsyncChatResponse, ChatModel, ChatRequest, ChatResponse}
import magic.jsonable.*
import magic.model.ModelManager

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private class TelegramMediaToolsetVisionFakeModel <: ChatModel {
    private var _maxTokens: Option<Int64> = None

    public prop provider: String {
        get() { "fake" }
    }

    public prop name: String {
        get() { "telegram-vision" }
    }

    public prop contextLength: Int64 {
        get() { 8192 }
    }

    public mut prop maxTokens: Option<Int64> {
        get() { this._maxTokens }
        set(v) { this._maxTokens = v }
    }

    public func create(request: ChatRequest): ChatResponse {
        let first = request.messageList[0]
        let prefix = match (first.image) {
            case Some(v) => if (v.startsWith("data:image/jpeg;base64,")) { "image-ok" } else { "image-bad" }
            case None => "image-missing"
        }
        ChatResponse(this.fullName, Message.assistant("${prefix}: a red square"))
    }

    public func asyncCreate(request: ChatRequest): AsyncChatResponse {
        throw Exception("async not used in telegram media toolset tests")
    }
}

@Test
public class GatewayTelegramMediaToolsetTest {
    private func withTelegramMediaToolsetConfigHome<T>(block: () -> T): T {
        let testHome = "/tmp/metis-telegram-media-toolset-config-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            MetisConfigManager.initializeIfMissing()
            return block()
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
        }
    }

    private func mediaContext(localPath: String, mediaKind!: String = "photo", mimeType!: String = "image/jpeg", fileName!: String = "file_1.jpg", relation!: String = "current"): JsonObject {
        let media = JsonObject()
        let records = JsonArray([])
        let record = JsonObject()
        record.put("mediaId", JsonString("tg-default-user-101-photo-photo-file"))
        record.put("messageId", JsonString("101"))
        record.put("relation", JsonString(relation))
        record.put("mediaKind", JsonString(mediaKind))
        record.put("mimeType", JsonString(mimeType))
        record.put("originalFileName", JsonString(fileName))
        record.put("fileName", JsonString(fileName))
        record.put("localPath", JsonString(localPath))
        record.put("downloaded", JsonBool(true))
        record.put("channel", JsonString("telegram"))
        record.put("accountId", JsonString("default"))
        if (mediaKind == "sticker") {
            record.put("fileId", JsonString("sticker-file-id"))
            record.put("fileUniqueId", JsonString("sticker-unique-id"))
            record.put("emoji", JsonString("🙂"))
            record.put("setName", JsonString("MetisStickers"))
            record.put("description", JsonString("friendly metis sticker"))
        }
        records.add(record)
        media.put("records", records)
        media
    }

    private func telegramScopeContext(accountId: String, peerId: String, messageId: String): JsonObject {
        let media = JsonObject()
        media.put("channel", JsonString("telegram"))
        media.put("accountId", JsonString(accountId))
        media.put("peerId", JsonString(peerId))
        media.put("messageId", JsonString(messageId))
        media
    }

    private func recentRecord(localPath: String, accountId: String, peerId: String, messageId: String, mediaId: String, fileId: String): JsonObject {
        let record = JsonObject()
        record.put("mediaId", JsonString(mediaId))
        record.put("channel", JsonString("telegram"))
        record.put("accountId", JsonString(accountId))
        record.put("peerId", JsonString(peerId))
        record.put("messageId", JsonString(messageId))
        record.put("relation", JsonString("current"))
        record.put("mediaKind", JsonString("photo"))
        record.put("mimeType", JsonString("image/jpeg"))
        record.put("originalFileName", JsonString("photo.jpg"))
        record.put("fileName", JsonString("photo.jpg"))
        record.put("fileId", JsonString(fileId))
        record.put("fileUniqueId", JsonString("unique-${fileId}"))
        record.put("localPath", JsonString(localPath))
        record.put("downloaded", JsonBool(true))
        record.put("persistedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        record
    }

    private func writeAgentsImageModelConfig(primary: String, imagePrimary!: String = ""): Unit {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString(primary))
        defaults.put("model", model)
        if (!imagePrimary.trimAscii().isEmpty()) {
            let imageModel = JsonObject()
            imageModel.put("primary", JsonString(imagePrimary))
            defaults.put("imageModel", imageModel)
        }
        agents.put("defaults", defaults)
        root.put("agents", agents)
        MetisConfigManager.writeRoot(root)
        CliSettingManager.applyPersistedFieldsToCliConfig()
    }

    private func writeTelegramMediaState(accountId: String, records: JsonArray): Unit {
        let accountDir = CliConfig.dotDir.join("gateway-telegram").join("accounts").join(accountId)
        Directory.create(accountDir, recursive: true)
        let root = JsonObject()
        root.put("accountId", JsonString(accountId))
        root.put("records", records)
        if (records.size() > 0) {
            root.put("lastMedia", records[records.size() - 1])
        } else {
            root.put("lastMedia", JsonObject())
        }
        File.writeTo(accountDir.join("media-state.json"), root.toJsonString().toArray())
    }

    @TestCase
    public func telegramMediaListReadsCurrentRuntimeContext(): Unit {
        let toolset = GatewayTelegramMediaToolset()
        let context = this.mediaContext("/tmp/metis-media/file_1.jpg")
        let out = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
            { => toolset.debugTelegramMediaListForTest() }
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
        @Expect(json.get("records").getOrThrow().asArray()[0].asObject().get("mediaId").getOrThrow().asString().getValue(), "tg-default-user-101-photo-photo-file")
        @Expect(json.get("records").getOrThrow().asArray()[0].asObject().get("localPath").getOrThrow().asString().getValue(), "/tmp/metis-media/file_1.jpg")
    }

    @TestCase
    public func telegramMediaListFallsBackToRecentSamePeerMediaState(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let source = CliConfig.dotDir.join("recent.jpg")
            File.writeTo(source, "recent-image".toArray())
            let records = JsonArray([])
            records.add(this.recentRecord(source.toString(), "default", "user:100", "101", "media-old", "file-old"))
            records.add(this.recentRecord("/tmp/other-peer.jpg", "default", "user:200", "102", "media-other", "file-other"))
            this.writeTelegramMediaState("default", records)

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.telegramScopeContext("default", "user:100", "202")),
                { => toolset.debugTelegramMediaListForTest() }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
            let first = json.get("records").getOrThrow().asArray()[0].asObject()
            @Expect(first.get("mediaId").getOrThrow().asString().getValue(), "media-old")
            @Expect(first.get("sourceScope").getOrThrow().asString().getValue(), "recent")
            @Expect(first.get("localPath").getOrThrow().asString().getValue(), source.toString())
        })
    }

    @TestCase
    public func telegramMediaSaveFindsRecentMediaByTelegramFileId(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let source = CliConfig.dotDir.join("recent-save.jpg")
            let dest = CliConfig.dotDir.join("saved").join("recent-save.jpg")
            File.writeTo(source, "recent-save-image".toArray())
            let records = JsonArray([])
            records.add(this.recentRecord(source.toString(), "default", "user:100", "101", "media-recent", "telegram-file-id"))
            this.writeTelegramMediaState("default", records)

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.telegramScopeContext("default", "user:100", "202")),
                { => toolset.debugTelegramMediaSaveForTest(Some(dest.toString()), Some("telegram-file-id"), None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "saved")
            @Expect(json.get("mediaId").getOrThrow().asString().getValue(), "media-recent")
            @Expect(exists(dest), true)
            @Expect(String.fromUtf8(File.readFrom(dest)), "recent-save-image")
        })
    }

    @TestCase
    public func telegramRecentMediaFallbackDoesNotCrossAccountOrPeer(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let defaultSource = CliConfig.dotDir.join("default.jpg")
            let workSource = CliConfig.dotDir.join("work.jpg")
            File.writeTo(defaultSource, "default-image".toArray())
            File.writeTo(workSource, "work-image".toArray())
            let defaultRecords = JsonArray([])
            defaultRecords.add(this.recentRecord(defaultSource.toString(), "default", "user:100", "101", "media-default", "file-default"))
            defaultRecords.add(this.recentRecord("/tmp/other-peer.jpg", "default", "user:200", "102", "media-other", "file-other"))
            this.writeTelegramMediaState("default", defaultRecords)
            let workRecords = JsonArray([])
            workRecords.add(this.recentRecord(workSource.toString(), "work", "user:100", "201", "media-work", "file-work"))
            this.writeTelegramMediaState("work", workRecords)

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.telegramScopeContext("work", "user:100", "202")),
                { => toolset.debugTelegramMediaListForTest() }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
            let first = json.get("records").getOrThrow().asArray()[0].asObject()
            @Expect(first.get("mediaId").getOrThrow().asString().getValue(), "media-work")
            @Expect(first.get("accountId").getOrThrow().asString().getValue(), "work")
        })
    }

    @TestCase
    public func telegramMediaSaveCopiesDownloadedCurrentMedia(): Unit {
        let root = Path("/tmp/metis-telegram-media-tool-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("source.jpg")
        let dest = root.join("out").join("saved.jpg")
        File.writeTo(source, "fake-image-bytes".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramMediaSaveForTest(Some(dest.toString()), None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "saved")
            @Expect(exists(dest), true)
            @Expect(String.fromUtf8(File.readFrom(dest)), "fake-image-bytes")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramMediaSaveWithoutDestinationKeepsTelegramArchivePath(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
            let archiveDir = CliConfig.dotDir.join("gateway-telegram").join("accounts").join("default").join("media").join("2026-05-07").join("user-100")
            Directory.create(archiveDir, recursive: true)
            let source = archiveDir.join("archive-default-${stamp}.jpg")
            File.writeTo(source, "archive-image".toArray())
            let workspaceTarget = CliConfig.cwd.join("archive-default-${stamp}.jpg")

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramMediaSaveForTest(None<String>, None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "saved")
            @Expect(json.get("destination").getOrThrow().asString().getValue(), source.toString())
            @Expect(json.get("archivePath").getOrThrow().asString().getValue(), source.toString())
            @Expect(json.get("copied").getOrThrow().asBool().getValue(), false)
            @Expect(json.get("alreadyArchived").getOrThrow().asBool().getValue(), true)
            @Expect(exists(source), true)
            @Expect(exists(workspaceTarget), false)
        })
    }

    @TestCase
    public func telegramMediaSaveRelativeDestinationStaysInsideTelegramArchive(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
            let archiveDir = CliConfig.dotDir.join("gateway-telegram").join("accounts").join("default").join("media").join("2026-05-07").join("user-100")
            Directory.create(archiveDir, recursive: true)
            let source = archiveDir.join("archive-relative-source-${stamp}.jpg")
            File.writeTo(source, "archive-relative-image".toArray())
            let relativeName = "archive-relative-copy-${stamp}.jpg"
            let expectedDest = archiveDir.join(relativeName)
            let workspaceTarget = CliConfig.cwd.join(relativeName)

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramMediaSaveForTest(Some(relativeName), None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "saved")
            @Expect(json.get("destination").getOrThrow().asString().getValue(), expectedDest.toString())
            @Expect(json.get("copied").getOrThrow().asBool().getValue(), true)
            @Expect(exists(expectedDest), true)
            @Expect(String.fromUtf8(File.readFrom(expectedDest)), "archive-relative-image")
            @Expect(exists(workspaceTarget), false)
        })
    }

    @TestCase
    public func telegramMediaSaveImagePlaceholderKeepsTelegramArchivePath(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
            let archiveDir = CliConfig.dotDir.join("gateway-telegram").join("accounts").join("default").join("media").join("2026-05-07").join("user-100")
            Directory.create(archiveDir, recursive: true)
            let source = archiveDir.join("archive-placeholder-${stamp}.jpg")
            File.writeTo(source, "archive-placeholder-image".toArray())

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramMediaSaveForTest(Some("[Image #1]"), None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "saved")
            @Expect(json.get("destination").getOrThrow().asString().getValue(), source.toString())
            @Expect(json.get("copied").getOrThrow().asBool().getValue(), false)
            @Expect(json.get("alreadyArchived").getOrThrow().asBool().getValue(), true)
        })
    }

    @TestCase
    public func telegramMediaSaveRejectsMetisWorkspaceDestination(): Unit {
        this.withTelegramMediaToolsetConfigHome({ =>
            let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
            let archiveDir = CliConfig.dotDir.join("gateway-telegram").join("accounts").join("default").join("media").join("2026-05-07").join("user-100")
            Directory.create(archiveDir, recursive: true)
            let source = archiveDir.join("archive-workspace-denied-${stamp}.jpg")
            File.writeTo(source, "archive-workspace-image".toArray())
            let workspaceDest = CliConfig.cwd.join("telegram-media-save-denied-${stamp}.jpg")

            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:100", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramMediaSaveForTest(Some(workspaceDest.toString()), None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "denied")
            @Expect(json.get("error").getOrThrow().asString().getValue().contains("Metis workspace"), true)
            @Expect(exists(workspaceDest), false)
        })
    }

    @TestCase
    public func telegramMediaGetFindsByMediaIdAndRelation(): Unit {
        let toolset = GatewayTelegramMediaToolset()
        let context = this.mediaContext("/tmp/metis-media/file_1.jpg", relation: "replyTarget")
        let out = gatewayWithToolRuntimeContext(
            GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
            { => toolset.debugTelegramMediaGetForTest(Some("tg-default-user-101-photo-photo-file"), None<Int64>, None<String>, Some("replyTarget")) }
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
        @Expect(json.get("media").getOrThrow().asObject().get("relation").getOrThrow().asString().getValue(), "replyTarget")
    }

    @TestCase
    public func telegramMediaReadReadsTextDocumentsOnly(): Unit {
        let root = Path("/tmp/metis-telegram-media-read-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("note.txt")
        File.writeTo(source, "hello from telegram file".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext(
                    "telegram",
                    channelName: "telegram",
                    sessionKey: "telegram:chat:1",
                    mediaContext: this.mediaContext(source.toString(), mediaKind: "document", mimeType: "text/plain", fileName: "note.txt")
                ),
                { => toolset.debugTelegramMediaReadForTest(None<String>, None<Int64>, Some(100)) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("readable").getOrThrow().asBool().getValue(), true)
            @Expect(json.get("content").getOrThrow().asString().getValue(), "hello from telegram file")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramMediaReadRefusesBinaryFiles(): Unit {
        let root = Path("/tmp/metis-telegram-media-binary-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("file_1.jpg")
        File.writeTo(source, "fake-image".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext(
                    "telegram",
                    channelName: "telegram",
                    sessionKey: "telegram:chat:1",
                    mediaContext: this.mediaContext(source.toString(), mediaKind: "photo", mimeType: "image/jpeg", fileName: "file_1.jpg")
                ),
                { => toolset.debugTelegramMediaReadForTest(None<String>, None<Int64>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("readable").getOrThrow().asBool().getValue(), false)
            @Expect(json.get("reason").getOrThrow().asString().getValue().contains("not a text-readable"), true)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramMediaSaveRejectsProtectedConfigPath(): Unit {
        let root = Path("/tmp/metis-telegram-media-protected-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("source.jpg")
        File.writeTo(source, "fake".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramMediaSaveForTest(Some("/Users/test/.metis/metis.json"), None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "denied")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramImageAnalyzeReadsVisionSidecar(): Unit {
        let root = Path("/tmp/metis-telegram-image-analysis-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("image.jpg")
        File.writeTo(source, "fake".toArray())
        File.writeTo(Path(source.toString() + ".analysis.txt"), "a red square".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramImageAnalyzeForTest(None<String>, None<Int64>, Some("describe")) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("analysis").getOrThrow().asString().getValue(), "a red square")
            @Expect(json.get("capability").getOrThrow().asString().getValue(), "image")
            @Expect(json.get("source").getOrThrow().asString().getValue(), "analysis_companion_file")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramImageAnalyzeUsesConfiguredVisionModelWhenNoSidecarExists(): Unit {
        let root = Path("/tmp/metis-telegram-image-model-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("image.jpg")
        File.writeTo(source, "fake".toArray())
        let modelName = "metis-test-telegram-vision-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        ModelManager.registerChatModel(modelName, { => TelegramMediaToolsetVisionFakeModel() })
        setGatewayTelegramMediaVisionCandidatesForTest(Some([modelName]))
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramImageAnalyzeForTest(None<String>, None<Int64>, Some("describe this image")) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("analysis").getOrThrow().asString().getValue().contains("image-ok"), true)
            @Expect(json.get("model").getOrThrow().asString().getValue(), "fake:telegram-vision")
        } finally {
            setGatewayTelegramMediaVisionCandidatesForTest(None<Array<String>>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramImageAnalyzeSkipsDeepseekTextModelCandidate(): Unit {
        let root = Path("/tmp/metis-telegram-image-deepseek-skip-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("image.jpg")
        File.writeTo(source, "fake".toArray())
        setGatewayTelegramMediaVisionCandidatesForTest(Some(["deepseek/deepseek-v4-pro"]))
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                { => toolset.debugTelegramImageAnalyzeForTest(None<String>, None<Int64>, Some("describe this image")) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "unsupported")
            @Expect(json.get("attempts").getOrThrow().asArray()[0].asObject().get("status").getOrThrow().asString().getValue(), "unsupported_model")
            @Expect(json.get("fallback").getOrThrow().asString().getValue().contains("agents.defaults.imageModel.primary"), true)
        } finally {
            setGatewayTelegramMediaVisionCandidatesForTest(None<Array<String>>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramImageAnalyzeSkipsDeepSeekPrimaryWhenImageModelIsMissing(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let root = Path("/tmp/metis-telegram-image-deepseek-primary-skip-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            Directory.create(root, recursive: true)
            let source = root.join("image.jpg")
            File.writeTo(source, "fake".toArray())
            let oldModel = CliConfig.modelOrEmpty()
            this.writeAgentsImageModelConfig("deepseek/deepseek-v4-pro")
            ModelManager.registerChatModel("deepseek:deepseek-v4-pro", { => TelegramMediaToolsetVisionFakeModel() })
            try {
                let toolset = GatewayTelegramMediaToolset()
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                    { => toolset.debugTelegramImageAnalyzeForTest(None<String>, None<Int64>, Some("describe this image")) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
                @Expect(out.contains("image-ok"), false)
                @Expect(out.contains("provider_error"), false)
                @Expect(out.contains("unsupported_model"), true)
                @Expect(out.contains("agents.defaults.imageModel.primary"), true)
            } finally {
                if (oldModel.isEmpty()) {
                    CliConfig.clearPrimaryModelForTest()
                } else {
                    CliConfig.model = oldModel
                }
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func telegramImageAnalyzeUsesAgentsImageModelBeforeDeepSeekPrimary(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let root = Path("/tmp/metis-telegram-image-image-model-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            Directory.create(root, recursive: true)
            let source = root.join("image.jpg")
            File.writeTo(source, "fake".toArray())
            let oldModel = CliConfig.modelOrEmpty()
            this.writeAgentsImageModelConfig("deepseek/deepseek-v4-pro", imagePrimary: "fake/telegram-vision")
            ModelManager.registerChatModel("fake:telegram-vision", { => TelegramMediaToolsetVisionFakeModel() })
            ModelManager.registerChatModel("deepseek:deepseek-v4-pro", { => TelegramMediaToolsetVisionFakeModel() })
            try {
                let toolset = GatewayTelegramMediaToolset()
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: this.mediaContext(source.toString())),
                    { => toolset.debugTelegramImageAnalyzeForTest(None<String>, None<Int64>, Some("describe this image")) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
                @Expect(json.get("analysis").getOrThrow().asString().getValue().contains("image-ok"), true)
                @Expect(json.get("model").getOrThrow().asString().getValue(), "fake:telegram-vision")
            } finally {
                if (oldModel.isEmpty()) {
                    CliConfig.clearPrimaryModelForTest()
                } else {
                    CliConfig.model = oldModel
                }
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func telegramAudioTranscribeReadsTranscriptSidecar(): Unit {
        let root = Path("/tmp/metis-telegram-audio-transcript-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("voice.ogg")
        File.writeTo(source, "fake".toArray())
        File.writeTo(Path(source.toString() + ".transcript.txt"), "hello voice".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext(
                    "telegram",
                    channelName: "telegram",
                    sessionKey: "telegram:chat:1",
                    mediaContext: this.mediaContext(source.toString(), mediaKind: "voice", mimeType: "audio/ogg", fileName: "voice.ogg")
                ),
                { => toolset.debugTelegramAudioTranscribeForTest(None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("transcript").getOrThrow().asString().getValue(), "hello voice")
            @Expect(json.get("capability").getOrThrow().asString().getValue(), "audio")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramAudioTranscribeReportsUnifiedRuntimeNotConfigured(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let root = Path("/tmp/metis-telegram-audio-runtime-not-configured-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            Directory.create(root, recursive: true)
            let source = root.join("voice.ogg")
            File.writeTo(source, "fake".toArray())
            try {
                let toolset = GatewayTelegramMediaToolset()
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext(
                        "telegram",
                        channelName: "telegram",
                        sessionKey: "telegram:chat:1",
                        mediaContext: this.mediaContext(source.toString(), mediaKind: "voice", mimeType: "audio/ogg", fileName: "voice.ogg")
                    ),
                    { => toolset.debugTelegramAudioTranscribeForTest(None<String>, None<Int64>) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "unsupported")
                @Expect(json.get("ASRStatus").getOrThrow().asString().getValue(), "not_configured")
                @Expect(json.get("capability").getOrThrow().asString().getValue(), "audio")
                let decision = json.get("decision").getOrThrow().asObject()
                @Expect(decision.get("outcome").getOrThrow().asString().getValue(), "not_configured")
            } finally {
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func telegramAudioTranscribeUsesSharedGatewayAsrProvider(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let root = Path("/tmp/metis-telegram-audio-shared-asr-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            Directory.create(root, recursive: true)
            let source = root.join("voice.ogg")
            File.writeTo(source, "fake".toArray())
            var user = GatewayUserSettings()
            let provider = JsonObject()
            provider.put("kind", JsonString("command"))
            provider.put("command", JsonArray([JsonString("sh"), JsonString("-c"), JsonString("printf 'shared tool transcript'")]))
            let providers = JsonObject()
            providers.put("shared", provider)
            user.speech.asr.put("enabled", true.toJsonValue())
            user.speech.asr.put("provider", JsonString("shared"))
            user.speech.asr.put("providers", providers)
            CliSettingManager.writeGatewaySettings(user)
            try {
                let toolset = GatewayTelegramMediaToolset()
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext(
                        "telegram",
                        channelName: "telegram",
                        sessionKey: "telegram:chat:1",
                        mediaContext: this.mediaContext(source.toString(), mediaKind: "voice", mimeType: "audio/ogg", fileName: "voice.ogg")
                    ),
                    { => toolset.debugTelegramAudioTranscribeForTest(None<String>, None<Int64>) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("ASRStatus").getOrThrow().asString().getValue(), "transcribed")
                @Expect(json.get("transcript").getOrThrow().asString().getValue(), "shared tool transcript")
            } finally {
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func telegramVideoDescribeReadsVideoCompanion(): Unit {
        let root = Path("/tmp/metis-telegram-video-description-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("clip.mp4")
        File.writeTo(source, "fake-video".toArray())
        File.writeTo(Path(source.toString() + ".video.txt"), "short product demo clip".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext(
                    "telegram",
                    channelName: "telegram",
                    sessionKey: "telegram:chat:1",
                    mediaContext: this.mediaContext(source.toString(), mediaKind: "video", mimeType: "video/mp4", fileName: "clip.mp4")
                ),
                { => toolset.debugTelegramVideoDescribeForTest(None<String>, None<Int64>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("description").getOrThrow().asString().getValue(), "short product demo clip")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramVideoDescribeReportsProviderErrorAsReadableStatus(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let root = Path("/tmp/metis-telegram-video-provider-error-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            Directory.create(root, recursive: true)
            let source = root.join("clip.mp4")
            File.writeTo(source, "fake-video".toArray())
            var user = GatewayUserSettings()
            let provider = JsonObject()
            provider.put("kind", JsonString("gemini-inline-video"))
            provider.put("apiKey", JsonString("secret-video-key"))
            provider.put("baseUrl", JsonString("https://gemini.example/v1beta"))
            provider.put("model", JsonString("gemini-3-flash-preview"))
            let providers = JsonObject()
            providers.put("gemini", provider)
            user.media.video.put("enabled", JsonBool(true))
            user.media.video.put("provider", JsonString("gemini"))
            user.media.video.put("providers", providers)
            CliSettingManager.writeGatewaySettings(user)
            setGatewayMediaVideoHttpRunnerForTest(Some({ _request: JsonObject =>
                GatewayMediaVideoHttpResult(500, bodyBytes: "{\"error\":\"secret-video-key provider exploded\"}".toArray())
            }))
            try {
                let toolset = GatewayTelegramMediaToolset()
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext(
                        "telegram",
                        channelName: "telegram",
                        sessionKey: "telegram:chat:1",
                        mediaContext: this.mediaContext(source.toString(), mediaKind: "video", mimeType: "video/mp4", fileName: "clip.mp4")
                    ),
                    { => toolset.debugTelegramVideoDescribeForTest(None<String>, None<Int64>) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
                @Expect(json.get("status").getOrThrow().asString().getValue(), "provider_error")
                @Expect(json.get("videoUnderstandingStatus").getOrThrow().asString().getValue(), "provider_error")
                @Expect(json.get("error").getOrThrow().asString().getValue().contains("video understanding provider failed"), true)
                @Expect(out.contains("secret-video-key"), false)
                @Expect(out.startsWith("{"), true)
            } finally {
                setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func telegramDocumentExtractReadsCompanionForBinaryDocument(): Unit {
        let root = Path("/tmp/metis-telegram-document-extract-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("report.pdf")
        File.writeTo(source, "fake-pdf".toArray())
        File.writeTo(Path(source.toString() + ".extract.txt"), "pdf extracted summary".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext(
                    "telegram",
                    channelName: "telegram",
                    sessionKey: "telegram:chat:1",
                    mediaContext: this.mediaContext(source.toString(), mediaKind: "document", mimeType: "application/pdf", fileName: "report.pdf")
                ),
                { => toolset.debugTelegramDocumentExtractForTest(None<String>, None<Int64>, Some(100)) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("readable").getOrThrow().asBool().getValue(), true)
            @Expect(json.get("content").getOrThrow().asString().getValue(), "pdf extracted summary")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramStickerAnalysisWritesDurableCacheDescription(): Unit {
        let root = Path("/tmp/metis-telegram-sticker-analysis-cache-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        setGatewayTelegramStickerCacheRootForTest(Some(root))
        Directory.create(root, recursive: true)
        let source = root.join("sticker.webp")
        File.writeTo(source, "fake-sticker".toArray())
        File.writeTo(Path(source.toString() + ".analysis.txt"), "smiling sticker with blue text".toArray())
        try {
            let toolset = GatewayTelegramMediaToolset()
            let context = this.mediaContext(source.toString(), mediaKind: "sticker", mimeType: "image/webp", fileName: "sticker.webp")
            context.get("records").getOrThrow().asArray()[0].asObject().put("description", JsonString(""))
            let analyzed = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
                { => toolset.debugTelegramImageAnalyzeForTest(None<String>, None<Int64>, Some("describe sticker")) }
            )
            @Expect(JsonValue.fromStr(analyzed).asObject().get("analysis").getOrThrow().asString().getValue(), "smiling sticker with blue text")
            let searched = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: JsonObject()),
                { => GatewayTelegramMediaToolset().debugTelegramStickerSearchForTest("blue text", Some(5)) }
            )
            let json = JsonValue.fromStr(searched).asObject()
            @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
        } finally {
            setGatewayTelegramStickerCacheRootForTest(None<Path>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramStickerSearchReadsCurrentContext(): Unit {
        let root = Path("/tmp/metis-telegram-sticker-cache-search-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        setGatewayTelegramStickerCacheRootForTest(Some(root))
        let toolset = GatewayTelegramMediaToolset()
        let context = this.mediaContext("/tmp/metis-media/sticker.webp", mediaKind: "sticker", mimeType: "image/webp", fileName: "sticker.webp")
        try {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
                { => toolset.debugTelegramStickerSearchForTest("friendly", Some(5)) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
            let first = json.get("stickers").getOrThrow().asArray()[0].asObject()
            @Expect(first.get("setName").getOrThrow().asString().getValue(), "MetisStickers")
        } finally {
            setGatewayTelegramStickerCacheRootForTest(None<Path>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramStickerGetReadsCurrentContextByFileUniqueId(): Unit {
        let root = Path("/tmp/metis-telegram-sticker-cache-get-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        setGatewayTelegramStickerCacheRootForTest(Some(root))
        let toolset = GatewayTelegramMediaToolset()
        let context = this.mediaContext("/tmp/metis-media/sticker.webp", mediaKind: "sticker", mimeType: "image/webp", fileName: "sticker.webp")
        try {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
                { => toolset.debugTelegramStickerGetForTest(None<String>, Some("sticker-unique-id"), None<String>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            let sticker = json.get("sticker").getOrThrow().asObject()
            @Expect(sticker.get("fileId").getOrThrow().asString().getValue(), "sticker-file-id")
            @Expect(sticker.get("description").getOrThrow().asString().getValue(), "friendly metis sticker")
        } finally {
            setGatewayTelegramStickerCacheRootForTest(None<Path>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramStickerCacheStatsCountsCurrentContext(): Unit {
        let root = Path("/tmp/metis-telegram-sticker-cache-stats-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        setGatewayTelegramStickerCacheRootForTest(Some(root))
        let toolset = GatewayTelegramMediaToolset()
        let context = this.mediaContext("/tmp/metis-media/sticker.webp", mediaKind: "sticker", mimeType: "image/webp", fileName: "sticker.webp")
        try {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
                { => toolset.debugTelegramStickerCacheStatsForTest() }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("stickerCount").getOrThrow().asInt().getValue(), 1)
            @Expect(json.get("describedCount").getOrThrow().asInt().getValue(), 1)
            @Expect(exists(root.join("sticker-cache.json")), true)
        } finally {
            setGatewayTelegramStickerCacheRootForTest(None<Path>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramStickerSearchReadsDurableCacheAfterContextClears(): Unit {
        let root = Path("/tmp/metis-telegram-sticker-cache-durable-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        setGatewayTelegramStickerCacheRootForTest(Some(root))
        try {
            let toolset = GatewayTelegramMediaToolset()
            let context = this.mediaContext("/tmp/metis-media/sticker.webp", mediaKind: "sticker", mimeType: "image/webp", fileName: "sticker.webp")
            let first = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: context),
                { => toolset.debugTelegramStickerSearchForTest("friendly", Some(5)) }
            )
            @Expect(JsonValue.fromStr(first).asObject().get("count").getOrThrow().asInt().getValue(), 1)
            let second = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: JsonObject()),
                { => GatewayTelegramMediaToolset().debugTelegramStickerSearchForTest("friendly", Some(5)) }
            )
            @Expect(JsonValue.fromStr(second).asObject().get("count").getOrThrow().asInt().getValue(), 1)
        } finally {
            setGatewayTelegramStickerCacheRootForTest(None<Path>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramTargetListReadsAuditEnvelope(): Unit {
        let row = JsonObject()
        row.put("kind", JsonString("user"))
        row.put("id", JsonString("user:123"))
        row.put("displayName", JsonString("user:123"))
        row.put("accountId", JsonString("default"))
        let rows = JsonArray([row])
        let directory = JsonObject()
        directory.put("rows", rows)
        let telegram = JsonObject()
        telegram.put("directory", directory)
        let audit = JsonObject()
        audit.put("telegram", telegram)
        let envelope = JsonObject()
        envelope.put("audit", audit)
        let out = GatewayTelegramMediaToolset().debugTelegramTargetListFromAuditForTest(envelope)
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("count").getOrThrow().asInt().getValue(), 1)
        @Expect(json.get("targets").getOrThrow().asArray()[0].asObject().get("id").getOrThrow().asString().getValue(), "user:123")
    }

    @TestCase
    public func telegramDoctorReadsDiagnosticsEnvelope(): Unit {
        let summary = JsonObject()
        summary.put("state", JsonString("ready"))
        let diagnostics = JsonObject()
        diagnostics.put("summary", summary)
        let doctor = JsonObject()
        doctor.put("telegramDiagnostics", diagnostics)
        let envelope = JsonObject()
        envelope.put("doctor", doctor)
        let out = GatewayTelegramMediaToolset().debugTelegramDoctorFromEnvelopeForTest(envelope)
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("summary").getOrThrow().asObject().get("state").getOrThrow().asString().getValue(), "ready")
    }

    @TestCase
    public func telegramTargetWritebackDryRunDoesNotMutateConfig(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "user:old"
            MetisConfigManager.setGatewaySettings(user)

            let out = GatewayTelegramMediaToolset().debugTelegramTargetWritebackDryRunForTest("@metis_user", Some("12345"))
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "dry_run")
            @Expect(json.get("defaultTo").getOrThrow().asString().getValue(), "user:12345")
            @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "user:old")
        }
    }

    @TestCase
    public func telegramTargetWritebackDryRunAutoResolvesUsernameWithGetChat(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "user:old"
            MetisConfigManager.setGatewaySettings(user)
            let toolset = GatewayTelegramMediaToolset()
            toolset.debugSetGatewayCallRunnerForTest(Some({ method: String, params: JsonObject =>
                let out = JsonObject()
                @Expect(method, "channels.telegram.getChat")
                @Expect(params.get("chatId").getOrThrow().asString().getValue(), "@demo")
                out.put("ok", JsonBool(true))
                out.put("chatId", JsonString("-1001234567890"))
                out
            }))
            try {
                let out = toolset.debugTelegramTargetWritebackDryRunForTest("https://t.me/demo", None<String>)
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "dry_run")
                @Expect(json.get("defaultTo").getOrThrow().asString().getValue(), "group:-1001234567890")
                @Expect(json.get("cronTarget").getOrThrow().asString().getValue(), "not_applicable")
                @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "user:old")
            } finally {
                toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            }
        }
    }

    @TestCase
    public func telegramTargetWritebackGetChatFailureDoesNotMutateConfig(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "user:old"
            MetisConfigManager.setGatewaySettings(user)
            let toolset = GatewayTelegramMediaToolset()
            toolset.debugSetGatewayCallRunnerForTest(Some({ _method: String, _params: JsonObject =>
                let out = JsonObject()
                out.put("ok", JsonBool(false))
                out.put("reason", JsonString("chat not found"))
                out
            }))
            try {
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", operatorScopes: ["operator.admin"]),
                    { => toolset.debugTelegramTargetWritebackApplyForTest("@missing", None<String>) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "error")
                @Expect(json.get("error").getOrThrow().asString().getValue().contains("chat not found"), true)
                @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "user:old")
            } finally {
                toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            }
        }
    }

    @TestCase
    public func telegramTargetWritebackApplyRequiresAdminScope(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", operatorScopes: []),
                { => GatewayTelegramMediaToolset().debugTelegramTargetWritebackApplyForTest("12345", None<String>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "denied")
            @Expect(json.get("error").getOrThrow().asString().getValue().contains("operator.admin"), true)
        }
    }

    @TestCase
    public func telegramTargetWritebackApplyUsesMetisConfigManagerInTempHome(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", operatorScopes: ["operator.admin"]),
                { => GatewayTelegramMediaToolset().debugTelegramTargetWritebackApplyForTest("-100123", None<String>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "applied")
            @Expect(json.get("defaultTo").getOrThrow().asString().getValue(), "group:-100123")
            @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "group:-100123")
            @Expect(MetisConfigManager.configPath().toString().contains("/tmp/metis-telegram-media-toolset-config-"), true)
        }
    }

    @TestCase
    public func telegramTargetWritebackApplyRespectsConfigWritesPolicy(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "user:old"
            user.telegram.configWrites = false
            MetisConfigManager.setGatewaySettings(user)
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", operatorScopes: ["operator.admin"]),
                { => GatewayTelegramMediaToolset().debugTelegramTargetWritebackApplyForTest("12345", None<String>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "denied")
            @Expect(json.get("error").getOrThrow().asString().getValue().contains("configWrites"), true)
            @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "user:old")
        }
    }

    @TestCase
    public func telegramSendToUsernameTargetResolvesWithGetChatAndSendsWithoutWriteback(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "user:old"
            MetisConfigManager.setGatewaySettings(user)
            let toolset = GatewayTelegramMediaToolset()
            toolset.debugSetGatewayCallRunnerForTest(Some({ method: String, params: JsonObject =>
                let out = JsonObject()
                if (method == "channels.telegram.getChat") {
                    @Expect(params.get("chatId").getOrThrow().asString().getValue(), "@demo")
                    out.put("ok", JsonBool(true))
                    out.put("chatId", JsonString("-1001234567890"))
                    return out
                }
                @Expect(method, "channels.send")
                @Expect(params.get("peerId").getOrThrow().asString().getValue(), "group:-1001234567890")
                out.put("ok", JsonBool(true))
                out.put("messageId", JsonString("501"))
                out
            }))
            try {
                let out = toolset.debugTelegramSendToTargetForTest("@demo", "hello", None<String>, None<Bool>)
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "accepted")
                @Expect(json.get("resolvedTarget").getOrThrow().asString().getValue(), "group:-1001234567890")
                @Expect(json.get("writeback").isNone(), true)
                @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "user:old")
            } finally {
                toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            }
        }
    }

    @TestCase
    public func telegramSendToDirectoryDisplayTargetAndDryRunWritebackArePolicyControlled(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "user:old"
            MetisConfigManager.setGatewaySettings(user)
            let toolset = GatewayTelegramMediaToolset()
            toolset.debugSetGatewayCallRunnerForTest(Some({ method: String, params: JsonObject =>
                let out = JsonObject()
                if (method == "channels.audit") {
                    let row = JsonObject()
                    row.put("kind", JsonString("group"))
                    row.put("id", JsonString("group:-10042"))
                    row.put("displayName", JsonString("Ops Room"))
                    row.put("accountId", JsonString("default"))
                    row.put("source", JsonString("directory"))
                    row.put("canSend", JsonBool(true))
                    let rows = JsonArray([])
                    rows.add(row)
                    let directory = JsonObject()
                    directory.put("rows", rows)
                    let telegram = JsonObject()
                    telegram.put("directory", directory)
                    let audit = JsonObject()
                    audit.put("telegram", telegram)
                    out.put("audit", audit)
                    return out
                }
                @Expect(method, "channels.send")
                @Expect(params.get("peerId").getOrThrow().asString().getValue(), "group:-10042")
                out.put("ok", JsonBool(true))
                out
            }))
            try {
                let out = toolset.debugTelegramSendToTargetForTest("Ops Room", "hello", Some("dry-run"), Some(true))
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "accepted")
                @Expect(json.get("resolvedTarget").getOrThrow().asString().getValue(), "group:-10042")
                @Expect(json.get("writeback").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "dry_run")
                @Expect(CliSettingManager.readGatewaySettings().telegram.defaultTo, "user:old")
            } finally {
                toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            }
        }
    }

    @TestCase
    public func telegramTargetWritebackApplyUpdatesMatchingAccountDefaultTarget(): Unit {
        this.withTelegramMediaToolsetConfigHome {
            var user = GatewayUserSettings()
            user.telegram.defaultTo = "@demo"
            let accounts = JsonObject()
            let work = JsonObject()
            work.put("defaultTo", JsonString("@demo"))
            accounts.put("work", work)
            user.telegram.accounts = Some(accounts)
            MetisConfigManager.setGatewaySettings(user)
            let toolset = GatewayTelegramMediaToolset()
            toolset.debugSetGatewayCallRunnerForTest(Some({ _method: String, _params: JsonObject =>
                let out = JsonObject()
                out.put("ok", JsonBool(true))
                out.put("chatId", JsonString("12345"))
                out
            }))
            try {
                let out = gatewayWithToolRuntimeContext(
                    GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", operatorScopes: ["operator.admin"]),
                    { => toolset.debugTelegramTargetWritebackApplyForTest("@demo", None<String>) }
                )
                let json = JsonValue.fromStr(out).asObject()
                @Expect(json.get("status").getOrThrow().asString().getValue(), "applied")
                @Expect(json.get("defaultTo").getOrThrow().asString().getValue(), "user:12345")
                let updated = CliSettingManager.readGatewaySettings()
                @Expect(updated.telegram.defaultTo, "user:12345")
                let accountDefault = updated.telegram.accounts.getOrThrow().get("work").getOrThrow().asObject().get("defaultTo").getOrThrow().asString().getValue()
                @Expect(accountDefault, "user:12345")
            } finally {
                toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            }
        }
    }

    @TestCase
    public func telegramActionBuildsUnifiedGatewaySendPayloads(): Unit {
        let toolset = GatewayTelegramMediaToolset()
        let sent = ArrayList<JsonObject>()
        toolset.debugSetGatewayCallRunnerForTest(Some({ method: String, params: JsonObject =>
            @Expect(method, "channels.send")
            sent.add(params)
            let out = JsonObject()
            out.put("ok", JsonBool(true))
            out.put("messageId", JsonString("900"))
            out
        }))
        try {
            let ctx = GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:direct:user:8734062810")
            let sendOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("sendMessage", None<String>, Some("hello"), None<String>, None<String>, None<Array<String>>, None<String>, None<String>)
            })
            @Expect(JsonValue.fromStr(sendOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")
            let reactOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("react", None<String>, None<String>, Some("101"), Some("👍"), None<Array<String>>, None<String>, None<String>)
            })
            @Expect(JsonValue.fromStr(reactOut).asObject().get("telegramAction").getOrThrow().asString().getValue(), "react")
            let pollOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("poll", None<String>, Some("Pick one"), None<String>, None<String>, Some(["A", "B"]), None<String>, None<String>)
            })
            @Expect(JsonValue.fromStr(pollOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")
            let deleteOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("delete", None<String>, None<String>, Some("102"), None<String>, None<Array<String>>, None<String>, None<String>)
            })
            @Expect(JsonValue.fromStr(deleteOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")
            let editOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("edit", None<String>, Some("updated"), Some("103"), None<String>, None<Array<String>>, None<String>, None<String>)
            })
            @Expect(JsonValue.fromStr(editOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")
            let stickerOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("sendSticker", None<String>, None<String>, None<String>, None<String>, None<Array<String>>, Some("sticker-file-id"), None<String>)
            })
            @Expect(JsonValue.fromStr(stickerOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")
            let topicCreateOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("topic-create", Some("group:-100123"), None<String>, None<String>, None<String>, None<Array<String>>, None<String>, Some("Sprint"))
            })
            @Expect(JsonValue.fromStr(topicCreateOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")
            let topicEditOut = gatewayWithToolRuntimeContext(ctx, { =>
                toolset.debugTelegramActionForTest("topic-edit", Some("group:-100123"), None<String>, Some("42"), None<String>, None<Array<String>>, None<String>, Some("Renamed"))
            })
            @Expect(JsonValue.fromStr(topicEditOut).asObject().get("status").getOrThrow().asString().getValue(), "accepted")

            @Expect(sent.size, 8)
            @Expect(sent[0].get("text").getOrThrow().asString().getValue(), "hello")
            @Expect(sent[1].get("text").getOrThrow().asString().getValue().contains("[reaction]"), true)
            @Expect(sent[1].get("replyToMessageId").getOrThrow().asString().getValue(), "101")
            @Expect(sent[2].get("text").getOrThrow().asString().getValue().contains("[poll]"), true)
            @Expect(sent[3].get("text").getOrThrow().asString().getValue(), "[delete]")
            @Expect(sent[4].get("text").getOrThrow().asString().getValue().contains("[edit]"), true)
            @Expect(sent[5].get("text").getOrThrow().asString().getValue().contains("[sticker]"), true)
            @Expect(sent[6].get("text").getOrThrow().asString().getValue().contains("[topic-create]"), true)
            @Expect(sent[7].get("text").getOrThrow().asString().getValue().contains("[topic-edit]"), true)
        } finally {
            toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
        }
    }

    @TestCase
    public func telegramActionDisabledReturnsStructuredError(): Unit {
        let toolset = GatewayTelegramMediaToolset()
        toolset.debugSetGatewayCallRunnerForTest(Some({ _method: String, _params: JsonObject =>
            let out = JsonObject()
            out.put("ok", JsonBool(false))
            out.put("reason", JsonString("telegram reaction action is disabled"))
            out
        }))
        try {
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:direct:user:8734062810"),
                { => toolset.debugTelegramActionForTest("react", None<String>, None<String>, Some("101"), Some("👍"), None<Array<String>>, None<String>, None<String>) }
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(json.get("status").getOrThrow().asString().getValue(), "error")
            @Expect(json.get("errorCode").getOrThrow().asString().getValue(), "action_disabled")
            @Expect(json.get("reason").getOrThrow().asString().getValue().contains("disabled"), true)
        } finally {
            toolset.debugSetGatewayCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
        }
    }
}
