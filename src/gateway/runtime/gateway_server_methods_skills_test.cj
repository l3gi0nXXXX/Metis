package metis.gateway.runtime

import metis.core.config.{MetisConfigManager, CliConfig, CliSettingManager}
import metis.core.skills.{SkillsPrompt, clawHubSkillsLockfilePath, setClawHubArchiveRootForTest, setClawHubHttpGetForTest}
import metis.gateway.config.buildGatewayConfigFromUserSettings

import magic.jsonable.*
import std.collection.HashMap
import std.fs.{Directory, File, Path, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewaySkillsTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayServerMethodsSkillsTest {
    private func clearTestState(skillDir: Path): Unit {
        SkillsPrompt.invalidate()
        setClawHubHttpGetForTest(None)
        setClawHubArchiveRootForTest(None)
        let _ = MetisConfigManager.setSkillsEntries(None)
        if (exists(skillDir)) {
            remove(skillDir, recursive: true)
        }
        let lockPath = clawHubSkillsLockfilePath(CliConfig.cwd)
        if (exists(lockPath)) {
            remove(lockPath)
        }
        let dotDir = CliConfig.cwd.join(".clawhub")
        if (exists(dotDir)) {
            remove(dotDir, recursive: true)
        }
    }

    @TestCase
    public func skillsStatusReportsEligibleWorkspaceSkill(): Unit {
        let slug = "gateway-skills-status-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                "---\nname: ${slug}\ndescription: gateway skill status\n---\n# ${slug}\n".toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(gatewaySkillsTestString(result, "workspaceDir"), CliConfig.cwd.join("skills").toString())
            @Expect(result.get("nodePolicy").isSome(), true)
            @Expect(result.get("devicePolicy").isSome(), true)
            @Expect(result.get("readiness").isSome(), true)
            @Expect(result.get("installRisk").isSome(), true)
            let rows = result.get("skills").getOrThrow().asArray()
            @Expect(rows.size() > 0, true)

            let dashboard = handleGatewayDashboardFamily("dashboard.skills", GatewayRpcRequest("dashboard.skills")).getOrThrow()
            @Expect(dashboard.ok, true)
            let dashboardRows = dashboard.result.asObject().get("skills").getOrThrow().asArray()
            @Expect(dashboardRows.size() > 0, true)

            let ws = gatewayControlUiWsCompatResponse("skills.status", JsonObject(), buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())).getOrThrow()
            let wsRows = ws.result.asObject().get("skills").getOrThrow().asArray()
            @Expect(wsRows.size() > 0, true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusExposesLegacyMetadataFields(): Unit {
        let slug = "gateway-skills-metadata-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill status metadata\n" +
                    "user-invocable: false\n" +
                    "disable-model-invocation: true\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"metadata-skill-key\",\"primaryEnv\":\"META_KEY\",\"always\":true,\"os\":[\"darwin\"],\"requires\":{\"env\":[\"REQ_ENV\"],\"bins\":[\"curl\"],\"anyBins\":[\"git\"],\"config\":[\"browser.enabled\"]},\"install\":[{\"id\":\"brew\",\"kind\":\"brew\",\"formula\":\"gh\",\"bins\":[\"gh\"]}]}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(result.get("hostEligibleCount").getOrThrow().asInt().getValue() >= 1, true)
            @Expect(result.get("sandboxEligibleCount").getOrThrow().asInt().getValue(), 0)
            let rows = result.get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                @Expect(gatewaySkillsTestString(row, "skillKey"), "metadata-skill-key")
                @Expect(gatewaySkillsTestString(row, "primaryEnv"), "META_KEY")
                @Expect(row.get("always").getOrThrow().asBool().getValue(), true)
                let osList = row.get("os").getOrThrow().asArray()
                @Expect(osList.size(), 1)
                @Expect(row.get("userInvocable").getOrThrow().asBool().getValue(), false)
                @Expect(row.get("disableModelInvocation").getOrThrow().asBool().getValue(), true)
                let requiredConfig = row.get("requiredConfig").getOrThrow().asArray()
                @Expect(requiredConfig.size(), 1)
                let requirements = row.get("requirements").getOrThrow().asObject()
                @Expect(requirements.get("config").getOrThrow().asArray().size(), 1)
                let configChecks = row.get("configChecks").getOrThrow().asArray()
                @Expect(configChecks.size(), 1)
                let install = row.get("install").getOrThrow().asArray()
                @Expect(install.size(), 1)
                let install0 = install[0].asObject()
                @Expect(gatewaySkillsTestString(install0, "id"), "brew")
                @Expect(gatewaySkillsTestString(install0, "kind"), "brew")
                let installRisk = row.get("installRisk").getOrThrow().asObject()
                @Expect(gatewaySkillsTestString(installRisk, "level"), "safe")
                let missing = row.get("missing").getOrThrow().asObject()
                let missingEnv = missing.get("env").getOrThrow().asArray()
                @Expect(missingEnv.size(), 1)
                let missingConfig = missing.get("config").getOrThrow().asArray()
                @Expect(missingConfig.size(), 1)
                let missingOs = missing.get("os").getOrThrow().asArray()
                @Expect(missingOs.size(), 0)
                @Expect(row.get("eligible").getOrThrow().asBool().getValue(), true)
                @Expect(row.get("hostEligible").getOrThrow().asBool().getValue(), true)
                @Expect(gatewaySkillsTestString(row, "readiness"), "ready")
                let sandbox = row.get("sandbox").getOrThrow().asObject()
                @Expect(sandbox.get("configured").getOrThrow().asBool().getValue(), false)
                @Expect(sandbox.get("eligible").getOrThrow().asBool().getValue(), false)
                @Expect(gatewaySkillsTestString(sandbox, "profile"), "workspace-write")
                @Expect(gatewaySkillsTestString(sandbox, "entrypoint"), "metis --sandbox --prompt \"...\"")
                @Expect(gatewaySkillsTestString(sandbox, "workspaceAccess"), "workspace-write")
                @Expect(gatewaySkillsTestString(sandbox, "reason"), "sandbox-runtime-unconfigured")
                let doctorActions = row.get("doctorActions").getOrThrow().asArray()
                @Expect(doctorActions.size(), 0)
                break
            }
            @Expect(found, true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusTreatsConfiguredEnvAndApiKeyAsSatisfiedRequirements(): Unit {
        let slug = "gateway-skills-configured-env-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill configured env\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"configured-env-key\",\"primaryEnv\":\"PRIMARY_SECRET\",\"requires\":{\"env\":[\"PRIMARY_SECRET\",\"CUSTOM_ENV\"]}}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("apiKey", JsonString("resolved-secret"))
            let envObj = JsonObject()
            envObj.put("CUSTOM_ENV", JsonString("configured"))
            entry.put("env", envObj)
            entries.put("configured-env-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let rows = response.result.asObject().get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                @Expect(gatewaySkillsTestString(row, "configuredApiKey"), "resolved-secret")
                @Expect(row.get("configuredEnv").isSome(), true)
                let missing = row.get("missing").getOrThrow().asObject()
                @Expect(missing.get("env").getOrThrow().asArray().size(), 0)
                @Expect(row.get("eligible").getOrThrow().asBool().getValue(), true)
                @Expect(gatewaySkillsTestString(row, "readiness"), "ready")
                break
            }
            @Expect(found, true)
        } finally {
            let _ = MetisConfigManager.setSkillsEntries(None)
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusMarksBlockedByAllowlistForAgentScopedVisibility(): Unit {
        let allowedSlug = "gateway-allowed-skill"
        let blockedSlug = "gateway-blocked-skill"
        let allowedDir = CliConfig.cwd.join("skills").join(allowedSlug)
        let blockedDir = CliConfig.cwd.join("skills").join(blockedSlug)
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject(HashMap<String, JsonValue>())
        try {
            clearTestState(allowedDir)
            clearTestState(blockedDir)
            Directory.create(allowedDir, recursive: true)
            Directory.create(blockedDir, recursive: true)
            File.writeTo(
                allowedDir.join("SKILL.md"),
                "---\nname: ${allowedSlug}\ndescription: allowed\n---\n# ${allowedSlug}\n".toArray()
            )
            File.writeTo(
                blockedDir.join("SKILL.md"),
                "---\nname: ${blockedSlug}\ndescription: blocked\n---\n# ${blockedSlug}\n".toArray()
            )
            SkillsPrompt.invalidate()

            let root = JsonObject(HashMap<String, JsonValue>())
            let agents = match (root.get("agents")) {
                case Some(value) => try { value.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
            let list = JsonArray([])
            let agent = JsonObject()
            agent.put("id", JsonString("reviewer"))
            agent.put("skills", JsonArray([JsonString(allowedSlug)]))
            list.add(agent)
            agents.put("list", list)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)
            SkillsPrompt.invalidate()

            let params = JsonObject()
            params.put("agentId", JsonString("reviewer"))
            let response = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(result.get("blockedByAllowlistCount").getOrThrow().asInt().getValue() >= 1, true)
            let rows = result.get("skills").getOrThrow().asArray()
            var foundBlocked = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != blockedSlug) {
                    continue
                }
                foundBlocked = true
                @Expect(row.get("blockedByAllowlist").getOrThrow().asBool().getValue(), true)
                @Expect(row.get("eligible").getOrThrow().asBool().getValue(), false)
                @Expect(gatewaySkillsTestString(row, "readiness"), "blocked-by-allowlist")
                break
            }
            @Expect(foundBlocked, true)
        } finally {
            MetisConfigManager.writeRoot(originalRoot)
            clearTestState(allowedDir)
            clearTestState(blockedDir)
        }
    }

    @TestCase
    public func skillsStatusTreatsBrowserConfigAsTruthyByDefault(): Unit {
        let slug = "gateway-skills-default-config-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject(HashMap<String, JsonValue>())
        try {
            clearTestState(skillDir)
            MetisConfigManager.writeRoot(JsonObject(HashMap<String, JsonValue>()))
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill config defaults\n" +
                    "metadata: {\"metis\":{\"requires\":{\"config\":[\"browser.enabled\",\"browser.evaluateEnabled\"]}}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let rows = response.result.asObject().get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                let missing = row.get("missing").getOrThrow().asObject()
                @Expect(missing.get("config").getOrThrow().asArray().size(), 0)
                let checks = row.get("configChecks").getOrThrow().asArray()
                @Expect(checks.size(), 2)
                @Expect(row.get("eligible").getOrThrow().asBool().getValue(), true)
                @Expect(gatewaySkillsTestString(row, "readiness"), "ready")
                break
            }
            @Expect(found, true)
        } finally {
            MetisConfigManager.writeRoot(originalRoot)
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusRespectsOsEligibilityWhenAlwaysIsFalse(): Unit {
        let slug = "gateway-skills-os-gating-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill os gating\n" +
                    "metadata: {\"metis\":{\"os\":[\"win32\"]}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let rows = response.result.asObject().get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                @Expect(row.get("eligible").getOrThrow().asBool().getValue(), false)
                @Expect(gatewaySkillsTestString(row, "readiness"), "missing-requirements")
                let missing = row.get("missing").getOrThrow().asObject()
                let missingOs = missing.get("os").getOrThrow().asArray()
                @Expect(missingOs.size(), 1)
                let doctorActions = row.get("doctorActions").getOrThrow().asArray()
                @Expect(doctorActions.size(), 0)
                break
            }
            @Expect(found, true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusExposesDoctorActionsForMissingRequirements(): Unit {
        let slug = "gateway-skills-doctor-actions-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill doctor actions\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"doctor-actions-key\",\"primaryEnv\":\"PRIMARY_SECRET\",\"requires\":{\"env\":[\"PRIMARY_SECRET\"],\"config\":[\"channels.discord.token\"]}}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let rows = response.result.asObject().get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                @Expect(gatewaySkillsTestString(row, "readiness"), "missing-requirements")
                let doctorActions = row.get("doctorActions").getOrThrow().asArray()
                @Expect(doctorActions.size() >= 2, true)
                @Expect(doctorActions[0].asObject().get("message").getOrThrow().asString().getValue(), "Configure skills.entries.doctor-actions-key.env.PRIMARY_SECRET or provide shell env PRIMARY_SECRET")
                break
            }
            @Expect(found, true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusPrefersConfiguredNodeInstallerAndSinglePreferredOption(): Unit {
        let slug = "gateway-skills-install-preference-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject(HashMap<String, JsonValue>())
        try {
            clearTestState(skillDir)
            let root = JsonObject(HashMap<String, JsonValue>())
            let skills = JsonObject()
            let install = JsonObject()
            install.put("preferBrew", false.toJsonValue())
            install.put("nodeManager", JsonString("pnpm"))
            skills.put("install", install)
            root.put("skills", skills)
            MetisConfigManager.writeRoot(root)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill install preference\n" +
                    "metadata: {\"metis\":{\"install\":[{\"id\":\"brew\",\"kind\":\"brew\",\"formula\":\"gh\",\"bins\":[\"gh\"]},{\"id\":\"node\",\"kind\":\"node\",\"package\":\"@scope/tool\",\"bins\":[\"tool\"]}]}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let rows = response.result.asObject().get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                let installOptions = row.get("install").getOrThrow().asArray()
                @Expect(installOptions.size(), 1)
                let install0 = installOptions[0].asObject()
                @Expect(gatewaySkillsTestString(install0, "kind"), "node")
                @Expect(gatewaySkillsTestString(install0, "label"), "Install @scope/tool (pnpm)")
                let installRisk = row.get("installRisk").getOrThrow().asObject()
                @Expect(gatewaySkillsTestString(installRisk, "level"), "caution")
                break
            }
            @Expect(found, true)
        } finally {
            MetisConfigManager.writeRoot(originalRoot)
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsBinsAggregatesWorkspaceSkillBinaries(): Unit {
        let slug = "gateway-skills-bins-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                "---\nname: ${slug}\ndescription: gateway skill bins\n---\nbinaries: curl, git\n".toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.bins").getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            let bins = result.get("bins").getOrThrow().asArray()
            @Expect(bins.size() >= 2, true)
            let hostBins = result.get("hostBins").getOrThrow().asArray()
            @Expect(hostBins.size() >= 2, true)
            let sandbox = result.get("sandbox").getOrThrow().asObject()
            @Expect(sandbox.get("configured").getOrThrow().asBool().getValue(), false)
            @Expect(sandbox.get("eligible").getOrThrow().asBool().getValue(), false)
            @Expect(gatewaySkillsTestString(sandbox, "profile"), "workspace-write")
            @Expect(gatewaySkillsTestString(sandbox, "entrypoint"), "metis --sandbox --prompt \"...\"")
            @Expect(gatewaySkillsTestString(sandbox, "reason"), "sandbox-runtime-unconfigured")
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsStatusMarksDirectDownloadInstallerAsWarnRisk(): Unit {
        let slug = "gateway-skills-download-risk-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: gateway skill download risk\n" +
                    "metadata: {\"metis\":{\"install\":[{\"id\":\"download\",\"kind\":\"download\",\"url\":\"https://example.com/tool.zip\"}]}}\n" +
                    "---\n# ${slug}\n").toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.status").getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            let installRiskSummary = result.get("installRisk").getOrThrow().asObject()
            @Expect(installRiskSummary.get("warnCount").getOrThrow().asInt().getValue() >= 1, true)
            let rows = result.get("skills").getOrThrow().asArray()
            var found = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (gatewaySkillsTestString(row, "name") != slug) {
                    continue
                }
                found = true
                let installRisk = row.get("installRisk").getOrThrow().asObject()
                @Expect(gatewaySkillsTestString(installRisk, "level"), "warn")
                @Expect(gatewaySkillsTestString(installRisk, "kind"), "download")
                let doctorActions = row.get("doctorActions").getOrThrow().asArray()
                @Expect(doctorActions.size() >= 1, true)
                break
            }
            @Expect(found, true)
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsSearchUsesNativeClawHubResultShape(): Unit {
        try {
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"results\":[{\"slug\":\"weather\",\"displayName\":\"Weather\",\"summary\":\"forecast\",\"version\":\"1.2.3\"}]}"
            }))
            let params = JsonObject()
            params.put("query", JsonString("weather"))
            let response = handleGatewaySkillsFamily("skills.search", request: Some(GatewayRpcRequest("skills.search", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let results = response.result.asObject().get("results").getOrThrow().asArray()
            @Expect(results.size(), 1)
        } finally {
            setClawHubHttpGetForTest(None)
        }
    }

    @TestCase
    public func skillsDetailFetchesClawHubJson(): Unit {
        try {
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"weather\",\"displayName\":\"Weather\"},\"latestVersion\":{\"version\":\"1.2.3\"}}"
            }))
            let params = JsonObject()
            params.put("slug", JsonString("weather"))
            let response = handleGatewaySkillsFamily("skills.detail", request: Some(GatewayRpcRequest("skills.detail", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            let skill = result.get("skill").getOrThrow().asObject()
            @Expect(gatewaySkillsTestString(skill, "slug"), "weather")
        } finally {
            setClawHubHttpGetForTest(None)
        }
    }

    @TestCase
    public func skillsCompatibilityMatrixIsExposedThroughGatewayFamily(): Unit {
        let slug = "gateway-skills-compatibility-matrix-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearTestState(skillDir)
            Directory.create(skillDir, recursive: true)
            File.writeTo(
                skillDir.join("SKILL.md"),
                "---\nname: ${slug}\ndescription: compatibility matrix gateway skill\n---\n# ${slug}\n".toArray()
            )
            SkillsPrompt.invalidate()

            let response = handleGatewaySkillsFamily("skills.compatibilityMatrix").getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(gatewaySkillsTestString(result, "kind"), "skills-compatibility-matrix")
            @Expect(result.get("rows").isSome(), true)

            let dashboard = handleGatewayDashboardFamily("dashboard.skills.compatibility", GatewayRpcRequest("dashboard.skills.compatibility")).getOrThrow()
            @Expect(dashboard.ok, true)
            let dashboardResult = dashboard.result.asObject()
            @Expect(gatewaySkillsTestString(dashboardResult, "kind"), "skills-compatibility-matrix")
        } finally {
            clearTestState(skillDir)
        }
    }

    @TestCase
    public func skillsInstallUsesNativeClawHubTransport(): Unit {
        let slug = "gateway-skills-install-test"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        let archiveRoot = CliConfig.cwd.join("target").join("gateway-skills-install-archive")
        try {
            clearTestState(skillDir)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
            Directory.create(archiveRoot, recursive: true)
            File.writeTo(
                archiveRoot.join("SKILL.md"),
                "---\nname: ${slug}\nversion: 4.5.6\ndescription: gateway install\n---\n# ${slug}\n".toArray()
            )
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"${slug}\"},\"latestVersion\":{\"version\":\"4.5.6\"}}"
            }))
            setClawHubArchiveRootForTest(Some({ _slug: String, _version: String => archiveRoot }))

            let params = JsonObject()
            params.put("source", JsonString("clawhub"))
            params.put("slug", JsonString(slug))
            let response = handleGatewaySkillsFamily("skills.install", request: Some(GatewayRpcRequest("skills.install", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(gatewaySkillsTestString(result, "slug"), slug)
            @Expect(gatewaySkillsTestString(result, "version"), "4.5.6")
        } finally {
            clearTestState(skillDir)
            if (exists(archiveRoot)) {
                remove(archiveRoot, recursive: true)
            }
        }
    }

    @TestCase
    public func skillsUpdateRejectsInvalidParameterCombination(): Unit {
        let params = JsonObject()
        params.put("slug", JsonString("weather"))
        params.put("all", true.toJsonValue())
        let response = handleGatewaySkillsFamily("skills.update", request: Some(GatewayRpcRequest("skills.update", params: params))).getOrThrow()
        @Expect(response.ok, false)
        @Expect(response.errorCode, "INVALID_REQUEST")
    }

    @TestCase
    public func skillsUpdateMutatesSkillConfigWhenSkillKeyIsProvided(): Unit {
        let params = JsonObject()
        params.put("skillKey", JsonString("review"))
        params.put("enabled", false.toJsonValue())
        params.put("apiKey", JsonString("abc\r\ndef"))
        let env = JsonObject()
        env.put(" OPENAI_API_KEY ", JsonString(" sk-live "))
        env.put("EMPTY", JsonString("   "))
        params.put("env", env)

        let response = handleGatewaySkillsFamily("skills.update", request: Some(GatewayRpcRequest("skills.update", params: params))).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(gatewaySkillsTestString(result, "skillKey"), "review")
        let config = result.get("config").getOrThrow().asObject()
        @Expect(config.get("enabled").getOrThrow().asBool().getValue(), false)
        @Expect(gatewaySkillsTestString(config, "apiKey"), "abcdef")
        let savedEnv = config.get("env").getOrThrow().asObject()
        @Expect(gatewaySkillsTestString(savedEnv, "OPENAI_API_KEY"), "sk-live")
        @Expect(savedEnv.get("EMPTY").isSome(), false)

        let dashboard = handleGatewayDashboardFamily("dashboard.skills.set", GatewayRpcRequest("dashboard.skills.set", params: params)).getOrThrow()
        @Expect(dashboard.ok, true)
        let dashboardConfig = dashboard.result.asObject().get("config").getOrThrow().asObject()
        @Expect(gatewaySkillsTestString(dashboardConfig, "apiKey"), "abcdef")
    }

    @TestCase
    public func skillsUpdateClearsApiKeyAndEnvWhenEmptyValuesAreProvided(): Unit {
        let seed = JsonObject()
        seed.put("skillKey", JsonString("review"))
        seed.put("apiKey", JsonString("seed"))
        let seedEnv = JsonObject()
        seedEnv.put("OPENAI_API_KEY", JsonString("seed"))
        seed.put("env", seedEnv)
        let _ = handleGatewaySkillsFamily("skills.update", request: Some(GatewayRpcRequest("skills.update", params: seed))).getOrThrow()

        let params = JsonObject()
        params.put("skillKey", JsonString("review"))
        params.put("apiKey", JsonString(" \r\n "))
        params.put("env", JsonObject())
        let response = handleGatewaySkillsFamily("skills.update", request: Some(GatewayRpcRequest("skills.update", params: params))).getOrThrow()
        @Expect(response.ok, true)
        let config = response.result.asObject().get("config").getOrThrow().asObject()
        @Expect(config.get("apiKey").isSome(), false)
        @Expect(config.get("env").isSome(), false)
    }
}
