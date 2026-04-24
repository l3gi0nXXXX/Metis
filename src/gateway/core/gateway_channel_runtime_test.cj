package metis.gateway.core

import std.fs.{File, Path, exists}
import std.unittest.testmacro.*

private func gatewayChannelRuntimeTestReadState(): String {
    let path = Path(gatewayChannelRuntimeStatePath())
    if (!exists(path)) {
        return ""
    }
    String.fromUtf8(File.readFrom(path))
}

private func gatewayChannelRuntimeTestWriteState(content: String): Unit {
    File.writeTo(Path(gatewayChannelRuntimeStatePath()), content.toArray())
}

@Test
public class GatewayChannelRuntimeTest {
    @TestCase
    public func autoEnabledPrimeClearsStaleManualStop(): Unit {
        let original = gatewayChannelRuntimeTestReadState()
        try {
            gatewayChannelRuntimeTestWriteState("{}")
            gatewayChannelRuntimeRegisterAccount("qq", accountId: "qq:test")
            gatewayChannelRuntimeMarkStopped("qq", accountId: "qq:test", reason: "manual-stop", manualStop: true)
            @Expect(gatewayChannelRuntimeCanStart("qq", accountId: "qq:test"), false)

            let primed = gatewayChannelRuntimePrimeAccount(
                "qq",
                accountId: "qq:test",
                configuredBinding: true,
                autoEnabled: true
            )
            @Expect(primed.get("manualStop").getOrThrow().asBool().getValue(), false)
            @Expect(primed.get("abortState").getOrThrow().asString().getValue(), "clear")
            @Expect(gatewayChannelRuntimeCanStart("qq", accountId: "qq:test"), true)
        } finally {
            gatewayChannelRuntimeTestWriteState(original)
        }
    }
}
