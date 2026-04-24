package metis.core.prompting

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
}
