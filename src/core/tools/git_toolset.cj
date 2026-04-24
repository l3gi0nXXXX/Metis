package metis.core.tools

import magic.dsl.*
import magic.prelude.*

import metis.io.PrintUtils

import std.env.*
import std.process.*
import std.io.*
import std.fs.*

@toolset
public class GitToolset {
    @tool[
        description: "Initialize a new Git repository in the specified directory",
        parameters: { path: "Directory path to initialize Git repository, must be an absolute path" }
    ]
    public func gitInit(path: String): String {
        PrintUtils.printTool("Git Init", shortMessage: path)

        try {
            let cmd = "git"
            let args: Array<String> = ["init"]

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Git repository initialized successfully."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Clone remote Git repository to local specified directory",
        parameters: { url: "Remote repository URL", path: "Local target directory path, must be an absolute path" }
    ]
    public func gitClone(url: String, path: String): String {
        PrintUtils.printTool("Git Clone", longMessage: "${url} -> ${path}")

        try {
            let cmd = "git"
            let args: Array<String> = ["clone", url]

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Repository cloned successfully."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Add files or directories to Git staging area",
        parameters: { path: "Working directory path, must be an absolute path", files: "Files or directories to add, use . for all files" }
    ]
    public func gitAdd(path: String, files: String): String {
        PrintUtils.printTool("Git Add", longMessage: "${path} - ${files}")

        try {
            let cmd = "git"
            let args: Array<String> = ["add", files]

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Files added to staging area."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Commit staged changes to local repository",
        parameters: { path: "Working directory path, must be an absolute path", message: "Commit message" }
    ]
    public func gitCommit(path: String, message: String): String {
        PrintUtils.printTool("Git Commit", longMessage: "${path} - ${message}")

        try {
            let cmd = "git"
            let args: Array<String> = ["commit", "-m", message]

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Commit successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Push local repository changes to remote repository",
        parameters: { path: "Working directory path, must be an absolute path", remote: "Remote repository name, default is origin", branch: "Branch name, default is current branch" }
    ]
    public func gitPush(path: String, remote: String, branch: String): String {
        PrintUtils.printTool("Git Push", longMessage: "${path} - ${remote} ${branch}")

        try {
            let cmd = "git"
            var args: Array<String> = ["push"]

            if (remote != "") {
                args = ["push", remote]
                if (branch != "") {
                    args = ["push", remote, branch]
                }
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Push successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Pull latest changes from remote repository",
        parameters: { path: "Working directory path, must be an absolute path", remote: "Remote repository name, default is origin", branch: "Branch name, default is current branch" }
    ]
    public func gitPull(path: String, remote: String, branch: String): String {
        PrintUtils.printTool("Git Pull", longMessage: "${path} - ${remote} ${branch}")

        try {
            let cmd = "git"
            var args: Array<String> = ["pull"]

            if (remote != "") {
                args = ["pull", remote]
                if (branch != "") {
                    args = ["pull", remote, branch]
                }
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Pull successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "View current status of Git repository",
        parameters: { path: "Working directory path, must be an absolute path" }
    ]
    public func gitStatus(path: String): String {
        PrintUtils.printTool("Git Status", shortMessage: path)

        try {
            let cmd = "git"
            let args: Array<String> = ["status"]

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                return outputString
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Manage Git branches, including create, switch, delete and list branches",
        parameters: { path: "Working directory path, must be an absolute path", action: "Action type: list, create, delete", branchName: "Branch name (required for create or delete)" }
    ]
    public func gitBranch(path: String, action: String, branchName: String): String {
        PrintUtils.printTool("Git Branch", longMessage: "${path} - ${action} ${branchName}")

        try {
            let cmd = "git"
            var args: Array<String> = ["branch"]

            if (action == "create" && branchName != "") {
                args = ["branch", branchName]
            } else if (action == "delete" && branchName != "") {
                args = ["branch", "-d", branchName]
            } else if (action == "list" || action == "") {
                args = ["branch", "-a"]
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Operation successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Checkout to specified branch or commit",
        parameters: { path: "Working directory path, must be an absolute path", target: "Target branch name or commit hash", createNew: "Whether to create new branch (true/false)" }
    ]
    public func gitCheckout(path: String, target: String, createNew: Bool): String {
        PrintUtils.printTool("Git Checkout", longMessage: "${path} - ${target}")

        try {
            let cmd = "git"
            var args: Array<String> = ["checkout", target]

            if (createNew == true) {
                args = ["checkout", "-b", target]
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Checkout successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Merge specified branch into current branch",
        parameters: { path: "Working directory path, must be an absolute path", branch: "Branch name to merge" }
    ]
    public func gitMerge(path: String, branch: String): String {
        PrintUtils.printTool("Git Merge", longMessage: "${path} - ${branch}")

        try {
            let cmd = "git"
            let args: Array<String> = ["merge", branch]

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Merge successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "View Git commit history",
        parameters: { path: "Working directory path, must be an absolute path", limit: "Limit number of commits to display, default is all" }
    ]
    public func gitLog(path: String, limit: Int64): String {
        PrintUtils.printTool("Git Log", shortMessage: path)

        try {
            let cmd = "git"
            var args: Array<String> = ["log", "--oneline"]

            if (limit > 0) {
                args = ["log", "--oneline", "-n", limit.toString()]
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                return outputString
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "View differences between working area, staging area or commits",
        parameters: { path: "Working directory path, must be an absolute path", staged: "Whether to view staged differences (true/false)", target: "Target for comparison (branch name or commit hash, optional)" }
    ]
    public func gitDiff(path: String, staged: Bool, target: String): String {
        PrintUtils.printTool("Git Diff", shortMessage: path)

        try {
            let cmd = "git"
            var args: Array<String> = ["diff"]

            if (staged == true) {
                args = ["diff", "--staged"]
            } else if (target != "") {
                args = ["diff", target]
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "No differences."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Stash current working area changes",
        parameters: { path: "Working directory path, must be an absolute path", action: "Action type: save, pop, list, clear", message: "Stash message (optional for save)" }
    ]
    public func gitStash(path: String, action: String, message: String): String {
        PrintUtils.printTool("Git Stash", longMessage: "${path} - ${action}")

        try {
            let cmd = "git"
            var args: Array<String> = ["stash"]

            if (action == "save" || action == "") {
                if (message != "") {
                    args = ["stash", "save", message]
                } else {
                    args = ["stash"]
                }
            } else if (action == "pop") {
                args = ["stash", "pop"]
            } else if (action == "list") {
                args = ["stash", "list"]
            } else if (action == "clear") {
                args = ["stash", "clear"]
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Operation successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Reset current branch to specified state",
        parameters: { path: "Working directory path, must be an absolute path", mode: "Reset mode: soft (keep changes in staging area), mixed (keep changes in working area), hard (discard all changes)", target: "Target commit (default is HEAD)" }
    ]
    public func gitReset(path: String, mode: String, target: String): String {
        PrintUtils.printTool("Git Reset", longMessage: "${path} - ${mode} ${target}")

        try {
            let cmd = "git"
            var args: Array<String> = ["reset"]
            let resetTarget = if (target == "") { "HEAD" } else { target }

            if (mode == "soft") {
                args = ["reset", "--soft", resetTarget]
            } else if (mode == "hard") {
                args = ["reset", "--hard", resetTarget]
            } else {
                args = ["reset", "--mixed", resetTarget]
            }

            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Reset successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }
}