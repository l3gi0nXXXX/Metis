package metis.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.jsonable.*

import metis.core.tools.cj_utils.{
    CangjieDocAgent,
    cangjieDocAnswerWithDefaultModel,
    cjcRun,
    cjpmBuild,
    cjpmRun,
    hasContext7ApiKey,
}
import metis.core.config.CliConfig
import metis.io.PrintUtils
import metis.utils.*

import magic.log.LogUtils

import std.collection.*
import stdx.encoding.json.*
import std.fs.*

@toolset
public class CangjieToolset {
    protected CangjieToolset(
        private let buildWithJsonOutput!: Bool = false
    ) { }

    @tool[
        description: "An tool specialized in the Cangjie programming language, capable of retrieving Cangjie language documentation based on user queries. ",
        parameters: {
            query: "Input user query: Topics to focus documentation on (e.g., 'hooks', 'routing')"
        }
    ]
    public func cangjieRetrieveDocuments(query: String): String {
        if (!hasContext7ApiKey()) {
            PrintUtils.printTool("Cangjie Docs（未配置 CONTEXT7_API_KEY，使用当前对话模型）", longMessage: query)
            let result = cangjieDocAnswerWithDefaultModel(query)
            PrintUtils.printToolResult(result)
            return result
        }
        PrintUtils.printTool("Cangjie Docs via Context7", longMessage: query)
        try {
            let agent = CangjieDocAgent()
            let result = agent.chat(query)
            PrintUtils.printToolResult(result)
            return result
        } catch (e: Exception) {
            LogUtils.info("Cangjie Context7 / DocAgent failed, fallback to default model: ${e.message}")
            PrintUtils.printTool("Cangjie Docs（Context7 不可用，改用当前对话模型）", longMessage: query)
            let result = cangjieDocAnswerWithDefaultModel(query)
            PrintUtils.printToolResult(result)
            return result
        }
    }

    @tool[
        description: "Initialize a new Cangjie project in the specified directory.",
        parameters: {
            path: "Path to the Cangjie module, must be an absolute path. If omitted, the current working directory will be used to initialized.",
            projectType: "Type of the Cangjie project to initialize. If omitted, default value 'executable' will be used. Valid values are 'executable', 'static' for static library or 'dynamic' for dynamic library."
        }
    ]
    public func cangjieInitProject(path: Option<String>, projectType: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        // Since Cangjie project name must be of camel case, we convert directory name to camel case
        let packageName = CangjieToolset.toCamelCase(projectDir.fileName)
        let args: Array<String> = ["init", "--name", packageName, "--type", projectType ?? "executable"]

        PrintUtils.printTool("cjpm init", shortMessage: projectDir.toString())
        let result = cjpmRun(args, projectDir)
        return "${result}\n\nThe root package name of the new project is: ${packageName}"
    }

    @tool[
        description: "Compile a single Cangjie file in the specified directory, generating an executable file main",
        parameters: {
            path: "Path to the Cangjie file to be compile, must be an absolute path"
        }
    ]
    public func cangjieCompileFile(path: String): String {
        let filePath = Path(path)

        PrintUtils.printTool("cjc compile", shortMessage: filePath.toString())
        let result = cjcRun([filePath.fileName], filePath.parent)
        PrintUtils.printToolResult(result)
        return result
    }

    @tool[
        description: "Compile the Cangjie module at the specified path. Option to choose incremental compilation for faster speed.",
        parameters: {
            path: "Path to the Cangjie module, must be an absolute path. If omitted, the current working directory will be used."
        }
    ]
    public func cangjieBuildProject(path: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd

        PrintUtils.printTool("cjpm build", shortMessage: projectDir.toString())
        let result = cjpmBuild(projectDir, outputJson: this.buildWithJsonOutput)
        PrintUtils.printToolResult(result.rawOutput)
        return result.processedOutput
    }

    // @tool[
    //     description: "Compile and run an executable artifact with the specified name.",
    //     parameters: {
    //         path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used.",
    //         name: "Name of the executable artifact to run. If omitted, the default `main.exe` will be run."
    //     }
    // ]
    public func cangjieRunProject(path: Option<String>, name: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        let execName = name ?? "main"

        let args: Array<String> = ["run", "--name", execName]
        PrintUtils.printTool("cjpm run", shortMessage: "${projectDir.toString()} --name ${execName}")
        let result = cjpmRun(args, projectDir)
        PrintUtils.printToolResult(result)
        return result
    }

    @tool[
        description: "Clean the target directory, removing all previously built artifacts.",
        parameters: {
            path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used."
        }
    ]
    public func cangjieCleanProject(path: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        PrintUtils.printTool("cjpm clean", shortMessage: projectDir.toString())
        return cjpmRun(["clean"], projectDir)
    }

    private static func toCamelCase(dirName: String): String {
        let normalized = dirName.replace("-", " ").replace("_", " ")
        let words = normalized.split(' ')
        let result = StringBuilder()

        for (i in 0..words.size) {
            let word = words[i].trimAscii()
            if (!word.isEmpty()) {
                if (result.size == 0) { // The first word
                    result.append(word.toAsciiLower())
                } else { // other words
                    result.append(word.toAsciiTitle())
                }
            }
        }
        return result.toString()
    }
}
