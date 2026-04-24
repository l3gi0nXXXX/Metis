package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.io.{InputUtils, PrintUtils, Confirmation}
import metis.utils.{ShellUtils, ShellTimeoutException}

import std.fs.Path

@tool[
    description: "Executes a shell command inside an absolute working directory with optional interactive mode.",
    parameters: {
        path: "Absolute working directory path.",
        command: "Shell command to execute.",
        description: "Optional short description shown to the user before confirmation.",
        interactive: "Optional. When true, run attached to the terminal."
    }
]
protected func shellExecute(path: String, command: String, description: Option<String>, interactive: Option<Bool>): String {
    if (InputUtils.confirm("Shell", description ?? "", command) == Confirmation.Deny) {
        return "User denied the operation"
    }

    try {
        let isInteractive = interactive ?? false
        if (isInteractive) {
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
        }

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
        }
        let errString = stderr.trimAscii()
        PrintUtils.printToolResult(errString)
        return "Command execution failed, error output:\n${errString}"
    } catch (e: ShellTimeoutException) {
        PrintUtils.printToolResult("Timeout")
        return "Command execution timeout after 3 minutes: ${e.message}"
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
public class GatewayShellToolset {
}
