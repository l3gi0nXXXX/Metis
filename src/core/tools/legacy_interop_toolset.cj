package metis.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.CliConfig
import metis.core.tools.fs_utils as FsUtils
import metis.io.{InputUtils, PrintUtils, Confirmation}
import metis.utils.{InfoUtils, ShellUtils}

import std.collection.ArrayList
import std.fs.{Path, File, exists, remove, FSException}
import std.time.*

private const BEGIN_PATCH_MARKER = "*** Begin Patch"
private const END_PATCH_MARKER = "*** End Patch"
private const ADD_FILE_MARKER = "*** Add File: "
private const DELETE_FILE_MARKER = "*** Delete File: "
private const UPDATE_FILE_MARKER = "*** Update File: "
private const MOVE_TO_MARKER = "*** Move to: "
private const EOF_MARKER = "*** End of File"

private func resolveCompatPath(path: String): String {
    let trimmed = path.trimAscii()
    if (trimmed.isEmpty()) {
        return CliConfig.cwd.toString()
    }
    let p = Path(trimmed)
    if (p.isAbsolute()) {
        return trimmed
    }
    return CliConfig.cwd.join(trimmed).toString()
}

private func isPatchBoundaryLine(line: String): Bool {
    return line == END_PATCH_MARKER ||
        line.startsWith(ADD_FILE_MARKER) ||
        line.startsWith(DELETE_FILE_MARKER) ||
        line.startsWith(UPDATE_FILE_MARKER)
}

private func joinLines(lines: ArrayList<String>): String {
    return String.join(lines.toArray(), delimiter: "\n")
}

private func pushPatchChunk(
    chunks: ArrayList<(String, String)>,
    oldLines: ArrayList<String>,
    newLines: ArrayList<String>
): Unit {
    if (oldLines.isEmpty() && newLines.isEmpty()) {
        return
    }
    chunks.add((joinLines(oldLines), joinLines(newLines)))
    oldLines.clear()
    newLines.clear()
}

private func applyUpdateChunks(filePath: String, chunks: Array<(String, String)>): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    try {
        let oldFileContent = String.fromUtf8(File.readFrom(filePath))
        let useCRLF = oldFileContent.contains("\r\n")
        var currentContent = oldFileContent.replace("\r\n", "\n")

        for (chunk in chunks) {
            let normalizedOld = chunk[0].replace("\r\n", "\n")
            let normalizedNew = chunk[1].replace("\r\n", "\n")
            if (!currentContent.contains(normalizedOld)) {
                return "Failed to edit. File ${filePath} does not contain the specified patch chunk."
            }
            currentContent = currentContent.replace(normalizedOld, normalizedNew)
        }

        if (useCRLF) {
            currentContent = currentContent.replace("\n", "\r\n")
        }
        if (currentContent == oldFileContent) {
            return "No changes to apply. The patch did not modify file: ${filePath}"
        }
        File.writeTo(filePath, currentContent.toArray())
        return ""
    } catch (_: FSException) {
        return "File path error or file is not readable/writable"
    } catch (_: IllegalArgumentException) {
        return "File path is empty or contains illegal characters"
    }
}

private func applyLegacyCompatPatch(input: String): String {
    let normalized = input.replace("\r\n", "\n")
    let lines = normalized.split("\n")
    if (lines.isEmpty() || lines[0].trimAscii() != BEGIN_PATCH_MARKER) {
        return "Provide a patch input wrapped by *** Begin Patch and *** End Patch."
    }

    let added = ArrayList<String>()
    let modified = ArrayList<String>()
    let deleted = ArrayList<String>()

    var index = 1
    while (index < lines.size) {
        let line = lines[index]
        if (line.trimAscii().isEmpty()) {
            index += 1
            continue
        }
        if (line == END_PATCH_MARKER) {
            let summary = ArrayList<String>(["Success. Updated the following files:"])
            for (path in added) {
                summary.add("A ${path}")
            }
            for (path in modified) {
                summary.add("M ${path}")
            }
            for (path in deleted) {
                summary.add("D ${path}")
            }
            return joinLines(summary)
        }

        if (line.startsWith(ADD_FILE_MARKER)) {
            let targetPath = resolveCompatPath(line[ADD_FILE_MARKER.size..].trimAscii())
            let contentLines = ArrayList<String>()
            index += 1
            while (index < lines.size && !isPatchBoundaryLine(lines[index])) {
                let patchLine = lines[index]
                if (!patchLine.startsWith("+")) {
                    return "Invalid add-file patch line: ${patchLine}"
                }
                contentLines.add(patchLine[1..])
                index += 1
            }
            if (InputUtils.confirm("Apply Patch", targetPath, "Add file") == Confirmation.Deny) {
                return "User denied the operation"
            }
            let writeResult = FsUtils.writeFileBasic(targetPath, joinLines(contentLines))
            if (writeResult.contains("failed") || writeResult.contains("Failed")) {
                return writeResult
            }
            added.add(targetPath)
            continue
        }

        if (line.startsWith(DELETE_FILE_MARKER)) {
            let targetPath = resolveCompatPath(line[DELETE_FILE_MARKER.size..].trimAscii())
            index += 1
            if (InputUtils.confirm("Apply Patch", targetPath, "Delete file") == Confirmation.Deny) {
                return "User denied the operation"
            }
            try {
                remove(Path(targetPath))
            } catch (e: Exception) {
                return "Failed to delete file: ${e}"
            }
            deleted.add(targetPath)
            continue
        }

        if (line.startsWith(UPDATE_FILE_MARKER)) {
            let sourcePath = resolveCompatPath(line[UPDATE_FILE_MARKER.size..].trimAscii())
            var movePath = ""
            let chunks = ArrayList<(String, String)>()
            let oldLines = ArrayList<String>()
            let newLines = ArrayList<String>()
            index += 1
            if (index < lines.size && lines[index].startsWith(MOVE_TO_MARKER)) {
                movePath = resolveCompatPath(lines[index][MOVE_TO_MARKER.size..].trimAscii())
                index += 1
            }
            while (index < lines.size && !isPatchBoundaryLine(lines[index])) {
                let patchLine = lines[index]
                if (patchLine == EOF_MARKER) {
                    pushPatchChunk(chunks, oldLines, newLines)
                    index += 1
                    continue
                }
                if (patchLine.startsWith("@@")) {
                    pushPatchChunk(chunks, oldLines, newLines)
                    index += 1
                    continue
                }
                if (patchLine.isEmpty()) {
                    return "Invalid update patch line"
                }
                let content = patchLine[1..]
                if (patchLine.startsWith("+")) {
                    newLines.add(content)
                } else if (patchLine.startsWith("-")) {
                    oldLines.add(content)
                } else if (patchLine.startsWith(" ")) {
                    oldLines.add(content)
                    newLines.add(content)
                } else {
                    return "Invalid update patch line: ${patchLine}"
                }
                index += 1
            }
            pushPatchChunk(chunks, oldLines, newLines)
            if (chunks.isEmpty()) {
                return "No update chunks found for ${sourcePath}"
            }
            if (InputUtils.confirm("Apply Patch", sourcePath, "Update file") == Confirmation.Deny) {
                return "User denied the operation"
            }
            let applyResult = applyUpdateChunks(sourcePath, chunks.toArray())
            if (!applyResult.isEmpty()) {
                return applyResult
            }
            if (!movePath.isEmpty()) {
                try {
                    let content = String.fromUtf8(File.readFrom(sourcePath))
                    let writeResult = FsUtils.writeFileBasic(movePath, content)
                    if (writeResult.contains("failed") || writeResult.contains("Failed")) {
                        return writeResult
                    }
                    remove(Path(sourcePath))
                } catch (e: Exception) {
                    return "Failed to move file: ${e}"
                }
                modified.add(movePath)
            } else {
                modified.add(sourcePath)
            }
            continue
        }

        return "Unknown patch operation: ${line}"
    }

    return "Patch is missing *** End Patch."
}

@tool[
    description: "Read file contents",
    parameters: {
        path: "The file path to read",
        offset: "Optional 1-based starting line number",
        limit: "Optional number of lines to read"
    }
]
protected func read(path: String, offset: Option<Int64>, limit: Option<Int64>): String {
    let resolvedPath = resolveCompatPath(path)
    let startLine = offset.map { n => if (n < 1) { 1 } else { n } }
    let endLine: Option<Int64> = if (let Some(count) <- limit) {
        let normalizedCount = if (count < 1) { 1 } else { count }
        if (let Some(start) <- startLine) {
            Some(start + normalizedCount - 1)
        } else {
            Some(normalizedCount)
        }
    } else {
        None<Int64>
    }
    if (let Some(start) <- startLine) {
        return FsUtils.catRange(resolvedPath, start, endLine: endLine ?? Int64.Max)
    }
    return FsUtils.cat(resolvedPath)
}

@tool[
    description: "Create or overwrite files",
    parameters: {
        path: "The file path to write",
        content: "Content to write"
    }
]
protected func write(path: String, content: String): String {
    let resolvedPath = resolveCompatPath(path)
    if (InputUtils.confirm("Write File", resolvedPath, content) == Confirmation.Deny) {
        return "User denied the operation"
    }
    return FsUtils.writeFileBasic(resolvedPath, content)
}

@tool[
    description: "Make precise edits to files",
    parameters: {
        path: "The file path to edit",
        oldText: "Exact old text to replace",
        newText: "Exact new text"
    }
]
protected func edit(path: String, oldText: String, newText: String): String {
    let resolvedPath = resolveCompatPath(path)
    if (!Path(resolvedPath).isAbsolute()) {
        return "File path must be absolute"
    }

    try {
        let oldFileContent = String.fromUtf8(File.readFrom(resolvedPath))
        let useCRLF = oldFileContent.contains("\r\n")
        var normalizedContent = oldFileContent.replace("\r\n", "\n")
        let normalizedOld = oldText.replace("\r\n", "\n")
        let normalizedNew = newText.replace("\r\n", "\n")
        if (!normalizedContent.contains(normalizedOld)) {
            return "Failed to edit. File ${resolvedPath} does not contain the specified content '${normalizedOld}'."
        }

        normalizedContent = normalizedContent.replace(normalizedOld, normalizedNew)
        if (useCRLF) {
            normalizedContent = normalizedContent.replace("\n", "\r\n")
        }
        if (normalizedContent == oldFileContent) {
            PrintUtils.printToolFailure("Edit File (${resolvedPath})", failure: "File content is not modified")
            return "No changes to apply. The oldText and newText are identical in file: ${resolvedPath}"
        }

        if (InputUtils.confirm("Edit File", resolvedPath, newText) == Confirmation.Deny) {
            return "User denied the operation"
        }
        File.writeTo(resolvedPath, normalizedContent.toArray())
        return "File ${resolvedPath} content modified successfully."
    } catch (_: FSException) {
        return "File path error or file is not readable/writable"
    } catch (_: IllegalArgumentException) {
        return "File path is empty or contains illegal characters"
    }
}

@tool[
    description: "Search file contents for patterns",
    parameters: {
        pattern: "Regular expression pattern to search for",
        path: "Optional directory path to search within",
        include: "Optional glob pattern to filter files"
    }
]
protected func grep(pattern: String, path: Option<String>, include: Option<String>): String {
    let resolvedPath = path.map { p => resolveCompatPath(p) }
    return FsUtils.grep(pattern, resolvedPath, include)
}

@tool[
    description: "Find files by glob pattern",
    parameters: {
        pattern: "Glob pattern to match",
        path: "Optional directory path to search within"
    }
]
protected func find(pattern: String, path: Option<String>): String {
    let searchPath = path.map { p => resolveCompatPath(p) } ?? CliConfig.cwd.toString()
    if (!Path(searchPath).isAbsolute()) {
        return "Path must be absolute"
    }
    if (!exists(Path(searchPath))) {
        return "Path does not exist: ${searchPath}"
    }

    try {
        let results = FsUtils.glob(pattern, searchPath)
        if (results.isEmpty()) {
            return "No files matching pattern '${pattern}' found"
        }
        let formatted = ArrayList<String>()
        for (file in results) {
            formatted.add("- ${file}")
        }
        return "Found ${results.size} matches:\n${String.join(formatted.toArray(), delimiter: "\n")}"
    } catch (e: Exception) {
        return "Error during glob search: ${e}"
    }
}

@tool[
    description: "List directory contents",
    parameters: {
        path: "Optional directory path to list"
    }
]
protected func ls(path: Option<String>): String {
    let resolvedPath = resolveCompatPath(path ?? CliConfig.cwd.toString())
    if (!Path(resolvedPath).isAbsolute()) {
        return "Directory path must be absolute"
    }

    try {
        let (exitCode, stdout, stderr) = if (InfoUtils.os == "windows") {
            ShellUtils.execute(["dir"], workDir: Path(resolvedPath))
        } else {
            ShellUtils.execute(["ls", "-l"], workDir: Path(resolvedPath))
        }

        if (exitCode == 0) {
            return "Directory contents:\n${stdout.replace("\r", "").trimAscii()}"
        }
        return "Failed to get directory contents, error output:\n${stderr.trimAscii()}"
    } catch (e: Exception) {
        return "Failed to list directory: ${e}"
    }
}

@tool[
    description: "Run shell commands (compatibility wrapper for Metis exec)",
    parameters: {
        command: "The command to execute",
        workdir: "Optional working directory",
        yieldMs: "Optional background yield window in milliseconds",
        background: "Optional background execution flag",
        timeout: "Optional timeout in milliseconds",
        pty: "Optional TTY flag",
        elevated: "Optional elevated execution flag",
        host: "Optional host selector",
        security: "Optional security mode",
        ask: "Optional approval prompt",
        node: "Optional node selector"
    }
]
protected func exec(
    command: String,
    workdir: Option<String>,
    yieldMs: Option<Int64>,
    background: Option<Bool>,
    timeout: Option<Int64>,
    pty: Option<Bool>,
    elevated: Option<Bool>,
    host: Option<String>,
    security: Option<String>,
    ask: Option<String>,
    node: Option<String>
): String {
    let resolvedPath = resolveCompatPath(workdir ?? CliConfig.cwd.toString())
    if (background ?? false) {
        return "[Metis exec compatibility note] background=true is not supported in this build. Please run without background and retry."
    }
    if (InputUtils.confirm("Shell", "", command) == Confirmation.Deny) {
        return "User denied the operation"
    }

    let result = try {
        let isInteractive = pty ?? false
        if (isInteractive) {
            InputUtils.lockTerminalInput()
            InputUtils.exitRawMode()
            try {
                let exitCode = ShellUtils.executeInteractive(
                    [command],
                    workDir: Path(resolvedPath),
                    usePowerShellOnWindows: true
                )
                "Interactive command finished with exit code ${exitCode}."
            } finally {
                InputUtils.enterRawMode()
                InputUtils.unlockTerminalInput()
            }
        } else {
            let effectiveTimeout = if ((timeout ?? 0) > 0) {
                Duration.millisecond * (timeout ?? 0)
            } else if ((yieldMs ?? 0) > 0) {
                Duration.millisecond * (yieldMs ?? 0)
            } else {
                Duration.second * 180
            }
            let (exitCode, stdout, stderr) = ShellUtils.execute(
                [command],
                workDir: Path(resolvedPath),
                timeout: effectiveTimeout,
                usePowerShellOnWindows: true
            )
            if (exitCode == 0) {
                "Command executed successfully, output:\n${stdout.trimAscii()}"
            } else {
                "Command execution failed, error output:\n${stderr.trimAscii()}"
            }
        }
    } catch (e: Exception) {
        "Exception occurred while executing command: ${e}\nCommand: ${command}"
    }
    let unsupported = ArrayList<String>()
    // `yieldMs` is mapped to timeout when `timeout` is absent, so only report if both are present.
    if ((yieldMs ?? 0) > 0 && (timeout ?? 0) > 0) { unsupported.add("yieldMs(ignored_due_to_timeout)") }
    if (elevated ?? false) { unsupported.add("elevated") }
    if (!((host ?? "").trimAscii().isEmpty())) { unsupported.add("host") }
    if (!((security ?? "").trimAscii().isEmpty())) { unsupported.add("security") }
    if (!((ask ?? "").trimAscii().isEmpty())) { unsupported.add("ask") }
    if (!((node ?? "").trimAscii().isEmpty())) { unsupported.add("node") }
    if (unsupported.isEmpty()) {
        return result
    }
    return "[Metis exec compatibility note] Ignored unsupported options: ${String.join(unsupported.toArray(), delimiter: ", ")}\n\n${result}"
}

@tool[
    description: "Apply a patch to one or more files using the apply_patch format",
    parameters: {
        input: "Patch content using the *** Begin Patch/End Patch format."
    }
]
protected func apply_patch(input: String): String {
    return applyLegacyCompatPatch(input)
}

@tool[
    description: "Search the web",
    parameters: {
        query: "Search query string",
        count: "Optional requested result count",
        freshness: "Optional freshness filter",
        country: "Optional country code",
        language: "Optional language code",
        search_lang: "Optional search language code"
    }
]
protected func web_search(
    query: String,
    count: Option<Int64>,
    freshness: Option<String>,
    country: Option<String>,
    language: Option<String>,
    search_lang: Option<String>
): String {
    let q = query.trimAscii()
    if (q.isEmpty()) {
        return "web_search requires a non-empty query."
    }
    let limit = if ((count ?? 0) > 0) { count ?? 5 } else { 5 }
    let cmd = "python -c \"import json,urllib.request,urllib.parse;u='https://api.duckduckgo.com/?q='+urllib.parse.quote('${q}')+'&format=json&no_redirect=1&no_html=1';d=json.loads(urllib.request.urlopen(u,timeout=10).read().decode('utf-8','ignore'));rows=[];a=d.get('AbstractText','').strip();h=d.get('Heading','').strip();(rows.append('- '+(h+': ' if h else '')+a) if a else None);t=d.get('RelatedTopics',[]);n=0\nfor item in t:\n    if n>=${limit}: break\n    if isinstance(item,dict) and item.get('Text'):\n        rows.append('- '+item['Text']);n+=1\nprint('\\n'.join(rows) if rows else 'No web results found.')\""
    try {
        let (exitCode, stdout, stderr) = ShellUtils.execute(
            [cmd],
            workDir: CliConfig.cwd,
            timeout: Duration.second * 20,
            usePowerShellOnWindows: true
        )
        if (exitCode == 0) {
            let out = stdout.trimAscii()
            if (out.isEmpty()) {
                return "No web results found."
            }
            return out
        }
        let err = stderr.trimAscii()
        if (err.isEmpty()) {
            return "web_search failed with exit code ${exitCode}."
        }
        return "web_search failed: ${err}"
    } catch (e: Exception) {
        return "web_search exception: ${e}"
    }
}

@toolset[
    tools: [read, write, edit, grep, find, ls, exec, apply_patch, web_search]
]
public class LegacyInteropToolset {
}
