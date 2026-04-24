#include "signature_node.h"

signature_node_t* create_signature_node(entity_type_t type, const char* name, 
                                       const char* signature, int start_line, 
                                       int start_column, int end_line, int end_column) {
    signature_node_t* node = (signature_node_t*)malloc(sizeof(signature_node_t));
    if (!node) {
        return NULL;
    }
    
    node->type = type;
    node->name = name ? strdup(name) : NULL;
    node->signature = signature ? strdup(signature) : NULL;
    node->start_line = start_line;
    node->start_column = start_column;
    node->end_line = end_line;
    node->end_column = end_column;
    node->parent = NULL;
    node->children = NULL;
    node->next_sibling = NULL;
    
    return node;
}

void free_signature_node(signature_node_t* node) {
    if (!node) {
        return;
    }
    
    // Free all children recursively
    signature_node_t* child = node->children;
    while (child) {
        signature_node_t* next = child->next_sibling;
        free_signature_node(child);
        child = next;
    }
    
    // Free node data
    if (node->name) {
        free(node->name);
    }
    
    if (node->signature) {
        free(node->signature);
    }
    
    free(node);
}

void add_child_signature_node(signature_node_t* parent, signature_node_t* child) {
    if (!parent || !child) {
        return;
    }
    
    child->parent = parent;
    
    if (!parent->children) {
        // No children yet, make this the first child
        parent->children = child;
    } else {
        // Find the last child and add this as the next sibling
        signature_node_t* last_child = parent->children;
        while (last_child->next_sibling) {
            last_child = last_child->next_sibling;
        }
        last_child->next_sibling = child;
    }
}

const char* entity_type_to_string(entity_type_t type) {
    switch (type) {
        case ENTITY_CLASS:
            return "class";
        case ENTITY_STRUCT:
            return "struct";
        case ENTITY_ENUM:
            return "enum";
        case ENTITY_INTERFACE:
            return "interface";
        case ENTITY_FUNCTION:
            return "func";
        case ENTITY_MAIN_FUNCTION:
            return "main";
        case ENTITY_PRIMARY_CONSTRUCTOR:
            return "primary_constructor";
        case ENTITY_PROPERTY:
            return "prop";
        case ENTITY_UNKNOWN:
        default:
            return "unknown";
    }
}

void print_signature_node(signature_node_t* node, int indent) {
    if (!node) {
        return;
    }
    
    // Print indentation
    for (int i = 0; i < indent; i++) {
        printf("  ");
    }
    
    printf("{\n");
    
    // Print indentation for fields
    for (int i = 0; i < indent + 1; i++) {
        printf("  ");
    }
    
    printf("\"type\": \"%s\",\n", entity_type_to_string(node->type));
    
    for (int i = 0; i < indent + 1; i++) {
        printf("  ");
    }
    
    printf("\"name\": \"%s\",\n", node->name ? node->name : "");
    
    for (int i = 0; i < indent + 1; i++) {
        printf("  ");
    }
    
    printf("\"signature\": \"%s\",\n", node->signature ? node->signature : "");
    
    for (int i = 0; i < indent + 1; i++) {
        printf("  ");
    }
    
    printf("\"location\": {\n");
    
    for (int i = 0; i < indent + 2; i++) {
        printf("  ");
    }
    
    printf("\"start\": {\"line\": %d, \"column\": %d},\n", node->start_line, node->start_column);
    
    for (int i = 0; i < indent + 2; i++) {
        printf("  ");
    }
    
    printf("\"end\": {\"line\": %d, \"column\": %d}\n", node->end_line, node->end_column);
    
    for (int i = 0; i < indent + 1; i++) {
        printf("  ");
    }
    
    // Print children if any
    if (node->children) {
        printf("},\n");
        
        for (int i = 0; i < indent + 1; i++) {
            printf("  ");
        }
        
        printf("\"children\": [\n");
        
        signature_node_t* child = node->children;
        while (child) {
            print_signature_node(child, indent + 2);
            child = child->next_sibling;
            if (child) {
                printf(",\n");
            } else {
                printf("\n");
            }
        }
        
        for (int i = 0; i < indent + 1; i++) {
            printf("  ");
        }
        
        printf("]\n");
    } else {
        printf("}\n");
    }
    
    for (int i = 0; i < indent; i++) {
        printf("  ");
    }
    
    printf("}");
}

void print_signature_tree(signature_node_t* root) {
    printf("[\n");
    if (root) {
        signature_node_t* sibling = root;
        while (sibling) {
            print_signature_node(sibling, 1);
            sibling = sibling->next_sibling;
            if (sibling) {
                printf(",\n");
            } else {
                printf("\n");
            }
        }
    }
    printf("]\n");
}