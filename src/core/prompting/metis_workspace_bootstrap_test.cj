package metis.core.prompting

import metis.utils.ShellUtils

import std.fs.{Directory, File, OpenMode, Path, exists, remove}
import std.unittest.testmacro.*

private func repeatWorkspaceText(text: String, count: Int64): String {
    var out = ""
    for (_ in 0..count) {
        out += text
    }
    out
}

private func cleanupWorkspaceBootstrapTestDir(root: Path): Unit {
    if (exists(root)) {
        remove(root, recursive: true)
    }
}

private func bootstrapHasFileWithSuffix(files: Array<MetisContextFile>, suffix: String): Bool {
    for (file in files) {
        if (file.path.endsWith(suffix)) {
            return true
        }
    }
    false
}

private func bootstrapStateHasName(files: Array<MetisAgentWorkspaceBootstrapFileState>, name: String): Bool {
    for (file in files) {
        if (file.name == name) {
            return true
        }
    }
    false
}

@Test
public class MetisWorkspaceBootstrapTest {
    /*
    @TestCase
    public func resolveContextFilesTruncatesLargeMemoryFileUsingBootstrapBudget(): Unit {
        let root = Path("/tmp/metis-workspace-bootstrap-large-memory")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root, recursive: true)
            File.writeTo(root.join("AGENTS.md"), "# Agents\n".toArray())
            File.writeTo(root.join("SOUL.md"), "# Soul\n".toArray())
            File.writeTo(root.join("TOOLS.md"), "# Tools\n".toArray())
            File.writeTo(root.join("IDENTITY.md"), "# Identity\n".toArray())
            File.writeTo(root.join("USER.md"), "# User\n".toArray())
            File.writeTo(root.join("HEARTBEAT.md"), "# Heartbeat\n".toArray())
            File.writeTo(root.join("BOOTSTRAP.md"), "# Bootstrap\n".toArray())
            let largeMemory = repeatWorkspaceText("memory-line-", 40000)
            File.writeTo(root.join("MEMORY.md"), largeMemory.toArray())

            let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(root)
            let files = bootstrap.files
            var foundMemory = false
            for (file in files) {
                if (file.path.endsWith("/MEMORY.md") || file.path.endsWith("\\MEMORY.md") || file.path.endsWith("MEMORY.md")) {
                    foundMemory = true
                    @Expect(file.content.contains("[...truncated, read MEMORY.md for full content...]"), true)
                    @Expect(file.content.contains("truncated MEMORY.md"), true)
                    @Expect(file.content.size <= DEFAULT_BOOTSTRAP_TOTAL_MAX_CHARS, true)
                }
            }
            @Expect(foundMemory, true)
            @Expect(bootstrap.truncatedFiles >= 1, true)
            @Expect(bootstrap.totalChars < bootstrap.originalTotalChars, true)
            @Expect(bootstrap.warnings.size >= 1, true)
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }
    */

    @TestCase
    public func resolveContextFilesPreservesMissingPlaceholderForAbsentMemory(): Unit {
        let root = Path("/tmp/metis-workspace-bootstrap-missing-memory")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root, recursive: true)
            File.writeTo(root.join("AGENTS.md"), "# Agents\n".toArray())
            File.writeTo(root.join("SOUL.md"), "# Soul\n".toArray())
            File.writeTo(root.join("TOOLS.md"), "# Tools\n".toArray())
            File.writeTo(root.join("IDENTITY.md"), "# Identity\n".toArray())
            File.writeTo(root.join("USER.md"), "# User\n".toArray())
            File.writeTo(root.join("HEARTBEAT.md"), "# Heartbeat\n".toArray())

            let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(root)
            let files = bootstrap.files
            var foundMissingMemory = false
            for (file in files) {
                if (file.content.startsWith("[MISSING] Expected at:") && (file.path.endsWith("/MEMORY.md") || file.path.endsWith("\\MEMORY.md") || file.path.endsWith("MEMORY.md"))) {
                    foundMissingMemory = true
                }
            }
            @Expect(foundMissingMemory, true)
            @Expect(bootstrap.missingFiles >= 1, true)
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }

    @TestCase
    public func resolveContextFilesMinimalModeStillOnlyReturnsAgentsAndTools(): Unit {
        let root = Path("/tmp/metis-workspace-bootstrap-minimal")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root, recursive: true)
            File.writeTo(root.join("AGENTS.md"), "# Agents\n".toArray())
            File.writeTo(root.join("TOOLS.md"), "# Tools\n".toArray())
            File.writeTo(root.join("MEMORY.md"), repeatWorkspaceText("memory-line-", 5000).toArray())

            let files = MetisWorkspaceBootstrap.resolveContextFiles(root, promptMode: PromptMode.MinimalMode)
            @Expect(files.size, 2)
            @Expect(files[0].path.endsWith("AGENTS.md"), true)
            @Expect(files[1].path.endsWith("TOOLS.md"), true)
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }

    @TestCase
    public func bootstrapPolicyDoesNotAutoCreateBootstrapButLoadsExistingInFullMode(): Unit {
        let root = Path("/tmp/metis-workspace-bootstrap-policy")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root, recursive: true)
            File.writeTo(root.join("BOOTSTRAP.md"), "# Setup State\n".toArray())

            @Expect(METIS_WORKSPACE_BOOTSTRAP_AUTOCREATES_BOOTSTRAP_FILE, false)
            @Expect(metisWorkspaceBootstrapFilenames().contains("BOOTSTRAP.md"), false)
            let ensure = ensureMetisAgentWorkspace(root)
            @Expect(ensure.createdCount >= 6, true)
            @Expect(bootstrapStateHasName(ensure.files, "BOOTSTRAP.md"), false)

            let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(root)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "BOOTSTRAP.md"), true)
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }

    @TestCase
    public func resolveContextFilesSkipsLowValueFilesForTelegramBootstrap(): Unit {
        let root = Path("/tmp/metis-workspace-bootstrap-telegram-compact")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root, recursive: true)
            File.writeTo(root.join("AGENTS.md"), "# Agents\n".toArray())
            File.writeTo(root.join("SOUL.md"), "# Soul\n".toArray())
            File.writeTo(root.join("TOOLS.md"), "# Tools\n".toArray())
            File.writeTo(root.join("IDENTITY.md"), "# Identity\n".toArray())
            File.writeTo(root.join("USER.md"), "# User\n".toArray())
            File.writeTo(root.join("HEARTBEAT.md"), "# Heartbeat\n".toArray())
            File.writeTo(root.join("BOOTSTRAP.md"), "# Bootstrap\n".toArray())
            File.writeTo(root.join("MEMORY.md"), "# Goals\n- keep this\n".toArray())

            let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(root, runtimeChannel: "telegram")
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "AGENTS.md"), true)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "TOOLS.md"), true)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "SOUL.md"), true)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "IDENTITY.md"), true)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "MEMORY.md"), true)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "USER.md"), false)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "HEARTBEAT.md"), false)
            @Expect(bootstrapHasFileWithSuffix(bootstrap.files, "BOOTSTRAP.md"), false)
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }

    @TestCase
    public func ensureAgentWorkspaceCreatesMissingBootstrapFilesWithoutOverwriting(): Unit {
        let root = Path("/tmp/metis-agent-workspace-bootstrap-ensure")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root, recursive: true)
            File.writeTo(root.join("SOUL.md"), "# Custom Soul\n".toArray())

            let bootstrap = ensureMetisAgentWorkspace(root)

            @Expect(bootstrap.workspaceDir.endsWith("metis-agent-workspace-bootstrap-ensure"), true)
            @Expect(bootstrap.createdCount >= 6, true)
            @Expect(String.fromUtf8(File.readFrom(root.join("SOUL.md"))), "# Custom Soul\n")
            for (name in metisWorkspaceBootstrapFilenames()) {
                @Expect(exists(root.join(name)), true)
            }
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }

    @TestCase
    public func safeWorkspaceReadWriteRejectsEscapesAndAllowsRelativeFiles(): Unit {
        let root = Path("/tmp/metis-agent-workspace-safe-io")
        let outside = Path("/tmp/metis-agent-workspace-safe-io-outside")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            cleanupWorkspaceBootstrapTestDir(outside)
            Directory.create(root, recursive: true)
            Directory.create(outside, recursive: true)
            File.writeTo(outside.join("secret.txt"), "secret".toArray())

            let writeResult = metisWorkspaceSafeWrite(root, "notes/today.md", "hello")
            @Expect(writeResult.ok, true)
            let readResult = metisWorkspaceSafeRead(root, "notes/today.md")
            @Expect(readResult.ok, true)
            @Expect(readResult.content, "hello")

            @Expect(metisWorkspaceSafeRead(root, "../secret.txt").ok, false)
            @Expect(metisWorkspaceSafeWrite(root, "/tmp/escape.txt", "bad").ok, false)

            let (code, _, _) = ShellUtils.execute(
                ["ln", "-s", outside.toString(), root.join("escape").toString()],
                withWrap: false
            )
            @Expect(code, 0)
            @Expect(metisWorkspaceSafeRead(root, "escape/secret.txt").ok, false)

            File.writeTo(outside.join("target.txt"), "keep".toArray())
            let (linkCode, _, _) = ShellUtils.execute(
                ["ln", "-s", outside.join("target.txt").toString(), root.join("link.txt").toString()],
                withWrap: false
            )
            @Expect(linkCode, 0)
            let symlinkWrite = metisWorkspaceSafeWrite(root, "link.txt", "bad")
            @Expect(symlinkWrite.ok, false)
            @Expect(String.fromUtf8(File.readFrom(outside.join("target.txt"))), "keep")
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
            cleanupWorkspaceBootstrapTestDir(outside)
        }
    }

    @TestCase
    public func identityMarkdownParsesFieldsAndValidatesAvatarBoundary(): Unit {
        let root = Path("/tmp/metis-agent-workspace-identity")
        try {
            cleanupWorkspaceBootstrapTestDir(root)
            Directory.create(root.join("assets"), recursive: true)
            File.writeTo(root.join("assets").join("avatar.png"), "png".toArray())

            let identity = parseMetisIdentityMarkdown(
                "# Identity\n\n" +
                "Name: Planner\n" +
                "Emoji: P\n" +
                "Theme: slate\n" +
                "Creature: \n" +
                "Vibe: calm\n" +
                "Avatar: assets/avatar.png\n"
            )
            @Expect(identity.name, "Planner")
            @Expect(identity.emoji, "P")
            @Expect(identity.theme, "slate")
            @Expect(identity.vibe, "calm")
            @Expect(identity.avatar, "assets/avatar.png")

            @Expect(validateMetisIdentityAvatar(root, "assets/avatar.png").ok, true)
            @Expect(validateMetisIdentityAvatar(root, "https://example.test/avatar.png").ok, true)
            @Expect(validateMetisIdentityAvatar(root, "HTTPS://example.test/avatar.png").ok, true)
            @Expect(validateMetisIdentityAvatar(root, "data:image/png;base64,AAAA").ok, true)
            @Expect(validateMetisIdentityAvatar(root, "DATA:image/png;base64,AAAA").ok, true)
            @Expect(validateMetisIdentityAvatar(root, "~/avatar.png").ok, false)
            @Expect(validateMetisIdentityAvatar(root, "file:///tmp/avatar.png").ok, false)
            @Expect(validateMetisIdentityAvatar(root, "../avatar.png").ok, false)
        } finally {
            cleanupWorkspaceBootstrapTestDir(root)
        }
    }
}
