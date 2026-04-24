package metis.utils

import magic.log.LogUtils

import std.process.*
import std.fs.Path
import std.collection.ArrayList
import std.time.*
import std.sync.*
import std.io.*

// Timeout exception for shell command execution
public class ShellTimeoutException <: Exception {
    public init(message: String) {
        super(message)
    }
}

public class ShellUtils {
    private static func buildCommandArgs(command: Array<String>, withWrap: Bool, usePowerShellOnWindows: Bool): (String, Array<String>) {
        if (!withWrap) {
            let args: Array<String> = if (command.size > 1) { command[1..] } else { [] }
            return (command[0], args)
        }
        if (InfoUtils.os == "windows") {
            // 如果在windows上，可以指定使用PowerShell，否则默认使用cmd，其他os上则不受这个参数的影响
            if (usePowerShellOnWindows) {
                return ("powershell", ["-Command", String.join(command, delimiter: " ")])
            } else {
                return ("cmd", ["/c", String.join(command, delimiter: " ")])
            }
        } else {
            return ("sh", ["-c", String.join(command, delimiter: " ")])
        }
    }

    public static func execute(command: Array<String>,
                               timeout!: Option<Duration> = None,
                               workDir!: Option<Path> = None,
                               withWrap!: Bool = true,
                               usePowerShellOnWindows!: Bool = false): (Int64, String, String) {
        let (cmd, cmdArgs) = buildCommandArgs(command, withWrap, usePowerShellOnWindows)

        match (timeout) {
            case None =>
                let (exitCode, stdoutBytes, stderrBytes) = executeWithOutput(
                    cmd,
                    cmdArgs,
                    workingDirectory: workDir
                )
                let stdout = try {
                    String.fromUtf8(stdoutBytes)
                } catch (e: Exception) {
                    LogUtils.debug("[ShellUtils] Failed to decode stdout: ${e}")
                    ""
                }
                let stderr = try {
                    String.fromUtf8(stderrBytes)
                } catch (e: Exception) {
                    LogUtils.debug("[ShellUtils] Failed to decode stderr: ${e}")
                    ""
                }
                if (exitCode != 0) {
                    LogUtils.error("Shell command execution failed: ${exitCode}")
                    LogUtils.error("  ${cmd} ${String.join(cmdArgs, delimiter: ' ')}")
                }
                return (exitCode, stdout, stderr)
            case Some(_) => ()
        }

        let process = launch(
            cmd,
            cmdArgs,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe,
            workingDirectory: workDir
        )

        let stdoutFuture = spawn {
            let reader = StringReader(process.stdOutPipe)
            try {
                return reader.readToEnd()
            } catch (e: Exception) {
                LogUtils.debug("[ShellUtils] Failed to read stdout: ${e}")
                return ""
            }
        }
        let stderrFuture = spawn {
            let reader = StringReader(process.stdErrPipe)
            try {
                return reader.readToEnd()
            } catch (e: Exception) {
                LogUtils.debug("[ShellUtils] Failed to read stderr: ${e}")
                return ""
            }
        }

        try {
            let exitCode = process.wait(timeout: timeout)
            let stdout = try {
                stdoutFuture.get()
            } catch (e: Exception) {
                LogUtils.debug("[ShellUtils] Failed to collect stdout: ${e}")
                ""
            }
            let stderr = try {
                stderrFuture.get()
            } catch (e: Exception) {
                LogUtils.debug("[ShellUtils] Failed to collect stderr: ${e}")
                ""
            }

            if (exitCode != 0) {
                LogUtils.error("Shell command execution failed: ${exitCode}")
                LogUtils.error("  ${cmd} ${String.join(cmdArgs, delimiter: ' ')}")
            }
            return (exitCode, stdout, stderr)
        } catch(ex: TimeoutException) {
            try {
                process.terminate(force: true)
            } catch (terminateErr: Exception) {
                LogUtils.debug("[ShellUtils] Failed to terminate process after timeout: ${terminateErr}")
            }
            // Ensure pipe readers exit before bubbling up
            try { stdoutFuture.get() } catch (_: Exception) { }
            try { stderrFuture.get() } catch (_: Exception) { }
            throw ShellTimeoutException("Shell command execution timed out")
        }
    }

    /**
     * Execute a command attached to the current terminal (no output capture).
     */
    public static func executeInteractive(command: Array<String>,
                                          timeout!: Option<Duration> = None,
                                          workDir!: Option<Path> = None,
                                          withWrap!: Bool = true,
                                          usePowerShellOnWindows!: Bool = false): Int64 {
        let (cmd, cmdArgs) = buildCommandArgs(command, withWrap, usePowerShellOnWindows)

        let process = launch(
            cmd,
            cmdArgs,
            stdIn: Inherit,
            stdOut: Inherit,
            stdErr: Inherit,
            workingDirectory: workDir
        )

        try {
            return process.wait(timeout: timeout)
        } catch(ex: TimeoutException) {
            try {
                process.terminate(force: true)
            } catch (terminateErr: Exception) {
                LogUtils.debug("[ShellUtils] Failed to terminate interactive process after timeout: ${terminateErr}")
            }
            throw ShellTimeoutException("Interactive shell command execution timed out")
        }
    }
}
