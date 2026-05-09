package metis.cliapp

import std.unittest.testmacro.*

@Test
public class AppPackageSmokeTest {
    @TestCase
    public func commandLinePredicatesKeepMetisSurfaceNames(): Unit {
        @Expect(isGatewayChannelCommandLine("/channel list"), true)
        @Expect(isGatewayPluginCommandLine("/plugin list"), true)
        @Expect(isGatewayPluginCommandLine("/plugin help"), true)
        @Expect(isGatewaySessionsCommandLine("/sessions list"), true)
        @Expect(isGatewaySubagentsCommandLine("/subagents list"), true)
        @Expect(isGatewayCronCommandLine("/cron list"), true)
    }

    @TestCase
    public func modelProviderPresetCatalogStillUsesMetisConfigPaths(): Unit {
        let presets = modelProviderPresets()
        @Expect(presets.size > 0, true)
        @Expect(presets[0].apiKeyConfigPath.contains("models.providers."), true)
        @Expect(presets[0].baseURLConfigPath.contains("models.providers."), true)
    }
}
