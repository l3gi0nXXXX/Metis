package metis.program

import std.unittest.testmacro.*

@Test
public class CliLocalFlowsAgentTeamTest {
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
        @Expect(help.contains("Telegram/Feishu IM are runtime entry points"), true)
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
