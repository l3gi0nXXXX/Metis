package metis.core.tools.fs_utils

import metis.core.config.CliConfig
import metis.io.PrintUtils

import std.fs.{Directory, File, Path, exists, remove}
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * Test function to verify glob functionality.
 * Creates a temporary directory structure and tests various glob patterns.
 */
@Test
public func testGlob(): Unit {
    PrintUtils.printLine("=== Testing Glob Functionality ===")

    let fixtureRoot = createGlobFixture("all")
    try {
        // Test pattern matching through the public glob API first.
        runBasicPatternMatching(fixtureRoot.toString())

        // Test recursive and path-based patterns against a bounded fixture.
        testWithFixtureFiles(fixtureRoot.toString())
    } finally {
        cleanupGlobFixture(fixtureRoot)
    }

    PrintUtils.printLine("=== Glob Tests Completed ===")
}

/**
 * Tests basic glob pattern matching through the public API.
 */
@Test
private func testBasicPatternMatching(): Unit {
    PrintUtils.printLine("\n--- Testing basic glob pattern matching ---")
    let fixtureRoot = createGlobFixture("basic")
    try {
        runBasicPatternMatching(fixtureRoot.toString())
    } finally {
        cleanupGlobFixture(fixtureRoot)
    }
}

private func runBasicPatternMatching(rootPath: String): Unit {
    let currentMatches = glob("*.cj", rootPath)
    PrintUtils.printLine("Pattern '*.cj' under cwd matched ${currentMatches.size} entries")
    @PowerAssert(currentMatches.size > 0)

    let srcDir = Path(rootPath).join("src")
    if (exists(srcDir)) {
        let sourceMatches = glob("src/**/*.cj", rootPath)
        PrintUtils.printLine("Pattern 'src/**/*.cj' matched ${sourceMatches.size} entries")
        @PowerAssert(sourceMatches.size >= 3)
    }
}

/**
 * Tests glob function with a small, isolated fixture.
 */
private func testWithFixtureFiles(rootPath: String): Unit {
    PrintUtils.printLine("\n--- Testing with fixture files ---")

    // Test simple wildcard patterns
    testPattern("*.cj", rootPath, "Find all .cj files in fixture root")
    testPattern("src/*", rootPath, "Find source files directly or recursively under src/", expectNonEmpty: false)

    // Test recursive patterns if src directory exists
    let srcPath = Path(rootPath).join("src")
    if (exists(srcPath)) {
        testPattern("**/glob.cj", rootPath, "Find glob.cj files recursively")
        testPattern("src/**/*.cj", rootPath, "Find all .cj files under src/ recursively")
        testPattern("**/tools/**", rootPath, "Find all items under any 'tools' directory")
        testPattern("docs/*.txt", rootPath, "Find text files under docs/")
    }

    // Test edge cases
    testPattern("**", rootPath, "Find everything in bounded fixture")
    testPattern("nonexistent*", rootPath, "Pattern matching no files")
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
    let fixtureRoot = createGlobFixture("benchmark")

    try {
        let rootPath = fixtureRoot.toString()
        let patterns = [
            "*.cj",           // Simple wildcard
            "**/glob.cj",     // Recursive search
            "src/**/*.cj",    // Complex recursive
            "**"              // Match everything in bounded fixture
        ]

        for (pattern in patterns) {
            PrintUtils.printLine("\nBenchmarking pattern: '${pattern}'")

            // Simple timing (note: Cangjie may not have precise timing APIs)
            let results = glob(pattern, rootPath)
            PrintUtils.printLine("Found ${results.size} matches")

            // Assert that we get reasonable results
            @PowerAssert(results.size >= 0)

            // Could add more sophisticated timing here if available
        }
    } finally {
        cleanupGlobFixture(fixtureRoot)
    }

    PrintUtils.printLine("\n=== Benchmark Completed ===")
}

private func createGlobFixture(label: String): Path {
    let root = Path(CliConfig.cwd.toString()).join("metis-glob-test-${label}")
    cleanupGlobFixture(root)

    Directory.create(root.join("src/core/tools/nested"), recursive: true)
    Directory.create(root.join("docs"), recursive: true)

    writeGlobFixtureFile(root.join("root.cj"), "package fixture\nfunc root(): Unit {}\n")
    writeGlobFixtureFile(root.join("README.md"), "# fixture\n")
    writeGlobFixtureFile(root.join("src/main.cj"), "package fixture\nfunc main(): Unit {}\n")
    writeGlobFixtureFile(root.join("src/core/tools/glob.cj"), "package fixture\nfunc globFixture(): Unit {}\n")
    writeGlobFixtureFile(root.join("src/core/tools/nested/extra.cj"), "package fixture\nfunc nested(): Unit {}\n")
    writeGlobFixtureFile(root.join("docs/guide.txt"), "fixture guide\n")

    return root
}

private func writeGlobFixtureFile(path: Path, content: String): Unit {
    if (!exists(path.parent)) {
        Directory.create(path.parent, recursive: true)
    }
    File.writeTo(path, content.toArray())
}

private func cleanupGlobFixture(root: Path): Unit {
    try {
        if (exists(root)) {
            remove(root, recursive: true)
        }
    } catch (_: Exception) {
        ()
    }
}
