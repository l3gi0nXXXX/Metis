package metis.telemetry.otel

import std.collection.*

public class LoggerProvider {
    let name: String
    let version: String
    let loggers: HashMap<String, Logger>
    let logExporters: ArrayList<LogExporter>
    let resourceAttributes: HashMap<String, AttributeValue>
    var isShutdown: Bool = false

    public init(name: String, version!: String = "1.0.0", logExporters!: ArrayList<LogExporter> = ArrayList<LogExporter>()) {
        this.name = name
        this.version = version
        this.loggers = HashMap<String, Logger>()
        this.logExporters = ArrayList<LogExporter>()
        this.logExporters.add(all: logExporters)
        this.resourceAttributes = HashMap<String, AttributeValue>()
        updateLogExporterResources()
    }

    public func createLogger(name: String, version: String): Logger {
        if (isShutdown) {
            return Logger(name, version: version)
        }

        let key = "${name}-${version}"
        match (loggers.get(key)) {
            case Some(logger) => return logger
            case None =>
                let logger = Logger(name, version: version)
                loggers[key] = logger
                return logger
        }
    }

    public func shutdown(): Unit {
        isShutdown = true
        let logRecords = collectLogRecords()
        for (exporter in logExporters) {
            exporter.export(logRecords)
            exporter.shutdown()
        }
    }

    public func setResourceAttribute(key: String, value: AttributeValue): Unit {
        resourceAttributes[key] = value
        updateLogExporterResources()
    }

    public func getResourceAttributes(): HashMap<String, AttributeValue> {
        return resourceAttributes
    }

    public func getLogExporters(): ArrayList<LogExporter> {
        let copy = ArrayList<LogExporter>()
        copy.add(all: logExporters)
        return copy
    }

    public func registerLogExporter(exporter: LogExporter): Unit {
        logExporters.add(exporter)
        exporter.updateResourceAttributes(resourceAttributes)
    }

    private func collectLogRecords(): ArrayList<LogRecord> {
        let logRecords = ArrayList<LogRecord>()
        for ((_, logger) in loggers) {
            let records = logger.collectLogRecords()
            logRecords.add(all: records)
        }
        return logRecords
    }

    private func updateLogExporterResources(): Unit {
        for (exporter in logExporters) {
            exporter.updateResourceAttributes(resourceAttributes)
        }
    }
}
