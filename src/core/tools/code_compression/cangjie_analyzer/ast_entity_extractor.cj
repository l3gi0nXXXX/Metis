package metis.core.tools.code_compression.cangjie_analyzer

import std.collection.*
import std.fs.*
import std.ast.*

public class ASTEntityExtractor <: Visitor {
    private let entities: CodeEntities
    private let currentFile: String
    private let currentFileContentLines: Array<String>
    private var currentParent: ?CodeEntity
    private let packageName: String

    public init(
        filePath: String, 
        fileContent!: ?String = None, 
        packageName!: ?String = None,
        currentParent!: ?CodeEntity = None
    ) {
        this.entities = CodeEntities()
        this.currentFile = filePath
        this.currentParent = currentParent
        let currentFileContent = fileContent.getOrDefault { => "" }
        this.currentFileContentLines = currentFileContent.split("\n")
        this.packageName = packageName.getOrDefault { => "" }
    }

    public init(
        filePath: Path,
        fileContent!: ?String = None, 
        packageName!: ?String = None,
        currentParent!: ?CodeEntity = None
    ) {
        this(
            filePath.toString(),
            fileContent: fileContent,
            packageName: packageName,
            currentParent: currentParent
        )
    }

    public func getEntities(): CodeEntities {
        entities
    }

    override public func visit(decl: ClassDecl) {
        visitDecl(decl)
    }

    override public func visit(decl: StructDecl) {
        visitDecl(decl)
    }

    override public func visit(decl: EnumDecl) {
        visitDecl(decl)
    }

    override public func visit(decl: InterfaceDecl) {
        visitDecl(decl)
    }

    override public func visit(decl: FuncDecl) {
        visitDecl(decl)
    }
    
    override public func visit(decl: MainDecl) {
        visitDecl(decl)
    }

    override public func visit(decl: PrimaryCtorDecl) {
        visitDecl(decl)
    }

    override public func visit(decl: PropDecl) {
        visitDecl(decl)
    }

    private func visitDecl(decl: Decl) {
        var entityType: String
        var subDecls: ?ArrayList<Decl> = None
        match (decl) {
            case classDecl: ClassDecl => 
                entityType = "class"
                subDecls = classDecl.body.decls
            case structDecl: StructDecl => 
                entityType = "struct"
                subDecls = structDecl.body.decls
            case enumDecl: EnumDecl => 
                entityType = "enum"
                subDecls = enumDecl.decls
            case interfaceDecl: InterfaceDecl => 
                entityType = "interface"
                subDecls = interfaceDecl.body.decls
            case funcDecl: FuncDecl => 
                entityType = "func"
            case mainDecl: MainDecl => 
                entityType = "main"
            case primaryCtorDecl: PrimaryCtorDecl => 
                entityType = "primary_constructor"
            case propDecl: PropDecl => 
                entityType = "prop"
            case _ => 
                // Not handled
                println("Not handled")
                breakTraverse()
                return
        }
        let name = decl.identifier.value
        let signature = SignatureExtractor.extractSignature(decl)
        let startLine = Int64(decl.beginPos.line)
        let endLine = Int64(decl.endPos.line)

        /* Cangjie has bug that it treats get() and set() in a property as a function, but thinks the start line and end line are both 0.
         * We currently igore get() and set() in property. We will treat the property declaration (PropDecl) separately in the future.
         */
        if (startLine == 0) {
            breakTraverse()
            return
        }
        let code = String.join(this.currentFileContentLines[startLine - 1..endLine], delimiter: "\n") // TODO: there is a bug, index out of bounds
        let summary = "placeholder"
        let codeEntity = CodeEntity(
            name,
            entityType,
            signature,
            code,
            summary,
            currentFile,
            startLine,
            endLine,
            packageName,
            currentParent
        )
        entities.addEntity(codeEntity)
        if (subDecls.isNone() || subDecls.getOrThrow().size == 0) {
            breakTraverse()
            return
        }
        let oldParent = currentParent
        currentParent = codeEntity
        for (d in subDecls.getOrThrow()) {
            d.traverse(this)
        }
        currentParent = oldParent
        breakTraverse()
        return
    }
}