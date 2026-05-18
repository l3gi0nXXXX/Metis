package metis.gateway.runtime

import std.unittest.testmacro.*

private func gatewayHumanTelegramAccountInspectJson(): String {
    return "\"accountInspect\":{" +
        "\"defaultAccountId\":\"writer\"," +
        "\"tokenRedacted\":true," +
        "\"count\":2," +
        "\"accounts\":[" +
            "{" +
                "\"accountId\":\"writer\"," +
                "\"defaultAccount\":true," +
                "\"configured\":true," +
                "\"tokenSource\":\"account-botToken\"," +
                "\"hasBotToken\":true," +
                "\"hasTokenFile\":false," +
                "\"allowFromCount\":1," +
                "\"allowFromEffectiveCount\":1," +
                "\"groupAllowFromCount\":2," +
                "\"groupAllowFromEffectiveCount\":2," +
                "\"securitySources\":{\"allowFrom\":\"account-local\",\"groupAllowFrom\":\"account-local\",\"dmPolicy\":\"account-local\",\"groupPolicy\":\"account-local\"}," +
                "\"approvedSenderCount\":3," +
                "\"hasMediaOverride\":true," +
                "\"hasNetworkOverride\":false," +
                "\"hasGroupsOverride\":false," +
                "\"hasDirectOverride\":true," +
                "\"hasDmsOverride\":false," +
                "\"botToken\":\"111111111:fake-writer-token\"" +
            "}," +
            "{" +
                "\"accountId\":\"reviewer\"," +
                "\"defaultAccount\":false," +
                "\"configured\":true," +
                "\"tokenSource\":\"account-botToken\"," +
                "\"hasBotToken\":true," +
                "\"hasTokenFile\":false," +
                "\"allowFromCount\":0," +
                "\"allowFromEffectiveCount\":0," +
                "\"groupAllowFromCount\":0," +
                "\"groupAllowFromEffectiveCount\":0," +
                "\"securitySources\":{\"allowFrom\":\"explicit-empty\",\"groupAllowFrom\":\"explicit-empty\",\"dmPolicy\":\"account-local\",\"groupPolicy\":\"account-local\"}," +
                "\"approvedSenderCount\":0," +
                "\"hasMediaOverride\":false," +
                "\"hasNetworkOverride\":true," +
                "\"hasGroupsOverride\":false," +
                "\"hasDirectOverride\":false," +
                "\"hasDmsOverride\":false," +
                "\"token\":\"222222222:fake-reviewer-token\"" +
            "}" +
        "]" +
    "}"
}

private func gatewayHumanTelegramChannelGetRaw(): String {
    return "{\"ok\":true,\"method\":\"channels.get\",\"result\":{\"channel\":{" +
        "\"id\":\"telegram\"," +
        "\"enabled\":true," +
        "\"configured\":true," +
        "\"mode\":\"polling\"," +
        "\"network\":{\"apiRoot\":\"https://api.telegram.org\",\"proxyConfigured\":true,\"envProxyEnabled\":false}," +
        "\"media\":{\"downloadEnabled\":true,\"mediaMaxBytes\":20971520,\"outboundAllowLocalPath\":true,\"outboundAllowUrl\":false}," +
        "\"directory\":{\"rowCount\":1}," +
        "\"actions\":{\"sendMessage\":true,\"photo\":true,\"document\":true,\"audio\":true,\"voice\":true,\"video\":true,\"reactions\":true}," +
        gatewayHumanTelegramAccountInspectJson() +
    "}}}"
}

private func gatewayHumanFeishuChannelGetRaw(): String {
    return "{\"ok\":true,\"method\":\"channels.get\",\"result\":{\"channel\":{" +
        "\"id\":\"feishu\"," +
        "\"enabled\":true," +
        "\"configured\":true," +
        "\"mode\":\"event\"," +
        "\"accountInspect\":{" +
            "\"defaultAccountId\":\"tenant-a\"," +
            "\"tokenRedacted\":true," +
            "\"count\":2," +
            "\"accounts\":[" +
                "{" +
                    "\"accountId\":\"tenant-a\"," +
                    "\"defaultAccount\":true," +
                    "\"enabled\":true," +
                    "\"configured\":true," +
                    "\"credentialSource\":\"account\"," +
                    "\"hasAppId\":true," +
                    "\"hasAppSecret\":true," +
                    "\"appId\":\"cli***123\"," +
                    "\"appSecret\":\"fake-feishu-secret-never-output\"," +
                    "\"token\":\"fake-feishu-token-never-output\"" +
                "}," +
                "{" +
                    "\"accountId\":\"tenant-b\"," +
                    "\"defaultAccount\":false," +
                    "\"enabled\":true," +
                    "\"configured\":false," +
                    "\"credentialSource\":\"missing\"," +
                    "\"hasAppId\":false," +
                    "\"hasAppSecret\":false" +
                "}" +
            "]" +
        "}" +
    "}}}"
}

private func gatewayHumanQqChannelGetRaw(): String {
    return "{\"ok\":true,\"method\":\"channels.get\",\"result\":{\"channel\":{" +
        "\"id\":\"qq\"," +
        "\"enabled\":true," +
        "\"configured\":true," +
        "\"mode\":\"official\"," +
        "\"accountInspect\":{" +
            "\"defaultAccountId\":\"work\"," +
            "\"redacted\":true," +
            "\"count\":2," +
            "\"accounts\":[" +
                "{" +
                    "\"accountId\":\"work\"," +
                    "\"defaultAccount\":true," +
                    "\"enabled\":true," +
                    "\"configured\":true," +
                    "\"credentialSource\":\"account\"," +
                    "\"appId\":\"998***665\"," +
                    "\"appSecret\":\"fake-qq-secret-never-output\"," +
                    "\"token\":\"fake-qq-token-never-output\"" +
                "}," +
                "{" +
                    "\"accountId\":\"backup\"," +
                    "\"defaultAccount\":false," +
                    "\"enabled\":true," +
                    "\"configured\":false," +
                    "\"credentialSource\":\"missing\"," +
                    "\"appId\":\"\"," +
                    "\"appSecret\":\"\"" +
                "}" +
            "]" +
        "}" +
    "}}}"
}

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
    public func formatsTelegramChannelGetWithMultipleAccounts(): Unit {
        let out = gatewayFormatCommandOutput(gatewayHumanTelegramChannelGetRaw())
        @Expect(out.contains("Channel: telegram"), true)
        @Expect(out.contains("Accounts: 2"), true)
        @Expect(out.contains("default=writer"), true)
        @Expect(out.contains("telegram/writer [default]"), true)
        @Expect(out.contains("telegram/reviewer"), true)
        @Expect(out.contains("token=account-botToken"), true)
        @Expect(out.contains("allowEffective=0"), true)
        @Expect(out.contains("groupAllowEffective=0"), true)
        @Expect(out.contains("allowSource=explicit-empty"), true)
        @Expect(out.contains("groupAllowSource=explicit-empty"), true)
        @Expect(out.contains("binding=telegram:writer"), true)
        @Expect(out.contains("binding=telegram:reviewer"), true)
        @Expect(out.contains("111111111:fake-writer-token"), false)
        @Expect(out.contains("222222222:fake-reviewer-token"), false)
        @Expect(out.contains("\"accountInspect\""), false)
        @Expect(out.contains("\"accounts\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsFeishuChannelGetAccountsWithoutSecrets(): Unit {
        let out = gatewayFormatCommandOutput(gatewayHumanFeishuChannelGetRaw())
        @Expect(out.contains("Channel: feishu"), true)
        @Expect(out.contains("Accounts: 2"), true)
        @Expect(out.contains("default=tenant-a"), true)
        @Expect(out.contains("feishu/tenant-a [default]"), true)
        @Expect(out.contains("feishu/tenant-b"), true)
        @Expect(out.contains("credential=account"), true)
        @Expect(out.contains("binding=feishu:tenant-a"), true)
        @Expect(out.contains("binding=feishu:tenant-b"), true)
        @Expect(out.contains("fake-feishu-secret-never-output"), false)
        @Expect(out.contains("fake-feishu-token-never-output"), false)
        @Expect(out.contains("\"appSecret\""), false)
        @Expect(out.contains("\"token\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsQqChannelGetAccountsWithoutSecrets(): Unit {
        let out = gatewayFormatCommandOutput(gatewayHumanQqChannelGetRaw())
        @Expect(out.contains("Channel: qq"), true)
        @Expect(out.contains("Accounts: 2"), true)
        @Expect(out.contains("default=work"), true)
        @Expect(out.contains("qq/work [default]"), true)
        @Expect(out.contains("qq/backup"), true)
        @Expect(out.contains("credential=account"), true)
        @Expect(out.contains("appId=998***665"), true)
        @Expect(out.contains("binding=qq:work"), true)
        @Expect(out.contains("binding=qq:backup"), true)
        @Expect(out.contains("fake-qq-secret-never-output"), false)
        @Expect(out.contains("fake-qq-token-never-output"), false)
        @Expect(out.contains("\"appSecret\""), false)
        @Expect(out.contains("\"token\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func keepsChannelGetWithoutAccountInspectStable(): Unit {
        let raw = "{\"ok\":true,\"method\":\"channels.get\",\"result\":{\"channel\":{\"id\":\"webhook-demo\",\"enabled\":true,\"configured\":false,\"mode\":\"webhook\",\"network\":{\"apiRoot\":\"https://example.test\",\"proxyConfigured\":false,\"envProxyEnabled\":false},\"media\":{\"downloadEnabled\":false,\"mediaMaxBytes\":0,\"outboundAllowLocalPath\":false,\"outboundAllowUrl\":false}}}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Channel: webhook-demo"), true)
        @Expect(out.contains("Enabled: true  configured=false  mode=webhook"), true)
        @Expect(out.contains("Network: apiRoot=https://example.test"), true)
        @Expect(out.contains("Media: download=false"), true)
        @Expect(out.contains("Accounts:"), false)
        @Expect(out.contains("\"accountInspect\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsChannelRuntimeWithConfiguredAccountsSeparately(): Unit {
        let raw = "{\"ok\":true,\"method\":\"channels.runtime\",\"result\":{" +
            "\"channelId\":\"telegram\"," +
            "\"defaultAccountId\":\"writer\"," +
            "\"accounts\":[{\"channelId\":\"telegram\",\"accountId\":\"writer\",\"running\":true,\"phase\":\"running\",\"pullCount\":12,\"inboundCount\":3,\"sendSuccessCount\":3,\"sendFailureCount\":0}]," +
            "\"telegram\":{" + gatewayHumanTelegramAccountInspectJson() + "}" +
        "}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Channel runtime: telegram"), true)
        @Expect(out.contains("Configured default account: writer"), true)
        @Expect(out.contains("Runtime accounts:"), true)
        @Expect(out.contains("telegram/writer: running=true"), true)
        @Expect(out.contains("Configured accounts: 2"), true)
        @Expect(out.contains("default=writer"), true)
        @Expect(out.contains("telegram/writer [default]"), true)
        @Expect(out.contains("telegram/reviewer"), true)
        @Expect(out.contains("binding=telegram:writer"), true)
        @Expect(out.contains("binding=telegram:reviewer"), true)
        @Expect(out.contains("telegram/reviewer: running=true"), false)
        @Expect(out.contains("111111111:fake-writer-token"), false)
        @Expect(out.contains("222222222:fake-reviewer-token"), false)
        @Expect(out.contains("\"accountInspect\""), false)
        @Expect(out.contains("\"accounts\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func formatsFeishuRuntimeWithConfiguredAndLiveAccountsWithoutRawJson(): Unit {
        let raw = "{\"ok\":true,\"method\":\"channels.runtime\",\"result\":{" +
            "\"channelId\":\"feishu\"," +
            "\"defaultAccountId\":\"tenant-a\"," +
            "\"accounts\":[" +
                "{\"channelId\":\"feishu\",\"accountId\":\"tenant-a\",\"running\":true,\"phase\":\"running\",\"pullCount\":0,\"inboundCount\":1,\"sendSuccessCount\":1,\"sendFailureCount\":0}," +
                "{\"channelId\":\"feishu\",\"accountId\":\"tenant-b\",\"running\":false,\"phase\":\"configured\",\"pullCount\":0,\"inboundCount\":0,\"sendSuccessCount\":0,\"sendFailureCount\":0,\"lastError\":\"wrong_app for account tenant-b\"}" +
            "]," +
            "\"feishu\":{\"accountInspect\":{" +
                "\"defaultAccountId\":\"tenant-a\"," +
                "\"redacted\":true," +
                "\"count\":2," +
                "\"accounts\":[" +
                    "{" +
                        "\"accountId\":\"tenant-a\"," +
                        "\"defaultAccount\":true," +
                        "\"enabled\":true," +
                        "\"configured\":true," +
                        "\"credentialSource\":\"account\"," +
                        "\"hasAppId\":true," +
                        "\"hasAppSecret\":true," +
                        "\"appId\":\"cli***123\"," +
                        "\"appSecret\":\"fake-feishu-secret-never-output\"" +
                    "}," +
                    "{" +
                        "\"accountId\":\"tenant-b\"," +
                        "\"defaultAccount\":false," +
                        "\"enabled\":true," +
                        "\"configured\":true," +
                        "\"credentialSource\":\"account\"," +
                        "\"hasAppId\":true," +
                        "\"hasAppSecret\":true," +
                        "\"appId\":\"cli***456\"," +
                        "\"appSecret\":\"fake-feishu-secret-never-output\"" +
                    "}" +
                "]" +
            "}}" +
        "}}"
        let out = gatewayFormatCommandOutput(raw)
        @Expect(out.contains("Channel runtime: feishu"), true)
        @Expect(out.contains("Configured default account: tenant-a"), true)
        @Expect(out.contains("Runtime accounts:"), true)
        @Expect(out.contains("feishu/tenant-a: running=true phase=running"), true)
        @Expect(out.contains("feishu/tenant-b: running=false phase=configured"), true)
        @Expect(out.contains("Configured accounts: 2"), true)
        @Expect(out.contains("feishu/tenant-a [default]"), true)
        @Expect(out.contains("feishu/tenant-b"), true)
        @Expect(out.contains("binding=feishu:tenant-a"), true)
        @Expect(out.contains("binding=feishu:tenant-b"), true)
        @Expect(out.contains("fake-feishu-secret-never-output"), false)
        @Expect(out.contains("\"accounts\""), false)
        @Expect(out.contains("{"), false)
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
