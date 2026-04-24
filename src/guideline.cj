package metis

import magic.config.Config
import magic.log.LogUtils

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}
import metis.io.{InputUtils, PrintUtils}
import metis.core.tools.fs_utils.writeFileBasic

import std.fs.{exists, File, Path, Directory}
import std.regex.Regex

func initSettingGuideline(): Unit {
    if (exists(MetisConfigManager.configPath())) {
        if (CliSettingManager.setting.language == "unknown" && CliConfig.language == "unknown") {
            CliConfig.language = "cangjie"
        }
        return
    }
    // Load the settings
    if (CliSettingManager.setting.language == "unknown" && CliConfig.language == "unknown") {
        let index = InputUtils.getOptions(
            ["Cangjie", "Others"],
            prompt: "Which programming language will be used (for this project). Default: Cangjie."
        ) ?? 0
        match (index) {
            case 0 =>
                let _ = MetisConfigManager.setLanguage("cangjie")
            case 1 =>
                let _ = MetisConfigManager.setLanguage("general")
            case _ => throw UnsupportedException("Unreachable")
        }
    }
}
