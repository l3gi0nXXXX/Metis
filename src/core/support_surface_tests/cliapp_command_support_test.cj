package metis.core.support_surface_tests

import metis.program_support.*

import metis.core.commands.renderBuiltinCommandsHelp

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class CliappCommandSupportTest {
    private func noticeEvent(sessionKey: String, notice: String, kind!: String = "session.subagent.notice"): JsonObject {
        let payload = JsonObject()
        payload.put("sessionKey", JsonString(sessionKey))
        payload.put("notice", JsonString(notice))
        let event = JsonObject()
        event.put("kind", JsonString(kind))
        event.put("payload", payload)
        event
    }

    @TestCase
    public func commandLinePredicatesKeepMetisSurfaceNames(): Unit {
        @Expect(programSupportIsGatewayChannelCommandLine("/channel list"), true)
        @Expect(programSupportIsGatewayPluginCommandLine("/plugin list"), true)
        @Expect(programSupportIsGatewayPluginCommandLine("/plugin help"), true)
        @Expect(programSupportIsGatewaySessionsCommandLine("/sessions list"), true)
        @Expect(programSupportIsGatewaySubagentsCommandLine("/subagents list"), true)
        @Expect(programSupportIsGatewayCronCommandLine("/cron list"), true)
    }

    @TestCase
    public func modelProviderPresetCatalogStillUsesMetisConfigPaths(): Unit {
        let presets = programSupportModelProviderPresets()
        @Expect(presets.size > 0, true)
        @Expect(presets[0].apiKeyConfigPath.contains("models.providers."), true)
        @Expect(presets[0].baseURLConfigPath.contains("models.providers."), true)
    }

    @TestCase
    public func metisMenuDetectionRemainsAvailable(): Unit {
        @Expect(programSupportIsMetisCommandLine("/metis"), true)
        @Expect(programSupportIsMetisCommandLine("/Metis status"), true)
        @Expect(programSupportIsMetisCommandLine("/models"), false)
    }

    @TestCase
    public func modelsCommandLineRecognizesHelpAndStatus(): Unit {
        @Expect(programSupportIsModelsCommandLine("/models"), true)
        @Expect(programSupportIsModelsCommandLine("/models status"), true)
        @Expect(programSupportIsModelsCommandLine("models help"), true)
        @Expect(programSupportIsModelsCommandLine("/model status"), false)
    }

    @TestCase
    public func modelsHelpAndStatusAreExplicitAboutScope(): Unit {
        let help = programSupportRenderModelsHelp()
        @Expect(help.contains("Usage: /models [status|help|set-image|image-fallbacks|<provider>|<page>]"), true)
        @Expect(help.contains("/models status"), true)
        @Expect(help.contains("/models set-image"), true)
        @Expect(help.contains("/models <provider>"), true)
        @Expect(help.contains("/models <page>"), true)
        @Expect(help.contains("may write metis.json"), true)
        @Expect(help.contains("metis models set <provider:model>"), true)

        let status = programSupportRenderModelsStatus()
        @Expect(status.contains("Models status (CLI chat)"), true)
        @Expect(status.contains("Image understanding model:"), true)
        @Expect(status.contains("read-only"), true)
        @Expect(status.contains("not a provider catalog"), true)
    }

    @TestCase
    public func modelsProviderBrowseRendersReadOnlyCliCandidates(): Unit {
        let index = programSupportRenderModelsProviderIndex(1)
        @Expect(index.contains("CLI models providers"), true)
        @Expect(index.contains("Use: /models <provider>"), true)
        @Expect(index.contains("Switch: metis models set <provider:model>"), true)

        let provider = programSupportRenderModelsProviderModels("openai", 1)
        @Expect(provider.contains("Models (openai)"), true)
        @Expect(provider.contains("openai/"), true)
        @Expect(provider.contains("Back: /models"), true)
        @Expect(provider.contains("Switch: metis models set <provider:model>"), true)
    }

    @TestCase
    public func modelsProviderBrowseReportsUnknownProviders(): Unit {
        let output = programSupportRenderModelsProviderModels("missing-provider-for-test", 1)
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

    @TestCase
    public func parsesOnlyGatewaySubagentNoticeEvents(): Unit {
        let event = noticeEvent("main", "[Subagent succeeded] reviewer subrun_1 summary done")
        match (programSupportCliSubagentNoticeFromGatewayEvent(event)) {
            case Some(notice) =>
                @Expect(notice.contains("[Subagent succeeded] reviewer subrun_1"), true)
                @Expect(notice.contains("summary done"), true)
            case None => @Expect("missing", "notice")
        }

        @Expect(
            programSupportCliSubagentNoticeFromGatewayEvent(
                noticeEvent("main", "ignored", kind: "session.transcript.updated")
            ).isNone(),
            true
        )
        @Expect(programSupportCliSubagentNoticeFromGatewayEvent(JsonObject()).isNone(), true)
    }

    @TestCase
    public func matchesCanonicalCliSessionAlias(): Unit {
        @Expect(programSupportCliSubagentNoticeEventMatchesSession(noticeEvent("agent:general:main", "notice"), "main"), true)
        @Expect(programSupportCliSubagentNoticeEventMatchesSession(noticeEvent("telegram:chat:owner", "notice"), "main"), false)
    }

    @TestCase
    public func extractsNoticesFromGatewayStreamResult(): Unit {
        let events = JsonArray([])
        events.add(noticeEvent("agent:general:main", "[Subagent succeeded] old subrun_old"))
        events.add(noticeEvent("telegram:chat:owner", "[Subagent failed] other subrun_other"))
        events.add(noticeEvent("main", "[Subagent failed] reviewer subrun_new"))
        let pull = JsonObject()
        pull.put("events", events)
        let result = JsonObject()
        result.put("pull", pull)

        let notices = programSupportCliSubagentNoticesFromGatewayStreamResult(result, "main")
        @Expect(notices.size, 2)
        @Expect(notices[0], "[Subagent succeeded] old subrun_old")
        @Expect(notices[1], "[Subagent failed] reviewer subrun_new")
    }
}
