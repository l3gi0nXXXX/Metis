package metis.gateway.runtime

public func gatewayDashboardMethodAlias(method: String): String {
    match (method.trimAscii().toAsciiLower()) {
        case "health" => "dashboard.status"
        case "health.get" => "dashboard.status"
        case "chat.history" => "dashboard.chat.history"
        case "chat.send" => "dashboard.chat.send"
        case "models" => "dashboard.models"
        case "models.list" => "dashboard.models"
        case "skills" => "skills.status"
        case "skills.list" => "skills.status"
        case "skills.compatibility" => "skills.compatibilityMatrix"
        case _ => ""
    }
}
