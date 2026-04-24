package metis.core.tools.code_compression

import metis.core.tools.code_compression.cangjie_analyzer.SkeletonAnalyzerCJ

import std.fs.Path

@When[enable_tree_sitter == "true"]
foreign func get_skeleton_xml_range(filePath: CString, language: CString, startLine: Int, endLine: Int): CString

@When[enable_tree_sitter == "true"]
private func doAnalyzeFile(filePath: Path, language: String, startLine!: Int = 1, endLine!: Int = Int.Max): String {
    var _filePath = unsafe {LibC.mallocCString(filePath.toString())}
    var _lang = unsafe {LibC.mallocCString(language)}
    var _xml = unsafe {
        get_skeleton_xml_range(_filePath, _lang, startLine, endLine)
    }
    let xml = _xml.toString()
    unsafe {
        LibC.free(_filePath)
        LibC.free(_lang)
        LibC.free(_xml)
    }
    return xml
}

/**
 * When enable_tree_sitter is false, only Cangjie analyzer is supported.
 */
@When[enable_tree_sitter != "true"]
private func doAnalyzeFile(filePath: Path, language: String, startLine!: Int = 1, endLine!: Int = Int.Max): String {
    throw Exception("Unsupported language for code compression: ${language}")
}

//-----------------------------------------------------------------------------------

public class SkeletonAnalyzer {
    public static func analyzeFile(filePath: Path,
                                   language: String,
                                   startLine!: Int = 1,
                                   endLine!: Int = Int.Max): String {
        match (language) {
            case "cangjie" =>
                SkeletonAnalyzerCJ.analyzeFile(filePath, startLine: startLine, endLine: endLine)
            case "java" | "python" =>
                doAnalyzeFile(filePath, language, startLine: startLine, endLine: endLine)
            case _ => throw Exception("Unsupported language for code compression: ${language}")
        }
    }

    protected static func analyzeFile(filePath: String,
                                      language: String,
                                      startLine!: Int = 1,
                                      endLine!: Int = Int.Max): String {
        analyzeFile(Path(filePath), language, startLine: startLine, endLine: endLine)
    }
}
