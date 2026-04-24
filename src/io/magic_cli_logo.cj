package metis.io

import std.collection.*
import metis.core.config.CliConfig

let title = "🫍 Metis"
let version = CliConfig.version

private let LOBSTER_ASCII = [
    "              #%%%%   #%%%%%%%%%%%%%*",
    "               =%%%@%%%%%%%%%%%%%%%%%%@",
    "                @%%%+    %%%%%%%%%%%%%%%",
    "               #%%+     %%:@@%%%%%%%%%%%%",
    "             :%%%%%%@@%%%*@%%%%%%%%%%%%%%",
    "             %%%%%%%%%=                 #",
    "            @%%%%%%%@           =.+****:        ███╗   ███╗███████╗████████╗██╗███████╗",
    "            %%%%%%%@                  +         ████╗ ████║██╔════╝╚══██╔══╝██║██╔════╝",
    "            %%%%%%%%@               ::          ██╔████╔██║█████╗     ██║   ██║███████╗",
    "            %%%%%%%%%              %%           ██║╚██╔╝██║██╔══╝     ██║   ██║╚════██║",
    "            %@%%%%@             +%%%%%          ██║ ╚═╝ ██║███████╗   ██║   ██║███████║",
    "           %%%%%%%           *  -%%%%%%",
    "          *%%%%*%%         -     #%%%%%%                 ${title} ${version}",
    "          %%%%           %         %%%%%",
    "         @%%* %%%=     :%           @%%%+",
    "        :%%    %%%#   -%             *%%",
    "               %%%%%%%+",
    "                %%%%%%=",
    "                +%%%%%%-",
    "              *%%%%%%%%%%%*",
    "            +%%%%%%%%%%%%%%%*",
    "           %%%%%%%%@@%%%%%%%%@",
    "          %%%*:",
    " "
]

private func colorBannerRune(ch: Rune): String {
    if (ch == r'█') {
        return "█".withColor(Theme.ACCENT)
    }
    if (ch == r'░') {
        return "░".withColor(Theme.MUTED)
    }
    if (ch == r'▀') {
        return "▀".withColor(Theme.PRIMARY)
    }
    if (ch == r'#' || ch == r'%' || ch == r'=' || ch == r'@' || ch == r'*' || ch == r'+' || ch == r':' || ch == r'.' || ch == r'-') {
        return ch.toString().withColor(Theme.ACCENT)
    }
    return ch.toString().withColor(Theme.MUTED)
}

private func formatBannerArt(): Array<String> {
    let lines = ArrayList<String>()
    for (line in LOBSTER_ASCII) {
        var rendered = ""
        for (ch in line.runes()) {
            rendered += colorBannerRune(ch)
        }
        lines.add(rendered)
    }
    return lines.toArray()
}

public func printMagicCliLogo() {
    PrintUtils.printLine("")
    for (line in formatBannerArt()) {
        PrintUtils.printLine(line)
    }
    PrintUtils.printLine("")
}
