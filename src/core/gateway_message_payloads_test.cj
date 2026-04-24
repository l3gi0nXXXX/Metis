package metis.core

import std.unittest.*

private func gatewayMessagePayloadLongString(char: Rune, count: Int64): String {
    let sb = StringBuilder()
    for (_ in 0..count) {
        sb.append(char)
    }
    sb.toString()
}

@Test
public class GatewayMessagePayloadsTest {
    @TestCase
    func renderGatewayPollTextFormatsTitleAndOptions(): Unit {
        let rendered = renderGatewayPollText("Lunch?|Rice|Noodles|Salad")
        @Expect(rendered.contains("[poll]"), true)
        @Expect(rendered.contains("Lunch?"), true)
        @Expect(rendered.contains("1. Rice"), true)
        @Expect(rendered.contains("3. Salad"), true)
    }

    @TestCase
    func parseGatewayPollPartsSplitsTitleAndOptions(): Unit {
        let parsed = parseGatewayPollParts("Lunch?|Rice|Noodles")
        @Expect(parsed[0], "Lunch?")
        @Expect(parsed[1].size, 2)
        @Expect(parsed[1][0], "Rice")
        @Expect(parsed[1][1], "Noodles")
    }

    @TestCase
    func renderGatewayReactionTextWrapsStructuredPayload(): Unit {
        let rendered = renderGatewayReactionText("+1")
        @Expect(rendered.contains("[reaction]"), true)
        @Expect(rendered.contains("token=+1"), true)
        @Expect(rendered.contains("render=+1"), true)
        @Expect(parseGatewayReactionToken(rendered), "+1")
    }

    @TestCase
    func renderGatewayStickerTextWrapsStructuredPayload(): Unit {
        let rendered = renderGatewayStickerText("sticker-file-id")
        @Expect(rendered.contains("[sticker]"), true)
        @Expect(rendered.contains("fileId=sticker-file-id"), true)
        @Expect(parseGatewayStickerFileId(rendered), "sticker-file-id")
    }

    @TestCase
    func renderAndParseGatewayPhotoPartsRoundTrip(): Unit {
        let rendered = renderGatewayPhotoText("photo-file-id", caption: "hello")
        @Expect(rendered.contains("[photo]"), true)
        let parsed = parseGatewayPhotoParts(rendered)
        @Expect(parsed[0], "photo-file-id")
        @Expect(parsed[1], "hello")
    }

    @TestCase
    func renderAndParseGatewayDocumentPartsRoundTrip(): Unit {
        let rendered = renderGatewayDocumentText("doc-file-id", caption: "report")
        @Expect(rendered.contains("[document]"), true)
        let parsed = parseGatewayDocumentParts(rendered)
        @Expect(parsed[0], "doc-file-id")
        @Expect(parsed[1], "report")
    }

    @TestCase
    func renderAndParseGatewayAudioPartsRoundTrip(): Unit {
        let rendered = renderGatewayAudioText("audio-file-id", caption: "podcast")
        @Expect(rendered.contains("[audio]"), true)
        let parsed = parseGatewayAudioParts(rendered)
        @Expect(parsed[0], "audio-file-id")
        @Expect(parsed[1], "podcast")
    }

    @TestCase
    func renderAndParseGatewayVoicePartsRoundTrip(): Unit {
        let rendered = renderGatewayVoiceText("voice-file-id", caption: "memo")
        @Expect(rendered.contains("[voice]"), true)
        let parsed = parseGatewayVoiceParts(rendered)
        @Expect(parsed[0], "voice-file-id")
        @Expect(parsed[1], "memo")
    }

    @TestCase
    func renderAndParseGatewayVideoPartsRoundTrip(): Unit {
        let rendered = renderGatewayVideoText("video-file-id", caption: "clip")
        @Expect(rendered.contains("[video]"), true)
        let parsed = parseGatewayVideoParts(rendered)
        @Expect(parsed[0], "video-file-id")
        @Expect(parsed[1], "clip")
    }

    @TestCase
    func renderAndParseGatewayVideoNotePartsRoundTrip(): Unit {
        let rendered = renderGatewayVideoNoteText("video-note-file-id")
        @Expect(rendered.contains("[video-note]"), true)
        @Expect(parseGatewayVideoNoteFileId(rendered), "video-note-file-id")
    }

    @TestCase
    func renderAndParseGatewayEditTextRoundTrip(): Unit {
        let rendered = renderGatewayEditText("Updated text")
        @Expect(rendered.contains("[edit]"), true)
        @Expect(parseGatewayEditText(rendered), "Updated text")
    }

    @TestCase
    func renderAndParseGatewayTopicCreateTextRoundTrip(): Unit {
        let rendered = renderGatewayTopicCreateText("Sprint")
        @Expect(rendered.contains("[topic-create]"), true)
        @Expect(parseGatewayTopicCreateText(rendered), "Sprint")
    }

    @TestCase
    func renderAndParseGatewayTopicEditTextRoundTrip(): Unit {
        let rendered = renderGatewayTopicEditText("Renamed Sprint")
        @Expect(rendered.contains("[topic-edit]"), true)
        @Expect(parseGatewayTopicEditText(rendered), "Renamed Sprint")
    }

    @TestCase
    func gatewayMessagePayloadPreviewTruncatesLongPayload(): Unit {
        let longText = gatewayMessagePayloadLongString(r'x', 200)
        let preview = gatewayMessagePayloadPreview(longText)
        @Expect(preview.size <= 163, true)
        @Expect(preview.endsWith("..."), true)
    }
}
