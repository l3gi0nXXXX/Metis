package metis.sandbox

import metis.core.config.CliConfig
import magic.log.LogUtils

import std.fs.*
import std.collection.{HashMap, ArrayList}
import std.process.launch
import std.env.{getVariable, getVariables, getCommand}

/**
 * macOS Seatbelt sandbox implementation
 */
func startMacOSSandbox(config: SandboxConfig, cliArgs: Array<String>): Int64 {
    // Check for BUILD_SANDBOX conflict
    if (getVariable("BUILD_SANDBOX").isSome()) {
        throw FatalSandboxError("Cannot BUILD_SANDBOX when using macOS Seatbelt")
    }

    let whichProfile = getVariable("SEATBELT_PROFILE") ?? "permissive-open"
    let profile = SEATBELT_PROFILES.get(whichProfile).getOrThrow( { =>
        throw FatalSandboxError("Missing macos seatbelt profile '${whichProfile}'")
    })

    let profilePath = CliConfig.dotDir.join("sandbox-macos-${whichProfile}.sb")
    try (file = File(profilePath, OpenMode.Write)) {
        file.write(profile.toArray())
        file.flush()
    }
    LogUtils.info("Using macos seatbelt (profile: ${profilePath}) ...")

    // Build the magic-cli start command
    // Set environment variables
    let magicCliStartCommand = ArrayList([
        "MAGIC_CLI_IN_SANDBOX=sandbox-exec" // Put the mark env
    ])
    // Inherit environment variables
    for ((env, value) in getVariables()) {
        magicCliStartCommand.add("${env}='${value}'")
    }
    // Add magic-cli command
    magicCliStartCommand.add(getCommand())
    // Add command line arguments
    for (arg in cliArgs) {
        magicCliStartCommand.add("'${arg}'")
    }

    // Build sandbox-exec arguments
    let sandboxExecArgs = [
        "-D",
        "WORK_DIR=${CliConfig.cwd}",
        "-D",
        "TMP_DIR=${SandboxConfig.TMP_DIR}", // Not works currently
        // "-D",
        // "HOME_DIR=${SandboxConfig.HOME_DIR}",
        "-f", profilePath.toString(),
        "sh", "-c", String.join(magicCliStartCommand.toArray(), delimiter: " ")
    ]
    LogUtils.trace("[sandbox] ${config.command} ${String.join(sandboxExecArgs, delimiter: " ")}")
    // println("[sandbox] ${config.command} ${String.join(sandboxExecArgs, delimiter: " ")}")
    // Start sandbox process
    let sandboxProcess = launch(config.command, sandboxExecArgs, stdIn: Inherit, stdOut: Inherit, stdErr: Inherit)

    return sandboxProcess.wait()
}
