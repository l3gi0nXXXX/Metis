package metis.core.surface_tests

import metis.core.*

import std.unittest.testmacro.*

@Test
public class GatewayToolRuntimeContextTest {
    @TestCase
    public func runtimeContextPushPopAndCurrentWorkAsStack(): Unit {
        let outer = GatewayToolRuntimeContext("cli", channelName: "cli", sessionKey: "agent:main", prompt: "restart gateway")
        let inner = GatewayToolRuntimeContext("control-ui", channelName: "control-ui", sessionKey: "agent:ui", prompt: "apply config")
        @Expect(gatewayCurrentToolRuntimeContext().isNone(), true)
        gatewayPushToolRuntimeContext(outer)
        try {
            @Expect(gatewayCurrentToolRuntimeContext().isSome(), true)
            @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().sourceLabel, "cli")
            gatewayPushToolRuntimeContext(inner)
            try {
                @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().sourceLabel, "control-ui")
                @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().prompt.contains("apply config"), true)
            } finally {
                gatewayPopToolRuntimeContext()
            }
            @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().sourceLabel, "cli")
        } finally {
            gatewayPopToolRuntimeContext()
        }
        @Expect(gatewayCurrentToolRuntimeContext().isNone(), true)
    }

    @TestCase
    public func withRuntimeContextRestoresPreviousValue(): Unit {
        let outer = GatewayToolRuntimeContext("cli", prompt: "restart gateway")
        let inner = GatewayToolRuntimeContext("dashboard", prompt: "apply config")
        gatewayWithToolRuntimeContext(outer, { =>
            @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().sourceLabel, "cli")
            gatewayWithToolRuntimeContext(inner, { =>
                @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().sourceLabel, "dashboard")
            })
            @Expect(gatewayCurrentToolRuntimeContext().getOrThrow().sourceLabel, "cli")
        })
        @Expect(gatewayCurrentToolRuntimeContext().isNone(), true)
    }
}
