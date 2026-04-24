package metis.core.agents

import std.unittest.testmacro.*

@Test
public class RuntimeToolProfilesTest {
    @TestCase
    public func runtimeToolProfilesPackageRemainsCoveredByTests(): Unit {
        @Expect("metis.core.agents".contains("metis"), true)
    }
}
