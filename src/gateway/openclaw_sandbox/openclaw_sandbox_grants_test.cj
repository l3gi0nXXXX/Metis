package metis.gateway.openclaw_sandbox

import std.unittest.testmacro.*

@Test
public class OpenClawSandboxGrantsTest {
    @TestCase
    public func sandboxDeniesProcessBrowserAndRealtimeUntilExplicitGrantExists(): Unit {
        let empty = OpenClawSandboxGrantSet([])
        let granted = OpenClawSandboxGrantSet(["process:spawn", "browser:not-applicable", "realtime:stream"])

        @Expect(empty.canSpawnProcess(), false)
        @Expect(empty.canUseBrowser(), false)
        @Expect(empty.canUseRealtime(), false)
        @Expect(granted.canSpawnProcess(), true)
        @Expect(granted.canUseBrowser(), true)
        @Expect(granted.canUseRealtime(), true)
        @Expect(granted.missing(["process:spawn", "network:https://example.com"])[0], "network:https://example.com")
    }
}
