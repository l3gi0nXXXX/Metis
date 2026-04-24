package metis.gateway.runtime

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*

@Test
public class GatewayServerMethodsStatusTest {
    @TestCase
    public func healthAndReadinessExposeSharedInspectContext(): Unit {
        let health = handleGatewayStatusFamily("health", GatewayUserSettings()).getOrThrow()
        let healthResult = health.result.toJsonString()
        @Expect(healthResult.contains("surfaces"), true)
        @Expect(healthResult.contains("platform"), true)

        let readiness = handleGatewayStatusFamily("readiness", GatewayUserSettings()).getOrThrow()
        let readinessResult = readiness.result.toJsonString()
        @Expect(readinessResult.contains("surfaces"), true)
        @Expect(readinessResult.contains("platform"), true)
    }
}
