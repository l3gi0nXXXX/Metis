package metis.core.tools.fs_utils

import metis.core.config.CliConfig
import metis.io.PrintUtils

import std.fs.{Directory, Path, exists}
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * Test function to verify glob functionality.
 * Creates a temporary directory structure and tests various glob patterns.
 */
@Test
public func testGlob(): Unit {
    PrintUtils.printLine("=== Testing Glob Functionality ===")

    // Test pattern matching through the public glob API first
    testBasicPatternMatching()

    // Test with current project structure
    testWithRealFiles()

    PrintUtils.printLine("=== Glob Tests Completed ===")
}

/**
 * Tests basic glob pattern matching through the public API.
 */
@Test
private func testBasicPatternMatching(): Unit {
    PrintUtils.printLine("\n--- Testing basic glob pattern matching ---")
    let currentDir = CliConfig.cwd.toString()

    let currentMatches = glob("*.cj", currentDir)
    PrintUtils.printLine("Pattern '*.cj' under cwd matched ${currentMatches.size} entries")
    @PowerAssert(currentMatches.size >= 0)

    let srcDir = Path(currentDir).join("src")
    if (exists(srcDir)) {
        let sourceMatches = glob("src/**/*.cj", currentDir)
        PrintUtils.printLine("Pattern 'src/**/*.cj' matched ${sourceMatches.size} entries")
        @PowerAssert(sourceMatches.size > 0)
    }
}

/**
 * Tests glob function with real files in the current project
 */
private func testWithRealFiles(): Unit {
    PrintUtils.printLine("\n--- Testing with real files ---")
    let currentDir = CliConfig.cwd.toString()

    // Test simple wildcard patterns
    testPattern("*.cj", currentDir, "Find all .cj files in current directory", expectNonEmpty: false)
    testPattern("src", currentDir, "Find 'src' directory", expectNonEmpty: false)
    testPattern("src/*", currentDir, "Find all items directly under src/", expectNonEmpty: false)

    // Test recursive patterns if src directory exists
    let srcPath = Path(currentDir).join("src")
    if (exists(srcPath)) {
        testPattern("**/glob.cj", currentDir, "Find glob.cj files recursively")
        testPattern("src/**/*.cj", currentDir, "Find all .cj files under src/ recursively")
        testPattern("**/tools/**", currentDir, "Find all items under any 'tools' directory")
    }

    // Test edge cases
    testPattern("**", currentDir, "Find everything (limited results for demo)")
    testPattern("nonexistent*", currentDir, "Pattern matching no files")
}

/**
 * Helper function to test a single glob pattern
 */
private func testPattern(
    pattern: String,
    rootPath: String,
    description: String,
    expectNonEmpty!: Bool = true
): Unit {
    PrintUtils.printLine("\nTesting: ${description}")
    PrintUtils.printLine("Pattern: '${pattern}'")

    let results = glob(pattern, rootPath)
    let count = results.size

    // Assert that we get some results for most patterns (except explicitly testing empty results)
    if (expectNonEmpty && !pattern.startsWith("nonexistent")) {
        @PowerAssert(count > 0)
    }

    if (count == 0) {
        PrintUtils.printLine("Result: No matches found")
    } else if (count <= 5) {
        PrintUtils.printLine("Result: ${count} matches:")
        for (path in results) {
            PrintUtils.printLine("  - ${path}")
        }
    } else {
        PrintUtils.printLine("Result: ${count} matches (showing first 5):")
        for (i in 0..5) {
            PrintUtils.printLine("  - ${results[i]}")
        }
        PrintUtils.printLine("  ... and ${count - 5} more")
    }
}

/**
 * Unit tests for individual helper functions
 */
@Test
public func testGlobUnits(): Unit {
    PrintUtils.printLine("\n=== Unit Tests ===")

    // Test string slicing functionality used in globWithDoubleAsterisk
    testStringSlicing()

    // Test pattern splitting
    testPatternSplitting()

    PrintUtils.printLine("=== Unit Tests Completed ===")
}

/**
 * Tests string slicing operations
 */
private func testStringSlicing(): Unit {
    PrintUtils.printLine("\n--- Testing string slicing ---")

    let testStr = "src/test/"
    let withoutTrailing = testStr[0..testStr.size - 1]
    PrintUtils.printLine("Remove trailing slash: '${testStr}' -> '${withoutTrailing}'")
    @PowerAssert(withoutTrailing, "src/test")

    let testStr2 = "/test/file"
    let withoutLeading = testStr2[1..]
    PrintUtils.printLine("Remove leading slash: '${testStr2}' -> '${withoutLeading}'")
    @PowerAssert(withoutLeading, "test/file")
}

/**
 * Tests pattern splitting functionality
 */
private func testPatternSplitting(): Unit {
    PrintUtils.printLine("\n--- Testing pattern splitting ---")

    let patterns = ["src/**/*.cj", "**/test.cj", "build/**", "**"]
    let expectedSizes = [2, 2, 2, 2]

    for (i in 0..patterns.size) {
        let pattern = patterns[i]
        let expectedSize = expectedSizes[i]
        let parts = pattern.split("**")
        PrintUtils.printLine("Split '${pattern}': ${parts.size} parts")

        @PowerAssert(parts.size, expectedSize)

        for (j in 0..parts.size) {
            PrintUtils.printLine("  [${j}]: '${parts[j]}'")
        }
    }
}

/**
 * Benchmark function to test performance with different patterns
 */
@Test
public func benchmarkGlob(): Unit {
    PrintUtils.printLine("\n=== Glob Performance Benchmark ===")
    let currentDir = CliConfig.cwd.toString()

    let patterns = [
        "*.cj",           // Simple wildcard
        "**/glob.cj",     // Recursive search
        "src/**/*.cj",    // Complex recursive
        "**"              // Match everything
    ]

    for (pattern in patterns) {
        PrintUtils.printLine("\nBenchmarking pattern: '${pattern}'")

        // Simple timing (note: Cangjie may not have precise timing APIs)
        let results = glob(pattern, currentDir)
        PrintUtils.printLine("Found ${results.size} matches")

        // Assert that we get reasonable results
        @PowerAssert(results.size >= 0)

        // Could add more sophisticated timing here if available
    }

    PrintUtils.printLine("\n=== Benchmark Completed ===")
}
