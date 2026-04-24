package metis.core.tools.fs_utils

import magic.utils.readFile

import std.fs.*
import std.io.*
import std.collection.*

/**
 * Reads and returns the full content of a single file with line numbers.
 * Similar to Unix cat -n command, shows content with line numbers for easy reference.
 *
 * @param filePath Absolute path to the file to read
 * @return String containing the full file content with line numbers
 */
public func cat(filePath: String): String {
    let path = Path(filePath)
    if (!path.isAbsolute()) {
        return "File path must be absolute"
    }
    if (!exists(path)) {
        return "File does not exist: ${filePath}"
    }
    if (!FileInfo(path).isRegular()) {
        return "Path is not a regular file: ${filePath}"
    }

    try {
        return readFile(path, withLineNumber: true)
    } catch (e: FSException) {
        return "Failed to read file: ${e}"
    } catch (e: Exception) {
        return "Error reading file: ${e}"
    }
    throw UnsupportedException("Unreachable")
}

/**
 * Reads and returns a specific range of lines from a file with line numbers.
 * Useful for viewing specific sections of large files.
 *
 * @param filePath Absolute path to the file to read
 * @param startLine Starting line number (1-based, inclusive)
 * @param endLine Ending line number (1-based, inclusive). If 0 or negative, reads to end of file
 * @return String containing the specified line range with line numbers
 */
public func catRange(filePath: String, startLine: Int64, endLine!: Int64 = Int64.Max): String {
    let path = Path(filePath)
    if (!path.isAbsolute()) {
        return "File path must be absolute"
    }
    if (!exists(path)) {
        return "File does not exist: ${filePath}"
    }
    if (!FileInfo(path).isRegular()) {
        return "Path is not a regular file: ${filePath}"
    }
    if (startLine <= 0) {
        return "Start line must be positive (1-based)"
    }
    if (endLine > 0 && endLine < startLine) {
        return "End line must be greater than or equal to start line"
    }

    try(file = File(filePath, Read)) {
        // Not read file with line number because it's prone to make the LLM mistake
        return readFile(path, withLineNumber: false, startLine: startLine, endLine: endLine)
    } catch (e: FSException) {
        return "Failed to read file: ${e}"
    } catch (e: Exception) {
        return "Error reading file: ${e}"
    }
    throw UnsupportedException("Unreachable")
}