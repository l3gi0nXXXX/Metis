package metis.utils

protected class InfoUtils {
    @When[os == "Linux"]
    public static let os = "linux"

    @When[os == "Windows"]
    public static let os = "windows"

    @When[os == "macOS"]
    public static let os = "macos"

    @When[os != "Linux" && os != "Windows" && os != "macOS"]
    public static let os = "unknown"

    @When[arch == "aarch64"]
    public static let arch = "aarch64"

    @When[arch == "x86_64"]
    public static let arch = "x64"

    @When[arch != "x86_64" && arch != "aarch64"]
    public static let arch = "unknown"
}