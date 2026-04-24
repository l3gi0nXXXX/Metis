package metis.core.tools.code_compression

import magic.log.LogUtils

import metis.core.config.CliConfig
import metis.core.model.ModelTokenLimits
import metis.core.model.CliModelManager

import std.fs.Path

protected func compressCode(
    filePath: String,
    startLine!: Int = 1,
    endLine!: Int = Int.Max,
    originalContent!: String = ""): String {
    let language: String = match {
        case filePath.endsWith(".cj") => "cangjie"
        case filePath.endsWith(".py") => "python"
        case filePath.endsWith(".java") => "java"
        case _ =>
            LogUtils.debug("Code compression not supported for this file type `${Path(filePath).extensionName}`.")
            return originalContent
    }

    let content = SkeletonAnalyzer.analyzeFile(filePath, language, startLine: startLine, endLine: endLine)
    // If there is something wrong when compressing the code (e.g, code with parsing error cannot be parsed), return the original content.
    if (content.isEmpty()) {
        return originalContent
    }

    """
The returned code is too large to return in full. Instead, you will receive a compressed index of code entities (functions, classes, structs, enums, etc.). The index contains: the signature of each entity, its hierarchical structure (e.g., a method inside a class), and its location (start and end line numbers). The following are the compressed index of code entities, formatted in the following XML string:

```
${content}
```

To get the full code for an entity, you can read the source file from the provided start line to end line, and expand the range slightly to include surrounding context, such as comments, annotations, or preprocessor directives, which may be crucial.
"""
}

protected func getCompressionThreshold(batchRead: Bool): Int {
    let modelTokenLimit = ModelTokenLimits.getInputLimit(
        (CliModelManager.lastAvailableModel ?? CliModelManager.model).fullName
    )
    let compressionThreshold = if (batchRead) {
        CliConfig.fileBatchReadThreshold
    } else {
        CliConfig.fileReadThreshold
    }

    // each token has about 4 characters on average
    Int64(compressionThreshold * Float64(modelTokenLimit) * 4.0)
}
