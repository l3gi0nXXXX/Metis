package metis.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*
import magic.log.LogUtils

import metis.utils.{InfoUtils, ShellUtils}
import metis.io.{InputUtils, PrintUtils, Confirmation}
import metis.core.tools.fs_utils.*
import metis.core.tools.code_compression.*
import metis.core.config.CliConfig
import metis.core.{gatewaySubagentAfterCurrentFileWrite, gatewaySubagentBeforeCurrentFileWrite, gatewaySubagentCancelCurrentFileWrite, gatewaySubagentRecordCurrentFileRead}

import std.collection.{map, collectArray, fold}
import std.fs.{Path, File, Directory, remove, exists, FSException}
import std.regex.Regex

//----------------------------------------------------------------------------------
// Read only tools
//----------------------------------------------------------------------------------

@tool[
    description: "Lists all files and subdirectories in a directory and returns the list",
    parameters: { path: "Directory path, must be an absolute path" }
]
protected func listDirectory(path: String): String {
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
        } else { //linux or ohos
            ShellUtils.execute(["ls", "-l"], workDir: Path(path))
        }

        if (exitCode == 0) {
            // Remove \r characters to prevent cursor from jumping to line start
            // Windows uses \r\n, and \r alone causes display issues
            let outString = stdout.replace("\r", "").trimAscii()
            PrintUtils.printToolResult(outString)
            return "Directory contents:\n${outString}"
        } else {
            let errString = stderr.trimAscii()
            let result = "Failed to get directory contents, error output:\n${errString}"
            PrintUtils.printToolResult(result)
            return result
        }
    } catch (e: Exception) {
        PrintUtils.printToolResult("Failed to list directory")
        return "Failed to list directory: ${e}"
    }
}

@tool[
    description: "Reads and returns a specific range of lines from a file with line numbers. If startLine and endLine is omitted, the entire file will be read.",
    parameters: {
        filePath: "The absolute path to the file to read",
        startLine: "Optional: Starting line number (1-based, inclusive). If not provided, reads from start of file",
        endLine: "Optional: Ending line number (1-based, inclusive). If not provided, reads to end of file"
    }
]
protected func fileRead(filePath: String, startLine: Option<Int64>, endLine: Option<Int64>): String {
    if (ignored(Path(filePath))) {
        let startInfo = startLine.map { n => " start=${n}" } ?? ""
        let endInfo = endLine.map { n => " end=${n}" } ?? ""
        return "<file-content path=${filePath}${startInfo}${endInfo}>\n[NOTE: This file is shielded by project configuration.]\n</file-content>"
    }
    let start = startLine ?? 1
    let end = endLine.map { n => n.toString() } ?? "EOF"
    let message = "${filePath} (${start}-${end})"
    PrintUtils.printTool("Read File", shortMessage: message)
    var content = catRange(filePath, startLine ?? 1, endLine: endLine ?? Int64.Max)
    let _ = gatewaySubagentRecordCurrentFileRead(filePath)

    if (content.size > getCompressionThreshold(false)) {
        content = compressCode(filePath, startLine: startLine ?? 1, endLine: endLine ?? Int64.Max, originalContent: content)
    }

    PrintUtils.printToolResult(content)
    let startInfo = startLine.map { n => " start=${n}" } ?? ""
    let endInfo = endLine.map { n => " end=${n}" } ?? ""
    return "<file-content path=${filePath}${startInfo}${endInfo}>\n${content}\n</file-content>"
}

@tool[
    description: 'Searches for a regular expression pattern within the content of files in a specified directory (or current working directory). Can filter files by a glob pattern. Returns the lines containing matches, along with their file paths and line numbers.',
    parameters: {
        pattern: "The regular expression (regex) pattern to search for within file contents (e.g., 'func \\s+foo', 'import\\s+\\{.*\\}\\s+.*').",
        path: "Optional: The absolute path to the directory to search within. If omitted, searches the current working directory.",
        fileType: "Optional: A glob pattern to filter which files are searched (e.g., '*.js', '*.{ts,tsx}', 'src/**'). If omitted, searches all files (respecting potential global ignores).",
    }
]
protected func grepSearch(pattern: String, path: Option<String>, include: Option<String>): String {
    // Construct the info message
    let strBuilder = StringBuilder("pattern: ${pattern}")
    if (let Some(include) <- include) {
        strBuilder.append("\ninclude: ${include}")
    }
    PrintUtils.printTool("Grep", shortMessage: path ?? "", longMessage: strBuilder.toString())

    let result = grep(pattern, path, include)
    if (result.isEmpty()) {
        PrintUtils.printToolResult("Nothing found")
        return "Nothing found"
    } else {
        PrintUtils.printToolResult(result)
        return result
    }
}

// @tool[
//     description: "Lists the directory structure recursively from the given path, showing files and subdirectories in a tree-like format. Useful for understanding the overall layout and hierarchy of a project or folder.",
//     parameters: {
//         path: "The absolute path to the directory to visualize."
//     }
// ]
// public func tree(path: String): String {
//     PrintUtils.printTool("Tree", "path: ${path}")
//     return listTree(path)
// }

/**
 * Maximum number of glob results to return (prevents context overflow)
 */
const MAX_GLOB_RESULTS: Int64 = 100

@tool[
    description: "Efficiently finds files matching specific extensions patterns (e.g., `src/**/*.ts`, `**/*.md`), returning absolute paths. Ideal for quickly locating files based on their extension name, especially in large codebases.",
    parameters: {
        pattern: "Glob pattern to match (e.g., '*.cj' for Cangjie files, '**/test*.cj' for test files recursively)",
        path: "Optional: absolute directory path to search in. Defaults to current working directory."
    }
]
protected func globSearch(pattern: String, path: Option<String>): String {
    let searchPath = path ?? CliConfig.cwd.toString()
    if (!Path(searchPath).isAbsolute()) {
        return "Path must be absolute"
    }
    if (!exists(searchPath)) {
        return "Path does not exist: ${searchPath}"
    }

    PrintUtils.printTool("Glob Search", shortMessage: searchPath, longMessage: pattern)

    try {
        let results = glob(pattern, searchPath)

        if (results.isEmpty()) {
            PrintUtils.printToolResult("Nothing found")
            return "No files matching pattern '${pattern}' found"
        }

        let totalMatches = results.size
        let shouldTruncate = totalMatches > MAX_GLOB_RESULTS
        let resultsToShow = if (shouldTruncate) {
            results[0..MAX_GLOB_RESULTS]
        } else {
            results
        }

        let found = String.join(
            resultsToShow |> map { file => "- ${file}" } |> collectArray,
            delimiter: "\n"
        )
        PrintUtils.printToolResult(found)

        if (shouldTruncate) {
            let remaining = totalMatches - MAX_GLOB_RESULTS
            return "Found ${totalMatches} matches (showing first ${MAX_GLOB_RESULTS}):\n${found}\n\n[Truncated: ${remaining} more files not shown. Use a more specific pattern to reduce results.]"
        } else {
            return "Found ${totalMatches} matches:\n${found}"
        }
    } catch (e: Exception) {
        return "Error during glob search: ${e}"
    }
}

/**
 * Read multiple files in parallel
 */
@tool[
    description: "${FILE_BATCH_READ_DESCRIPTION}",
    parameters: {
        filePaths: "Array of JSON objects, each containing the absolute path to the file to read, optional startLine, and optional endLine."
    }
]
protected func fileBatchRead(files: Array<ReadFileParam>): String {
    // Construct the info message
    let paths = files |> map { param: ReadFileParam =>
            let start = param.startLine ?? 1
            let end = param.endLine.map { n => n.toString() } ?? "EOF"
            "${param.filePath} (${start}-${end})"
        } |> collectArray

    let message = String.join(paths, delimiter: "\n")
    PrintUtils.printTool("Batch Read Files", longMessage: message)

    // Validate input
    if (files.isEmpty()) {
        let errorResult = HashMap<String, JsonValue>()
        errorResult["error"] = JsonString("No file paths provided")
        errorResult["files"] = JsonArray([])
        return JsonObject(errorResult).toJsonString()
    }

    let results = batchRead(files)
    for (param in files) {
        let _ = gatewaySubagentRecordCurrentFileRead(param.filePath)
    }

    //code compression
    var totalChars = results |> fold(0) { sum: Int, r: ?String => sum + (r?.size ?? 0) }
    for (i in 0..files.size) {
        if (totalChars <= getCompressionThreshold(true)) {
            break
        }
        let filePath = files[i].filePath
        if (let Some(fileContent) <- results[i]) {
            let old = fileContent.size
            let newContent = compressCode(filePath, originalContent: fileContent)
            results[i] = newContent
            let new = newContent.size
            totalChars += (new - old)
        }
    }

    // Merge all file content
    let result = mergeBatchResults(files, results)

    PrintUtils.printToolResult(result)
    return result
}

//----------------------------------------------------------------------------------

/**
 * Read-only file system tools
 */
@toolset[
    tools: [listDirectory, fileRead, fileBatchRead, grepSearch, globSearch]
]
public class ReadOnlyFSToolset {
}

//------------------------------------------------------------------------------------

@tool[
    description: "Creates a file with content and returns the creation result",
    parameters: {
        filePath: "File path, must be an absolute path",
        content: "File content"
    }
]
protected func fileCreate(filePath: String, content: String): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    let coordination = gatewaySubagentBeforeCurrentFileWrite(filePath, operation: "create")
    if (!coordination[0]) {
        return "[subagent-file-coordination:block] ${coordination[1]}"
    }
    if (InputUtils.confirm("Create File", filePath, content) == Confirmation.Deny) {
        let _ = gatewaySubagentCancelCurrentFileWrite(filePath)
        return "User denied the operation"
    }

    try {
        let file = File(filePath, Write)
        file.write(content.toArray())
        file.close()
        let _ = gatewaySubagentAfterCurrentFileWrite(filePath, operation: "create", warning: coordination[1])
        let prefix = if (coordination[1].isEmpty()) { "" } else { "[subagent-file-coordination:warning] ${coordination[1]}\n" }
        return "${prefix}File ${filePath} created successfully!"
    } catch (e: Exception) {
        let _ = gatewaySubagentCancelCurrentFileWrite(filePath)
        return "Failed to create file: ${e}"
    }
}

@tool[
    description: "Writes content to a single file and returns the write result",
    parameters: { filePath: "File path, must be an absolute path", content: "Content to write" }
]
protected func fileWrite(filePath: String, content: String): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    let coordination = gatewaySubagentBeforeCurrentFileWrite(filePath, operation: "write")
    if (!coordination[0]) {
        return "[subagent-file-coordination:block] ${coordination[1]}"
    }
    if (InputUtils.confirm("Write File", filePath, content) == Confirmation.Deny) {
        let _ = gatewaySubagentCancelCurrentFileWrite(filePath)
        return "User denied the operation"
    }
    let result = writeFileBasic(filePath, content)
    if (result.contains("written successfully")) {
        let _ = gatewaySubagentAfterCurrentFileWrite(filePath, operation: "write", warning: coordination[1])
    } else {
        let _ = gatewaySubagentCancelCurrentFileWrite(filePath)
    }
    let prefix = if (coordination[1].isEmpty()) { "" } else { "[subagent-file-coordination:warning] ${coordination[1]}\n" }
    return "${prefix}${result}"
}

@tool[
    description: "${FILE_EDIT_DESCRIPTION}",
    parameters: {
        filePath: "File path, must be an absolute path",
        oldContent: "The exact literal text to replace, preferably unescaped. Including at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. If this string is not the exact literal text (i.e. you escaped it) or does not match exactly, the tool will fail.",
        newContent: "The exact literal text to replace `oldContent` with, preferably unescaped. Provide the EXACT text. newContent MUST be different from oldContent; otherwise, the tool will fail."
    }
]
protected func fileEdit(filePath: String, oldContent: String, newContent: String): String {
    return FSToolset.fileMultiEditImpl(
        "Edit File", filePath, [MultiEditParam(oldContent: oldContent, newContent: newContent)]
    )
}

/**
 * General file system tools
 */
@toolset[
    tools: [
        listDirectory, grepSearch, globSearch,
        fileRead, fileBatchRead, fileCreate, fileWrite, fileEdit
    ]
]
public class FSToolset {
    @tool[
        description: "${FILE_MULTI_EDIT_DESCRIPTION}",
        parameters: {
            filePath: "File path, must be an absolute path",
            edits: "Array of edit operations to perform sequentially on the file"
        }
    ]
    func fileMultiEdit(filePath: String, edits: Array<MultiEditParam>): String {
        return fileMultiEditImpl("Multi-Edit File", filePath, edits)
    }

    static func fileMultiEditImpl(toolName: String, filePath: String, edits: Array<MultiEditParam>): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        try {
            // Load the original file content
            let oldFileContent = String.fromUtf8(File.readFrom(filePath))
            //Regex to normalize the line ending style to the file style to avoid failure due to CRLF/LF
            let regex = Regex(#"\r?\n"#)
            // Apply each edit sequentially 
            let useCRLF = oldFileContent.contains("\r\n")
            var currFileContent = regex.replaceAll(oldFileContent, "\n")
            for (edit in edits) {
                var oldContent = regex.replaceAll(edit.oldContent, "\n")
                var newContent = regex.replaceAll(edit.newContent, "\n")
                if (!currFileContent.contains(oldContent)) {
                    return "Failed to edit. File ${filePath} does not contain the specified content '${oldContent}'."
                }
                currFileContent = currFileContent.replace(oldContent, newContent)
            }
            //Normalize the line ending style to the file style to avoid failure due to CRLF/LF
            if(useCRLF) {
                currFileContent = currFileContent.replace("\n", "\r\n")
            }
            // Check if the content has changed
            let newFileContent = currFileContent
            if (oldFileContent == newFileContent) {
                PrintUtils.printToolFailure(
                    "${toolName} (${filePath})",
                    failure: "File content is not modified"
                )
                return "No changes to apply. The oldContent and newContent are identical in file: ${filePath}"
            }
            // Render the diff message
            let message = diff(oldFileContent, newFileContent) |> PrintUtils.renderDiff
            if (InputUtils.confirm(toolName, filePath, message) == Confirmation.Deny) {
                return "User denied the operation"
            }
            let coordination = gatewaySubagentBeforeCurrentFileWrite(filePath, operation: "edit")
            if (!coordination[0]) {
                return "[subagent-file-coordination:block] ${coordination[1]}"
            }
            // Write the modified content to the file
            try {
                File.writeTo(filePath, newFileContent.toArray())
                let _ = gatewaySubagentAfterCurrentFileWrite(filePath, operation: "edit", warning: coordination[1])
                let prefix = if (coordination[1].isEmpty()) { "" } else { "[subagent-file-coordination:warning] ${coordination[1]}\n" }
                return "${prefix}File ${filePath} content modified successfully."
            } catch (e: Exception) {
                let _ = gatewaySubagentCancelCurrentFileWrite(filePath)
                throw e
            }
        } catch (ex: FSException) {
            return "File path error or file is not readable/writable"
        } catch (ex: IllegalArgumentException) {
            return "File path is empty or contains illegal characters"
        }
    }

}
