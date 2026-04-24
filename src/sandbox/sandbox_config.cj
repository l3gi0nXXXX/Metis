package metis.sandbox

import std.env.getTempDirectory

/**
 * Configuration classes
 */
public class SandboxConfig {
    public let command: String
    public let image: String

    public init(command: String, image: String) {
        this.command = command
        this.image = image
    }

    static prop TMP_DIR: String {
        get() {
            return "/tmp"
        }
    }

    static let HOME_DIR = "/home/magic-cli"

    static let WORK_DIR = "/workspace"
}
