package metis.core.skills

import magic.jsonable.*

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.fs.{Directory, File, Path, exists}
import std.sort.sort
import std.time.*
import stdx.encoding.json.{JsonObject, JsonValue, JsonString}

public struct ClawHubSkillOrigin {
    public let registry: String
    public let slug: String
    public let installedVersion: String
    public let installedAt: Int64

    public init(
        registry: String,
        slug: String,
        installedVersion: String,
        installedAt: Int64
    ) {
        this.registry = registry
        this.slug = slug
        this.installedVersion = installedVersion
        this.installedAt = installedAt
    }

    public func toJsonObject(): JsonObject {
        let root = JsonObject()
        root.put("version", 1.toJsonValue())
        root.put("registry", JsonString(registry))
        root.put("slug", JsonString(slug))
        root.put("installedVersion", JsonString(installedVersion))
        root.put("installedAt", installedAt.toJsonValue())
        root
    }
}

public struct ClawHubTrackedSkill {
    public let version: String
    public let installedAt: Int64

    public init(version: String, installedAt: Int64) {
        this.version = version
        this.installedAt = installedAt
    }

    public func toJsonObject(): JsonObject {
        let root = JsonObject()
        root.put("version", JsonString(version))
        root.put("installedAt", installedAt.toJsonValue())
        root
    }
}

public struct ClawHubSkillsLockfile {
    public let skills: HashMap<String, ClawHubTrackedSkill>

    public init(skills!: HashMap<String, ClawHubTrackedSkill> = HashMap<String, ClawHubTrackedSkill>()) {
        this.skills = skills
    }

    public func toJsonObject(): JsonObject {
        let root = JsonObject()
        root.put("version", 1.toJsonValue())
        let skillsRoot = JsonObject()
        for (slug in skills.keys()) {
            skillsRoot.put(slug, skills.get(slug).getOrThrow().toJsonObject())
        }
        root.put("skills", skillsRoot)
        root
    }
}

public struct SkillsInstallTarget {
    public let kind: String
    public let raw: String
    public let slug: String

    public init(kind: String, raw: String, slug!: String = "") {
        this.kind = kind
        this.raw = raw
        this.slug = slug
    }
}

public struct SkillsInstallRequest {
    public let target: SkillsInstallTarget
    public let version: String
    public let force: Bool

    public init(target: SkillsInstallTarget, version!: String = "", force!: Bool = false) {
        this.target = target
        this.version = version.trimAscii()
        this.force = force
    }
}

public struct SkillsUpdateRequest {
    public let slug: String
    public let all: Bool
    public let valid: Bool

    public init(slug!: String = "", all!: Bool = false, valid!: Bool = true) {
        this.slug = slug.trimAscii()
        this.all = all
        this.valid = valid
    }
}

public struct SkillsSearchRequest {
    public let query: String
    public let limit: Int64
    public let json: Bool
    public let valid: Bool

    public init(query!: String = "", limit!: Int64 = 0, json!: Bool = false, valid!: Bool = true) {
        this.query = query.trimAscii()
        this.limit = limit
        this.json = json
        this.valid = valid
    }
}

private let CLAWHUB_DOT_DIR = ".clawhub"
private let CLAWHUB_REGISTRY = "https://clawhub.ai"

private func skillStatusNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func skillStatusReadJson(path: Path): Option<JsonObject> {
    if (!exists(path)) {
        return None
    }
    try {
        Some(JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject())
    } catch (_: Exception) {
        None
    }
}

private func skillStatusReadText(path: Path): Option<String> {
    if (!exists(path)) {
        return None
    }
    try {
        Some(String.fromUtf8(File.readFrom(path)))
    } catch (_: Exception) {
        None
    }
}

private func jsonStringValue(obj: JsonObject, key: String): Option<String> {
    match (obj.get(key)) {
        case Some(value) => Some(value.asString().getValue())
        case None => None
    }
}

private func jsonInt64Value(obj: JsonObject, key: String): Option<Int64> {
    match (obj.get(key)) {
        case Some(value) => try {
            Some(Int64.parse(value.toJsonString().trimAscii().replace("\"", "")))
        } catch (_: Exception) {
            None
        }
        case None => None
    }
}

private func isAsciiDigit(ch: UInt8): Bool {
    ch >= b'0' && ch <= b'9'
}

private func splitTopLevelJsonEntries(raw: String): Array<String> {
    let body = raw.trimAscii()
    if (body.size < 2 || !body.startsWith("{") || !body.endsWith("}")) {
        return []
    }
    let inner = body[1..body.size - 1]
    if (inner.trimAscii().isEmpty()) {
        return []
    }
    let out = ArrayList<String>()
    var buf = ""
    var depth: Int64 = 0
    var inString = false
    var escaped = false
    for (ch in inner) {
        buf += ch.toString()
        if (escaped) {
            escaped = false
            continue
        }
        if (ch == b'\\') {
            escaped = true
            continue
        }
        if (ch == b'"') {
            inString = !inString
            continue
        }
        if (inString) {
            continue
        }
        if (ch == b'{') {
            depth += 1
            continue
        }
        if (ch == b'}') {
            depth -= 1
            continue
        }
        if (ch == b',' && depth == 0) {
            let row = buf
            out.add(row[0..row.size - 1].trimAscii())
            buf = ""
        }
    }
    let tail = buf.trimAscii()
    if (!tail.isEmpty()) {
        out.add(tail)
    }
    out.toArray()
}

public func clawHubSkillsLockfilePath(workspaceDir: Path): Path {
    workspaceDir.join(CLAWHUB_DOT_DIR).join("lock.json")
}

public func clawHubSkillOriginPath(skillDir: Path): Path {
    skillDir.join(CLAWHUB_DOT_DIR).join("origin.json")
}

public func resolveClawHubSkillInstallDir(workspaceDir: Path, slug: String): Path {
    workspaceDir.join("skills").join(slug)
}

public func isLikelyClawHubSlug(raw: String): Bool {
    let slug = raw.trimAscii()
    if (slug.isEmpty()) {
        return false
    }
    if (slug.contains("/") || slug.contains("\\") || slug.contains("@") || slug.contains("..")) {
        return false
    }
    if (!(slug[0].isAsciiLetter() || isAsciiDigit(slug[0]))) {
        return false
    }
    if (!(slug[slug.size - 1].isAsciiLetter() || isAsciiDigit(slug[slug.size - 1]))) {
        return false
    }
    for (ch in slug) {
        if (ch.isAsciiLetter() || isAsciiDigit(ch) || ch == b'-') {
            continue
        }
        return false
    }
    true
}

public func resolveSkillsInstallTarget(raw: String): SkillsInstallTarget {
    let trimmed = raw.trimAscii()
    if (isLikelyClawHubSlug(trimmed)) {
        return SkillsInstallTarget("clawhub", trimmed, slug: trimmed)
    }
    let slug = if (trimmed.contains("@")) { trimmed[trimmed.lastIndexOf("@").getOrThrow() + 1..].trimAscii() } else { "" }
    SkillsInstallTarget("package", trimmed, slug: if (isLikelyClawHubSlug(slug)) { slug } else { "" })
}

public func resolveSkillsInstallRequest(raw: String): SkillsInstallRequest {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return SkillsInstallRequest(resolveSkillsInstallTarget(""))
    }
    let parts = ArrayList<String>()
    for (part in trimmed.split(" ")) {
        let token = part.trimAscii()
        if (!token.isEmpty()) {
            parts.add(token)
        }
    }
    if (parts.isEmpty()) {
        return SkillsInstallRequest(resolveSkillsInstallTarget(""))
    }
    let positional = ArrayList<String>()
    var version = ""
    var force = false
    var idx = 0
    while (idx < parts.size) {
        let token = parts[idx]
        if (token == "--force") {
            force = true
            idx += 1
            continue
        }
        if (token == "--version") {
            if (idx + 1 < parts.size) {
                version = parts[idx + 1].trimAscii()
                idx += 2
                continue
            }
            idx += 1
            continue
        }
        if (token.startsWith("--version=")) {
            version = token["--version=".size..].trimAscii()
            idx += 1
            continue
        }
        positional.add(token)
        idx += 1
    }
    let targetRaw = if (positional.isEmpty()) { "" } else { positional[0] }
    SkillsInstallRequest(
        resolveSkillsInstallTarget(targetRaw),
        version: version,
        force: force
    )
}

public func resolveSkillsUpdateRequest(raw: String): SkillsUpdateRequest {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return SkillsUpdateRequest(all: true)
    }
    let tokens = ArrayList<String>()
    for (part in trimmed.split(" ")) {
        let token = part.trimAscii()
        if (!token.isEmpty()) {
            tokens.add(token)
        }
    }
    var all = false
    let positional = ArrayList<String>()
    for (token in tokens) {
        if (token == "--all") {
            all = true
            continue
        }
        positional.add(token)
    }
    if (all && !positional.isEmpty()) {
        return SkillsUpdateRequest(valid: false)
    }
    if (all) {
        return SkillsUpdateRequest(all: true)
    }
    if (positional.isEmpty()) {
        return SkillsUpdateRequest(all: true)
    }
    SkillsUpdateRequest(slug: positional[0], all: false)
}

public func resolveSkillsSearchRequest(raw: String): SkillsSearchRequest {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return SkillsSearchRequest()
    }
    let tokens = ArrayList<String>()
    for (part in trimmed.split(" ")) {
        let token = part.trimAscii()
        if (!token.isEmpty()) {
            tokens.add(token)
        }
    }
    var limit: Int64 = 0
    var json = false
    let queryParts = ArrayList<String>()
    var idx = 0
    while (idx < tokens.size) {
        let token = tokens[idx]
        if (token == "--json") {
            json = true
            idx += 1
            continue
        }
        if (token == "--limit") {
            if (idx + 1 >= tokens.size) {
                return SkillsSearchRequest(valid: false)
            }
            try {
                limit = Int64.parse(tokens[idx + 1])
            } catch (_: Exception) {
                return SkillsSearchRequest(valid: false)
            }
            idx += 2
            continue
        }
        if (token.startsWith("--limit=")) {
            try {
                limit = Int64.parse(token["--limit=".size..].trimAscii())
            } catch (_: Exception) {
                return SkillsSearchRequest(valid: false)
            }
            idx += 1
            continue
        }
        queryParts.add(token)
        idx += 1
    }
    SkillsSearchRequest(
        query: String.join(queryParts.toArray(), delimiter: " "),
        limit: limit,
        json: json
    )
}

public func readClawHubSkillOrigin(skillDir: Path): Option<ClawHubSkillOrigin> {
    match (skillStatusReadJson(clawHubSkillOriginPath(skillDir))) {
        case Some(root) =>
            let registry = jsonStringValue(root, "registry")
            let slug = jsonStringValue(root, "slug")
            let version = jsonStringValue(root, "installedVersion")
            let installedAt = jsonInt64Value(root, "installedAt")
            if (registry.isSome() && slug.isSome() && version.isSome() && installedAt.isSome()) {
                return Some(
                    ClawHubSkillOrigin(
                        registry.getOrThrow(),
                        slug.getOrThrow(),
                        version.getOrThrow(),
                        installedAt.getOrThrow()
                    )
                )
            }
            None
        case None => None
    }
}

public func writeClawHubSkillOrigin(skillDir: Path, origin: ClawHubSkillOrigin): Unit {
    let target = clawHubSkillOriginPath(skillDir)
    Directory.create(target.parent, recursive: true)
    File.writeTo(target, (origin.toJsonObject().toJsonString() + "\n").toArray())
}

public func readClawHubSkillsLockfile(workspaceDir: Path): ClawHubSkillsLockfile {
    match (skillStatusReadJson(clawHubSkillsLockfilePath(workspaceDir))) {
        case Some(root) =>
            let parsed = HashMap<String, ClawHubTrackedSkill>()
            match (root.get("skills")) {
                case Some(skillsRaw) =>
                    for (entry in splitTopLevelJsonEntries(skillsRaw.toJsonString())) {
                        match (entry.indexOf(":")) {
                            case Some(colon) =>
                                let slug = entry[0..colon].trimAscii().replace("\"", "")
                                let payload = entry[colon + 1..].trimAscii()
                                try {
                                    let entryObj = JsonValue.fromStr(payload).asObject()
                                    let version = jsonStringValue(entryObj, "version")
                                    let installedAt = jsonInt64Value(entryObj, "installedAt")
                                    if (!slug.isEmpty() && version.isSome() && installedAt.isSome()) {
                                        parsed[slug] = ClawHubTrackedSkill(version.getOrThrow(), installedAt.getOrThrow())
                                    }
                                } catch (_: Exception) {
                                    ()
                                }
                            case None => ()
                        }
                    }
                case None => ()
            }
            ClawHubSkillsLockfile(skills: parsed)
        case None => ClawHubSkillsLockfile()
    }
}

public func writeClawHubSkillsLockfile(workspaceDir: Path, lockfile: ClawHubSkillsLockfile): Unit {
    let target = clawHubSkillsLockfilePath(workspaceDir)
    Directory.create(target.parent, recursive: true)
    File.writeTo(target, (lockfile.toJsonObject().toJsonString() + "\n").toArray())
}

public func readTrackedClawHubSkillSlugs(workspaceDir: Path): Array<String> {
    let slugs = ArrayList<String>()
    for (slug in readClawHubSkillsLockfile(workspaceDir).skills.keys()) {
        slugs.add(slug)
    }
    let out = slugs.toArray()
    sort(out)
    out
}

public func isTrackedClawHubSkill(workspaceDir: Path, slug: String): Bool {
    let normalizedSlug = slug.trimAscii()
    if (normalizedSlug.isEmpty()) {
        return false
    }
    let lock = readClawHubSkillsLockfile(workspaceDir)
    if (lock.skills.contains(normalizedSlug)) {
        return true
    }
    let skillDir = resolveClawHubSkillInstallDir(workspaceDir, normalizedSlug)
    readClawHubSkillOrigin(skillDir).isSome()
}

public func recordInstalledClawHubSkill(
    workspaceDir: Path,
    slug: String,
    installedVersion: String,
    installedAtMs!: Int64 = 0
): Unit {
    let normalizedVersion = if (installedVersion.trimAscii().isEmpty()) { "unknown" } else { installedVersion.trimAscii() }
    let installedAt = if (installedAtMs > 0) { installedAtMs } else { skillStatusNowMs() }
    let skillDir = resolveClawHubSkillInstallDir(workspaceDir, slug.trimAscii())
    writeClawHubSkillOrigin(
        skillDir,
        ClawHubSkillOrigin(
            CLAWHUB_REGISTRY,
            slug.trimAscii(),
            normalizedVersion,
            installedAt
        )
    )
    let lock = readClawHubSkillsLockfile(workspaceDir)
    lock.skills[slug.trimAscii()] = ClawHubTrackedSkill(normalizedVersion, installedAt)
    writeClawHubSkillsLockfile(workspaceDir, lock)
}

public func refreshTrackedClawHubSkillVersion(
    workspaceDir: Path,
    slug: String,
    installedVersion: String
): Unit {
    let normalizedSlug = slug.trimAscii()
    let normalizedVersion = if (installedVersion.trimAscii().isEmpty()) { "unknown" } else { installedVersion.trimAscii() }
    let nowMs = skillStatusNowMs()
    let skillDir = resolveClawHubSkillInstallDir(workspaceDir, normalizedSlug)
    let registry = match (readClawHubSkillOrigin(skillDir)) {
        case Some(origin) => origin.registry
        case None => CLAWHUB_REGISTRY
    }
    writeClawHubSkillOrigin(
        skillDir,
        ClawHubSkillOrigin(
            registry,
            normalizedSlug,
            normalizedVersion,
            nowMs
        )
    )
    let lock = readClawHubSkillsLockfile(workspaceDir)
    lock.skills[normalizedSlug] = ClawHubTrackedSkill(normalizedVersion, nowMs)
    writeClawHubSkillsLockfile(workspaceDir, lock)
}
