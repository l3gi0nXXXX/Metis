package metis.gateway.openclaw_media

import std.unittest.testmacro.*

@Test
public class OpenClawMediaRuntimeTest {
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
}
