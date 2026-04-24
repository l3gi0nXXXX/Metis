package metis.app

import std.unittest.testmacro.*

@Test
public class ModelsCommandTest {
    @TestCase
    public func metisMenuDetectionRemainsAvailable(): Unit {
        @Expect(isMetisCommandLine("/metis"), true)
        @Expect(isMetisCommandLine("/Metis status"), true)
        @Expect(isMetisCommandLine("/models"), false)
    }
}
