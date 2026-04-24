package metis.gateway.runtime

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*

@Test
public class GatewayServerMethodsPlatformTest {
    @TestCase
    public func httpStatusCarriesProbeAliasesAndPaths(): Unit {
        let response = handleGatewayPlatformFamily("http.status", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let http = result.get("http").getOrThrow().asObject()
        @Expect(http.get("health").isSome(), true)
        @Expect(http.get("healthz").isSome(), true)
        @Expect(http.get("ready").isSome(), true)
        @Expect(http.get("readyz").isSome(), true)
        @Expect(http.get("probePaths").isSome(), true)
    }

    @TestCase
    public func controlUiAssetsCarriesSharedRuntimeContext(): Unit {
        let response = handleGatewayPlatformFamily("control_ui.assets", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("summary").isSome(), true)
        @Expect(result.get("binding").isSome(), true)
        @Expect(result.get("contract").isSome(), true)
    }

    @TestCase
    public func controlUiAuthCarriesSharedRuntimeContext(): Unit {
        let response = handleGatewayPlatformFamily("control_ui.auth", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("auth").isSome(), true)
        @Expect(result.get("summary").isSome(), true)
        @Expect(result.get("binding").isSome(), true)
        @Expect(result.get("contract").isSome(), true)
    }

    @TestCase
    public func controlUiHealthCarriesSharedRuntimeContext(): Unit {
        let response = handleGatewayPlatformFamily("control_ui.health", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("summary").isSome(), true)
        @Expect(result.get("binding").isSome(), true)
        @Expect(result.get("contract").isSome(), true)
        @Expect(result.get("state").isSome(), true)
    }
}
