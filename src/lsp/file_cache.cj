package metis.lsp

import std.collection.*
import std.io.*
import std.fs.*

class FileCache {
    private let cache = HashMap<String, String>()

    private let lineCache = HashMap<String, Array<String>>()

    private func pathToKey(path: Path): String {
        return canonicalize(path).toString()
    }

    /**
     * Invalidates the cache for the given file path.
     */
    public func invalidateCache(path: Path): Unit {
        let pathKey = this.pathToKey(path)
        this.cache.remove(pathKey)
        this.lineCache.remove(pathKey)
    }

    public func getFileContent(path: String): String {
        return getFileContent(Path(path))
    }

    public func getFileContent(path: Path): String {
        let pathKey = this.pathToKey(path)
        if (this.cache.contains(pathKey)) {
            return this.cache[pathKey]
        }

        let content = readFileContent(path)
        this.cache[pathKey] = content
        return content
    }

    /**
     * Returns the content of a specific range in a file.
     * @param path Path to the file
     * @param range Range to extract (0-based)
     */
    public func getFileRangeContent(path: Path, range: Range): String {
        let lines = this.getFileLines(path, range.start.line, range.end.line)
        if (lines.size == 1) {
            return lines[0][range.start.character..range.end.character]
        }
        let strBuilder = StringBuilder(lines[0][range.start.character..]) // Add the first line
        for (i in 1..lines.size-1) {
            strBuilder.append("\n${lines[i]}\n") // Add middle lines
        }
        strBuilder.append(lines[lines.size-1][0..range.end.character]) // Add the last line
        return strBuilder.toString()
    }

    private func getFileLines(path: Path, startLine: Int64, endLine: Int64): Array<String> {
        let pathKey = this.pathToKey(path)
        let lines = if (this.lineCache.contains(pathKey)) {
            this.lineCache[pathKey]
        } else {
            let lines = this.getFileContent(pathKey).split("\n")
            this.lineCache.add(pathKey, lines)
            lines
        }

        if (startLine < 0 || endLine < 0 || startLine > endLine) {
            return []
        }

        let actualEndLine = min(lines.size, endLine)

        if (startLine > lines.size) {
            return []
        }
        return lines[(startLine)..=(actualEndLine)]
    }

    private func readFileContent(path: Path): String {
        return String.fromUtf8(File.readFrom(path))
    }

    public func clearAll(): Unit {
        this.cache.clear()
        this.lineCache.clear()
    }
}