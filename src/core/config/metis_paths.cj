package metis.core.config

import std.env.getVariable
import std.fs.{Path, Directory, canonicalize, exists}

public class MetisPaths {
    private static func resolveExistingPath(raw: String): Option<Path> {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return None
        }
        let path = Path(trimmed)
        if (!exists(path)) {
            return None
        }
        try {
            Some(canonicalize(path))
        } catch (_: Exception) {
            Some(path)
        }
    }

    private static func directoryContainingCjpmToml(start: Path): Option<Path> {
        try {
            var cur = canonicalize(start)
            var guard = 0
            while (guard < 96) {
                if (exists(cur.join("cjpm.toml"))) {
                    return Some(cur)
                }
                let parent = cur.parent
                if (parent == cur) {
                    break
                }
                cur = parent
                guard += 1
            }
        } catch (_: Exception) {
            ()
        }
        None
    }

    public static func homeRoot(): Path {
        match (getVariable("METIS_HOME")) {
            case Some(raw) =>
                let trimmed = raw.trimAscii()
                if (!trimmed.isEmpty()) {
                    let p = Path(trimmed)
                    if (!exists(p)) {
                        Directory.create(p, recursive: true)
                    }
                    return p
                }
            case None => ()
        }
        let home = match (getVariable("HOME")) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { t } else { getVariable("USERPROFILE").getOrDefault { "." }.trimAscii() }
            case None => getVariable("USERPROFILE").getOrDefault { "." }.trimAscii()
        }
        let root = Path(home).join(".metis")
        if (!exists(root)) {
            Directory.create(root, recursive: true)
        }
        root
    }

    public static func workspaceRoot(): Path {
        try {
            return canonicalize(Path("."))
        } catch (_: Exception) {
            ()
        }
        match (getVariable("PWD")) {
            case Some(raw) =>
                if (let Some(path) <- resolveExistingPath(raw)) {
                    return path
                }
            case None => ()
        }
        let fallback = homeRoot()
        if (!exists(fallback)) {
            Directory.create(fallback, recursive: true)
        }
        fallback
    }

    public static func projectRoot(): Option<Path> {
        match (getVariable("METIS_CJPM_ROOT")) {
            case Some(raw) =>
                if (let Some(path) <- resolveExistingPath(raw)) {
                    if (exists(path.join("cjpm.toml"))) {
                        return Some(path)
                    }
                }
            case None => ()
        }
        match (directoryContainingCjpmToml(Path("."))) {
            case Some(root) => return Some(root)
            case None => ()
        }
        directoryContainingCjpmToml(workspaceRoot())
    }

    public static func bundledSkillsRoot(): Option<Path> {
        match (projectRoot()) {
            case Some(root) => Some(root.join("skills"))
            case None => None
        }
    }

    public static func configPath(): Path {
        homeRoot().join("metis.json")
    }

    public static func modelsRuntimePath(): Path {
        homeRoot().join("models.json")
    }
}
