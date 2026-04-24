#ifndef SIGNATURE_EXTRACTOR_H
#define SIGNATURE_EXTRACTOR_H

#include "signature_node.h"
#include "tree_sitter/api.h"
#include "dll_export.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Extract signatures from a Tree-sitter AST
 * @param tree Tree-sitter tree
 * @param source_code Source code text
 * @param language Language of the source code ("java" or "python")
 * @return Linked list of signature nodes
 */
DLL_EXPORT signature_node_t* extract_signatures(TSTree* tree, const char* source_code, const char* language);
DLL_EXPORT signature_node_t* extract_signatures_from_file(const char *filename, const char *language);
DLL_EXPORT char* get_skeleton_xml(const char *filename, const char *language);
DLL_EXPORT char* get_skeleton_xml_range(const char *filename, const char *language, int start_line, int end_line);
DLL_EXPORT char* get_skeleton_xml_with_errors(const char *filename, const char *language, int start_line, int end_line);

// Java processing functions
DLL_EXPORT signature_node_t* process_java_class(TSNode node, const char* source_code);
DLL_EXPORT signature_node_t* process_java_method(TSNode node, const char* source_code);
DLL_EXPORT signature_node_t* process_java_interface(TSNode node, const char* source_code);
DLL_EXPORT signature_node_t* process_java_enum(TSNode node, const char* source_code);

// Python processing functions
DLL_EXPORT signature_node_t* process_python_class(TSNode node, const char* source_code);
DLL_EXPORT signature_node_t* process_python_function(TSNode node, const char* source_code);

// Helper functions for getting signatures
char* get_java_method_signature(TSNode node, const char* source_code);
char* get_java_class_signature(TSNode node, const char* source_code);
char* get_python_function_signature(TSNode node, const char* source_code);
char* get_python_class_signature(TSNode node, const char* source_code);

DLL_EXPORT TSLanguage* tree_sitter_python(void);
DLL_EXPORT TSLanguage* tree_sitter_java(void);

// Helper function for cloning signature nodes
signature_node_t* clone_signature_node(signature_node_t* node);
signature_node_t* clone_signature_node_with_range(signature_node_t* node, int start_line, int end_line);

// Helper functions for XML generation
size_t calculate_node_size_recursive(signature_node_t* node);
int print_node_recursive(char* buffer, size_t buffer_size, signature_node_t* node, int offset, int indent_level);
int print_error_node_recursive(char* buffer, size_t buffer_size, const char* source_code, TSTree* tree, int offset);

// Error handling functions
parse_error_t* extract_parse_errors(TSTree* tree, const char* source_code, int* error_count);
void free_parse_errors(parse_error_t* errors, int error_count);

// Error context functions
void get_error_context(const char* source_code, int error_line_number, 
                      char** error_line, char** above_lines, char** below_lines);
void get_error_context_ext(const char* source_code, int error_line_number, int context_lines,
                          char** error_line, char** above_lines, char** below_lines);

#ifdef __cplusplus
}
#endif

#endif // SIGNATURE_EXTRACTOR_H