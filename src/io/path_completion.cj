package metis.io

import std.collection.*
import std.fs.*
import metis.core.config.CliConfig
import std.sort.sort

/**
 * Convert a file path to Unix-style format with forward slashes
 * Optionally adds a trailing slash for directory paths
 *
 * @param pathStr The input path string to convert
 * @param appendSuffix Whether to ensure the path ends with "/" (default: false)
 * @return The path converted to Unix-style format
 */
private func toUnixStyle(pathStr: String, appendSuffix!: Bool = false): String {
    if (appendSuffix) {
        var unixPath = pathStr.replace("\\", "/")
        if (!unixPath.endsWith("/")) {
            unixPath = unixPath + "/"
        }
        return unixPath
    } else {
        return pathStr.replace("\\", "/")
    }
}

/**
 * List files and directories matching a given prefix for path completion
 * This function is used in readline_2 for @path completion functionality
 *
 * The function handles:
 * - Incomplete path inputs by looking at the parent directory
 * - Unix-style path normalization for cross-platform compatibility
 * - Directory vs file differentiation (directories get "/" suffix)
 * - Sorted output with directories appearing first
 * - Filtering out hidden files (starting with '.')
 *
 * @param workDir The base working directory to search in (default: current working directory)
 * @param prefix The path prefix to filter results by (default: empty string)
 * @return Array of matching file/directory paths, sorted with directories first
 */
func getPathCompletionList(workDir!: Path = CliConfig.cwd, prefix!: String = ""): Array<String> {
    // Try to construct the target path from workDir + prefix
    var targetPath = try {
        workDir.join(prefix)
    } catch (e: FSException) { // Invalid path combination
        return []
    }

    // Get normalized base path with trailing slash for string replacement
    let normalizedBasePath = toUnixStyle(workDir.normalize().toString(), appendSuffix: true)

    // Determine which directory to scan based on path existence
    let searchDirectory = if (exists(targetPath)) {
        FileInfo(targetPath)
    } else if (exists(targetPath.parent)) { // Handle incomplete path input
        FileInfo(targetPath.parent)
    } else {
        return [] // Neither target nor parent exists
    }

    // Only scan directories
    if (!searchDirectory.isDirectory()) {
        return []
    }

    let matchingFiles = ArrayList<String>()

    // Walk through all files in the search directory
    Directory.walk(searchDirectory.path) {
        currentFile: FileInfo =>
        // Normalize and convert to Unix-style relative path
        var relativePath = currentFile.path.normalize().toString()
        relativePath = toUnixStyle(relativePath).replace(normalizedBasePath, "")

        // Filter: must start with prefix and not be hidden
        if (!relativePath.startsWith(prefix) || relativePath.startsWith('.')) {
            return true // Continue walking
        }

        // Add appropriate suffix based on file type
        if (currentFile.isDirectory()) {
            matchingFiles.add(relativePath + "/")
        } else {
            matchingFiles.add(relativePath)
        }
        true // Continue walking
    }

    let resultArray = matchingFiles.toArray()

    // Sort results with directories appearing first
    // This is achieved by prepending '\0' to directory paths during comparison
    sort(
        resultArray,
        by: {
            firstPath: String, secondPath: String =>
            var sortKey1 = firstPath
            var sortKey2 = secondPath

            // Directories get '\0' prefix to sort first (since '\0' < any printable char)
            if (sortKey1.endsWith('/')) {
                sortKey1 = '\0' + sortKey1
            }
            if (sortKey2.endsWith('/')) {
                sortKey2 = '\0' + sortKey2
            }

            // Standard string comparison
            if (sortKey1 > sortKey2) {
                return Ordering.GT
            } else if (sortKey1 == sortKey2) {
                return Ordering.EQ
            } else {
                return Ordering.LT
            }
        },
        stable: true // Preserve original order for equal elements
    )

    return resultArray
}
