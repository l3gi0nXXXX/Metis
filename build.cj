import std.process.*
import std.fs.*
import std.env.exit

@When[os == "Linux"]
const OS = "linux"

@When[os == "Windows"]
const OS = "windows"

@When[os == "macOS"]
const OS = "mac"

@When[os != "Linux" && os != "Windows" && os != "macOS"]
const OS = "unknown"

@When[arch == "aarch64"]
const ARCH = "aarch64"

@When[arch == "x86_64"]
const ARCH = "x64"

@When[arch != "x86_64" && arch != "aarch64"]
const ARCH = "unknown"

func checkStaticLinking(): Bool {
    try {
        let toml = String.fromUtf8(File.readFrom("./cjpm.toml"))
        return toml.contains("--static-libs")
    } catch (e: FSException) {
        println("Failed to read cjpm.toml: ${e.message}")
        return false
    }
}

func checkTreeSitterEnabled(): Bool {
    try {
        let toml = String.fromUtf8(File.readFrom("./cjpm.toml"))
        let normalized = toml.replace(" ", "").replace("\t", "")
        if (normalized.contains("enable_tree_sitter=true")) {
            return true
        }
        if (normalized.contains("enable_tree_sitter=false")) {
            return false
        }
        return true
    } catch (e: FSException) {
        return true
    }
}

func compileStaticLib(sourceFile: String, libFile: String): Bool {
    let objectFile = sourceFile.replace(".c", ".o")
    if (launch("gcc", ["-c", "-Wall", "-Werror", sourceFile, "-o", objectFile]).wait() != 0) {
        println("Building object file failed")
        return false
    }

    let buildProc = launch("ar", ["rcs", libFile, objectFile])
    if (buildProc.wait() != 0) {
        println("Building shared lib failed")
        return false
    }
    remove(objectFile)
    return true
}

func compileDynamicLib(sourceFile: String, libFile: String): Bool {
    let objectFile = sourceFile.replace(".c", ".o")
    if (launch("gcc", ["-c", "-Wall", "-Werror", "-fPIC", sourceFile, "-o", objectFile]).wait() != 0) {
        println("Building object file failed")
        return false
    }

    let buildProc = match (OS) {
        case "linux" | "windows"=>
            launch("gcc", ["-shared", "-o", libFile, objectFile])
        case "mac" =>
            launch("gcc", ["-dynamiclib", "-o", libFile, objectFile])
        case _ =>
            throw UnsupportedException("Unreachable")
    }
    if (buildProc.wait() != 0) {
        println("Building shared lib failed")
        return false
    }
    remove(objectFile)
    return true
}

func buildFFI(staticLib: Bool): Int64 {
    let ffiDir = "./ffi"
    let sourceFile = match(OS) {
        case "linux"|"mac" => "${ffiDir}/raw_input_linux.c"
        case "windows" => "${ffiDir}/raw_input_win.c"
        case _ => throw UnsupportedException("Unreachable")
    }
    let libFile = if (staticLib) {
        match(OS) {
            case "linux" | "mac" => "${ffiDir}/librawinput.a"
            case "windows" => "${ffiDir}/librawinput.lib"
            case _ => throw UnsupportedException("Unreachable")
        }
    } else {
         match(OS) {
            case "linux" => "${ffiDir}/librawinput.so"
            case "windows" => "${ffiDir}/librawinput.dll"
            case "mac" => "${ffiDir}/librawinput.dylib"
            case _ => throw UnsupportedException("Unreachable")
        }
    }

    if (!exists(libFile) ||
        FileInfo(libFile).lastModificationTime < FileInfo(sourceFile).lastModificationTime) {
        let status = if (staticLib) {
            compileStaticLib(sourceFile, libFile)
        } else {
            compileDynamicLib(sourceFile, libFile)
        }
        return if (status) { 0 } else { 1 }
    }
    return 0
}

func downloadTreeSitter(): Int64 {
    let targetDir = "./ffi/tree-sitter-signature-extraction"

    // Check if tree-sitter already exists
    if (!exists("${targetDir}/tree-sitter")) {
        // Download tree-sitter
        println("Starting download of tree-sitter...")
        let tsProc = launch("git", ["clone", "https://gitcode.com/gh_mirrors/tr/tree-sitter.git", "${targetDir}/tree-sitter", "--depth=1", "--branch=master"])
        if (tsProc.wait() != 0) {
            println("Failed to download tree-sitter")
            return 1
        }
    }

    // Check if tree-sitter-python already exists
    if (!exists("${targetDir}/tree-sitter-python")) {
        println("Starting download of tree-sitter-python...")
        // Download tree-sitter-python
        let tspProc = launch("git", ["clone", "https://gitcode.com/ohohei/tree-sitter.git", "${targetDir}/tree-sitter-python", "--depth=1", "--branch=master"])
        if (tspProc.wait() != 0) {
            println("Failed to download tree-sitter-python")
            return 1
        }
    }

    // Check if tree-sitter-java already exists
    if (!exists("${targetDir}/tree-sitter-java")) {
        println("Starting download of tree-sitter-java...")
        // Download tree-sitter-java
        let tsjProc = launch("git", ["clone", "https://gitcode.com/ohohei/tree-sitter-java.git", "${targetDir}/tree-sitter-java", "--depth=1", "--branch=master"])
        if (tsjProc.wait() != 0) {
            println("Failed to download tree-sitter-java")
            return 1
        }
    }

    return 0
}

func buildSignatureExtractorFFI(staticLib: Bool): Int64 {
    let sourceDir = "./ffi/tree-sitter-signature-extraction"
    let targetDir = "./ffi"

    // Determine the built library name based on OS and library type
    let libName = match (OS) {
        case "windows" =>
            if (staticLib) { "libsignature_extractor.lib" } else { "libsignature_extractor.dll" }
        case "linux" =>
            if (staticLib) { "libsignature_extractor.a" } else { "libsignature_extractor.so" }
        case "mac" =>
            if (staticLib) { "libsignature_extractor.a" } else { "libsignature_extractor.dylib" }
        case _ => throw UnsupportedException("Unsupported OS")
    }

    // Check if library already exists in target directory
    let targetLibPath = "${targetDir}/${libName}"
    if (exists(targetLibPath)) {
        return 0
    }
    let downloadStatus = downloadTreeSitter()
    if (downloadStatus != 0) {
        return downloadStatus
    }

    // Run make in the source directory
    let makeProc = launch("make", ["clean"], workingDirectory: Path(sourceDir))
    if (makeProc.wait() != 0) {
        println("Failed to clean previous build")
        return 1
    }

    let buildProc = launch("make", if (staticLib) { ["static"] } else { ["dynamic"] }, workingDirectory: Path(sourceDir))
    if (buildProc.wait() != 0) {
        println("Failed to build signature extractor library")
        return 1
    }

    // Move the built library to the ffi directory
    let sourceLibPath = "${sourceDir}/${libName}"

    try {
        rename(sourceLibPath, to: targetLibPath)
    } catch (e: FSException) {
        println("Failed to move library to ffi directory: ${e.message}")
        return 1
    }

    return 0
}

func getEnvOrExit(key: String): String {
    match (Process.current.getEnv(key)) {
        case Some(value) => value
        case None =>
            eprintln("${key} not set")
            exit(1)
    }
}

func checkStdx(): Bool {
    let version = "1.0.0.1"
    let magicDir = getEnvOrExit("MAGIC_PATH")
    let stdxDir = "${magicDir}/libs/cangjie-stdx-${OS}-${ARCH}-${version}"
    println("stdxDir: ${stdxDir}")
    return exists(stdxDir)
}

func downloadStdx(): Int64 {
    // Build CangjieMagic to download stdx
    let magicDir = getEnvOrExit("MAGIC_PATH")
    let proc = launch("cjpm", ["build"], workingDirectory: Path(magicDir))
    return proc.wait()
}

func stagePreBuild(): Int64 {
    if (OS == "unknown" || ARCH == "unknown") {
        println("Unsupported os or Arch")
        return 1
    }
    if (!checkStdx()) {
        println("stdx not found, try to download")
        let status = downloadStdx()
        if (status != 0) {
            println("Download stdx failed")
            return status
        }
    }

    let staticLib = checkStaticLinking()
    let treeSitterEnabled = checkTreeSitterEnabled()
    let signatureStatus = if (treeSitterEnabled) {
        buildSignatureExtractorFFI(staticLib)
    } else {
        0
    }
    return buildFFI(staticLib) | signatureStatus
}

func stagePostBuild(): Int64 {
    let targets = [
        "./target/release/unittest_bin/metis.app",
        "./target/debug/unittest_bin/metis.app"
    ]
    for (target in targets) {
        let status = wrapDotAppTestBinary(target)
        if (status != 0) {
            return status
        }
    }
    0
}

func wrapDotAppTestBinary(targetPath: String): Int64 {
    if (!exists(targetPath)) {
        return 0
    }
    let target = Path(targetPath)
    let realBinary = Path("${targetPath}.bin")
    if (!exists(realBinary)) {
        try {
            rename(target, to: realBinary)
        } catch (e: FSException) {
            eprintln("Failed to rename ${targetPath} to ${realBinary}: ${e.message}")
            return 1
        }
    } else {
        try {
            remove(target)
        } catch (e: FSException) {
            eprintln("Failed to remove existing wrapper ${targetPath}: ${e.message}")
            return 1
        }
    }

    let script = "#!/bin/sh\nexec \"${realBinary}\" \"$@\"\n"
    try {
        File.writeTo(target, script.toArray())
    } catch (e: FSException) {
        eprintln("Failed to write wrapper ${targetPath}: ${e.message}")
        return 1
    }
    if (launch("chmod", ["+x", targetPath]).wait() != 0) {
        eprintln("Failed to chmod +x ${targetPath}")
        return 1
    }
    0
}

main(): Int64 {
    match (Process.current.arguments[0]) {
        case "pre-build" => stagePreBuild()
        case "post-build" => stagePostBuild()
        case _ => 0
    }
}
