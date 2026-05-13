package metis.core.prompting

import std.collection.ArrayList
import std.fs.{Path, File, Directory, FileInfo, exists, canonicalize, remove, rename}
import std.io.*
import std.time.DateTime

private const AGENTS_FILENAME = "AGENTS.md"
private const SOUL_FILENAME = "SOUL.md"
private const TOOLS_FILENAME = "TOOLS.md"
private const IDENTITY_FILENAME = "IDENTITY.md"
private const USER_FILENAME = "USER.md"
private const HEARTBEAT_FILENAME = "HEARTBEAT.md"
private const BOOTSTRAP_FILENAME = "BOOTSTRAP.md"
private const MEMORY_FILENAME = "MEMORY.md"
private const MEMORY_ALT_FILENAME = "memory.md"

// BOOTSTRAP.md is an explicit, user-created setup-state file: load it in full prompt mode
// when present, but do not auto-create it as durable workspace memory for every agent.
public const METIS_WORKSPACE_BOOTSTRAP_AUTOCREATES_BOOTSTRAP_FILE: Bool = false

public class MetisAgentWorkspaceBootstrapFileState {
    public var name: String = ""
    public var path: String = ""
    public var created: Bool = false
    public var existed: Bool = false
    public init() {}
}

public class MetisAgentWorkspaceBootstrapResult {
    public var workspaceDir: String = ""
    public var createdCount: Int64 = 0
    public var files: Array<MetisAgentWorkspaceBootstrapFileState> = []
    public init() {}
}

public class MetisWorkspaceFileIoResult {
    public var ok: Bool = false
    public var reason: String = ""
    public var path: String = ""
    public var content: String = ""
    public init() {}
}

public class MetisAgentIdentity {
    public var name: String = ""
    public var emoji: String = ""
    public var theme: String = ""
    public var creature: String = ""
    public var vibe: String = ""
    public var avatar: String = ""
    public init() {}
}

public class MetisIdentityAvatarValidation {
    public var ok: Bool = false
    public var reason: String = ""
    public init() {}
}

private func canonicalPathString(path: Path): String {
    try {
        canonicalize(path).toString()
    } catch (_) {
        path.toString()
    }
}

private func readTextFile(path: Path): String {
    String.fromUtf8(File.readFrom(path))
}

private func metisEnsureDirectory(path: Path): Unit {
    if (!exists(path)) {
        Directory.create(path, recursive: true)
    }
}

private func metisPathIsSymlink(path: Path): Bool {
    try {
        FileInfo(path).isSymbolicLink()
    } catch (_e: Exception) {
        false
    }
}

private func metisWorkspaceTemplate(name: String): String {
    match (name) {
        case AGENTS_FILENAME =>
            "# Agents\n\n" +
            "This workspace belongs to a Metis agent. Keep durable operating rules, delegation notes, and handoff conventions here.\n"
        case SOUL_FILENAME =>
            "# Soul\n\n" +
            "Describe the agent's purpose, tone, boundaries, and decision preferences.\n"
        case TOOLS_FILENAME =>
            "# Tools\n\n" +
            "Record workspace-specific tool expectations, allowed workflows, and local caveats.\n"
        case IDENTITY_FILENAME =>
            "# Identity\n\n" +
            "Name: Metis Agent\n" +
            "Emoji: \n" +
            "Theme: practical and careful\n" +
            "Creature: \n" +
            "Vibe: focused engineering partner\n" +
            "Avatar: \n"
        case USER_FILENAME =>
            "# User\n\n" +
            "Store user preferences that are safe to share with this agent. Do not put credentials here.\n"
        case HEARTBEAT_FILENAME =>
            "# Heartbeat\n\n" +
            "Use this file for lightweight status, recurring checks, and continuity notes.\n"
        case MEMORY_FILENAME =>
            "# Memory\n\n" +
            "Add durable facts, goals, and decisions that should survive across sessions.\n"
        case _ => "# ${name}\n"
    }
}

private func metisWorkspaceSafeFailure(reason: String, path!: String = ""): MetisWorkspaceFileIoResult {
    let result = MetisWorkspaceFileIoResult()
    result.ok = false
    result.reason = reason
    result.path = path
    result
}

private func metisWorkspaceSafeSuccess(path: String, content!: String = ""): MetisWorkspaceFileIoResult {
    let result = MetisWorkspaceFileIoResult()
    result.ok = true
    result.path = path
    result.content = content
    result
}

private func metisWorkspaceRejectReason(relativePath: String): String {
    let trimmed = relativePath.trimAscii()
    if (trimmed.isEmpty()) {
        return "empty path"
    }
    let normalized = trimmed.replace("\\", "/")
    if (normalized.startsWith("/") || normalized.startsWith("~")) {
        return "path must be workspace-relative"
    }
    if (normalized.contains("://") || normalized.contains(":")) {
        return "path must not include a URI scheme"
    }
    for (part in normalized.split("/")) {
        let segment = part.trimAscii()
        if (segment == "..") {
            return "path traversal is not allowed"
        }
    }
    ""
}

private func metisCanonicalInside(root: Path, candidate: Path): Bool {
    try {
        let rootText = canonicalize(root).toString()
        let candidateText = canonicalize(candidate).toString()
        candidateText == rootText || candidateText.startsWith(rootText + "/")
    } catch (_e: Exception) {
        false
    }
}

private func metisIdentityCleanKey(raw: String): String {
    raw.replace("*", "").replace("_", "").trimAscii().toAsciiLower()
}

private func metisIdentityCleanValue(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed == "<unset>" || trimmed == "unset" || trimmed == "TODO" || trimmed == "todo") {
        return ""
    }
    trimmed
}

public func metisWorkspaceBootstrapFilenames(): Array<String> {
    [
        AGENTS_FILENAME,
        SOUL_FILENAME,
        TOOLS_FILENAME,
        IDENTITY_FILENAME,
        USER_FILENAME,
        HEARTBEAT_FILENAME,
        MEMORY_FILENAME
    ]
}

public func ensureMetisAgentWorkspace(workspaceDir: Path): MetisAgentWorkspaceBootstrapResult {
    metisEnsureDirectory(workspaceDir)
    let result = MetisAgentWorkspaceBootstrapResult()
    result.workspaceDir = canonicalPathString(workspaceDir)
    let states = ArrayList<MetisAgentWorkspaceBootstrapFileState>()
    var createdCount: Int64 = 0
    for (name in metisWorkspaceBootstrapFilenames()) {
        let path = workspaceDir.join(name)
        let state = MetisAgentWorkspaceBootstrapFileState()
        state.name = name
        state.path = path.toString()
        if (exists(path)) {
            state.existed = true
        } else {
            if (metisPathIsSymlink(path)) {
                state.existed = true
            } else {
                try (file = File.create(path)) {
                    file.write(metisWorkspaceTemplate(name).toArray())
                }
                state.created = true
                createdCount += 1
            }
        }
        states.add(state)
    }
    result.createdCount = createdCount
    result.files = states.toArray()
    result
}

public func metisWorkspaceSafeRead(workspaceDir: Path, relativePath: String): MetisWorkspaceFileIoResult {
    let reason = metisWorkspaceRejectReason(relativePath)
    if (!reason.isEmpty()) {
        return metisWorkspaceSafeFailure(reason)
    }
    if (!exists(workspaceDir)) {
        return metisWorkspaceSafeFailure("workspace does not exist")
    }
    let target = workspaceDir.join(relativePath.trimAscii())
    if (!exists(target)) {
        return metisWorkspaceSafeFailure("file does not exist", path: target.toString())
    }
    if (!metisCanonicalInside(workspaceDir, target)) {
        return metisWorkspaceSafeFailure("path escapes workspace", path: target.toString())
    }
    metisWorkspaceSafeSuccess(canonicalPathString(target), content: readTextFile(target))
}

public func metisWorkspaceSafeWrite(workspaceDir: Path, relativePath: String, content: String): MetisWorkspaceFileIoResult {
    let reason = metisWorkspaceRejectReason(relativePath)
    if (!reason.isEmpty()) {
        return metisWorkspaceSafeFailure(reason)
    }
    metisEnsureDirectory(workspaceDir)
    let target = workspaceDir.join(relativePath.trimAscii())
    let parent = target.parent
    metisEnsureDirectory(parent)
    if (!metisCanonicalInside(workspaceDir, parent)) {
        return metisWorkspaceSafeFailure("path escapes workspace", path: target.toString())
    }
    if (metisPathIsSymlink(target)) {
        return metisWorkspaceSafeFailure("path escapes workspace", path: target.toString())
    }
    if (exists(target) && !metisCanonicalInside(workspaceDir, target)) {
        return metisWorkspaceSafeFailure("path escapes workspace", path: target.toString())
    }
    let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let tmp = parent.join(".${target.fileName}.metis-${stamp}.tmp")
    try {
        try (file = File.create(tmp)) {
            file.write(content.toArray())
        }
        if (metisPathIsSymlink(target)) {
            try { remove(tmp) } catch (_: Exception) { () }
            return metisWorkspaceSafeFailure("path escapes workspace", path: target.toString())
        }
        if (exists(target) && !metisCanonicalInside(workspaceDir, target)) {
            try { remove(tmp) } catch (_: Exception) { () }
            return metisWorkspaceSafeFailure("path escapes workspace", path: target.toString())
        }
        rename(tmp, to: target, overwrite: true)
    } catch (e: Exception) {
        try { remove(tmp) } catch (_: Exception) { () }
        return metisWorkspaceSafeFailure("write failed: ${e.message}", path: target.toString())
    }
    metisWorkspaceSafeSuccess(canonicalPathString(target), content: content)
}

public func parseMetisIdentityMarkdown(content: String): MetisAgentIdentity {
    let identity = MetisAgentIdentity()
    for (line in content.split("\n")) {
        var trimmed = line.trimAscii()
        if (trimmed.startsWith("-")) {
            trimmed = trimmed[1..].trimAscii()
        }
        if (trimmed.startsWith("*")) {
            trimmed = trimmed[1..].trimAscii()
        }
        if (!trimmed.contains(":")) {
            continue
        }
        let parts = trimmed.split(":")
        if (parts.size < 2) {
            continue
        }
        let key = metisIdentityCleanKey(parts[0])
        let value = metisIdentityCleanValue(String.join(parts[1..parts.size], delimiter: ":"))
        if (key == "name") {
            identity.name = value
        } else if (key == "emoji") {
            identity.emoji = value
        } else if (key == "theme") {
            identity.theme = value
        } else if (key == "creature") {
            identity.creature = value
        } else if (key == "vibe") {
            identity.vibe = value
        } else if (key == "avatar") {
            identity.avatar = value
        }
    }
    identity
}

public func validateMetisIdentityAvatar(workspaceDir: Path, avatar: String): MetisIdentityAvatarValidation {
    let result = MetisIdentityAvatarValidation()
    let trimmed = avatar.trimAscii()
    let low = trimmed.toAsciiLower()
    if (trimmed.isEmpty() || low.startsWith("http://") || low.startsWith("https://") || low.startsWith("data:")) {
        result.ok = true
        return result
    }
    if (trimmed.startsWith("~")) {
        result.reason = "avatar must not use home-relative paths"
        return result
    }
    if (trimmed.contains("://") || trimmed.contains(":")) {
        result.reason = "avatar URI scheme is not allowed"
        return result
    }
    let reason = metisWorkspaceRejectReason(trimmed)
    if (!reason.isEmpty()) {
        result.reason = reason
        return result
    }
    if (!exists(workspaceDir)) {
        result.reason = "workspace does not exist"
        return result
    }
    let target = workspaceDir.join(trimmed)
    let parent = target.parent
    if (exists(parent) && !metisCanonicalInside(workspaceDir, parent)) {
        result.reason = "avatar path escapes workspace"
        return result
    }
    if (exists(target) && !metisCanonicalInside(workspaceDir, target)) {
        result.reason = "avatar path escapes workspace"
        return result
    }
    result.ok = true
    result
}

private func buildMissingContextFile(path: Path): MetisContextFile {
    let displayPath = canonicalPathString(path)
    MetisContextFile(displayPath, "[MISSING] Expected at: ${displayPath}")
}

private func loadContextFile(path: Path): MetisContextFile {
    MetisContextFile(canonicalPathString(path), readTextFile(path))
}

private func shouldIncludeInMinimalMode(fileName: String): Bool {
    fileName == AGENTS_FILENAME || fileName == TOOLS_FILENAME
}

private func shouldUseCompactImBootstrap(runtimeChannel: String): Bool {
    let normalized = runtimeChannel.trimAscii().toAsciiLower()
    normalized == "telegram" || normalized == "qq" || normalized == "feishu"
}

private func shouldSkipInCompactImMode(fileName: String): Bool {
    fileName == USER_FILENAME || fileName == HEARTBEAT_FILENAME || fileName == BOOTSTRAP_FILENAME
}

public class MetisWorkspaceBootstrap {
    public static func resolveContextFilesDetailed(
        workspaceDir: Path,
        promptMode!: PromptMode = PromptMode.FullMode,
        runtimeChannel!: String = ""
    ): MetisBootstrapBudgetResult {
        let files = ArrayList<MetisContextFile>()
        let minimalMode = match (promptMode) {
            case PromptMode.MinimalMode => true
            case _ => false
        }
        let compactImMode = shouldUseCompactImBootstrap(runtimeChannel)
        let baseNames = [
            AGENTS_FILENAME,
            SOUL_FILENAME,
            TOOLS_FILENAME,
            IDENTITY_FILENAME,
            USER_FILENAME,
            HEARTBEAT_FILENAME
        ]

        for (name in baseNames) {
            if (minimalMode && !shouldIncludeInMinimalMode(name)) {
                continue
            }
            if (!minimalMode && compactImMode && shouldSkipInCompactImMode(name)) {
                continue
            }
            let path = workspaceDir.join(name)
            if (exists(path)) {
                files.add(loadContextFile(path))
            } else {
                files.add(buildMissingContextFile(path))
            }
        }

        if (!minimalMode) {
            let bootstrapPath = workspaceDir.join(BOOTSTRAP_FILENAME)
            if (!compactImMode && exists(bootstrapPath)) {
                files.add(loadContextFile(bootstrapPath))
            }

            let memoryPath = workspaceDir.join(MEMORY_FILENAME)
            let memoryAltPath = workspaceDir.join(MEMORY_ALT_FILENAME)
            if (exists(memoryPath)) {
                files.add(loadContextFile(memoryPath))
            } else if (exists(memoryAltPath)) {
                files.add(loadContextFile(memoryAltPath))
            } else {
                files.add(buildMissingContextFile(memoryPath))
            }
        }

        MetisBootstrapBudget.buildContextFiles(files.toArray())
    }

    public static func resolveContextFiles(
        workspaceDir: Path,
        promptMode!: PromptMode = PromptMode.FullMode,
        runtimeChannel!: String = ""
    ): Array<MetisContextFile> {
        MetisWorkspaceBootstrap.resolveContextFilesDetailed(
            workspaceDir,
            promptMode: promptMode,
            runtimeChannel: runtimeChannel
        ).files
    }
}
