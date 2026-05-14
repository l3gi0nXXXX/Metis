package metis.core.model

import metis.core.config.CliConfig

import std.unittest.testmacro.*

@Test
public class ModelTokenLimitsTest {
    @TestCase
    public func deepseekV4ProOutputLimitDoesNotFallBackToZeroDefault(): Unit {
        let oldDefault = CliConfig.defaultModelOutputLimit
        try {
            CliConfig.defaultModelOutputLimit = 0
            @Expect(ModelTokenLimits.getOutputLimit("deepseek:deepseek-v4-pro") > 0, true)
        } finally {
            CliConfig.defaultModelOutputLimit = oldDefault
        }
    }
}
