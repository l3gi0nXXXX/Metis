package metis.sandbox

import magic.log.LogUtils

import metis.utils.InfoUtils

/**
 * Main sandbox start function
 */
protected func startSandbox(cliArgs: Array<String>): Int64 {
    if (InfoUtils.os == "macos") {
        return startSandbox(SandboxConfig("sandbox-exec", ""), cliArgs)
    } else {
        return startSandbox(SandboxConfig("docker", "magic-cli"), cliArgs)
    }
}

protected func startSandbox(config: SandboxConfig, cliArgs: Array<String>): Int64 {
    try {
        LogUtils.info("Entering sandbox (command: ${config.command}) ...")
        if (config.command == "sandbox-exec") {
            // macOS Seatbelt sandbox implementation
            return startMacOSSandbox(config, cliArgs)
        } else {
            // Docker/Podman sandbox implementation
            return startContainerSandbox(config, cliArgs)
        }
    } catch (ex: FatalSandboxError) {
        throw ex
    } catch (ex: Exception) {
        throw FatalSandboxError("Sandbox execution failed: ${ex.message}")
    }
}