package metis.io

import std.collection.{ArrayList, filter, enumerate, collectArray}

protected class CompletionListUtils {
    static let COMPLETION_LIST = ArrayList<String>()

    protected static func registerCompletionItem(item: String) {
        COMPLETION_LIST.add(item)
    }

    protected static func unregisterCompletionItem(item: String) {
        for ((idx, value) in enumerate(COMPLETION_LIST)) {
            if (value == item) {
                COMPLETION_LIST.remove(at: idx)
                break
            }
        }
    }
}

/**
 * Build completion list based on current input and cursor position
 * Supports both /commands and @paths
*/
func buildCompletionList(input: String, cursor: Int64, isShellMode!: Bool = false): Option<Array<String>> {
    let text = input
    // Completion list is disable for shell mode
    if (text.isEmpty() || isShellMode) {
        return None
    }

    let allCompletions = ArrayList<String>()

    // Check for @<path> completion
    if (let Some((atIndex, pathStart, pathEnd, pathPrefix)) <- extractPathContext(text, cursor)) {
        let pathCompletions = getPathCompletionList(prefix: pathPrefix)
        if (pathCompletions.size > 0) {
            // For empty prefix (just "@"), show all files
            // For non-empty prefix, show paths that start with prefix but are different
            if (pathPrefix.isEmpty()) {
                allCompletions.add(all: pathCompletions)
            } else {
                allCompletions.add(all: pathCompletions |>
                    filter { path => path.startsWith(pathPrefix) && path != pathPrefix } |>
                    collectArray
                )
            }
        }
    }
    // Add @<agent> completions
    allCompletions.add(all: buildCompletionListForAgent(text, cursor))
    if (!allCompletions.isEmpty()) {
        return allCompletions.toArray()
    }

    return buildCompletionListForCommand(text, cursor)
}

func buildCompletionListForCommand(text: String, cursor: Int64): Option<Array<String>> {
    // Check for /command completion (only at beginning and cursor at end)
    if (cursor != text.size || !text.startsWith("/")) {
        return None
    }

    let allCompletions = ArrayList<String>()

    // Generate all possible completions from command definitions
    // Last, add all registered items
    for (completion in CompletionListUtils.COMPLETION_LIST) {
        addCompletionIfMatches(allCompletions, completion, text)
    }

    if (allCompletions.isEmpty()) {
        return None
    } else {
        return allCompletions.toArray()
    }
}

func buildCompletionListForAgent(text: String, cursor: Int64): Array<String> {
    // Check for or @agent completion (only at beginning and cursor at end)
    if (cursor != text.size || !text.startsWith("@")) {
        return []
    }

    let allCompletions = ArrayList<String>()
    for (completion in CompletionListUtils.COMPLETION_LIST) {
        addCompletionIfMatches(allCompletions, completion, text)
    }

    return allCompletions.toArray()
}

/**
 * Add completion to list if it matches the text
 */
private func addCompletionIfMatches(allCompletions: ArrayList<String>, completion: String, text: String): Unit {
    if (completion.startsWith(text) && completion != text) {
        if (text.startsWith("@")) {
            allCompletions.add(completion[1..]) // Remove "@" prefix for agent completions
        } else {
            allCompletions.add(completion)
        }
    }
}