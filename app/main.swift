import AppKit
import Foundation
import Darwin
import Sparkle

// The engine owns the Dock entry. This delegate keeps the hidden bootstrap alive
// until all bundled game processes exit, including an engine orphaned by a helper.
final class LauncherDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let updateRequestID = UUID().uuidString
    var updatesEnabled = true
    var process: Process?
    var childStatus: Int32 = 0
    var pendingInstall: (() -> Void)?
    var exitTimer: Timer?
    var reporting: CrashReporting?
    var reportTimer: Timer?
    var reportTicks = 0
    var finishingReports = false
    var crashReportReadyAfter: Date?
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func gameIsRunning() -> Bool {
        if process?.isRunning == true { return true }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/ps")
        probe.arguments = ["-ww", "-axo", "comm="]
        let pipe = Pipe()
        probe.standardOutput = pipe
        do {
            try probe.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            guard probe.terminationStatus == 0,
                  let commands = String(data: output, encoding: .utf8) else { return true }
            return bundledGameIsRunning(commands: commands, bundle: Bundle.main.bundleURL)
        } catch {
            return true // Never replace the app if process discovery failed.
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reporting?.scan(allowPrompt: true)
        reportTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            reporting?.pollManualRequest()
            reportTicks += 1
            if reportTicks % 30 == 0 { reporting?.scan() }
        }
        guard updatesEnabled, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(checkForUpdatesFromGame(_:)),
            name: Notification.Name("org.zerok.macos.checkForUpdates"), object: updateRequestID)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(toggleAutomaticChecks(_:)),
            name: Notification.Name("org.zerok.macos.toggleAutomaticChecks"), object: updateRequestID)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(publishAutomaticChecks(_:)),
            name: Notification.Name("org.zerok.macos.requestAutomaticChecks"), object: updateRequestID)
        updaterController.startUpdater()
        publishAutomaticChecks()
    }

    @objc func checkForUpdatesFromGame(_ notification: Notification) {
        updaterController.checkForUpdates(nil)
    }

    @objc func toggleAutomaticChecks(_ notification: Notification) {
        updaterController.updater.automaticallyChecksForUpdates.toggle()
        publishAutomaticChecks()
    }

    @objc func publishAutomaticChecks(_ notification: Notification? = nil) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("org.zerok.macos.automaticChecksChanged"), object: updateRequestID,
            userInfo: ["enabled": updaterController.updater.automaticallyChecksForUpdates],
            deliverImmediately: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if gameIsRunning() {
            // Sparkle also requests normal application termination before installation.
            // Refuse it while the game runs; never kill a match to apply an update.
            return .terminateCancel
        }
        return .terminateNow
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard gameIsRunning() else { return false }
        pendingInstall = installHandler
        let alert = NSAlert()
        alert.messageText = "Update ready to install"
        alert.informativeText = "Quit Zero-K normally when you have finished playing. The update will then install and Zero-K will reopen."
        alert.addButton(withTitle: "Continue Playing")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
        return true
    }

    func childDidExit(_ status: Int32) {
        childStatus = status
        if status != 0 { crashReportReadyAfter = Date().addingTimeInterval(3) }
        finishWhenGameExits()
        // A helper can exit before its engine. Wait for both before letting
        // Sparkle's installer observe bootstrap termination.
        if gameIsRunning() || crashReportReadyAfter != nil {
            exitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.finishWhenGameExits()
            }
        }
    }

    func finishWhenGameExits() {
        guard !gameIsRunning() else { return }
        if let ready = crashReportReadyAfter, Date() < ready { return }
        guard !finishingReports else { return }
        finishingReports = true
        exitTimer?.invalidate()
        exitTimer = nil
        reportTimer?.invalidate()
        if let reporting {
            reporting.scan(allowPrompt: true) { [self] in finishTermination() }
        } else {
            finishTermination()
        }
    }

    func finishTermination() {
        guard !gameIsRunning() else {
            finishingReports = false
            exitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.finishWhenGameExits()
            }
            return
        }
        if let install = pendingInstall {
            pendingInstall = nil
            install()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
}

func bundledGameIsRunning(commands: String, bundle: URL) -> Bool {
    let contents = bundle.resolvingSymlinksInPath().appendingPathComponent("Contents").path
    return commands.split(separator: "\n").contains { line in
        let command = line.trimmingCharacters(in: .whitespaces)
        return command == contents + "/MacOS/spring"
            || command.hasPrefix(contents + "/Resources/client/")
    }
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

#if CRASH_REPORT_TESTS
CrashReportChecks.run()
#elseif UPDATE_CHECK_TESTS
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
let reporting = CrashReporting(data: data)

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
    let delegate = LauncherDelegate()
    delegate.reporting = reporting
    if !engineOnly, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
        environment["ZEROK_UPDATE_REQUEST_ID"] = delegate.updateRequestID
        environment["ZEROK_AUTOMATIC_UPDATE_CHECKS"] = delegate.updaterController.updater.automaticallyChecksForUpdates ? "1" : "0"
    }
    let process = Process()
    delegate.process = process
    process.terminationHandler = { finished in
        DispatchQueue.main.async { delegate.childDidExit(finished.terminationStatus) }
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
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    // Direct --engine invocations retain the same safe quit handling but don't
    // start a second updater alongside the ordinary launcher.
    application.delegate = delegate
    delegate.updatesEnabled = !engineOnly
    withExtendedLifetime(delegate) { application.run() }
    exit(delegate.childStatus)
} catch {
    let alert = NSAlert()
    alert.messageText = "Zero-K could not start"
    alert.informativeText = error.localizedDescription
    alert.runModal()
    exit(1)
}
#endif
