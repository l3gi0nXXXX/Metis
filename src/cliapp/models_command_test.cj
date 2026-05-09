package metis.cliapp

import metis.core.commands.renderBuiltinCommandsHelp

import std.unittest.testmacro.*

@Test
public class ModelsCommandTest {
    @TestCase
    public func metisMenuDetectionRemainsAvailable(): Unit {
        @Expect(isMetisCommandLine("/metis"), true)
        @Expect(isMetisCommandLine("/Metis status"), true)
        @Expect(isMetisCommandLine("/models"), false)
    }

    @TestCase
    public func modelsCommandLineRecognizesHelpAndStatus(): Unit {
        @Expect(isModelsCommandLine("/models"), true)
        @Expect(isModelsCommandLine("/models status"), true)
        @Expect(isModelsCommandLine("models help"), true)
        @Expect(isModelsCommandLine("/model status"), false)
    }

    @TestCase
    public func modelsHelpAndStatusAreExplicitAboutScope(): Unit {
        let help = renderModelsHelp()
        @Expect(help.contains("Usage: /models [status|help|<provider>|<page>]"), true)
        @Expect(help.contains("/models status"), true)
        @Expect(help.contains("/models <provider>"), true)
        @Expect(help.contains("/models <page>"), true)
        @Expect(help.contains("may write metis.json"), true)
        @Expect(help.contains("metis models set <provider:model>"), true)

        let status = renderModelsStatus()
        @Expect(status.contains("Models status (CLI chat)"), true)
        @Expect(status.contains("read-only"), true)
        @Expect(status.contains("not a provider catalog"), true)
    }

    @TestCase
    public func modelsProviderBrowseRendersReadOnlyCliCandidates(): Unit {
        let index = renderModelsProviderIndex(1)
        @Expect(index.contains("CLI models providers"), true)
        @Expect(index.contains("Use: /models <provider>"), true)
        @Expect(index.contains("Switch: metis models set <provider:model>"), true)

        let provider = renderModelsProviderModels("openai", 1)
        @Expect(provider.contains("Models (openai)"), true)
        @Expect(provider.contains("openai/"), true)
        @Expect(provider.contains("Back: /models"), true)
        @Expect(provider.contains("Switch: metis models set <provider:model>"), true)
    }

    @TestCase
    public func modelsProviderBrowseReportsUnknownProviders(): Unit {
        let output = renderModelsProviderModels("missing-provider-for-test", 1)
        @Expect(output.contains("Unknown provider or no models: missing-provider-for-test"), true)
        @Expect(output.contains("Available providers:"), true)
        @Expect(output.contains("Use: /models <provider>"), true)
    }

    @TestCase
    public func slashHelpListsArgsGatewayAndMenus(): Unit {
        let help = renderBuiltinCommandsHelp()

        @Expect(help.contains("CLI chat slash commands"), true)
        @Expect(help.contains("/channel [list|help|enable|disable|set]"), true)
        @Expect(help.contains("enable <feishu|qq>"), true)
        @Expect(help.contains("/sessions [path|list|show|clear|delete|remove|help]"), true)
        @Expect(help.contains("/plugin [list|list-supported|install|enable|disable|set|help]"), true)
        @Expect(help.contains("/subagents <spawn|list|status|logs|poll|kill|cleanup|steer|send|help>"), true)
        @Expect(help.contains("/cron <status|list|path|add|create|update|edit|remove|rm|delete|enable|disable|run|runs|wake|help>"), true)
        @Expect(help.contains("gateway=yes; menu=yes"), true)
        @Expect(help.contains("gateway=no; menu=yes"), true)
    }

    @TestCase
    public func slashHelpClarifiesStatusModelsAndDashboardSemantics(): Unit {
        let help = renderBuiltinCommandsHelp()

        @Expect(help.contains("/status"), true)
        @Expect(help.contains("not gateway runtime status"), true)
        @Expect(help.contains("/models [status|help|<provider>|<page>]"), true)
        @Expect(help.contains("provider pages are read-only"), true)
        @Expect(help.contains("/dashboard [--open|--no-open|help]"), true)
    }
}
