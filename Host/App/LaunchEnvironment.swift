import Foundation

/// How the app was launched: under XCTest, or with debug overrides on the command line.
enum LaunchEnvironment {
    /// True while the app is only hosting the unit tests: then it opens no windows and leaves
    /// the user's saved session alone.
    static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// `-HomePage <url>`: open this instead of the home page and the saved session.
    /// Debug builds only (used for screenshots, see DebugSnapshot); always nil in release builds.
    static var homePageOverride: URL? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HomePage").flatMap(URL.init(string:))
        #else
        nil
        #endif
    }
}
