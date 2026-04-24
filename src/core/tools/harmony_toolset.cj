package metis.core.tools

import std.env.*
import std.process.*
import std.collection.*
import magic.dsl.*
import magic.prelude.*

@toolset
public class HarmonyToolset {
    @tool[
        description: "Install third-party library dependencies for the project and its modules. This command needs to be executed in the project and each module directory before building from command line.",
        parameters: {}
    ]
    func ohpm_install(): String {
        try {
            let cmd = "ohpm"
            let args: Array<String> = ["install", "--all"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Clean the project build artifacts, removing previously compiled files.",
        parameters: {}
    ]
    func hvigorw_clean(): String {
        try {
            let cmd = "hvigorw"
            let args: Array<String> = ["clean", "--no-daemon"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Build Hap application. Hap is the basic installation unit for HarmonyOS applications. This command compiles modules and generates .hap files.",
        parameters: {
            product: "Product name to build (e.g., default, phone, tablet)",
            build_mode: "Build mode (debug or release)"
        }
    ]
    func hvigorw_assemble_hap(product: String, build_mode: String): String {
        try {
            let cmd = "hvigorw"
            let args: Array<String> = ["assembleHap", "--mode module", "-p product=${product}",
                "-p buildMode=${build_mode}", "--no-daemon"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Build App application, generating the final .app file containing all Hap packages and descriptor files.",
        parameters: {
            product: "Product name to build (e.g., default, phone, tablet)",
            build_mode: "Build mode (debug or release)"
        }
    ]
    func hvigorw_assemble_app(product: String, build_mode: String): String {
        try {
            let cmd = "hvigorw"
            let args: Array<String> = ["assembleApp", "--mode project", "-p product=${product}",
                "-p buildMode=${build_mode}", "--no-daemon"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Query and list all currently connected devices and emulators. Use this command to get the target device serial number (SN) before deploying and debugging applications.",
        parameters: {}
    ]
    func hdc_list_devices(): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["list targets"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Push local file to specified remote device path. This is the first step for installing or storing files on the device.",
        parameters: {
            device_sn: "Serial number of the target device",
            local_file_path: "Path to the local file to send",
            remote_device_path: "Destination path on the remote device"
        }
    ]
    func hdc_file_send(device_sn: String, local_file_path: String, remote_device_path: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["-t", device_sn, "file", "send", local_file_path, remote_device_path]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Install a signed HAP package to a physical device using HDC (HarmonyOS Device Connector) tool.",
        parameters: {
            hap_path: "Path to the HAP file on the device (after file send)"
        }
    ]
    func hdc_install_hap(hap_path: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["shell", "bm", "install", "-p", hap_path]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Install one or more .hap files to the specified device. This is a key step for deploying built applications to physical devices or emulators for testing. Requires device serial number and HAP file path.",
        parameters: {
            device_sn: "Serial number of the target device",
            hap_file: "Path to the HAP file to install"
        }
    ]
    func hdc_install_app(device_sn: String, hap_file: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["-t", device_sn, "install", hap_file]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Uninstall an application from the specified device. Requires the application's bundle name.",
        parameters: {
            device_sn: "Serial number of the target device",
            bundle_name: "Bundle name of the application to uninstall"
        }
    ]
    func hdc_uninstall_app(device_sn: String, bundle_name: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["-t", device_sn, "shell", "bm", "uninstall", "-n", bundle_name]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Force stop an application process running on the specified device. Requires the application's bundle name.",
        parameters: {
            device_sn: "Serial number of the target device",
            bundle_name: "Bundle name of the application to terminate"
        }
    ]
    func hdc_terminate_app(device_sn: String, bundle_name: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["-t", device_sn, "shell", "aa", "force-stop", bundle_name]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Start a specific Ability within an application using hdc shell command. This is useful for automated testing or directly navigating to specific application pages.",
        parameters: {
            device_sn: "Serial number of the target device",
            ability_name: "Name of the Ability to start",
            bundle_name: "Bundle name of the application containing the Ability"
        }
    ]
    func hdc_start_ability(device_sn: String, ability_name: String, bundle_name: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["-t", device_sn, "shell", "aa", "start", "-a", ability_name, "-b", bundle_name]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "View real-time logs (hilog) from the specified device. This is a core tool for debugging applications, analyzing crashes, and monitoring application behavior. Can be filtered by tag or level.",
        parameters: {
            device_sn: "Serial number of the target device",
            tag: "Log tag to filter (leave empty for all logs)"
        }
    ]
    func hdc_view_logs(device_sn: String, tag: String): String {
        try {
            let cmd = "hdc"
            let args: Array<String> = ["-t", device_sn, "hilog", "-T", tag]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Task executed successfully"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }
}
