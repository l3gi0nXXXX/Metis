package metis.core.tools.code_compression.cangjie_analyzer

import std.collection.*
import std.ast.*

protected class SignatureExtractor {
    protected static func extractSignature(decl: Decl): String {
        match (decl) {
            case classDecl: ClassDecl => buildClassSignature(classDecl)
            case structDecl: StructDecl => buildStructSignature(structDecl)
            case enumDecl: EnumDecl => buildEnumSignature(enumDecl)
            case interfaceDecl: InterfaceDecl => buildInterfaceSignature(interfaceDecl)
            case funcDecl: FuncDecl => buildFuncSignature(funcDecl)
            case mainDecl: MainDecl => buildMainSignature(mainDecl)
            case primaryCtorDecl: PrimaryCtorDecl => buildCtorSignature(primaryCtorDecl)
            case propDecl: PropDecl => buildPropSignature(propDecl)
            case _ => ""
        }
    }

    private static func extractParamType(paramType: TypeNode): String {
        match (paramType) {
            case funcType: FuncType => 
                let inputs = funcType.types |> map {t: TypeNode => extractParamType(t)} |> collectArray
                let inputStr = String.join(inputs, delimiter: ", ")
                "(${inputStr}) -> ${extractParamType(funcType.returnType)}"
            case parenType: ParenType => "(${extractParamType(parenType.parenthesizedType)})"
            case prefixType: PrefixType => "?${extractParamType(prefixType.baseType)}"
            case primType: PrimitiveType => primType.keyword.value
            case qType: QualifiedType => "${extractParamType(qType.baseType)}.${qType.identifier.value}}"
            case refType: RefType => 
                let generics = refType.typeArguments |> map {t: TypeNode => extractParamType(t)} |> collectArray
                let genericsString = if (generics.size > 0) {"<${String.join(generics, delimiter: ", ")}>"} else {""}
                refType.identifier.value + genericsString
            case thisType: ThisType => thisType.keyword.value 
            case tupleType: TupleType => 
                let inputs = tupleType.types |> map {t: TypeNode => extractParamType(t)} |> collectArray
                let inputStr = String.join(inputs, delimiter: ", ")
                "(${inputStr})"
            case vType: VArrayType => "VArray<${extractParamType(vType.elementTy)}, ${vType.size.value}>"
            case _ => "Unknown"
        }
    }

    private static func extractModifiers(decl: Decl): String {
        if (decl.modifiers.isEmpty()) {
            return ""
        }
        let modifierStrs = ArrayList<String>()
        for (modifier in decl.modifiers) { 
            modifierStrs.add(modifier.keyword.value)
        }
        let strArray = modifierStrs |> collectArray
        String.join(strArray, delimiter: " ") + " "
    }

    private static func extractFuncParams(funcParams: ArrayList<FuncParam>): String {
        var params: ArrayList<String> = ArrayList<String>()
        for (param in funcParams) {
            let paramName = param.identifier.value
            let paramType = extractParamType(param.paramType)
            var defaultValue: String
            try {
                defaultValue = " = ${param.expr.toTokens().toString()}"
            } catch(e: ASTException) {
                defaultValue = ""
            }
            var notSign: String
            try {
                notSign = param.not.value
            } catch(e: ASTException) {
                notSign = ""
            }
            params.add("${paramName}${notSign}: ${paramType}${defaultValue}")
        }
        let paramsArray = params |> collectArray
        let paramStr = String.join(paramsArray, delimiter: ", ")
        return paramStr
    }

    private static func extractGenericConstraints(decl: Decl): String {
        if (decl.genericConstraint.isEmpty()) {
            return ""
        }
        let gcStr: ArrayList<String> = ArrayList()
        for (gc in decl.genericConstraint) {
            gcStr.add(gc.toTokens().toString())
        }
        return " " + String.join(gcStr |> collectArray, delimiter: ", ")
        
    }

    private static func extractParentEntities(parentEntities: ArrayList<TypeNode>): String {
        if (parentEntities.size == 0) {
            return ""
        }
        
        var parentNames: ArrayList<String> = ArrayList<String>()
        for (parentType in parentEntities) {
            let parentName = extractParamType(parentType)
            parentNames.add(parentName)
        }
        
        let parentNamesArray = parentNames |> collectArray
        " <: " + String.join(parentNamesArray, delimiter: " & ")
    }
    
    private static func extractGenericParam(decl: Decl): String {
        var genericParamStr: String
        try {
            let genericParam = decl.genericParam.parameters |> map {t: Token => t.value} |> collectArray
            genericParamStr = "<${String.join(genericParam, delimiter: ", ")}>"
        } catch(error: ASTException) {
            genericParamStr = ""
        }
        return genericParamStr

    }

    private static func buildClassSignature(classDecl: ClassDecl): String {
        let genericParam = extractGenericParam(classDecl)
        let genericConstraint = extractGenericConstraints(classDecl)
        let parentEntities = extractParentEntities(classDecl.superTypes)
        let modifiers = extractModifiers(classDecl)
        let name = classDecl.identifier.value
        "${modifiers}class ${name}${genericParam}${parentEntities}${genericConstraint}"
    }

    private static func buildStructSignature(structDecl: StructDecl): String {
        let genericParam = extractGenericParam(structDecl)
        let genericConstraint = extractGenericConstraints(structDecl)
        let parentEntities = extractParentEntities(structDecl.superTypes)
        let modifiers = extractModifiers(structDecl)
        let name = structDecl.identifier.value
        "${modifiers}struct ${name}${genericParam}${parentEntities}${genericConstraint}"
    }

    private static func buildInterfaceSignature(interfaceDecl: InterfaceDecl): String {
        let genericParam = extractGenericParam(interfaceDecl)
        let genericConstraint = extractGenericConstraints(interfaceDecl)
        let parentEntities = extractParentEntities(interfaceDecl.superTypes)
        let modifiers = extractModifiers(interfaceDecl)
        let name = interfaceDecl.identifier.value
        "${modifiers}interface ${name}${genericParam}${parentEntities}${genericConstraint}"
    }

    private static func buildEnumSignature(enumDecl: EnumDecl): String {
        let genericParam = extractGenericParam(enumDecl)
        let genericConstraint = extractGenericConstraints(enumDecl)
        let parentEntities = extractParentEntities(enumDecl.superTypes)
        let modifiers = extractModifiers(enumDecl)
        let name = enumDecl.identifier.value
        "${modifiers}enum ${name}${genericParam}${parentEntities}${genericConstraint}"
    }

    private static func buildMainSignature(mainDecl: MainDecl): String { 
        let modifiers = extractModifiers(mainDecl)
        let paramStr = extractFuncParams(mainDecl.funcParams)
        var returnType: String
        try {
            returnType = extractParamType(mainDecl.declType)
        } catch (e: ASTException) {
            returnType = ""
        }
        if (!returnType.isEmpty()) {
            returnType = ": ${returnType}"
        }
        
        "${modifiers}main(${paramStr})${returnType}"
    }

    private static func buildCtorSignature(primaryCtorDecl: PrimaryCtorDecl): String {
        let modifiers = extractModifiers(primaryCtorDecl)
        let name = primaryCtorDecl.identifier.value
        let paramStr = extractFuncParams(primaryCtorDecl.funcParams)
        "${modifiers}${name}(${paramStr})"
    }


    private static func buildFuncSignature(funcDecl: FuncDecl): String {
        let genericParam = extractGenericParam(funcDecl)
        let genericConstraint = extractGenericConstraints(funcDecl)
        let name = funcDecl.identifier.value
        let modifiers = extractModifiers(funcDecl)
        let paramStr = extractFuncParams(funcDecl.funcParams)
        var returnType: String
        try {
            returnType = extractParamType(funcDecl.declType)
        } catch (e: ASTException) {
            returnType = ""
        }
        if (!returnType.isEmpty()) {
            returnType = ": ${returnType}"
        }
        
        if (name == 'init') {
            return "${modifiers}${name}${genericParam}(${paramStr})${genericConstraint}"
        }
        "${modifiers}func ${name}${genericParam}(${paramStr})${returnType}${genericConstraint}"
    }

    private static func buildPropSignature(propDecl: PropDecl): String {
        let modifiers = extractModifiers(propDecl)
        let name = propDecl.identifier.value
        let returnType = extractParamType(propDecl.declType)
        "${modifiers}prop ${name}: ${returnType}"
    }
}