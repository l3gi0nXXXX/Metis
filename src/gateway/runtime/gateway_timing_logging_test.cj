package metis.gateway.runtime

import std.unittest.testmacro.*

@Test
public class GatewayTimingLoggingTest {
    @TestCase
    public func gatewayCliTimingMessageFormatsElapsedMs(): Unit {
        @Expect(
            gatewayCliTimingMessage("restart", "launch-done", 1000, nowMs: 1123),
            "[gateway.timing] flow=restart step=launch-done elapsedMs=123"
        )
    }

    @TestCase
    public func gatewayLaunchTimingMessageFormatsElapsedMs(): Unit {
        @Expect(
            gatewayLaunchTimingMessage("nohup-launch-done", 2000, nowMs: 2150),
            "[gateway.timing] flow=launch step=nohup-launch-done elapsedMs=150"
        )
    }
}
