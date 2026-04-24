#include "signature_extractor.h"
#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Helper function to get the signature of a Java method
char* get_java_method_signature(TSNode node, const char* source_code) {
    // TSNode modifiers = ts_node_child_by_field_name(node, "modifiers", 9);
    TSNode type_parameters = ts_node_child_by_field_name(node, "type_parameters", 15);
    TSNode type = ts_node_child_by_field_name(node, "type", 4);
    TSNode name = ts_node_child_by_field_name(node, "name", 4);
    TSNode parameters = ts_node_child_by_field_name(node, "parameters", 10);
    TSNode throws = ts_node_child_by_field_name(node, "throws", 6);
    
    // Build signature string
    char* signature = NULL;
    size_t sig_len = 0;
    size_t sig_cap = 64; // Initial capacity
    signature = malloc(sig_cap);
    if (!signature) return NULL;
    signature[0] = '\0';
    
    // Add modifiers if present
    char* modifiers_text = get_modifiers_text(node, source_code);
    if (modifiers_text) {
        size_t modifiers_len = strlen(modifiers_text) + 1;
        // ensure enough capacity
        while (sig_len + modifiers_len + 1 > sig_cap) {
            sig_cap *= 2;
            signature = realloc(signature, sig_cap);
            if (!signature) {
                free(modifiers_text);
                return NULL;
            }
        }
        strcat(signature, modifiers_text);
        strcat(signature, " ");
        sig_len += modifiers_len;
        free(modifiers_text);
    }
    
    // Add type parameters if present (generics)
    if (!ts_node_is_null(type_parameters)) {
        char* type_params_text = get_node_text(type_parameters, source_code);
        if (type_params_text) {
            size_t type_params_len = strlen(type_params_text) + 1;
            // Ensure enough capacity
            while (sig_len + type_params_len > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(type_params_text);
                    return NULL;
                }
            }
            strcat(signature, type_params_text);
            strcat(signature, " ");
            sig_len += type_params_len;
            free(type_params_text);
        }
    }

    // Add return type if present
    if (!ts_node_is_null(type)) {
        char* type_text = get_node_text(type, source_code);
        if (type_text) {
            size_t type_len = strlen(type_text) + 1;
            // Ensure enough capacity
            while (sig_len + type_len + 1 > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(type_text);
                    return NULL;
                }
            }
            strcat(signature, type_text);
            strcat(signature, " ");
            sig_len += type_len;
            free(type_text);
        }
    } 
    
    // Add method name
    char* name_text = get_node_text(name, source_code);
    if (name_text) {
        size_t name_len = strlen(name_text);
        // Ensure enough capacity
        while (sig_len + name_len > sig_cap) {
            sig_cap *= 2;
            signature = realloc(signature, sig_cap);
            if (!signature) {
                free(name_text);
                return NULL;
            }
        }
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
            while (sig_len + params_len > sig_cap) {
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
    
    // Add throws clause if present
    if (!ts_node_is_null(throws)) {
        char* throws_text = get_node_text(throws, source_code);
        if (throws_text) {
            size_t throws_len = strlen(throws_text);
            // Ensure enough capacity
            while (sig_len + throws_len + 9 > sig_cap) { // +9 for " throws "
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(throws_text);
                    return NULL;
                }
            }
            strcat(signature, " throws ");
            strcat(signature, throws_text);
            sig_len += throws_len + 8;
            free(throws_text);
        }
    }
    
    if (sig_len == 0) {
        free(signature);
        return get_node_text(node, source_code);
    }
    
    return signature;
}

// Helper function to get the signature of a Java class
char* get_java_class_signature(TSNode node, const char* source_code) {
    TSNode modifiers = ts_node_child_by_field_name(node, "modifiers", 9);
    TSNode name = ts_node_child_by_field_name(node, "name", 4);
    TSNode type_parameters = ts_node_child_by_field_name(node, "type_parameters", 15);
    TSNode superclass = ts_node_child_by_field_name(node, "superclass", 10);
    TSNode interfaces = ts_node_child_by_field_name(node, "interfaces", 10);
    
    // Build signature string
    char* signature = NULL;
    size_t sig_len = 0;
    size_t sig_cap = 64; // Initial capacity
    signature = malloc(sig_cap);
    if (!signature) return NULL;
    signature[0] = '\0';

    // Add modifiers if present
    char* modifiers_text = get_modifiers_text(node, source_code);
    if (modifiers_text) {
        size_t modifiers_len = strlen(modifiers_text) + 1;
        // ensure enough capacity
        while (sig_len + modifiers_len + 1 > sig_cap) {
            sig_cap *= 2;
            signature = realloc(signature, sig_cap);
            if (!signature) {
                free(modifiers_text);
                return NULL;
            }
        }
        strcat(signature, modifiers_text);
        strcat(signature, " ");
        sig_len += modifiers_len;
        free(modifiers_text);
    }
    

    while (sig_len + 7 > sig_cap) {
        sig_cap *= 2;
        signature = realloc(signature, sig_cap);
        if (!signature) {
            return NULL;
        }
    }
    strcat(signature, "class ");
    sig_len += 5;
    
    // Add class name
    char* name_text = get_node_text(name, source_code);
    if (name_text) {
        size_t name_len = strlen(name_text);
        // Ensure enough capacity
        while (sig_len + name_len + 1 > sig_cap) {
            sig_cap *= 2;
            signature = realloc(signature, sig_cap);
            if (!signature) {
                free(name_text);
                return NULL;
            }
        }
        strcat(signature, name_text);
        sig_len += name_len;
        free(name_text);
    }
    
    // Add type parameters if present (generics)
    if (!ts_node_is_null(type_parameters)) {
        char* type_params_text = get_node_text(type_parameters, source_code);
        if (type_params_text) {
            size_t type_params_len = strlen(type_params_text);
            // Ensure enough capacity
            while (sig_len + type_params_len > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(type_params_text);
                    return NULL;
                }
            }
            strcat(signature, type_params_text);
            sig_len += type_params_len;
            free(type_params_text);
        }
    }
    
    // Add superclass if present
    if (!ts_node_is_null(superclass)) {
        char* super_text = get_node_text(superclass, source_code);
        if (super_text) {
            size_t super_len = strlen(super_text) + 1;
            // Ensure enough capacity
            while (sig_len + super_len + 1 > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(super_text);
                    return NULL;
                }
            }
            strcat(signature, " ");
            strcat(signature, super_text);
            sig_len += super_len;
            free(super_text);
        }
    }
    
    // Add interfaces if present
    if (!ts_node_is_null(interfaces)) {
        char* interfaces_text = get_node_text(interfaces, source_code);
        if (interfaces_text) {
            size_t interfaces_len = strlen(interfaces_text) + 1;
            // Ensure enough capacity
            while (sig_len + interfaces_len + 1 > sig_cap) {
                sig_cap *= 2;
                signature = realloc(signature, sig_cap);
                if (!signature) {
                    free(interfaces_text);
                    return NULL;
                }
            }
            strcat(signature, " ");
            strcat(signature, interfaces_text);
            sig_len += interfaces_len;
            free(interfaces_text);
        }
    }
    
    if (sig_len == 0) {
        free(signature);
        return get_node_text(node, source_code);
    }
    
    return signature;
}


// Process a Java class declaration
signature_node_t* process_java_class(TSNode node, const char* source_code) {
    TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
    if (ts_node_is_null(name_node)) {
        return NULL;
    }
    
    char* name = get_node_text(name_node, source_code);
    char* signature = get_java_class_signature(node, source_code);
    
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

// Process a Java method declaration
signature_node_t* process_java_method(TSNode node, const char* source_code) {
    TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
    if (ts_node_is_null(name_node)) {
        return NULL;
    }
    
    char* name = get_node_text(name_node, source_code);
    char* signature = get_java_method_signature(node, source_code);
    
    TSPoint start_point = ts_node_start_point(node);
    TSPoint end_point = ts_node_end_point(node);
    
    // Check if it's a main method
    entity_type_t type = ENTITY_FUNCTION;
    if (name && strcmp(name, "main") == 0) {
        type = ENTITY_MAIN_FUNCTION;
    }
    
    signature_node_t* sig_node = create_signature_node(
        type, name, signature,
        start_point.row + 1, start_point.column + 1,
        end_point.row + 1, end_point.column + 1
    );
    
    if (name) free(name);
    if (signature) free(signature);
    
    return sig_node;
}

// Process a Java interface declaration
signature_node_t* process_java_interface(TSNode node, const char* source_code) {
    TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
    if (ts_node_is_null(name_node)) {
        return NULL;
    }
    
    char* name = get_node_text(name_node, source_code);
    char* signature = get_java_class_signature(node, source_code); // Similar to class signature
    
    TSPoint start_point = ts_node_start_point(node);
    TSPoint end_point = ts_node_end_point(node);
    
    signature_node_t* sig_node = create_signature_node(
        ENTITY_INTERFACE, name, signature,
        start_point.row + 1, start_point.column + 1,
        end_point.row + 1, end_point.column + 1
    );
    
    if (name) free(name);
    if (signature) free(signature);
    
    return sig_node;
}

// Process a Java enum declaration
signature_node_t* process_java_enum(TSNode node, const char* source_code) {
    TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
    if (ts_node_is_null(name_node)) {
        return NULL;
    }
    
    char* name = get_node_text(name_node, source_code);
    char* signature = get_java_class_signature(node, source_code); // Similar to class signature
    
    TSPoint start_point = ts_node_start_point(node);
    TSPoint end_point = ts_node_end_point(node);
    
    signature_node_t* sig_node = create_signature_node(
        ENTITY_ENUM, name, signature,
        start_point.row + 1, start_point.column + 1,
        end_point.row + 1, end_point.column + 1
    );
    
    if (name) free(name);
    if (signature) free(signature);
    
    return sig_node;
}