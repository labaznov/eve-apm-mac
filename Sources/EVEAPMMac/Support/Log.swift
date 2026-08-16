import OSLog

/// The app's single logging entry point, so diagnostics land in Console under
/// one subsystem instead of scattered print statements.
enum Log {
    private static let logger = Logger(subsystem: "com.github.labaznov.eveapmmac", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
