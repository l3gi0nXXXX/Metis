package metis.gateway.runtime

import std.unittest.testmacro.*

@Test
public class GatewayServeLockLogicTest {
    @TestCase
    public func parsePidListTextDeduplicatesAndSkipsInvalidRows(): Unit {
        let pids = gatewayParsePidListText("24626\n\nabc\n39668\n24626\n")
        @Expect(pids.size, 2)
        @Expect(pids[0], 24626)
        @Expect(pids[1], 39668)
    }

    @TestCase
    public func looksLikeServeCommandRequiresGatewayServeAndKnownBinary(): Unit {
        @Expect(
            gatewayLooksLikeServeCommand(
                "/bin/zsh -lc rtk cjpm run --skip-build --name metis --run-args gateway serve"
            ),
            true
        )
        @Expect(
            gatewayLooksLikeServeCommand("/usr/bin/python3 -m http.server 18788"),
            false
        )
    }

    @TestCase
    public func resolveStopTargetsPrefersVerifiedListenersOverLockPid(): Unit {
        let listener = gatewayResolveStopTargetPids([24626, 24627], lockPid: Some(39668))
        @Expect(listener.size, 2)
        @Expect(listener[0], 24626)
        @Expect(listener[1], 24627)

        let fallback = gatewayResolveStopTargetPids([], lockPid: Some(39668))
        @Expect(fallback.size, 1)
        @Expect(fallback[0], 39668)
    }
}
