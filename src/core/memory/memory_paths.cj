package metis.core.memory

import metis.core.config.CliConfig

import std.fs.{Directory, Path, exists}

public class MemoryPaths {
    public static let DREAMING_CRON_NAME = "Memory Dreaming Promotion"
    public static let DREAMING_SYSTEM_EVENT = "__magic_cli_memory_dreaming_sweep__"
    public static let DREAMING_LIGHT_CRON_NAME = "Memory Light Dreaming"
    public static let DREAMING_LIGHT_SYSTEM_EVENT = "__magic_cli_memory_dreaming_light__"
    public static let DREAMING_REM_CRON_NAME = "Memory REM Dreaming"
    public static let DREAMING_REM_SYSTEM_EVENT = "__magic_cli_memory_dreaming_rem__"

    public static func memoryDotDir(): Path {
        let dir = CliConfig.dotDir.join("memory")
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        dir
    }

    public static func indexStorePath(): Path {
        memoryDotDir().join("index.json")
    }

    public static func sqliteStorePath(): Path {
        memoryDotDir().join("index.sqlite")
    }

    public static func shortTermRecallPath(): Path {
        memoryDotDir().join("short-term-recall.json")
    }

    public static func promotedAuditPath(): Path {
        memoryDotDir().join("promoted.txt")
    }

    public static func durableMemoryPath(): Path {
        let primary = CliConfig.cwd.join("MEMORY.md")
        let legacy = CliConfig.cwd.join("memory.md")
        if (exists(primary)) {
            return primary
        }
        if (exists(legacy)) {
            return legacy
        }
        primary
    }

    public static func dreamsDirPath(): Path {
        let dir = CliConfig.cwd.join("memory").join(".dreams")
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        dir
    }

    public static func dreamsMarkdownPath(): Path {
        let primary = CliConfig.cwd.join("DREAMS.md")
        let legacy = CliConfig.cwd.join("dreams.md")
        if (exists(primary)) {
            return primary
        }
        if (exists(legacy)) {
            return legacy
        }
        primary
    }

    public static func ensureWorkspaceMemoryDir(): String {
        let memoryDir = CliConfig.cwd.join("memory")
        if (!exists(memoryDir)) {
            Directory.create(memoryDir, recursive: true)
            return memoryDir.toString()
        }
        ""
    }
}
