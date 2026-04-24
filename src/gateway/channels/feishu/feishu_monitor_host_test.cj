package metis.gateway.channels.feishu

import std.unittest.testmacro.*

@Test
public class FeishuMonitorHostTest {
    @TestCase
    public func ingressHintUsesMonitorHostWording(): Unit {
        let text = feishuMonitorHostIngressHintText()
        @Expect(text.contains("official SDK monitor host"), true)
        @Expect(text.contains("official WebSocket"), false)
    }

    @TestCase
    public func stopFrameUsesJsonLineProtocol(): Unit {
        @Expect(feishuMonitorHostStopFrame(), "{\"type\":\"stop\"}\n")
    }

    @TestCase
    public func stopWaitWindowsStayShortAndBounded(): Unit {
        @Expect(feishuMonitorHostGraceStopWaitMs(), 400)
        @Expect(feishuMonitorHostForcedStopWaitMs(), 600)
    }

    @TestCase
    public func shellQuoteAndPsLookupStayScopedToScriptAndAppId(): Unit {
        @Expect(feishuMonitorHostShellSingleQuote("a'b"), "'a'\"'\"'b'")
        let command = feishuMonitorHostPsLookupCommand(
            "/tmp/scripts/feishu-ws-sidecar.mjs",
            "cli_test_app"
        )
        @Expect(command.contains("ps -axo pid=,ppid=,command="), true)
        @Expect(command.contains("grep -F --"), true)
        @Expect(command.contains("feishu-ws-sidecar.mjs"), true)
        @Expect(command.contains("--app-id cli_test_app"), true)
    }

    @TestCase
    public func parseMonitorHostPidsReadsLeadingPidColumn(): Unit {
        let raw = "12581     12550 node /tmp/feishu-ws-sidecar.mjs --app-id cli_a\n95093         1 node /tmp/feishu-ws-sidecar.mjs --app-id cli_a\n"
        let pids = feishuParseMonitorHostPids(raw)
        @Expect(pids.size, 2)
        @Expect(pids[0], 12581)
        @Expect(pids[1], 95093)
    }

    @TestCase
    public func parseMonitorHostPidsIgnoresEmptyAndNonNumericSegments(): Unit {
        let raw = "\n  \ninvalid token\n12581 extra\n"
        let pids = feishuParseMonitorHostPids(raw)
        @Expect(pids.size, 1)
        @Expect(pids[0], 12581)
    }
}
