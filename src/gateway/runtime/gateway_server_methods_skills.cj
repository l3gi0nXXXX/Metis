package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{MetisConfigManager, CliConfig, CliSettingManager}
import metis.utils.InfoUtils
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.core.skills.{
    ClawHubUpdateTransportResult,
    SkillsPrompt,
    SkillDescriptor,
    fetchClawHubSkillDetailJson,
    installClawHubSkill,
    readTrackedClawHubSkillSlugs,
    resolveAgentSkillVisibility,
    searchClawHubSkillsText,
    SkillsSearchRequest,
    skillsManagedDir,
    skillsWorkspaceDir,
    updateClawHubSkills
}

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.env.getVariable
import std.fs.{File, OpenMode, Path, exists}
import std.io.readToEnd
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

import metis.utils.ShellUtils

private func gatewaySkillsString(params: JsonObject, key: String): String {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func gatewaySkillsBool(params: JsonObject, key: String, fallback: Bool): Bool {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) {
                try {
                    let text = v.asString().getValue().trimAscii().toAsciiLower()
                    text == "true" || text == "1" || text == "yes" || text == "on"
                } catch (_: Exception) {
                    fallback
                }
            }
        case None => fallback
    }
}

private func gatewaySkillsInt(params: JsonObject, key: String, fallback: Int64): Int64 {
    match (params.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_: Exception) {
                try { Int64.parse(v.toJsonString().trimAscii()) } catch (_: Exception) { fallback }
            }
        case None => fallback
    }
}

private func gatewaySkillsNormalizeSecretInput(raw: String): String {
    raw.replace("\r", "").replace("\n", "").trimAscii()
}

private func gatewaySkillsCloneWithoutKeys(obj: JsonObject, keys: Array<String>): JsonObject {
    let out = JsonObject()
    for ((key, value) in obj.getFields()) {
        if (keys.contains(key)) {
            continue
        }
        out.put(key, value)
    }
    out
}

private func gatewaySkillsNormalizedEnvMap(params: JsonObject): JsonObject {
    let envObj = JsonObject()
    match (params.get("env")) {
        case Some(value) =>
            try {
                let raw = value.asObject()
                for ((key, vv) in raw.getFields()) {
                    let trimmedKey = key.trimAscii()
                    if (trimmedKey.isEmpty()) {
                        continue
                    }
                    let trimmedValue = try { vv.asString().getValue().trimAscii() } catch (_: Exception) { "" }
                    if (!trimmedValue.isEmpty()) {
                        envObj.put(trimmedKey, JsonString(trimmedValue))
                    }
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    envObj
}

private func gatewaySkillsReadRaw(path: String): String {
    let p = Path(path)
    if (!exists(p)) {
        return ""
    }
    try {
        String.fromUtf8(readToEnd(File(p, OpenMode.Read)))
    } catch (_: Exception) {
        ""
    }
}

private func gatewaySkillsParseFrontmatter(raw: String): HashMap<String, String> {
    let fm = HashMap<String, String>()
    if (!raw.startsWith("---\n")) {
        return fm
    }
    try {
        let lines = raw.split("\n")
        var endIdx: Int64 = -1
        var i: Int64 = 1
        while (i < lines.size) {
            if (lines[i].trimAscii() == "---") {
                endIdx = i
                break
            }
            i += 1
        }
        if (endIdx < 0) {
            return fm
        }
        var j: Int64 = 1
        while (j < endIdx) {
            let line = lines[j]
            match (line.indexOf(":")) {
                case Some(colon) =>
                    let key = line[0..colon].trimAscii().toAsciiLower()
                    let value = line[colon + 1..line.size].trimAscii().replace("\"", "").replace("'", "")
                    if (!key.isEmpty()) {
                        fm[key] = value
                    }
                case None => ()
            }
            j += 1
        }
    } catch (_: Exception) {
        ()
    }
    fm
}

private func gatewaySkillsRequirementsFromFrontmatter(fm: HashMap<String, String>): Array<String> {
    let raw = fm.get("requires_env") ?? ""
    if (raw.trimAscii().isEmpty()) {
        return []
    }
    let out = ArrayList<String>()
    for (part in raw.split(",")) {
        let key = part.trimAscii()
        if (!key.isEmpty()) {
            out.add(key)
        }
    }
    out.toArray()
}

private func gatewaySkillsBinariesFromRaw(raw: String): Array<String> {
    let out = ArrayList<String>()
    for (line0 in raw.split("\n")) {
        let line = line0.trimAscii().toAsciiLower()
        if (line.startsWith("binaries:")) {
            let vv = line0.trimAscii()["binaries:".size..].trimAscii()
            for (part in vv.split(",")) {
                let bin = part.trimAscii().replace("\"", "").replace("'", "")
                if (!bin.isEmpty()) {
                    out.add(bin)
                }
            }
        }
    }
    match (raw.indexOf("\"bins\"")) {
        case Some(pos) =>
            let tail = raw[pos..]
            match (tail.indexOf("[")) {
                case Some(lb) =>
                    let tail2 = tail[lb + 1..]
                    match (tail2.indexOf("]")) {
                        case Some(rb) =>
                            let body = tail2[0..rb]
                            for (part in body.split(",")) {
                                let bin = part.trimAscii().replace("\"", "").replace("'", "")
                                if (!bin.isEmpty()) {
                                    out.add(bin)
                                }
                            }
                        case None => ()
                    }
                case None => ()
            }
        case None => ()
    }
    if (out.isEmpty() && raw.toAsciiLower().contains("curl")) {
        out.add("curl")
    }
    out.toArray()
}

private func gatewaySkillBinaryExists(bin: String): Bool {
    let normalized = bin.trimAscii()
    if (normalized.isEmpty()) {
        return false
    }
    try {
        let (codeWhere, _, _) = ShellUtils.execute(
            ["where ${normalized}"],
            workDir: CliConfig.cwd,
            timeout: Some(Duration.second * 3),
            usePowerShellOnWindows: true
        )
        if (codeWhere == 0) {
            return true
        }
        let (codeWhich, _, _) = ShellUtils.execute(
            ["which ${normalized}"],
            workDir: CliConfig.cwd,
            timeout: Some(Duration.second * 3),
            usePowerShellOnWindows: true
        )
        codeWhich == 0
    } catch (_: Exception) {
        false
    }
}

private func gatewaySkillsMissingEnv(requirements: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (key in requirements) {
        if (getVariable(key).isNone()) {
            out.add(key)
        }
    }
    out.toArray()
}

private func gatewaySkillsMissingEnvWithConfig(descriptor: SkillDescriptor, requirements: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (key0 in requirements) {
        let key = key0.trimAscii()
        if (key.isEmpty()) {
            continue
        }
        if (getVariable(key).isSome()) {
            continue
        }
        var satisfied = false
        match (descriptor.configuredEnv) {
            case Some(envObj) =>
                match (envObj.get(key)) {
                    case Some(value) =>
                        try {
                            if (!value.asString().getValue().trimAscii().isEmpty()) {
                                satisfied = true
                            }
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
            case None => ()
        }
        if (!satisfied && !descriptor.primaryEnv.isEmpty() && descriptor.primaryEnv == key && !descriptor.configuredApiKey.isEmpty()) {
            satisfied = true
        }
        if (!satisfied) {
            out.add(key)
        }
    }
    out.toArray()
}

private func gatewaySkillsMissingBins(bins: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (bin in bins) {
        if (!gatewaySkillBinaryExists(bin)) {
            out.add(bin)
        }
    }
    out.toArray()
}

private func gatewaySkillsMissingConfig(paths: Array<String>): Array<String> {
    let out = ArrayList<String>()
    let root = MetisConfigManager.rawConfig() ?? JsonObject()
    let defaultTruthy = HashMap<String, Bool>()
    defaultTruthy["browser.enabled"] = true
    defaultTruthy["browser.evaluateEnabled"] = true
    for (path in paths) {
        let normalized = path.trimAscii()
        if (normalized.isEmpty()) {
            continue
        }
        var current: JsonValue = root
        var found = true
        for (segment0 in normalized.split(".")) {
            let segment = segment0.trimAscii()
            if (segment.isEmpty()) {
                found = false
                break
            }
            current = match (current) {
                case obj: JsonObject =>
                    match (obj.get(segment)) {
                        case Some(value) => value
                        case None =>
                            found = false
                            break
                    }
                case _ =>
                    found = false
                    break
            }
        }
        if (!found) {
            if (defaultTruthy.contains(normalized) && defaultTruthy[normalized]) {
                continue
            }
            out.add(normalized)
            continue
        }
        let truthy = try {
            current.asBool().getValue()
        } catch (_: Exception) {
            try {
                current.asInt().getValue() != 0
            } catch (_: Exception) {
                try {
                    !current.asString().getValue().trimAscii().isEmpty()
                } catch (_: Exception) {
                    true
                }
            }
        }
        if (!truthy) {
            out.add(normalized)
        }
    }
    out.toArray()
}

private func gatewaySkillsStringArrayFromJson(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                let out = ArrayList<String>()
                for (i in 0..arr.size()) {
                    try {
                        let text = arr[i].asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                []
            }
        case None => []
    }
}

private func gatewaySkillsInstallLabel(spec: JsonObject, kind: String): String {
    let explicit = gatewaySkillsString(spec, "label")
    if (!explicit.isEmpty()) {
        return explicit
    }
    if (kind == "brew") {
        let formula = gatewaySkillsString(spec, "formula")
        if (!formula.isEmpty()) {
            return "Install ${formula} (brew)"
        }
    }
    if (kind == "node") {
        let pkg = gatewaySkillsString(spec, "package")
        if (!pkg.isEmpty()) {
            return "Install ${pkg} (npm)"
        }
    }
    if (kind == "go") {
        let module = gatewaySkillsString(spec, "module")
        if (!module.isEmpty()) {
            return "Install ${module} (go)"
        }
    }
    if (kind == "uv") {
        let pkg = gatewaySkillsString(spec, "package")
        if (!pkg.isEmpty()) {
            return "Install ${pkg} (uv)"
        }
    }
    if (kind == "download") {
        let url = gatewaySkillsString(spec, "url")
        if (!url.isEmpty()) {
            return "Download ${url}"
        }
    }
    "Run installer"
}

private func gatewaySkillsInstallPreferences(): (Bool, String) {
    let root = MetisConfigManager.rawConfig() ?? JsonObject()
    let skillsObj = match (root.get("skills")) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let installObj = match (skillsObj.get("install")) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let preferBrew = match (installObj.get("preferBrew")) {
        case Some(value) =>
            try { value.asBool().getValue() } catch (_: Exception) { true }
        case None => true
    }
    let nodeManagerRaw = match (installObj.get("nodeManager")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii().toAsciiLower() } catch (_: Exception) { "npm" }
        case None => "npm"
    }
    let nodeManager = if (
        nodeManagerRaw == "npm" ||
        nodeManagerRaw == "pnpm" ||
        nodeManagerRaw == "yarn" ||
        nodeManagerRaw == "bun"
    ) {
        nodeManagerRaw
    } else {
        "npm"
    }
    (preferBrew, nodeManager)
}

private func gatewaySkillsInstallOptions(descriptor: SkillDescriptor): JsonArray {
    let requiredOs = descriptor.requiredOs
    let currentPlatform = match (InfoUtils.os) {
        case "macos" => "darwin"
        case "windows" => "win32"
        case "linux" => "linux"
        case _ => "unknown"
    }
    if (!requiredOs.isEmpty() && !requiredOs.contains(currentPlatform)) {
        return JsonArray([])
    }
    let filtered = ArrayList<JsonObject>()
    for (i in 0..descriptor.installSpecs.size) {
        let spec = descriptor.installSpecs[i]
        let specOs = gatewaySkillsStringArrayFromJson(spec, "os")
        if (!specOs.isEmpty() && !specOs.contains(currentPlatform)) {
            continue
        }
        let kind = gatewaySkillsString(spec, "kind")
        if (kind.isEmpty()) {
            continue
        }
        filtered.add(spec)
    }
    if (filtered.isEmpty()) {
        return JsonArray([])
    }
    var allDownloads = true
    for (spec in filtered) {
        if (gatewaySkillsString(spec, "kind") != "download") {
            allDownloads = false
            break
        }
    }
    let (preferBrew, nodeManager) = gatewaySkillsInstallPreferences()
    let brewAvailable = gatewaySkillBinaryExists("brew")
    let preferredKinds = ArrayList<String>()
    if (preferBrew && brewAvailable) {
        preferredKinds.add("brew")
    }
    preferredKinds.add("uv")
    preferredKinds.add("node")
    if (brewAvailable && !preferredKinds.contains("brew")) {
        preferredKinds.add("brew")
    }
    preferredKinds.add("go")
    preferredKinds.add("download")

    let selected = ArrayList<(Int64, JsonObject)>()
    if (allDownloads) {
        for (i in 0..filtered.size) {
            selected.add((i, filtered[i]))
        }
    } else {
        var chosen: Option<(Int64, JsonObject)> = None
        for (kind in preferredKinds) {
            for (i in 0..filtered.size) {
                if (gatewaySkillsString(filtered[i], "kind") == kind) {
                    chosen = Some((i, filtered[i]))
                    break
                }
            }
            if (chosen.isSome()) {
                break
            }
        }
        if (let Some(item) <- chosen) {
            selected.add(item)
        }
    }

    let arr = JsonArray([])
    for ((i, spec) in selected) {
        let kind = gatewaySkillsString(spec, "kind")
        let option = JsonObject()
        let id = gatewaySkillsString(spec, "id")
        option.put("id", JsonString(if (id.isEmpty()) { "${kind}-${i}" } else { id }))
        option.put("kind", JsonString(kind))
        let normalizedLabel = if (kind == "node") {
            let explicit = gatewaySkillsString(spec, "label")
            if (!explicit.isEmpty()) {
                explicit
            } else {
                let pkg = gatewaySkillsString(spec, "package")
                if (!pkg.isEmpty()) {
                    "Install ${pkg} (${nodeManager})"
                } else {
                    gatewaySkillsInstallLabel(spec, kind)
                }
            }
        } else {
            gatewaySkillsInstallLabel(spec, kind)
        }
        option.put("label", JsonString(normalizedLabel))
        let bins = JsonArray([])
        for (bin in gatewaySkillsStringArrayFromJson(spec, "bins")) {
            bins.add(JsonString(bin))
        }
        option.put("bins", bins)
        arr.add(option)
    }
    arr
}

private func gatewaySkillsInstallRisk(descriptor: SkillDescriptor): JsonObject {
    let install = gatewaySkillsInstallOptions(descriptor)
    let risk = JsonObject()
    if (install.size() == 0) {
        risk.put("level", JsonString("none"))
        risk.put("kind", JsonString(""))
        risk.put("message", JsonString(""))
        return risk
    }
    let install0 = install[0].asObject()
    let kind = gatewaySkillsString(install0, "kind")
    risk.put("kind", JsonString(kind))
    if (kind == "download") {
        risk.put("level", JsonString("warn"))
        risk.put("message", JsonString("Review download installer source before running it"))
        return risk
    }
    if (kind == "node") {
        risk.put("level", JsonString("caution"))
        risk.put("message", JsonString("Review package installer before running it"))
        return risk
    }
    risk.put("level", JsonString("safe"))
    risk.put("message", JsonString("Installer uses managed package tooling"))
    risk
}

private func gatewaySkillsSandboxSummary(missingBins!: JsonArray = JsonArray([])): JsonObject {
    let sandboxObj = JsonObject()
    let runtimeCommand = if (InfoUtils.os == "macos") { "sandbox-exec" } else { "docker" }
    sandboxObj.put("configured", false.toJsonValue())
    sandboxObj.put("runtime", JsonString(runtimeCommand))
    sandboxObj.put("profile", JsonString("workspace-write"))
    sandboxObj.put("entrypoint", JsonString("metis --sandbox --prompt \"...\""))
    sandboxObj.put("workspaceAccess", JsonString("workspace-write"))
    sandboxObj.put("skillsReadable", true.toJsonValue())
    sandboxObj.put("eligible", false.toJsonValue())
    sandboxObj.put("reason", JsonString("sandbox-runtime-unconfigured"))
    let sandboxMissing = JsonObject()
    sandboxMissing.put("bins", missingBins)
    sandboxObj.put("missing", sandboxMissing)
    sandboxObj
}

private func gatewaySkillsDoctorActions(
    descriptor: SkillDescriptor,
    missingEnv!: Array<String> = [],
    missingBins!: Array<String> = [],
    missingAnyBins!: Array<String> = [],
    missingConfig!: Array<String> = []
): JsonArray {
    let actions = JsonArray([])
    let key = if (descriptor.skillKey.trimAscii().isEmpty()) { descriptor.name } else { descriptor.skillKey }
    for (envKey in missingEnv) {
        let obj = JsonObject()
        obj.put("kind", JsonString("env"))
        obj.put("key", JsonString(envKey))
        obj.put("message", JsonString("Configure skills.entries.${key}.env.${envKey} or provide shell env ${envKey}"))
        actions.add(obj)
    }
    if (!descriptor.primaryEnv.trimAscii().isEmpty() &&
        !descriptor.configuredApiKey.trimAscii().isEmpty() == false &&
        missingEnv.contains(descriptor.primaryEnv)
    ) {
        let obj = JsonObject()
        obj.put("kind", JsonString("apiKey"))
        obj.put("key", JsonString(descriptor.primaryEnv))
        obj.put("message", JsonString("Configure skills.entries.${key}.apiKey for ${descriptor.primaryEnv}"))
        actions.add(obj)
    }
    for (bin in missingBins) {
        let obj = JsonObject()
        obj.put("kind", JsonString("bin"))
        obj.put("key", JsonString(bin))
        obj.put("message", JsonString("Install required binary ${bin}"))
        actions.add(obj)
    }
    if (!missingAnyBins.isEmpty()) {
        let obj = JsonObject()
        obj.put("kind", JsonString("anyBin"))
        obj.put("key", JsonString(String.join(missingAnyBins, delimiter: ",")))
        obj.put("message", JsonString("Install at least one of: ${String.join(missingAnyBins, delimiter: ", ")}"))
        actions.add(obj)
    }
    for (path in missingConfig) {
        let obj = JsonObject()
        obj.put("kind", JsonString("config"))
        obj.put("key", JsonString(path))
        obj.put("message", JsonString("Set config path ${path} to a truthy value"))
        actions.add(obj)
    }
    let installRisk = gatewaySkillsInstallRisk(descriptor)
    let riskLevel = gatewaySkillsString(installRisk, "level")
    if (riskLevel == "warn" || riskLevel == "caution") {
        let obj = JsonObject()
        obj.put("kind", JsonString("installRisk"))
        obj.put("key", JsonString(gatewaySkillsString(installRisk, "kind")))
        obj.put("message", JsonString(gatewaySkillsString(installRisk, "message")))
        actions.add(obj)
    }
    actions
}

private func gatewaySkillStatusRow(descriptor: SkillDescriptor): JsonObject {
    let raw = gatewaySkillsReadRaw(descriptor.location)
    let fm = gatewaySkillsParseFrontmatter(raw)
    let requirements = if (!descriptor.requiredEnv.isEmpty()) {
        descriptor.requiredEnv
    } else {
        gatewaySkillsRequirementsFromFrontmatter(fm)
    }
    let bins = ArrayList<String>()
    let seenBins = HashMap<String, Bool>()
    for (bin in descriptor.requiredBins) {
        let normalized = bin.trimAscii()
        if (!normalized.isEmpty() && !seenBins.contains(normalized)) {
            seenBins[normalized] = true
            bins.add(normalized)
        }
    }
    let anyBins = ArrayList<String>()
    for (bin in descriptor.requiredAnyBins) {
        let normalized = bin.trimAscii()
        if (!normalized.isEmpty()) {
            anyBins.add(normalized)
            if (!seenBins.contains(normalized)) {
                seenBins[normalized] = true
                bins.add(normalized)
            }
        }
    }
    for (bin in gatewaySkillsBinariesFromRaw(raw)) {
        let normalized = bin.trimAscii()
        if (!normalized.isEmpty() && !seenBins.contains(normalized)) {
            seenBins[normalized] = true
            bins.add(normalized)
        }
    }
    let missingEnv = gatewaySkillsMissingEnvWithConfig(descriptor, requirements)
    let missingBins = gatewaySkillsMissingBins(descriptor.requiredBins)
    let missingConfig = gatewaySkillsMissingConfig(descriptor.requiredConfig)
    let anyBinCandidates = anyBins.toArray()
    let emptyMissingBins: Array<String> = []
    let missingAnyBinCandidates = if (anyBinCandidates.isEmpty()) {
        emptyMissingBins
    } else {
        gatewaySkillsMissingBins(anyBinCandidates)
    }
    let missingAnyBins = if (anyBinCandidates.isEmpty()) {
        emptyMissingBins
    } else if (missingAnyBinCandidates.size == anyBinCandidates.size) {
        anyBinCandidates
    } else {
        emptyMissingBins
    }
    let currentPlatform = match (InfoUtils.os) {
        case "macos" => "darwin"
        case "windows" => "win32"
        case "linux" => "linux"
        case _ => "unknown"
    }
    let requiredOs = descriptor.requiredOs
    let missingOs = if (descriptor.always || requiredOs.isEmpty() || requiredOs.contains(currentPlatform)) {
        let ok: Array<String> = []
        ok
    } else {
        requiredOs
    }
    let configChecks = JsonArray([])
    for (path in descriptor.requiredConfig) {
        let check = JsonObject()
        check.put("path", JsonString(path))
        check.put("satisfied", (!missingConfig.contains(path)).toJsonValue())
        configChecks.add(check)
    }
    let install = gatewaySkillsInstallOptions(descriptor)
    let installRisk = gatewaySkillsInstallRisk(descriptor)
    let hostEligible = descriptor.enabled &&
        (descriptor.always || (missingEnv.isEmpty() && missingBins.isEmpty() && missingAnyBins.isEmpty() && missingConfig.isEmpty() && missingOs.isEmpty()))
    let eligible = hostEligible

    let row = JsonObject()
    row.put("name", JsonString(descriptor.name))
    row.put("description", JsonString(descriptor.description))
    row.put("source", JsonString(descriptor.source))
    row.put("filePath", JsonString(descriptor.location))
    row.put("skillKey", JsonString(descriptor.skillKey))
    row.put("primaryEnv", JsonString(descriptor.primaryEnv))
    row.put("configuredApiKey", JsonString(descriptor.configuredApiKey))
    row.put("homepage", JsonString(descriptor.homepage))
    row.put("always", descriptor.always.toJsonValue())
    let osArr = JsonArray([])
    for (platform in requiredOs) {
        osArr.add(JsonString(platform))
    }
    row.put("os", osArr)
    row.put("userInvocable", descriptor.userInvocable.toJsonValue())
    row.put("disableModelInvocation", descriptor.disableModelInvocation.toJsonValue())
    row.put("disabled", (!descriptor.enabled).toJsonValue())
    row.put("eligible", eligible.toJsonValue())
    row.put("hostEligible", hostEligible.toJsonValue())
    row.put(
        "readiness",
        JsonString(
            if (!descriptor.enabled) {
                "disabled"
            } else if (hostEligible) {
                "ready"
            } else {
                "missing-requirements"
            }
        )
    )

    let requirementsObj = JsonObject()
    let reqArr = JsonArray([])
    for (key in requirements) {
        reqArr.add(JsonString(key))
    }
    requirementsObj.put("env", reqArr)

    let binArr = JsonArray([])
    for (bin in bins) {
        binArr.add(JsonString(bin))
    }
    requirementsObj.put("bins", binArr)
    let anyBinArr = JsonArray([])
    for (bin in anyBinCandidates) {
        anyBinArr.add(JsonString(bin))
    }
    requirementsObj.put("anyBins", anyBinArr)
    let requiredConfigArr = JsonArray([])
    for (path in descriptor.requiredConfig) {
        requiredConfigArr.add(JsonString(path))
    }
    requirementsObj.put("config", requiredConfigArr)
    requirementsObj.put("os", osArr)
    row.put("requirements", requirementsObj)
    row.put("bins", binArr)
    row.put("anyBins", anyBinArr)
    row.put("requiredConfig", requiredConfigArr)
    row.put("configChecks", configChecks)
    row.put("install", install)
    row.put("installRisk", installRisk)
    match (descriptor.configuredEnv) {
        case Some(envObj) => row.put("configuredEnv", envObj)
        case None => ()
    }
    match (descriptor.configuredConfig) {
        case Some(configObj) => row.put("configuredConfig", configObj)
        case None => ()
    }

    let missing = JsonObject()
    let missingEnvArr = JsonArray([])
    for (key in missingEnv) {
        missingEnvArr.add(JsonString(key))
    }
    missing.put("env", missingEnvArr)
    let missingBinsArr = JsonArray([])
    for (bin in missingBins) {
        missingBinsArr.add(JsonString(bin))
    }
    missing.put("bins", missingBinsArr)
    let missingAnyBinsArr = JsonArray([])
    for (bin in missingAnyBins) {
        missingAnyBinsArr.add(JsonString(bin))
    }
    missing.put("anyBins", missingAnyBinsArr)
    let missingConfigArr = JsonArray([])
    for (path in missingConfig) {
        missingConfigArr.add(JsonString(path))
    }
    missing.put("config", missingConfigArr)
    let missingOsArr = JsonArray([])
    for (platform in missingOs) {
        missingOsArr.add(JsonString(platform))
    }
    missing.put("os", missingOsArr)
    row.put("missing", missing)
    row.put("sandbox", gatewaySkillsSandboxSummary(missingBins: missingBinsArr))
    row.put(
        "doctorActions",
        gatewaySkillsDoctorActions(
            descriptor,
            missingEnv: missingEnv,
            missingBins: missingBins,
            missingAnyBins: missingAnyBins,
            missingConfig: missingConfig
        )
    )
    row
}

private func gatewaySkillsStatusResult(agentId: String): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let visibility = resolveAgentSkillVisibility(agentId)
    let allowed = HashMap<String, Bool>()
    match (visibility.names) {
        case Some(names) =>
            for (name in names) {
                let normalized = name.trimAscii().toAsciiLower()
                if (!normalized.isEmpty()) {
                    allowed[normalized] = true
                }
            }
        case None => ()
    }
    let rows = JsonArray([])
    var eligibleCount: Int64 = 0
    var hostEligibleCount: Int64 = 0
    var sandboxEligibleCount: Int64 = 0
    var disabledCount: Int64 = 0
    var blockedCount: Int64 = 0
    var readyCount: Int64 = 0
    var missingRequirementsCount: Int64 = 0
    var safeInstallRiskCount: Int64 = 0
    var cautionInstallRiskCount: Int64 = 0
    var warnInstallRiskCount: Int64 = 0
    var noneInstallRiskCount: Int64 = 0
    let skills = SkillsPrompt.listAllSkillDescriptors()
    for (descriptor in skills) {
        let row = gatewaySkillStatusRow(descriptor)
        let blockedByAllowlist = match (visibility.names) {
            case Some(_) => !allowed.contains(descriptor.name.trimAscii().toAsciiLower())
            case None => false
        }
        row.put("blockedByAllowlist", blockedByAllowlist.toJsonValue())
        if (blockedByAllowlist) {
            row.put("eligible", false.toJsonValue())
            row.put("readiness", JsonString("blocked-by-allowlist"))
            blockedCount += 1
        }
        rows.add(row)
        if (try { row.get("hostEligible").getOrThrow().asBool().getValue() } catch (_: Exception) { false }) {
            hostEligibleCount += 1
        }
        if (
            try {
                row.get("sandbox").getOrThrow().asObject().get("eligible").getOrThrow().asBool().getValue()
            } catch (_: Exception) {
                false
            }
        ) {
            sandboxEligibleCount += 1
        }
        if (try { row.get("eligible").getOrThrow().asBool().getValue() } catch (_: Exception) { false }) {
            eligibleCount += 1
        }
        if (try { row.get("disabled").getOrThrow().asBool().getValue() } catch (_: Exception) { false }) {
            disabledCount += 1
        }
        let installRisk = try { row.get("installRisk").getOrThrow().asObject() } catch (_: Exception) { JsonObject() }
        let installRiskLevel = gatewaySkillsString(installRisk, "level")
        if (installRiskLevel == "safe") {
            safeInstallRiskCount += 1
        } else if (installRiskLevel == "caution") {
            cautionInstallRiskCount += 1
        } else if (installRiskLevel == "warn") {
            warnInstallRiskCount += 1
        } else {
            noneInstallRiskCount += 1
        }
        let readiness = try { row.get("readiness").getOrThrow().asString().getValue() } catch (_: Exception) { "" }
        if (readiness == "ready") {
            readyCount += 1
        }
        if (readiness == "missing-requirements") {
            missingRequirementsCount += 1
        }
    }
    let result = JsonObject()
    result.put("workspaceDir", JsonString(skillsWorkspaceDir().toString()))
    result.put("managedSkillsDir", JsonString(skillsManagedDir().toString()))
    result.put("agentId", JsonString(agentId))
    result.put("scope", JsonString(visibility.scope))
    result.put("count", skills.size.toJsonValue())
    result.put("eligibleCount", eligibleCount.toJsonValue())
    result.put("hostEligibleCount", hostEligibleCount.toJsonValue())
    result.put("sandboxEligibleCount", sandboxEligibleCount.toJsonValue())
    result.put("disabledCount", disabledCount.toJsonValue())
    result.put("blockedByAllowlistCount", blockedCount.toJsonValue())
    let readiness = JsonObject()
    readiness.put("readyCount", readyCount.toJsonValue())
    readiness.put("missingRequirementsCount", missingRequirementsCount.toJsonValue())
    readiness.put("disabledCount", disabledCount.toJsonValue())
    readiness.put("blockedByAllowlistCount", blockedCount.toJsonValue())
    result.put("readiness", readiness)
    let installRisk = JsonObject()
    installRisk.put("safeCount", safeInstallRiskCount.toJsonValue())
    installRisk.put("cautionCount", cautionInstallRiskCount.toJsonValue())
    installRisk.put("warnCount", warnInstallRiskCount.toJsonValue())
    installRisk.put("noneCount", noneInstallRiskCount.toJsonValue())
    result.put("installRisk", installRisk)
    result.put("nodePolicy", gatewayNodeSchedulerPolicySummary(cfg))
    result.put("devicePolicy", gatewayDeviceApprovalPolicySummary(cfg))
    result.put("skills", rows)
    result
}

public func gatewaySkillsCompatibilityMatrixReport(agentId!: String = ""): JsonObject {
    let status = gatewaySkillsStatusResult(agentId)
    let rows = try { status.get("skills").getOrThrow().asArray() } catch (_: Exception) { JsonArray([]) }
    let matrix = JsonArray([])
    var fullyCompatibleCount: Int64 = 0
    var partiallyCompatibleCount: Int64 = 0
    var incompatibleCount: Int64 = 0
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        let readiness = gatewaySkillsString(row, "readiness")
        let installRisk = try { row.get("installRisk").getOrThrow().asObject() } catch (_: Exception) { JsonObject() }
        let riskLevel = gatewaySkillsString(installRisk, "level")
        let disableModelInvocation = try { row.get("disableModelInvocation").getOrThrow().asBool().getValue() } catch (_: Exception) { false }
        let blockedByAllowlist = try { row.get("blockedByAllowlist").getOrThrow().asBool().getValue() } catch (_: Exception) { false }

        let compatibility = if (readiness != "ready") {
            "incompatible"
        } else if (riskLevel == "warn" || riskLevel == "caution" || disableModelInvocation || blockedByAllowlist) {
            "partially-compatible"
        } else {
            "fully-compatible"
        }
        if (compatibility == "fully-compatible") {
            fullyCompatibleCount += 1
        } else if (compatibility == "partially-compatible") {
            partiallyCompatibleCount += 1
        } else {
            incompatibleCount += 1
        }

        let reportRow = JsonObject()
        reportRow.put("name", JsonString(gatewaySkillsString(row, "name")))
        reportRow.put("compatibility", JsonString(compatibility))
        reportRow.put("readiness", JsonString(readiness))
        reportRow.put("installRisk", installRisk)
        reportRow.put("blockedByAllowlist", blockedByAllowlist.toJsonValue())
        reportRow.put("disableModelInvocation", disableModelInvocation.toJsonValue())
        reportRow.put("eligible", row.get("eligible") ?? false.toJsonValue())
        reportRow.put("hostEligible", row.get("hostEligible") ?? false.toJsonValue())
        reportRow.put("doctorActions", row.get("doctorActions") ?? JsonArray([]))
        reportRow.put("missing", row.get("missing") ?? JsonObject())
        matrix.add(reportRow)
    }

    let summary = JsonObject()
    summary.put("fullyCompatibleCount", fullyCompatibleCount.toJsonValue())
    summary.put("partiallyCompatibleCount", partiallyCompatibleCount.toJsonValue())
    summary.put("incompatibleCount", incompatibleCount.toJsonValue())

    let result = JsonObject()
    result.put("kind", JsonString("skills-compatibility-matrix"))
    result.put("agentId", JsonString(agentId))
    result.put("summary", summary)
    result.put("rows", matrix)
    result
}

private func gatewaySkillsBinsResult(agentId: String): JsonObject {
    let seen = HashMap<String, Bool>()
    let arr = JsonArray([])
    let hostBins = JsonArray([])
    let missingSandboxBins = JsonArray([])
    let skills = SkillsPrompt.listSkillDescriptors(agentId: agentId)
    for (descriptor in skills) {
        let raw = gatewaySkillsReadRaw(descriptor.location)
        let bins = gatewaySkillsBinariesFromRaw(raw)
        for (bin in bins) {
            let normalized = bin.trimAscii()
            if (normalized.isEmpty() || seen.contains(normalized)) {
                continue
            }
            seen[normalized] = true
            arr.add(JsonString(normalized))
            let available = gatewaySkillBinaryExists(normalized)
            let row = JsonObject()
            row.put("name", JsonString(normalized))
            row.put("available", available.toJsonValue())
            hostBins.add(row)
            if (!available) {
                missingSandboxBins.add(JsonString(normalized))
            }
        }
    }
    let result = JsonObject()
    result.put("bins", arr)
    result.put("hostBins", hostBins)
    result.put("sandbox", gatewaySkillsSandboxSummary(missingBins: missingSandboxBins))
    result
}

private func gatewaySkillsSearchResult(query: String, limit: Int64): JsonObject {
    let raw = searchClawHubSkillsText(SkillsSearchRequest(query: query, limit: limit, json: true))
    let parsed = JsonValue.fromStr(raw).asObject()
    let result = JsonObject()
    match (parsed.get("results")) {
        case Some(value) => result.put("results", value)
        case None =>
            match (parsed.get("items")) {
                case Some(value) => result.put("results", value)
                case None => result.put("results", JsonArray([]))
            }
    }
    result
}

private func gatewaySkillsUpdateResultsJson(results: Array<ClawHubUpdateTransportResult>): JsonArray {
    let arr = JsonArray([])
    for (item in results) {
        let row = JsonObject()
        row.put("ok", item.ok.toJsonValue())
        row.put("slug", JsonString(item.slug))
        row.put("version", JsonString(item.version))
        row.put("previousVersion", JsonString(item.previousVersion))
        row.put("targetDir", JsonString(item.targetDir))
        row.put("error", JsonString(item.error))
        arr.add(row)
    }
    arr
}

public func handleGatewaySkillsFamily(method: String, request!: Option<GatewayRpcRequest> = None): Option<GatewayRpcResponse> {
    let params = match (request) {
        case Some(req) => req.params
        case None => JsonObject()
    }
    if (method == "skills.compatibilityMatrix") {
        return Some(
            GatewayRpcResponse(
                true,
                method,
                result: gatewaySkillsCompatibilityMatrixReport(agentId: gatewaySkillsString(params, "agentId"))
            )
        )
    }
    if (method == "skills.status") {
        return Some(GatewayRpcResponse(true, method, result: gatewaySkillsStatusResult(gatewaySkillsString(params, "agentId"))))
    }
    if (method == "skills.bins") {
        return Some(GatewayRpcResponse(true, method, result: gatewaySkillsBinsResult(gatewaySkillsString(params, "agentId"))))
    }
    if (method == "skills.search") {
        let limit = gatewaySkillsInt(params, "limit", 0)
        if (limit < 0 || limit > 100) {
            return Some(GatewayRpcResponse(false, method, error: "skills.search limit must be between 1 and 100", errorCode: "INVALID_REQUEST"))
        }
        try {
            return Some(GatewayRpcResponse(true, method, result: gatewaySkillsSearchResult(gatewaySkillsString(params, "query"), limit)))
        } catch (e: Exception) {
            return Some(GatewayRpcResponse(false, method, error: e.message, errorCode: "UNAVAILABLE"))
        }
    }
    if (method == "skills.detail") {
        let slug = gatewaySkillsString(params, "slug")
        if (slug.isEmpty()) {
            return Some(GatewayRpcResponse(false, method, error: "skills.detail requires slug", errorCode: "INVALID_REQUEST"))
        }
        try {
            return Some(GatewayRpcResponse(true, method, result: fetchClawHubSkillDetailJson(slug)))
        } catch (e: Exception) {
            return Some(GatewayRpcResponse(false, method, error: e.message, errorCode: "UNAVAILABLE"))
        }
    }
    if (method == "skills.install") {
        let source = gatewaySkillsString(params, "source")
        if (!source.isEmpty() && source != "clawhub") {
            return Some(GatewayRpcResponse(false, method, error: "skills.install currently supports clawhub source only", errorCode: "INVALID_REQUEST"))
        }
        let slug = gatewaySkillsString(params, "slug")
        if (slug.isEmpty()) {
            return Some(GatewayRpcResponse(false, method, error: "skills.install requires slug", errorCode: "INVALID_REQUEST"))
        }
        let install = installClawHubSkill(
            CliConfig.cwd,
            slug,
            version: gatewaySkillsString(params, "version"),
            force: gatewaySkillsBool(params, "force", false)
        )
        if (!install.ok) {
            return Some(GatewayRpcResponse(false, method, error: install.error, errorCode: "UNAVAILABLE"))
        }
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("message", JsonString("Installed ${install.slug}@${install.version}"))
        result.put("stdout", JsonString(""))
        result.put("stderr", JsonString(""))
        result.put("code", 0.toJsonValue())
        result.put("slug", JsonString(install.slug))
        result.put("version", JsonString(install.version))
        result.put("targetDir", JsonString(install.targetDir))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "skills.update") {
        let source = gatewaySkillsString(params, "source")
        if (!source.isEmpty() && source != "clawhub") {
            return Some(GatewayRpcResponse(false, method, error: "skills.update source must be clawhub when provided", errorCode: "INVALID_REQUEST"))
        }
        let skillKey = gatewaySkillsString(params, "skillKey")
        if (source.isEmpty() && !skillKey.isEmpty()) {
            var entries = match (CliSettingManager.setting.skills.entries) {
                case Some(v) => v
                case None => JsonObject()
            }
            var current = match (entries.get(skillKey)) {
                case Some(value) =>
                    try { value.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
            if (params.get("enabled").isSome()) {
                current.put("enabled", gatewaySkillsBool(params, "enabled", true).toJsonValue())
            }
            if (params.get("apiKey").isSome()) {
                let apiKey = gatewaySkillsNormalizeSecretInput(gatewaySkillsString(params, "apiKey"))
                if (apiKey.isEmpty()) {
                    current = gatewaySkillsCloneWithoutKeys(current, ["apiKey"])
                } else {
                    current.put("apiKey", JsonString(apiKey))
                }
            }
            if (params.get("env").isSome()) {
                let envObj = gatewaySkillsNormalizedEnvMap(params)
                if (envObj.size() == 0) {
                    current = gatewaySkillsCloneWithoutKeys(current, ["env"])
                } else {
                    current.put("env", envObj)
                }
            }
            entries.put(skillKey, current)
            let ok = MetisConfigManager.setSkillsEntries(Some(entries)).isSome()
            let result = JsonObject()
            result.put("ok", ok.toJsonValue())
            result.put("skillKey", JsonString(skillKey))
            result.put("config", current)
            return Some(
                GatewayRpcResponse(
                    ok,
                    method,
                    result: result,
                    error: if (ok) { "" } else { "failed to save skills config" },
                    errorCode: if (ok) { "" } else { "WRITE_FAILED" }
                )
            )
        }
        let slug = gatewaySkillsString(params, "slug")
        let all = gatewaySkillsBool(params, "all", false)
        if (slug.isEmpty() && !all) {
            return Some(GatewayRpcResponse(false, method, error: "clawhub skills.update requires slug or all", errorCode: "INVALID_REQUEST"))
        }
        if (!slug.isEmpty() && all) {
            return Some(GatewayRpcResponse(false, method, error: "clawhub skills.update accepts either slug or all, not both", errorCode: "INVALID_REQUEST"))
        }
        let slugs = if (all) { readTrackedClawHubSkillSlugs(CliConfig.cwd) } else { [slug] }
        let results = updateClawHubSkills(CliConfig.cwd, slugs)
        var hasError = false
        let messages = ArrayList<String>()
        for (item in results) {
            if (!item.ok) {
                hasError = true
                messages.add(item.error)
            }
        }
        let config = JsonObject()
        config.put("source", JsonString("clawhub"))
        config.put("results", gatewaySkillsUpdateResultsJson(results))
        let result = JsonObject()
        result.put("ok", (!hasError).toJsonValue())
        result.put("skillKey", JsonString(if (all) { "*" } else { slug }))
        result.put("config", config)
        return Some(
            GatewayRpcResponse(
                !hasError,
                method,
                result: result,
                error: if (hasError) { String.join(messages.toArray(), delimiter: "; ") } else { "" },
                errorCode: if (hasError) { "UNAVAILABLE" } else { "" }
            )
        )
    }
    None
}
