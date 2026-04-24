package metis.gateway.runtime

import metis.core.config.{CliSettingManager, MetisConfigManager}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.unittest.testmacro.*

@Test
public class GatewayCliConfigValidationTest {
    @TestCase
    public func cliGatewayClientUsesLocalTransportUnlessRemoteGatewayIsEnabled(): Unit {
        let testHome = "/tmp/metis-phase4-gateway-cli-transport-selection"
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let original = CliSettingManager.readGatewaySettings()
        try {
            var localOnly = original
            localOnly.remote.enabled = false
            let _ = MetisConfigManager.setGatewaySettings(localOnly)
            CliSettingManager.invalidate()

            let localClient = gatewayCliClient()
            @Expect(localClient.transport, "local")
            @Expect(localClient.gatewayUrl, "local://gateway")

            var remote = original
            remote.remote.enabled = true
            remote.remote.transport = "ssh"
            remote.remote.url = "https://gateway.example.test"
            let _ = MetisConfigManager.setGatewaySettings(remote)
            CliSettingManager.invalidate()

            let remoteClient = gatewayCliClient()
            @Expect(remoteClient.transport, "ssh")
            @Expect(remoteClient.gatewayUrl, "https://gateway.example.test")
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
        }
    }

    @TestCase
    public func restartValidationMessageReportsInvalidConfig(): Unit {
        let testHome = "/tmp/metis-phase3-gateway-restart-invalid-config-message"
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let invalidConfig = "{\n" +
            "  \"gateway\": {\"auth\": {\"mode\": \"token\"}}\n" +
            "}\n" +
            "\"\n"
        File.writeTo(MetisConfigManager.configPath(), invalidConfig.toArray())

        let message = gatewayRestartConfigValidationMessage().getOrThrow()
        @Expect(message.contains("metis.json 解析失败"), true)
        @Expect(message.contains("跳过任何配置持久化"), true)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func restartReturnsFailureWithoutStoppingOrLaunchingWhenConfigIsInvalid(): Unit {
        let testHome = "/tmp/metis-phase3-gateway-restart-invalid-config-code"
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let invalidConfig = "{\n" +
            "  \"gateway\": {\"auth\": {\"mode\": \"token\"}}\n" +
            "}\n" +
            "\"\n"
        let path = MetisConfigManager.configPath()
        File.writeTo(path, invalidConfig.toArray())

        @Expect(gatewayExecuteRestartServe(), 1)
        @Expect(String.fromUtf8(File.readFrom(path)), invalidConfig)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}
