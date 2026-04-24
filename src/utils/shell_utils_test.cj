package metis.utils

import std.unittest.testmacro.*

@Test
public class ShellUtilsTest {
    @TestCase
    public func executeUsesStdProcessCaptureForNoTimeoutCommands(): Unit {
        let (exitCode, stdout, stderr) = ShellUtils.execute(
            ["printf", "hello-shell-utils"],
            withWrap: false
        )
        @Expect(exitCode, 0)
        @Expect(stdout, "hello-shell-utils")
        @Expect(stderr, "")
    }
}
