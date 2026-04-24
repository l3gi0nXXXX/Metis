#include "signature_extractor.h"
#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int MAX_XML_SIZE = 3 * 1024 * 1024;

// Helper function to get error context directly from source code
void get_error_context(const char* source_code, int error_line_number, 
                      char** error_line, char** above_lines, char** below_lines) {
    // Call the extended version with default context of 2 lines
    get_error_context_ext(source_code, error_line_number, 2, error_line, above_lines, below_lines);
}

// Extended helper function to get error context with configurable context lines
void get_error_context_ext(const char* source_code, int error_line_number, int context_lines,
                          char** error_line, char** above_lines, char** below_lines) {
    if (!source_code || error_line_number < 1) {
        *error_line = NULL;
        *above_lines = NULL;
        *below_lines = NULL;
        return;
    }
    
    // Count total lines in the source
    int total_lines = 1;
    const char* ptr = source_code;
    while (*ptr) {
        if (*ptr == '\n') {
            total_lines++;
        }
        ptr++;
    }
    
    // Check if the requested line exists
    if (error_line_number > total_lines) {
        *error_line = NULL;
        *above_lines = NULL;
        *below_lines = NULL;
        return;
    }
    
    // Allocate array to store line start positions
    const char** line_starts = malloc(sizeof(char*) * (total_lines + 1));
    if (!line_starts) {
        *error_line = NULL;
        *above_lines = NULL;
        *below_lines = NULL;
        return;
    }
    
    // Fill the line start positions
    line_starts[0] = source_code;
    int current_line = 1;
    ptr = source_code;
    while (*ptr) {
        if (*ptr == '\n') {
            current_line++;
            line_starts[current_line-1] = ptr + 1;
        }
        ptr++;
    }
    
    // For a more accurate error line, we'll look at the reported line and nearby lines
    // to try to identify the actual problematic line
    int actual_error_line = error_line_number;
    
    // Get the actual error line (the reported line)
    const char* error_line_start = line_starts[error_line_number - 1];
    const char* error_line_end = error_line_start;
    
    // Find end of error line
    while (*error_line_end && *error_line_end != '\n') {
        error_line_end++;
    }
    
    size_t error_line_len = error_line_end - error_line_start;
    *error_line = malloc(error_line_len + 1);
    if (*error_line) {
        strncpy(*error_line, error_line_start, error_line_len);
        (*error_line)[error_line_len] = '\0';
    }
    
    // Get context lines above the error line
    if (error_line_number > 1) {
        // Determine start line for above context (at most context_lines or to start of file)
        int above_start_line = (error_line_number - 1 - context_lines) > 0 ? 
                              (error_line_number - 1 - context_lines) : 0;
        
        const char* above_start = line_starts[above_start_line];
        const char* above_end = error_line_start;
        
        // Make sure we don't include the newline before the error line
        if (above_end > above_start && *(above_end - 1) == '\n') {
            above_end--;
        }
        
        size_t above_len = above_end - above_start;
        *above_lines = malloc(above_len + 1);
        if (*above_lines) {
            strncpy(*above_lines, above_start, above_len);
            (*above_lines)[above_len] = '\0';
        }
    } else {
        *above_lines = NULL;
    }
    
    // Get context lines below the error line
    if (error_line_number < total_lines) {
        // Determine end line for below context (at most context_lines or to end of file)
        int below_end_line = (error_line_number + context_lines) < total_lines ? 
                            (error_line_number + context_lines) : (total_lines - 1);
        
        const char* below_start = error_line_end;
        // Skip the newline character
        if (*below_start == '\n') {
            below_start++;
        }
        const char* below_end = line_starts[below_end_line] ;
        
        // Find the end of the below_end_line
        while (*below_end && *below_end != '\n') {
            below_end++;
        }
        if (*below_end == '\n') {
            below_end++; // Include the last newline
        }
        
        size_t below_len = below_end - below_start;
        *below_lines = malloc(below_len + 1);
        if (*below_lines) {
            strncpy(*below_lines, below_start, below_len);
            (*below_lines)[below_len] = '\0';
        }
    } else {
        *below_lines = NULL;
    }
    
    free(line_starts);
}

// Extract parse errors from the tree
parse_error_t* extract_parse_errors(TSTree* tree, const char* source_code, int* error_count) {
    *error_count = 0;
    
    // Get the root node
    TSNode root_node = ts_tree_root_node(tree);
    
    // Count total nodes to pre-allocate errors array
    // We'll do a simple traversal to find ERROR nodes
    parse_error_t* errors = NULL;
    int capacity = 0;
    
    // Create a queue for breadth-first traversal
    TSNode queue[1024];
    int front = 0, rear = 0;
    
    // Enqueue root node
    queue[rear++] = root_node;
    
    // Traverse the tree using breadth-first search
    while (front < rear && *error_count < 1024) {
        // Dequeue node
        TSNode node = queue[front++];
        
        // Check if this is an ERROR node
        if (!ts_node_is_null(node)) {
            const char* node_type = ts_node_type(node);
            if (strcmp(node_type, "ERROR") == 0) {
                // Found an error node, add it to our list
                if (*error_count >= capacity) {
                    capacity = (capacity == 0) ? 10 : capacity * 2;
                    parse_error_t* temp = realloc(errors, sizeof(parse_error_t) * capacity);
                    if (!temp) {
                        // Clean up and return what we have
                        break;
                    }
                    errors = temp;
                }
                
                TSPoint start_point = ts_node_start_point(node);
                errors[*error_count].line = start_point.row + 1; // 1-indexed
                errors[*error_count].message = strdup("Syntax error detected");
                
                // Get error context directly from source code with 2 lines of context
                get_error_context_ext(source_code, start_point.row + 1, 2,
                                &errors[*error_count].error_line,
                                &errors[*error_count].code_above_error_line,
                                &errors[*error_count].code_below_error_line);
                
                (*error_count)++;
            }
            
            // Check for missing nodes (indicated by ts_node_is_missing)
            if (ts_node_is_missing(node)) {
                if (*error_count >= capacity) {
                    capacity = (capacity == 0) ? 10 : capacity * 2;
                    parse_error_t* temp = realloc(errors, sizeof(parse_error_t) * capacity);
                    if (!temp) {
                        // Clean up and return what we have
                        break;
                    }
                    errors = temp;
                }
                
                TSPoint start_point = ts_node_start_point(node);
                errors[*error_count].line = start_point.row + 1; // 1-indexed
                errors[*error_count].message = strdup("Missing token or construct");
                
                // Get error context directly from source code with 2 lines of context
                get_error_context_ext(source_code, start_point.row + 1, 2,
                                &errors[*error_count].error_line,
                                &errors[*error_count].code_above_error_line,
                                &errors[*error_count].code_below_error_line);
                
                (*error_count)++;
            }
        }
        
        // Add children to queue for further processing
        uint32_t child_count = ts_node_child_count(node);
        for (uint32_t i = 0; i < child_count && rear < 1024; i++) {
            TSNode child = ts_node_child(node, i);
            if (!ts_node_is_null(child)) {
                queue[rear++] = child;
            }
        }
    }
    
    // Remove duplicate errors (same line number)
    if (errors && *error_count > 1) {
        for (int i = 0; i < *error_count; i++) {
            for (int j = i + 1; j < *error_count; j++) {
                if (errors[i].line == errors[j].line) {
                    // Found duplicate, remove the later one
                    // Free the strings in the duplicate entry
                    if (errors[j].message) free(errors[j].message);
                    if (errors[j].error_line) free(errors[j].error_line);
                    if (errors[j].code_above_error_line) free(errors[j].code_above_error_line);
                    if (errors[j].code_below_error_line) free(errors[j].code_below_error_line);
                    
                    // Shift all entries after j one position to the left
                    for (int k = j; k < *error_count - 1; k++) {
                        errors[k] = errors[k + 1];
                    }
                    
                    // Decrement the count and adjust indices
                    (*error_count)--;
                    j--; // Check the same index again as elements have shifted
                }
            }
        }
    }
    
    return errors;
}

// Update the free_parse_errors function to handle the new structure
void free_parse_errors(parse_error_t* errors, int error_count) {
    if (!errors) return;
    
    for (int i = 0; i < error_count; i++) {
        if (errors[i].message) free(errors[i].message);
        if (errors[i].error_line) free(errors[i].error_line);
        if (errors[i].code_above_error_line) free(errors[i].code_above_error_line);
        if (errors[i].code_below_error_line) free(errors[i].code_below_error_line);
    }
    
    free(errors);
}

// Recursive function to traverse the AST and extract signatures
signature_node_t* traverse_and_extract(TSNode node, const char* source_code, const char* language, signature_node_t* parent) {
    if (ts_node_is_null(node)) {
        return NULL;
    }
    
    const char* node_type = ts_node_type(node);
    signature_node_t* sig_node = NULL;
    
    // Java specific processing
    if (strcmp(language, "java") == 0) {
        if (strcmp(node_type, "class_declaration") == 0) {
            sig_node = process_java_class(node, source_code);
        } else if (strcmp(node_type, "method_declaration") == 0) {
            sig_node = process_java_method(node, source_code);
        } else if (strcmp(node_type, "interface_declaration") == 0) {
            sig_node = process_java_interface(node, source_code);
        } else if (strcmp(node_type, "enum_declaration") == 0) {
            sig_node = process_java_enum(node, source_code);
        }
    }
    // Python specific processing
    else if (strcmp(language, "python") == 0) {
        if (strcmp(node_type, "class_definition") == 0) {
            sig_node = process_python_class(node, source_code);
        } else if (strcmp(node_type, "function_definition") == 0) {
            sig_node = process_python_function(node, source_code);
        }
    }
    
    // If we created a signature node, set its parent
    if (sig_node && parent) {
        add_child_signature_node(parent, sig_node);
    }
    
    // For the root node or when we don't have a signature node, continue with the same parent
    signature_node_t* current_parent = sig_node ? sig_node : parent;
    
    // Recursively process children
    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
        TSNode child = ts_node_child(node, i);
        traverse_and_extract(child, source_code, language, current_parent);
    }
    
    return sig_node;
}

signature_node_t* extract_signatures(TSTree* tree, const char* source_code, const char* language) {
    if (!tree || !source_code || !language) {
        return NULL;
    }
    
    TSNode root_node = ts_tree_root_node(tree);
    
    // Create a dummy root node to hold all top-level signatures
    signature_node_t* root_container = create_signature_node(
        ENTITY_UNKNOWN, "root", "root", 0, 0, 0, 0
    );
    
    traverse_and_extract(root_node, source_code, language, root_container);
    
    // Return the children of the dummy root (the actual top-level signatures)
    signature_node_t* result = root_container->children;
    
    // Disconnect the children from the dummy root
    if (result) {
        signature_node_t* child = result;
        while (child) {
            child->parent = NULL;
            child = child->next_sibling;
        }
    }
    
    // Free the dummy root but not its children
    root_container->children = NULL;
    free_signature_node(root_container);
    
    return result;
}

signature_node_t* extract_signatures_from_file(const char *filepath, const char *language) {
    size_t source_size;
    char *source_code = read_file(filepath, &source_size);
    if (!source_code) {
        return NULL;
    }

    // Create a parser
    TSParser *parser = ts_parser_new();
    
    // Set the language
    TSLanguage *lang = NULL;
    if (strcmp(language, "java") == 0) {
        lang = tree_sitter_java();
    } else if (strcmp(language, "python") == 0) {
        lang = tree_sitter_python();
    } else {
        fprintf(stderr, "Unsupported language: %s\n", language);
        free(source_code);
        ts_parser_delete(parser);
        return NULL;
    }
    
    ts_parser_set_language(parser, lang);
    
    // Parse the source code
    TSTree *tree = ts_parser_parse_string(parser, NULL, source_code, source_size);
    
    // Extract signatures
    signature_node_t* signatures = extract_signatures(tree, source_code, language);
    
    // Clean up
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    free(source_code);
    
    return signatures;
}

// Helper function to escape XML special characters for attributes
char* escape_xml_attr(const char* input) {
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
            case '\'': escaped_len += 6; break;
            case '\n': escaped_len += 5; break;  // &#10;
            case '\r': escaped_len += 5; break;  // &#13;
            case '\t': escaped_len += 5; break;  // &#9;
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
                j += 5;
                break;
            default:
                escaped[j++] = input[i];
                break;
        }
    }
    
    escaped[j] = '\0';
    return escaped;
}

char* get_skeleton_xml_range(const char *filename, const char *language, int start_line, int end_line) {
    return get_skeleton_xml_with_errors(filename, language, start_line, end_line);
}

char* get_skeleton_xml(const char *filename, const char *language) {
    return get_skeleton_xml_with_errors(filename, language, -1, -1);
}

char* get_skeleton_xml_with_errors(const char *filename, const char *language, int start_line, int end_line) {
    // Extract signatures from the file
    size_t source_size;
    char *source_code = read_file(filename, &source_size);
    if (!source_code) {
        return NULL;
    }

    // Create a parser
    TSParser *parser = ts_parser_new();
    
    // Set the language
    TSLanguage *lang = NULL;
    if (strcmp(language, "java") == 0) {
        lang = tree_sitter_java();
    } else if (strcmp(language, "python") == 0) {
        lang = tree_sitter_python();
    } else {
        fprintf(stderr, "Unsupported language: %s\n", language);
        free(source_code);
        ts_parser_delete(parser);
        return NULL;
    }
    
    ts_parser_set_language(parser, lang);
    
    // Parse the source code
    TSTree *tree = ts_parser_parse_string(parser, NULL, source_code, source_size);
    
    // Extract signatures
    signature_node_t* root = extract_signatures(tree, source_code, language);
    
    // Extract errors
    int error_count = 0;
    parse_error_t* errors = extract_parse_errors(tree, source_code, &error_count);
    
    // Filter errors based on line range if specified
    parse_error_t* filtered_errors = NULL;
    int filtered_error_count = 0;
    
    if (start_line != -1 && end_line != -1 && errors && error_count > 0) {
        // Allocate memory for filtered errors
        filtered_errors = malloc(sizeof(parse_error_t) * error_count);
        if (filtered_errors) {
            for (int i = 0; i < error_count; i++) {
                // Check if error is within the specified range
                if (errors[i].line >= start_line && errors[i].line <= end_line) {
                    filtered_errors[filtered_error_count] = errors[i];
                    // Since we're copying the struct, we need to duplicate the strings
                    if (filtered_errors[filtered_error_count].message) {
                        filtered_errors[filtered_error_count].message = strdup(filtered_errors[filtered_error_count].message);
                    }
                    if (filtered_errors[filtered_error_count].error_line) {
                        filtered_errors[filtered_error_count].error_line = strdup(filtered_errors[filtered_error_count].error_line);
                    }
                    if (filtered_errors[filtered_error_count].code_above_error_line) {
                        filtered_errors[filtered_error_count].code_above_error_line = strdup(filtered_errors[filtered_error_count].code_above_error_line);
                    }
                    if (filtered_errors[filtered_error_count].code_below_error_line) {
                        filtered_errors[filtered_error_count].code_below_error_line = strdup(filtered_errors[filtered_error_count].code_below_error_line);
                    }
                    filtered_error_count++;
                }
            }
        }
    } else {
        // Use all errors if no range is specified
        filtered_errors = errors;
        filtered_error_count = error_count;
        errors = NULL; // Prevent double-free
    }
    
    // Filter code entities based on line range if specified
    signature_node_t* filtered_root = NULL;
    if (start_line != -1 && end_line != -1 && root) {
        // Create a new root container for filtered nodes
        filtered_root = create_signature_node(
            ENTITY_UNKNOWN, "root", "root", 0, 0, 0, 0
        );
        
        // Iterate through all top-level nodes
        signature_node_t* current = root;
        while (current) {
            // Check if this node overlaps with the range
            // entity.endLine >= target_startLine && entity.startLine <= target_endLine
            if ((current->end_line >= start_line && current->start_line <= end_line)) {
                // Add node to filtered results with range-based filtering of children
                signature_node_t* cloned_node = clone_signature_node_with_range(current, start_line, end_line);
                if (cloned_node) {
                    add_child_signature_node(filtered_root, cloned_node);
                }
            }
            current = current->next_sibling;
        }
    } else {
        filtered_root = root;
    }
    
    // Calculate approximate buffer size needed
    // Start with a reasonable base size for XML structure
    size_t buffer_size = 8192; // Increased base size
    signature_node_t* current = (start_line != -1 && end_line != -1) ? filtered_root->children : filtered_root;
    
    // Roughly estimate space needed for all signatures
    while (current) {
        if (current->signature) {
            buffer_size += strlen(current->signature) + 500; // Extra for XML tags
        }
        // Also account for children recursively
        signature_node_t* child = current ? current->children : NULL;
        while (child) {
            buffer_size += calculate_node_size_recursive(child);
            child = child->next_sibling;
        }
        current = current->next_sibling;
    }
    
    // Account for errors
    buffer_size += filtered_error_count * 2048; // More space for the detailed error info
    if (buffer_size > MAX_XML_SIZE) {
        buffer_size = MAX_XML_SIZE;
    }
    
    // Allocate buffer
    char* xml_buffer = (char*)malloc(buffer_size);
    if (!xml_buffer) {
        free_parse_errors(filtered_errors, filtered_error_count);
        if (errors) free_parse_errors(errors, error_count);
        if (root && (start_line == -1 || end_line == -1)) {
            free_signature_node(root);
        } else if (filtered_root) {
            free_signature_node(filtered_root);
        }
        free(source_code);
        ts_tree_delete(tree);
        ts_parser_delete(parser);
        return NULL;
    }
    
    // Start building XML
    int offset = 0;
    char* escaped_filename = escape_xml_attr(filename);
    if (escaped_filename) {
        if (start_line != -1 && end_line != -1) {
            offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                               "<code-skeleton path=\"%s\" range=\"%d-%d\">\n", escaped_filename, start_line, end_line);
        } else {
            offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                               "<code-skeleton path=\"%s\">\n", escaped_filename);
        }
        free(escaped_filename);
    } else {
        if (start_line != -1 && end_line != -1) {
            offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                               "<code-skeleton path=\"%s\" range=\"%d-%d\">\n", filename, start_line, end_line);
        } else {
            offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                               "<code-skeleton path=\"%s\">\n", filename);
        }
    }
    
    // Process all top-level nodes
    current = (start_line != -1 && end_line != -1) ? filtered_root->children : filtered_root;
    while (current) {
        if (current->signature) {
            offset = print_node_recursive(xml_buffer, buffer_size, current, offset, 1);
        }
        current = current->next_sibling;
    }
    
    // Process errors if any
    if (filtered_error_count > 0 && filtered_errors) {
        offset += snprintf(xml_buffer + offset, buffer_size - offset,
                           "  <code-errors>\n");
                           
        for (int i = 0; i < filtered_error_count; i++) {
            offset += snprintf(xml_buffer + offset, buffer_size - offset,
                               "    <error line=%d>\n", filtered_errors[i].line);
                               
            char* escaped_message = escape_xml(filtered_errors[i].message);
            if (escaped_message) {
                offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                   "      <message>%s</message>\n", escaped_message);
                free(escaped_message);
            } else {
                offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                   "      <message>%s</message>\n", filtered_errors[i].message);
            }
            
            // Add the detailed error context
            if (filtered_errors[i].error_line) {
                char* escaped_error_line = escape_xml(filtered_errors[i].error_line);
                if (escaped_error_line) {
                    offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                       "      <error-line>%s</error-line>\n", escaped_error_line);
                    free(escaped_error_line);
                } else {
                    offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                       "      <error-line>%s</error-line>\n", filtered_errors[i].error_line);
                }
            }
            
            if (filtered_errors[i].code_above_error_line) {
                char* escaped_above_line = escape_xml(filtered_errors[i].code_above_error_line);
                if (escaped_above_line) {
                    offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                       "      <code-above-error-line>%s</code-above-error-line>\n", escaped_above_line);
                    free(escaped_above_line);
                } else {
                    offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                       "      <code-above-error-line>%s</code-above-error-line>\n", filtered_errors[i].code_above_error_line);
                }
            }
            
            if (filtered_errors[i].code_below_error_line) {
                char* escaped_below_line = escape_xml(filtered_errors[i].code_below_error_line);
                if (escaped_below_line) {
                    offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                       "      <code-below-error-line>%s</code-below-error-line>\n", escaped_below_line);
                    free(escaped_below_line);
                } else {
                    offset += snprintf(xml_buffer + offset, buffer_size - offset,
                                       "      <code-below-error-line>%s</code-below-error-line>\n", filtered_errors[i].code_below_error_line);
                }
            }
            
            offset += snprintf(xml_buffer + offset, buffer_size - offset,
                               "    </error>\n");
        }
        
        offset += snprintf(xml_buffer + offset, buffer_size - offset,
                           "  </code-errors>\n");
    }
    
    offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                       "</code-skeleton>");
    
    // Clean up
    free_parse_errors(filtered_errors, filtered_error_count);
    if (errors) free_parse_errors(errors, error_count);
    if (root && (start_line == -1 || end_line == -1)) {
        free_signature_node(root);
    } else if (filtered_root) {
        free_signature_node(filtered_root);
    }
    free(source_code);
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    
    return xml_buffer;
}

// Helper function to calculate the size needed for a node and all its descendants
size_t calculate_node_size_recursive(signature_node_t* node) {
    if (!node || !node->signature) return 0;
    
    size_t size = strlen(node->signature) + 100; // Base size for this node
    
    // Add size for all children recursively
    signature_node_t* child = node->children;
    while (child) {
        size += calculate_node_size_recursive(child);
        child = child->next_sibling;
    }
    
    return size;
}

// Helper function to recursively print a node and all its descendants
int print_node_recursive(char* buffer, size_t buffer_size, signature_node_t* node, int offset, int indent_level) {
    if (!node || !node->signature) return offset;
    
    // Print indentation
    for (int i = 0; i < indent_level; i++) {
        offset += snprintf(buffer + offset, buffer_size - offset, "    ");
    }
    
    // Print the code entity
    offset += snprintf(buffer + offset, buffer_size - offset,
                       "<code-entity start=%d end=%d>\n", 
                       node->start_line, node->end_line);
    
    // Print indentation for signature
    for (int i = 0; i < indent_level + 1; i++) {
        offset += snprintf(buffer + offset, buffer_size - offset, "    ");
    }
    
    // Escape special XML characters in signature
    char* escaped_signature = escape_xml(node->signature);
    if (escaped_signature) {
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "<signature>%s</signature>\n", 
                           escaped_signature);
        free(escaped_signature);
    } else {
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "<signature>%s</signature>\n", 
                           node->signature);
    }
    
    // Process children if they exist
    if (node->children) {
        // Print indentation for member
        for (int i = 0; i < indent_level + 1; i++) {
            offset += snprintf(buffer + offset, buffer_size - offset, "    ");
        }
        
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "<member>\n");
        
        signature_node_t* child = node->children;
        while (child) {
            offset = print_node_recursive(buffer, buffer_size, child, offset, indent_level + 2);
            child = child->next_sibling;
        }
        
        // Print indentation for closing member tag
        for (int i = 0; i < indent_level + 1; i++) {
            offset += snprintf(buffer + offset, buffer_size - offset, "    ");
        }
        
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "</member>\n");
    }
    
    // Print indentation for closing code-entity tag
    for (int i = 0; i < indent_level; i++) {
        offset += snprintf(buffer + offset, buffer_size - offset, "    ");
    }
    
    offset += snprintf(buffer + offset, buffer_size - offset,
                       "</code-entity>\n");
    
    return offset;
}

// Helper function to clone a signature node and its children with range filtering
signature_node_t* clone_signature_node_with_range(signature_node_t* node, int start_line, int end_line) {
    if (!node) return NULL;
    
    // Check if this node overlaps with the range
    // entity.endLine >= target_startLine && entity.startLine <= target_endLine
    if (!(node->end_line >= start_line && node->start_line <= end_line)) {
        return NULL; // Node doesn't overlap with range, don't include it
    }
    
    signature_node_t* clone = create_signature_node(
        node->type, node->name, node->signature,
        node->start_line, node->start_column,
        node->end_line, node->end_column
    );
    
    if (!clone) return NULL;
    
    // Clone children that also overlap with the range
    signature_node_t* child = node->children;
    while (child) {
        signature_node_t* cloned_child = clone_signature_node_with_range(child, start_line, end_line);
        if (cloned_child) {
            add_child_signature_node(clone, cloned_child);
        }
        child = child->next_sibling;
    }
    
    return clone;
}

// Helper function to clone a signature node and its children (without range filtering)
signature_node_t* clone_signature_node(signature_node_t* node) {
    if (!node) return NULL;
    
    signature_node_t* clone = create_signature_node(
        node->type, node->name, node->signature,
        node->start_line, node->start_column,
        node->end_line, node->end_column
    );
    
    if (!clone) return NULL;
    
    // Clone children
    signature_node_t* child = node->children;
    while (child) {
        signature_node_t* cloned_child = clone_signature_node(child);
        if (cloned_child) {
            add_child_signature_node(clone, cloned_child);
        }
        child = child->next_sibling;
    }
    
    return clone;
}