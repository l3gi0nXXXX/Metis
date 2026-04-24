package metis

import magic.log.LogUtils

import metis.cliapp.CliApp
import metis.core.config.CliConfig
import metis.gateway.runtime.{gatewayInvokeCliAgent, runFeishuWebhookGatewayService, runGatewayP0Demo, runGatewayP1DemoWithFeishuWebhook}
import metis.io.PrintUtils
import metis.io.InputUtils
import metis.program.{CLI_EXIT_OK, CLI_EXIT_USAGE_ERROR, cliDispatchProgramFastPath, cliProgramCommandArgs, cliProgramInteractiveMode, cliProgramShouldEnterInteractive,
    createCliProgramContext, printRootHelp, runConfigureModelWizard, runOnboardWizard}
import metis.sandbox.startSandbox

import std.collection.{collectArray, filter}
import std.env.getVariable

private func cliParseProgramArgs(cliArgs: Array<String>): Option<Int64> {
    match (parseArgsAndSetConfig(cliArgs)) {
        case ParseArgsResult.Exit => Some(CLI_EXIT_OK)
        case ParseArgsResult.Continue => None
        case ParseArgsResult.Sandbox =>
            if (getVariable("MAGIC_CLI_IN_SANDBOX").isNone()) {
                let sandboxArgs = cliArgs |> filter { arg => arg != "--sandbox" } |> collectArray
                return Some(startSandbox(sandboxArgs))
            }
            None
    }
}

private func cliRunInteractiveApp(mode: String): Int64 {
    InputUtils.enterRawMode()
    if (mode == "onboard") {
        let wizardCode = runOnboardWizard()
        if (wizardCode != CLI_EXIT_OK) {
            InputUtils.exitRawMode()
            return wizardCode
        }
    } else if (mode == "configure") {
        let wizardCode = runConfigureModelWizard()
        if (wizardCode != CLI_EXIT_OK) {
            InputUtils.exitRawMode()
            return wizardCode
        }
    }
    let app = CliApp()
    if (mode == "setup" || mode == "onboard") {
        initSettingGuideline()
    }
    app.startInteractive(mode: mode)
    CLI_EXIT_OK
}

private func cliRunProgramDemos(): Option<Int64> {
    if (CliConfig.gatewayP0Demo) {
        runGatewayP0Demo()
        return Some(CLI_EXIT_OK)
    }
    if (CliConfig.gatewayP1Demo) {
        runGatewayP1DemoWithFeishuWebhook()
        return Some(CLI_EXIT_OK)
    }
    if (CliConfig.gatewayFeishuWebhook) {
        runFeishuWebhookGatewayService()
        return Some(CLI_EXIT_OK)
    }
    None
}

public func runCliProgram(args: Array<String>): Int64 {
    let ctx = createCliProgramContext(args)
    if (let Some(code) <- cliDispatchProgramFastPath(ctx)) {
        return code
    }

    let cliArgs = cliProgramCommandArgs(ctx)
    if (let Some(code) <- cliParseProgramArgs(cliArgs)) {
        return code
    }
    LogUtils.debug(CliConfig.toString())

    if (let Some(code) <- cliRunProgramDemos()) {
        return code
    }

    if (!cliProgramShouldEnterInteractive(ctx) && CliConfig.nonInteractive) {
        let (ok, answer, err) = gatewayInvokeCliAgent(CliConfig.nonInteractivePrompt, sessionKey: "main", channel: "cli")
        if (!ok) {
            PrintUtils.printLine("Gateway agent failed: ${err}")
            PrintUtils.printLine("Start the unified Gateway main runtime with `metis gateway run`, or use `metis agent --local --message \"...\"` for explicit embedded mode.")
            return CLI_EXIT_USAGE_ERROR
        }
        PrintUtils.printLine(answer)
        return CLI_EXIT_OK
    }
    if (!cliProgramShouldEnterInteractive(ctx)) {
        printRootHelp()
        return CLI_EXIT_OK
    }
    cliRunInteractiveApp(cliProgramInteractiveMode(ctx))
}
