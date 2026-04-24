package metis.core.tools.fs_utils

import std.fs.*
import std.io.*
import std.collection.*

/**
 * Returns the first N lines of a file.
 * Useful for quickly inspecting the beginning of large files without loading the entire content.
 *
 * @param filePath Absolute path to the file to read
 * @param lines Number of lines to return (defaults to 10)
 * @return String containing the first N lines with line numbers
 */
public func head(filePath: String, lines!: Int64 = 10): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    if (!exists(filePath)) {
        return "File does not exist: ${filePath}"
    }

    let path = Path(filePath)
    if (!FileInfo(path).isRegular()) {
        return "Path is not a regular file: ${filePath}"
    }

    if (lines <= 0) {
        return "Number of lines must be positive"
    }

    try(file = File(filePath, Read)) {
        let reader = StringReader(file)
        let result = StringBuilder()
        var lineNumber: Int64 = 1
        var linesRead: Int64 = 0

        while (linesRead < lines) {
            let line = if (let Some(line) <- reader.readln()) {
                line
            } else {
                // End of file reached
                break
            }
            // Format with line number (similar to cat -n)
            let lineNo = lineNumber.toString()
            result.append("${lineNo.padStart(6)}  ${line}\n")
            lineNumber += 1
            linesRead += 1
        }

        if (result.size == 0) {
            return "File is empty: ${filePath}"
        }

        return result.toString().trimAscii()

    } catch (e: FSException) {
        return "Failed to read file: ${e}"
    } catch (e: Exception) {
        return "Error reading file: ${e}"
    }
    throw UnsupportedException("Unreachable")
}

/**
 * Returns the first N lines of a file without line numbers.
 * Simpler version for when line numbers are not needed.
 *
 * @param filePath Absolute path to the file to read
 * @param lines Number of lines to return (defaults to 10)
 * @return String containing the first N lines without line numbers
 */
public func headSimple(filePath: String, lines!: Int64 = 10): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    if (!exists(filePath)) {
        return "File does not exist: ${filePath}"
    }

    let path = Path(filePath)
    if (!FileInfo(path).isRegular()) {
        return "Path is not a regular file: ${filePath}"
    }

    if (lines <= 0) {
        return "Number of lines must be positive"
    }

    try(file = File(filePath, Read)) {
        let result = StringBuilder()
        let reader = StringReader(file)
        var linesRead: Int64 = 0

        while (linesRead < lines) {
            let line = if (let Some(line) <- reader.readln()) {
                line
            } else {
                // End of file reached
                break
            }
            result.append("${line}\n")
            linesRead += 1
        }

        if (result.size == 0) {
            return "File is empty: ${filePath}"
        }

        return result.toString()
    } catch (e: FSException) {
        return "Failed to read file: ${e}"
    } catch (e: Exception) {
        return "Error reading file: ${e}"
    }
    throw UnsupportedException("Unreachable")
}