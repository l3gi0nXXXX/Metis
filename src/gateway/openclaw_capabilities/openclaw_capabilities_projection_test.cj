package metis.gateway.openclaw_capabilities

import metis.core.model.{OpenClawProviderBridge, OpenClawProviderRegistration}
import metis.core.tools.{OpenClawToolBridge, OpenClawToolRegistration}
import metis.gateway.openclaw_sandbox.OpenClawSandboxGrantSet

import std.unittest.testmacro.*

@Test
public class OpenClawCapabilitiesProjectionTest {
    @TestCase
    public func toolProjectionPreservesSchemaContextPermissionsTimeoutAndResultShape(): Unit {
        let tool = OpenClawToolRegistration(
            "firecrawl_search",
            "{\"type\":\"object\",\"required\":[\"query\"]}",
            requiredPermissions: ["network:https://api.firecrawl.dev"],
            timeoutMs: 8000,
            contextScopes: ["channel", "account", "peer", "thread"],
            resultOkKey: "ok",
            resultContentKey: "content",
            resultErrorKey: "error"
        )
        let grants = OpenClawSandboxGrantSet(["network:https://api.firecrawl.dev"])
        let projection = OpenClawToolBridge.project(tool, grants)

        @Expect(projection.name, "firecrawl_search")
        @Expect(projection.inputSchema.contains("\"query\""), true)
        @Expect(projection.requiredPermissions[0], "network:https://api.firecrawl.dev")
        @Expect(projection.timeoutMs, 8000)
        @Expect(projection.contextScopes.contains("thread"), true)
        @Expect(projection.allowed, true)
        @Expect(projection.resultShape.okKey, "ok")
        @Expect(projection.resultShape.contentKey, "content")
        @Expect(projection.resultShape.errorKey, "error")
    }

    @TestCase
    public func commandHookApprovalAndInteractiveProjectionAreChannelNeutralAndScoped(): Unit {
        let scope = OpenClawCapabilityScope("generic", "acct-1", "room-7", "thread-3")
        let command = OpenClawCommandProjection("doctor", summary: "Inspect runtime health", aliases: ["health"], requiredPermissions: ["gateway:read"])
        let hook = OpenClawHookProjection("message_media_lifecycle", ["message", "media", "sent-result", "reasoning", "tool-progress"], channelSpecific: false)
        let approval = OpenClawRoutedProjection("tool-execution", scope)
        let interactive = OpenClawRoutedProjection("confirm-button", scope)

        @Expect(command.catalogKey(), "doctor")
        @Expect(command.aliases[0], "health")
        @Expect(command.requiredPermissions[0], "gateway:read")
        @Expect(hook.canDispatch("media", scope), true)
        @Expect(hook.channelSpecific, false)
        @Expect(approval.routeKey(), "generic/acct-1/room-7/thread-3/tool-execution")
        @Expect(interactive.routeKey(), "generic/acct-1/room-7/thread-3/confirm-button")
    }

    @TestCase
    public func providerProjectionSupportsFakeModelListStreamingAndToolCallsWithoutSecrets(): Unit {
        let provider = OpenClawProviderRegistration(
            "fake-openai",
            authKind: "bearer",
            configKeys: ["baseUrl", "timeoutMs"],
            models: ["fake-gpt-4o", "fake-gpt-4o-mini"],
            supportsStreaming: true,
            supportsToolCalls: true,
            supportsModelList: true
        )
        let projection = OpenClawProviderBridge.project(provider)
        let chunks = OpenClawProviderBridge.fakeStream("fake-gpt-4o", "hello")
        let toolCall = OpenClawProviderBridge.fakeToolCall("search", "{\"query\":\"metis\"}")

        @Expect(projection.id, "fake-openai")
        @Expect(projection.authKind, "bearer")
        @Expect(projection.configKeys.contains("baseUrl"), true)
        @Expect(OpenClawProviderBridge.fakeModelList(projection)[1], "fake-gpt-4o-mini")
        @Expect(chunks.size, 2)
        @Expect(chunks[0].kind, "partial-token")
        @Expect(chunks[1].done, true)
        @Expect(toolCall.name, "search")
        @Expect(toolCall.argumentsJson.contains("metis"), true)
        @Expect(projection.toSafeSummary().contains("sk-"), false)
    }
}
