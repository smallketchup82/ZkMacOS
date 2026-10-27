import AppKit
import Foundation
import Darwin

func versionNumbers(_ version: String) -> [Int]? {
    let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var numbers: [Int] = []
    for part in parts {
        guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let number = Int(part) else { return nil }
        numbers.append(number)
    }
    return numbers
}

func availableUpdate(_ data: Data, currentVersion: String) -> String? {
    struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }
    guard let release = try? JSONDecoder().decode(Release.self, from: data),
          !release.draft, !release.prerelease,
          let current = versionNumbers(currentVersion),
          let latest = versionNumbers(release.tag_name),
          current.lexicographicallyPrecedes(latest) else { return nil }
    return release.tag_name
}

func checkForUpdates() {
    guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
    let endpoint = URL(string: "https://api.github.com/repos/smallketchup82/ZkMacOS/releases/latest")!
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("ZkMacOS/" + currentVersion, forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, response, error in
        guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
              let data, let latest = availableUpdate(data, currentVersion: currentVersion) else { return }
        DispatchQueue.main.async {
            let releases = URL(string: "https://github.com/smallketchup82/ZkMacOS/releases/latest")!
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "A ZkMacOS update is available"
            alert.informativeText = "ZkMacOS \(latest) is available. You have \(currentVersion).\n\nQuit Zero-K before updating. Update through your package manager, or download the latest version from GitHub Releases.\n\nHomebrew:\nbrew update\nbrew upgrade --cask smallketchup82/zkmacos/zkmacos\n\n\(releases.absoluteString)"
            alert.addButton(withTitle: "Open GitHub Releases")
            alert.addButton(withTitle: "Later")
            NSApplication.shared.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releases)
            }
        }
    }.resume()
}

func showStartupWarning(in data: URL) throws {
    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
    let acknowledgments = data.appendingPathComponent("startup-warning-versions.json")
    var versions = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: acknowledgments))) ?? []
    if versions.contains(version) { return }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "⚠️ READ BEFORE PLAYING ⚠️"
    alert.informativeText = """
    ZkMacOS is unstable and experimental. Please heed the following warnings:

    1. DO NOT report ZkMacOS bugs to the official Zero-K developers. Use this project's GitHub issues instead.

    2. ZkMacOS is a third-party client, not endorsed or officially supported by the Zero-K developers.

    3. This experimental port is not thoroughly tested. Expect bugs and crashes. Play ranked at your own risk: you accept responsibility for any resulting loss or Elo change.
    """
    let link = NSTextField(labelWithAttributedString: NSAttributedString(
        string: "Report ZkMacOS issues on GitHub",
        attributes: [.link: URL(string: "https://github.com/smallketchup82/ZkMacOS/issues")!]
    ))
    link.isSelectable = true
    link.allowsEditingTextAttributes = true
    link.sizeToFit()
    alert.accessoryView = link
    alert.addButton(withTitle: "I Understand")
    NSApplication.shared.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { exit(0) }

    versions.append(version)
    try JSONEncoder().encode(versions).write(to: acknowledgments, options: .atomic)
}

#if UPDATE_CHECK_TESTS
UpdateChecks.run()
#else
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
    if !engineOnly { try showStartupWarning(in: data) }
    let helper = client.appendingPathComponent("Zero-K-Helper")
    let process = Process()
    process.terminationHandler = { finished in
        DispatchQueue.main.async { exit(finished.terminationStatus) }
    }
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
    if !engineOnly { checkForUpdates() }
    // Keep the main thread available for update dialogs and child termination.
    RunLoop.main.run()
} catch {
    let alert = NSAlert()
    alert.messageText = "Zero-K could not start"
    alert.informativeText = error.localizedDescription
    alert.runModal()
    exit(1)
}
#endif
