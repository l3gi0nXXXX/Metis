#ifndef SIGNATURE_NODE_H
#define SIGNATURE_NODE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "dll_export.h"

#ifdef __cplusplus
extern "C" {
#endif

// Types of code entities we're interested in
typedef enum {
    ENTITY_CLASS,
    ENTITY_STRUCT,
    ENTITY_ENUM,
    ENTITY_INTERFACE,
    ENTITY_FUNCTION,
    ENTITY_MAIN_FUNCTION,
    ENTITY_PRIMARY_CONSTRUCTOR,
    ENTITY_PROPERTY,
    ENTITY_UNKNOWN
} entity_type_t;

// Structure to represent a parsing error
typedef struct {
    int line;
    char* message;
    char* error_line;
    char* code_above_error_line;
    char* code_below_error_line;
} parse_error_t;

// Forward declaration
typedef struct signature_node signature_node_t;

// Node structure to represent a code entity signature in a tree structure
typedef struct signature_node {
    entity_type_t type;              // Type of the entity
    char* name;                      // Name of the entity
    char* signature;                 // Full signature of the entity
    int start_line;                  // Starting line number
    int start_column;                // Starting column number
    int end_line;                    // Ending line number
    int end_column;                  // Ending column number
    signature_node_t* parent;        // Pointer to parent node
    signature_node_t* children;      // Pointer to first child node
    signature_node_t* next_sibling;  // Pointer to next sibling node
} signature_node_t;

/**
 * Create a new signature node
 * @param type Entity type
 * @param name Entity name
 * @param signature Full signature
 * @param start_line Starting line number
 * @param start_column Starting column number
 * @param end_line Ending line number
 * @param end_column Ending column number
 * @return Pointer to the new signature node
 */
DLL_EXPORT signature_node_t* create_signature_node(entity_type_t type, const char* name, 
                                       const char* signature, int start_line, 
                                       int start_column, int end_line, int end_column);

/**
 * Free a signature node and all its descendants
 * @param node Node to free
 */
DLL_EXPORT void free_signature_node(signature_node_t* node);

/**
 * Add a child node to a parent node
 * @param parent Parent node
 * @param child Child node to add
 */
DLL_EXPORT void add_child_signature_node(signature_node_t* parent, signature_node_t* child);

/**
 * Convert entity type to string
 * @param type Entity type
 * @return String representation of the type
 */
DLL_EXPORT const char* entity_type_to_string(entity_type_t type);

/**
 * Print a signature node
 * @param node Node to print
 * @param indent Indentation level for tree printing
 */
DLL_EXPORT void print_signature_node(signature_node_t* node, int indent);

/**
 * Print an entire tree of signature nodes
 * @param root Root of the tree
 */
DLL_EXPORT void print_signature_tree(signature_node_t* root);

#ifdef __cplusplus
}
#endif

#endif // SIGNATURE_NODE_H