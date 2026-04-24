package metis.core.tools.fs_utils

import std.fs.*
import std.collection.*
import std.collection.concurrent.ConcurrentHashMap
import std.process.executeWithOutput
import std.sync.Mutex
import metis.core.config.CliConfig

// Predefined black-list of directories (static fallback)
let IGNORED_DIR = HashSet<String>([".git", ".metis", ".cache", "node_modules", "bower_components", "build", "target"])
let gitCheckIgnoreCache = ConcurrentHashMap<String, Bool>()

// Global flag and repo root for workspace-level git detection (initialized once)
let workspaceGitInitMutex = Mutex()
var workspaceIsGitRepo: Option<Bool> = None
var workspaceGitRepoRoot: Option<String> = None

// Initialize workspace git detection (thread-safe, only once)
private func ensureWorkspaceGitInited(): Unit {
    if (workspaceIsGitRepo != None) {
        return
    }
    synchronized(workspaceGitInitMutex) {
        if (workspaceIsGitRepo == None) {
            try {
                let cwdStr = try { canonicalize(CliConfig.cwd).toString() } catch (_) { CliConfig.cwd.toString() }
                let gitDir = CliConfig.cwd.join(".git")
                if (exists(gitDir)) {
                    workspaceIsGitRepo = Some(true)
                    workspaceGitRepoRoot = Some(cwdStr)
                } else {
                    workspaceIsGitRepo = Some(false)
                    workspaceGitRepoRoot = None
                }
            } catch (_: Exception) {
                // automatic downgrade
                workspaceIsGitRepo = Some(false)
                workspaceGitRepoRoot = None
            }
        }
    }
}

public func ignored(path: Path): Bool {
    let fileName = path.fileName
    
    // Ensure workspace git detection is initialized (only once, thread-safe)
    ensureWorkspaceGitInited()
    
    // Use workspace-level git detection result
    if (let Some(false) <- workspaceIsGitRepo) {
        return IGNORED_DIR.contains(fileName)
    }

    let gitRepoRoot = workspaceGitRepoRoot

    // Git project: use .gitignore rules + IGNORED_DIR
    if (fileName == ".gitignore") {
        return false
    }

    if (IGNORED_DIR.contains(fileName)) {
        return true
    }

    try {
        if (let Some(repoRoot) <- gitRepoRoot) {
            // Convert absolute path to relative path from git repo root
            let absPath = try { canonicalize(path).toString() } catch (_) { path.toString() }
            let repoRootNormalized = repoRoot.replace("\\", "/")
            let absPathNormalized = absPath.replace("\\", "/")
            
            var pathStr = absPathNormalized
            if (absPathNormalized.startsWith(repoRootNormalized)) {
                // Calculate relative path from repo root
                var rel = absPathNormalized[repoRootNormalized.size..]
                if (rel.startsWith("/")) {
                    rel = rel[1..]
                }
                pathStr = rel
            }
            
            // Exit code 0: ignored, 1: not ignored
            let cacheKey = "${repoRoot}|${pathStr}"
            if (gitCheckIgnoreCache.contains(cacheKey)) {
                if (gitCheckIgnoreCache[cacheKey]) {
                    return true
                }
            } else {
                try {
                    let (exitCode, _, _) = executeWithOutput("git", ["-C", repoRoot, "check-ignore", "--no-index", "-q", pathStr])
                    let isIgnored = exitCode == 0
                    gitCheckIgnoreCache[cacheKey] = isIgnored
                    if (isIgnored) {
                        return true
                    }
                } catch (_: Exception) {
                    gitCheckIgnoreCache[cacheKey] = false
                }
            }
        }
    } catch (e: Exception) {
        // If git command fails, fall through to return false (non-git project)
    }
    return false
}
