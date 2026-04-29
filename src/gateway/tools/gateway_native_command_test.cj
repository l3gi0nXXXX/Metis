package metis.gateway.tools

import std.unittest.testmacro.*
import stdx.encoding.json.*

@Test
public class GatewayNativeCommandTest {
    private func parse(raw: String): JsonObject {
        JsonValue.fromStr(raw).asObject()
    }

    @TestCase
    public func helpCommandReturnsStructuredGatewayUsage(): Unit {
        let out = parse(gatewayHandleNativeCommandLine("/help").getOrThrow())
        @Expect(out.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(out.get("status").getOrThrow().asString().getValue(), "ok")
        @Expect(out.get("action").getOrThrow().asString().getValue(), "help")
        @Expect(out.get("usage").getOrThrow().asString().getValue().contains("/status"), true)
        @Expect(out.get("commands").getOrThrow().asArray().size() > 0, true)
    }

    @TestCase
    public func statusActivationAndPairCommandsAreRecognized(): Unit {
        @Expect(gatewayHandleNativeCommandLine("/status").isSome(), true)
        @Expect(gatewayHandleNativeCommandLine("/activation").isSome(), true)
        @Expect(gatewayHandleNativeCommandLine("/pair").isSome(), true)
        @Expect(gatewayHandleNativeCommandLine("/unknown").isNone(), true)
    }
}
