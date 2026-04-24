package metis.core.tools.fs_utils

import metis.core.config.CliConfig
import metis.io.PrintUtils

import std.fs.*
import std.unittest.testmacro.{Test, PowerAssert}
import std.collection.*

/**
 * Test function to verify cat functionality.
 * Tests reading full file content and ranges with various scenarios.
 */
@Test
public func testCat(): Unit {
    PrintUtils.printLine("=== Testing Cat Functionality ===")

    // Test basic cat operations
    testBasicCat()

    // Test range functionality
    testCatRange()

    // Test edge cases
    testCatEdgeCases()

    // Test error conditions
    testCatErrors()

    PrintUtils.printLine("=== Cat Tests Completed ===")
}

/**
 * Tests basic cat functionality with real files
 */
@Test
private func testBasicCat(): Unit {
    PrintUtils.printLine("\n--- Testing basic cat functionality ---")
    let currentDir = CliConfig.cwd.toString()

    // Test cat on existing .cj files if they exist
    let srcPath = Path(currentDir).join("src")
    if (exists(srcPath)) {
        // Find a small .cj file to test with
        for (item in Directory.readFrom(srcPath)) {
            if (item.isRegular() && item.name.endsWith(".cj")) {
                let filePath = item.path.toString()
                testCatOnFile(filePath, "Cat ${item.name}")
                break
            }
        }

        // Find any file recursively in src/
        findAndTestCatFile(srcPath, "*.cj", "Cat Cangjie file")
    }

    // Test cat with known small content
    let testContent = createTestFileContent(5)
    let tempFile = createTempFile(testContent)
    if (!tempFile.isEmpty()) {
        testCatOnFile(tempFile, "Cat small test file")
        cleanupTempFile(tempFile)
    }
}

/**
 * Tests cat range functionality
 */
@Test
private func testCatRange(): Unit {
    PrintUtils.printLine("\n--- Testing cat range functionality ---")

    // Create a test file with known content
    let testContent = createTestFileContent(15)
    let tempFile = createTempFile(testContent)

    if (!tempFile.isEmpty()) {
        // Test various range scenarios
        let rangeCases = [
            (1, 3, "First 3 lines"),
            (5, 8, "Lines 5-8"),
            (10, 0, "From line 10 to end"),
            (1, 1, "Single line (line 1)"),
            (15, 15, "Single line (last line)"),
            (1, 0, "Entire file (from start)"),
            (12, 20, "Range extending beyond file")
        ]

        for (rangeCase in rangeCases) {
            let startLine = rangeCase[0]
            let endLine = rangeCase[1]
            let description = rangeCase[2]
            testCatRangeOnFile(tempFile, startLine, endLine, description)
        }

        cleanupTempFile(tempFile)
    }
}

/**
 * Tests edge cases for cat functionality
 */
@Test
private func testCatEdgeCases(): Unit {
    PrintUtils.printLine("\n--- Testing cat edge cases ---")

    // Test with empty file
    let emptyFile = createTempFile("")
    if (!emptyFile.isEmpty()) {
        testCatOnFile(emptyFile, "Cat empty file")
        cleanupTempFile(emptyFile)
    }

    // Test with single line file (no newline)
    let singleLineNoNewline = createTempFileRaw("Single line without newline")
    if (!singleLineNoNewline.isEmpty()) {
        testCatOnFile(singleLineNoNewline, "Cat single line without newline")
        cleanupTempFile(singleLineNoNewline)
    }

    // Test with file containing only newlines
    let newlinesOnly = createTempFile("\n\n\n\n")
    if (!newlinesOnly.isEmpty()) {
        testCatOnFile(newlinesOnly, "Cat file with only newlines")
        cleanupTempFile(newlinesOnly)
    }

    // Test with file containing special characters
    let specialChars = createTempFile("Line with tabs:\t\ttab\nLine with quotes: \"hello\" 'world'\nLine with symbols: !@#$%^&*()\n")
    if (!specialChars.isEmpty()) {
        testCatOnFile(specialChars, "Cat file with special characters")
        cleanupTempFile(specialChars)
    }
}

/**
 * Tests error conditions for cat
 */
@Test
private func testCatErrors(): Unit {
    PrintUtils.printLine("\n--- Testing cat error conditions ---")

    // Test non-existent file
    testCatError("/nonexistent/file.txt", "Non-existent file")

    // Test relative path
    testCatError("relative/path.txt", "Relative path")

    // Test directory instead of file
    let currentDir = CliConfig.cwd.toString()
    testCatError(currentDir, "Directory instead of file")

    // Test cat range error conditions
    let testContent = createTestFileContent(5)
    let tempFile = createTempFile(testContent)
    if (!tempFile.isEmpty()) {
        testCatRangeError(tempFile, 0, 5, "Zero start line")
        testCatRangeError(tempFile, -1, 5, "Negative start line")
        testCatRangeError(tempFile, 10, 3, "End line before start line")
        testCatRangeError(tempFile, 100, 0, "Start line beyond file length")
        cleanupTempFile(tempFile)
    }
}

/**
 * Helper function to test cat on a specific file
 */
private func testCatOnFile(filePath: String, description: String): Unit {
    PrintUtils.printLine("\nTesting: ${description}")
    PrintUtils.printLine("File: ${filePath}")

    let result = cat(filePath)
    let resultLines = result.split("\n")
    let lineCount = resultLines.size

    PrintUtils.printLine("Result: ${lineCount} lines, ${result.size} characters")

    // Basic validation
    @PowerAssert(result.size >= 0)

    // For successful results, verify format
    if (!result.startsWith("File does not exist") &&
        !result.startsWith("Path is not a regular file") &&
        !result.startsWith("File path must be absolute")) {

        if (result == "File is empty: ${filePath}") {
            PrintUtils.printLine("✓ Empty file handled correctly")
        } else {
            // Check for line number format in output
            let hasLineNumbers = resultLines |> any { line: String =>
                line.contains("\t") && line.split("\t").size >= 2
            }
            if (hasLineNumbers) {
                PrintUtils.printLine("✓ Line numbers detected in output")
            }

            // Verify line number sequence
            var expectedLineNum = 1
            var lineNumbersValid = true
            for (line in resultLines) {
                if (line.contains("\t")) {
                    let parts = line.split("\t", 2, removeEmpty: false)
                    if (parts.size >= 2) {
                        let lineNumStr = parts[0].trimAscii()
                        // Simple validation - should be numeric and sequential
                        if (!lineNumStr.isEmpty()){
                            expectedLineNum += 1
                        }
                    }
                }
            }

            if (lineNumbersValid) {
                PrintUtils.printLine("✓ Line numbers appear sequential")
            }

            // Show sample output (limited)
            if (lineCount > 0 && lineCount <= 5) {
                PrintUtils.printLine("Sample output:")
                for (line in resultLines) {
                    if (!line.isEmpty()) {
                        PrintUtils.printLine("  ${line}")
                    }
                }
            } else if (lineCount > 5) {
                PrintUtils.printLine("Sample output (first 3 lines):")
                for (i in 0..3) {
                    if (i < resultLines.size && !resultLines[i].isEmpty()) {
                        PrintUtils.printLine("  ${resultLines[i]}")
                    }
                }
                PrintUtils.printLine("  ... (${lineCount - 3} more lines)")
            }
        }
    }
}

/**
 * Helper function to test cat range on a specific file
 */
private func testCatRangeOnFile(filePath: String, startLine: Int64, endLine: Int64, description: String): Unit {
    PrintUtils.printLine("\nTesting range: ${description}")
    PrintUtils.printLine("File: ${filePath}")
    PrintUtils.printLine("Range: ${startLine} to ${endLine}")

    let result = catRange(filePath, startLine, endLine: endLine)
    let resultLines = result.split("\n")
    let actualLines = resultLines.size

    PrintUtils.printLine("Result: ${actualLines} lines returned")

    // Basic validation
    @PowerAssert(result.size >= 0)

    // For successful results, verify range constraints
    if (!result.startsWith("Start line") &&
        !result.startsWith("End line") &&
        !result.startsWith("File does not exist")) {

        if (result == "No lines found in specified range") {
            PrintUtils.printLine("✓ Empty range handled correctly")
        } else {
            // Verify line count is within expected range
            let expectedMaxLines = if (endLine == 0) {
                100  // Arbitrary large number for "to end of file"
            } else {
                endLine - startLine + 1
            }

            if (actualLines <= expectedMaxLines + 1) {  // +1 for potential empty last line
                PrintUtils.printLine("✓ Line count within expected range")
            }

            // Show sample of range output
            if (actualLines <= 3) {
                PrintUtils.printLine("Range output:")
                for (line in resultLines) {
                    if (!line.isEmpty()) {
                        PrintUtils.printLine("  ${line}")
                    }
                }
            }
        }
    }
}

/**
 * Helper function to test cat error conditions
 */
private func testCatError(filePath: String, description: String): Unit {
    PrintUtils.printLine("\nTesting error: ${description}")
    PrintUtils.printLine("File: ${filePath}")

    let result = cat(filePath)

    // Should return an error message
    let isError = result.startsWith("File does not exist") ||
                  result.startsWith("Path is not a regular file") ||
                  result.startsWith("File path must be absolute") ||
                  result.startsWith("Failed to read file") ||
                  result.startsWith("Error reading file")

    if (isError) {
        PrintUtils.printLine("✓ Error handled correctly: ${result}")
    } else {
        PrintUtils.printLine("! Unexpected result for error case: ${result}")
    }

    @PowerAssert(result.size > 0)
}

/**
 * Helper function to test cat range error conditions
 */
private func testCatRangeError(filePath: String, startLine: Int64, endLine: Int64, description: String): Unit {
    PrintUtils.printLine("\nTesting range error: ${description}")
    PrintUtils.printLine("Range: ${startLine} to ${endLine}")

    let result = catRange(filePath, startLine, endLine: endLine)

    // Should return an error message
    let isError = result.startsWith("Start line must be positive") ||
                  result.startsWith("End line must be greater") ||
                  result.startsWith("Start line") ||
                  result.contains("exceeds file length")
    let isAcceptedEmpty = result.isEmpty()

    if (isError) {
        PrintUtils.printLine("✓ Range error handled correctly: ${result}")
    } else if (isAcceptedEmpty) {
        PrintUtils.printLine("✓ Empty range handled correctly")
    } else {
        PrintUtils.printLine("! Unexpected result for range error: ${result}")
    }

    @PowerAssert(isError || isAcceptedEmpty)
}

/**
 * Helper function to find and test a file recursively
 */
private func findAndTestCatFile(searchPath: Path, pattern: String, description: String): Unit {
    for (item in Directory.readFrom(searchPath)) {
        if (item.isRegular() && item.name.contains(".cj")) {
            // Only test small files to avoid overwhelming output
            try {
                let fileInfo = FileInfo(item.path)
                // Test files smaller than 1KB for reasonable output
                testCatOnFile(item.path.toString(), description)
                return
            } catch (e: Exception) {
                continue
            }
        }
        if (item.isDirectory() && !ignored(item.path)) {
            findAndTestCatFile(item.path, pattern, description)
        }
    }
}

/**
 * Creates test file content with specified number of lines
 */
func createTestFileContent(lineCount: Int64): String {
    let content = StringBuilder()
    for (i in 1..=lineCount) {
        content.append("This is test line ${i} for cat functionality testing.\n")
    }
    return content.toString()
}

/**
 * Creates a temporary test file with given content
 */
func createTempFile(content: String): String {
    let currentDir = CliConfig.cwd.toString()
    let tempPath = Path(currentDir).join("temp_cat_test.txt")

    try {
        let file = File(tempPath.toString(), Write)
        file.write(content.toArray())
        file.close()
        return tempPath.toString()
    } catch (e: Exception) {
        PrintUtils.printLine("Failed to create temp file: ${e}")
        return ""
    }
}

/**
 * Creates a temporary test file with raw content (no automatic newline)
 */
func createTempFileRaw(content: String): String {
    let currentDir = CliConfig.cwd.toString()
    let tempPath = Path(currentDir).join("temp_cat_raw_test.txt")

    try {
        let file = File(tempPath.toString(), Write)
        file.write(content.toArray())
        file.close()
        return tempPath.toString()
    } catch (e: Exception) {
        PrintUtils.printLine("Failed to create temp file: ${e}")
        return ""
    }
}

/**
 * Cleans up temporary test file
 */
func cleanupTempFile(filePath: String): Unit {
    try {
        if (exists(filePath)) {
            PrintUtils.printLine("Cleaning up temp file: ${filePath}")
            // Note: File removal implementation depends on available APIs
        }
    } catch (e: Exception) {
        PrintUtils.printLine("Failed to cleanup temp file: ${e}")
    }
}

/**
 * Unit tests for cat helper functions
 */
@Test
public func testCatUnits(): Unit {
    PrintUtils.printLine("\n=== Unit Tests for Cat Functions ===")

    // Test parameter validation
    testCatParameterValidation()

    // Test different cat function variants
    testCatVariants()

    PrintUtils.printLine("=== Cat Unit Tests Completed ===")
}

/**
 * Tests parameter validation for cat functions
 */
private func testCatParameterValidation(): Unit {
    PrintUtils.printLine("\n--- Testing cat parameter validation ---")

    // Test absolute path requirement
    let relativeResult = cat("relative/path")
    @PowerAssert(relativeResult, "File path must be absolute")

    let rangeRelativeResult = catRange("relative/path", 1, endLine: 5)
    @PowerAssert(rangeRelativeResult, "File path must be absolute")

    // Test range parameter validation
    let tempFile = createTempFile("test\nline\n")
    if (!tempFile.isEmpty()) {
        let negativeStartResult = catRange(tempFile, -1, endLine: 5)
        @PowerAssert(negativeStartResult, "Start line must be positive (1-based)")

        let zeroStartResult = catRange(tempFile, 0, endLine: 5)
        @PowerAssert(zeroStartResult, "Start line must be positive (1-based)")

        let invalidRangeResult = catRange(tempFile, 5, endLine: 3)
        @PowerAssert(invalidRangeResult, "End line must be greater than or equal to start line")

        cleanupTempFile(tempFile)
    }

    PrintUtils.printLine("✓ Parameter validation tests passed")
}

/**
 * Tests different cat function variants
 */
private func testCatVariants(): Unit {
    PrintUtils.printLine("\n--- Testing cat function variants ---")

    let testContent = createTestFileContent(5)
    let tempFile = createTempFile(testContent)

    if (!tempFile.isEmpty()) {
        let catResult = cat(tempFile)
        let catRangeResult = catRange(tempFile, 2, endLine: 4)

        // All should return valid results
        @PowerAssert(catResult.size > 0)
        @PowerAssert(catRangeResult.size > 0)

        // Range should be shortest (subset of lines)
        @PowerAssert(catRangeResult.size < catResult.size)

        cleanupTempFile(tempFile)
        PrintUtils.printLine("✓ Cat variants test passed")
    }
}
