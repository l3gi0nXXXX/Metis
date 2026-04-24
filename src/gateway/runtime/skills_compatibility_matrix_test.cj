package metis.gateway.runtime

import metis.core.config.{MetisConfigManager, CliConfig}
import metis.core.skills.{SkillsPrompt, tryHandleSkillsCommand}

import std.collection.ArrayList
import std.fs.{Directory, File, OpenMode, Path, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func matrixRowByName(rows: ArrayList<JsonObject>, name: String): Option<JsonObject> {
    for (row in rows) {
        match (row.get("name")) {
            case Some(v) =>
                if (try { v.asString().getValue() } catch (_: Exception) { "" } == name) {
                    return Some(row)
                }
            case None => ()
        }
    }
    None
}

private func matrixCheckJson(raw: String): JsonObject {
    JsonValue.fromStr(raw).asObject()
}

private func matrixReportRowByName(rows: JsonArray, name: String): Option<JsonObject> {
    for (i in 0..rows.size()) {
        let row = rows[i].asObject()
        match (row.get("name")) {
            case Some(v) =>
                if (try { v.asString().getValue() } catch (_: Exception) { "" } == name) {
                    return Some(row)
                }
            case None => ()
        }
    }
    None
}

@Test
public class SkillsCompatibilityMatrixTest {
    private func clearSkill(skillDir: Path): Unit {
        SkillsPrompt.invalidate()
        let _ = MetisConfigManager.setSkillsEntries(None)
        if (exists(skillDir)) {
            remove(skillDir, recursive: true)
        }
    }

    private func writeSkill(skillDir: Path, raw: String): Unit {
        Directory.create(skillDir, recursive: true)
        File.writeTo(skillDir.join("SKILL.md"), raw.toArray())
        SkillsPrompt.invalidate()
    }

    @TestCase
    public func matrixPromptOnlySkillIsFullyCompatible(): Unit {
        let slug = "compat-matrix-prompt-only"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearSkill(skillDir)
            writeSkill(
                skillDir,
                "---\nname: ${slug}\ndescription: prompt only matrix skill\n---\n# ${slug}\n"
            )

            let check = tryHandleSkillsCommand("/skills check --json").getOrThrow()
            @Expect(check.contains("\"kind\":\"skills-check\""), true)
            @Expect(check.contains("\"name\":\"${slug}\""), true)

            let status = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status"))).getOrThrow()
            @Expect(status.ok, true)
            let rowsJson = status.result.asObject().get("skills").getOrThrow().asArray()
            let rows = ArrayList<JsonObject>()
            for (i in 0..rowsJson.size()) {
                rows.add(rowsJson[i].asObject())
            }
            let row = matrixRowByName(rows, slug).getOrThrow()
            @Expect(row.get("eligible").getOrThrow().asBool().getValue(), true)
            @Expect(try { row.get("readiness").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "ready")
        } finally {
            clearSkill(skillDir)
        }
    }

    @TestCase
    public func matrixConfiguredApiKeySkillIsCompatibleWhenConfigured(): Unit {
        let slug = "compat-matrix-api-key"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearSkill(skillDir)
            writeSkill(
                skillDir,
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: api key matrix skill\n" +
                    "metadata: {\"metis\":{\"skillKey\":\"compat-matrix-api-key\",\"primaryEnv\":\"PRIMARY_SECRET\",\"requires\":{\"env\":[\"PRIMARY_SECRET\"]}}}\n" +
                    "---\n# ${slug}\n")
            )
            let entries = JsonObject()
            let entry = JsonObject()
            entry.put("apiKey", JsonString("resolved-secret"))
            entries.put("compat-matrix-api-key", entry)
            let _ = MetisConfigManager.setSkillsEntries(Some(entries))
            SkillsPrompt.invalidate()

            let status = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status"))).getOrThrow()
            @Expect(status.ok, true)
            let rowsJson = status.result.asObject().get("skills").getOrThrow().asArray()
            let rows = ArrayList<JsonObject>()
            for (i in 0..rowsJson.size()) {
                rows.add(rowsJson[i].asObject())
            }
            let row = matrixRowByName(rows, slug).getOrThrow()
            @Expect(row.get("eligible").getOrThrow().asBool().getValue(), true)
            @Expect(try { row.get("configuredApiKey").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "resolved-secret")
        } finally {
            clearSkill(skillDir)
        }
    }

    @TestCase
    public func matrixDirectDownloadSkillIsPartiallyCompatibleWithRiskWarning(): Unit {
        let slug = "compat-matrix-download"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearSkill(skillDir)
            writeSkill(
                skillDir,
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: direct download matrix skill\n" +
                    "metadata: {\"metis\":{\"install\":[{\"id\":\"download\",\"kind\":\"download\",\"url\":\"https://example.com/tool.zip\"}]}}\n" +
                    "---\n# ${slug}\n")
            )

            let check = tryHandleSkillsCommand("/skills check --json").getOrThrow()
            @Expect(check.contains("\"warnCount\":\"1\"") || check.contains("\"warnCount\":\""), true)

            let status = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status"))).getOrThrow()
            @Expect(status.ok, true)
            let rowsJson = status.result.asObject().get("skills").getOrThrow().asArray()
            let rows = ArrayList<JsonObject>()
            for (i in 0..rowsJson.size()) {
                rows.add(rowsJson[i].asObject())
            }
            let row = matrixRowByName(rows, slug).getOrThrow()
            let risk = row.get("installRisk").getOrThrow().asObject()
            @Expect(try { risk.get("level").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "warn")
        } finally {
            clearSkill(skillDir)
        }
    }

    @TestCase
    public func matrixAllowlistBlockedSkillIsReportedAsBlocked(): Unit {
        let slug = "compat-matrix-blocked"
        let allowedSlug = "compat-matrix-allowed"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        let allowedDir = CliConfig.cwd.join("skills").join(allowedSlug)
        try {
            clearSkill(skillDir)
            clearSkill(allowedDir)
            writeSkill(skillDir, "---\nname: ${slug}\ndescription: blocked matrix skill\n---\n# ${slug}\n")
            writeSkill(allowedDir, "---\nname: ${allowedSlug}\ndescription: allowed matrix skill\n---\n# ${allowedSlug}\n")

            let params = JsonObject()
            params.put("agentId", JsonString("docs"))
            let root = JsonObject()
            let agents = JsonObject()
            let list = JsonArray([])
            let docs = JsonObject()
            docs.put("id", JsonString("docs"))
            docs.put("skills", JsonArray([JsonString(allowedSlug)]))
            list.add(docs)
            agents.put("list", list)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)
            SkillsPrompt.invalidate()

            let status = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status", params: params))).getOrThrow()
            @Expect(status.ok, true)
            let rowsJson = status.result.asObject().get("skills").getOrThrow().asArray()
            let rows = ArrayList<JsonObject>()
            for (i in 0..rowsJson.size()) {
                rows.add(rowsJson[i].asObject())
            }
            let row = matrixRowByName(rows, slug).getOrThrow()
            @Expect(row.get("blockedByAllowlist").getOrThrow().asBool().getValue(), true)
            @Expect(try { row.get("readiness").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "blocked-by-allowlist")
        } finally {
            let root = JsonObject()
            MetisConfigManager.writeRoot(root)
            clearSkill(skillDir)
            clearSkill(allowedDir)
        }
    }

    @TestCase
    public func matrixDisableModelInvocationSkillRemainsEligibleButFlagged(): Unit {
        let slug = "compat-matrix-disable-model"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearSkill(skillDir)
            writeSkill(
                skillDir,
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: disable-model matrix skill\n" +
                    "user-invocable: true\n" +
                    "disable-model-invocation: true\n" +
                    "---\n# ${slug}\n")
            )

            let status = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status"))).getOrThrow()
            @Expect(status.ok, true)
            let rowsJson = status.result.asObject().get("skills").getOrThrow().asArray()
            let rows = ArrayList<JsonObject>()
            for (i in 0..rowsJson.size()) {
                rows.add(rowsJson[i].asObject())
            }
            let row = matrixRowByName(rows, slug).getOrThrow()
            @Expect(row.get("eligible").getOrThrow().asBool().getValue(), true)
            @Expect(row.get("userInvocable").getOrThrow().asBool().getValue(), true)
            @Expect(row.get("disableModelInvocation").getOrThrow().asBool().getValue(), true)
        } finally {
            clearSkill(skillDir)
        }
    }

    @TestCase
    public func matrixMissingConfigSkillIsReportedAsMissingRequirements(): Unit {
        let slug = "compat-matrix-config-missing"
        let skillDir = CliConfig.cwd.join("skills").join(slug)
        try {
            clearSkill(skillDir)
            writeSkill(
                skillDir,
                ("---\n" +
                    "name: ${slug}\n" +
                    "description: missing config matrix skill\n" +
                    "metadata: {\"metis\":{\"requires\":{\"config\":[\"channels.discord.token\"]}}}\n" +
                    "---\n# ${slug}\n")
            )

            let check = matrixCheckJson(tryHandleSkillsCommand("/skills check --json").getOrThrow())
            @Expect(try { check.get("missingRequirementsCount").getOrThrow().asString().getValue() } catch (_: Exception) { "" } != "0", true)

            let status = handleGatewaySkillsFamily("skills.status", request: Some(GatewayRpcRequest("skills.status"))).getOrThrow()
            @Expect(status.ok, true)
            let rowsJson = status.result.asObject().get("skills").getOrThrow().asArray()
            let rows = ArrayList<JsonObject>()
            for (i in 0..rowsJson.size()) {
                rows.add(rowsJson[i].asObject())
            }
            let row = matrixRowByName(rows, slug).getOrThrow()
            @Expect(row.get("eligible").getOrThrow().asBool().getValue(), false)
            @Expect(try { row.get("readiness").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "missing-requirements")
            let missing = row.get("missing").getOrThrow().asObject()
            @Expect(missing.get("config").getOrThrow().asArray().size(), 1)
        } finally {
            clearSkill(skillDir)
        }
    }

    @TestCase
    public func matrixReportClassifiesRepresentativeSkillTypes(): Unit {
        let promptSlug = "compat-report-prompt"
        let downloadSlug = "compat-report-download"
        let configSlug = "compat-report-config"
        let promptDir = CliConfig.cwd.join("skills").join(promptSlug)
        let downloadDir = CliConfig.cwd.join("skills").join(downloadSlug)
        let configDir = CliConfig.cwd.join("skills").join(configSlug)
        try {
            clearSkill(promptDir)
            clearSkill(downloadDir)
            clearSkill(configDir)
            writeSkill(promptDir, "---\nname: ${promptSlug}\ndescription: prompt report skill\n---\n# ${promptSlug}\n")
            writeSkill(
                downloadDir,
                ("---\n" +
                    "name: ${downloadSlug}\n" +
                    "description: download report skill\n" +
                    "metadata: {\"metis\":{\"install\":[{\"id\":\"download\",\"kind\":\"download\",\"url\":\"https://example.com/tool.zip\"}]}}\n" +
                    "---\n# ${downloadSlug}\n")
            )
            writeSkill(
                configDir,
                ("---\n" +
                    "name: ${configSlug}\n" +
                    "description: config report skill\n" +
                    "metadata: {\"metis\":{\"requires\":{\"config\":[\"channels.discord.token\"]}}}\n" +
                    "---\n# ${configSlug}\n")
            )

            let report = gatewaySkillsCompatibilityMatrixReport()
            @Expect(try { report.get("kind").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "skills-compatibility-matrix")
            let summary = report.get("summary").getOrThrow().asObject()
            @Expect(summary.get("fullyCompatibleCount").getOrThrow().asInt().getValue() >= 1, true)
            @Expect(summary.get("partiallyCompatibleCount").getOrThrow().asInt().getValue() >= 1, true)
            @Expect(summary.get("incompatibleCount").getOrThrow().asInt().getValue() >= 1, true)

            let rows = report.get("rows").getOrThrow().asArray()
            let promptRow = matrixReportRowByName(rows, promptSlug).getOrThrow()
            @Expect(try { promptRow.get("compatibility").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "fully-compatible")

            let downloadRow = matrixReportRowByName(rows, downloadSlug).getOrThrow()
            @Expect(try { downloadRow.get("compatibility").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "partially-compatible")

            let configRow = matrixReportRowByName(rows, configSlug).getOrThrow()
            @Expect(try { configRow.get("compatibility").getOrThrow().asString().getValue() } catch (_: Exception) { "" }, "incompatible")
        } finally {
            clearSkill(promptDir)
            clearSkill(downloadDir)
            clearSkill(configDir)
        }
    }
}
