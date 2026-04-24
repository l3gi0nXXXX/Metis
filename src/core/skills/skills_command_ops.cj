package metis.core.skills

import magic.log.LogUtils
import magic.jsonable.*

import metis.core.config.{CliConfig, MetisConfigManager}
import metis.utils.{InfoUtils, ShellUtils}

import std.collection.{ArrayList, HashMap}
import std.env.getVariable
import std.fs.{File, OpenMode, Path, exists}
import std.io.readToEnd
import std.sort.sort
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private struct ParsedSkillsCommand {
    ParsedSkillsCommand(
        let op: String,
        let arg: String
    ) {}
}

private var skillsCommandRunnerOverride: Option<(String) -> String> = None

public func setSkillsCommandRunnerForTest(runner: Option<(String) -> String>): Unit {
    skillsCommandRunnerOverride = runner
}

private func parseSkillsCommand(rawInput: String): Option<ParsedSkillsCommand> {
    let t = rawInput.trimAscii()
    let body = if (t.startsWith("/")) { t[1..] } else { t }
    let b = body.trimAscii()
    if (!b.startsWith("skills")) {
        return None
    }
    let rest = b["skills".size..].trimAscii()
    if (rest.isEmpty()) {
        return None
    }
    if (let Some(pivot) <- rest.indexOf(b' ')) {
        let op = rest[0..pivot].trimAscii().toAsciiLower()
        let arg = rest[pivot + 1..].trimAscii()
        return Some(ParsedSkillsCommand(op, arg))
    }
    Some(ParsedSkillsCommand(rest.toAsciiLower(), ""))
}

private func shellSkillsCli(command: String): String {
    let commands = ArrayList<String>()
    commands.add(command)
    // Compatibility fallback: old snapshots used `skills@rtos` which is not resolvable on npm.
    if (command.contains("skills@rtos")) {
        commands.add(command.replace("skills@rtos", "skills"))
    }

    var lastCode: Int64 = -1
    var lastErr = ""
    var lastOut = ""
    for (cmd in commands) {
        try {
            let (code, stdout, stderr) = ShellUtils.execute(
                [cmd],
                workDir: CliConfig.cwd,
                timeout: Some(Duration.second * 120),
                usePowerShellOnWindows: true
            )
            lastCode = code
            lastOut = stdout.trimAscii()
            lastErr = stderr.trimAscii()
            if (code == 0) {
                if (lastOut.isEmpty()) {
                    return "Command succeeded (no output)."
                }
                return lastOut
            }
        } catch (e: Exception) {
            LogUtils.info("skills command failed: ${e.message}")
            lastErr = e.message
            lastCode = -1
        }
    }

    if (lastCode == -1) {
        return "Command error: ${lastErr}"
    }
    if (lastErr.isEmpty()) {
        if (!lastOut.isEmpty()) {
            return "Command failed (exit=${lastCode}):\n${lastOut}"
        }
        return "Command failed (exit=${lastCode})."
    }
    if (!lastOut.isEmpty() && lastOut != lastErr) {
        return "Command failed (exit=${lastCode}):\n${lastErr}\n${lastOut}"
    }
    return "Command failed (exit=${lastCode}):\n${lastErr}"
}

private func runSkillsCommand(args: String): String {
    if (skillsCommandRunnerOverride.isSome()) {
        return skillsCommandRunnerOverride.getOrThrow()(args)
    }
    // Use npm package `skills` directly; keep fallback for historical `skills@rtos` tags.
    shellSkillsCli("npx -y skills ${args}")
}

private func appendRawCommandOutput(summary: String, rawOutput: String): String {
    let trimmed = rawOutput.trimAscii()
    if (trimmed.isEmpty() || trimmed == "Command succeeded (no output).") {
        return summary
    }
    summary + "\n\n" + trimmed
}

private func formatClawHubInstallSuccess(slug: String, rawOutput: String): String {
    let skillDir = resolveClawHubSkillInstallDir(CliConfig.cwd, slug)
    let origin = readClawHubSkillOrigin(skillDir)
    if (origin.isNone()) {
        return rawOutput
    }
    let item = origin.getOrThrow()
    let summary = "Installed ${item.slug}@${item.installedVersion}\nTarget Dir: ${skillDir}\nRegistry: ${item.registry}"
    appendRawCommandOutput(summary, rawOutput)
}

private func formatClawHubUpdateSuccess(slugs: Array<String>, rawOutput: String): String {
    let rows = ArrayList<String>()
    for (slug in slugs) {
        let origin = readClawHubSkillOrigin(resolveClawHubSkillInstallDir(CliConfig.cwd, slug))
        if (origin.isSome()) {
            let item = origin.getOrThrow()
            rows.add("${item.slug}@${item.installedVersion}")
        }
    }
    if (rows.isEmpty()) {
        return rawOutput
    }
    let summary = if (rows.size == 1) {
        "Updated ${rows[0]}"
    } else {
        "Updated tracked ClawHub skills (${rows.size})\n- " + String.join(rows.toArray(), delimiter: "\n- ")
    }
    appendRawCommandOutput(summary, rawOutput)
}

private func runSkillsFind(query: String): String {
    let request = resolveSkillsSearchRequest(query)
    if (!request.valid) {
        return "Usage: /skills search [query] [--limit <n>] [--json]"
    }
    if (skillsCommandRunnerOverride.isNone()) {
        try {
            return searchClawHubSkillsText(request)
        } catch (e: Exception) {
            LogUtils.info("ClawHub search transport failed: ${e.message}")
        }
    }
    let queryArg = if (request.query.isEmpty()) { "" } else { " ${request.query}" }
    let limitArg = if (request.limit > 0) { " --limit ${request.limit}" } else { "" }
    let jsonArg = if (request.json) { " --json" } else { "" }
    let primary = runSkillsCommand("find${queryArg}${limitArg}${jsonArg}")
    if (!primary.contains("Command failed")) {
        return primary
    }
    // Some installations expose `search` instead of `find`.
    shellSkillsCli("npx -y skills search${queryArg}${limitArg}${jsonArg}")
}

private func installedSkillVersion(skillDir: Path): String {
    let candidates = [
        skillDir.join("SKILL.md"),
        skillDir.join("skill.md"),
        skillDir.join("skills.md"),
        skillDir.join("SKILL.MD")
    ]
    for (candidate in candidates) {
        if (!exists(candidate)) {
            continue
        }
        let fm = parseFrontmatter(candidate.toString())
        let version = (fm.get("version") ?? "").trimAscii()
        if (!version.isEmpty()) {
            return version
        }
    }
    "unknown"
}

private func recordClawHubInstallIfNeeded(target: SkillsInstallTarget): Unit {
    if (target.kind != "clawhub" || target.slug.trimAscii().isEmpty()) {
        return
    }
    let skillDir = resolveClawHubSkillInstallDir(CliConfig.cwd, target.slug)
    if (!exists(skillDir)) {
        return
    }
    recordInstalledClawHubSkill(
        CliConfig.cwd,
        target.slug,
        installedSkillVersion(skillDir)
    )
}

private func runSkillsInstall(pkg: String): String {
    let request = resolveSkillsInstallRequest(pkg)
    let target = request.target.raw.trimAscii()
    if (target.isEmpty()) {
        return "Usage: /skills install <slug | owner/repo@skill>"
    }
    let installTarget = request.target
    if (skillsCommandRunnerOverride.isNone() && installTarget.kind == "clawhub") {
        let result = installClawHubSkill(
            CliConfig.cwd,
            installTarget.slug,
            version: request.version,
            force: request.force
        )
        if (result.ok) {
            SkillsPrompt.invalidate()
            return formatClawHubInstallSuccess(installTarget.slug, "")
        }
        return result.error
    }
    let versionArg = if (request.version.isEmpty()) { "" } else { " --version ${request.version}" }
    let forceArg = if (request.force) { " --force" } else { "" }
    // Primary path used by current compatible flows.
    let addResult = runSkillsCommand("add ${target}${versionArg}${forceArg} -y")
    if (!addResult.contains("Command failed")) {
        SkillsPrompt.invalidate()
        recordClawHubInstallIfNeeded(installTarget)
        if (installTarget.kind == "clawhub") {
            return formatClawHubInstallSuccess(installTarget.slug, addResult)
        }
        return addResult
    }
    // Fallback for CLI variants that expose `install` instead of `add`.
    let installResult = runSkillsCommand("install ${target}${versionArg}${forceArg} -y")
    if (!installResult.contains("Command failed")) {
        SkillsPrompt.invalidate()
        recordClawHubInstallIfNeeded(installTarget)
        if (installTarget.kind == "clawhub") {
            return formatClawHubInstallSuccess(installTarget.slug, installResult)
        }
        return installResult
    }
    // Help users when they pass only a keyword like "calendar".
    if (installTarget.kind == "clawhub") {
        return installResult + "\nHint: install also supports ClawHub slugs directly. Try: /skills search ${target}"
    }
    installResult
}

private func refreshTrackedClawHubSkills(slugs: Array<String>): Unit {
    for (slug in slugs) {
        let skillDir = resolveClawHubSkillInstallDir(CliConfig.cwd, slug)
        if (!exists(skillDir)) {
            continue
        }
        refreshTrackedClawHubSkillVersion(
            CliConfig.cwd,
            slug,
            installedSkillVersion(skillDir)
        )
    }
}

private func runSkillsUpdate(arg: String): String {
    let request = resolveSkillsUpdateRequest(arg)
    if (!request.valid) {
        return "Usage: /skills update [slug | --all]"
    }
    let trackedBefore = readTrackedClawHubSkillSlugs(CliConfig.cwd)
    let trimmed = request.slug
    if (!trimmed.isEmpty() && isLikelyClawHubSlug(trimmed) && !isTrackedClawHubSkill(CliConfig.cwd, trimmed)) {
        return "Skill \"${trimmed}\" is not tracked as a ClawHub install. Install it first with /skills install ${trimmed}"
    }
    if (skillsCommandRunnerOverride.isNone()) {
        if (request.all && trackedBefore.isEmpty()) {
            return "No tracked ClawHub skills to update."
        }
        let nativeTargets: Array<String> = if (request.all) {
            trackedBefore
        } else if (isLikelyClawHubSlug(trimmed)) {
            [trimmed]
        } else {
            Array<String>()
        }
        if (!nativeTargets.isEmpty()) {
            let results = updateClawHubSkills(CliConfig.cwd, nativeTargets)
            let failed = ArrayList<String>()
            let succeeded = ArrayList<String>()
            for (result in results) {
                if (result.ok) {
                    succeeded.add(result.slug)
                } else if (!result.error.trimAscii().isEmpty()) {
                    failed.add("${result.slug}: ${result.error}")
                }
            }
            SkillsPrompt.invalidate()
            if (!succeeded.isEmpty()) {
                let summary = formatClawHubUpdateSuccess(succeeded.toArray(), "")
                if (failed.isEmpty()) {
                    return summary
                }
                return summary + "\n\n" + String.join(failed.toArray(), delimiter: "\n")
            }
            if (!failed.isEmpty()) {
                return String.join(failed.toArray(), delimiter: "\n")
            }
        }
    }
    let updateArg = if (request.all) { "update -y" } else { "update ${trimmed} -y" }
    let out = runSkillsCommand(updateArg)
    if (!out.contains("Command failed")) {
        SkillsPrompt.invalidate()
        if (request.all) {
            refreshTrackedClawHubSkills(trackedBefore)
            return formatClawHubUpdateSuccess(trackedBefore, out)
        } else if (isLikelyClawHubSlug(trimmed)) {
            refreshTrackedClawHubSkills([trimmed])
            return formatClawHubUpdateSuccess([trimmed], out)
        }
    }
    out
}

private func sourceLabelForLocation(location: String): String {
    skillsSourceTagForLocation(location)
}

private func parseFrontmatter(path: String): HashMap<String, String> {
    let fm = HashMap<String, String>()
    let p = Path(path)
    if (!exists(p)) {
        return fm
    }
    try {
        let raw = String.fromUtf8(readToEnd(File(p, OpenMode.Read)))
        let lines = raw.split("\n")
        if (lines.isEmpty() || lines[0].trimAscii() != "---") {
            return fm
        }
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
                    let k = line[0..colon].trimAscii().toAsciiLower()
                    let v = line[colon + 1..line.size].trimAscii().replace("\"", "").replace("'", "")
                    if (!k.isEmpty()) {
                        fm[k] = v
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

private func requirementsFromFrontmatter(fm: HashMap<String, String>): Array<String> {
    let reqRaw = fm.get("requires_env") ?? ""
    if (reqRaw.trimAscii().isEmpty()) {
        return []
    }
    let out = ArrayList<String>()
    for (part in reqRaw.split(",")) {
        let key = part.trimAscii()
        if (!key.isEmpty()) {
            out.add(key)
        }
    }
    out.toArray()
}

private func readSkillRaw(path: String): String {
    let p = Path(path)
    if (!exists(p)) {
        return ""
    }
    try {
        return String.fromUtf8(readToEnd(File(p, OpenMode.Read)))
    } catch (_: Exception) {
        return ""
    }
}

private func extractQuotedValueAfter(raw: String, anchor: String): Option<String> {
    match (raw.indexOf(anchor)) {
        case None => None
        case Some(pos) =>
            let tail = raw[pos + anchor.size..]
            match (tail.indexOf("\"")) {
                case None => None
                case Some(q1) =>
                    let tail2 = tail[q1 + 1..]
                    match (tail2.indexOf("\"")) {
                        case None => None
                        case Some(q2) =>
                            let v = tail2[0..q2].trimAscii()
                            if (v.isEmpty()) { None } else { Some(v) }
                    }
            }
    }
}

private func extractEmojiFromRaw(raw: String): String {
    match (extractQuotedValueAfter(raw, "\"emoji\"")) {
        case Some(v) => return v
        case None => ()
    }
    for (line0 in raw.split("\n")) {
        let line = line0.trimAscii()
        if (line.startsWith("emoji:")) {
            let v = line["emoji:".size..].trimAscii().replace("\"", "").replace("'", "")
            if (!v.isEmpty()) {
                return v
            }
        }
    }
    ""
}

private func iconBySkillName(_name: String): String {
    // Do not hardcode per-skill icon mapping in code.
    "📦"
}

private func resolveSkillIcon(name: String, raw: String): String {
    let em = extractEmojiFromRaw(raw)
    if (!em.isEmpty()) {
        return em
    }
    iconBySkillName(name)
}

private func binariesFromRaw(raw: String): Array<String> {
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
    // The weather skill often depends on curl binary.
    if (out.isEmpty() && raw.toAsciiLower().contains("curl")) {
        out.add("curl")
    }
    out.toArray()
}

private func binaryExists(bin: String): Bool {
    if (bin.trimAscii().isEmpty()) {
        return false
    }
    try {
        let (codeWhere, _, _) = ShellUtils.execute(
            ["where ${bin}"],
            workDir: CliConfig.cwd,
            timeout: Some(Duration.second * 3),
            usePowerShellOnWindows: true
        )
        if (codeWhere == 0) {
            return true
        }
        let (codeWhich, _, _) = ShellUtils.execute(
            ["which ${bin}"],
            workDir: CliConfig.cwd,
            timeout: Some(Duration.second * 3),
            usePowerShellOnWindows: true
        )
        codeWhich == 0
    } catch (_: Exception) {
        false
    }
}

private func statusFromRequirements(requirements: Array<String>, bins: Array<String>): String {
    if (requirements.isEmpty()) {
        for (bin in bins) {
            if (!binaryExists(bin)) {
                return "missing"
            }
        }
        return "ready"
    }
    for (key in requirements) {
        if (getVariable(key).isNone()) {
            return "missing"
        }
    }
    for (bin in bins) {
        if (!binaryExists(bin)) {
            return "missing"
        }
    }
    "ready"
}

private func configuredEnvRequirementSatisfied(descriptor: SkillDescriptor, key0: String): Bool {
    let key = key0.trimAscii()
    if (key.isEmpty()) {
        return true
    }
    if (getVariable(key).isSome()) {
        return true
    }
    match (descriptor.configuredEnv) {
        case Some(envObj) =>
            match (envObj.get(key)) {
                case Some(value) =>
                    try {
                        if (!value.asString().getValue().trimAscii().isEmpty()) {
                            return true
                        }
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
        case None => ()
    }
    !descriptor.primaryEnv.trimAscii().isEmpty() &&
        descriptor.primaryEnv == key &&
        !descriptor.configuredApiKey.trimAscii().isEmpty()
}

private func configuredConfigRequirementSatisfied(path0: String): Bool {
    let path = path0.trimAscii()
    if (path.isEmpty()) {
        return true
    }
    let root = MetisConfigManager.rawConfig() ?? JsonObject()
    let defaultTruthy = HashMap<String, Bool>()
    defaultTruthy["browser.enabled"] = true
    defaultTruthy["browser.evaluateEnabled"] = true
    var current: JsonValue = root
    var found = true
    for (segment0 in path.split(".")) {
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
        return defaultTruthy.contains(path) && defaultTruthy[path]
    }
    try {
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
}

private func statusFromDescriptor(descriptor: SkillDescriptor, bins: Array<String>): String {
    for (key in descriptor.requiredEnv) {
        if (!configuredEnvRequirementSatisfied(descriptor, key)) {
            return "missing"
        }
    }
    for (path in descriptor.requiredConfig) {
        if (!configuredConfigRequirementSatisfied(path)) {
            return "missing"
        }
    }
    for (bin in descriptor.requiredBins) {
        if (!binaryExists(bin)) {
            return "missing"
        }
    }
    if (!descriptor.requiredAnyBins.isEmpty()) {
        var anyOk = false
        for (bin in descriptor.requiredAnyBins) {
            if (binaryExists(bin)) {
                anyOk = true
                break
            }
        }
        if (!anyOk) {
            return "missing"
        }
    }
    statusFromRequirements([], bins)
}

private func repeatChar(ch: Rune, count: Int64): String {
    let sb = StringBuilder()
    var i: Int64 = 0
    while (i < count) {
        sb.append(ch.toString())
        i += 1
    }
    sb.toString()
}

private func padRight(text: String, width: Int64): String {
    if (text.size >= width) {
        return text
    }
    text + repeatChar(r' ', width - text.size)
}

private func wrapText(text: String, width: Int64): Array<String> {
    let t = text.trimAscii()
    if (t.isEmpty()) {
        return [""]
    }
    let out = ArrayList<String>()
    var line = ""
    for (word0 in t.split(" ")) {
        let word = word0.trimAscii()
        if (word.isEmpty()) {
            continue
        }
        if (line.isEmpty()) {
            if (word.size <= width) {
                line = word
            } else {
                var rest = word
                while (rest.size > width) {
                    out.add(rest[0..width])
                    rest = rest[width..]
                }
                line = rest
            }
            continue
        }

        let candidate = line + " " + word
        if (candidate.size <= width) {
            line = candidate
            continue
        }
        out.add(line)
        if (word.size <= width) {
            line = word
        } else {
            var rest = word
            while (rest.size > width) {
                out.add(rest[0..width])
                rest = rest[width..]
            }
            line = rest
        }
    }
    if (!line.isEmpty()) {
        out.add(line)
    }
    if (out.isEmpty()) {
        return [""]
    }
    out.toArray()
}

private func tableBorder(col1: Int64, col2: Int64, col3: Int64, col4: Int64): String {
    "+" + repeatChar(r'-', col1 + 2) +
        "+" + repeatChar(r'-', col2 + 2) +
        "+" + repeatChar(r'-', col3 + 2) +
        "+" + repeatChar(r'-', col4 + 2) + "+"
}

private func ansi(text: String, code: String): String {
    "\u{001b}[${code}m${text}\u{001b}[0m"
}

// Unified CLI color tokens.
private func colorReady(text: String): String {
    ansi(text, "38;5;48")
}

private func colorAccent(text: String): String {
    ansi(text, "38;5;214")
}

private func colorMuted(text: String): String {
    ansi(text, "38;5;242")
}

private func colorSource(text: String): String {
    ansi(text, "38;5;240")
}

private func listSkillIcon(fm: HashMap<String, String>, raw: String): String {
    let icon = (fm.get("icon") ?? fm.get("emoji") ?? "").trimAscii()
    if (!icon.isEmpty()) {
        return icon
    }
    let em = extractEmojiFromRaw(raw).trimAscii()
    if (!em.isEmpty()) {
        return em
    }
    "*"
}

private func trailingSpaces(width: Int64, contentSize: Int64): String {
    if (contentSize >= width) {
        return ""
    }
    repeatChar(r' ', width - contentSize)
}

private func colorMissing(text: String): String {
    ansi(text, "38;5;203")
}

private func colorSection(text: String): String {
    ansi(text, "38;5;208")
}

private func colorWarn(text: String): String {
    ansi(text, "38;5;220")
}

private func formatList(): String {
    let list = SkillsPrompt.listSkillDescriptors()
    let sb = StringBuilder()
    if (list.isEmpty()) {
        sb.append("Skills (0/0 ready)\n")
        sb.append("+-----------+-----------------------+-------------------------------------------------------------------------------------------+------------------------+\n")
        sb.append("| Status    | Skill                 | Description                                                                               | Source                 |\n")
        sb.append("+-----------+-----------------------+-------------------------------------------------------------------------------------------+------------------------+")
        return sb.toString()
    }

    let statusW: Int64 = 9
    let skillW: Int64 = 21
    let descW: Int64 = 89
    let srcW: Int64 = 22
    let border = tableBorder(statusW, skillW, descW, srcW)

    let rows = ArrayList<(String, String, String, String, String)>()
    var readyCount: Int64 = 0
    if (list.isEmpty()) {
        // no-op
    }
    for (d in list) {
        let fm = parseFrontmatter(d.location)
        let req = requirementsFromFrontmatter(fm)
        let raw = readSkillRaw(d.location)
        let bins = binariesFromRaw(raw)
        let status = statusFromDescriptor(d, bins)
        let source = d.source
        if (status == "ready") {
            readyCount += 1
        }
        // Keep status strictly ASCII to stabilize terminal width calculation.
        let statusLabel = if (status == "ready") { "v ready" } else { "x missing" }
        // Keep a fixed icon slot (no brackets) to avoid row-content left drift.
        let skillLabel = " ${padRight(listSkillIcon(fm, raw), 2)} ${d.name}"
        rows.add((statusLabel, skillLabel, d.description, source, status))
    }

    sb.append("Skills (${readyCount}/${list.size} ready)\n")
    sb.append("${border}\n")
    sb.append("| ${padRight("Status", statusW)} | ${padRight("Skill", skillW)} | ${padRight("Description", descW)} | ${padRight("Source", srcW)} |\n")
    sb.append("${border}\n")

    // Preferred ordering: ready first, then missing.
    let readyRows = ArrayList<(String, String, String, String, String)>()
    let missingRows = ArrayList<(String, String, String, String, String)>()
    for ((statusText0, skillText0, descText0, sourceText0, statusRaw0) in rows) {
        let row = (statusText0, skillText0, descText0, sourceText0, statusRaw0)
        if (statusRaw0 == "ready") {
            readyRows.add(row)
        } else {
            missingRows.add(row)
        }
    }
    let orderedRows = ArrayList<(String, String, String, String, String)>()
    for (r in readyRows) { orderedRows.add(r) }
    for (r in missingRows) { orderedRows.add(r) }

    for ((statusText, skillText, descText, sourceText, statusRaw) in orderedRows) {
        let descLines = wrapText(descText, descW)
        var idx: Int64 = 0
        while (idx < descLines.size) {
            let s = if (idx == 0) { statusText } else { "" }
            let k = if (idx == 0) { skillText } else { "" }
            let src = if (idx == 0) { sourceText } else { "" }
            let statusSpaces = trailingSpaces(statusW, s.size)
            let skillSpaces = trailingSpaces(skillW, k.size)
            let descText = descLines[idx]
            let descSpaces = trailingSpaces(descW, descText.size)
            let statusColored = if (s.isEmpty()) {
                repeatChar(r' ', statusW)
            } else if (statusRaw == "ready") {
                colorReady(s) + statusSpaces
            } else {
                colorMissing(s) + statusSpaces
            }
            let skillColored = if (k.isEmpty()) {
                repeatChar(r' ', skillW)
            } else {
                colorAccent(k) + skillSpaces
            }
            let descColored = if (descText.isEmpty()) {
                repeatChar(r' ', descW)
            } else {
                colorMuted(descText) + descSpaces
            }
            let sourceColored = padRight(src, srcW)
            sb.append(
                "| ${statusColored} | ${skillColored} | ${descColored} | ${sourceColored} |\n"
            )
            idx += 1
        }
    }
    sb.append("${border}")
    sb.toString().trimAscii()
}

private func formatInfo(skillName: String): String {
    let target = skillName.trimAscii().toAsciiLower()
    if (target.isEmpty()) {
        return "Usage: /skills info <skillName>"
    }
    let list = SkillsPrompt.listSkillDescriptors()
    for (d in list) {
        if (d.name.toAsciiLower() != target) {
            continue
        }
        let sb = StringBuilder()
        let fm = parseFrontmatter(d.location)
        let req = d.requiredEnv
        let raw = readSkillRaw(d.location)
        let bins = if (d.requiredBins.isEmpty() && d.requiredAnyBins.isEmpty()) {
            binariesFromRaw(raw)
        } else {
            let merged = ArrayList<String>()
            let seen = HashMap<String, Bool>()
            for (bin in d.requiredBins) {
                let normalized = bin.trimAscii()
                if (!normalized.isEmpty() && !seen.contains(normalized)) {
                    seen[normalized] = true
                    merged.add(normalized)
                }
            }
            for (bin in d.requiredAnyBins) {
                let normalized = bin.trimAscii()
                if (!normalized.isEmpty() && !seen.contains(normalized)) {
                    seen[normalized] = true
                    merged.add(normalized)
                }
            }
            merged.toArray()
        }
        let status = statusFromDescriptor(d, bins)
        let source = d.source
        let emoji = resolveSkillIcon(d.name, raw)
        let homepage = if (d.homepage.trimAscii().isEmpty()) { fm.get("homepage") ?? "" } else { d.homepage }
        let origin = readClawHubSkillOrigin(Path(d.location).parent)
        let icon = if (emoji.isEmpty()) { "❁" } else { emoji }
        let namePart = colorAccent("${icon} ${d.name}")
        let readyPart = if (status == "ready") { colorReady("✓ Ready") } else { colorMissing("✗ Missing") }
        sb.append("${namePart} / ${readyPart}\n")
        sb.append("\n")
        sb.append("${colorMuted(d.description)}\n")
        sb.append("\n")
        sb.append("${colorSection("Details:")}\n")
        sb.append("${colorMuted("  Source: ${source}")}\n")
        sb.append("${colorMuted("  Path: ${d.location}")}\n")
        sb.append("${colorMuted("  Skill Key: ${d.skillKey}")}\n")
        sb.append("${colorMuted("  Primary Env: ${if (d.primaryEnv.trimAscii().isEmpty()) { "-" } else { d.primaryEnv }}")}\n")
        match (origin) {
            case Some(item) =>
                sb.append("${colorMuted("  ClawHub Slug: ${item.slug}")}\n")
                sb.append("${colorMuted("  Registry: ${item.registry}")}\n")
                sb.append("${colorMuted("  Installed Version: ${item.installedVersion}")}\n")
            case None => ()
        }
        sb.append("${colorMuted("  Homepage: ${if (homepage.trimAscii().isEmpty()) { "-" } else { homepage }}")}\n")
        sb.append("\n")
        sb.append("${colorSection("Requirements:")}\n")
        if (bins.isEmpty()) {
            sb.append("${colorMuted("  Binaries: -")}\n")
        } else {
            let checks = StringBuilder()
            var idx: Int64 = 0
            for (bin in bins) {
                if (idx > 0) {
                    checks.append(", ")
                }
                let mark = if (binaryExists(bin)) { colorReady("✓") } else { colorMissing("✗") }
                checks.append("${mark} ${bin}")
                idx += 1
            }
            sb.append("${colorMuted("  Binaries: ")}${checks.toString()}\n")
        }
        for (r in req) {
            let ok = configuredEnvRequirementSatisfied(d, r)
            let envMark = if (ok) { colorReady("✓ present") } else { colorMissing("✗ missing") }
            sb.append("${colorMuted("  Env ${r}: ")}${envMark}\n")
        }
        if (!d.configuredApiKey.trimAscii().isEmpty() || d.configuredEnv.isSome() || d.configuredConfig.isSome()) {
            sb.append("\n")
            sb.append("${colorSection("Configured Overrides:")}\n")
            sb.append("${colorMuted("  API Key: ${if (d.configuredApiKey.trimAscii().isEmpty()) { "-" } else { "[configured]" }}")}\n")
            match (d.configuredEnv) {
                case Some(envObj) =>
                    let keys = ArrayList<String>()
                    for ((key, _) in envObj.getFields()) {
                        keys.add(key)
                    }
                    sort(keys)
                    sb.append("${colorMuted("  Env Keys: ${if (keys.isEmpty()) { "-" } else { String.join(keys.toArray(), delimiter: ", ") }}")}\n")
                case None =>
                    sb.append("${colorMuted("  Env Keys: -")}\n")
            }
            match (d.configuredConfig) {
                case Some(configObj) =>
                    let keys = ArrayList<String>()
                    for ((key, _) in configObj.getFields()) {
                        keys.add(key)
                    }
                    sort(keys)
                    sb.append("${colorMuted("  Config Keys: ${if (keys.isEmpty()) { "-" } else { String.join(keys.toArray(), delimiter: ", ") }}")}\n")
                case None =>
                    sb.append("${colorMuted("  Config Keys: -")}\n")
            }
        }
        sb.append("\n")
        sb.append("${colorMuted("Tip: use `metis skills search`, `metis skills install`, and `metis skills update` for ClawHub-backed skills.")}\n")
        return sb.toString().trimAscii()
    }
    "Skill not found: ${skillName}"
}

private func missingReasonForSkill(raw: String, req: Array<String>, bins: Array<String>): String {
    let reasons = ArrayList<String>()
    if (!bins.isEmpty()) {
        let missingBins = ArrayList<String>()
        for (bin in bins) {
            if (!binaryExists(bin)) {
                missingBins.add(bin)
            }
        }
        if (!missingBins.isEmpty()) {
            let sb = StringBuilder()
            var i: Int64 = 0
            for (b in missingBins) {
                if (i > 0) {
                    sb.append(", ")
                }
                sb.append(b)
                i += 1
            }
            reasons.add("bins: ${sb.toString()}")
        }
    }
    if (!req.isEmpty()) {
        let missingEnv = ArrayList<String>()
        for (key in req) {
            if (getVariable(key).isNone()) {
                missingEnv.add(key)
            }
        }
        if (!missingEnv.isEmpty()) {
            let sb = StringBuilder()
            var i: Int64 = 0
            for (k in missingEnv) {
                if (i > 0) {
                    sb.append(", ")
                }
                sb.append(k)
                i += 1
            }
            reasons.add("env: ${sb.toString()}")
        }
    }
    let lower = raw.toAsciiLower()
    if (lower.contains("\"os\"") && lower.contains("darwin")) {
        reasons.add("os: darwin")
    }
    if (lower.contains("bluebubbles")) {
        reasons.add("config: channels.bluebubbles")
    }
    if (lower.contains("discord.token")) {
        reasons.add("config: channels.discord.token")
    }
    if (reasons.isEmpty()) {
        return "requirements: unknown"
    }
    let sb = StringBuilder()
    var idx: Int64 = 0
    for (r in reasons) {
        if (idx > 0) {
            sb.append("; ")
        }
        sb.append(r)
        idx += 1
    }
    sb.toString()
}

private func missingReasonForDescriptor(descriptor: SkillDescriptor, raw: String, bins: Array<String>): String {
    let reasons = ArrayList<String>()
    let missingEnv = ArrayList<String>()
    for (key in descriptor.requiredEnv) {
        if (!configuredEnvRequirementSatisfied(descriptor, key)) {
            missingEnv.add(key)
        }
    }
    if (!missingEnv.isEmpty()) {
        reasons.add("env: " + String.join(missingEnv.toArray(), delimiter: ", "))
    }
    let missingBins = ArrayList<String>()
    for (bin in descriptor.requiredBins) {
        if (!binaryExists(bin)) {
            missingBins.add(bin)
        }
    }
    if (!missingBins.isEmpty()) {
        reasons.add("bins: " + String.join(missingBins.toArray(), delimiter: ", "))
    }
    if (!descriptor.requiredAnyBins.isEmpty()) {
        var anyOk = false
        for (bin in descriptor.requiredAnyBins) {
            if (binaryExists(bin)) {
                anyOk = true
                break
            }
        }
        if (!anyOk) {
            reasons.add("anyBins: " + String.join(descriptor.requiredAnyBins, delimiter: ", "))
        }
    }
    let missingConfig = ArrayList<String>()
    for (path in descriptor.requiredConfig) {
        if (!configuredConfigRequirementSatisfied(path)) {
            missingConfig.add(path)
        }
    }
    if (!missingConfig.isEmpty()) {
        reasons.add("config: " + String.join(missingConfig.toArray(), delimiter: ", "))
    }
    if (reasons.isEmpty()) {
        return missingReasonForSkill(raw, descriptor.requiredEnv, bins)
    }
    String.join(reasons.toArray(), delimiter: "; ")
}

private func doctorActionsForDescriptor(descriptor: SkillDescriptor, bins: Array<String>): Array<String> {
    let actions = ArrayList<String>()
    let configKey = if (descriptor.skillKey.trimAscii().isEmpty()) { descriptor.name } else { descriptor.skillKey }
    let missingEnv = ArrayList<String>()
    for (key in descriptor.requiredEnv) {
        if (!configuredEnvRequirementSatisfied(descriptor, key)) {
            missingEnv.add(key)
            actions.add("configure skills.entries.${configKey}.env.${key} or provide shell env ${key}")
        }
    }
    if (!descriptor.primaryEnv.trimAscii().isEmpty() &&
        missingEnv.contains(descriptor.primaryEnv) &&
        descriptor.configuredApiKey.trimAscii().isEmpty()
    ) {
        actions.add("configure skills.entries.${configKey}.apiKey for ${descriptor.primaryEnv}")
    }
    for (bin in descriptor.requiredBins) {
        if (!binaryExists(bin)) {
            actions.add("install required binary ${bin}")
        }
    }
    if (!descriptor.requiredAnyBins.isEmpty()) {
        var anyOk = false
        for (bin in descriptor.requiredAnyBins) {
            if (binaryExists(bin)) {
                anyOk = true
                break
            }
        }
        if (!anyOk) {
            actions.add("install at least one of: " + String.join(descriptor.requiredAnyBins, delimiter: ", "))
        }
    }
    for (path in descriptor.requiredConfig) {
        if (!configuredConfigRequirementSatisfied(path)) {
            actions.add("set config path ${path} to a truthy value")
        }
    }
    actions.toArray()
}

private func installRiskString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func checkReportString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func installRiskStringArray(obj: JsonObject, key: String): Array<String> {
    let result = ArrayList<String>()
    match (obj.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                for (i in 0..arr.size()) {
                    try {
                        let item = arr[i].asString().getValue().trimAscii()
                        if (!item.isEmpty()) {
                            result.add(item)
                        }
                    } catch (_: Exception) {
                    }
                }
            } catch (_: Exception) {
            }
        case None => ()
    }
    result.toArray()
}

private func installRiskMessageForDescriptor(descriptor: SkillDescriptor): String {
    let (level, message) = installRiskForDescriptor(descriptor)
    if (level == "none" || level == "safe") {
        return ""
    }
    message
}

private func installRiskForDescriptor(descriptor: SkillDescriptor): (String, String) {
    let installSpecs = descriptor.installSpecs
    if (installSpecs.isEmpty()) {
        return ("none", "")
    }
    let currentPlatform = match (InfoUtils.os) {
        case "macos" => "darwin"
        case "windows" => "win32"
        case "linux" => "linux"
        case _ => "unknown"
    }
    let requiredOs = descriptor.requiredOs
    if (!requiredOs.isEmpty() && !requiredOs.contains(currentPlatform)) {
        return ("none", "")
    }
    for (spec in installSpecs) {
        let specOs = installRiskStringArray(spec, "os")
        if (!specOs.isEmpty() && !specOs.contains(currentPlatform)) {
            continue
        }
        let kind = installRiskString(spec, "kind")
        if (kind == "download") {
            return ("warn", "review installer source before running direct download")
        }
        if (kind == "node") {
            return ("caution", "review package installer before running node-based install")
        }
        if (kind == "brew" || kind == "uv" || kind == "go") {
            return ("safe", "installer uses managed package tooling")
        }
    }
    ("none", "")
}

private func checkReportJson(): JsonObject {
    let list = SkillsPrompt.listSkillDescriptors()
    let total = list.size
    let readyRows = ArrayList<String>()
    let missingRows = ArrayList<String>()
    let installerReviewRows = ArrayList<String>()
    let readyJson = JsonArray([])
    let missingJson = JsonArray([])
    let installerReviewJson = JsonArray([])
    var disabledCount: Int64 = 0
    var missingCount: Int64 = 0
    var safeInstallRiskCount: Int64 = 0
    var cautionInstallRiskCount: Int64 = 0
    var warnInstallRiskCount: Int64 = 0
    var noneInstallRiskCount: Int64 = 0

    for (d in list) {
        if (!d.enabled) {
            disabledCount += 1
            continue
        }
        let raw = readSkillRaw(d.location)
        let bins = if (d.requiredBins.isEmpty() && d.requiredAnyBins.isEmpty()) {
            binariesFromRaw(raw)
        } else {
            let merged = ArrayList<String>()
            let seen = HashMap<String, Bool>()
            for (bin in d.requiredBins) {
                let normalized = bin.trimAscii()
                if (!normalized.isEmpty() && !seen.contains(normalized)) {
                    seen[normalized] = true
                    merged.add(normalized)
                }
            }
            for (bin in d.requiredAnyBins) {
                let normalized = bin.trimAscii()
                if (!normalized.isEmpty() && !seen.contains(normalized)) {
                    seen[normalized] = true
                    merged.add(normalized)
                }
            }
            merged.toArray()
        }
        let status = statusFromDescriptor(d, bins)
        let (installRiskLevel, installRiskMessage) = installRiskForDescriptor(d)
        if (installRiskLevel == "safe") {
            safeInstallRiskCount += 1
        } else if (installRiskLevel == "caution") {
            cautionInstallRiskCount += 1
        } else if (installRiskLevel == "warn") {
            warnInstallRiskCount += 1
        } else {
            noneInstallRiskCount += 1
        }
        let icon = resolveSkillIcon(d.name, raw)
        if (status == "ready") {
            readyRows.add("  ${icon} ${d.name}")
            let readyObj = JsonObject()
            readyObj.put("name", d.name.toJsonValue())
            readyObj.put("icon", icon.toJsonValue())
            readyJson.add(readyObj)
            if (installRiskLevel == "caution" || installRiskLevel == "warn") {
                installerReviewRows.add("  ${icon} ${d.name} (${installRiskLevel}: ${installRiskMessage})")
                let reviewObj = JsonObject()
                reviewObj.put("name", d.name.toJsonValue())
                reviewObj.put("icon", icon.toJsonValue())
                reviewObj.put("level", installRiskLevel.toJsonValue())
                reviewObj.put("message", installRiskMessage.toJsonValue())
                installerReviewJson.add(reviewObj)
            }
        } else {
            let reason = missingReasonForDescriptor(d, raw, bins)
            let actions = doctorActionsForDescriptor(d, bins)
            let row = StringBuilder()
            row.append("  ${icon} ${d.name} (${reason})")
            if (!actions.isEmpty() || !installRiskMessage.isEmpty()) {
                let details = ArrayList<String>()
                for (action in actions) {
                    details.add(action)
                }
                if (!installRiskMessage.isEmpty()) {
                    details.add(installRiskMessage)
                }
                row.append("\n      fix: " + String.join(details.toArray(), delimiter: " | "))
            }
            missingRows.add(row.toString())
            let missingObj = JsonObject()
            missingObj.put("name", d.name.toJsonValue())
            missingObj.put("icon", icon.toJsonValue())
            missingObj.put("reason", reason.toJsonValue())
            let actionsJson = JsonArray([])
            for (action in actions) {
                actionsJson.add(action.toJsonValue())
            }
            if (!installRiskMessage.isEmpty()) {
                actionsJson.add(installRiskMessage.toJsonValue())
            }
            missingObj.put("doctorActions", actionsJson)
            missingJson.add(missingObj)
            missingCount += 1
        }
    }

    let report = JsonObject()
    report.put("kind", JsonString("skills-check"))
    report.put("total", JsonString(total.toString()))
    report.put("eligibleCount", JsonString(readyRows.size.toString()))
    report.put("disabledCount", JsonString(disabledCount.toString()))
    report.put("blockedByAllowlistCount", JsonString("0"))
    report.put("missingRequirementsCount", JsonString(missingCount.toString()))
    let installRisk = JsonObject()
    installRisk.put("safeCount", JsonString(safeInstallRiskCount.toString()))
    installRisk.put("cautionCount", JsonString(cautionInstallRiskCount.toString()))
    installRisk.put("warnCount", JsonString(warnInstallRiskCount.toString()))
    installRisk.put("noneCount", JsonString(noneInstallRiskCount.toString()))
    report.put("installRisk", installRisk)
    report.put("ready", readyJson)
    report.put("missing", missingJson)
    report.put("installerReview", installerReviewJson)
    report
}

private func formatCheckFromReport(report: JsonObject): String {
    let total = checkReportString(report, "total")
    let eligibleCount = checkReportString(report, "eligibleCount")
    let disabledCount = checkReportString(report, "disabledCount")
    let missingCount = checkReportString(report, "missingRequirementsCount")
    let installRisk = report.get("installRisk").getOrThrow().asObject()
    let safeInstallRiskCount = checkReportString(installRisk, "safeCount")
    let cautionInstallRiskCount = checkReportString(installRisk, "cautionCount")
    let warnInstallRiskCount = checkReportString(installRisk, "warnCount")
    let noneInstallRiskCount = checkReportString(installRisk, "noneCount")
    let ready = report.get("ready").getOrThrow().asArray()
    let missing = report.get("missing").getOrThrow().asArray()
    let installerReview = report.get("installerReview").getOrThrow().asArray()
    let sb = StringBuilder()
    sb.append("${ansi("Skills Status Check", "38;5;208")}\n\n")
    sb.append("${ansi("Total: ${total}", "90")}\n")
    sb.append("${ansi("✓ Eligible: ${eligibleCount}", "32")}\n")
    sb.append("${ansi("⚠ Disabled: ${disabledCount}", "33")}\n")
    sb.append("${ansi("○ Blocked by allowlist: 0", "33")}\n")
    sb.append("${ansi("✗ Missing requirements: ${missingCount}", "31")}\n\n")
    sb.append("${ansi("Installer risk: safe=${safeInstallRiskCount} caution=${cautionInstallRiskCount} warn=${warnInstallRiskCount} none=${noneInstallRiskCount}", "90")}\n\n")
    sb.append("${ansi("Ready to use:", "38;5;208")}\n")
    if (ready.size() == 0) {
        sb.append("  (none)\n")
    } else {
        for (i in 0..ready.size()) {
            let row = ready[i].asObject()
            sb.append("  ${checkReportString(row, "icon")} ${checkReportString(row, "name")}\n")
        }
    }
    sb.append("\n${ansi("Missing requirements:", "38;5;208")}\n")
    if (missing.size() == 0) {
        sb.append("  (none)\n")
    } else {
        for (i in 0..missing.size()) {
            let row = missing[i].asObject()
            sb.append("  ${checkReportString(row, "icon")} ${checkReportString(row, "name")} (${checkReportString(row, "reason")})")
            let actions = row.get("doctorActions").getOrThrow().asArray()
            if (actions.size() > 0) {
                let actionRows = ArrayList<String>()
                for (j in 0..actions.size()) {
                    actionRows.add(actions[j].asString().getValue())
                }
                sb.append("\n      fix: " + String.join(actionRows.toArray(), delimiter: " | "))
            }
            sb.append("\n")
        }
    }
    sb.append("\n${ansi("Installer review:", "38;5;208")}\n")
    if (installerReview.size() == 0) {
        sb.append("  (none)\n")
    } else {
        for (i in 0..installerReview.size()) {
            let row = installerReview[i].asObject()
            sb.append("  ${checkReportString(row, "icon")} ${checkReportString(row, "name")} (${checkReportString(row, "level")}: ${checkReportString(row, "message")})\n")
        }
    }
    sb.toString().trimAscii()
}

private func formatCheck(): String {
    formatCheckFromReport(checkReportJson())
}

public func tryHandleSkillsCommand(rawInput: String): Option<String> {
    match (parseSkillsCommand(rawInput)) {
        case None => None
        case Some(cmd) =>
            let op = cmd.op
            let arg = cmd.arg
            if (op == "list") {
                return Some(formatList())
            }
            if (op == "info") {
                return Some(formatInfo(arg))
            }
            if (op == "check") {
                if (arg.trimAscii() == "--json") {
                    return Some(checkReportJson().toString())
                }
                if (!arg.trimAscii().isEmpty()) {
                    return Some("Usage: /skills check [--json]")
                }
                return Some(formatCheck())
            }
            if (op == "search") {
                return Some(runSkillsFind(arg))
            }
            if (op == "install") {
                if (arg.isEmpty()) {
                    return Some("Usage: /skills install <slug | owner/repo@skill>")
                }
                return Some(runSkillsInstall(arg))
            }
            if (op == "update") {
                return Some(runSkillsUpdate(arg))
            }
            Some("Unknown skills subcommand: ${op}\nSupported: list, info, check, search, install, update")
    }
}
