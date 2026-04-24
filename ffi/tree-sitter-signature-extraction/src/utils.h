#ifndef UTILS_H
#define UTILS_H

#include "tree_sitter/api.h"
#include "dll_export.h"

#ifdef __cplusplus
extern "C" {
#endif

DLL_EXPORT char* get_node_text(TSNode node, const char* source_code);
DLL_EXPORT char* get_modifiers_text(TSNode node, const char* source_code);
DLL_EXPORT char *read_file(const char *filename, size_t *size);
DLL_EXPORT char* escape_xml(const char* input);

#ifdef __cplusplus
}
#endif

#endif // UTILS_H