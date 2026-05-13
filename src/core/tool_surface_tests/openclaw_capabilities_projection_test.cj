package metis.core.tool_surface_tests

import metis.gateway.openclaw_capabilities.*

import metis.core.model.{OpenClawProviderBridge, OpenClawProviderRegistration}
import metis.core.tools.{OpenClawMetisToolRegistry, OpenClawToolBridge, OpenClawToolDispatchRequest, OpenClawToolDispatchResult, OpenClawToolRegistration}
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
    public func toolRegistryDispatchesThroughMetisBridgeAndKeepsResultShape(): Unit {
        let tool = OpenClawToolRegistration(
            "tavily.search",
            "{\"type\":\"object\",\"required\":[\"query\"]}",
            requiredPermissions: ["network:https://api.tavily.com"],
            timeoutMs: 9000,
            contextScopes: ["channel", "account", "peer", "thread"],
            resultOkKey: "ok",
            resultContentKey: "content",
            resultErrorKey: "error"
        )
        let projection = OpenClawToolBridge.project(tool, OpenClawSandboxGrantSet(["network:https://api.tavily.com"]))
        let registry = OpenClawMetisToolRegistry()

        registry.register(projection, { request: OpenClawToolDispatchRequest =>
            OpenClawToolDispatchResult(
                true,
                content: "tool=${request.name};thread=${request.threadId};input=${request.inputJson}",
                rawJson: "{\"ok\":true,\"content\":\"fixture\"}"
            )
        })

        let listed = registry.list()
        let result = registry.dispatch(OpenClawToolDispatchRequest(
            "tavily.search",
            inputJson: "{\"query\":\"metis\"}",
            channelId: "generic",
            accountId: "acct-1",
            peerId: "peer-1",
            threadId: "thread-1"
        ))

        @Expect(listed.size, 1)
        @Expect(listed[0].inputSchema.contains("\"query\""), true)
        @Expect(listed[0].timeoutMs, 9000)
        @Expect(listed[0].resultShape.contentKey, "content")
        @Expect(result.ok, true)
        @Expect(result.content.contains("thread=thread-1"), true)
        @Expect(result.rawJson.contains("\"ok\":true"), true)
    }

    @TestCase
    public func toolRegistryReturnsStructuredNotSupportedEvidenceForDeniedOrMissingTools(): Unit {
        let restrictedTool = OpenClawToolRegistration(
            "firecrawl_search",
            "{\"type\":\"object\",\"required\":[\"query\"]}",
            requiredPermissions: ["network:https://api.firecrawl.dev"],
            timeoutMs: 8000
        )
        let registry = OpenClawMetisToolRegistry()

        registry.register(OpenClawToolBridge.project(restrictedTool, OpenClawSandboxGrantSet([])), { _: OpenClawToolDispatchRequest =>
            OpenClawToolDispatchResult(true, content: "should not run")
        })

        let denied = registry.dispatch(OpenClawToolDispatchRequest("firecrawl_search", inputJson: "{\"query\":\"metis\"}"))
        let missing = registry.dispatch(OpenClawToolDispatchRequest("missing_tool"))

        @Expect(denied.ok, false)
        @Expect(denied.status, "not_supported")
        @Expect(denied.evidenceJson.contains("network:https://api.firecrawl.dev"), true)
        @Expect(missing.status, "not_supported")
        @Expect(missing.evidenceJson.contains("\"tool\":\"missing_tool\""), true)
    }

    @TestCase
    public func commandHookApprovalAndInteractiveProjectionAreChannelNeutralAndScoped(): Unit {
        let scope = OpenClawCapabilityScope("generic", "acct-1", "room-7", "thread-3")
        let command = OpenClawCommandProjection("doctor", summary: "Inspect runtime health", aliases: ["health"], requiredPermissions: ["gateway:read"])
        let cli = OpenClawCommandProjection("metis approvals status", summary: "Show approval queue", aliases: ["approvals"], requiredPermissions: ["gateway:read"])
        let hook = OpenClawHookProjection("message_media_lifecycle", ["message", "media", "sent-result", "reasoning", "tool-progress"], channelSpecific: false)
        let approval = OpenClawRoutedProjection("tool-execution", scope)
        let interactive = OpenClawRoutedProjection("confirm-button", scope)
        let catalog = OpenClawCommandCatalog()
        let hookRegistry = OpenClawLifecycleHookRegistry()
        let scopedRegistry = OpenClawScopedDispatchRegistry()

        catalog.register(command, { request: OpenClawCommandDispatchRequest =>
            OpenClawCommandDispatchResult(true, status: "dispatched", payloadJson: "{\"command\":\"${request.name}\",\"input\":${request.inputJson}}")
        })
        catalog.registerCli(cli, { request: OpenClawCommandDispatchRequest =>
            OpenClawCommandDispatchResult(true, status: "dispatched", payloadJson: "{\"cli\":\"${request.name}\"}")
        })
        hookRegistry.register(hook, { event: OpenClawLifecycleHookEvent =>
            OpenClawLifecycleHookResult(true, payloadJson: "{\"stage\":\"${event.stage}\",\"payload\":${event.payloadJson}}")
        })
        scopedRegistry.registerApproval(approval, { request: OpenClawScopedDispatchRequest =>
            OpenClawScopedDispatchResult(true, status: "approved", payloadJson: request.payloadJson)
        })
        scopedRegistry.registerInteractive(interactive, { request: OpenClawScopedDispatchRequest =>
            OpenClawScopedDispatchResult(true, status: "handled", payloadJson: request.payloadJson)
        })

        let hookResults = hookRegistry.dispatch(OpenClawLifecycleHookEvent("tool-progress", "{\"percent\":50}", scope))
        let missingHookResult = hookRegistry.dispatchOne(OpenClawLifecycleHookEvent("unregistered-stage", "{}", scope))
        let commandResult = catalog.dispatch(OpenClawCommandDispatchRequest("health", inputJson: "{\"verbose\":true}", scope: scope))
        let cliResult = catalog.dispatchCli(OpenClawCommandDispatchRequest("approvals", scope: scope))
        let missingCommandResult = catalog.dispatch(OpenClawCommandDispatchRequest("missing", scope: scope))
        let approvalResult = scopedRegistry.dispatchApproval(OpenClawScopedDispatchRequest("tool-execution", scope, payloadJson: "{\"decision\":\"allow\"}"))
        let interactiveResult = scopedRegistry.dispatchInteractive(OpenClawScopedDispatchRequest("confirm-button", scope, payloadJson: "{\"data\":\"ok\"}"))

        @Expect(command.catalogKey(), "doctor")
        @Expect(command.aliases[0], "health")
        @Expect(command.requiredPermissions[0], "gateway:read")
        @Expect(catalog.contains("health"), true)
        @Expect(catalog.list()[0].summary, "Inspect runtime health")
        @Expect(catalog.listCli()[0].name, "metis approvals status")
        @Expect(commandResult.status, "dispatched")
        @Expect(cliResult.payloadJson.contains("approvals"), true)
        @Expect(missingCommandResult.status, "not_supported")
        @Expect(missingCommandResult.evidenceJson.contains("\"kind\":\"command\""), true)
        @Expect(hook.canDispatch("media", scope), true)
        @Expect(hook.channelSpecific, false)
        @Expect(hookResults.size, 1)
        @Expect(hookResults[0].payloadJson.contains("tool-progress"), true)
        @Expect(missingHookResult.status, "not_supported")
        @Expect(missingHookResult.evidenceJson.contains("unregistered-stage"), true)
        @Expect(approval.routeKey(), "generic/acct-1/room-7/thread-3/tool-execution")
        @Expect(interactive.routeKey(), "generic/acct-1/room-7/thread-3/confirm-button")
        @Expect(approvalResult.status, "approved")
        @Expect(interactiveResult.status, "handled")
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
