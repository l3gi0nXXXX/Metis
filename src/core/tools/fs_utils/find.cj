package metis.core.tools.fs_utils

import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.collection.*
import std.regex.Regex

/**
 * Backup
 * Currently, we do not provide a find tool
 */
public func find(rootPath: String, pattern: String): ArrayList<String> {
    let results = ArrayList<String>()
    let root = Path(rootPath)

    if (!exists(root)) {
        return results
    }

    let regex = Regex(pattern)
    findRecursive(root, regex, results)

    return results
}

private func findRecursive(currentPath: Path, pattern: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemName = item.name
        let itemPath = item.path

        if (ignored(itemPath)) {
            continue
        }

        if (pattern.matches(itemName)) {
            results.add(itemPath.toString())
        }

        if (item.isDirectory()) {
            findRecursive(itemPath, pattern, results)
        }
    }
}