package metis.gateway.runtime

import metis.gateway.channels.feishu.FeishuAdapter
import metis.gateway.model.FeishuConfig
import std.unittest.testmacro.*

@Test
public class GatewayFeishuSidecarRuntimeTest {
    @TestCase
    public func monitorHostArgsCarryAccountIdAndRedactSecretsForDiagnostics(): Unit {
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                appId: "cli_writer_app",
                appSecret: "sidecar-secret-never-output",
                receiveMode: "long_connect",
                verificationToken: "verify-token-never-output",
                encryptKey: "encrypt-key-never-output"
            ),
            accountId: "feishu-writer"
        )
        let args = adapter.debugOfficialSdkMonitorHostArgsForTest()
        let joined = String.join(args, delimiter: " ")

        @Expect(joined.contains("--account-id feishu-writer"), true)
        @Expect(joined.contains("--app-id cli_writer_app"), true)
        @Expect(joined.contains("sidecar-secret-never-output"), false)
        @Expect(joined.contains("verify-token-never-output"), false)
        @Expect(joined.contains("encrypt-key-never-output"), false)
        @Expect(joined.contains("[redacted]"), true)
    }
}
