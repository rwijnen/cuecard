import Foundation
import OSLog

/// One subsystem, a few categories. `log stream --predicate 'subsystem == "com.robinwijnen.Cuecard"'`
/// is the fastest way to watch what the app is deciding.
enum Log {
    static let app = Logger(subsystem: subsystem, category: "app")
    static let spotify = Logger(subsystem: subsystem, category: "spotify")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let present = Logger(subsystem: subsystem, category: "present")

    private static let subsystem = "com.robinwijnen.Cuecard"
}
