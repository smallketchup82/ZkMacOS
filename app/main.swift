import AppKit
import Foundation
import Darwin

// The engine owns the game window and Dock entry. This bootstrap stays hidden.
// LSUIElement in Info.plist keeps this command-line bootstrap out of the Dock.
umask(0o077)
let files = FileManager.default
let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
let resources = contents.appendingPathComponent("Resources")
let engine = contents.appendingPathComponent("MacOS/spring")
let client = resources.appendingPathComponent("client")
let data = ProcessInfo.processInfo.environment["ZKMACOS_DATA_DIR"].map { URL(fileURLWithPath: $0) }
    ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zero-K")

do {
    try files.createDirectory(at: data, withIntermediateDirectories: true)
    let defaults = resources.appendingPathComponent("defaults")
    if let entries = files.enumerator(at: defaults, includingPropertiesForKeys: [.isRegularFileKey]) {
        for case let file as URL in entries {
            if try !file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile! { continue }
            let relative = String(file.path.dropFirst(defaults.path.count + 1))
            let destination = data.appendingPathComponent(relative)
            if files.fileExists(atPath: destination.path) { continue }
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: file, to: destination)
        }
    }
    let logs = data.appendingPathComponent("log")
    try files.createDirectory(at: logs, withIntermediateDirectories: true)
    var environment = ProcessInfo.processInfo.environment
    environment["ZEROK_DATA_DIR"] = data.path
    environment["ZEROK_RESOURCE_DIR"] = resources.appendingPathComponent("data").path
    environment["ZEROK_ENGINE_PATH"] = engine.path
    environment["ZEROK_CHOBBY_NAME"] = "Chobby macos-source"
    environment["SPRING_DATADIR"] = data.path + ":" + resources.appendingPathComponent("data").path
    environment["SPRING_WRITEDIR"] = data.path
    environment["SPRING_ISOLATED"] = data.path
    environment["FONTCONFIG_FILE"] = resources.appendingPathComponent("fontconfig.conf").path
    environment["XDG_CACHE_HOME"] = data.appendingPathComponent("cache").path
    environment["SteamAppId"] = "334920"
    environment["SteamGameId"] = "334920"

    var arguments = Array(CommandLine.arguments.dropFirst())
    let engineOnly = arguments.first == "--engine"
    if engineOnly { arguments.removeFirst() }
    let helper = client.appendingPathComponent("Zero-K-Helper")
    let process = Process()
    process.currentDirectoryURL = data
    process.environment = environment
    let logFile = logs.appendingPathComponent(engineOnly ? "engine-launch.log" : "launcher.log")
    files.createFile(atPath: logFile.path, contents: nil)
    let output = try FileHandle(forWritingTo: logFile)
    process.standardOutput = output
    process.standardError = output
    process.executableURL = engineOnly ? engine : helper
    process.arguments = engineOnly
        ? ["--isolation-dir", data.path, "--write-dir", data.path, "--config", data.appendingPathComponent("springsettings.cfg").path] + arguments
        : []

    do {
        try process.run()
    } catch where !engineOnly {
        // Preserve ordinary account/offline login if the optional helper fails.
        try output.write(contentsOf: Data("Steam helper unavailable; using native account/offline lobby.\n".utf8))
        process.executableURL = engine
        process.arguments = ["--isolation-dir", data.path, "--write-dir", data.path, "--config", data.appendingPathComponent("springsettings.cfg").path, "--menu", "Chobby macos-source"]
        try process.run()
    }
    process.waitUntilExit()
    try output.close()
    exit(process.terminationStatus)
} catch {
    let alert = NSAlert()
    alert.messageText = "Zero-K could not start"
    alert.informativeText = error.localizedDescription
    alert.runModal()
    exit(1)
}
