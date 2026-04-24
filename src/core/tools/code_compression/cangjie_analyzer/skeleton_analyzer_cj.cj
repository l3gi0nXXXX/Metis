package metis.core.tools.code_compression.cangjie_analyzer

import magic.log.LogUtils
import magic.utils.readFile

import std.ast.*
import std.collection.*
import std.fs.*
import std.io.*
import std.posix.*
import std.regex.*

public class SignatureNode <: ToString {
    public let signature: String
    public let startLine: Int
    public let endLine: Int
    public let children: ArrayList<SignatureNode>

    public init(signature: String, startLine: Int, endLine: Int, children: ArrayList<SignatureNode>) {
        this.signature = signature
        this.startLine = startLine
        this.endLine = endLine
        this.children = children
    }

    public func addChild(child: SignatureNode) {
        children.add(child)
    }

    override public func toString(): String {
        return signature
    }
}

protected class SkeletonAnalyzerCJ {
    
    protected static func analyzeFile(filePath: Path, startLine!: Int = 1, endLine!: Int = Int.Max): String { 
        var stringOutput = ""
        try {
            let content = readFile(filePath)
            let program = parseFile(content)
            let packageName = getFullPackageName(program)
            let newEntities = CodeEntities()
            
            for (decl in program.decls) {
                let extractor = ASTEntityExtractor(filePath, fileContent: content, packageName: packageName)
                decl.traverse(extractor)
                let entities = extractor.getEntities()
                for (entity in entities) {
                    if (entity.endLine >= startLine && entity.startLine <= endLine) {
                        newEntities.addEntity(entity)
                    }
                }
            }
            stringOutput += getSkeletonXml(buildSkeletonTree(newEntities), 0, filePath.toString())
        } catch (e: Exception) {
            LogUtils.error("Error analyzing ${filePath}: ${e.toString()}")
        }
        return stringOutput
    }

    protected static func analyzeFile(filePath: String, startLine!: Int = 1, endLine!: Int = Int.Max): String { 
        analyzeFile(Path(filePath), startLine: startLine, endLine: endLine)
    }

    private static func buildSkeletonTree(entities: CodeEntities): SignatureNode {
        let hashMap = HashMap<String, SignatureNode>()
        for (entity in entities) {
            let signature = entity.signature
            hashMap.add(signature, SignatureNode(signature, entity.startLine, entity.endLine, ArrayList<SignatureNode>()))
        }
        let dummyRoot = SignatureNode("", -1, -1, ArrayList<SignatureNode>())
        for (entity in entities) {
            let signature = entity.signature
            if (entity.parent.isNone() || !hashMap.contains(entity.parent.getOrThrow().signature)) {
                let root = hashMap.get(signature).getOrThrow()
                dummyRoot.addChild(root)
            } else { 
                let parentSignature = entity.parent.getOrThrow().signature
                hashMap.get(parentSignature).getOrThrow().addChild(hashMap.get(signature).getOrThrow())
            }
        }
        return dummyRoot
    }

    private static func getSkeletonXml(signatureNode: SignatureNode, indentLevel: Int, filePath: String): String {
        let signature = signatureNode.signature
        let startLine = signatureNode.startLine
        let endLine = signatureNode.endLine
        let children = signatureNode.children

        let childrenXml = if (children.size == 0) {
            ""
        } else if (startLine == -1) {
            let rawChildrenXml = String.join(children |> map {child: SignatureNode => getSkeletonXml(child, indentLevel + 1, filePath)} |> collectArray, delimiter: "\n")
"""
${rawChildrenXml}
"""

        } else {
            let rawChildrenXml = String.join(children |> map {child: SignatureNode => getSkeletonXml(child, indentLevel + 2, filePath)} |> collectArray, delimiter: "\n")
"""
${" " * (indentLevel + 1) * 4}<member>
${rawChildrenXml}
${" " * (indentLevel + 1) * 4}</member>
"""
        }
        
        if (startLine == -1) {
            return """
<code-skeleton path="${filePath}">
${childrenXml}</code-skeleton>"""
        }


"""
${" " * indentLevel * 4}<code-entity start=${startLine} end=${endLine}>
${" " * (indentLevel + 1) * 4}<signature>${signature}</signature>
${childrenXml}${" " * indentLevel * 4}</code-entity>"""
    }
}