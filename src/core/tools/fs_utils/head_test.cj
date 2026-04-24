package metis.core.tools.fs_utils

import metis.core.config.CliConfig
import metis.io.PrintUtils

import std.collection.*
import std.fs.*
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * Test function to verify head functionality.
 * Tests reading first N lines from files with various scenarios.
 */
@Test
public func testHead(): Unit {
    PrintUtils.printLine("=== Testing Head Functionality ===")

    // Test basic head operations
    testBasicHead()

    // Test different line counts
    testLineCounts()

    // Test edge cases
    testHeadEdgeCases()

    // Test error conditions
    testHeadErrors()

    PrintUtils.printLine("=== Head Tests Completed ===")
}

/**
 * Tests basic head functionality with real files
 */
@Test
private func testBasicHead(): Unit {
    PrintUtils.printLine("\n--- Testing basic head functionality ---")
    let currentDir = CliConfig.cwd.toString()

    // Test head on existing .cj files if they exist
    let srcPath = Path(currentDir).join("src")
    if (exists(srcPath)) {
        // Find a .cj file to test with
        for (item in Directory.readFrom(srcPath)) {
            if (item.isRegular() && item.name.endsWith(".cj")) {
                let filePath = item.path.toString()
                testHeadOnFile(filePath, 5, "Head of ${item.name} (5 lines)")
                break
            }
        }

        // Find any file recursively in src/
        findAndTestFile(srcPath, "*.cj", 10, "Head of Cangjie file (10 lines)")
    }

    // Test head on this test file itself
    let testFilePath = Path(currentDir).join("src/core/tools/head_test.cj")
    if (exists(testFilePath)) {
        testHeadOnFile(testFilePath.toString(), 3, "Head of head_test.cj (3 lines)")
    }
}

/**
 * Tests different line count parameters
 */
@Test
private func testLineCounts(): Unit {
    PrintUtils.printLine("\n--- Testing different line counts ---")

    // Create a temporary test file with known content
    let testContent = createTestFileContent(20)
    let tempFilePath = createTempFile(testContent)

    if (!tempFilePath.isEmpty()) {
        // Test various line counts
        let testCases = [
            (1, "Single line"),
            (5, "Five lines"),
            (10, "Default ten lines"),
            (15, "Fifteen lines"),
            (25, "More lines than file contains")
        ]

        for (testCase in testCases) {
            let lines = testCase[0]
            let description = testCase[1]
            testHeadOnFile(tempFilePath, lines, description)
        }

        // Clean up temporary file
        cleanupTempFile(tempFilePath)
    }
}

/**
 * Tests edge cases for head functionality
 */
@Test
private func testHeadEdgeCases(): Unit {
    PrintUtils.printLine("\n--- Testing head edge cases ---")

    // Test with empty file
    let emptyFilePath = createTempFile("")
    if (!emptyFilePath.isEmpty()) {
        testHeadOnFile(emptyFilePath, 5, "Head of empty file")
        cleanupTempFile(emptyFilePath)
    }

    // Test with single line file
    let singleLineFile = createTempFile("Single line only\n")
    if (!singleLineFile.isEmpty()) {
        testHeadOnFile(singleLineFile, 10, "Head of single line file")
        cleanupTempFile(singleLineFile)
    }

    // Test with file containing long lines
    let longLineContent = "This is a very long line that contains many characters and should test how head handles long content within individual lines without issues.\n"
    let longLineFile = createTempFile(longLineContent + longLineContent + longLineContent)
    if (!longLineFile.isEmpty()) {
        testHeadOnFile(longLineFile, 2, "Head of file with long lines")
        cleanupTempFile(longLineFile)
    }
}

/**
 * Tests error conditions for head
 */
@Test
private func testHeadErrors(): Unit {
    PrintUtils.printLine("\n--- Testing head error conditions ---")

    // Test non-existent file
    testHeadError("/nonexistent/file.txt", 5, "Non-existent file")

    // Test relative path
    testHeadError("relative/path.txt", 5, "Relative path")

    // Test directory instead of file
    let currentDir = CliConfig.cwd.toString()
    testHeadError(currentDir, 5, "Directory instead of file")

    // Test negative line count
    let testContent = createTestFileContent(5)
    let tempFile = createTempFile(testContent)
    if (!tempFile.isEmpty()) {
        testHeadError(tempFile, -1, "Negative line count")
        testHeadError(tempFile, 0, "Zero line count")
        cleanupTempFile(tempFile)
    }
}

/**
 * Helper function to test head on a specific file
 */
private func testHeadOnFile(filePath: String, lines: Int64, description: String): Unit {
    PrintUtils.printLine("\nTesting: ${description}")
    PrintUtils.printLine("File: ${filePath}")
    PrintUtils.printLine("Lines: ${lines}")

    let result = head(filePath, lines: lines)
    let resultLines = result.split("\n")
    let actualLineCount = resultLines.size

    PrintUtils.printLine("Result: ${actualLineCount} lines returned")

    // Basic validation
    @PowerAssert(result.size >= 0)

    // For successful results, verify format and constraints
    if (!result.startsWith("File does not exist") &&
        !result.startsWith("Path is not a regular file") &&
        !result.startsWith("File path must be absolute")) {

        if (result == "File is empty: ${filePath}") {
            PrintUtils.printLine("✓ Empty file handled correctly")
        } else {
            // Verify line count is reasonable (should be <= requested lines)
            if (actualLineCount <= lines + 1) {  // +1 for potential empty last line
                PrintUtils.printLine("✓ Line count constraint satisfied")
            } else {
                PrintUtils.printLine("! Line count higher than expected")
            }

            // Check for line number format in output
            let hasLineNumbers = resultLines |> any { line: String =>
                line.contains("\t") && line.split("\t").size >= 2
            }
            if (hasLineNumbers) {
                PrintUtils.printLine("✓ Line numbers detected in output")
            }

            // Show sample output
            if (actualLineCount > 0 && actualLineCount <= 3) {
                PrintUtils.printLine("Sample output:")
                for (line in resultLines) {
                    if (!line.isEmpty()) {
                        PrintUtils.printLine("  ${line}")
                    }
                }
            } else if (actualLineCount > 3) {
                PrintUtils.printLine("Sample output (first 2 lines):")
                for (i in 0..2) {
                    if (i < resultLines.size && !resultLines[i].isEmpty()) {
                        PrintUtils.printLine("  ${resultLines[i]}")
                    }
                }
                PrintUtils.printLine("  ... (${actualLineCount - 2} more lines)")
            }
        }
    }
}

/**
 * Helper function to test head error conditions
 */
private func testHeadError(filePath: String, lines: Int64, description: String): Unit {
    PrintUtils.printLine("\nTesting error: ${description}")
    PrintUtils.printLine("File: ${filePath}")
    PrintUtils.printLine("Lines: ${lines}")

    let result = head(filePath, lines: lines)

    // Should return an error message
    let isError = result.startsWith("File does not exist") ||
                  result.startsWith("Path is not a regular file") ||
                  result.startsWith("File path must be absolute") ||
                  result.startsWith("Number of lines must be positive") ||
                  result.startsWith("Failed to read file") ||
                  result.startsWith("Error reading file")

    if (isError) {
        PrintUtils.printLine("✓ Error handled correctly: ${result}")
    } else {
        PrintUtils.printLine("! Unexpected result for error case: ${result}")
    }

    @PowerAssert(result.size > 0)  // Should always return some message
}

/**
 * Helper function to find and test a file recursively
 */
private func findAndTestFile(searchPath: Path, pattern: String, lines: Int64, description: String): Unit {
    for (item in Directory.readFrom(searchPath)) {
        if (item.isRegular() && item.name.contains(".cj")) {
            testHeadOnFile(item.path.toString(), lines, description)
            return
        }
        if (item.isDirectory() && !ignored(item.path)) {
            findAndTestFile(item.path, pattern, lines, description)
        }
    }
}

/**
 * Unit tests for head helper functions
 */
@Test
public func testHeadUnits(): Unit {
    PrintUtils.printLine("\n=== Unit Tests for Head Functions ===")

    // Test headSimple function
    testHeadSimpleFunction()

    // Test parameter validation
    testParameterValidation()

    PrintUtils.printLine("=== Head Unit Tests Completed ===")
}

/**
 * Tests the headSimple function
 */
private func testHeadSimpleFunction(): Unit {
    PrintUtils.printLine("\n--- Testing headSimple function ---")

    let testContent = createTestFileContent(8)
    let tempFile = createTempFile(testContent)

    if (!tempFile.isEmpty()) {
        let simpleResult = headSimple(tempFile, lines: 3)
        let normalResult = head(tempFile, lines: 3)

        PrintUtils.printLine("Simple head result length: ${simpleResult.size}")
        PrintUtils.printLine("Normal head result length: ${normalResult.size}")

        // Simple version should be shorter (no line numbers)
        @PowerAssert(simpleResult.size > 0)
        @PowerAssert(simpleResult.size < normalResult.size)  // Should be shorter without line numbers

        cleanupTempFile(tempFile)
        PrintUtils.printLine("✓ headSimple function test passed")
    }
}

/**
 * Tests parameter validation logic
 */
private func testParameterValidation(): Unit {
    PrintUtils.printLine("\n--- Testing parameter validation ---")

    let currentDir = CliConfig.cwd.toString()

    // Test absolute path requirement
    let relativeResult = head("relative/path", lines: 5)
    @PowerAssert(relativeResult, "File path must be absolute")

    // Test positive line count requirement
    let tempFile = createTempFile("test\n")
    if (!tempFile.isEmpty()) {
        let negativeResult = head(tempFile, lines: -1)
        @PowerAssert(negativeResult, "Number of lines must be positive")

        let zeroResult = head(tempFile, lines: 0)
        @PowerAssert(zeroResult, "Number of lines must be positive")

        cleanupTempFile(tempFile)
    }

    PrintUtils.printLine("✓ Parameter validation tests passed")
}
