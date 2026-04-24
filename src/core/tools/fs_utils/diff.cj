package metis.core.tools.fs_utils

import metis.core.config.CliConfig

import std.fs.{File, Directory, remove}
import std.process.executeWithOutput
import std.collection.ArrayList

/**
 * Compute the diff of contents
 */
protected func diff(oldContent: String, newContent: String): String {
    // Create temporary files
    let tempDir = Directory.createTemp(CliConfig.dotDir)
    try {
        let oldFile = tempDir.join("old_content")
        let newFile = tempDir.join("new_content")

        // Write content to temp files
        File.writeTo(oldFile, oldContent.toArray())
        File.writeTo(newFile, newContent.toArray())

        // Try git diff first
        let (gitExitCode, gitStdOut, gitStdErr) = executeWithOutput(
            "git",
            ["diff", "--no-index", "--color=never", oldFile.toString(), newFile.toString()]
        )
        if (gitExitCode == 1 || gitExitCode == 0) { // git diff returns 1 when files differ, 0 when same
            return filterDiffOutput(String.fromUtf8(gitStdOut))
        }

        // Fallback to system diff
        let (diffExitCode, diffStdOut, diffStdErr) = executeWithOutput(
            "diff", ["-u", oldFile.toString(), newFile.toString()]
        )
        if (diffExitCode == 1 || diffExitCode == 0) { // diff returns 1 when files differ, 0 when same
            return filterDiffOutput(String.fromUtf8(diffStdOut))
        }

        // If both tools failed, show both content directly
        return "Old content:\n" + oldContent + "\nNew content:\n" + newContent
    } catch (e: Exception) {
        // If temp file operations fail, show both content directly
        return "Old content:\n" + oldContent + "\nNew content:\n" + newContent
    } finally {
        // Clean up temp files
        remove(tempDir, recursive: true)
    }
}

/**
 * Filter out temporary file paths from diff output
 */
private func filterDiffOutput(diffOutput: String): String {
    let lines = diffOutput.split('\n')
    let filteredLines = ArrayList<String>()

    for (line in lines) {
        // Skip lines that start with "diff --git", "index", "---", "+++"
        if (line.startsWith("diff --git") ||
            line.startsWith("index ") ||
            line.startsWith("--- ") ||
            line.startsWith("+++ ")) {
            continue
        }
        filteredLines.add(line)
    }

    return String.join(filteredLines.toArray(), delimiter: "\n")
}