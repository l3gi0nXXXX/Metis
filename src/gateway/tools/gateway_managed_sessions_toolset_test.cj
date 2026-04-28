package metis.gateway.tools

import metis.core.{GatewayToolRuntimeContext, gatewaySubagentCreateRunRecord, gatewaySubagentResolveAgent, gatewaySubagentResolveRunRecord, gatewaySubagentRunRecordString, gatewayWithToolRuntimeContext}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}
import metis.core.memory.memorySessionStoreForGatewayUser
import metis.utils.ShellUtils

import std.env.{getVariable, setVariable}
import std.collection.ArrayList
import std.fs.{Directory, File, Path, exists, remove}
import std.core.Duration
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonValue}

private func withManagedSessionsToolsetTestHome<T>(home: String, block: () -> T): T {
    let actualHome = "${home}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
    try {
        remove(Path(actualHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(actualHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", actualHome)
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            remove(Path(actualHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
    }
}

private func managedSubagentsJson(raw: String): JsonObject {
    JsonValue.fromStr(raw).asObject()
}

private func managedSubagentsSome(v: String): Option<String> {
    Some<String>(v)
}

private func managedSubagentsString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func managedSubagentsInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { v.asInt().getValue() } catch (_: Exception) { 0 }
        case None => 0
    }
}

private func createManagedSubagentsCustomAgentFixture(id: String, background: Bool): Path {
    let agentDir = CliConfig.dotDir.join("agents").join(id)
    Directory.create(agentDir, recursive: true)
    File.writeTo(
        agentDir.join("AGENT.md"),
        (
            "id: ${id}\n" +
            "name: ${id}\n" +
            "description: Phase 9 custom subagent fixture\n" +
            "model: openai/gpt-test\n" +
            "tools: fileRead,grepSearch\n" +
            "background: ${background}\n" +
            "isolation: shared\n" +
            "maxTurns: 7\n" +
            "---\n" +
            "# Fixture Instructions\n" +
            "Always answer as the phase 9 custom fixture.\n"
        ).toArray()
    )
    CliConfig.invalidatePathCache()
    agentDir
}

private func managedSubagentsRunGit(repo: Path, args: Array<String>): Bool {
    let command = ArrayList<String>()
    command.add("git")
    for (arg in args) {
        command.add(arg)
    }
    let result = ShellUtils.execute(command.toArray(), timeout: Some(Duration.second * 30), workDir: Some(repo), withWrap: false)
    result[0] == 0
}

private func createManagedSubagentsGitRepo(name: String): Path {
    let repo = CliConfig.dotDir.join(name)
    Directory.create(repo, recursive: true)
    File.writeTo(repo.join("README.md"), "# phase 11\n".toArray())
    @Expect(managedSubagentsRunGit(repo, ["init"]), true)
    @Expect(managedSubagentsRunGit(repo, ["config", "user.email", "metis-test@example.invalid"]), true)
    @Expect(managedSubagentsRunGit(repo, ["config", "user.name", "Metis Test"]), true)
    @Expect(managedSubagentsRunGit(repo, ["add", "README.md"]), true)
    @Expect(managedSubagentsRunGit(repo, ["commit", "-m", "init"]), true)
    repo
}

@Test
public class GatewayManagedSessionsToolsetTest {
    @TestCase
    public func subagentsListStatusAndLogsReturnRunStoreData(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-list-status-logs") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "child-session-a"
            store.appendTranscriptEntry(sessionKey, "assistant", "analysis ready")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                parentSessionKey: "cli:main",
                requesterSessionKey: "cli:main",
                agentId: "explorer",
                runtime: "subagent",
                status: "running",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:main")) {
                let listed = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("list"), managedSubagentsSome("agent:explorer"), None<String>, None<Int64>))
                @Expect(managedSubagentsString(listed, "action"), "list")
                @Expect(managedSubagentsString(listed, "filter"), "agent:explorer")
                @Expect(listed.get("sessions").getOrThrow().asArray().size(), 1)
                @Expect(managedSubagentsString(listed.get("sessions").getOrThrow().asArray()[0].asObject(), "runId"), runId)

                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(status, "action"), "status")
                @Expect(managedSubagentsString(status, "runId"), runId)
                @Expect(status.get("run").getOrThrow().asObject().get("runId").getOrThrow().asString().getValue(), runId)

                let logs = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("logs"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(logs, "action"), "logs")
                @Expect(managedSubagentsString(logs, "logs").contains("analysis ready"), true)
                @Expect(managedSubagentsString(logs, "transcriptPath").isEmpty(), false)
            }
        }
    }

    @TestCase
    public func subagentsKillCancelsStaleNonTerminalRunWithoutDeletingTranscript(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-kill-running") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "child-session-kill"
            store.appendTranscriptEntry(sessionKey, "assistant", "work in progress")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                requesterSessionKey: "cli:main",
                agentId: "reviewer",
                status: "running",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:main")) {
                let killed = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("kill"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(killed, "status"), "cancelled")
                @Expect(killed.get("deleted").getOrThrow().asBool().getValue(), false)
                @Expect(exists(store.transcriptPath(sessionKey)), true)
                match (gatewaySubagentResolveRunRecord(store.sessionsRoot(), runId)) {
                    case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "status"), "cancelled")
                    case None => @Expect("missing", "record")
                }
            }
        }
    }

    @TestCase
    public func subagentsKillCompletedRunIsIdempotent(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-kill-completed") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "child-session-completed"
            store.appendTranscriptEntry(sessionKey, "assistant", "done")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                requesterSessionKey: "cli:main",
                agentId: "planner",
                status: "succeeded",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:main")) {
                let killed = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("kill"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(killed, "status"), "noop")
                @Expect(killed.get("deleted").getOrThrow().asBool().getValue(), false)
                match (gatewaySubagentResolveRunRecord(store.sessionsRoot(), runId)) {
                    case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "status"), "succeeded")
                    case None => @Expect("missing", "record")
                }
            }
        }
    }

    @TestCase
    public func subagentsStatusDeniesDifferentRequesterSessionOnChannelSurface(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-scope-deny") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                "child-session-owned",
                requesterSessionKey: "telegram:chat:owner",
                agentId: "explorer",
                status: "running"
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:other")) {
                let denied = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(denied, "status"), "denied")
                @Expect(managedSubagentsString(denied, "action"), "status")
            }
        }
    }

    @TestCase
    public func subagentsCommandSpawnRejectsUnknownAgent(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-command-spawn-record") {
            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:phase7")) {
                let spawned = managedSubagentsJson(gatewayHandleSubagentsCommandLine("/subagents spawn observer \"inspect unicode 任务\"").getOrThrow())
                @Expect(managedSubagentsString(spawned, "status"), "error")
                @Expect(managedSubagentsString(spawned, "agentId"), "observer")
                @Expect(managedSubagentsString(spawned, "error").contains("unknown subagent agent"), true)
            }
        }
    }

    @TestCase
    public func customSubagentResolverReadsAgentMarkdownMetadata(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-custom-resolver") {
            let agentDir = createManagedSubagentsCustomAgentFixture("phase9-custom", false)
            let spec = gatewaySubagentResolveAgent("phase9-custom")
            @Expect(spec.found, true)
            @Expect(spec.source, "custom")
            @Expect(spec.agentId, "phase9-custom")
            @Expect(spec.agentDir, agentDir.toString())
            @Expect(spec.model, "openai/gpt-test")
            @Expect(spec.tools.size, 2)
            @Expect(spec.background, false)
            @Expect(spec.isolation, "shared")
            @Expect(spec.maxTurns, 7)
        }
    }

    @TestCase
    public func sessionsSpawnCustomAgentRequiresPolicyAllow(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-custom-policy-deny") {
            createManagedSubagentsCustomAgentFixture("phase9-custom", false)
            let toolset = GatewayManagedSessionsToolset()
            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:phase9")) {
                let spawned = managedSubagentsJson(toolset.sessionsSpawnForCommand(
                    "inspect unicode 任务",
                    Some("custom"),
                    Some("subagent"),
                    Some("phase9-custom"),
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<Int64>,
                    None<Int64>,
                    None<String>,
                    None<String>,
                    None<Bool>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>
                ))
                @Expect(managedSubagentsString(spawned, "status"), "rejected")
                @Expect(managedSubagentsString(spawned, "reason"), "custom agents disabled")
                @Expect(managedSubagentsString(spawned, "agentId"), "phase9-custom")
            }
        }
    }

    @TestCase
    public func sessionsSpawnCustomAgentRecordsRunWhenPolicyAllows(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-custom-spawn-record") {
            createManagedSubagentsCustomAgentFixture("phase9-custom", false)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()
            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:phase9")) {
                let spawned = managedSubagentsJson(toolset.sessionsSpawnForCommand(
                    "inspect unicode 任务",
                    Some("custom"),
                    Some("subagent"),
                    Some("phase9-custom"),
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<Int64>,
                    None<Int64>,
                    None<String>,
                    None<String>,
                    None<Bool>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>
                ))
                @Expect(managedSubagentsString(spawned, "status"), "accepted")
                @Expect(managedSubagentsString(spawned, "agentId"), "phase9-custom")
                @Expect(managedSubagentsString(spawned, "agentSource"), "custom")
                @Expect(managedSubagentsString(spawned, "model"), "openai/gpt-test")
                @Expect(spawned.get("liveRunStarted").getOrThrow().asBool().getValue(), false)
                let runId = managedSubagentsString(spawned, "runId")
                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(status, "status"), "ok")
                @Expect(managedSubagentsString(status, "runId"), runId)
                let run = status.get("run").getOrThrow().asObject()
                @Expect(managedSubagentsString(run, "status"), "queued")
                @Expect(managedSubagentsString(run, "requesterSessionKey"), "telegram:chat:phase9")
                @Expect(managedSubagentsString(run, "requesterChannel"), "telegram")
                @Expect(managedSubagentsString(run, "agentSource"), "custom")
                let metadata = run.get("metadata").getOrThrow().asObject()
                let agent = metadata.get("agent").getOrThrow().asObject()
                @Expect(managedSubagentsString(agent, "source"), "custom")
                @Expect(managedSubagentsString(agent, "model"), "openai/gpt-test")
            }
        }
    }

    @TestCase
    public func sessionsSpawnStoresRequestedContextModeAndParentThread(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-context-mode") {
            createManagedSubagentsCustomAgentFixture("phase10-custom", false)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            store.appendTranscriptEntry("telegram:chat:phase10:topic:42", "user", "parent context should be available")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:phase10:topic:42")) {
                let spawned = managedSubagentsJson(toolset.sessionsSpawnForCommand(
                    "inspect with parent context",
                    Some("context"),
                    Some("subagent"),
                    Some("phase10-custom"),
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<Int64>,
                    None<Int64>,
                    Some("with-context"),
                    None<String>,
                    None<Bool>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>
                ))
                @Expect(managedSubagentsString(spawned, "status"), "accepted")
                @Expect(managedSubagentsString(spawned, "contextMode"), "with_context")
                let runId = managedSubagentsString(spawned, "runId")
                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(runId), None<String>, None<Int64>))
                let run = status.get("run").getOrThrow().asObject()
                @Expect(managedSubagentsString(run, "contextMode"), "with_context")
                @Expect(managedSubagentsString(run, "parentSessionKey"), "telegram:chat:phase10:topic:42")
                @Expect(managedSubagentsString(run, "requesterThreadId"), "42")
            }
        }
    }

    @TestCase
    public func sessionsSpawnCwdIsolationRecordsSpecifiedWorkspace(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-cwd-isolation") {
            createManagedSubagentsCustomAgentFixture("phase11-cwd", false)
            let workspace = CliConfig.dotDir.join("phase11-workspace")
            Directory.create(workspace, recursive: true)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:phase11")) {
                let spawned = managedSubagentsJson(toolset.sessionsSpawnForCommand(
                    "inspect cwd workspace",
                    Some("cwd"),
                    Some("subagent"),
                    Some("phase11-cwd"),
                    None<String>,
                    None<String>,
                    None<String>,
                    Some(workspace.toString()),
                    None<Int64>,
                    None<Int64>,
                    None<String>,
                    Some("cwd"),
                    None<Bool>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>
                ))
                @Expect(managedSubagentsString(spawned, "status"), "accepted")
                @Expect(managedSubagentsString(spawned, "isolationMode"), "cwd")
                @Expect(managedSubagentsString(spawned, "cwd"), workspace.toString())
                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(managedSubagentsString(spawned, "runId")), None<String>, None<Int64>))
                let run = status.get("run").getOrThrow().asObject()
                @Expect(managedSubagentsString(run, "isolationMode"), "cwd")
                @Expect(managedSubagentsString(run, "cwd"), workspace.toString())
            }
        }
    }

    @TestCase
    public func sessionsSpawnWorktreeIsolationCreatesAndDeletesWorktreeWhenRequested(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-worktree-isolation") {
            createManagedSubagentsCustomAgentFixture("phase11-worktree", false)
            let repo = createManagedSubagentsGitRepo("phase11-source-repo")
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:phase11-worktree")) {
                let spawned = managedSubagentsJson(toolset.sessionsSpawnForCommand(
                    "inspect isolated worktree",
                    Some("worktree"),
                    Some("subagent"),
                    Some("phase11-worktree"),
                    None<String>,
                    None<String>,
                    None<String>,
                    Some(repo.toString()),
                    None<Int64>,
                    None<Int64>,
                    None<String>,
                    Some("worktree"),
                    None<Bool>,
                    None<String>,
                    Some("delete"),
                    None<String>,
                    None<String>
                ))
                @Expect(managedSubagentsString(spawned, "status"), "accepted")
                @Expect(managedSubagentsString(spawned, "isolationMode"), "worktree")
                let worktreePath = managedSubagentsString(spawned, "worktreePath")
                @Expect(worktreePath.isEmpty(), false)
                @Expect(exists(Path(worktreePath)), false)
                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(managedSubagentsString(spawned, "runId")), None<String>, None<Int64>))
                let run = status.get("run").getOrThrow().asObject()
                @Expect(managedSubagentsString(run, "worktreePath"), worktreePath)
                @Expect(managedSubagentsString(run, "cleanupMode"), "delete")
            }
        }
    }

    @TestCase
    public func subagentsCommandErrorsUseStructuredJson(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-command-error") {
            let failed = managedSubagentsJson(gatewayHandleSubagentsCommandLine("/subagents steer subrun_123").getOrThrow())
            @Expect(failed.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(managedSubagentsString(failed, "status"), "error")
            @Expect(managedSubagentsString(failed, "action"), "steer")
            @Expect(managedSubagentsString(failed, "usage").contains("/subagents spawn"), true)
        }
    }

    @TestCase
    public func subagentsCommandHelpReturnsSuccessfulUsageJson(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-command-help") {
            let help = managedSubagentsJson(gatewayHandleSubagentsCommandLine("/subagents help").getOrThrow())
            @Expect(help.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(managedSubagentsString(help, "status"), "ok")
            @Expect(managedSubagentsString(help, "action"), "help")
            @Expect(managedSubagentsString(help, "usage").contains("/subagents spawn"), true)
            @Expect(help.get("examples").getOrThrow().asArray().size() > 0, true)
        }
    }

    @TestCase
    public func sessionsBatchDelegateRecordsMultipleChildRuns(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-batch-success") {
            createManagedSubagentsCustomAgentFixture("phase13-batch", false)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:phase13")) {
                let batch = managedSubagentsJson(toolset.sessionsBatchDelegateForTest(
                    ["inspect first", "inspect second"],
                    Some("phase13-batch"),
                    Some("phase13"),
                    Some(2),
                    None<Int64>
                ))
                @Expect(managedSubagentsString(batch, "status"), "accepted")
                @Expect(managedSubagentsInt(batch, "total"), 2)
                @Expect(managedSubagentsInt(batch, "acceptedCount"), 2)
                @Expect(managedSubagentsString(batch, "summary"), "accepted=2 failed=0 timedOut=0 deferred=0")
                let children = batch.get("children").getOrThrow().asArray()
                @Expect(children.size(), 2)
                let first = children[0].asObject()
                let second = children[1].asObject()
                @Expect(managedSubagentsString(first, "status"), "accepted")
                @Expect(managedSubagentsString(second, "status"), "accepted")
                @Expect(managedSubagentsString(first, "runId").isEmpty(), false)
                @Expect(managedSubagentsString(second, "runId").isEmpty(), false)
                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(managedSubagentsString(first, "runId")), None<String>, None<Int64>))
                @Expect(managedSubagentsString(status, "status"), "ok")
            }
        }
    }

    @TestCase
    public func sessionsBatchDelegateKeepsValidTasksWhenOneFailsValidation(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-batch-partial") {
            createManagedSubagentsCustomAgentFixture("phase13-partial", false)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:phase13-partial")) {
                let batch = managedSubagentsJson(toolset.sessionsBatchDelegateForTest(
                    ["inspect valid", "   "],
                    Some("phase13-partial"),
                    Some("phase13-partial"),
                    Some(2),
                    None<Int64>
                ))
                @Expect(managedSubagentsString(batch, "status"), "partial")
                @Expect(managedSubagentsInt(batch, "acceptedCount"), 1)
                @Expect(managedSubagentsInt(batch, "failedCount"), 1)
                @Expect(managedSubagentsString(batch, "summary"), "accepted=1 failed=1 timedOut=0 deferred=0")
                let children = batch.get("children").getOrThrow().asArray()
                @Expect(children.size(), 2)
                @Expect(managedSubagentsString(children[0].asObject(), "status"), "accepted")
                @Expect(managedSubagentsString(children[1].asObject(), "status"), "error")
            }
        }
    }

    @TestCase
    public func sessionsBatchDelegateCanMarkImmediatePerTaskTimeout(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-batch-timeout") {
            createManagedSubagentsCustomAgentFixture("phase13-timeout", false)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:phase13-timeout")) {
                let batch = managedSubagentsJson(toolset.sessionsBatchDelegateForTest(
                    ["inspect timeout"],
                    Some("phase13-timeout"),
                    Some("phase13-timeout"),
                    Some(1),
                    Some(0)
                ))
                @Expect(managedSubagentsString(batch, "status"), "partial")
                @Expect(managedSubagentsInt(batch, "timedOutCount"), 1)
                let child = batch.get("children").getOrThrow().asArray()[0].asObject()
                @Expect(managedSubagentsString(child, "status"), "timed_out")
                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(managedSubagentsString(child, "runId")), None<String>, None<Int64>))
                let run = status.get("run").getOrThrow().asObject()
                @Expect(managedSubagentsString(run, "status"), "timed_out")
            }
        }
    }

    @TestCase
    public func sessionsBatchDelegateHonorsMaxWorkersWithDeferredRows(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-batch-max-workers") {
            createManagedSubagentsCustomAgentFixture("phase13-workers", false)
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.allowCustomAgents = true
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:phase13-workers")) {
                let batch = managedSubagentsJson(toolset.sessionsBatchDelegateForTest(
                    ["inspect one", "inspect two", "inspect three"],
                    Some("phase13-workers"),
                    Some("phase13-workers"),
                    Some(2),
                    None<Int64>
                ))
                @Expect(managedSubagentsString(batch, "status"), "partial")
                @Expect(managedSubagentsInt(batch, "maxWorkers"), 2)
                @Expect(managedSubagentsInt(batch, "acceptedCount"), 2)
                @Expect(managedSubagentsInt(batch, "deferredCount"), 1)
                let children = batch.get("children").getOrThrow().asArray()
                @Expect(children.size(), 3)
                @Expect(managedSubagentsString(children[0].asObject(), "status"), "accepted")
                @Expect(managedSubagentsString(children[1].asObject(), "status"), "accepted")
                @Expect(managedSubagentsString(children[2].asObject(), "status"), "deferred")
                @Expect(batch.get("runIds").getOrThrow().asArray().size(), 2)
            }
        }
    }
}
