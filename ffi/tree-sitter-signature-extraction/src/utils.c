#include "signature_extractor.h"
#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Helper function to get the text of a node
char* get_node_text(TSNode node, const char* source_code) {
    if (ts_node_is_null(node)) {
        return NULL;
    }
    
    uint32_t start_byte = ts_node_start_byte(node);
    uint32_t end_byte = ts_node_end_byte(node);
    uint32_t length = end_byte - start_byte;
    
    if (length == 0) {
        return NULL;
    }
    
    char* text = (char*)malloc(length + 1);
    if (!text) {
        return NULL;
    }
    
    memcpy(text, source_code + start_byte, length);
    text[length] = '\0';
    
    return text;
}

char* get_modifiers_text(TSNode node, const char* source_code) {
    uint32_t child_count = ts_node_child_count(node);
    TSNode modifiers_node = {0}; // Initialize to null node
    bool found_modifier = false;

    for (uint32_t i = 0; i < child_count; i++) {
        const char* field_name = ts_node_field_name_for_child(node, i);
        // Check both by field name (if available) and by node type
        if (field_name && strcmp(field_name, "modifiers") == 0) {
            modifiers_node = ts_node_child(node, i);
            found_modifier = true;
            break;
        }
        // If field name is not found, check the node type
        TSNode potential_child = ts_node_child(node, i);
        if (strcmp(ts_node_type(potential_child), "modifiers") == 0) {
            modifiers_node = potential_child;
            found_modifier = true;
            break;
        }
    }
    
    // Check if we found a modifiers node
    if (!found_modifier) {
        return NULL;
    }
    
    // Check if the modifiers node is valid
    if (ts_node_is_null(modifiers_node)) {
        return NULL;
    }
    
    uint32_t modifier_count = ts_node_child_count(modifiers_node);
    
    if (modifier_count == 0) return NULL;

    // Now check if we found the modifiers_node and iterate through its children
    char *rst = NULL;
    size_t sig_len = 0;
    size_t sig_cap = 64; // Initial capacity
    rst = malloc(sig_cap);
    if (!rst) {
        return NULL;
    }
    rst[0] = '\0';
    for (uint32_t j = 0; j < modifier_count; j++) {
        TSNode mod_node = ts_node_child(modifiers_node, j);
        char* mod_text = get_node_text(mod_node, source_code);
        if (mod_text) {
            size_t mod_len = strlen(mod_text) + 1;
            // Ensure enough capacity
            while (sig_len + mod_len + 1 > sig_cap) {
                sig_cap *= 2;
                char* temp = realloc(rst, sig_cap);
                if (!temp) {
                    free(mod_text);
                    free(rst);
                    return NULL;
                }
                rst = temp;
            }
            strcat(rst, mod_text);
            if (mod_text[0] == '@') strcat(rst, "\n");
            else if (j < modifier_count - 1) strcat(rst, " ");
            sig_len += mod_len;
            free(mod_text);
        }
    }
    return rst;
}

char *read_file(const char *filename, size_t *size) {
    FILE *file = fopen(filename, "rb");
    if (!file) {
        perror("Error opening file");
        return NULL;
    }

    fseek(file, 0, SEEK_END);
    *size = ftell(file);
    fseek(file, 0, SEEK_SET);

    char *buffer = malloc(*size + 1);
    if (!buffer) {
        fclose(file);
        fprintf(stderr, "Error allocating memory\n");
        return NULL;
    }

    fread(buffer, 1, *size, file);
    buffer[*size] = '\0';

    fclose(file);
    return buffer;
}

// Helper function to escape XML special characters
char* escape_xml(const char* input) {
    if (!input) return NULL;
    
    // Calculate the length needed for the escaped string
    size_t len = strlen(input);
    size_t escaped_len = len;
    
    for (size_t i = 0; i < len; i++) {
        switch (input[i]) {
            case '&':  escaped_len += 5; break;  // &amp;
            case '<':  escaped_len += 4; break;  // &lt;
            case '>':  escaped_len += 4; break;  // &gt;
            case '"':  escaped_len += 6; break;  // &quot;
            case '\'': escaped_len += 6; break;  // &apos;
            case '\n': escaped_len += 5; break;  // &#10;
            case '\r': escaped_len += 5; break;  // &#13;
            case '\t': escaped_len += 4; break;  // &#9;
            default:   break;
        }
    }
    
    // Allocate memory for the escaped string
    char* escaped = (char*)malloc(escaped_len + 1);
    if (!escaped) return NULL;
    
    // Perform the escaping
    size_t j = 0;
    for (size_t i = 0; i < len; i++) {
        switch (input[i]) {
            case '&':
                strcpy(escaped + j, "&amp;");
                j += 5;
                break;
            case '<':
                strcpy(escaped + j, "&lt;");
                j += 4;
                break;
            case '>':
                strcpy(escaped + j, "&gt;");
                j += 4;
                break;
            case '"':
                strcpy(escaped + j, "&quot;");
                j += 6;
                break;
            case '\'':
                strcpy(escaped + j, "&apos;");
                j += 6;
                break;
            case '\n':
                strcpy(escaped + j, "&#10;");
                j += 5;
                break;
            case '\r':
                strcpy(escaped + j, "&#13;");
                j += 5;
                break;
            case '\t':
                strcpy(escaped + j, "&#9;");
                j += 4;
                break;
            default:
                escaped[j++] = input[i];
                break;
        }
    }
    
    escaped[j] = '\0';
    return escaped;
}
