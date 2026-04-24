package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.tools.fs_utils.{catRange, grep, glob, ignored}
import metis.io.PrintUtils
import metis.core.config.CliConfig
import metis.utils.{InfoUtils, ShellUtils}

import std.collection.{ArrayList, map, collectArray}
import std.fs.{Path, exists}

@toolset
public class GatewayFSToolset {
    @tool[
        description: "Lists files and subdirectories in an absolute directory path.",
        parameters: { path: "Absolute directory path." }
    ]
    public func listDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "Directory path must be absolute"
        }
        if (ignored(Path(path))) {
            return "Directory ${path} is ignored by project configuration."
        }
        PrintUtils.printTool("List Directory", shortMessage: path)
        try {
            let (exitCode, stdout, stderr) = if (InfoUtils.os == "windows") {
                ShellUtils.execute(["dir"], workDir: Path(path))
            } else {
                ShellUtils.execute(["ls", "-l"], workDir: Path(path))
            }
            if (exitCode == 0) {
                let outString = stdout.replace("\r", "").trimAscii()
                PrintUtils.printToolResult(outString)
                return "Directory contents:\n${outString}"
            }
            let errString = stderr.trimAscii()
            let result = "Failed to get directory contents, error output:\n${errString}"
            PrintUtils.printToolResult(result)
            return result
        } catch (e: Exception) {
            PrintUtils.printToolResult("Failed to list directory")
            return "Failed to list directory: ${e}"
        }
    }

    @tool[
        description: "Reads a specific file or line range from an absolute file path.",
        parameters: {
            filePath: "Absolute file path.",
            startLine: "Optional 1-based start line.",
            endLine: "Optional 1-based end line."
        }
    ]
    public func fileRead(filePath: String, startLine: Option<Int64>, endLine: Option<Int64>): String {
        if (ignored(Path(filePath))) {
            let startInfo = startLine.map { n => " start=${n}" } ?? ""
            let endInfo = endLine.map { n => " end=${n}" } ?? ""
            return "<file-content path=${filePath}${startInfo}${endInfo}>\n[NOTE: This file is shielded by project configuration.]\n</file-content>"
        }
        let start = startLine ?? 1
        let end = endLine.map { n => n.toString() } ?? "EOF"
        PrintUtils.printTool("Read File", shortMessage: "${filePath} (${start}-${end})")
        let content = catRange(filePath, start, endLine: endLine ?? Int64.Max)
        PrintUtils.printToolResult(content)
        let startInfo = startLine.map { n => " start=${n}" } ?? ""
        let endInfo = endLine.map { n => " end=${n}" } ?? ""
        return "<file-content path=${filePath}${startInfo}${endInfo}>\n${content}\n</file-content>"
    }

    @tool[
        description: "Searches file contents with a regex pattern inside the current workspace.",
        parameters: {
            pattern: "Regex pattern.",
            path: "Optional absolute directory path.",
            fileType: "Optional glob include pattern."
        }
    ]
    public func grepSearch(pattern: String, path: Option<String>, fileType: Option<String>): String {
        PrintUtils.printTool("Grep", shortMessage: path ?? "", longMessage: pattern)
        let result = grep(pattern, path, fileType)
        if (result.isEmpty()) {
            PrintUtils.printToolResult("Nothing found")
            return "Nothing found"
        }
        PrintUtils.printToolResult(result)
        return result
    }

    @tool[
        description: "Finds files by glob pattern inside the current workspace.",
        parameters: {
            pattern: "Glob pattern, e.g. *.cj or **/test*.cj.",
            path: "Optional absolute directory path."
        }
    ]
    public func globSearch(pattern: String, path: Option<String>): String {
        let searchPath = path ?? CliConfig.cwd.toString()
        if (!Path(searchPath).isAbsolute()) {
            return "Path must be absolute"
        }
        if (!exists(searchPath)) {
            return "Path does not exist: ${searchPath}"
        }
        PrintUtils.printTool("Glob Search", shortMessage: searchPath, longMessage: pattern)
        let results = glob(pattern, searchPath)
        if (results.isEmpty()) {
            PrintUtils.printToolResult("Nothing found")
            return "No files matching pattern '${pattern}' found"
        }
        let found = String.join(results.toArray() |> map { file => "- ${file}" } |> collectArray, delimiter: "\n")
        PrintUtils.printToolResult(found)
        return "Found ${results.size} matches:\n${found}"
    }
}
