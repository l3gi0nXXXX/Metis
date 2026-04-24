package metis.core.tools.code_compression.cangjie_analyzer

// TODO: macroDecl, extendDecl, macroExpandDecl, TypeAliasDecl, VarDecl
public class CodeEntity {
    public let name: String
    public let entityType: String // "class", "struct", "enum", "interace", "func", "main", "primary_constructor", etc
    public let signature: String
    public let code: String
    public let summary: String
    public let filePath: String
    public let startLine: Int
    public let endLine: Int
    public let packageName: String
    public let parent: Option<CodeEntity> // TODO any way to refer to this rather than copy it

    public init (
        name: String, 
        entityType: String, 
        signature: String, 
        code: String, 
        summary: String, 
        filePath: String, 
        startLine: Int, 
        endLine: Int, 
        packageName: String, 
        parent: Option<CodeEntity>
    ) {
        this.name = name
        this.entityType = entityType
        this.signature = signature
        this.code = code
        this.summary = summary
        this.filePath = filePath
        this.startLine = startLine
        this.endLine = endLine
        this.packageName = packageName
        this.parent = parent
    }
}