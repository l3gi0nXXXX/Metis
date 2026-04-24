package metis.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*
import magic.jsonable.*
import magic.log.LogUtils
import magic.utils.http.HttpUtils

import metis.core.config.MetisConfigManager
import metis.io.PrintUtils

import std.env.getVariable
import std.collection.*
import stdx.encoding.json.*

@toolset
public class SearchToolset {
    public init() {}

    @tool[
        description: "Use Tavily for web search to get the latest online information. Returns 5 results by default, includes AI summary answers, with basic search depth",
        parameters: {
            query: "Search query string"
        }
    ]
    public func search(query: String): String {
        PrintUtils.printTool("Tavily Search", shortMessage: query)
        let tool = TavilyTool()
        return tool.search(query)
    }
}

private struct TavilySearchResult {
    public let title: String
    public let url: String
    public let content: String
    public let score: Float64

    public TavilySearchResult(title: String, url: String, content: String, score: Float64) {
        this.title = title
        this.url = url
        this.content = content
        this.score = score
    }
}

private struct TavilySearchResponse {
    public let query: String
    public let answer: Option<String>
    public let results: Array<TavilySearchResult>
    public let responseTime: Float64

    public TavilySearchResponse(query: String, answer: Option<String>, results: Array<TavilySearchResult>, responseTime: Float64) {
        this.query = query
        this.answer = answer
        this.results = results
        this.responseTime = responseTime
    }
}

class TavilyTool {
    private let apiKey: String

    public TavilyTool() {
        let configured = MetisConfigManager.readTavilyApiKey().trimAscii()
        this.apiKey = if (!configured.isEmpty()) {
            configured
        } else {
            getVariable("TAVILY_API_KEY") ?? ""
        }
        if (this.apiKey.isEmpty()) {
            throw Exception("Tavily API key is not set (tools.search.tavily.apiKey / TAVILY_API_KEY)")
        }
    }

    public func search(query: String): String {
        if (query.trimAscii().isEmpty()) {
            return "Search query cannot be empty"
        }

        let maxResults: Int64 = 5
        let includeAnswer: Bool = true
        let searchDepth = "basic"

        try {
            let response = performSearch(query, maxResults, includeAnswer, searchDepth)
            return formatSearchResponse(response)
        } catch (e: Exception) {
            LogUtils.error("Tavily search failed: ${e.message}")
            return "Search failed: ${e.message}"
        }
    }

    private func performSearch(
        query: String,
        maxResults: Int64,
        includeAnswer: Bool,
        searchDepth: String
    ): TavilySearchResponse {
        let url = "https://api.tavily.com/search"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json"),
            ("Authorization", "Bearer ${this.apiKey}")
        ])

        let requestMap = HashMap<String, JsonValue>()
        requestMap.add("query", JsonString(query))
        requestMap.add("max_results", maxResults.toJsonValue())
        requestMap.add("include_answer", includeAnswer.toJsonValue())
        requestMap.add("search_depth", JsonString(searchDepth))
        requestMap.add("include_raw_content", false.toJsonValue())

        let requestBody = JsonObject(requestMap)

        let rawResponseOpt = HttpUtils.post(url, header, requestBody)
        let rawResponse = match (rawResponseOpt) {
            case Some(resp) => resp
            case None => throw Exception("No response received from server")
        }

        // Parse response
        let responseData: JsonValue
        try {
            responseData = JsonValue.fromStr(rawResponse)
        } catch (e: Exception) {
            throw Exception("JSON parsing failed: ${e.message}")
        }

        return parseSearchResponse(responseData)
    }

    private func parseSearchResponse(responseData: JsonValue): TavilySearchResponse {
        match (responseData) {
            case jsonObj: JsonObject =>
                let query = extractString(jsonObj, "query") ?? ""
                let answer = extractOptionalString(jsonObj, "answer")
                let responseTime = extractFloat(jsonObj, "response_time") ?? 0.0

                let results = ArrayList<TavilySearchResult>()
                if (let Some(resultsValue) <- jsonObj.get("results")) {
                    let resultsArray = resultsValue as JsonArray
                    if (let Some(arrayData) <- resultsArray) {
                        for (i in 0..arrayData.size()) {
                            let resultValue = arrayData[i]
                            let resultObj = resultValue as JsonObject
                            if (let Some(objData) <- resultObj) {
                                let title = extractString(objData, "title") ?? ""
                                let url = extractString(objData, "url") ?? ""
                                let content = extractString(objData, "content") ?? ""
                                let score = extractFloat(objData, "score") ?? 0.0

                                results.add(TavilySearchResult(title, url, content, score))
                            }
                        }
                    }
                }

                return TavilySearchResponse(query, answer, results.toArray(), responseTime)
            case _ => throw Exception("Invalid response format")
        }
    }

    private func extractString(obj: JsonObject, key: String): Option<String> {
        if (let Some(value) <- obj.get(key)) {
            let jsonStr = value as JsonString
            if (let Some(strValue) <- jsonStr) {
                return Some(strValue.getValue())
            }
        }
        return None
    }

    private func extractOptionalString(obj: JsonObject, key: String): Option<String> {
        if (let Some(value) <- obj.get(key)) {
            match (value) {
                case jsonStr: JsonString => Some(jsonStr.getValue())
                case _: JsonNull => None
                case _ => None
            }
        } else {
            None
        }
    }

    private func extractFloat(obj: JsonObject, key: String): Option<Float64> {
        if (let Some(value) <- obj.get(key)) {
            match (value) {
                case jsonNum: JsonInt => Some(Float64(jsonNum.getValue()))
                case jsonNum: JsonFloat => Some(jsonNum.getValue())
                case _ => None
            }
        } else {
            None
        }
    }

    private func formatSearchResponse(response: TavilySearchResponse): String {
        let results = ArrayList<String>()
        results.add("=== Tavily Search Results ===\n")
        results.add("Query: ${response.query}\n")
        results.add("Response time: ${response.responseTime}s\n\n")

        // Show AI-generated answer first if available
        if (let Some(answer) <- response.answer) {
            results.add("[AI Summary Answer]\n")
            results.add("${answer}\n\n")
        }

        // Display search results
        results.add("[Search Results]\n")
        for (i in 0..response.results.size) {
            let searchResult = response.results[i]
            results.add("${i + 1}. ${searchResult.title}\n")
            results.add("   URL: ${searchResult.url}\n")
            results.add("   Relevance: ${searchResult.score}\n")
            results.add("   Content: ${searchResult.content}\n\n")
        }

        return String.join(results.toArray(), delimiter: "")
    }
}
