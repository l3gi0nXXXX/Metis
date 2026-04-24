"""
Cangjie code element extraction using regex patterns.
"""
import re
from typing import List, Tuple
from .models import Chunk, CodeElement, Reference, ElementType, ReferenceType


class CangjiePatterns:
    """Regex patterns for parsing Cangjie language constructs."""
    
    # Function definitions: func foo(a: Int64, b: String): String
    FUNCTION_DEF = re.compile(
        r'func\s+(\w+)\s*\(([^)]*)\)(?:\s*:\s*([^{\n]+))?',
        re.MULTILINE
    )
    
    # Type definitions - more flexible patterns
    # class A, class A extends B, class A {, class A extends B {
    CLASS_DEF = re.compile(r'class\s+(\w+)(?:\s+extends\s+(\w+))?(?:\s*\{|\s*$|\s+)', re.MULTILINE)
    # struct A, struct A {
    STRUCT_DEF = re.compile(r'struct\s+(\w+)(?:\s*\{|\s*$|\s+)', re.MULTILINE)
    # interface A, interface A {
    INTERFACE_DEF = re.compile(r'interface\s+(\w+)(?:\s*\{|\s*$|\s+)', re.MULTILINE)
    # enum A, enum A {
    ENUM_DEF = re.compile(r'enum\s+(\w+)(?:\s*\{|\s*$|\s+)', re.MULTILINE)
    
    # Function calls: obj.method(...) or function(...)
    METHOD_CALL = re.compile(r'(\w+)\.(\w+)\s*\(', re.MULTILINE)
    FUNCTION_CALL = re.compile(r'(?<![\w.])\b([a-zA-Z_]\w*)\s*\(', re.MULTILINE)


class CangjieCodeElementExtractor:
    """Extract code elements from Cangjie documentation chunks."""
    
    def __init__(self):
        self.patterns = CangjiePatterns()
    
    def extract_elements(self, chunk: Chunk) -> List[CodeElement]:
        """Extract all code elements from a chunk."""
        elements = []
        
        # Extract function definitions
        elements.extend(self._extract_function_definitions(chunk))
        
        # Extract type definitions
        elements.extend(self._extract_type_definitions(chunk))
        
        return elements
    
    def extract_references(self, chunk: Chunk) -> List[Reference]:
        """Extract function calls and references from a chunk."""
        references = []
        
        # Extract method calls (obj.method())
        references.extend(self._extract_method_calls(chunk))
        
        # Extract function calls (function())
        references.extend(self._extract_function_calls(chunk))
        
        # Extract type references from function signatures
        references.extend(self._extract_type_references(chunk))
        
        return references
    
    def _extract_function_definitions(self, chunk: Chunk) -> List[CodeElement]:
        """Extract function definitions from chunk content."""
        elements = []
        
        for match in self.patterns.FUNCTION_DEF.finditer(chunk.content):
            name = match.group(1)
            params = match.group(2) if match.group(2) else ""
            return_type = match.group(3) if match.group(3) else ""
            
            # Build function signature
            signature = f"func {name}({params})"
            if return_type:
                signature += f": {return_type.strip()}"
            
            # Calculate line number
            line_number = chunk.content[:match.start()].count('\n') + chunk.start_line
            
            elements.append(CodeElement(
                name=name,
                element_type=ElementType.FUNCTION,
                signature=signature,
                source_chunk=chunk.id,
                line_number=line_number
            ))
        
        return elements
    
    def _extract_type_definitions(self, chunk: Chunk) -> List[CodeElement]:
        """Extract type definitions (class, struct, interface, enum) from chunk."""
        elements = []
        
        # Define patterns and their corresponding element types
        type_patterns = [
            (self.patterns.CLASS_DEF, ElementType.CLASS),
            (self.patterns.STRUCT_DEF, ElementType.STRUCT),
            (self.patterns.INTERFACE_DEF, ElementType.INTERFACE),
            (self.patterns.ENUM_DEF, ElementType.ENUM)
        ]
        
        for pattern, element_type in type_patterns:
            for match in pattern.finditer(chunk.content):
                name = match.group(1)
                line_number = chunk.content[:match.start()].count('\n') + chunk.start_line
                
                # For classes, include inheritance info in signature
                if element_type == ElementType.CLASS and match.lastindex >= 2 and match.group(2):
                    signature = f"class {name} extends {match.group(2)}"
                else:
                    signature = f"{element_type.value} {name}"
                
                elements.append(CodeElement(
                    name=name,
                    element_type=element_type,
                    signature=signature,
                    source_chunk=chunk.id,
                    line_number=line_number
                ))
        
        return elements
    
    def _extract_method_calls(self, chunk: Chunk) -> List[Reference]:
        """Extract method calls (obj.method()) from chunk content."""
        references = []
        
        for match in self.patterns.METHOD_CALL.finditer(chunk.content):
            receiver = match.group(1)
            method_name = match.group(2)
            
            # Skip common non-method patterns
            if self._is_likely_method_call(receiver, method_name):
                references.append(Reference(
                    source_chunk=chunk.id,
                    target_element=method_name,
                    reference_type=ReferenceType.CALLS,
                    receiver=receiver,
                    confidence=0.8
                ))
        
        return references
    
    def _extract_function_calls(self, chunk: Chunk) -> List[Reference]:
        """Extract function calls (function()) from chunk content."""
        references = []
        
        for match in self.patterns.FUNCTION_CALL.finditer(chunk.content):
            function_name = match.group(1)
            
            # Filter out common keywords and patterns that aren't function calls
            if self._is_likely_function_call(function_name, chunk.content, match):
                references.append(Reference(
                    source_chunk=chunk.id,
                    target_element=function_name,
                    reference_type=ReferenceType.CALLS,
                    confidence=0.7
                ))
        
        return references
    
    def _is_likely_method_call(self, receiver: str, method_name: str) -> bool:
        """Check if a pattern is likely a method call."""
        # Skip common false positives
        false_positives = {
            'if', 'for', 'while', 'switch', 'catch', 'try'
        }
        
        return (method_name not in false_positives and 
                len(method_name) > 1 and 
                receiver.isidentifier())
    
    def _is_likely_function_call(self, function_name: str, content: str, match: re.Match) -> bool:
        """Check if a pattern is likely a function call."""
        # Skip keywords and common false positives
        keywords = {
            'if', 'for', 'while', 'switch', 'case', 'catch', 'try',
            'func', 'class', 'struct', 'interface', 'enum', 'var', 'let'
        }
        
        if function_name in keywords or len(function_name) <= 1:
            return False
        
        # Check if preceded by 'func' keyword (function definition)
        before_match = content[:match.start()]
        if re.search(r'\bfunc\s*$', before_match):
            return False
        
        # Check if it's a type annotation (after :)
        if re.search(r':\s*[^:]*$', before_match):
            return False
        
        return True
    
    def _extract_type_references(self, chunk: Chunk) -> List[Reference]:
        """Extract type references from function parameters and return types."""
        references = []
        
        # Pattern to match function signatures with parameters and return types
        # func name(param1: Type1, param2: Type2): ReturnType
        func_sig_pattern = re.compile(
            r'func\s+(\w+)\s*\(([^)]*)\)(?:\s*:\s*([^{\n]+))?',
            re.MULTILINE
        )
        
        for match in func_sig_pattern.finditer(chunk.content):
            func_name = match.group(1)
            params = match.group(2) if match.group(2) else ""
            return_type = match.group(3) if match.group(3) else ""
            
            # Extract parameter types
            if params.strip():
                param_types = self._parse_parameter_types(params)
                for param_type in param_types:
                    if self._is_custom_type(param_type):
                        references.append(Reference(
                            source_chunk=chunk.id,
                            target_element=param_type,
                            reference_type=ReferenceType.TYPE_REFERENCE,
                            receiver=func_name,  # Function that uses this type
                            confidence=0.9
                        ))
            
            # Extract return type
            if return_type.strip():
                return_type_cleaned = self._clean_type_name(return_type.strip())
                if return_type_cleaned and self._is_custom_type(return_type_cleaned):
                    references.append(Reference(
                        source_chunk=chunk.id,
                        target_element=return_type_cleaned,
                        reference_type=ReferenceType.TYPE_REFERENCE,
                        receiver=func_name,  # Function that returns this type
                        confidence=0.9
                    ))
        
        return references
    
    def _parse_parameter_types(self, params_str: str) -> List[str]:
        """Parse parameter types from function parameter string."""
        types = []
        
        # Split by comma but be careful of nested generics like Array<String>
        param_parts = []
        current_param = ""
        bracket_count = 0
        
        for char in params_str:
            if char == '<':
                bracket_count += 1
            elif char == '>':
                bracket_count -= 1
            elif char == ',' and bracket_count == 0:
                param_parts.append(current_param.strip())
                current_param = ""
                continue
            current_param += char
        
        if current_param.strip():
            param_parts.append(current_param.strip())
        
        # Extract type from each parameter (format: name: Type or name!: Type = default)
        type_pattern = re.compile(r'\w+!?\s*:\s*([^=]+)(?:\s*=.*)?')
        
        for param in param_parts:
            match = type_pattern.match(param.strip())
            if match:
                type_str = match.group(1).strip()
                base_type = self._extract_base_type(type_str)
                if base_type:
                    types.append(base_type)
        
        return types
    
    def _extract_base_type(self, type_str: str) -> str:
        """Extract base type name from complex type like Array<String> -> Array."""
        # Remove generic parameters for now, keep base type
        base_match = re.match(r'(\w+)', type_str.strip())
        if base_match:
            return base_match.group(1)
        return ""
    
    def _clean_type_name(self, type_str: str) -> str:
        """Clean type name from return type string."""
        # Remove leading/trailing whitespace and extract main type
        cleaned = type_str.strip()
        # Handle generic types like Array<String> -> Array  
        base_match = re.match(r'(\w+)', cleaned)
        if base_match:
            return base_match.group(1)
        return ""
    
    def _is_custom_type(self, type_name: str) -> bool:
        """Check if a type is likely a custom/user-defined type."""
        # Filter out primitive types
        primitive_types = {
            'Int8', 'Int16', 'Int32', 'Int64', 'IntNative',
            'UInt8', 'UInt16', 'UInt32', 'UInt64', 'UIntNative', 
            'Float16', 'Float32', 'Float64',
            'String', 'Rune', 'Bool', 'Unit', 'Byte',
            'Array', 'ArrayList', 'HashMap', 'HashSet',
            'Option', 'Result', 'Iterator'
        }
        
        # Consider it custom if:
        # 1. Not a primitive type
        # 2. Starts with uppercase (Cangjie naming convention)
        # 3. Length > 1
        return (type_name not in primitive_types and 
                len(type_name) > 1 and 
                type_name[0].isupper() and
                type_name.isalpha())  # Only alphabetic characters
    
    def get_code_element_names(self, chunk: Chunk) -> List[str]:
        """Get a list of all unique code element names in a chunk."""
        elements = self.extract_elements(chunk)
        # Use set to remove duplicates, then convert back to list
        unique_names = list(set(element.name for element in elements))
        return sorted(unique_names)  # Sort for consistent output