package metis.core.tools.fs_utils

import magic.dsl.{jsonable, field}
import magic.jsonable.*
import magic.log.LogUtils

import std.collection.{map, collectArray, ArrayList, HashMap}
import std.fs.File
import stdx.encoding.json.*

@jsonable
protected struct EditFileParam {
    public let filePath: String
    public let oldContent: String
    public let newContent: String
}

//==============================================================================
// CLAIM
// Some prompts in this file are copied from
// https://github.com/google-gemini/gemini-cli/tree/main/packages/core/src/tools
// https://github.com/Yuyz0112/claude-code-reverse/blob/main/results/tools/MultiEdit.tool.yaml
//==============================================================================

protected let FILE_EDIT_DESCRIPTION = """
Replaces text within a file. By default, replaces a single occurrence.
This tool requires providing significant context around the change to ensure precise targeting. Always use the readFile tool to examine the file's current content before attempting a text replacement.

Expectation for required parameters:
1. path MUST be an absolute path; otherwise an error will be thrown.
2. oldContent MUST be the exact literal text to replace (including all whitespace, indentation, newlines, and surrounding code etc.).
3. newContent MUST be the exact literal text to replace `oldContent` with (also including all whitespace, indentation, newlines, and surrounding code etc.). Ensure the resulting code is correct and idiomatic.
4. NEVER escape `oldContent` or `newContent`, that would break the exact literal text requirement.
**Important:** If ANY of the above are not satisfied, the tool will fail. CRITICAL for `oldContent`: Must uniquely identify the single instance to change. Include at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. If this string matches multiple locations, or does not match exactly, the tool will fail.
"""

@jsonable
protected class MultiEditParam {
    @field["The old content to replace"]
    public let oldContent: String

    @field["The new content to replace oldContent with"]
    public let newContent: String
}

@jsonable
protected struct MultiEditFileParam {
    public let filePath: String
    public let edits: Array<MultiEditParam>
}

protected const FILE_MULTI_EDIT_DESCRIPTION = """
This is a tool for making multiple edits to a single file in one operation. It is built on top of the fileEdit tool and allows you to perform multiple find-and-replace operations efficiently. Prefer this tool over the Edit tool when you need to make multiple edits to the same file.

Before using this tool:

1. Use the read tools to understand the file's contents and context
2. Verify the directory path is correct

To make multiple file edits, provide the following:
1. filePath: The absolute path to the file to modify (must be absolute, not relative)
2. edits: An array of edit operations to perform, where each edit contains:
    - oldContent: The text to replace (must match the file contents exactly, including all whitespace and indentation)
    - newContent: The edited text to replace the oldContent

IMPORTANT:

- All edits are applied in sequence, in the order they are provided
- Each edit operates on the result of the previous edit
- All edits must be valid for the operation to succeed - if any edit fails, none will be applied
- This tool is ideal when you need to make several changes to different parts of the same file

CRITICAL REQUIREMENTS:

1. All edits follow the same requirements as the single fileEdit tool
2. The edits are atomic - either all succeed or none are applied
3. Plan your edits carefully to avoid conflicts between sequential operations

WARNING:

- The tool will fail if edits.oldContent doesn't match the file contents exactly (including whitespace)
- The tool will fail if edits.oldContent and edits.newContent are the same
- Since edits are applied in sequence, ensure that earlier edits don't affect the text that later edits are trying to find

When making edits:

- Ensure all edits result in idiomatic, correct code
- Do not leave the code in a broken state
- Always use absolute file paths (starting with /)
- Only use emojis if the user explicitly requests it. Avoid adding emojis to files unless asked.
parameter is useful if you want to rename a variable for instance.
"""
