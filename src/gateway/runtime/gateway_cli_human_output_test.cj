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
    public func formatsImageUnderstandingStatusWithoutRawJson(): Unit {
        let raw = "{\"configChannel\":\"telegram\",\"channel\":\"telegram\",\"configured\":true,\"enabled\":true,\"imageModel\":\"dashscope:qwen-vl-max\",\"imageFallbackModels\":[\"openai:gpt-4o\"],\"candidateCount\":1,\"candidates\":[{\"modelRef\":\"dashscope:qwen-vl-max\",\"source\":\"agents.defaults.imageModel.primary\",\"capability\":{\"modelRef\":\"dashscope:qwen-vl-max\",\"status\":\"supported\"}}],\"rejected\":[{\"modelRef\":\"deepseek:deepseek-v4-pro\",\"source\":\"agents.defaults.model.primary\",\"capability\":{\"modelRef\":\"deepseek:deepseek-v4-pro\",\"status\":\"unsupported\",\"reason\":\"built-in deny\"}}]}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Image understanding"), true)
        @Expect(out.contains("telegram"), true)
        @Expect(out.contains("dashscope:qwen-vl-max"), true)
        @Expect(out.contains("openai:gpt-4o"), true)
        @Expect(out.contains("Skipped"), true)
        @Expect(out.contains("deepseek:deepseek-v4-pro"), true)
        @Expect(out.contains("\"candidates\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsImageConfigMutationWithoutRawJson(): Unit {
        let raw = "{\"ok\":true,\"channel\":\"telegram\",\"action\":\"set\",\"image\":{\"enabled\":true,\"provider\":\"dashscope\",\"models\":[{\"provider\":\"dashscope\",\"model\":\"qwen-vl-max\"}]}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Image understanding configuration updated"), true)
        @Expect(out.contains("Channel: telegram"), true)
        @Expect(out.contains("dashscope:qwen-vl-max"), true)
        @Expect(out.contains("\"image\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsCronJobObjectWithoutRawJson(): Unit {
        let raw = "{\"id\":\"job-a\",\"enabled\":true,\"prompt\":\"hello cron\",\"sessionTarget\":\"main\",\"schedule\":{\"kind\":\"every\",\"everyMs\":60000},\"state\":{\"nextRunAtMs\":1710000000000}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Cron job"), true)
        @Expect(out.contains("ID: job-a"), true)
        @Expect(out.contains("every 60000ms"), true)
        @Expect(out.contains("\"schedule\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsGenericRpcSuccessWithoutRawJson(): Unit {
        let raw = "{\"ok\":true,\"method\":\"usage-cost\",\"result\":{\"totalTokens\":12,\"estimatedCostUsd\":\"0.01\"}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Gateway call: usage-cost"), true)
        @Expect(out.contains("Result fields:"), true)
        @Expect(out.contains("\"result\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func pluginHelpDocumentsAliasAndSupportedActions(): Unit {
        let help = String.join(gatewayPluginHelpLines(), delimiter: "\n")
        @Expect(help.contains("gateway plugin list"), true)
        @Expect(help.contains("gateway plugins ..."), true)
        @Expect(help.contains("install <name>"), true)
        @Expect(help.contains("enable <id>"), true)
    }

    @TestCase
    public func runtimeHintIsOnlyForGatewayConnectionFailures(): Unit {
        @Expect(gatewayCliShouldPrintRuntimeRequiredHint("Gateway client connect failed."), true)
        @Expect(gatewayCliShouldPrintRuntimeRequiredHint("Http status: 401"), false)
        @Expect(
            gatewayCliShouldPrintRuntimeRequiredHint("Model replied an invalid message: Invalid max_tokens value"),
            false
        )
    }
}
