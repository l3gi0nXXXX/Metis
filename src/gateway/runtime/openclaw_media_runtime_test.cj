package metis.gateway.runtime

import metis.gateway.openclaw_media.*
import metis.core.{setGatewayMediaAsrRunnerForTest, setGatewayMediaDocumentExtractorForTest, setGatewayMediaVisionRunnerForTest}

import std.fs.{Directory, File, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*

@Test
public class OpenClawMediaRuntimeTest {
    private func tempRoot(label: String): Path {
        let root = Path("/tmp/metis-openclaw-media-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        Directory.create(root, recursive: true)
        root
    }

    @TestCase
    public func mediaMockStoresResolvesAndProjectsOutboundRefs(): Unit {
        let runtime = OpenClawMediaRuntime()
        let stored = runtime.store("image/png", "diagram.png", "bytes:fake")
        let resolved = runtime.resolve(stored.ref)
        let outbound = runtime.outbound(stored.ref)

        @Expect(stored.ref, "media-1")
        @Expect(resolved.isSome(), true)
        @Expect(resolved.getOrThrow().mimeType, "image/png")
        @Expect(outbound.ref, "media-1")
        @Expect(outbound.kind, "outbound-media")
    }

    @TestCase
    public func mediaRuntimeUsesMetisUnderstandingContractForAsrVisionAndDocuments(): Unit {
        let root = this.tempRoot("understanding")
        let image = root.join("image.jpg")
        let audio = root.join("voice.ogg")
        let document = root.join("report.txt")
        File.writeTo(image, "jpg".toArray())
        File.writeTo(audio, "ogg".toArray())
        File.writeTo(document, "metis document context".toArray())

        setGatewayMediaVisionRunnerForTest(Some({ path, mime, kind, prompt, maxBytes =>
            "${kind}:${mime}:${prompt}:${maxBytes}:${path.endsWith("image.jpg")}"
        }))
        setGatewayMediaAsrRunnerForTest(Some({ path, mime =>
            "transcript:${mime}:${path.endsWith("voice.ogg")}"
        }))
        setGatewayMediaDocumentExtractorForTest(Some({ path, mime, name, maxBytes =>
            "document:${mime}:${name}:${maxBytes}:${path.endsWith("report.txt")}"
        }))
        try {
            let runtime = OpenClawMediaRuntime()
            let imageRef = runtime.storeMetisRef("image/jpeg", "image.jpg", image.toString(), mediaKind: "photo")
            let audioRef = runtime.storeMetisRef("audio/ogg", "voice.ogg", audio.toString(), mediaKind: "voice")
            let documentRef = runtime.storeMetisRef("text/plain", "report.txt", document.toString(), mediaKind: "document")

            let vision = runtime.understand(imageRef.ref, capability: "image", prompt: "describe")
            let asr = runtime.understand(audioRef.ref, capability: "audio")
            let doc = runtime.understand(documentRef.ref, capability: "document", maxBytes: 64)
            let outbound = runtime.outbound(documentRef.ref, channel: "telegram", caption: "send")

            @Expect(vision.contract, "metis.media-understanding.v1")
            @Expect(vision.status, "ok")
            @Expect(vision.text.contains("photo:image/jpeg:describe"), true)
            @Expect(asr.text.contains("transcript:audio/ogg:true"), true)
            @Expect(doc.text.contains("metis document context") || doc.text.contains("document:text/plain:report.txt"), true)
            @Expect(outbound.contract, "metis.outbound-media-ref.v1")
            @Expect(outbound.channel, "telegram")
            @Expect(outbound.caption, "send")
        } finally {
            setGatewayMediaVisionRunnerForTest(None<(String, String, String, String, Int64) -> String>)
            setGatewayMediaAsrRunnerForTest(None<(String, String) -> String>)
            setGatewayMediaDocumentExtractorForTest(None<(String, String, String, Int64) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }
}
