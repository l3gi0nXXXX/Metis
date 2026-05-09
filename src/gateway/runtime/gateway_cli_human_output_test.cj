package metis.gateway.runtime

import std.unittest.testmacro.*

@Test
public class GatewayCliHumanOutputTest {
    @TestCase
    public func formatsSubagentsListWithoutRawJson(): Unit {
        let raw = "{\"ok\":true,\"status\":\"ok\",\"action\":\"list\",\"filter\":\"active\",\"total\":1,\"activeCount\":1,\"terminalCount\":0,\"staleCount\":0,\"recordedCount\":0,\"sessions\":[{\"runId\":\"subrun_1\",\"sessionKey\":\"session-a\",\"agentId\":\"reviewer\",\"runtime\":\"subagent\",\"effectiveState\":\"running\",\"noticeStatus\":\"none\"}]}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Subagents"), true)
        @Expect(out.contains("subrun_1"), true)
        @Expect(out.contains("\"sessions\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsGatewayDiscoverAsChannelSummary(): Unit {
        let raw = "{\"ok\":true,\"method\":\"discover\",\"result\":{\"channels\":[{\"id\":\"telegram\",\"enabled\":true,\"configured\":true,\"mode\":\"polling\",\"network\":{\"apiRoot\":\"https://api.telegram.org\",\"proxyConfigured\":true},\"media\":{\"downloadEnabled\":true,\"outboundAllowLocalPath\":true,\"outboundAllowUrl\":false}}],\"plugins\":[]}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Gateway channels"), true)
        @Expect(out.contains("telegram"), true)
        @Expect(out.contains("download=true"), true)
        @Expect(out.contains("\"channels\""), false)
    }

    @TestCase
    public func formatsUnsupportedRpcErrorClearly(): Unit {
        let raw = "{\"ok\":false,\"method\":\"channels.unknown\",\"error\":\"Unsupported local gateway RPC method\",\"errorCode\":\"UNSUPPORTED_METHOD\"}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Gateway call failed"), true)
        @Expect(out.contains("UNSUPPORTED_METHOD"), true)
        @Expect(out.contains("\"ok\""), false)
    }

    @TestCase
    public func pluginHelpDocumentsAliasAndSupportedActions(): Unit {
        let help = String.join(gatewayPluginHelpLines(), delimiter: "\n")
        @Expect(help.contains("gateway plugin list"), true)
        @Expect(help.contains("gateway plugins ..."), true)
        @Expect(help.contains("install <name>"), true)
        @Expect(help.contains("enable <id>"), true)
    }
}
