package metis.gateway.core

import metis.core.{GatewayToolRuntimeContext, gatewayCurrentToolRuntimeContext, gatewayNotifyCurrentToolRuntimeStatus}
import metis.core.{gatewayMediaUnderstandingFirstText, gatewayMediaUnderstandingForRecord, setGatewayMediaAsrRunnerForTest, setGatewayMediaDocumentExtractorForTest, setGatewayMediaVideoRunnerForTest, setGatewayMediaVisionRunnerForTest}
import metis.core.config.GatewayUserSettings
import metis.gateway.session.{GatewayDeliveryTarget, GatewayIngressSource, GatewaySessionContext, GatewaySessionRequest}

import std.collection.ArrayList
import std.fs.{Directory, File, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

@Test
public class GatewaySessionTurnRunnerTest {
    @TestCase
    public func telegramLifecycleHookReportsThinkingToolDone(): Unit {
        let statuses = ArrayList<String>()
        setGatewayAgentBridgeReplyRunnerForTest(Some({
            _conversationKey: String,
            _prompt: String,
            _channelName: String,
            _agentId: String,
            _streamingEnabled: Bool,
            _streamChunkHook: Option<(String) -> Unit> =>
                gatewayNotifyCurrentToolRuntimeStatus("tool")
                "tool answer"
        }))
        try {
            let store = GatewaySessionStore(Path("."), enabled: false, agentId: "general")
            let bridge = AgentBridge(sessionStore: store)
            let context = GatewaySessionContext(
                GatewayIngressSource.Channel("telegram"),
                "telegram",
                "telegram",
                "telegram:chat:1",
                "general",
                deliveryTarget: Some(GatewayDeliveryTarget("telegram", "user:1", accountId: "default", replyToMessageId: "7"))
            )
            let result = gatewayExecuteSessionTurn(
                bridge,
                context,
                "run fake tool",
                deliver: true,
                toolRuntimeContext: Some(GatewayToolRuntimeContext(
                    "telegram",
                    channelName: "telegram",
                    sessionKey: "telegram:chat:1",
                    lifecycleHook: Some({ status: String => statuses.add(status) })
                )),
                deliverHook: Some({
                    _channelName: String,
                    _accountId: String,
                    _peerId: String,
                    _text: String,
                    _replyToMessageId: Option<String>,
                    _replyInThread: Bool => "501"
                }),
                lifecycleHook: Some({ status: String => statuses.add(status) })
            )
            @Expect(result.delivered, true)
            @Expect(statuses.size, 3)
            @Expect(statuses[0], "thinking")
            @Expect(statuses[1], "tool")
            @Expect(statuses[2], "done")
        } finally {
            setGatewayAgentBridgeReplyRunnerForTest(None<(String, String, String, String, Bool, Option<(String) -> Unit>) -> String>)
        }
    }

    @TestCase
    public func telegramLifecycleHookReportsErrorWhenSessionFails(): Unit {
        let statuses = ArrayList<String>()
        setGatewayAgentBridgeReplyRunnerForTest(Some({
            _conversationKey: String,
            _prompt: String,
            _channelName: String,
            _agentId: String,
            _streamingEnabled: Bool,
            _streamChunkHook: Option<(String) -> Unit> =>
                throw Exception("fake failure")
        }))
        try {
            let store = GatewaySessionStore(Path("."), enabled: false, agentId: "general")
            let bridge = AgentBridge(sessionStore: store)
            let context = GatewaySessionContext(
                GatewayIngressSource.Channel("telegram"),
                "telegram",
                "telegram",
                "telegram:chat:1",
                "general"
            )
            var failed = false
            try {
                let _ = gatewayExecuteSessionTurn(
                    bridge,
                    context,
                    "fail",
                    lifecycleHook: Some({ status: String => statuses.add(status) })
                )
            } catch (_e: Exception) {
                failed = true
            }
            @Expect(failed, true)
            @Expect(statuses.size, 2)
            @Expect(statuses[0], "thinking")
            @Expect(statuses[1], "error")
        } finally {
            setGatewayAgentBridgeReplyRunnerForTest(None<(String, String, String, String, Bool, Option<(String) -> Unit>) -> String>)
        }
    }

    @TestCase
    public func telegramStreamingSplitsAnswerAndReasoningLanes(): Unit {
        let raw = "<think>check facts</think><final>visible answer</final>"
        let hidden = gatewayDebugTelegramStreamingLanesForTest(raw)
        @Expect(hidden.get("answer").getOrThrow().asString().getValue(), "visible answer")
        @Expect(hidden.get("reasoning").getOrThrow().asString().getValue(), "")

        let visible = gatewayDebugTelegramStreamingLanesForTest(raw, reasoningEnabled: true)
        @Expect(visible.get("answer").getOrThrow().asString().getValue(), "visible answer")
        @Expect(visible.get("reasoning").getOrThrow().asString().getValue(), "check facts")
    }

    @TestCase
    public func telegramReasoningLaneDoesNotReplaceFinalAnswer(): Unit {
        let root = Path("/tmp/metis-telegram-reasoning-lane-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        File.writeTo(root.join("sessions.json"), "{\"telegram:chat:1\":{\"reasoningVisibility\":\"on\"}}".toArray())
        let sentTexts = ArrayList<String>()
        setGatewayAgentBridgeReplyRunnerForTest(Some({
            _conversationKey: String,
            _prompt: String,
            _channelName: String,
            _agentId: String,
            _streamingEnabled: Bool,
            streamChunkHook: Option<(String) -> Unit> =>
                match (streamChunkHook) {
                    case Some(notify) => notify("<think>check facts</think>")
                    case None => ()
                }
                "<think>check facts</think><final>visible answer</final>"
        }))
        try {
            let store = GatewaySessionStore(root, enabled: true, agentId: "general")
            let bridge = AgentBridge(sessionStore: store)
            let context = GatewaySessionContext(
                GatewayIngressSource.Channel("telegram"),
                "telegram",
                "telegram",
                "telegram:chat:1",
                "general",
                deliveryTarget: Some(GatewayDeliveryTarget("telegram", "user:1", accountId: "default", replyToMessageId: "7"))
            )
            let result = gatewayExecuteSessionTurn(
                bridge,
                context,
                "stream",
                deliver: true,
                streamingEnabled: true,
                deliverHook: Some({
                    _channelName: String,
                    _accountId: String,
                    _peerId: String,
                    text: String,
                    _replyToMessageId: Option<String>,
                    _replyInThread: Bool =>
                        sentTexts.add(text)
                        "m-${sentTexts.size}"
                })
            )
            @Expect(result.delivered, true)
            @Expect(result.deliveryMessageId, "m-2")
            @Expect(sentTexts.size, 2)
            @Expect(sentTexts[0].contains("Reasoning"), true)
            @Expect(sentTexts[0].contains("check facts"), true)
            @Expect(sentTexts[1], "visible answer")
        } finally {
            setGatewayAgentBridgeReplyRunnerForTest(None<(String, String, String, String, Bool, Option<(String) -> Unit>) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func executeSessionRequestTurnResolvesContextBeforeReply(): Unit {
        let store = GatewaySessionStore(Path("."), enabled: false, agentId: "general")
        let bridge = AgentBridge(sessionStore: store)
        let turn = gatewayExecuteSessionRequestTurn(
            bridge,
            GatewaySessionRequest(
                GatewayIngressSource.Cli,
                channelName: "cli",
                sessionHint: "main",
                agentId: "general"
            ),
            "/unknown"
        )
        @Expect(turn.context.channelName, "cli")
        @Expect(turn.context.sessionKey, "agent:general:main")
        @Expect(turn.context.agentId, "general")
        @Expect(turn.execution.delivered, false)
        @Expect(turn.execution.answer.contains("这不是一个有效的命令"), true)
    }

    @TestCase
    public func executeSessionRequestTurnForUserBuildsBridgeFromResolvedRequest(): Unit {
        let turn = gatewayExecuteSessionRequestTurnForUser(
            GatewayUserSettings(),
            GatewaySessionRequest(
                GatewayIngressSource.Cli,
                channelName: "cli",
                sessionHint: "agent:general:main",
                agentId: ""
            ),
            "/unknown"
        )
        @Expect(turn.context.channelName, "cli")
        @Expect(turn.context.sessionKey, "agent:general:main")
        @Expect(turn.context.agentId, "general")
        @Expect(turn.execution.answer.contains("这不是一个有效的命令"), true)
    }

    @TestCase
    public func executeSessionRequestTurnClearsToolRuntimeContextAfterReply(): Unit {
        let store = GatewaySessionStore(Path("."), enabled: false, agentId: "general")
        let bridge = AgentBridge(sessionStore: store)
        let turn = gatewayExecuteSessionRequestTurn(
            bridge,
            GatewaySessionRequest(
                GatewayIngressSource.ControlUi,
                channelName: "control-ui",
                sessionHint: "main",
                agentId: "general",
                senderId: "operator-1",
                text: "/unknown"
            ),
            "/unknown"
        )
        @Expect(turn.context.channelName, "control-ui")
        @Expect(gatewayCurrentToolRuntimeContext().isNone(), true)
    }

    @TestCase
    public func mediaContextPromptExposesMediaPathsAndTypes(): Unit {
        let media = JsonObject()
        let records = JsonArray([])
        let record = JsonObject()
        record.put("mediaId", JsonString("tg-default-user-101-photo"))
        record.put("mediaKind", JsonString("photo"))
        record.put("mimeType", JsonString("image/jpeg"))
        record.put("originalFileName", JsonString("file_1.jpg"))
        record.put("localPath", JsonString("/tmp/metis-media/file_1.jpg"))
        record.put("downloaded", JsonBool(true))
        records.add(record)
        media.put("records", records)

        let prompt = gatewayBuildMediaContextPrompt(media)
        @Expect(prompt.contains("MediaPath=/tmp/metis-media/file_1.jpg"), true)
        @Expect(prompt.contains("MediaType=photo"), true)
        @Expect(prompt.contains("MediaPaths=/tmp/metis-media/file_1.jpg"), true)
        @Expect(prompt.contains("MediaTypes=photo"), true)
        @Expect(prompt.contains("visionInputReady=true"), true)
        @Expect(prompt.contains("visionAction=use telegram_image_analyze"), true)
        @Expect(prompt.contains("call telegram_image_analyze before answering"), true)
        @Expect(prompt.contains("Do not claim that the image cannot be seen"), true)
    }

    @TestCase
    public func mediaContextPromptIncludesAudioTranscriptSidecar(): Unit {
        let root = Path("/tmp/metis-media-audio-context-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let voice = root.join("voice.ogg")
        File.writeTo(voice, "fake-audio".toArray())
        File.writeTo(Path("${voice.toString()}.transcript.txt"), "hello from voice".toArray())
        try {
            let media = JsonObject()
            let records = JsonArray([])
            let record = JsonObject()
            record.put("mediaKind", JsonString("voice"))
            record.put("mimeType", JsonString("audio/ogg"))
            record.put("localPath", JsonString(voice.toString()))
            record.put("downloaded", JsonBool(true))
            records.add(record)
            media.put("records", records)
            let prompt = gatewayBuildMediaContextPrompt(media)
            @Expect(prompt.contains("AudioTranscript=hello from voice"), true)
            @Expect(prompt.contains("use AudioTranscript when present"), true)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaContextPromptIncludesNativeAsrTranscript(): Unit {
        let root = Path("/tmp/metis-media-audio-native-asr-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let voice = root.join("voice.ogg")
        File.writeTo(voice, "fake-audio".toArray())
        setGatewayMediaAsrRunnerForTest(Some({ _path: String, _mime: String => "native voice transcript" }))
        try {
            let media = JsonObject()
            let records = JsonArray([])
            let record = JsonObject()
            record.put("mediaKind", JsonString("voice"))
            record.put("mimeType", JsonString("audio/ogg"))
            record.put("localPath", JsonString(voice.toString()))
            record.put("downloaded", JsonBool(true))
            records.add(record)
            media.put("records", records)
            let prompt = gatewayBuildMediaContextPrompt(media)
            @Expect(prompt.contains("AudioTranscript=native voice transcript"), true)
            @Expect(prompt.contains("MediaUnderstandingCapability=audio"), true)
            @Expect(prompt.contains("MediaUnderstandingStatus=ok"), true)
        } finally {
            setGatewayMediaAsrRunnerForTest(None<(String, String) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaContextPromptIncludesReadableDocumentPreview(): Unit {
        let root = Path("/tmp/metis-media-doc-context-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let doc = root.join("report.txt")
        File.writeTo(doc, "line one\nline two".toArray())
        try {
            let media = JsonObject()
            let records = JsonArray([])
            let record = JsonObject()
            record.put("mediaKind", JsonString("document"))
            record.put("mimeType", JsonString("text/plain"))
            record.put("originalFileName", JsonString("report.txt"))
            record.put("localPath", JsonString(doc.toString()))
            record.put("downloaded", JsonBool(true))
            records.add(record)
            media.put("records", records)
            let prompt = gatewayBuildMediaContextPrompt(media)
            @Expect(prompt.contains("FileContentPreview=line one\nline two"), true)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaUnderstandingRuntimeReadsImageAnalysisCompanion(): Unit {
        let root = Path("/tmp/metis-media-understanding-image-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let image = root.join("image.jpg")
        File.writeTo(image, "fake-image".toArray())
        File.writeTo(Path(image.toString() + ".analysis.txt"), "a blue square".toArray())
        try {
            let record = JsonObject()
            record.put("mediaId", JsonString("tg-image-1"))
            record.put("mediaKind", JsonString("photo"))
            record.put("mimeType", JsonString("image/jpeg"))
            record.put("localPath", JsonString(image.toString()))
            record.put("downloaded", JsonBool(true))

            let result = gatewayMediaUnderstandingForRecord(record)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(result.get("capability").getOrThrow().asString().getValue(), "image")
            @Expect(gatewayMediaUnderstandingFirstText(result), "a blue square")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func t44MediaUnderstandingRuntimeUsesNativeVisionProvider(): Unit {
        let root = Path("/tmp/metis-media-understanding-native-vision-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let image = root.join("image.jpg")
        File.writeTo(image, "fake-image".toArray())
        setGatewayMediaVisionRunnerForTest(Some({ _path: String, _mime: String, kind: String, prompt: String, _maxBytes: Int64 =>
            "${kind}: native vision: ${prompt.trimAscii()}"
        }))
        try {
            let record = JsonObject()
            record.put("mediaId", JsonString("tg-image-native"))
            record.put("mediaKind", JsonString("photo"))
            record.put("mimeType", JsonString("image/jpeg"))
            record.put("localPath", JsonString(image.toString()))
            record.put("downloaded", JsonBool(true))

            let result = gatewayMediaUnderstandingForRecord(record, prompt: "describe")
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(gatewayMediaUnderstandingFirstText(result), "photo: native vision: describe")
            let outputs = result.get("outputs").getOrThrow().asArray()
            @Expect(outputs[0].asObject().get("source").getOrThrow().asString().getValue(), "native_vision_runtime")
        } finally {
            setGatewayMediaVisionRunnerForTest(None<(String, String, String, String, Int64) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaContextPromptIncludesUnifiedImageDescription(): Unit {
        let root = Path("/tmp/metis-media-context-image-understanding-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let image = root.join("image.jpg")
        File.writeTo(image, "fake-image".toArray())
        File.writeTo(Path(image.toString() + ".analysis.txt"), "a green square".toArray())
        try {
            let media = JsonObject()
            let records = JsonArray([])
            let record = JsonObject()
            record.put("mediaKind", JsonString("photo"))
            record.put("mimeType", JsonString("image/jpeg"))
            record.put("localPath", JsonString(image.toString()))
            record.put("downloaded", JsonBool(true))
            records.add(record)
            media.put("records", records)

            let prompt = gatewayBuildMediaContextPrompt(media)
            @Expect(prompt.contains("MediaUnderstandingStatus=ok"), true)
            @Expect(prompt.contains("MediaUnderstandingCapability=image"), true)
            @Expect(prompt.contains("ImageDescription=a green square"), true)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaUnderstandingRuntimeReportsVideoNotConfigured(): Unit {
        let root = Path("/tmp/metis-media-understanding-video-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let video = root.join("clip.mp4")
        File.writeTo(video, "fake-video".toArray())
        try {
            let record = JsonObject()
            record.put("mediaKind", JsonString("video"))
            record.put("mimeType", JsonString("video/mp4"))
            record.put("localPath", JsonString(video.toString()))
            record.put("downloaded", JsonBool(true))

            let result = gatewayMediaUnderstandingForRecord(record)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "not_configured")
            @Expect(result.get("capability").getOrThrow().asString().getValue(), "video")
            @Expect(result.get("videoUnderstandingStatus").getOrThrow().asString().getValue(), "not_configured")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func t44MediaUnderstandingRuntimeUsesNativeVideoProvider(): Unit {
        let root = Path("/tmp/metis-media-understanding-native-video-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let video = root.join("clip.mp4")
        File.writeTo(video, "fake-video".toArray())
        setGatewayMediaVideoRunnerForTest(Some({ _path: String, mime: String, prompt: String, _maxBytes: Int64 =>
            "native video ${mime}: ${prompt.trimAscii()}"
        }))
        try {
            let record = JsonObject()
            record.put("mediaKind", JsonString("video"))
            record.put("mimeType", JsonString("video/mp4"))
            record.put("localPath", JsonString(video.toString()))
            record.put("downloaded", JsonBool(true))

            let result = gatewayMediaUnderstandingForRecord(record, capability: "video", prompt: "summarize")
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(gatewayMediaUnderstandingFirstText(result), "native video video/mp4: summarize")
            let outputs = result.get("outputs").getOrThrow().asArray()
            @Expect(outputs[0].asObject().get("source").getOrThrow().asString().getValue(), "native_video_runtime")
        } finally {
            setGatewayMediaVideoRunnerForTest(None<(String, String, String, Int64) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaContextPromptIncludesVideoDescriptionCompanion(): Unit {
        let root = Path("/tmp/metis-media-context-video-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let video = root.join("clip.mp4")
        File.writeTo(video, "fake-video".toArray())
        File.writeTo(Path(video.toString() + ".video.txt"), "demo video description".toArray())
        try {
            let media = JsonObject()
            let records = JsonArray([])
            let record = JsonObject()
            record.put("mediaKind", JsonString("video"))
            record.put("mimeType", JsonString("video/mp4"))
            record.put("localPath", JsonString(video.toString()))
            record.put("downloaded", JsonBool(true))
            records.add(record)
            media.put("records", records)
            let prompt = gatewayBuildMediaContextPrompt(media)
            @Expect(prompt.contains("VideoDescription=demo video description"), true)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaUnderstandingRuntimeExtractsDocumentCompanion(): Unit {
        let root = Path("/tmp/metis-media-document-extract-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let doc = root.join("report.pdf")
        File.writeTo(doc, "fake-pdf".toArray())
        File.writeTo(Path(doc.toString() + ".extract.txt"), "extracted pdf content".toArray())
        try {
            let record = JsonObject()
            record.put("mediaKind", JsonString("document"))
            record.put("mimeType", JsonString("application/pdf"))
            record.put("originalFileName", JsonString("report.pdf"))
            record.put("localPath", JsonString(doc.toString()))
            record.put("downloaded", JsonBool(true))
            let result = gatewayMediaUnderstandingForRecord(record)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(result.get("documentExtractStatus").getOrThrow().asString().getValue(), "ok")
            @Expect(gatewayMediaUnderstandingFirstText(result), "extracted pdf content")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaUnderstandingRuntimeUsesNativeDocumentExtractor(): Unit {
        let root = Path("/tmp/metis-media-document-native-extract-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let doc = root.join("report.pdf")
        File.writeTo(doc, "fake-pdf".toArray())
        setGatewayMediaDocumentExtractorForTest(Some({ _path: String, _mime: String, _fileName: String, _maxBytes: Int64 => "native pdf text" }))
        try {
            let record = JsonObject()
            record.put("mediaKind", JsonString("document"))
            record.put("mimeType", JsonString("application/pdf"))
            record.put("originalFileName", JsonString("report.pdf"))
            record.put("localPath", JsonString(doc.toString()))
            record.put("downloaded", JsonBool(true))
            let result = gatewayMediaUnderstandingForRecord(record)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(result.get("documentExtractStatus").getOrThrow().asString().getValue(), "ok")
            @Expect(result.get("extractor").getOrThrow().asString().getValue(), "native")
            @Expect(gatewayMediaUnderstandingFirstText(result), "native pdf text")
        } finally {
            setGatewayMediaDocumentExtractorForTest(None<(String, String, String, Int64) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaContextPromptIncludesStructuredTelegramContextWithoutMediaRecords(): Unit {
        let media = JsonObject()
        let context = JsonObject()
        let location = JsonObject()
        location.put("latitude", JsonString("31.23"))
        location.put("longitude", JsonString("121.47"))
        context.put("location", location)
        let contact = JsonObject()
        contact.put("firstName", JsonString("Ada"))
        contact.put("phoneNumber", JsonString("123"))
        context.put("contact", contact)
        media.put("context", context)

        let prompt = gatewayBuildMediaContextPrompt(media)
        @Expect(prompt.contains("StructuredTelegramContext:"), true)
        @Expect(prompt.contains("Location="), true)
        @Expect(prompt.contains("31.23"), true)
        @Expect(prompt.contains("Contact="), true)
        @Expect(prompt.contains("Ada"), true)
    }

    @TestCase
    public func mediaContextPromptIncludesTelegramRouteContextWithoutMediaRecords(): Unit {
        let media = JsonObject()
        let context = JsonObject()
        let route = JsonObject()
        route.put("agentId", JsonString("topic-agent"))
        route.put("systemPrompt", JsonString("topic prompt"))
        route.put("skills", JsonArray([JsonString("review")]))
        route.put("disableAudioPreflight", JsonBool(true))
        context.put("telegramRoute", route)
        media.put("context", context)

        let prompt = gatewayBuildMediaContextPrompt(media)
        @Expect(prompt.contains("StructuredTelegramContext:"), true)
        @Expect(prompt.contains("TelegramRoute="), true)
        @Expect(prompt.contains("topic-agent"), true)
        @Expect(prompt.contains("topic prompt"), true)
    }

    @TestCase
    public func streamingDefaultsToOnButCanBeDisabledPerImChannel(): Unit {
        var defaults = GatewayUserSettings()
        defaults.telegram.enabled = true
        defaults.feishu.enabled = true
        defaults.qq.enabled = true
        @Expect(gatewayStreamingEnabledForUserChannel(defaults, "telegram"), true)
        @Expect(gatewayStreamingEnabledForUserChannel(defaults, "feishu"), true)
        @Expect(gatewayStreamingEnabledForUserChannel(defaults, "qq"), true)

        var disabled = GatewayUserSettings()
        disabled.telegram.enabled = true
        disabled.telegram.streaming = "off"
        @Expect(gatewayStreamingEnabledForUserChannel(disabled, "telegram"), false)

        var feishuDisabled = GatewayUserSettings()
        feishuDisabled.feishu.enabled = true
        feishuDisabled.feishu.streaming = "off"
        @Expect(gatewayStreamingEnabledForUserChannel(feishuDisabled, "feishu"), false)

        var qqDisabled = GatewayUserSettings()
        qqDisabled.qq.enabled = true
        qqDisabled.qq.streaming = "off"
        @Expect(gatewayStreamingEnabledForUserChannel(qqDisabled, "qq"), false)

        var blocked = GatewayUserSettings()
        blocked.telegram.enabled = true
        blocked.telegram.blockStreaming = true
        @Expect(gatewayStreamingEnabledForUserChannel(blocked, "telegram"), false)

        var feishuBlocked = GatewayUserSettings()
        feishuBlocked.feishu.enabled = true
        feishuBlocked.feishu.blockStreaming = true
        @Expect(gatewayStreamingEnabledForUserChannel(feishuBlocked, "feishu"), false)

        var qqBlocked = GatewayUserSettings()
        qqBlocked.qq.enabled = true
        qqBlocked.qq.blockStreaming = true
        @Expect(gatewayStreamingEnabledForUserChannel(qqBlocked, "qq"), false)
    }
}
