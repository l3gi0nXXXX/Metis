package metis.core.prompting

import std.collection.ArrayList
import std.fs.{Path, File, exists, canonicalize}

private const AGENTS_FILENAME = "AGENTS.md"
private const SOUL_FILENAME = "SOUL.md"
private const TOOLS_FILENAME = "TOOLS.md"
private const IDENTITY_FILENAME = "IDENTITY.md"
private const USER_FILENAME = "USER.md"
private const HEARTBEAT_FILENAME = "HEARTBEAT.md"
private const BOOTSTRAP_FILENAME = "BOOTSTRAP.md"
private const MEMORY_FILENAME = "MEMORY.md"
private const MEMORY_ALT_FILENAME = "memory.md"

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
