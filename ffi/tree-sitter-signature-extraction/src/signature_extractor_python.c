#include "signature_extractor.h"
#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Helper function to get the signature of a Python function
char* get_python_function_signature(TSNode node, const char* source_code) {
    TSNode name = ts_node_child_by_field_name(node, "name", 4);
    TSNode parameters = ts_node_child_by_field_name(node, "parameters", 10);
    TSNode type = ts_node_child_by_field_name(node, "return_type", 11);
    
    // Build signature string
    char* signature = NULL;
    size_t sig_len = 0;
    size_t sig_cap = 32; // Initial capacity
    signature = malloc(sig_cap);
    if (!signature) return NULL;
    signature[0] = '\0';
    
    strcpy(signature, "def");
    sig_len = 3;
    
    // Add function name
    char* name_text = get_node_text(name, source_code);
    if (name_text) {
        size_t name_len = strlen(name_text) + 1;
        // Ensure enough capacity
        while (sig_len + name_len + 1 > sig_cap) {
            sig_cap *= 2;
            signature = realloc(signature, sig_cap);
            if (!signature) {
                free(name_text);
                return NULL;
            }
        }
        strcat(signature, " ");
        strcat(signature, name_text);
        sig_len += name_len;
        free(name_text);
    }
    
    // Add parameters
    if (!ts_node_is_null(parameters)) {
        char* params_text = get_node_text(parameters, source_code);
        if (params_text) {
            size_t params_len = strlen(params_text);
            // Ensure enough capacity
            while (sig_len + params_len + 1 > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(params_text);
                    return NULL;
                }
            }
            strcat(signature, params_text);
            sig_len += params_len;
            free(params_text);
        }
    }

    // Add return type if present
    if (!ts_node_is_null(type)) {
        char* type_text = get_node_text(type, source_code);
        if (type_text) {
            size_t type_len = strlen(type_text) + 4;
            // Ensure enough capacity
            while (sig_len + type_len + 5 > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(type_text);
                    return NULL;
                }
            }
            strcat(signature, " -> ");
            strcat(signature, type_text);
            sig_len += type_len;
            free(type_text);
        }
    }
    
    // Add colon
    // Ensure enough capacity
    while (sig_len + 2 > sig_cap) {
        sig_cap *= 2;
        signature = realloc(signature, sig_cap);
        if (!signature) return NULL;
    }
    strcat(signature, ":");
    sig_len += 1;
    
    if (sig_len == 0) {
        free(signature);
        return get_node_text(node, source_code);
    }
    
    return signature;
}

// Helper function to get the signature of a Python class
char* get_python_class_signature(TSNode node, const char* source_code) {
    TSNode name = ts_node_child_by_field_name(node, "name", 4);
    TSNode superclasses = ts_node_child_by_field_name(node, "superclasses", 12);
    // TSNode type_parameters = ts_node_child_by_field_name(node, "type_parameters", 15);
    
    // Build signature string
    char* signature = NULL;
    size_t sig_len = 0;
    size_t sig_cap = 32; // Initial capacity
    signature = malloc(sig_cap);
    if (!signature) return NULL;
    signature[0] = '\0';
    
    strcpy(signature, "class");
    sig_len = 5;
    
    // Add class name
    char* name_text = get_node_text(name, source_code);
    if (name_text) {
        size_t name_len = strlen(name_text) + 1;
        // Ensure enough capacity
        while (sig_len + name_len + 1 > sig_cap) {
            sig_cap *= 2;
            signature = realloc(signature, sig_cap);
            if (!signature) {
                free(name_text);
                return NULL;
            }
        }
        strcat(signature, " ");
        strcat(signature, name_text);
        sig_len += name_len;
        free(name_text);
    }
    
    // Add superclasses if present
    if (!ts_node_is_null(superclasses)) {
        char* super_text = get_node_text(superclasses, source_code);
        if (super_text) {
            size_t super_len = strlen(super_text);
            // Ensure enough capacity
            while (sig_len + super_len + 1 > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(super_text);
                    return NULL;
                }
            }
            strcat(signature, super_text);
            sig_len += super_len;
            free(super_text);
        }
    }
    
    // Add colon
    // Ensure enough capacity
    while (sig_len + 2 > sig_cap) {
        sig_cap *= 2;
        signature = realloc(signature, sig_cap);
        if (!signature) return NULL;
    }
    strcat(signature, ":");
    sig_len += 1;
    
    if (sig_len == 0) {
        free(signature);
        return get_node_text(node, source_code);
    }
    
    return signature;
}


// Process a Python class definition
signature_node_t* process_python_class(TSNode node, const char* source_code) {
    TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
    if (ts_node_is_null(name_node)) {
        return NULL;
    }
    
    char* name = get_node_text(name_node, source_code);
    char* signature = get_python_class_signature(node, source_code);
    
    TSPoint start_point = ts_node_start_point(node);
    TSPoint end_point = ts_node_end_point(node);
    
    signature_node_t* sig_node = create_signature_node(
        ENTITY_CLASS, name, signature,
        start_point.row + 1, start_point.column + 1,
        end_point.row + 1, end_point.column + 1
    );
    
    if (name) free(name);
    if (signature) free(signature);
    
    return sig_node;
}

// Process a Python function definition
signature_node_t* process_python_function(TSNode node, const char* source_code) {
    TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
    if (ts_node_is_null(name_node)) {
        return NULL;
    }
    
    char* name = get_node_text(name_node, source_code);
    char* signature = get_python_function_signature(node, source_code);
    
    TSPoint start_point = ts_node_start_point(node);
    TSPoint end_point = ts_node_end_point(node);
    
    // Check if it's a main function (__main__ check would be at module level)
    entity_type_t type = ENTITY_FUNCTION;
    
    signature_node_t* sig_node = create_signature_node(
        type, name, signature,
        start_point.row + 1, start_point.column + 1,
        end_point.row + 1, end_point.column + 1
    );
    
    if (name) free(name);
    if (signature) free(signature);
    
    return sig_node;
}
