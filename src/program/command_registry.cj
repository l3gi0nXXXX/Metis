package metis.program

import metis.core.config.MetisConfigManager

private func sliceArgs(args: Array<String>, start: Int64): Array<String> {
    if (start >= args.size) {
        return Array<String>()
    }
    args[start..args.size]
}

public func cliDispatchRegisteredRootCommand(args: Array<String>): Option<Int64> {
    match (firstNonFlagToken(args)) {
        case Some((idx, token)) =>
            MetisConfigManager.initializeIfMissing()
            MetisConfigManager.migrateLegacyIfNeeded()
            MetisConfigManager.applyPersistedFieldsToCliConfig()
            let cmd = token.trimAscii().toAsciiLower()
            let tail = sliceArgs(args, idx + 1)
            if (let Some(code) <- cliDispatchGatewayBackedRootCommand(cmd, tail)) {
                return Some(code)
            }
            cliDispatchCoreRootCommand(cmd, tail)
        case None => None
    }
}
