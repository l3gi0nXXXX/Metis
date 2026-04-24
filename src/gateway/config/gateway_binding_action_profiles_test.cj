package metis.gateway.config

import std.unittest.testmacro.*

@Test
public class GatewayBindingActionProfilesTest {
    @TestCase
    public func channelAndPluginActionProfilesReturnExpectedShapes(): Unit {
        @Expect(gatewayChannelBindingConstraintsJson(true, false, false).size(), 3)
        @Expect(gatewayChannelBindingActionsJson("qq", false, false).size() >= 2, true)
        @Expect(gatewayPluginBindingConstraintsJson(true, false, false, false, 0).size(), 5)
        @Expect(gatewayPluginBindingActionsJson("demo", false, false, false, false).size() >= 2, true)
    }
}
