package metis.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.{CliSettingManager, skillEntryEnabled}
import metis.utils.fetchWttrWeatherPlain

private const WEATHER_SKILL_NAME = "weather"

@toolset
public class WeatherToolset {
    @tool[
        description:
            "Fetch current weather as plain text from wttr.in (no API key, no curl). Use when the user asks for weather, temperature, or forecast. Prefer this over running curl in the shell. Pass location in English when possible (e.g. Nanjing, Beijing). Empty location uses IP-based default on wttr.in.",
        parameters: {
            location:
                "City or region (English recommended, e.g. Nanjing). Leave empty for IP-based location."
        }
    ]
    public func weather(location: String): String {
        if (!skillEntryEnabled(CliSettingManager.setting.skills, WEATHER_SKILL_NAME)) {
            return "根据 metis.json 配置，weather 功能已被禁用（meta.metis.legacySettings.skills.entries.weather.enabled=false）。本次不执行天气查询。"
        }
        fetchWttrWeatherPlain(location)
    }
}
