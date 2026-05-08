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
        @Expect(empty.canFetchHttp("https://api.example.test/v1"), false)
        @Expect(granted.canSpawnProcess(), true)
        @Expect(granted.canUseBrowser(), true)
        @Expect(granted.canUseRealtime(), true)
        @Expect(granted.missing(["process:spawn", "network:https://example.com"])[0], "network:https://example.com")
    }

    @TestCase
    public func sandboxManagerExecutesGrantedProcessAndMarksHighRiskFacetsNotApplicable(): Unit {
        let empty = OpenClawSandboxManager(OpenClawSandboxGrantSet([]))
        let granted = OpenClawSandboxManager(OpenClawSandboxGrantSet([
            "process:spawn",
            "browser:not-applicable",
            "realtime:not-applicable"
        ]))

        @Expect(empty.spawnProcess("node", ["--version"]).status, "permission_denied")
        @Expect(granted.spawnProcess("node", ["--version"]).status, "authorized")
        @Expect(granted.spawnProcess("node", ["--version"]).contract, "metis.openclaw-sandbox.v1")
        @Expect(granted.browserAutomation("open page").status, "not_applicable")
        @Expect(granted.browserAutomation("open page").notApplicable, true)
        @Expect(granted.realtimeSession("websocket").status, "not_applicable")
        @Expect(granted.notApplicableEvidence().contains("browser:not-applicable"), true)
        @Expect(granted.notApplicableEvidence().contains("realtime:not-applicable"), true)
    }

    @TestCase
    public func sandboxManagerRecordsFetchGrantDecisions(): Unit {
        let empty = OpenClawSandboxManager(OpenClawSandboxGrantSet([]))
        let granted = OpenClawSandboxManager(OpenClawSandboxGrantSet([
            "network:https://api.example.test",
            "network:http://127.0.0.1:8080"
        ]))

        let denied = empty.fetchHttp("https://api.example.test/v1")
        let allowed = granted.fetchHttp("https://api.example.test/v1")
        let invalid = granted.fetchHttp("file:///tmp/token")

        @Expect(denied.status, "permission_denied")
        @Expect(allowed.status, "authorized")
        @Expect(allowed.contract, "metis.openclaw-sandbox.v1")
        @Expect(invalid.status, "invalid_request")
    }
}
