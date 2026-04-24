package metis.core.tools.cj_utils

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.core.message.{Message, MessageList}
import magic.model.ModelUtils

import metis.core.config.{CliConfig, MetisConfigManager}
import metis.core.model.CliModelManager
import metis.io.{PrintUtils, WithColor, AnsiColor}

private let CANGJIE_CONTEXT7_PROMPT = """
You are an intelligent assistant for the Cangjie programming language. You have access to two tools:

- `queryCangjie(query: str)`: Use this tool to search general Cangjie language documentation (e.g., syntax, core features, standard library).
- `queryCangjieStdExtension(query: str)`: Use this tool **only** to search documentation for packages in the `stdx` (Cangjie Standard Library Extension).

The `stdx` extension includes the following packages:
- `aspectCJ`: Aspect-oriented programming (AOP) capabilities.
- `compress.zlib`: Compression and decompression.
- `crypto.crypto`: Secure encryption.
- `crypto.digest`: Message digest algorithms.
- `crypto.keys`: Asymmetric encryption and signing.
- `crypto.x509`: Digital certificate handling.
- `encoding.base64`: Base64 encoding/decoding.
- `encoding.hex`: Hex encoding/decoding.
- `encoding.json`: JSON processing (String, JsonValue, DataModel conversion).
- `encoding.json.stream`: JSON stream serialization/deserialization.
- `encoding.url`: URL parsing, encoding/decoding, and path resolution.
- `fuzz.fuzz`: Coverage-guided fuzz testing engine.
- `log`: Logging functionality.
- `logger`: Text and JSON log printing.
- `net.http`: HTTP/1.1, HTTP/2, and WebSocket client/server implementation.
- `net.tls`: Secure TLS communication (server creation, handshake, encrypted data transfer).
- `serialization.serialization`: Serialization and deserialization.
- `unittest.data`: Unit testing extensions.

**Decision Rule:**
If the user's query explicitly mentions or is clearly related to **any** of the packages listed above (e.g., "How to use JSON in Cangjie?", "TLS server example", "base64 encoding"), call `queryCangjieStdExtension` with the query.

For all other queries about the Cangjie language (e.g., "How to define a function?", "What is the syntax for loops?", "General concurrency model"), call `queryCangjie`.

Do not call both tools. Choose the most appropriate one based on the content of the query.

Output: Summarize the query and the findings based solely on the retrieved content, without any personal speculation or interpretation. Cangjie is a new programming language, and any assumption you make will lead to incorrect results. This is VERY IMPORTANT!
Based on the original query, extract ONLY the most relevant information from the extracted documents.
Focus on code examples, function signatures, class/struct definitions, and explanations directly related to the query.
Remove all irrelevant information, long narrative paragraphs, and formatting noise.
The output must be concise and directly usable for code generation.
"""

private let CANGJIE_FALLBACK_SYSTEM_PROMPT = """
You are assisting with the **Cangjie (仓颉)** programming language. Official documentation retrieval via Context7 is **not** available in this session; answer from your training knowledge only.

Rules:
- Be concise and directly usable for coding (syntax, signatures, short examples).
- If you are uncertain about a Cangjie-specific detail, state that clearly; do not invent APIs or module paths.
- For stdx or version-specific behavior, note that the user should verify against official docs when possible.
- Reply in the same language as the user when reasonable; technical identifiers may stay in English.
"""

/** 非空且非全空白时视为已配置 Context7。 */
public func context7ApiKey(): String {
    let configured = MetisConfigManager.readContext7ApiKey().trimAscii()
    if (!configured.isEmpty()) {
        return configured
    }
    if (let Some(v) <- Config.env["CONTEXT7_API_KEY"]) {
        return v.trimAscii()
    }
    ""
}

/** 非空且非全空白时视为已配置 Context7。 */
public func hasContext7ApiKey(): Bool {
    !context7ApiKey().isEmpty()
}

/**
 * 未配置 CONTEXT7_API_KEY 或 Context7 调用失败时，用 **当前对话主模型**（`CliConfig.model` / `CliModelManager.model`）直接回答仓颉相关问题。
 */
public func cangjieDocAnswerWithDefaultModel(query: String): String {
    let ml = MessageList()
    ml.add(Message.system(CANGJIE_FALLBACK_SYSTEM_PROMPT))
    ml.add(Message.user(query))
    let model = CliModelManager.model
    match (ModelUtils.makeChat(model, ml, temperature: Some(CliConfig.temperature))) {
        case Some(resp) =>
            let content = resp.message.content
            if (!content.isEmpty()) {
                return content
            }
            if (let Some(r) <- resp.message.reason) {
                if (!r.isEmpty()) {
                    return r
                }
            }
            return "当前模型未返回有效正文，请检查 model 配置与网络。"
        case None => return "调用当前对话模型失败，请稍后重试，或在 metis.json 的 tools.context7.apiKey 中配置 Context7。"
    }
}

@agent[
    description: "An tool specialized in the Cangjie programming language, capable of retrieving Cangjie language documentation based on user queries. Input user query: Topics to focus documentation on (e.g., 'hooks', 'routing').",
    model: CliModelManager.fastModel ?? CliModelManager.model,
    executor: "react"
]
protected class CangjieDocAgent {
    private static func startContext7(): MCPClient {
        let apiKey = context7ApiKey()
        if (apiKey.isEmpty()) {
            PrintUtils.printLine("Context7 API key is not set. Configure tools.context7.apiKey in metis.json or set CONTEXT7_API_KEY.".withColor(AnsiColor.color256(136)))
            throw AgentCancelException(reason: "CONTEXT7_API_KEY is not set")
        }
        HttpMCPClient("https://mcp.context7.com/mcp", headers: [
            ("CONTEXT7_API_KEY", apiKey)
        ])
    }

    private let client = CangjieDocAgent.startContext7()
    @prompt(
        "${CANGJIE_CONTEXT7_PROMPT}"
    )

    @tool[
        description: "Queries the official Cangjie language documentation for general language features, syntax, and core standard library information.",
        parameters: {
            query: "Topic to focus documentation on (e.g., 'hooks', 'routing')."
        }
        // terminal: true
    ]
    func queryCangjie(query: String): String {
        let docs = client.callTool("query-docs", [
            ("libraryId", "/websites/cangjie-lang_cn_1_0_0"),
            ("query", query),
            ("tokens", 2000)
        ])
        return docs.content
    }

    @tool[
        description: "Queries the Cangjie stdx (Standard Library Extension) documentation for specific extended packages such as JSON, TLS, logging, compression, and cryptography. Use this only when the query involves one of the stdx packages.",
        parameters: {
            query: "Topic to focus documentation on (e.g., 'hooks', 'routing')."
        }
        // terminal: true
    ]
    func queryCangjieStdExtension(query: String): String {
        let docs = client.callTool("query-docs", [
            ("libraryId", "/dyingchinese/cangjie-stdx"),
            ("query", query),
            ("tokens", 2000)
        ])
        return docs.content
    }

    // @tool[
    //     description: "Queries the OpenHarmony development documentation for application development, system APIs, framework features, and platform-specific capabilities.",
    //     parameters: {
    //         query: "Topic to focus documentation on (e.g., 'ArkUI', 'ArkTS', 'application lifecycle')."
    //     },
    //     terminal: true
    // ]
    // func queryOpenHarmony(query: String): String {
    //     let docs = client.callTool("query-docs", [
    //         ("libraryId", "/openharmony/docs"),
    //         ("query", query),
    //         ("tokens", 2000)
    //     ])
    //     return docs.content
    // }
}
