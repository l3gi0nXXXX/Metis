package metis.core.tools.cj_utils

import magic.log.LogUtils
import magic.utils.readFile
import magic.dsl.jsonable
import magic.jsonable.*
import magic.parser.ParserUtils

import metis.io.removeAnsiEscape
import std.unicode.UnicodeStringExtension
import metis.core.config.CliConfig

import std.collection.{ArrayList, HashMap}
import std.fs.{Path, File, OpenMode, copy, remove}
import std.io.StringWriter
import std.process.{executeWithOutput, ProcessException}
import stdx.encoding.json.*

protected func cjpmRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjpm", args, projectDir)
}

protected func cjcRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjc", args, projectDir)
}

@jsonable
class BuildResult {
    let Diags: ArrayList<Diagnostic>

    /**
     * Filter out only same error diagnostics
     */
    func filterSameErrors(limit!: Option<Int64> = None): Unit {
        // Filter out only error diagnostics
        this.Diags.removeIf ({ diag => diag.Severity != "error" })
        if (this.Diags.isEmpty()) {
            return
        }
        // Filter out only same error diagnostics
        let error = this.Diags[0].Message
        this.Diags.removeIf ({ diag => diag.Message != error })
        // Limit the number of errors
        if (let Some(_limit) <- limit && _limit < this.Diags.size) {
            this.Diags.remove(_limit..this.Diags.size)
        }
    }

    /**
     * Add code snippets of the error
     */
    func addCodeSnippets(): Unit {
        for (diag in this.Diags) {
            let start = max(0, diag.Location.Line - 2)
            let end = diag.Location.Line + 2
            let code = readFile(Path(diag.Location.File), withLineNumber: true, startLine: start, endLine: end)
            diag.CodeSnippet = code
        }
    }

    func toString(): String {
        let writer = StringBuilder()
        for (diag in this.Diags) {
            let msg = if (diag.MainHint.Content.isEmpty()) {
                diag.Message
            } else {
                "${diag.Message}; ${diag.MainHint.Content}"
            }
            writer.append("<error location=\"${diag.Location.File}:${diag.Location.Line}\" message=\"${msg}\" >\n")
            if (let Some(code) <- diag.CodeSnippet) {
                writer.append("${code}\n")
            }
            writer.append("</error>\n")
            writer.append("\n")
        }
        return writer.toString()
    }
}

@jsonable
class Diagnostic {
    let DiagKind: String
    let Severity: String
    let Message: String
    let Location: DiagLocation
    let MainHint: DiagHint
    var CodeSnippet: Option<String>
}

@jsonable
class DiagLocation {
    let File: String
    let Line: Int64
    let Column: Int64
}

@jsonable
class DiagHint {
    let Content: String
}

/**
 * Backup the original cjpm.toml file
 */
private func backupCjpmToml(projectDir: Path): Bool {
    let originalPath = projectDir.join("cjpm.toml")
    let backupPath = CliConfig.dotDir.join("cjpm.toml.backup")

    try {
        copy(originalPath, to: backupPath, overwrite: true)
        return true
    } catch (ex: Exception) {
        LogUtils.error("Failed to backup cjpm.toml: ${ex}")
        return false
    }
}

/**
 * Restore cjpm.toml from backup
 */
protected func restoreCjpmToml(projectDir: Path): Bool {
    let originalPath = projectDir.join("cjpm.toml")
    let backupPath = CliConfig.dotDir.join("cjpm.toml.backup")

    try {
        // Restore original file
        copy(backupPath, to: originalPath, overwrite: true)

        // Remove backup file
        remove(backupPath)
        return true
    } catch (e: Exception) {
        LogUtils.error("Failed to restore cjpm.toml: ${e}")
        return false
    }
}

/**
 * Modify cjpm.toml to add --diagnostic-format=json to compile-option
 */
protected func modifyCjpmToml(projectDir: Path): Bool {
    // Backup cjpm.toml first
    if (!backupCjpmToml(projectDir)) {
        return false
    }

    let tomlPath = projectDir.join("cjpm.toml")

    try {
        // Read original file
        let content = readFile(tomlPath)

        // Find and modify the compile-option line
        let lines = content.split('\n')
        let modifiedContent = StringBuilder()
        var found = false

        for (i in 0..lines.size) {
            let line = lines[i]
            if (line.contains("override-compile-option")) {
                // Parse existing compile-option value
                let parts = line.split('=', 2)
                if (parts.size == 2) {
                    let key = parts[0].trimAscii()
                    let value = parts[1].trimAscii()

                    // Remove quotes if present
                    var unquotedValue = value
                    if (value.startsWith('"') || value.startsWith("'")) {
                        unquotedValue = value[1..(value.size - 1)].trimAscii()
                    }

                    // Add --diagnostic-format=json if not already present
                    if (!unquotedValue.contains("--diagnostic-format=json")) {
                        unquotedValue += " --diagnostic-format=json"
                    }

                    // Add --error-count-limit=all if not already present
                    if (!unquotedValue.contains("--error-count-limit")) {
                        unquotedValue += " --error-count-limit=all"
                    }

                    modifiedContent.append("${key} = \"${unquotedValue}\"")

                    // Re-quote the value
                    found = true
                } else {
                    modifiedContent.append(line)
                }
            } else {
                modifiedContent.append(line)
            }

            if (i < lines.size - 1) {
                modifiedContent.append('\n')
            }
        }
        // Add the override-compile-option if not found
        var newCjpmToml = modifiedContent.toString()
        if (!found) {
            newCjpmToml = newCjpmToml.replace(
                "[package]",
                "[package]\n  override-compile-option = \"--diagnostic-format=json --error-count-limit=all\"\n")
        }
        // Overwrite the current toml file
        try (file = File(tomlPath, OpenMode.Write)) {
            let writer = StringWriter(file)
            writer.write(newCjpmToml)
            writer.flush()
        }
        return true
    } catch (ex: Exception) {
        LogUtils.error("Failed to modify cjpm.toml: ${ex}")
        // If modified failed, restore original cjpm.toml
        restoreCjpmToml(projectDir)
        return false
    }
}

protected struct CJPMBuildResult {
    CJPMBuildResult(
        public let rawOutput: String, // The raw output from cjpm build command
        public let processedOutput: String // The processed output with error messages for LLM
    ) { }
}

/**
 *
 */
protected func cjpmBuild(projectDir: Path,
                         outputJson!: Bool = false,
                         withCode!: Bool = false): CJPMBuildResult {
    // Execute the build
    let output = cjpmRun(["build", "-i"], projectDir)
    // Check if build succeeded; if so, return success message
    if (output.contains("cjpm build success")) {
        return CJPMBuildResult(
            output,
            "${output}\nHint: the project is successfully built, so there are no errors to fix."
        )
    }
    if (outputJson) {
        try {
            let result = ParserUtils.extractFirstValue<BuildResult>(output)
            result.filterSameErrors(limit: 5)
            result.addCodeSnippets()
            if (!result.Diags.isEmpty()) {
                return CJPMBuildResult(
                    output,
                    "<compile error>\n${result.toString()}\n</compile error>"
                )
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to parse cjpm build Json output\n```\n${output}\n```")
        }
    }

    // Process the output as plain text if the build output is not Json
    let errors = output.split("error: ")
    // Only return the first error if there are multiple errors
    if (errors.size > 1) {
        return CJPMBuildResult(
            output,
            "${errors[0]}error: ${errors[1]}"
        )
    } else {
        return CJPMBuildResult(
            output,
            output
        )
    }
}

private func execCommand(command: String, args: Array<String>, projectDir: Path): String {
    try {
        let (exitCode, stdOut, stdErr) = executeWithOutput(command, args, workingDirectory: projectDir)

        if (exitCode == 0) {
            let output = String.fromUtf8(stdOut)
            if (output.trimAscii().isEmpty()) {
                return "Execute '${command} ${String.join(args, delimiter: " ")}' successfully."
            } else {
                return removeAnsiEscape(output)
            }
        } else {
            return removeAnsiEscape(String.fromUtf8(stdErr))
        }
    } catch (e: ProcessException) {
        return "Process execution error: ${e}"
    } catch (e: Exception) {
        return "Unknown error occurred: ${e}"
    }
}
