package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.{CliSettingManager, skillEntryEnabled}
import metis.utils.fetchWttrWeatherPlain

/** 与 settings / skill 中引用的工具名一致，供 deny/allow 配置。 */
public let GATEWAY_TOOL_WEATHER = "weather"

/**
 * 网关 P1 天气工具：实现与 CLI `WeatherToolset` 相同，额外应用 `gateway.tools` 策略。
 */
@toolset
public class GatewayWeatherToolset {
    @tool[
        description:
            "Fetch current weather text from wttr.in (no API key). Use when the user asks about weather, temperature, or forecast for a place. Pass location in English or Latin letters (e.g. Beijing, London, Paris). For empty location, uses IP-based approximate location. Returns plain text; summarize for the user in Chinese if they asked in Chinese.",
        parameters: {
            location:
                "City or region name (ASCII/English recommended, e.g. Shanghai). Leave empty to use wttr.in default (IP-based)."
        }
    ]
    public func weather(location: String): String {
        if (!skillEntryEnabled(CliSettingManager.setting.skills, GATEWAY_TOOL_WEATHER)) {
            return "根据 metis.json 配置，weather 功能已被禁用（meta.metis.legacySettings.skills.entries.weather.enabled=false）。本次不执行天气查询。"
        }
        if (!isGatewayToolAllowed(GATEWAY_TOOL_WEATHER)) {
            return "工具 weather 已被 gateway.tools 策略禁用。"
        }
        fetchWttrWeatherPlain(location)
    }
}
