package metis.core.tools.code_compression.cangjie_analyzer

import magic.log.LogUtils

import std.fs.*
import std.io.*
import std.ast.{Program, Token, parseProgram, cangjieLex}
import std.collection.{map, collectArray, ArrayList}

// public func readFile(filePath: String): String {
//     let path = Path(filePath)
//     if (!exists(path)) {
//         LogUtils.error("File not found: ${filePath}")
//         return ""
//     }
    
//     let file = File(path, Read)
//     let content = String.fromUtf8(readToEnd(file))
//     file.close()
//     content
// }

public func parseFile(code: String): Program {
    let tokens = cangjieLex(code)
    parseProgram(tokens)
}

public func getFullPackageName(program: Program): String {
    let header = program.packageHeader
    let prefix = String.join(header.prefixPaths |> map {t: Token => t.value} |> collectArray, delimiter: ".")
    let packageId = header.packageIdentifier.value
    if (prefix.isEmpty()) {
        packageId
    } else {
        prefix + "." + packageId
    }
}

public func findCjFiles(dir: Path): ArrayList<String> {
    let result = ArrayList<String>()
    let entries = Directory.readFrom(dir)
    
    for (entry in entries) {
        if (entry.isDirectory()) {
            result.add(all: findCjFiles(entry.path))
        } else if (entry.path.toString().endsWith(".cj")) {
            result.add(entry.path.toString())
        }
    }
    return result
}

public func findCjFiles(dir: String): ArrayList<String> {
    findCjFiles(Path(dir))
}