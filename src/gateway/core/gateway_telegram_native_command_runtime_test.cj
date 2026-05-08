package metis.gateway.core

import std.unittest.testmacro.*
import stdx.encoding.json.JsonValue

@Test
public class GatewayTelegramNativeCommandRuntimeTest {
    @TestCase
    public func parsesSlashCommandAliasesAndBotSuffixToCatalogCommand(): Unit {
        let runtime = GatewayTelegramNativeCommandRuntime()
        let decision = runtime.resolveText(
            "/tell@MetisBot worker stay focused",
            "8734062810",
            "default",
            "telegram:direct:8734062810",
            true
        )

        @Expect(decision.handled, true)
        let context = decision.context.getOrThrow()
        @Expect(context.command, "steer")
        @Expect(context.argsText, "worker stay focused")
        @Expect(context.commandText, "/steer worker stay focused")
        @Expect(decision.preflightReply, "")
    }

    @TestCase
    public func resolvesNativeCallbackDataThroughSameCatalogContext(): Unit {
        let runtime = GatewayTelegramNativeCommandRuntime()
        let decision = runtime.resolveCallbackData(
            "cmd:think:high",
            "8734062810",
            "default",
            "telegram:direct:8734062810",
            true
        )

        @Expect(decision.handled, true)
        let context = decision.context.getOrThrow()
        @Expect(context.isCallback, true)
        @Expect(context.command, "think")
        @Expect(context.commandText, "/think high")
        @Expect(decision.preflightReply, "")
    }

    @TestCase
    public func rejectsOperatorCommandsBeforeGatewayHandlerRuns(): Unit {
        let runtime = GatewayTelegramNativeCommandRuntime()
        let decision = runtime.resolveText(
            "/bash echo no",
            "123",
            "default",
            "telegram:direct:123",
            false
        )

        @Expect(decision.handled, true)
        let root = JsonValue.fromStr(decision.preflightReply).asObject()
        @Expect(root.get("action").getOrThrow().asString().getValue(), "bash")
        @Expect(root.get("status").getOrThrow().asString().getValue(), "rejected")
        @Expect(root.get("ok").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func catalogHasAllowedStatusesAndNoImplementedCommandWithoutHandler(): Unit {
        let validation = gatewayTelegramNativeCommandCatalogValidation()
        @Expect(validation.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(validation.get("invalidStatuses").getOrThrow().asArray().size(), 0)
        @Expect(validation.get("missingHandlers").getOrThrow().asArray().size(), 0)
        @Expect(gatewayFindTelegramNativeCommandSpec("allowlist").getOrThrow().status, "approval_required")
        @Expect(gatewayFindTelegramNativeCommandSpec("acp").getOrThrow().status, "not_applicable")
    }
}
