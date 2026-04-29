package metis.gateway.core

import metis.core.config.CliConfig

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
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

private func withGatewayChannelRuntimeTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-channel-runtime-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    CliConfig.invalidatePathCache()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
    }
}

@Test
public class GatewayChannelRuntimeTest {
    @TestCase
    public func autoEnabledPrimeClearsStaleManualStop(): Unit {
        withGatewayChannelRuntimeTestHome {
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
        }
    }
}
