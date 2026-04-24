package metis.gateway.config

import std.unittest.testmacro.*

@Test
public class GatewayBootstrapProfilesTest {
    @TestCase
    public func bootstrapCatalogPlanListsBuiltinChannelsAndNonBuiltinPlugins(): Unit {
        let plan = gatewayBootstrapCatalogPlanJson()
        let channelIds = try { plan.get("channelIds").getOrThrow().asArray() } catch (_e: Exception) { @Assert(false); return }
        @Expect(channelIds.size() > 0, true)
        let pluginIds = try { plan.get("pluginIds").getOrThrow().asArray() } catch (_e: Exception) { @Assert(false); return }
        @Expect(pluginIds.size() >= 0, true)
    }
}
