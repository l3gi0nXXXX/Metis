package metis.core.tools

import magic.dsl.*
import magic.prelude.*

import metis.io.{InputUtils, PrintUtils, Confirmation}
import metis.utils.*

import std.fs.*
import std.io.*
import std.env.*

private let GIT_GUIDELINE = """
# Committing changes with git

When the user asks you to create a new git commit, follow these steps carefully:

1. You have the capability to call multiple tools in a single response. When multiple independent pieces of information are requested, batch your tool calls together for optimal performance. ALWAYS run the following bash commands in parallel, each using the Bash tool:
  - Run a git status command to see all untracked files.
  - Run a git diff command to see both staged and unstaged changes that will be committed.
  - Run a git log command to see recent commit messages, so that you can follow this repository's commit message style.
2. Analyze all staged changes (both previously staged and newly added) and draft a commit message:
  - Summarize the nature of the changes (eg. new feature, enhancement to an existing feature, bug fix, refactoring, test, docs, etc.). Ensure the message accurately reflects the changes and their purpose (i.e. \"add\" means a wholly new feature, \"update\" means an enhancement to an existing feature, \"fix\" means a bug fix, etc.).
  - Check for any sensitive information that shouldn't be committed
  - Draft a concise (1-2 sentences) commit message that focuses on the \"why\" rather than the \"what\"
  - Ensure it accurately reflects the changes and their purpose
3. You have the capability to call multiple tools in a single response. When multiple independent pieces of information are requested, batch your tool calls together for optimal performance. ALWAYS run the following commands in parallel:
   - Add relevant untracked files to the staging area.
   - Create the commit with a message ending with:
   🤖 Generated with [Metis]

   Co-Authored-By: Metis <noreply@metis.com>
   - Run git status to make sure the commit succeeded.
4. If the commit fails due to pre-commit hook changes, retry the commit ONCE to include these automated changes. If it fails again, it usually means a pre-commit hook is preventing the commit. If the commit succeeds but you notice that files were modified by the pre-commit hook, you MUST amend your commit to include them.

Important notes:
- NEVER update the git config
- NEVER run additional commands to read or explore code, besides git bash commands
- NEVER use the TodoWrite or Task tools
- DO NOT push to the remote repository unless the user explicitly asks you to do so
- IMPORTANT: Never use git commands with the -i flag (like git rebase -i or git add -i) since they require interactive input which is not supported.
- If there are no changes to commit (i.e., no untracked files and no modifications), do not create an empty commit
- In order to ensure good formatting, ALWAYS pass the commit message via a HEREDOC, a la this example:
<example>
git commit -m \"$(cat <<'EOF'
   Commit message here.

   🤖 Generated with [Claude Code](https://claude.ai/code)

   Co-Authored-By: Metis <noreply@metis.com>
   EOF
   )\"
</example>

# Creating pull requests
Use the gh command via the Bash tool for ALL GitHub-related tasks including working with issues, pull requests, checks, and releases. If given a Github URL use the gh command to get the information needed.

IMPORTANT: When the user asks you to create a pull request, follow these steps carefully:

1. You have the capability to call multiple tools in a single response. When multiple independent pieces of information are requested, batch your tool calls together for optimal performance. ALWAYS run the following bash commands in parallel using the Bash tool, in order to understand the current state of the branch since it diverged from the main branch:
   - Run a git status command to see all untracked files
   - Run a git diff command to see both staged and unstaged changes that will be committed
   - Check if the current branch tracks a remote branch and is up to date with the remote, so you know if you need to push to the remote
   - Run a git log command and `git diff [base-branch]...HEAD` to understand the full commit history for the current branch (from the time it diverged from the base branch)
2. Analyze all changes that will be included in the pull request, making sure to look at all relevant commits (NOT just the latest commit, but ALL commits that will be included in the pull request!!!), and draft a pull request summary
3. You have the capability to call multiple tools in a single response. When multiple independent pieces of information are requested, batch your tool calls together for optimal performance. ALWAYS run the following commands in parallel:
   - Create new branch if needed
   - Push to remote with -u flag if needed
   - Create PR using gh pr create with the format below. Use a HEREDOC to pass the body to ensure correct formatting.
<example>
gh pr create --title \"the pr title\" --body \"$(cat <<'EOF'
## Summary
<1-3 bullet points>

## Test plan
[Checklist of TODOs for testing the pull request...]

🤖 Generated with [Metis]
EOF
)\"
</example>

Important:
- NEVER update the git config
- DO NOT use the TodoWrite or Task tools
- Return the PR URL when you're done, so the user can see it

# Other common operations
- View comments on a Github PR: gh api repos/foo/bar/pulls/123/comments
"""

private let COMMON_GUIDELINES = """
Executes a given bash command in a persistent shell session with optional timeout, ensuring proper handling and security measures.

CRITICAL: Choose the correct execution mode BEFORE executing:
- Set interactive=true for commands that need user input or prompts (npx, npm init, sudo, code generators, installers)
- Set interactive=false (default) for commands where you need to read the output (git status, ls, grep, tests, builds)
- When in doubt, use interactive=true to prevent hanging

Interactive mode (interactive=true):
- Runs with TTY support, user can provide input
- Output is printed to terminal but NOT returned to you
- Use for: npx, npm create, sudo, ssh, project scaffolding, ANY command with "create-" prefix

Non-interactive mode (interactive=false):
- Output is captured and returned to you for analysis
- User cannot provide input - command will HANG if it tries to prompt
- Use for: information queries (git status, ls), builds, tests, file operations

Before executing the command, please follow these steps:

1. Directory Verification:
   - If the command will create new directories or files, first use the LS tool to verify the parent directory exists and is the correct location
   - For example, before running "mkdir foo/bar", first use `listDirectory` to check that "foo" exists and is the intended parent directory

2. Command Execution:
   - Always quote file paths that contain spaces with double quotes (e.g., cd \"path with spaces/file.txt\")
   - After ensuring proper quoting, execute the command.

Usage notes:
  - The command argument is required.
  - It is very helpful if you write a clear, concise description of what this command does in 5-10 words.
  - If the output exceeds 30000 characters, output will be truncated before being returned to you.
  - VERY IMPORTANT: You MUST avoid using search commands like `find` and `grep`. Instead use ${globSearch.name}, ${grepSearch.name} to search. You MUST avoid read tools like `cat`, `head`, `tail`, and `ls`, and use ${fileRead.name}, ${fileBatchRead.name}, ${listDirectory.name} to read files.
  - Try to maintain your current working directory throughout the session by using absolute paths and avoiding usage of `cd`. You may use `cd` if the User explicitly requests it.
"""

// Bash-specific guidelines (for Linux/macOS)
private let BASH_SPECIFIC = """

## Bash Shell Specifics:
  - Use standard Unix commands (ls, grep, sed, awk, etc.)
  - When issuing multiple commands, use the ';' or '&&' operator to separate them. DO NOT use newlines (newlines are ok in quoted strings).
  - Path separator is forward slash (/)
  - Examples:
    - cd \"/Users/name/My Documents\" (correct)
    - cd /Users/name/My Documents (incorrect - will fail)
    - python \"/path/with spaces/script.py\" (correct)
    - python /path/with spaces/script.py (incorrect - will fail)
  <good-example>
  pytest /foo/bar/tests
  </good-example>
  <bad-example>
  cd /foo/bar && pytest tests
  </bad-example>
"""

// PowerShell-specific guidelines (for Windows)
private let POWERSHELL_SPECIFIC = """

## Windows PowerShell Specifics:
  - Use PowerShell cmdlets (Get-ChildItem, Copy-Item, Remove-Item, etc.)
  - Path separator is backslash (\\) but forward slash (/) works in most cases
  - Use semicolon (;) to chain commands
  - Environment variables: use $env:VAR syntax (e.g., $env:USERPROFILE, $env:PATH)
  - String quotes: use single quotes for literals, double quotes for expansion
  - PowerShell supports pipes (|) and powerful object manipulation
  - Examples:
    - cd \"C:\\Program Files\\MyApp\" (correct)
    - Set-Location \"C:\\Program Files\\MyApp\" (PowerShell native)
    - Get-ChildItem -Path . -Recurse -Filter *.txt (find all txt files)
    - $env:USERNAME (get username)
    - (Get-Content file.txt) -replace 'old','new' | Set-Content file.txt (replace text)
  - Common cmdlets:
    - Get-ChildItem (alias: dir, ls): list directory contents
    - Set-Location (alias: cd): change directory
    - Copy-Item (alias: copy, cp): copy files
    - Move-Item (alias: move, mv): move files
    - Remove-Item (alias: del, rm): delete files
    - Get-Content (alias: cat, type): display file contents
    - New-Item: create files/directories
  - PowerShell is case-insensitive but cmdlets use PascalCase by convention
  <good-example>
  python \"C:\\My Scripts\\test.py\"
  Get-ChildItem -Path \"C:\\Projects\" -Recurse
  </good-example>
  <bad-example>
  cd C:\\My Scripts; python test.py
  </bad-example>
"""

// Generate tool description based on OS
private let specificGuidelines = if (InfoUtils.os == "windows") {
    POWERSHELL_SPECIFIC
} else {
    BASH_SPECIFIC
}
private let TOOL_DESCRIPTION = COMMON_GUIDELINES + specificGuidelines

@tool[
    description: "${TOOL_DESCRIPTION}",
    parameters: {
        path: "Directory path for command execution, must be an absolute path",
        command: "The command to execute",
        description: "Optional. Clear, concise description of what this command does in 5-10 words. Examples:\nInput: ls\nOutput: Lists files in current directory\n\nInput: git status\nOutput: Shows working tree status\n\nInput: npm install\nOutput: Installs package dependencies\n\nInput: mkdir foo\nOutput: Creates directory 'foo'",
        interactive: "Optional. When true, run attached to the user's terminal (TTY) to allow interactive input (sudo/ssh/installers). Output is shown directly in terminal and not captured."
    }
]
protected func shellExecute(path: String, command: String, description: Option<String>, interactive: Option<Bool>): String {
    if (InputUtils.confirm("Shell", description ?? "", command) == Confirmation.Deny) {
        return "User denied the operation"
    }

    try {
        let isInteractive = interactive ?? false
        if (isInteractive) {
            // Avoid competing reads from terminal input.
            InputUtils.lockTerminalInput()
            InputUtils.exitRawMode()
            try {
                let exitCode = ShellUtils.executeInteractive(
                    [command],
                    workDir: Path(path),
                    usePowerShellOnWindows: true
                )
                return "Interactive command finished with exit code ${exitCode}."
            } finally {
                InputUtils.enterRawMode()
                InputUtils.unlockTerminalInput()
            }
        } else {
            // Use executeWithTimeout with 3-minute default timeout to prevent hanging on daemon processes
            let (exitCode, stdout, stderr) = ShellUtils.execute(
                [command],
                workDir: Path(path),
                timeout: Duration.second * 180,
                usePowerShellOnWindows: true
            )

            if (exitCode == 0) {
                let outString = stdout.trimAscii()
                PrintUtils.printToolResult(outString)
                return "Command executed successfully, output:\n${outString}"
            } else {
                let errString = stderr.trimAscii()
                PrintUtils.printToolResult(errString)
                return "Command execution failed, error output:\n${errString}"
            }
        }
    } catch (e: ShellTimeoutException) {
        PrintUtils.printToolResult("Timeout")
        return "Command execution timeout after 3 minutes: ${e.message}\n\nThe command appears to be a daemon/server process or is taking too long to execute.\n\nSuggestions:\n1. If this is a server/daemon (like 'python3 -m http.server'), it should be run in the background manually\n2. If the command legitimately needs more time, consider breaking it into smaller steps\n3. Check if the command is stuck waiting for input or has encountered an error"
    } catch (e: Exception) {
        PrintUtils.printToolResult("Exception")
        return "Exception occurred while executing command: ${e}\nCommand: ${command}"
    }
}

@toolset[
    tools: [
        shellExecute
    ]
]
public class ShellTool {
}
