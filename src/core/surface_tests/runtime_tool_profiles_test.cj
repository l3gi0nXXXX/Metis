package metis.core.surface_tests

import metis.core.*

import magic.jsonable.*

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}
import std.unittest.testmacro.*

@Test
public class RuntimeToolProfilesTest {
    private func stringArray(values: Array<String>): JsonArray {
        let arr = JsonArray([])
        for (value in values) {
            arr.add(JsonString(value))
        }
        arr
    }

    private func toolPolicy(
        allow!: Array<String> = [],
        alsoAllow!: Array<String> = [],
        deny!: Array<String> = [],
        profile!: String = ""
    ): JsonObject {
        let obj = JsonObject()
        if (allow.size > 0) {
            obj.put("allow", this.stringArray(allow))
        }
        if (alsoAllow.size > 0) {
            obj.put("alsoAllow", this.stringArray(alsoAllow))
        }
        if (deny.size > 0) {
            obj.put("deny", this.stringArray(deny))
        }
        if (!profile.isEmpty()) {
            obj.put("profile", JsonString(profile))
        }
        obj
    }

    private func configWithAgents(defaultTools!: JsonObject = JsonObject(), agentEntries!: JsonArray = JsonArray([])): JsonObject {
        let root = JsonObject()
        let agents = JsonObject()
        if (defaultTools.size() > 0) {
            let defaults = JsonObject()
            defaults.put("tools", defaultTools)
            agents.put("defaults", defaults)
        }
        if (agentEntries.size() > 0) {
            agents.put("list", agentEntries)
        }
        root.put("agents", agents)
        root
    }

    private func agentEntry(id: String, tools!: JsonObject = JsonObject()): JsonObject {
        let entry = JsonObject()
        entry.put("id", JsonString(id))
        if (tools.size() > 0) {
            entry.put("tools", tools)
        }
        entry
    }

    @TestCase
    public func toolListFilteringIsAgentScopedAndInvocationIsRechecked(): Unit {
        let agents = JsonArray([])
        agents.add(this.agentEntry("agent-a", tools: this.toolPolicy(deny: ["shellExecute"])))
        agents.add(this.agentEntry("agent-b"))
        let root = this.configWithAgents(agentEntries: agents)
        let inventory = ["fileRead", "shellExecute", "message"]

        let reportA = resolveRuntimeToolPolicyFromRoot(root, inventory, agentId: "agent-a")
        @Expect(runtimeToolNamesContain(reportA.visibleTools, "shellExecute"), false)
        @Expect(runtimeToolInvocationAllowedFromRoot(root, "shellExecute", inventory, agentId: "agent-a").allowed, false)

        let reportB = resolveRuntimeToolPolicyFromRoot(root, inventory, agentId: "agent-b")
        @Expect(runtimeToolNamesContain(reportB.visibleTools, "shellExecute"), true)
        @Expect(runtimeToolInvocationAllowedFromRoot(root, "shellExecute", inventory, agentId: "agent-b").allowed, true)
    }

    @TestCase
    public func execAliasDenyHidesShellExecuteAndRejectsInvocation(): Unit {
        let agents = JsonArray([])
        agents.add(this.agentEntry("agent-a", tools: this.toolPolicy(deny: ["exec"])))
        let root = this.configWithAgents(agentEntries: agents)
        let inventory = ["fileRead", "shellExecute", "message"]

        let report = resolveRuntimeToolPolicyFromRoot(root, inventory, agentId: "agent-a")
        @Expect(runtimeToolNamesContain(report.visibleTools, "shellExecute"), false)
        @Expect(runtimeToolNamesContain(report.deniedTools, "shellExecute"), true)

        let decision = runtimeToolInvocationAllowedFromRoot(root, "shellExecute", inventory, agentId: "agent-a")
        @Expect(decision.allowed, false)
        @Expect(decision.reason.contains("shellExecute"), true)
    }

    @TestCase
    public func sandboxToolPolicyNarrowsParentScopeAndReportsSource(): Unit {
        let root = JsonObject()
        let tools = this.toolPolicy(allow: ["fileRead", "shellExecute"])
        let sandbox = JsonObject()
        sandbox.put("tools", this.toolPolicy(deny: ["exec"]))
        tools.put("sandbox", sandbox)
        root.put("tools", tools)

        let report = resolveRuntimeToolPolicyFromRoot(root, ["fileRead", "shellExecute"])

        @Expect(runtimeToolNamesContain(report.visibleTools, "fileRead"), true)
        @Expect(runtimeToolNamesContain(report.visibleTools, "shellExecute"), false)
        @Expect(report.policySource.contains("tools.sandbox.tools"), true)
    }

    @TestCase
    public func alsoAllowDoesNotWidenEarlierAllowScope(): Unit {
        let root = JsonObject()
        root.put("tools", this.toolPolicy(allow: ["fileRead"]))
        let gateway = JsonObject()
        gateway.put("tools", this.toolPolicy(alsoAllow: ["shellExecute"], profile: "coding"))
        root.put("gateway", gateway)

        let report = resolveRuntimeToolPolicyFromRoot(root, ["fileRead", "shellExecute", "message"])

        @Expect(runtimeToolNamesContain(report.visibleTools, "fileRead"), true)
        @Expect(runtimeToolNamesContain(report.visibleTools, "shellExecute"), false)
        @Expect(runtimeToolNamesContain(report.visibleTools, "message"), false)
        @Expect(report.policySource.contains("tools"), true)
        @Expect(report.policySource.contains("gateway.tools"), true)
    }

    @TestCase
    public func agentSandboxToolsCannotWidenAgentToolPolicyWithAlsoAllow(): Unit {
        let agents = JsonArray([])
        let agentTools = this.toolPolicy(allow: ["fileRead"])
        let sandbox = JsonObject()
        sandbox.put("tools", this.toolPolicy(alsoAllow: ["shellExecute"], profile: "coding"))
        agentTools.put("sandbox", sandbox)
        agents.add(this.agentEntry("agent-a", tools: agentTools))
        let root = this.configWithAgents(agentEntries: agents)

        let report = resolveRuntimeToolPolicyFromRoot(root, ["fileRead", "shellExecute"], agentId: "agent-a")

        @Expect(runtimeToolNamesContain(report.visibleTools, "fileRead"), true)
        @Expect(runtimeToolNamesContain(report.visibleTools, "shellExecute"), false)
        @Expect(report.policySource.contains("agents.list[agent-a].tools.sandbox.tools"), true)
    }

    @TestCase
    public func allowDenyAlsoAllowAndProviderConflictsAreDiagnosed(): Unit {
        let root = JsonObject()
        root.put("tools", this.toolPolicy(allow: ["fileRead"], alsoAllow: ["message"], deny: ["fileRead"]))
        let byProvider = JsonObject()
        byProvider.put("openai", this.toolPolicy(allow: ["message"], alsoAllow: ["weather"]))
        root.get("tools").getOrThrow().asObject().put("byProvider", byProvider)

        let report = resolveRuntimeToolPolicyFromRoot(root, ["fileRead", "message", "weather"], provider: "openai/gpt-5")

        @Expect(report.diagnostics.size >= 3, true)
        @Expect(runtimeToolDiagnosticsContain(report, "allow and alsoAllow"), true)
        @Expect(runtimeToolDiagnosticsContain(report, "deny wins"), true)
        @Expect(runtimeToolDiagnosticsContain(report, "tools.byProvider[openai]"), true)
    }

    @TestCase
    public func unknownAgentFallsBackToDefaultsWithoutWideningTools(): Unit {
        let root = this.configWithAgents(defaultTools: this.toolPolicy(allow: ["fileRead"]))
        let report = resolveRuntimeToolPolicyFromRoot(root, ["fileRead", "shellExecute"], agentId: "missing-agent")

        @Expect(runtimeToolNamesContain(report.visibleTools, "fileRead"), true)
        @Expect(runtimeToolNamesContain(report.visibleTools, "shellExecute"), false)
        @Expect(report.policySource.contains("agents.defaults.tools"), true)
    }

    @TestCase
    public func subagentBoundaryCannotBypassParentToolDenyOrRequireAgentId(): Unit {
        let parent = resolveRuntimeToolPolicyFromRoot(
            this.configWithAgents(defaultTools: this.toolPolicy(deny: ["shellExecute"])),
            ["fileRead", "shellExecute"]
        )

        let missingAgentId = runtimeSubagentBoundaryDecision(
            parent,
            requestedAgentId: "",
            requireAgentId: true,
            allowAgents: ["reviewer"],
            requestedTools: ["shellExecute"]
        )
        @Expect(missingAgentId.allowed, false)
        @Expect(missingAgentId.reason.contains("agent id required"), true)

        let forgedExec = runtimeSubagentBoundaryDecision(
            parent,
            requestedAgentId: "reviewer",
            requireAgentId: true,
            allowAgents: ["reviewer"],
            requestedTools: ["shellExecute"]
        )
        @Expect(forgedExec.allowed, false)
        @Expect(forgedExec.reason.contains("parent tool policy denied"), true)
    }

    @TestCase
    public func elevatedPolicyIsExplainedAsGlobalSenderBasedBoundary(): Unit {
        let report = resolveRuntimeToolPolicyFromRoot(JsonObject(), ["shellExecute"], agentId: "agent-a")

        @Expect(report.elevatedExplanation.contains("global sender-based"), true)
        @Expect(report.elevatedExplanation.contains("agent-a"), false)
    }
}
