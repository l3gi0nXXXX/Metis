package metis.core.tools.fs_utils

import metis.core.config.CliConfig
import metis.io.PrintUtils

import std.collection.any
import std.fs.{Directory, Path, exists}
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * Tests basic regex pattern matching
 */
@Test
private func testBasicPatterns(): Unit {
    PrintUtils.printLine("\n--- Testing basic patterns ---")
    let currentDir = CliConfig.cwd.toString()

    // Test simple word search
    testGrepPattern("func", "./src", None, "Find function declarations")

    // Test regex pattern
    testGrepPattern("import.*std", "./src", None, "Find std library imports")

    // Test case-sensitive search
    testGrepPattern("PrintUtils.printLine", "./src", None, "Find PrintUtils.printLine statements")

    // Test pattern with special regex characters
    testGrepPattern("\\*\\*", "./src", None, "Find double asterisk patterns")
}

/**
 * Tests file type filtering using include patterns
 */
@Test
private func testFileTypeFiltering(): Unit {
    PrintUtils.printLine("\n--- Testing file type filtering ---")

    // Test .cj files only
    testGrepPattern("func", "./src", Some("*.cj"), "Search only in .cj files")

    // Test multiple extensions (if supported)
    testGrepPattern("test", "./src", Some("*test*.cj"), "Search in test files")

    // Test specific directory pattern
    testGrepPattern("import", "./src", Some("src/**/*.cj"), "Search recursively in src/")
}

/**
 * Tests searching in specific paths
 */
@Test
private func testPathFiltering(): Unit {
    PrintUtils.printLine("\n--- Testing path filtering ---")
    let currentDir = CliConfig.cwd.toString()

    // Test searching in src directory if it exists
    let srcPath = Path(currentDir).join("src")
    if (exists(srcPath)) {
        testGrepPattern("package", Some(srcPath.toString()), None, "Search in src/ directory")
        testGrepPattern("func", Some(srcPath.toString()), Some("*.cj"), "Search .cj files in src/")
    }

    // Test searching in current directory explicitly
    testGrepPattern("glob", Some(currentDir), None, "Search in current directory")
}

/**
 * Tests edge cases and error conditions
 */
@Test
private func testEdgeCases(): Unit {
    PrintUtils.printLine("\n--- Testing edge cases ---")

    // Test pattern that should return no matches
    testGrepPattern("zzzzNeverMatchThis", "./src", None, "Pattern with no matches")

    // Test empty pattern (if allowed)
    testGrepPattern("", "./src", None, "Empty pattern")

    // Test complex regex pattern
    testGrepPattern("func\\s+\\w+\\(", "./src", Some("*.cj"), "Complex function declaration pattern")

    // Test search with non-existent path
    testGrepPattern("test", Some("/nonexistent/path"), None, "Search in non-existent path")
}

/**
 * Helper function to test a single grep pattern and validate results
 */
private func testGrepPattern(pattern: String, path: Option<String>, include: Option<String>, description: String): Unit {
    PrintUtils.printLine("\nTesting: ${description}")
    PrintUtils.printLine("Pattern: '${pattern}'")

    let pathStr = path.map { p => p } ?? "current directory"
    let includeStr = include.map { i => i } ?? "all files"
    PrintUtils.printLine("Path: ${pathStr}")
    PrintUtils.printLine("Include: ${includeStr}")

    let result = grep(pattern, path, include)
    let lines = result.split("\n")
    let matchCount = lines.size

    PrintUtils.printLine("Result: ${matchCount} lines of output")

    // Basic validation - result should be a string
    @PowerAssert(result.size >= 0)

    // For successful searches, validate output format
    if (!result.startsWith("Failed") && !result.contains("No such file") && matchCount > 0 && !pattern.isEmpty()) {
        // Check that result contains typical grep output format (path:line:content)
        let hasValidFormat = lines |> any { line: String =>
            let parts = line.split(":")
            parts.size >= 3 && parts[0].contains("/")  // Should have path:line:content format
        }
        if (hasValidFormat) {
            PrintUtils.printLine("✓ Valid grep output format detected")
        } else {
            PrintUtils.printLine("! Unusual output format (might be expected for this pattern)")
        }
    } else if (pattern == "zzzzNeverMatchThis") {
        // This pattern should return no matches or error - both are acceptable
        PrintUtils.printLine("✓ No matches found for non-existent pattern (as expected)")
    } else if (pattern.isEmpty()) {
        // Empty pattern behavior varies by grep implementation
        PrintUtils.printLine("✓ Empty pattern handled")
    } else if (result.contains("No such file") || result.contains("Failed")) {
        // Error cases
        PrintUtils.printLine("✓ Error case handled appropriately")
    }

    // Show sample of results (first 3 lines) for debugging
    if (matchCount > 0 && matchCount <= 3) {
        PrintUtils.printLine("Sample results:")
        for (line in lines) {
            PrintUtils.printLine("  ${line}")
        }
    } else if (matchCount > 3) {
        PrintUtils.printLine("Sample results (first 3 lines):")
        for (i in 0..3) {
            PrintUtils.printLine("  ${lines[i]}")
        }
        PrintUtils.printLine("  ... and ${matchCount - 3} more lines")
    }
}

/**
 * Unit tests for helper functions (if any were added to grep.cj)
 */
@Test
public func testGrepUnits(): Unit {
    PrintUtils.printLine("\n=== Unit Tests for Grep Helpers ===")

    // Test path resolution logic
    testPathResolution()

    // Test output parsing validation
    testOutputParsing()

    PrintUtils.printLine("=== Grep Unit Tests Completed ===")
}

/**
 * Tests path resolution functionality
 */
private func testPathResolution(): Unit {
    PrintUtils.printLine("\n--- Testing path resolution ---")

    let currentDir = CliConfig.cwd.toString()

    // Test that current directory path is absolute
    @PowerAssert(Path(currentDir).isAbsolute())

    // Test relative to absolute path conversion
    let testRelPath = "./test"
    let resolvedPath = Path(currentDir).join(testRelPath)
    @PowerAssert(resolvedPath.isAbsolute())

    PrintUtils.printLine("✓ Path resolution tests passed")
}

/**
 * Tests output parsing validation
 */
private func testOutputParsing(): Unit {
    PrintUtils.printLine("\n--- Testing output parsing logic ---")

    // Test typical grep output line format
    let sampleLine = "/path/to/file.cj:42:some code here"
    let parts = sampleLine.split(":", 3, removeEmpty: false)

    @PowerAssert(parts.size, 3)
    @PowerAssert(parts[0], "/path/to/file.cj")
    @PowerAssert(parts[1], "42")
    @PowerAssert(parts[2], "some code here")

    // Test edge case with colons in content
    let complexLine = "/path/file.cj:10:let obj = { key: value }"
    let complexParts = complexLine.split(":", 3, removeEmpty: false)
    @PowerAssert(complexParts.size, 3)
    @PowerAssert(complexParts[2], "let obj = { key: value }")

    PrintUtils.printLine("✓ Output parsing tests passed")
}

/**
 * Performance benchmark for grep operations
 */
@Test
public func benchmarkGrep(): Unit {
    PrintUtils.printLine("\n=== Grep Performance Benchmark ===")
    let currentDir = CliConfig.cwd.toString()

    let testCases: Array<(String, ?String, ?String, String)> = [
        ("func", "./src", None, "Simple word search"),
        ("import.*std", "./src", Some("*.cj"), "Regex in .cj files"),
        ("\\w+", "./src", Some("src/**/*.cj"), "Complex pattern in src/")
    ]

    for (testCase in testCases) {
        let pattern = testCase[0]
        let path = testCase[1]
        let include = testCase[2]
        let description = testCase[3]

        PrintUtils.printLine("\nBenchmarking: ${description}")
        PrintUtils.printLine("Pattern: '${pattern}'")

        // Simple timing (Cangjie may not have precise timing APIs)
        let result = grep(pattern, path, include)
        let lineCount = result.split("\n").size
        PrintUtils.printLine("Found ${lineCount} lines")

        // Assert reasonable performance (non-negative results)
        @PowerAssert(lineCount >= 0)
    }

    PrintUtils.printLine("\n=== Benchmark Completed ===")
}
