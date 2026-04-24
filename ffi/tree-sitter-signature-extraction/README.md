# Tree-sitter Signature Extraction Library

A C library that uses Tree-sitter to extract code signatures and build code skeletons from source files. This library can parse Java and Python source code and extract structured information about classes, interfaces, methods, functions, and other code entities.

## Features

- Extract signatures from Java and Python source code
- Support for classes, interfaces, enums, methods, and functions
- Generate XML skeleton representation of code structure
- C FFI (Foreign Function Interface) compatible
- Line/column position information for each entity

## Supported Languages

1. Java:
   - Class declarations
   - Interface declarations
   - Enum declarations
   - Method declarations

2. Python:
   - Class definitions
   - Function definitions

## API

```c
signature_node_t* extract_signatures(TSTree* tree, const char* source_code, const char* language);
```
Extract signatures from a parsed Tree-sitter tree.

```c
signature_node_t* extract_signatures_from_file(const char *filename, const char *language);
```
Extract signatures directly from a source file.

```c
char* get_skeleton_xml(const char *filename, const char *language);
```
Generate an XML skeleton representation of the code structure.

```c
char* get_skeleton_xml_range(const char *filename, const char *language, int start_line, int end_line);
```
Generate an XML skeleton representation for a specific range of lines.

## Building

This library is typically built as part of the larger project. It requires Tree-sitter development libraries and headers.

Dependencies:
- Tree-sitter runtime
- Tree-sitter Java grammar (for Java support)
- Tree-sitter Python grammar (for Python support)

Download the soruce of the Tree-sitter runtime and grammars from the Tree-sitter repository (https://github.com/tree-sitter). Put the Tree-sitter runtime and grammars in the root directory. Your directory structure should look like this:
```
tree-sitter-signature-extraction
├── src
├── tree-sitter
├── tree-sitter-java
├── tree-sitter-python
└── MakeFile
```

Run `make` to build both the static and dynamic libraries.
