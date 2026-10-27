import AppKit
import Foundation

struct UpdateChecks {
    static func run() {
        let bundle = URL(fileURLWithPath: "/Applications/Zero-K.app")
        for command in ["/Applications/Zero-K.app/Contents/MacOS/spring",
                        "/Applications/Zero-K.app/Contents/Resources/client/Zero-K-Helper"] {
            precondition(bundledGameIsRunning(commands: "  " + command + "\n", bundle: bundle))
        }
        for command in ["/Applications/Zero-K.app/Contents/MacOS/Zero-K",
                        "/Applications/Zero-K.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
                        "/Applications/Other.app/Contents/MacOS/spring",
                        "/Applications/Zero-K.app/Contents/MacOS/spring-other", ""] {
            precondition(!bundledGameIsRunning(commands: command, bundle: bundle))
        }
        let moved = URL(fileURLWithPath: "/tmp/Renamed Game.app")
        precondition(bundledGameIsRunning(
            commands: "/tmp/Renamed Game.app/Contents/MacOS/spring\n", bundle: moved))

        let delegate = LauncherDelegate()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        delegate.process = process
        try! process.run()
        precondition(delegate.gameIsRunning())
        precondition(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        var installs = 0
        delegate.pendingInstall = { installs += 1 }
        delegate.finishWhenGameExits()
        precondition(installs == 0, "An update must not install while a child is running")
        process.terminate()
        process.waitUntilExit()
        precondition(!delegate.gameIsRunning())
        delegate.finishWhenGameExits()
        precondition(installs == 1 && delegate.pendingInstall == nil)
        precondition(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        print("Update process discovery and deferred installation checks passed")
    }
}
