package metis.core.tools.fs_utils

import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.collection.*
import std.sort.sort

import magic.prelude.*
import magic.log.LogUtils

import metis.utils.*
import metis.core.config.CliConfig

/**
 * Maximum number of grep results to return (prevents context overflow)
 */
const MAX_GREP_MATCHES: Int64 = 100

/**
 * Main grep function that searches for a regular expression pattern within file contents.
 * Uses ripgrep if available, falls back to traditional grep/PowerShell.
 *
 * @param pattern The regular expression pattern to search for
 * @param path Optional directory path to search in (defaults to current working directory)
 * @param include Optional glob pattern to filter files (e.g., "*.cj", "*.{ts,tsx}")
 * @return String containing matching lines with file paths and line numbers
 */
public func grep(pattern: String, path: Option<String>, include: Option<String>): String {
    // Try ripgrep first, fall back to traditional grep
    if (let Some(rgPath) <- getRipgrepPath()) {
        return grepWithRipgrep(pattern, path, include, rgPath)
    } else {
        return grepWithTraditional(pattern, path, include)
    }
}

/**
 * Check if ripgrep is available in system PATH.
 */
private func getRipgrepPath(): Option<String> {
    try {
        let checkCommand = if (InfoUtils.os == "windows") { "where" } else { "which" }
        let (exitCode, stdOutData, _) = executeWithOutput(checkCommand, ["rg"])
        if (exitCode == 0) {
            let output = String.fromUtf8(stdOutData).trimAscii()
            if (!output.isEmpty() && (output.contains("rg.exe") || output.endsWith("rg"))) {
                try {
                    let (versionExitCode, _, _) = executeWithOutput("rg", ["--version"])
                    if (versionExitCode == 0) {
                        return Some("rg")
                    }
                } catch (e: Exception) {
                    // rg command exists but fails to run, continue to fallback
                }
            }
        }
    } catch (e: Exception) {
        // Command not found, continue to fallback
    }
    return None
}

/**
 * Grep implementation using ripgrep for better performance.
 */
private func grepWithRipgrep(pattern: String, path: Option<String>, include: Option<String>, rgPath: String): String {
    try {
        let rgCmd = ArrayList<String>([rgPath, "--line-number", "--with-filename", "--no-heading"])

        // Add glob pattern if specified
        if (let Some(includePattern) <- include) {
            rgCmd.add("--glob='${includePattern}'")
        }

        for (dir in IGNORED_DIR) {
            rgCmd.add("--glob='!**/${dir}/**'")
        }

        rgCmd.add("${pattern}")

        // Add search path (default to current directory)
        let searchPath = path ?? "."
        rgCmd.add(searchPath)

        let command = String.join(rgCmd.toArray(), delimiter: " ")
        LogUtils.debug("[Run command] ${command}")

        let (exitCode, stdOut, stdErr) = ShellUtils.execute(rgCmd.toArray(), workDir: CliConfig.cwd, usePowerShellOnWindows: true)

        LogUtils.debug("Status: ${exitCode}")
        if (exitCode == 0) {
            LogUtils.debug("[Ripgrep output] ${stdOut}")
            return parseGrepOutput(stdOut, CliConfig.cwd)
        } else {
            LogUtils.debug("[Ripgrep error] ${stdErr}")
            return stdErr
        }
    } catch (e: Exception) {
        LogUtils.info("Ripgrep failed, falling back to traditional grep: ${e.message}")
        return grepWithTraditional(pattern, path, include)
    }
}

private func grepWithTraditional(pattern: String, path: Option<String>, include: Option<String>): String {
    try {
        let command = if (InfoUtils.os == "windows") {
            let includeArg = include.map { s => "-Include ${s}" } ?? ""
            let excludeArg = "-Exclude " + String.join(IGNORED_DIR.toArray(), delimiter: ",")
            "Get-ChildItem -Recurse ${includeArg} ${excludeArg} | Select-String -Pattern \"${pattern}\" | Select-Object Path, LineNumber, Line"
        } else {
            let grepCmd = ArrayList<String>(["grep", '-r', '-n', '-H', '-E'])
            for (dir in IGNORED_DIR) {
                grepCmd.add("--exclude-dir=${dir}")
            }
            if (let Some(include) <- include) {
                grepCmd.add("--include=${include}");
            }
            grepCmd.add(pattern)
            grepCmd.add(".")
            String.join(grepCmd.toArray(), delimiter: " ")
        }
        LogUtils.debug("[Run command] ${command}")

        let workingDir = path.map { s => Path(s) } ?? CliConfig.cwd
        let (exitCode, stdout, stderr) = ShellUtils.execute([command],  workDir: workingDir, usePowerShellOnWindows: true)

        if (exitCode == 0) {
            let outString = stdout.trimAscii()
            return parseGrepOutput(outString, workingDir)
        } else {
            let errString = stderr.trimAscii()
            return errString
        }
    } catch (e: Exception) {
        return "Failed to execute grep: ${e}"
    }
}


/**
 * Parses grep/ripgrep output and converts relative paths to absolute paths.
 * Both tools use similar output format: "path:line-number:content"
 * Limits results to 100 matches to prevent context overflow.
 *
 * @param rawOutput Raw output from grep/ripgrep command
 * @param workingDir Working directory used for path resolution
 * @return Formatted output with absolute paths, truncated if necessary
 */
private func parseGrepOutput(rawOutput: String, workingDir: Path): String {
    let lines = rawOutput.split("\n")
    let nonEmptyLines = lines |> filter { line => !line.trimAscii().isEmpty() } |> collectArray

    let totalMatches = nonEmptyLines.size
    let linesToProcess = nonEmptyLines[0..min(nonEmptyLines.size, MAX_GREP_MATCHES)]

    let formattedLines = linesToProcess |>
        map { line: String =>
            // Both grep and ripgrep return "path:line-number:content"
            let items = line.split(":", 3, removeEmpty: false)
            if (items.size != 3) {
                return line
            }
            // Convert relative paths to absolute paths safely
            let path = try {
                if (items[0].startsWith("./")) {
                    canonicalize(workingDir.join(items[0]))
                } else if (!Path(items[0]).isAbsolute()) {
                    canonicalize(workingDir.join(items[0]))
                } else {
                    canonicalize(items[0])
                }
            } catch (e: Exception) {
                // If canonicalize fails, use the original path
                if (items[0].startsWith("./")) {
                    workingDir.join(items[0])
                } else if (!Path(items[0]).isAbsolute()) {
                    workingDir.join(items[0])
                } else {
                    Path(items[0])
                }
            }
            if (ignored(path)) {
                return ""
            }
            let number = items[1]
            let content = items[2]
            return String.join([path.toString(), number, content], delimiter: ":")
        } |>
        filter { s => !s.isEmpty() } |>
        collectArray

    let result = String.join(formattedLines, delimiter: "\n")

    if (totalMatches > MAX_GREP_MATCHES) {
        let remaining = totalMatches - MAX_GREP_MATCHES
        return result + "\n\n[Truncated: showing ${MAX_GREP_MATCHES} of ${totalMatches} matches. ${remaining} more results not shown. Use more specific pattern or include filter.]"
    }

    return result
}