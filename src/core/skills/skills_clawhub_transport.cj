package metis.core.skills

import magic.log.LogUtils
import magic.utils.http.HttpUtils

import metis.core.config.CliConfig
import metis.utils.ShellUtils

import std.collection.{ArrayList, HashMap}
import std.fs.{copy, Directory, exists, FileInfo, Path, remove}
import std.time.*

import stdx.encoding.json.{JsonArray, JsonInt, JsonObject, JsonString, JsonValue}

private let CLAWHUB_BASE_URL = "https://clawhub.ai"
private let CLAWHUB_USER_AGENT = "Metis-Skills/1.0"

private var clawHubHttpGetOverride: Option<(String) -> String> = None
private var clawHubArchiveRootOverride: Option<(String, String) -> Path> = None

public struct ClawHubInstallTransportResult {
    public let ok: Bool
    public let slug: String
    public let version: String
    public let targetDir: String
    public let error: String

    public init(
        ok: Bool,
        slug!: String = "",
        version!: String = "",
        targetDir!: String = "",
        error!: String = ""
    ) {
        this.ok = ok
        this.slug = slug
        this.version = version
        this.targetDir = targetDir
        this.error = error
    }
}

public struct ClawHubUpdateTransportResult {
    public let ok: Bool
    public let slug: String
    public let version: String
    public let previousVersion: String
    public let targetDir: String
    public let error: String

    public init(
        ok: Bool,
        slug!: String = "",
        version!: String = "",
        previousVersion!: String = "",
        targetDir!: String = "",
        error!: String = ""
    ) {
        this.ok = ok
        this.slug = slug
        this.version = version
        this.previousVersion = previousVersion
        this.targetDir = targetDir
        this.error = error
    }
}

public func setClawHubHttpGetForTest(fetcher: Option<(String) -> String>): Unit {
    clawHubHttpGetOverride = fetcher
}

public func setClawHubArchiveRootForTest(resolver: Option<(String, String) -> Path>): Unit {
    clawHubArchiveRootOverride = resolver
}

private func clawHubRequestHeaders(accept: String): HashMap<String, String> {
    HashMap<String, String>([
        ("User-Agent", CLAWHUB_USER_AGENT),
        ("Accept", accept)
    ])
}

private func clawHubUrlEncode(raw: String): String {
    let sb = StringBuilder()
    for (ch in raw.toArray()) {
        if ((ch >= b'a' && ch <= b'z') ||
            (ch >= b'A' && ch <= b'Z') ||
            (ch >= b'0' && ch <= b'9') ||
            ch == b'-' || ch == b'_' || ch == b'.' || ch == b'~') {
            sb.append(String.fromUtf8([ch]))
            continue
        }
        sb.append("%")
        let high = ch / 16
        let low = ch % 16
        sb.append(if (high < 10) { String.fromUtf8([b'0' + high]) } else { String.fromUtf8([b'A' + (high - 10)]) })
        sb.append(if (low < 10) { String.fromUtf8([b'0' + low]) } else { String.fromUtf8([b'A' + (low - 10)]) })
    }
    sb.toString()
}

private func clawHubHttpGet(url: String, accept: String): String {
    if (clawHubHttpGetOverride.isSome()) {
        return clawHubHttpGetOverride.getOrThrow()(url)
    }
    match (HttpUtils.get(url, clawHubRequestHeaders(accept), None, verify: false)) {
        case Some(raw) => raw
        case None => throw Exception("ClawHub request returned empty response")
    }
}

private func extractString(obj: JsonObject, key: String): Option<String> {
    if (let Some(value) <- obj.get(key)) {
        match (value) {
            case jsonStr: JsonString => Some(jsonStr.getValue())
            case _ => None
        }
    } else {
        None
    }
}

private func extractInt64(obj: JsonObject, key: String): Option<Int64> {
    if (let Some(value) <- obj.get(key)) {
        match (value) {
            case jsonInt: JsonInt => Some(jsonInt.getValue())
            case _ => None
        }
    } else {
        None
    }
}

private func parseClawHubSearchResults(raw: String): Array<JsonObject> {
    let parsed = JsonValue.fromStr(raw)
    match (parsed) {
        case root: JsonObject =>
            if (let Some(resultsValue) <- root.get("results")) {
                let arr = resultsValue as JsonArray
                if (let Some(items) <- arr) {
                    let out = ArrayList<JsonObject>()
                    for (i in 0..items.size()) {
                        let obj = items[i] as JsonObject
                        if (let Some(entryObj) <- obj) {
                            out.add(entryObj)
                        }
                    }
                    return out.toArray()
                }
            }
            if (let Some(itemsValue) <- root.get("items")) {
                let arr = itemsValue as JsonArray
                if (let Some(items) <- arr) {
                    let out = ArrayList<JsonObject>()
                    for (i in 0..items.size()) {
                        let obj = items[i] as JsonObject
                        if (let Some(entryObj) <- obj) {
                            out.add(entryObj)
                        }
                    }
                    return out.toArray()
                }
            }
            []
        case _ => []
    }
}

private func parseLatestSkillVersion(raw: String): String {
    let parsed = JsonValue.fromStr(raw)
    match (parsed) {
        case root: JsonObject =>
            if (let Some(latestValue) <- root.get("latestVersion")) {
                if (let Some(latestObj) <- (latestValue as JsonObject)) {
                    return extractString(latestObj, "version") ?? ""
                }
            }
            ""
        case _ => ""
    }
}

private func hasSkillFile(dir: Path): Bool {
    exists(dir.join("SKILL.md")) ||
    exists(dir.join("skill.md")) ||
    exists(dir.join("skills.md")) ||
    exists(dir.join("SKILL.MD"))
}

private func findExtractedSkillRoot(root: Path): Option<Path> {
    if (hasSkillFile(root)) {
        return Some(root)
    }
    for (entry in Directory.readFrom(root)) {
        if (!entry.isDirectory()) {
            continue
        }
        match (findExtractedSkillRoot(entry.path)) {
            case Some(hit) => return Some(hit)
            case None => ()
        }
    }
    None
}

private func copyTree(from: Path, to: Path): Unit {
    let info = FileInfo(from)
    if (info.isDirectory()) {
        Directory.create(to, recursive: true)
        for (entry in Directory.readFrom(from)) {
            copyTree(entry.path, to.join(entry.name))
        }
        return
    }
    Directory.create(to.parent, recursive: true)
    copy(from, to: to, overwrite: true)
}

private func extractDownloadedArchive(slug: String, version: String): Path {
    if (clawHubArchiveRootOverride.isSome()) {
        return clawHubArchiveRootOverride.getOrThrow()(slug, version)
    }
    let tempDir = Directory.createTemp(CliConfig.dotDir)
    let archivePath = tempDir.join("${slug}.zip")
    let extractDir = tempDir.join("extract")
    let url = "${CLAWHUB_BASE_URL}/api/v1/download?slug=${clawHubUrlEncode(slug)}&version=${clawHubUrlEncode(version)}"
    let (curlCode, _, curlErr) = ShellUtils.execute(
        ["curl", "-LfsS", url, "-o", archivePath.toString()],
        timeout: Some(Duration.second * 120),
        workDir: Some(CliConfig.cwd),
        withWrap: false
    )
    if (curlCode != 0) {
        throw Exception(if (curlErr.trimAscii().isEmpty()) { "failed to download ClawHub archive" } else { curlErr.trimAscii() })
    }
    Directory.create(extractDir, recursive: true)
    let (unzipCode, _, unzipErr) = ShellUtils.execute(
        ["unzip", "-q", archivePath.toString(), "-d", extractDir.toString()],
        timeout: Some(Duration.second * 120),
        workDir: Some(CliConfig.cwd),
        withWrap: false
    )
    if (unzipCode != 0) {
        throw Exception(if (unzipErr.trimAscii().isEmpty()) { "failed to extract ClawHub archive" } else { unzipErr.trimAscii() })
    }
    match (findExtractedSkillRoot(extractDir)) {
        case Some(root) => root
        case None => throw Exception("downloaded archive is missing SKILL.md")
    }
}

public func searchClawHubSkillsText(request: SkillsSearchRequest): String {
    let query = request.query.trimAscii()
    let limitArg = if (request.limit > 0) { "?limit=${request.limit}" } else { "" }
    let raw = if (query.isEmpty()) {
        clawHubHttpGet("${CLAWHUB_BASE_URL}/api/v1/skills${limitArg}", "application/json")
    } else {
        let sep = if (request.limit > 0) { "&" } else { "?" }
        clawHubHttpGet(
            "${CLAWHUB_BASE_URL}/api/v1/search?q=${clawHubUrlEncode(query)}${if (request.limit > 0) { "${sep}limit=${request.limit}" } else { "" }}",
            "application/json"
        )
    }
    if (request.json) {
        return raw.trimAscii()
    }
    let rows = parseClawHubSearchResults(raw)
    if (rows.isEmpty()) {
        return "No ClawHub skills found."
    }
    let out = ArrayList<String>()
    for (row in rows) {
        let slug = extractString(row, "slug") ?? ""
        let displayName = extractString(row, "displayName") ?? slug
        let summary = extractString(row, "summary") ?? ""
        let version = if (let Some(latestValue) <- row.get("latestVersion")) {
            if (let Some(latestObj) <- (latestValue as JsonObject)) {
                extractString(latestObj, "version") ?? (extractString(row, "version") ?? "")
            } else {
                extractString(row, "version") ?? ""
            }
        } else {
            extractString(row, "version") ?? ""
        }
        let updatedAt = extractInt64(row, "updatedAt") ?? 0
        out.add("${slug}${if (!version.isEmpty()) { " @${version}" } else { "" }}")
        if (!displayName.isEmpty() && displayName != slug) {
            out.add("  Name: ${displayName}")
        }
        if (!summary.isEmpty()) {
            out.add("  Summary: ${summary}")
        }
        if (updatedAt > 0) {
            out.add("  Updated At: ${updatedAt}")
        }
    }
    String.join(out.toArray(), delimiter: "\n")
}

public func fetchClawHubSkillDetailJson(slug: String): JsonObject {
    let normalizedSlug = slug.trimAscii()
    if (normalizedSlug.isEmpty()) {
        throw Exception("missing skill slug")
    }
    let raw = clawHubHttpGet(
        "${CLAWHUB_BASE_URL}/api/v1/skills/${clawHubUrlEncode(normalizedSlug)}",
        "application/json"
    )
    JsonValue.fromStr(raw).asObject()
}

public func installClawHubSkill(
    workspaceDir: Path,
    slug: String,
    version!: String = "",
    force!: Bool = false
): ClawHubInstallTransportResult {
    try {
        let normalizedSlug = slug.trimAscii()
        let detailRaw = fetchClawHubSkillDetailJson(normalizedSlug).toJsonString()
        let resolvedVersion = if (!version.trimAscii().isEmpty()) { version.trimAscii() } else { parseLatestSkillVersion(detailRaw) }
        if (resolvedVersion.isEmpty()) {
            return ClawHubInstallTransportResult(false, slug: "", version: "", targetDir: "", error: "Skill \"${normalizedSlug}\" has no installable version.")
        }
        let targetDir = resolveClawHubSkillInstallDir(workspaceDir, normalizedSlug)
        if (exists(targetDir) && !force) {
            return ClawHubInstallTransportResult(
                false,
                slug: "",
                version: "",
                targetDir: "",
                error: "Skill already exists at ${targetDir}. Re-run with force/update."
            )
        }
        let extractedRoot = extractDownloadedArchive(normalizedSlug, resolvedVersion)
        if (exists(targetDir)) {
            remove(targetDir, recursive: true)
        }
        copyTree(extractedRoot, targetDir)
        recordInstalledClawHubSkill(workspaceDir, normalizedSlug, resolvedVersion)
        ClawHubInstallTransportResult(
            true,
            slug: normalizedSlug,
            version: resolvedVersion,
            targetDir: targetDir.toString(),
            error: ""
        )
    } catch (e: Exception) {
        LogUtils.info("ClawHub install failed: ${e.message}")
        ClawHubInstallTransportResult(false, slug: "", version: "", targetDir: "", error: e.message)
    }
}

public func updateClawHubSkills(
    workspaceDir: Path,
    slugs: Array<String>
): Array<ClawHubUpdateTransportResult> {
    let out = ArrayList<ClawHubUpdateTransportResult>()
    for (slug0 in slugs) {
        let slug = slug0.trimAscii()
        if (slug.isEmpty()) {
            continue
        }
        let previousVersion = match (readClawHubSkillOrigin(resolveClawHubSkillInstallDir(workspaceDir, slug))) {
            case Some(origin) => origin.installedVersion
            case None => ""
        }
        let install = installClawHubSkill(workspaceDir, slug, force: true)
        if (!install.ok) {
            out.add(ClawHubUpdateTransportResult(false, slug: slug, version: "", previousVersion: "", targetDir: "", error: install.error))
            continue
        }
        out.add(
            ClawHubUpdateTransportResult(
                true,
                slug: slug,
                version: install.version,
                previousVersion: previousVersion,
                targetDir: install.targetDir,
                error: ""
            )
        )
    }
    out.toArray()
}
