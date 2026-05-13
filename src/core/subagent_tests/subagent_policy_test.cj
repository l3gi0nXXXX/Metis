package metis.core.subagent_tests

import metis.core.*

import metis.core.config.GatewaySubagentPolicyUserSettings

import std.fs.{Directory, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*

@Test
public class SubagentPolicyTest {
    private func tempSessionsRoot(label: String): Path {
        let root = Path("/tmp/metis-subagent-policy-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        if (exists(root)) {
            remove(root, recursive: true)
        }
        Directory.create(root, recursive: true)
        root.join("agents").join("main").join("sessions")
    }

    private func evaluate(
        settings: GatewaySubagentPolicyUserSettings,
        sessionsRoot: Path,
        requesterSessionKey!: String = "",
        agentId!: String = "reviewer",
        agentSource!: String = "builtin",
        runtime!: String = "subagent",
        requestedTimeoutSeconds!: Int64 = -1,
        currentDepth!: Int64 = 0,
        requestedIsolationMode!: String = "shared"
    ): SubagentPolicyDecision {
        gatewaySubagentEvaluateSpawnPolicy(
            settings,
            sessionsRoot,
            requesterSessionKey,
            agentId,
            agentSource,
            runtime,
            requestedTimeoutSeconds,
            currentDepth,
            requestedIsolationMode
        )
    }

    @TestCase
    public func defaultPolicyAllowsSpawnAndAppliesDefaultTimeout(): Unit {
        let sessionsRoot = this.tempSessionsRoot("default")
        let settings = GatewaySubagentPolicyUserSettings()

        let decision = this.evaluate(settings, sessionsRoot)

        @Expect(decision.allowed, true)
        @Expect(decision.effectiveTimeoutSeconds, 600)
        @Expect(decision.timeoutClamped, false)
    }

    @TestCase
    public func disabledPolicyRejectsBeforeSpawn(): Unit {
        let sessionsRoot = this.tempSessionsRoot("disabled")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.enabled = false

        let decision = this.evaluate(settings, sessionsRoot)

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "subagents disabled")
    }

    @TestCase
    public func denyListTakesPrecedenceOverAllowList(): Unit {
        let sessionsRoot = this.tempSessionsRoot("deny")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.allowAgents = ["reviewer"]
        settings.denyAgents = ["reviewer"]

        let decision = this.evaluate(settings, sessionsRoot, agentId: "reviewer")

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "agent denied: reviewer")
    }

    @TestCase
    public func allowListRejectsUnlistedAgent(): Unit {
        let sessionsRoot = this.tempSessionsRoot("allow")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.allowAgents = ["reviewer"]

        let decision = this.evaluate(settings, sessionsRoot, agentId: "planner")

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "agent not allowed: planner")
    }

    @TestCase
    public func maxConcurrentSubagentsRejectsWhenActiveLimitReached(): Unit {
        let sessionsRoot = this.tempSessionsRoot("concurrent")
        Directory.create(sessionsRoot, recursive: true)
        let _ = gatewaySubagentCreateRunRecord(sessionsRoot, "child-1", status: "running")
        let _ = gatewaySubagentCreateRunRecord(sessionsRoot, "child-2", status: "queued")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.maxConcurrentSubagents = 2

        let decision = this.evaluate(settings, sessionsRoot)

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "max concurrent subagents exceeded")
    }

    @TestCase
    public func maxConcurrentSubagentsCanUseEffectiveActiveRunCountOverride(): Unit {
        let sessionsRoot = this.tempSessionsRoot("concurrent-effective")
        Directory.create(sessionsRoot, recursive: true)
        let _ = gatewaySubagentCreateRunRecord(sessionsRoot, "child-stale-1", status: "running")
        let _ = gatewaySubagentCreateRunRecord(sessionsRoot, "child-stale-2", status: "queued")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.maxConcurrentSubagents = 1

        let allowed = gatewaySubagentEvaluateSpawnPolicy(
            settings,
            sessionsRoot,
            "",
            "reviewer",
            "builtin",
            "subagent",
            -1,
            0,
            "shared",
            activeRunCountOverride: 0,
            staleRunCountOverride: 2
        )
        @Expect(allowed.allowed, true)
        @Expect(allowed.activeRunCount, 0)
        @Expect(allowed.staleRunCount, 2)

        let rejected = gatewaySubagentEvaluateSpawnPolicy(
            settings,
            sessionsRoot,
            "",
            "reviewer",
            "builtin",
            "subagent",
            -1,
            0,
            "shared",
            activeRunCountOverride: 1,
            staleRunCountOverride: 2
        )
        @Expect(rejected.allowed, false)
        @Expect(rejected.reason, "max concurrent subagents exceeded")
        @Expect(rejected.activeRunCount, 1)
        @Expect(rejected.staleRunCount, 2)
    }

    @TestCase
    public func maxChildrenPerSessionRejectsWhenRequesterLimitReached(): Unit {
        let sessionsRoot = this.tempSessionsRoot("children")
        Directory.create(sessionsRoot, recursive: true)
        let _ = gatewaySubagentCreateRunRecord(
            sessionsRoot,
            "child-1",
            requesterSessionKey: "main-session",
            status: "succeeded"
        )
        var settings = GatewaySubagentPolicyUserSettings()
        settings.maxChildrenPerSession = 1

        let decision = this.evaluate(settings, sessionsRoot, requesterSessionKey: "main-session")

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "max children per session exceeded")
    }

    @TestCase
    public func maxSpawnDepthRejectsNestedSpawnBeyondLimit(): Unit {
        let sessionsRoot = this.tempSessionsRoot("depth")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.maxSpawnDepth = 1

        let decision = this.evaluate(settings, sessionsRoot, currentDepth: 1)

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "max spawn depth exceeded")
    }

    @TestCase
    public func timeoutIsClampedToPolicyMaximum(): Unit {
        let sessionsRoot = this.tempSessionsRoot("timeout")
        let settings = GatewaySubagentPolicyUserSettings()

        let decision = this.evaluate(settings, sessionsRoot, requestedTimeoutSeconds: 9999)

        @Expect(decision.allowed, true)
        @Expect(decision.effectiveTimeoutSeconds, 1800)
        @Expect(decision.timeoutClamped, true)
    }

    @TestCase
    public func childToolPolicyIsCarriedInDecision(): Unit {
        let sessionsRoot = this.tempSessionsRoot("tools")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.childAllowedTools = ["read", "sessions_status"]
        settings.childDeniedTools = ["shell"]

        let decision = this.evaluate(settings, sessionsRoot)

        @Expect(decision.allowed, true)
        @Expect(decision.childAllowedTools.size, 2)
        @Expect(decision.childDeniedTools.size, 1)
    }

    @TestCase
    public func writeCapableAgentRequiresExplicitPermission(): Unit {
        let sessionsRoot = this.tempSessionsRoot("write")
        let settings = GatewaySubagentPolicyUserSettings()

        let decision = this.evaluate(settings, sessionsRoot, agentId: "editor")

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "write-capable agents disabled: editor")
    }

    @TestCase
    public func readonlyBuiltinAgentRunsUnderDefaultPolicy(): Unit {
        let sessionsRoot = this.tempSessionsRoot("readonly")
        let settings = GatewaySubagentPolicyUserSettings()

        let decision = this.evaluate(settings, sessionsRoot, agentId: "reviewer")

        @Expect(decision.allowed, true)
        @Expect(decision.reason, "allowed")
    }

    @TestCase
    public func writeBuiltinAgentRequiresWorktreeWhenWriteAgentsAllowed(): Unit {
        let sessionsRoot = this.tempSessionsRoot("write-worktree")
        var settings = GatewaySubagentPolicyUserSettings()
        settings.allowWriteAgents = true

        let denied = this.evaluate(settings, sessionsRoot, agentId: "test_generator", requestedIsolationMode: "shared")
        @Expect(denied.allowed, false)
        @Expect(denied.reason, "write-capable agents require worktree isolation")

        let allowed = this.evaluate(settings, sessionsRoot, agentId: "test_generator", requestedIsolationMode: "worktree")
        @Expect(allowed.allowed, true)
        @Expect(allowed.reason, "allowed")
    }

    @TestCase
    public func customAgentRequiresExplicitPermission(): Unit {
        let sessionsRoot = this.tempSessionsRoot("custom")
        let settings = GatewaySubagentPolicyUserSettings()

        let decision = this.evaluate(settings, sessionsRoot, agentId: "custom-reviewer", agentSource: "custom")

        @Expect(decision.allowed, false)
        @Expect(decision.reason, "custom agents disabled")
    }
}
