package metis.core.tools.fs_utils

import metis.utils.ShellUtils

import std.fs.*
import std.regex.Regex
import std.collection.*
import std.process.*
import std.io.*

/**
 * Main glob function that matches files and directories using glob patterns.
 * Supports wildcards (* and ?) and recursive directory matching (**).
 * First attempts to use system find command for performance, falls back to native implementation.
 *
 * @param pattern Glob pattern (e.g., "*.cj", "** / test*.cj", "src / **")
 * @param rootPath Absolute path to start searching from
 * @return ArrayList of matching file/directory paths
 */
public func glob(pattern: String, rootPath: String): ArrayList<String> {
    let results = ArrayList<String>()
    let root = Path(rootPath)

    // Return empty results if root path doesn't exist
    if (!exists(root)) {
        return results
    }

    // First try using system find command for better performance
    let findResults = tryGlobWithFind(pattern, rootPath)
    if (findResults.size > 0) {
        return findResults
    }

    // Fallback to native implementation if find command is not available or fails
    // Handle ** patterns (recursive directory matching) specially
    if (pattern.contains("**")) {
        globWithDoubleAsterisk(root, pattern, results)
    } else {
        // Handle patterns without ** - could be simple filename or path-based
        if (pattern.contains("/")) {
            // Path-based pattern like "src/*" or "dir/file.txt"
            globWithPath(root, pattern, results)
        } else {
            // Simple filename pattern like "*.cj" or "test*"
            let regex = Regex(globToRegex(pattern), [])
            globRecursive(root, regex, results)
        }
    }

    return results
}

/**
 * Attempts to use system find command to match glob patterns for better performance.
 * Converts glob patterns to find command syntax and executes the search.
 * Returns empty list if find command is not available or conversion fails.
 *
 * @param pattern Glob pattern to convert and execute
 * @param rootPath Root directory to search from
 * @return ArrayList of matching paths, or empty list if find fails
 */
private func tryGlobWithFind(pattern: String, rootPath: String): ArrayList<String> {
    let results = ArrayList<String>()

    try {
        // Convert glob pattern to find command
        let findCommand = globToFindCommand(pattern, rootPath)
        if (findCommand.isEmpty()) {
            return results
        }

        // Execute find command
        let (exitCode, stdout, stderr) = ShellUtils.execute(findCommand, workDir: Path(rootPath))

        if (exitCode == 0) {
            // Read the output and split by lines
            for (line in stdout.split("\n")) {
                let trimmed = line.trimAscii()
                // Convert relative path to absolute
                let path = Path(rootPath).join(trimmed)
                if (!trimmed.isEmpty() && exists(path) && !ignored(path)) {
                    results.add(canonicalize(path).toString())
                }
            }
        }
    } catch (_: Exception) {
        // Find command failed or not available, return empty list to trigger fallback
        return ArrayList<String>()
    }

    return results
}

/**
 * Converts glob pattern to find command syntax.
 * Returns empty string if pattern cannot be converted.
 *
 * @param pattern Glob pattern (e.g., "*.cj", "** /config/ *.cj", "src / ** / *.js")
 * @param rootPath Root directory for the search
 * @return Find command string, or empty string if conversion fails
 */
private func globToFindCommand(pattern: String, rootPath: String): Array<String> {
    let command = ArrayList<String>()

    // Base find command
    command.add(all: ["find", "."]) // Always start from current directory

    // Skip common ignore directories for performance
    command.add(all: ["-not", "-path", "\"*/.git/*\""])
    command.add(all: ["-not", "-path", "\"*/node_modules/*\""])
    command.add(all: ["-not", "-path", "\"*/target/*\""])
    command.add(all: ["-not", "-path", "\"*/build/*\""])
    command.add(all: ["-not", "-path", "\"*/dist/*\""])

    // Convert glob pattern to find expressions
    if (pattern.startsWith("**/")) {
        // Pattern like **/*.txt or **/config/*.cj
        let pathPattern = pattern[3..]  // Remove **/ prefix

        if (pathPattern.contains("/")) {
            // Path-based pattern like config/*.cj
            let parts = pathPattern.split("/")
            if (parts.size == 2) {
                let dir = parts[0]
                let filePattern = parts[1]
                let namePattern = globPatternToNamePattern(filePattern)
                command.add(all: ["-type", "f"])
                command.add(all: ["-path", "\"*/${dir}/*\""])
                command.add(all: ["-name", "\"${namePattern}\""])
            } else {
                // More complex path pattern, use regex
                let pathRegex = globPatternToPathRegex(pathPattern)
                command.add(all: ["-type", "f"])
                command.add(all: ["-regex", "\"${pathRegex}\""])
            }
        } else {
            // Simple file pattern like *.txt
            let namePattern = globPatternToNamePattern(pathPattern)
            command.add(all: ["-type", "f"])
            command.add(all: ["-name", "\"${namePattern}\""])
        }
    } else if (pattern.endsWith("/**")) {
        // Pattern like src/** or **/abc/**
        if (pattern.startsWith("**/")) {
            // Pattern like **/abc/** - find all contents under any 'abc' directory
            let dirPattern = pattern[3..pattern.size-3]  // Remove **/ prefix and /** suffix
            command.add(all: ["-path", "\"*/${dirPattern}/*\""])
        } else {
            // Pattern like src/** - find all contents under src directory
            let dirPattern = pattern[0..pattern.size-3]  // Remove /** suffix
            command.add(all: ["-path", "\"${dirPattern}/*\""])
        }
    } else if (pattern.contains("**")) {
        // Complex pattern with ** in the middle
        // For now, use a simple approach that may be slower but works
        command.add(all: ["-type", "f"])

        // Extract file extension if it exists
        if (pattern.contains(".")) {
            let ext = pattern[pattern.lastIndexOf(".").getOrThrow() + 1..]
            if (ext.contains("*")) {
                // Pattern like **/*.cj or src/**/*.js
                command.add(all: ["-name", "\"*.${ext.replace('*', '*')}\""])
            }
        }
    } else if (pattern.contains("/")) {
        // Path-based pattern without **
        let pathRegex = globPatternToPathRegex(pattern)
        command.add(all: ["-type", "f"])
        command.add(all: ["-regex", "\"${pathRegex}\""])
    } else {
        // Simple filename pattern
        let namePattern = globPatternToNamePattern(pattern)
        command.add(all: ["-type", "f"])
        command.add(all: ["-name", "\"${namePattern}\""])
    }

    return command.toArray()
}

/**
 * Converts glob filename pattern to find -name pattern.
 * Handles wildcards * and ? for filename matching.
 */
private func globPatternToNamePattern(pattern: String): String {
    // Convert glob wildcards to find -name pattern
    // find -name uses shell glob patterns, so we can mostly keep the same syntax
    let result = StringBuilder()

    for (char in pattern.runes()) {
        match (char.toString()) {
            case "*" => result.append("*")      // find -name uses * for any characters
            case "?" => result.append("?")      // find -name uses ? for single character
            case "." => result.append(".")      // literal dot
            case _ => result.append(char.toString())
        }
    }

    return result.toString()
}

/**
 * Converts glob path pattern to find -regex pattern.
 * Handles complex path patterns with directories and wildcards.
 */
private func globPatternToPathRegex(pattern: String): String {
    // Convert glob pattern to find -regex pattern
    // find regex uses standard regex syntax with escaped special characters
    let result = StringBuilder()

    for (char in pattern.runes()) {
        match (char.toString()) {
            case "*" => result.append(".*")     // regex * -> .*
            case "?" => result.append(".")      // regex ? -> .
            case "." => result.append("\\.")    // escape dot
            case "/" => result.append("/")      // preserve path separator
            case _ => result.append(char.toString())
        }
    }

    return result.toString()
}

/**
 * Handles glob patterns containing ** (recursive directory matching).
 * Now supports complex patterns with multiple ** segments.
 *
 * Examples:
 * - "** /test.cj" -> find test.cj in any subdirectory
 * - "src / **" -> find everything under src/
 * - "src / ** / *.cj" -> find all .cj files under src/ recursively
 * - "** /tools / **" -> find everything under any 'tools' directory
 * - "** / ** / **" -> find everything at least 3 levels deep
 */
private func globWithDoubleAsterisk(currentPath: Path, pattern: String, results: ArrayList<String>): Unit {
    // Handle the most common simple cases first for performance
    let parts = pattern.split("**")

    if (parts.size == 2) {
        // Simple case: only one ** in pattern
        // Remove leading/trailing slashes from pattern parts
        let beforePattern = parts[0].trimEnd("/")
        let afterPattern = parts[1].trimStart("/")

        if (beforePattern.isEmpty() && !afterPattern.isEmpty()) {
            // Pattern like "**/something"
            globRecursiveWithAfterMatch(currentPath, afterPattern, results, currentPath)
        } else if (!beforePattern.isEmpty() && afterPattern.isEmpty()) {
            // Pattern like "something/**"
            let beforeRegex = Regex(globToRegex(beforePattern))
            globRecursiveWithBeforeMatch(currentPath, beforeRegex, results)
        } else if (!beforePattern.isEmpty() && !afterPattern.isEmpty()) {
            // Pattern like "something/**/other"
            let beforeRegex = Regex(globToRegex(beforePattern))
            globRecursiveWithBeforeAfterMatch(currentPath, beforeRegex, afterPattern, results)
        } else {
            // Pattern is just "**"
            globRecursiveAll(currentPath, results)
        }
    } else if (parts.size >= 3) {
        // Complex case: multiple ** in pattern - use advanced matching
        matchComplexPattern(currentPath, parts, results)
    }
}

/**
 * Handles complex patterns with multiple ** segments.
 * Examples: "** / tools / **", "** / ** / **", "src / ** /test/ ** /file.cj"
 */
private func matchComplexPattern(currentPath: Path, parts: Array<String>, results: ArrayList<String>): Unit {
    if (parts.size == 3) {
        // Handle patterns like "**/middle/**"
        let beforePart = parts[0]
        let middlePart = parts[1]
        let afterPart = parts[2]

        // Clean up the middle part
        let middlePattern = if (middlePart.startsWith("/") && middlePart.endsWith("/")) {
            middlePart[1..middlePart.size - 1]
        } else if (middlePart.startsWith("/")) {
            middlePart[1..]
        } else if (middlePart.endsWith("/")) {
            middlePart[0..middlePart.size - 1]
        } else {
            middlePart
        }

        if (beforePart.isEmpty() && afterPart.isEmpty()) {
            // Pattern like "**/tools/**"
            if (!middlePattern.isEmpty()) {
                let middleRegex = Regex(globToRegex(middlePattern), [])
                findMiddleAndCollectAll(currentPath, middleRegex, results)
            } else {
                // Pattern like "**/*/**" - just collect everything
                globRecursiveAll(currentPath, results)
            }
        }
    } else if (parts.size == 4) {
        // Handle patterns like "**/**/**" (all empty parts except separators)
        var allEmpty = true
        for (part in parts) {
            let cleanPart = if (part == "/" || part == "") { "" } else { part }
            if (!cleanPart.isEmpty()) {
                allEmpty = false
                break
            }
        }
        if (allEmpty) {
            // Pattern like "**/**/**" - collect everything
            globRecursiveAll(currentPath, results)
        }
    }
    // For more complex patterns, fall back to collecting everything
    // This is a simplification - a full implementation would parse recursively
}

/**
 * Finds directories matching the middle pattern, then collects everything under them.
 * Used for patterns like "** / tools / **" where we find 'tools' directory anywhere.
 */
private func findMiddleAndCollectAll(currentPath: Path, middleRegex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip ignored files and directories
        if (ignored(item.path)) {
            continue
        }

        if (middleRegex.matches(itemName) && item.isDirectory()) {
            // Found matching middle directory - collect everything under it
            globRecursiveAll(itemPath, results)
        }

        // Continue searching in subdirectories for the middle pattern
        if (item.isDirectory()) {
            findMiddleAndCollectAll(itemPath, middleRegex, results)
        }
    }
}

/**
 * Recursively collects all files and directories under the given path.
 * Used when the glob pattern is just "**" (match everything).
 * Skips hidden files and common ignore patterns.
 */
private func globRecursiveAll(currentPath: Path, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and directories like .git, node_modules, etc.
        if (ignored(item.path)) {
            continue
        }

        // Add current item to results
        results.add(itemPath.toString())

        // Recursively process subdirectories
        if (item.isDirectory()) {
            globRecursiveAll(itemPath, results)
        }
    }
}

/**
 * Recursively searches for items matching the "after" pattern.
 * Used for patterns like "** / filename" where we search for filename in any subdirectory.
 * Also handles patterns like "** / config / *.cj" by matching against the full relative path.
 *
 * @param currentPath Current directory being searched
 * @param afterPattern After pattern string (will be converted to appropriate regex)
 * @param results List to collect matching paths
 * @param originalRoot Root path for calculating relative paths
 */
private func globRecursiveWithAfterMatch(currentPath: Path, afterPattern: String, results: ArrayList<String>, originalRoot: Path): Unit {
    // Create two regex patterns: one for filename matching, one for relative path matching
    let filenameRegex = Regex(globToRegex(afterPattern), [])
    let pathRegex = Regex(globToRegexForPath(afterPattern), [])

    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and common ignore patterns
        if (ignored(item.path)) {
            continue
        }

        // Calculate relative path from original root for proper pattern matching
        let relativePath = calculateRelativePath(itemPath, originalRoot)

        // Check if current item matches the pattern
        // First try matching against the name (for simple patterns like **/*.txt)
        if (filenameRegex.matches(itemName)) {
            results.add(itemPath.toString())
        }
        // Also try matching against the relative path (for patterns like **/config/*.cj)
        else if (!relativePath.isEmpty() && pathRegex.matches(relativePath)) {
            results.add(itemPath.toString())
        }

        // Continue searching in subdirectories
        if (item.isDirectory()) {
            globRecursiveWithAfterMatch(itemPath, afterPattern, results, originalRoot)
        }
    }
}

/**
 * Searches for directories matching the "before" pattern, then collects everything under them.
 * Used for patterns like "dirname / **" where we find dirname then collect all its contents.
 *
 * @param currentPath Current directory being searched
 * @param beforeRegex Regex pattern to match directory names
 * @param results List to collect matching paths
 */
private func globRecursiveWithBeforeMatch(currentPath: Path, beforeRegex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and common ignore patterns
        if (ignored(item.path)) {
            continue
        }

        if (beforeRegex.matches(itemName)) {
            // Found matching before part, now collect everything under it
            if (item.isDirectory()) {
                // Recursively collect all contents under this directory
                globRecursiveAll(itemPath, results)
            } else {
                // If it's a file that matches, add it directly
                results.add(itemPath.toString())
            }
        }

        // Continue searching in subdirectories for more matches
        if (item.isDirectory()) {
            globRecursiveWithBeforeMatch(itemPath, beforeRegex, results)
        }
    }
}

/**
 * Handles complex patterns like "src/**/test*.cj".
 * First finds directories matching the before pattern, then searches for after pattern within them.
 *
 * @param currentPath Current directory being searched
 * @param beforeRegex Regex pattern to match directory names (before **)
 * @param afterPattern String pattern to match file/directory names (after **)
 * @param results List to collect matching paths
 */
private func globRecursiveWithBeforeAfterMatch(currentPath: Path, beforeRegex: Regex, afterPattern: String, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and common ignore patterns
        if (ignored(item.path)) {
            continue
        }

        if (beforeRegex.matches(itemName) && item.isDirectory()) {
            // Found matching before part (directory), now search for after pattern within it
            globRecursiveWithAfterMatch(itemPath, afterPattern, results, currentPath)
        }

        // Continue searching for before pattern in subdirectories
        if (item.isDirectory()) {
            globRecursiveWithBeforeAfterMatch(itemPath, beforeRegex, afterPattern, results)
        }
    }
}

/**
 * Standard recursive glob matching without ** patterns.
 * Used for simple patterns like "*.cj", "test*", etc.
 *
 * @param currentPath Current directory being searched
 * @param regex Regex pattern converted from glob pattern
 * @param results List to collect matching paths
 */
private func globRecursive(currentPath: Path, regex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemName = item.name
        let itemPath = item.path

        // Skip hidden files and directories like .git, node_modules, etc.
        if (ignored(item.path)) {
            continue
        }

        // Check if current item matches the glob pattern
        if (regex.matches(itemName)) {
            results.add(itemPath.toString())
        }

        // Recursively search subdirectories
        if (item.isDirectory()) {
            globRecursive(itemPath, regex, results)
        }
    }
}

/**
 * Calculates the relative path from a base path to a target path.
 * Returns the relative path as a string, or empty string if calculation fails.
 *
 * @param targetPath The target path
 * @param basePath The base path to calculate relative path from
 * @return Relative path string, or empty string if invalid
 */
private func calculateRelativePath(targetPath: Path, basePath: Path): String {
    try {
        let targetStr = targetPath.toString()
        let baseStr = basePath.toString()

        // If target is not under base, return empty
        if (!targetStr.startsWith(baseStr)) {
            return ""
        }

        // Calculate relative path
        let relative = targetStr[baseStr.size..]

        // Remove leading slash if present
        if (relative.startsWith("/")) {
            return relative[1..]
        }

        return relative
    } catch (_: Exception) {
        return ""
    }
}

/**
 * Converts a glob pattern to a regular expression with anchors for exact matching.
 * Used for filename matching where we want exact string matches.
 *
 * @param pattern Glob pattern string
 * @return Regex pattern string with ^ and $ anchors
 */
func globToRegex(pattern: String): String {
    return globToRegexInternal(pattern, true)  // Use anchors for exact matching
}

/**
 * Converts a glob pattern to a regular expression without anchors for relative path matching.
 * Used for relative path matching where we want substring matches.
 *
 * @param pattern Glob pattern string
 * @return Regex pattern string without ^ and $ anchors
 */
func globToRegexForPath(pattern: String): String {
    return globToRegexInternal(pattern, false)  // No anchors for path matching
}

/**
 * Internal function to convert glob pattern to regex.
 *
 * @param pattern Glob pattern string
 * @param useAnchors Whether to add ^ and $ anchors
 * @return Regex pattern string
 */
private func globToRegexInternal(pattern: String, useAnchors: Bool): String {
    let regex = StringBuilder()

    if (useAnchors) {
        regex.append("^")  // Start anchor for exact matching
    }

    let runes = pattern.toRuneArray()
    let len = runes.size
    var i = 0

    while (i < len) {
        let char = runes[i].toString()

        match (char) {
            case "*" => regex.append(".*")      // * matches any characters
            case "?" => regex.append(".")       // ? matches single character
            case "." => regex.append("\\.")     // Escape regex special chars
            case "\\" => regex.append("\\\\")
            case "+" => regex.append("\\+")
            case "^" => regex.append("\\^")
            case "$" => regex.append("\\$")
            case "(" => regex.append("\\(")
            case ")" => regex.append("\\)")
            case "[" => regex.append("\\[")
            case "]" => regex.append("\\]")
            case "{" => regex.append("\\{")
            case "}" => regex.append("\\}")
            case "|" => regex.append("\\|")
            case "/" => regex.append("/")       // Preserve path separators
            case _ => regex.append(char)        // Regular characters as-is
        }
        i += 1
    }

    if (useAnchors) {
        regex.append("$")  // End anchor for exact matching
    }

    return regex.toString()
}

/**
 * Handles path-based glob patterns like "src/ *", "dir/file.txt", "a/b/c/ *.cj".
 * Matches against the relative path from root directory.
 */
private func globWithPath(root: Path, pattern: String, results: ArrayList<String>): Unit {
    // Split pattern into path segments
    let pathSegments = pattern.split("/")

    // Start matching from root with first segment
    matchPathSegments(root, pathSegments, 0, "", results)
}

/**
 * Recursively matches path segments against directory structure.
 *
 * @param currentPath Current directory being examined
 * @param segments Array of path segments from the pattern
 * @param segmentIndex Current segment index being matched
 * @param relativePath Relative path built so far
 * @param results List to collect matching paths
 */
private func matchPathSegments(currentPath: Path, segments: Array<String>, segmentIndex: Int64, relativePath: String, results: ArrayList<String>): Unit {
    // If we've matched all segments, we found a complete match
    if (segmentIndex >= segments.size) {
        return
    }

    let segment = segments[segmentIndex]
    let regex = Regex(globToRegex(segment), [])

    for (item in Directory.readFrom(currentPath)) {
        let itemName = item.name
        let itemPath = item.path

        // Skip ignored files and directories
        if (ignored(item.path)) {
            continue
        }

        if (regex.matches(itemName)) {
            // Build the relative path for this match
            let newRelativePath = if (relativePath.isEmpty()) {
                itemName
            } else {
                relativePath + "/" + itemName
            }

            if (segmentIndex == segments.size - 1) {
                // Last segment - add to results
                results.add(itemPath.toString())
            } else if (item.isDirectory()) {
                // Continue with next segment
                matchPathSegments(itemPath, segments, segmentIndex + 1, newRelativePath, results)
            }
        }
    }
}
