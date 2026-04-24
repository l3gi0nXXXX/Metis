package metis.gateway.runtime

import std.unittest.testmacro.*

@Test
public class GatewayMethodAliasesTest {
    @TestCase
    public func dashboardAliasNormalizesSharedGatewayMethods(): Unit {
        @Expect(gatewayDashboardMethodAlias("health"), "dashboard.status")
        @Expect(gatewayDashboardMethodAlias("chat.send"), "dashboard.chat.send")
        @Expect(gatewayDashboardMethodAlias("models.list"), "dashboard.models")
        @Expect(gatewayDashboardMethodAlias("skills"), "skills.status")
        @Expect(gatewayDashboardMethodAlias("skills.list"), "skills.status")
        @Expect(gatewayDashboardMethodAlias("skills.compatibility"), "skills.compatibilityMatrix")
        @Expect(gatewayDashboardMethodAlias("sessions.reset"), "")
        @Expect(gatewayDashboardMethodAlias("unknown.method"), "")
    }
}
