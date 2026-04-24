package metis.gateway.config

import std.unittest.testmacro.*

@Test
public class GatewayChannelCatalogProfilesTest {
    @TestCase
    public func catalogProfilesExposeOrderLabelsAndImages(): Unit {
        @Expect(gatewayChannelOrderJson().size() > 0, true)
        @Expect(gatewayPluginOrderJson().size() >= 0, true)
        @Expect(gatewayChannelLabelsJson().size() > 0, true)
        @Expect(gatewayChannelDetailLabelsJson().size() > 0, true)
        @Expect(gatewayChannelSystemImagesJson().size() > 0, true)
    }
}
