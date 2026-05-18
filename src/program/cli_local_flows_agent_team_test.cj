package metis.program

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

@Test
public class CliLocalFlowsAgentTeamTest {
    @TestCase
    public func semanticGatewayAgentErrorsDoNotPrintRuntimeHint(): Unit {
        @Expect(cliGatewayShouldPrintRuntimeHintForError("Agent \"reviewer\" already exists."), false)
        @Expect(cliGatewayShouldPrintRuntimeHintForError("Agent \"reviewer\" is a builtin agent and cannot be deleted."), false)
        @Expect(cliGatewayShouldPrintRuntimeHintForError("Agent \"manual-reviewer\" not found."), false)
        @Expect(cliGatewayShouldPrintRuntimeHintForError("connection refused"), true)
    }

    @TestCase
    public func buildsAgentAddRpcParamsWithoutShortcutFieldsWhenUnset(): Unit {
        let spec = cliBuildAgentsAddRpcSpec([
            "add",
            "--agent",
            "demo",
            "--name",
            "Demo",
            "--workspace",
            "/tmp/metis-demo",
            "--model",
            "qwen/qwen3.6-plus"
        ]).getOrThrow()

        @Expect(spec.method, "agents.add")
        @Expect(spec.json, false)
        @Expect(spec.params.get("agentId").getOrThrow().asString().getValue(), "demo")
        @Expect(spec.params.get("name").getOrThrow().asString().getValue(), "Demo")
        @Expect(spec.params.get("workspace").getOrThrow().asString().getValue(), "/tmp/metis-demo")
        @Expect(spec.params.get("model").getOrThrow().asString().getValue(), "qwen/qwen3.6-plus")
        @Expect(spec.params.get("bind").isNone(), true)
        @Expect(spec.params.get("channelCredentials").isNone(), true)
        @Expect(spec.params.get("channelOverwrite").isNone(), true)
    }

    @TestCase
    public func buildsAgentAddShortcutCredentialParamsAndBindings(): Unit {
        let spec = cliBuildAgentsAddRpcSpec([
            "add",
            "--agent",
            "demo",
            "--bind",
            "telegram:manual",
            "--bind",
            "feishu:tenant-b",
            "--feishu-account",
            "tenant-a",
            "--feishu",
            "cli:id:secret",
            "--qqbot",
            "1020:secret:tail",
            "--telegram-bot-token",
            "123:ABC",
            "--channel-overwrite",
            "--json"
        ]).getOrThrow()

        @Expect(spec.method, "agents.add")
        @Expect(spec.json, true)
        let binds = spec.params.get("bind").getOrThrow().asArray()
        @Expect(binds.size(), 5)
        @Expect(binds[0].asString().getValue(), "telegram:manual")
        @Expect(binds[1].asString().getValue(), "feishu:tenant-b")
        @Expect(binds[2].asString().getValue(), "feishu:tenant-a")
        @Expect(binds[3].asString().getValue(), "qq:demo")
        @Expect(binds[4].asString().getValue(), "telegram:demo")

        let credentials = spec.params.get("channelCredentials").getOrThrow().asObject()
        let feishu = credentials.get("feishu").getOrThrow().asObject()
        @Expect(feishu.get("accountId").getOrThrow().asString().getValue(), "tenant-a")
        @Expect(feishu.get("appId").getOrThrow().asString().getValue(), "cli")
        @Expect(feishu.get("appSecret").getOrThrow().asString().getValue(), "id:secret")
        let qq = credentials.get("qq").getOrThrow().asObject()
        @Expect(qq.get("accountId").getOrThrow().asString().getValue(), "demo")
        @Expect(qq.get("appId").getOrThrow().asString().getValue(), "1020")
        @Expect(qq.get("appSecret").getOrThrow().asString().getValue(), "secret:tail")
        let telegram = credentials.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("accountId").getOrThrow().asString().getValue(), "demo")
        @Expect(telegram.get("botToken").getOrThrow().asString().getValue(), "123:ABC")
        @Expect(spec.params.get("channelOverwrite").getOrThrow().asBool().getValue(), true)
    }

    @TestCase
    public func rejectsConflictingTelegramShortcutTokens(): Unit {
        let spec = cliBuildAgentsAddRpcSpec([
            "add",
            "--agent",
            "demo",
            "--telegram",
            "123:A",
            "--telegram-bot-token",
            "123:B"
        ])

        @Expect(spec.isNone(), true)
    }

    @TestCase
    public func rendersAgentAddOutputWithRedactedCredentialSummary(): Unit {
        let result = JsonObject()
        result.put("agentId", JsonString("demo"))
        result.put("name", JsonString("Demo"))
        result.put("model", JsonString("qwen/qwen3.6-plus"))
        result.put("workspace", JsonString("/tmp/metis-demo"))
        result.put("agentDir", JsonString("/tmp/metis-demo/.metis/agents/demo"))
        let accounts = JsonArray([])
        let telegram = JsonObject()
        telegram.put("channel", JsonString("telegram"))
        telegram.put("accountId", JsonString("demo"))
        telegram.put("action", JsonString("created"))
        telegram.put("token", JsonString("123:RAW_TOKEN"))
        accounts.add(telegram)
        let feishu = JsonObject()
        feishu.put("channel", JsonString("feishu"))
        feishu.put("accountId", JsonString("tenant-a"))
        feishu.put("action", JsonString("created"))
        feishu.put("appId", JsonString("cli_raw_app"))
        feishu.put("appSecret", JsonString("RAW_FEISHU_SECRET"))
        accounts.add(feishu)
        result.put("channelAccounts", accounts)
        let bindings = JsonObject()
        let added = JsonArray([])
        added.add(JsonString("telegram:demo"))
        added.add(JsonString("feishu:tenant-a"))
        bindings.put("added", added)
        result.put("bindings", bindings)

        let text = cliRenderGatewayAgentAddResult(result, "demo")
        @Expect(text.contains("Added agent: demo"), true)
        @Expect(text.contains("model: qwen/qwen3.6-plus"), true)
        @Expect(text.contains("Configured channel accounts:"), true)
        @Expect(text.contains("token=[redacted]"), true)
        @Expect(text.contains("appId=cli_..."), true)
        @Expect(text.contains("appSecret=[redacted]"), true)
        @Expect(text.contains("Added bindings:"), true)
        @Expect(text.contains("{\""), false)
        @Expect(text.contains("RAW_TOKEN"), false)
        @Expect(text.contains("RAW_FEISHU_SECRET"), false)
    }

    @TestCase
    public func buildsAgentUpdateRpcParamsForModelWithoutDirectConfigWrite(): Unit {
        let spec = cliBuildAgentsUpdateRpcSpec([
            "update",
            "--agent",
            "reviewer",
            "--model",
            "qwen/qwen3.6-plus",
            "--json"
        ]).getOrThrow()

        @Expect(spec.method, "agents.update")
        @Expect(spec.json, true)
        @Expect(spec.params.get("agentId").getOrThrow().asString().getValue(), "reviewer")
        @Expect(spec.params.get("model").getOrThrow().asString().getValue(), "qwen/qwen3.6-plus")
        @Expect(spec.params.get("channelCredentials").isNone(), true)
    }

    @TestCase
    public func rendersAgentUpdateOutputWithoutRawJson(): Unit {
        let result = JsonObject()
        result.put("agentId", JsonString("reviewer"))
        let agent = JsonObject()
        agent.put("id", JsonString("reviewer"))
        agent.put("name", JsonString("Reviewer"))
        agent.put("model", JsonString("qwen/qwen3.6-plus"))
        agent.put("workspace", JsonString("/tmp/reviewer"))
        result.put("agent", agent)
        let refresh = JsonObject()
        refresh.put("ok", JsonBool(true))
        result.put("modelsRefresh", refresh)

        let text = cliRenderGatewayAgentUpdateResult(result, "reviewer")
        @Expect(text.contains("Updated agent: reviewer"), true)
        @Expect(text.contains("model: qwen/qwen3.6-plus"), true)
        @Expect(text.contains("modelsRefresh: ok"), true)
        @Expect(text.contains("{\""), false)
    }

    @TestCase
    public func redactsAgentAddJsonAndGatewayErrorText(): Unit {
        let obj = JsonObject()
        obj.put("botToken", JsonString("123:RAW_TOKEN"))
        obj.put("appSecret", JsonString("RAW_SECRET"))
        obj.put("appId", JsonString("10201234"))
        let json = cliRedactJsonObjectForOutput(obj).toJsonString()
        @Expect(json.contains("RAW_TOKEN"), false)
        @Expect(json.contains("RAW_SECRET"), false)
        @Expect(json.contains("[redacted]"), true)
        @Expect(json.contains("1020..."), true)

        let err = cliRedactTextForOutput("telegram failed token=123:RAW_TOKEN appSecret:RAW_SECRET")
        @Expect(err.contains("RAW_TOKEN"), false)
        @Expect(err.contains("RAW_SECRET"), false)
        @Expect(err.contains("[redacted]"), true)
    }

    @TestCase
    public func buildsCreateTeamRpcParamsFromCliFlags(): Unit {
        let spec = cliBuildAgentsTeamRpcSpec([
            "team",
            "create",
            "--team",
            "content",
            "--name",
            "Content Team",
            "--template",
            "pm-writer-reviewer",
            "--member",
            "writer:writer:Writer",
            "--alias",
            "pm=content-pm",
            "--json"
        ]).getOrThrow()

        @Expect(spec.method, "agents.teams.create")
        @Expect(spec.json, true)
        @Expect(spec.params.get("id").getOrThrow().asString().getValue(), "content")
        @Expect(spec.params.get("displayName").getOrThrow().asString().getValue(), "Content Team")
        @Expect(spec.params.get("template").getOrThrow().asString().getValue(), "pm-writer-reviewer")

        let members = spec.params.get("members").getOrThrow().asArray()
        @Expect(members.size(), 1)
        let member = members[0].asObject()
        @Expect(member.get("agentId").getOrThrow().asString().getValue(), "writer")
        @Expect(member.get("role").getOrThrow().asString().getValue(), "writer")
        @Expect(member.get("displayName").getOrThrow().asString().getValue(), "Writer")

        let aliases = spec.params.get("aliases").getOrThrow().asArray()
        @Expect(aliases.size(), 1)
        let alias = aliases[0].asObject()
        @Expect(alias.get("alias").getOrThrow().asString().getValue(), "pm")
        @Expect(alias.get("agentId").getOrThrow().asString().getValue(), "content-pm")
    }

    @TestCase
    public func buildsUpdateTeamRpcParamsWithMembersAndAliases(): Unit {
        let spec = cliBuildAgentsTeamRpcSpec([
            "team",
            "update",
            "--team",
            "content",
            "--name",
            "Editorial",
            "--member",
            "content-reviewer:reviewer",
            "--alias",
            "review=content-reviewer"
        ]).getOrThrow()

        @Expect(spec.method, "agents.teams.update")
        @Expect(spec.params.get("id").getOrThrow().asString().getValue(), "content")
        @Expect(spec.params.get("displayName").getOrThrow().asString().getValue(), "Editorial")
        @Expect(spec.params.get("members").getOrThrow().asArray().size(), 1)
        @Expect(spec.params.get("aliases").getOrThrow().asArray().size(), 1)
    }

    @TestCase
    public func updateTeamAcceptsBindingOnlyAsMutationField(): Unit {
        let spec = cliBuildAgentsTeamRpcSpec([
            "team",
            "update",
            "--team",
            "content",
            "--binding-json",
            "{\"type\":\"route\",\"agentId\":\"content-writer\",\"match\":{\"channel\":\"telegram\",\"accountId\":\"bot-a\"}}"
        ]).getOrThrow()

        @Expect(spec.method, "agents.teams.update")
        @Expect(spec.params.get("id").getOrThrow().asString().getValue(), "content")
        @Expect(spec.params.get("bindings").getOrThrow().asArray().size(), 1)
        @Expect(cliAgentsTeamHasAnyUpdateField(spec.params), true)
    }

    @TestCase
    public func buildsTeamBindingRpcParamsFromInlineJsonAndLegacyBindFlags(): Unit {
        let spec = cliBuildAgentsTeamRpcSpec([
            "team",
            "create",
            "--team",
            "content",
            "--template",
            "pm-writer-reviewer",
            "--binding-json",
            "{\"type\":\"route\",\"agentId\":\"content-writer\",\"match\":{\"channel\":\"telegram\",\"accountId\":\"bot-a\"}}",
            "--bind",
            "feishu:tenant-a",
            "--json"
        ]).getOrThrow()

        @Expect(spec.method, "agents.teams.create")
        @Expect(spec.json, true)
        let bindings = spec.params.get("bindings").getOrThrow().asArray()
        @Expect(bindings.size(), 2)
        let explicit = bindings[0].asObject()
        @Expect(explicit.get("agentId").getOrThrow().asString().getValue(), "content-writer")
        @Expect(explicit.get("match").getOrThrow().asObject().get("channel").getOrThrow().asString().getValue(), "telegram")
        @Expect(bindings[1].asString().getValue(), "feishu:tenant-a")
    }

    @TestCase
    public func buildsGetAndDeleteTeamRpcParamsWithTeamId(): Unit {
        let getSpec = cliBuildAgentsTeamRpcSpec(["team", "get", "--team", "content"]).getOrThrow()
        let deleteSpec = cliBuildAgentsTeamRpcSpec(["team", "delete", "--team", "content"]).getOrThrow()

        @Expect(getSpec.method, "agents.teams.get")
        @Expect(deleteSpec.method, "agents.teams.delete")
        @Expect(getSpec.params.get("id").getOrThrow().asString().getValue(), "content")
        @Expect(deleteSpec.params.get("id").getOrThrow().asString().getValue(), "content")
    }

    @TestCase
    public func listTeamRpcHasNoRequiredParams(): Unit {
        let spec = cliBuildAgentsTeamRpcSpec(["team", "list", "--json"]).getOrThrow()
        @Expect(spec.method, "agents.teams.list")
        @Expect(spec.json, true)
        @Expect(spec.params.size(), 0)
    }

    @TestCase
    public func teamHelpClarifiesCliGatewayCrudAndImRuntimeBoundary(): Unit {
        let help = cliAgentsTeamProductSemanticsHelpText()
        @Expect(help.contains("Team CRUD is handled by CLI/UI/Gateway RPC"), true)
        @Expect(help.contains("CRUD methods: list|get|create|update|delete"), true)
        @Expect(help.contains("JSON responses include semantics.crudSurface=cli-ui-gateway-rpc"), true)
        @Expect(help.contains("Telegram/Feishu IM are runtime entry points"), true)
        @Expect(help.contains("runtime route/native command only"), true)
        @Expect(help.contains("do not create/update/delete teams"), true)
        @Expect(help.contains("manager is a normal member/defaultAgent"), true)
        @Expect(help.contains("autonomous manager runtime"), true)
    }

    @TestCase
    public func buildsMigrationDryRunRpcParamsFromInlineConfigAndBinding(): Unit {
        let spec = cliBuildAgentsMigrationRpcSpec([
            "migrate",
            "--dry-run",
            "--config-json",
            "{\"agents\":{\"list\":[{\"id\":\"main\",\"default\":true}]}}",
            "--binding-json",
            "{\"type\":\"route\",\"agentId\":\"main\",\"match\":{\"channel\":\"telegram\",\"accountId\":\"bot-a\"}}",
            "--json"
        ]).getOrThrow()

        @Expect(spec.method, "agents.migration.dryRun")
        @Expect(spec.json, true)
        @Expect(spec.params.get("configRoot").getOrThrow().asObject().get("agents").isSome(), true)
        let proposed = spec.params.get("proposedBindings").getOrThrow().asArray()
        @Expect(proposed.size(), 1)
        @Expect(proposed[0].asObject().get("agentId").getOrThrow().asString().getValue(), "main")
    }
}
